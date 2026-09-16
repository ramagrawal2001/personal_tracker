import { z } from "zod";
import { AuthError } from "../auth/supabase-auth";
import {
  computeAccountBalance, computeAllBalances, computeBudgetSpent, computePersonBalance, resolveSplitShares,
  type BalanceTxn, type PayableRow, type ReceivableRow, type SpentTxn, type SplitMode,
} from "../data/derive";
import { ENTITIES, ENTITY_NAMES, SPLIT_MODES, type EntityDef, type EntityName } from "../data/entities";
import type { SupabaseRest } from "../data/supabase-rest";

export interface ToolResult {
  content: { type: "text"; text: string }[];
  isError?: boolean;
}

export interface McpServerLike {
  tool(
    name: string,
    description: string,
    paramsShape: Record<string, unknown>,
    handler: (args: any) => Promise<ToolResult>,
  ): void;
}

export interface ToolDeps {
  rest: SupabaseRest;
  identity: () => { email: string; supabaseUserId: string; connectedAt: string };
}

const SESSION_EXPIRED_MSG =
  "Your PersonalTracker session has expired. Reconnect the connector in Claude settings.";

function ok(data: unknown): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
function fail(message: string): ToolResult {
  return { content: [{ type: "text", text: message }], isError: true };
}
function toToolError(e: unknown): ToolResult {
  if (e instanceof AuthError) return fail(SESSION_EXPIRED_MSG);
  return fail(e instanceof Error ? e.message : String(e));
}
function stripOmitted(entity: EntityName, row: Record<string, unknown>): Record<string, unknown> {
  const out = { ...row };
  for (const f of ENTITIES[entity].omitFields) delete out[f];
  return out;
}
function zodMsg(entity: EntityName, err: z.ZodError): string {
  const i = err.issues[0];
  const path = i.path.join(".") || "(root)";
  return `Invalid ${ENTITIES[entity].displayName} data: ${path} — ${i.message}`;
}

async function attachBalances(
  rest: SupabaseRest,
  accounts: Record<string, any>[],
): Promise<Record<string, any>[]> {
  if (accounts.length === 0) return accounts;
  const [txns, cards] = await Promise.all([
    rest.list("transactions", { limit: 500 }),
    rest.list("credit_cards", { limit: 500 }),
  ]);
  const creditIds = new Set<string>(
    (cards as any[]).filter((c) => c.card_type === "credit").map((c) => c.id),
  );
  const balTxns = txns as BalanceTxn[];
  return accounts.map((a) => ({
    ...a,
    calculated_balance_synced: a.calculated_balance,
    calculated_balance: computeAccountBalance(
      { id: a.id, opening_balance: a.opening_balance ?? 0 },
      balTxns,
      creditIds,
    ),
  }));
}

async function attachBudgetSpent(
  rest: SupabaseRest,
  budgets: Record<string, any>[],
): Promise<Record<string, any>[]> {
  if (budgets.length === 0) return budgets;
  const txns = (await rest.list("transactions", { limit: 500 })) as SpentTxn[];
  return budgets.map((b) => ({
    ...b,
    spent_amount_synced: b.spent_amount,
    spent_amount: computeBudgetSpent(
      { category_id: b.category_id, month_year: b.month_year },
      txns,
    ),
  }));
}

type Ref = { ok: string } | { error: string };

function resolveRef(
  kind: "account" | "category" | "credit card" | "person",
  needle: string,
  rows: { id: string; name: string }[],
): Ref {
  const byId = rows.find((r) => r.id === needle);
  if (byId) return { ok: byId.id };
  const hits = rows.filter((r) => (r.name ?? "").toLowerCase() === needle.toLowerCase());
  if (hits.length === 1) return { ok: hits[0].id };
  if (hits.length === 0) {
    const names = rows.map((r) => r.name).filter(Boolean).slice(0, 10).join(", ");
    return { error: `No ${kind} named "${needle}". Available: ${names || "(none)"}.` };
  }
  return { error: `Multiple ${kind}s named "${needle}" — use its id instead.` };
}

/**
 * Guards the one invariant a generic Zod schema can't express: the sum of a
 * split's participant shares must never exceed its total_amount (which would
 * imply a negative payer share). Only split_participants writes go through
 * this — the other entities have no cross-row sum to protect.
 */
async function checkSplitParticipantReconciles(
  rest: SupabaseRest,
  args: { splitExpenseId: string; shareAmount: number; excludeParticipantId?: string },
): Promise<string | null> {
  const split = (await rest.get("split_expenses", args.splitExpenseId)) as Record<string, any> | null;
  if (!split) return `No split expense with id "${args.splitExpenseId}".`;
  const siblings = (await rest.list("split_participants", {
    eq: { split_expense_id: args.splitExpenseId },
    limit: 500,
  })) as Record<string, any>[];
  const othersTotal = siblings
    .filter((p) => p.id !== args.excludeParticipantId)
    .reduce((sum, p) => sum + (p.share_amount ?? 0), 0);
  const impliedPayerShare = split.total_amount - othersTotal - args.shareAmount;
  if (impliedPayerShare < -0.01) {
    return (
      `This share doesn't reconcile: participants would owe ` +
      `₹${(othersTotal + args.shareAmount).toFixed(2)} of a ₹${split.total_amount.toFixed(2)} ` +
      `bill ("${split.title}") — that's more than the total. Reduce a share or raise the split's total_amount.`
    );
  }
  return null;
}

export function registerTools(server: McpServerLike, deps: ToolDeps): void {
  const { rest } = deps;

  server.tool(
    "whoami",
    "Show which PersonalTracker account this connector is signed in as.",
    {},
    async () => ok(deps.identity()),
  );

  server.tool(
    "list_records",
    `List records for one PersonalTracker entity (deleted rows excluded). Entities: ${ENTITY_NAMES.join(", ")}.`,
    {
      entity: z.enum(ENTITY_NAMES),
      filter: z
        .record(z.string(), z.string())
        .optional()
        .describe('Exact-match column filters, e.g. {"type":"expense"} or {"month_year":"2026-09"}.'),
      limit: z.number().int().min(1).max(500).optional(),
      with_account_balance: z
        .boolean()
        .optional()
        .describe("accounts only: attach a computed calculated_balance from live transactions."),
      with_budget_spent: z
        .boolean()
        .optional()
        .describe("budgets only: recompute spent_amount from this month's transactions."),
    },
    async ({ entity, filter, limit, with_account_balance, with_budget_spent }) => {
      try {
        const rows = (await rest.list(ENTITIES[entity as EntityName].table, {
          eq: filter,
          limit,
        })) as Record<string, any>[];
        let mapped = rows.map((r) => stripOmitted(entity as EntityName, r));
        if (entity === "accounts" && with_account_balance) mapped = await attachBalances(rest, mapped);
        if (entity === "budgets" && with_budget_spent) mapped = await attachBudgetSpent(rest, mapped);
        return ok(mapped);
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "get_record",
    "Fetch one PersonalTracker record by id.",
    { entity: z.enum(ENTITY_NAMES), id: z.string() },
    async ({ entity, id }) => {
      try {
        const row = (await rest.get(ENTITIES[entity as EntityName].table, id)) as
          | Record<string, any>
          | null;
        if (!row) return ok({ found: false });
        let mapped = stripOmitted(entity as EntityName, row);
        if (entity === "accounts") [mapped] = await attachBalances(rest, [mapped]);
        return ok(mapped);
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "create_record",
    "Create one PersonalTracker record. `data` fields depend on `entity`; on a validation error the message names the offending field.",
    { entity: z.enum(ENTITY_NAMES), data: z.record(z.string(), z.unknown()) },
    async ({ entity, data }) => {
      const name = entity as EntityName;
      const def: EntityDef = ENTITIES[name];
      const parsed = def.createSchema.safeParse(data);
      if (!parsed.success) return fail(zodMsg(name, parsed.error));
      const now = new Date().toISOString();
      const row: Record<string, unknown> = {
        id: crypto.randomUUID(),
        ...(def.fixed ?? {}),
        ...(parsed.data as Record<string, unknown>),
        created_at: now,
        updated_at: now,
      };
      if (name === "transactions" && !row.date) row.date = now;
      if (name === "split_participants") {
        const d = parsed.data as { split_expense_id: string; share_amount: number };
        const err = await checkSplitParticipantReconciles(rest, {
          splitExpenseId: d.split_expense_id,
          shareAmount: d.share_amount,
        });
        if (err) return fail(err);
      }
      try {
        const created = (await rest.insert(def.table, row)) as Record<string, unknown>;
        return ok(stripOmitted(name, created));
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "update_record",
    "Patch fields on one PersonalTracker record.",
    {
      entity: z.enum(ENTITY_NAMES),
      id: z.string(),
      changes: z.record(z.string(), z.unknown()),
    },
    async ({ entity, id, changes }) => {
      const name = entity as EntityName;
      const def: EntityDef = ENTITIES[name];
      const parsed = def.updateSchema.safeParse(changes);
      if (!parsed.success) return fail(zodMsg(name, parsed.error));
      // .partial() still injects .default() values for absent keys — forward
      // only the columns the caller actually supplied, so an update never
      // clobbers unrelated fields with schema defaults.
      const validated = parsed.data as Record<string, unknown>;
      const fields: Record<string, unknown> = {};
      for (const k of Object.keys(changes as Record<string, unknown>)) {
        if (k in validated) fields[k] = validated[k];
      }
      if (Object.keys(fields).length === 0) return fail("No valid fields to update.");
      if (name === "split_participants" && ("share_amount" in fields || "split_expense_id" in fields)) {
        const existing = (await rest.get("split_participants", id)) as Record<string, any> | null;
        if (existing) {
          const splitExpenseId = (fields.split_expense_id as string) ?? existing.split_expense_id;
          const shareAmount = (fields.share_amount as number) ?? existing.share_amount;
          const err = await checkSplitParticipantReconciles(rest, {
            splitExpenseId, shareAmount, excludeParticipantId: id,
          });
          if (err) return fail(err);
        }
      }
      try {
        const updated = (await rest.patch(def.table, id, {
          ...fields,
          updated_at: new Date().toISOString(),
        })) as Record<string, unknown> | null;
        if (!updated) return ok({ found: false });
        return ok(stripOmitted(name, updated));
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "delete_record",
    "Soft-delete one PersonalTracker record (recoverable in the app).",
    { entity: z.enum(ENTITY_NAMES), id: z.string() },
    async ({ entity, id }) => {
      try {
        const now = new Date().toISOString();
        const updated = await rest.patch(ENTITIES[entity as EntityName].table, id, {
          is_deleted: true,
          deleted_at: now,
          updated_at: now,
        });
        return ok({ deleted: updated != null, id });
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "add_transaction",
    "Add an income / expense / transfer, resolving account and category by name (or id).",
    {
      type: z.enum(["income", "expense", "transfer"]),
      amount: z.number().positive(),
      account: z.string().describe("Source account name or id."),
      category: z.string().optional().describe("Category name or id (ignored for transfers)."),
      to_account: z.string().optional().describe("Destination account name or id (transfer only)."),
      merchant: z.string().optional(),
      note: z.string().optional(),
      date: z.string().datetime({ offset: true }).optional(),
    },
    async (a) => {
      try {
        const accounts = (await rest.list("accounts", { limit: 500 })) as {
          id: string;
          name: string;
        }[];
        const src = resolveRef("account", a.account, accounts);
        if ("error" in src) return fail(src.error);

        let toAccountId: string | null = null;
        if (a.type === "transfer") {
          if (!a.to_account) return fail("A transfer needs `to_account`.");
          const dst = resolveRef("account", a.to_account, accounts);
          if ("error" in dst) return fail(dst.error);
          toAccountId = dst.ok;
        }

        let categoryId: string | null = null;
        if (a.category && a.type !== "transfer") {
          const cats = (await rest.list("categories", { limit: 500 })) as {
            id: string;
            name: string;
          }[];
          const cat = resolveRef("category", a.category, cats);
          if ("error" in cat) return fail(cat.error);
          categoryId = cat.ok;
        }

        const now = new Date().toISOString();
        const row = {
          id: crypto.randomUUID(),
          account_id: src.ok,
          to_account_id: toAccountId,
          type: a.type,
          amount: a.amount,
          category_id: categoryId,
          merchant: a.merchant ?? null,
          notes: a.note ?? null,
          date: a.date ?? now,
          is_external_to_account: false,
          tags: [],
          splits: [],
          sync_status: "synced",
          created_at: now,
          updated_at: now,
        };
        const created = await rest.insert("transactions", row);
        return ok(created);
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "add_split_expense",
    "Log a bill you paid in full and split with others (e.g. a group dinner). " +
      "The FULL amount debits your account/card — matching your real bank statement " +
      "— while each participant's share is tracked separately as money they owe you, " +
      "never counted against your balance a second time. Modes: equal (even split " +
      "among everyone including you), custom (exact amount per participant), ratio " +
      "(shares like 2:1:1), percentage (must sum to 100 with your own `payer_value`). " +
      "`payer_value` is required for ratio/percentage — your own ratio or percent.",
    {
      title: z.string().trim().min(1),
      total_amount: z.number().positive(),
      account: z.string().describe("Paying account name or id."),
      credit_card: z.string().optional().describe("Charge to this credit card instead of the account."),
      category: z.string().optional(),
      date: z.string().datetime({ offset: true }).optional(),
      mode: z.enum(SPLIT_MODES).default("equal"),
      participants: z
        .array(
          z.object({
            person: z.string().describe("Name or id — a new name is created automatically."),
            value: z
              .number()
              .optional()
              .describe("Exact amount (custom), ratio (ratio), or percent (percentage). Ignored for equal."),
            category: z
              .string()
              .optional()
              .describe("Override category for just this person's share — defaults to the bill's own category."),
            note: z.string().optional().describe("Note on just this person's share."),
          }),
        )
        .min(1),
      payer_value: z.number().optional().describe("Your own ratio/percent — required for ratio and percentage modes."),
    },
    async (a) => {
      try {
        if ((a.mode === "ratio" || a.mode === "percentage") && a.payer_value == null) {
          return fail(`\`payer_value\` is required for mode "${a.mode}".`);
        }

        const accounts = (await rest.list("accounts", { limit: 500 })) as { id: string; name: string }[];
        const acctRef = resolveRef("account", a.account, accounts);
        if ("error" in acctRef) return fail(acctRef.error);

        let creditCardId: string | null = null;
        if (a.credit_card) {
          const cards = (await rest.list("credit_cards", { limit: 500 })) as { id: string; name: string }[];
          const cardRef = resolveRef("credit card", a.credit_card, cards);
          if ("error" in cardRef) return fail(cardRef.error);
          creditCardId = cardRef.ok;
        }

        let categoryId: string | null = null;
        const needCats = !!a.category || a.participants.some((p: { category?: string }) => p.category);
        const cats = needCats
          ? ((await rest.list("categories", { limit: 500 })) as { id: string; name: string }[])
          : [];
        if (a.category) {
          const catRef = resolveRef("category", a.category, cats);
          if ("error" in catRef) return fail(catRef.error);
          categoryId = catRef.ok;
        }

        // Resolve each participant by name/id, auto-creating a new person —
        // People are lightweight (just a name), so this is low-risk and
        // matches the app's own inline "+ Add person" convenience.
        const people = (await rest.list("people", { limit: 500 })) as { id: string; name: string }[];
        const now = new Date().toISOString();
        const participantIds: string[] = [];
        const participantInputs: Record<string, number> = {};
        const participantExtras: Record<string, { categoryId: string | null; note: string | null }> = {};
        for (const p of a.participants) {
          const ref = resolveRef("person", p.person, people);
          let id: string;
          if ("error" in ref) {
            if (people.some((x) => x.name.toLowerCase() === p.person.toLowerCase())) {
              return fail(ref.error); // genuinely ambiguous — surface it rather than guess
            }
            const created = (await rest.insert("people", {
              id: crypto.randomUUID(),
              name: p.person,
              created_at: now,
              updated_at: now,
            })) as { id: string };
            id = created.id;
            people.push({ id, name: p.person });
          } else {
            id = ref.ok;
          }
          participantIds.push(id);
          participantInputs[id] = p.value ?? 0;

          let pCategoryId: string | null = null;
          if (p.category) {
            const catRef = resolveRef("category", p.category, cats);
            if ("error" in catRef) return fail(catRef.error);
            pCategoryId = catRef.ok;
          }
          participantExtras[id] = { categoryId: pCategoryId, note: p.note ?? null };
        }

        const shares = resolveSplitShares({
          mode: a.mode as SplitMode,
          totalAmount: a.total_amount,
          participantIds,
          participantInputs,
          payerInput: a.payer_value ?? 1,
        });
        if (!shares) {
          return fail(
            "The shares given don't resolve to a valid split for this mode — " +
              "custom shares must not exceed the total, and ratio/percentage " +
              "(including payer_value) must be positive and, for percentage, sum to 100.",
          );
        }

        // 1. The real, full-amount expense — this is what actually left the
        // account/card, exactly like any other expense.
        const txRow = {
          id: crypto.randomUUID(),
          account_id: acctRef.ok,
          type: "expense",
          amount: a.total_amount,
          category_id: categoryId,
          merchant: a.title,
          date: a.date ?? now,
          credit_card_id: creditCardId,
          is_external_to_account: false,
          is_cash_spend: false,
          tags: [],
          splits: [],
          sync_status: "synced",
          created_at: now,
          updated_at: now,
        };
        const createdTx = (await rest.insert("transactions", txRow)) as { id: string };

        // 2. The split expense, linked to that transaction.
        const createdSplit = (await rest.insert("split_expenses", {
          id: crypto.randomUUID(),
          title: a.title,
          total_amount: a.total_amount,
          date: a.date ?? now,
          transaction_id: createdTx.id,
          mode: a.mode,
          created_at: now,
          updated_at: now,
        })) as { id: string };

        // 3. One participant row per person with their resolved share.
        const participants = [];
        for (const id of participantIds) {
          participants.push(
            await rest.insert("split_participants", {
              id: crypto.randomUUID(),
              split_expense_id: createdSplit.id,
              person_id: id,
              share_amount: shares[id],
              category_id: participantExtras[id]?.categoryId ?? null,
              note: participantExtras[id]?.note ?? null,
              settled_amount: 0,
              created_at: now,
              updated_at: now,
            }),
          );
        }

        return ok({ transaction: createdTx, split_expense: createdSplit, participants });
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "settle_person",
    "Record money received from a person, applied to their oldest unsettled split shares " +
      "first — fully covering each before moving to the next (partial settlement allowed, " +
      "and the amount is capped at what's actually owed). Pass `account` if they paid you " +
      "back via bank/UPI — this also records a real credit to that account, excluded from " +
      "income/expense reports since it's a balance transfer, not new income. Omit it if they " +
      "handed you cash: only the settled amounts update, your balance is untouched.",
    {
      person: z.string().describe("Name or id."),
      amount: z.number().positive(),
      account: z.string().optional().describe("If given, records a transaction crediting this account."),
    },
    async ({ person, amount, account }) => {
      try {
        const people = (await rest.list("people", { limit: 500 })) as { id: string; name: string }[];
        const personRef = resolveRef("person", person, people);
        if ("error" in personRef) return fail(personRef.error);
        const personId = personRef.ok;
        const personName = people.find((p) => p.id === personId)?.name ?? person;

        const [participants, splits] = (await Promise.all([
          rest.list("split_participants", { eq: { person_id: personId }, limit: 500 }),
          rest.list("split_expenses", { limit: 500 }),
        ])) as [Record<string, any>[], Record<string, any>[]];
        const splitDateById = new Map(splits.map((s) => [s.id, s.date as string]));
        const rows = participants
          .filter((p) => p.share_amount - (p.settled_amount ?? 0) > 0.01)
          .sort((a2, b2) => {
            const da = splitDateById.get(a2.split_expense_id) ?? "";
            const db = splitDateById.get(b2.split_expense_id) ?? "";
            return da < db ? -1 : da > db ? 1 : 0;
          });
        if (rows.length === 0) return fail(`${personName} has no unsettled split shares.`);

        let remaining = amount;
        const updates: { id: string; newSettled: number }[] = [];
        for (const row of rows) {
          if (remaining <= 0.01) break;
          const owed = row.share_amount - (row.settled_amount ?? 0);
          const applied = Math.min(remaining, owed);
          updates.push({ id: row.id, newSettled: (row.settled_amount ?? 0) + applied });
          remaining -= applied;
        }
        const totalApplied = amount - remaining;
        if (totalApplied <= 0.01) return fail("Nothing to settle.");

        const now = new Date().toISOString();
        let settledTransactionId: string | null = null;
        if (account) {
          const accounts = (await rest.list("accounts", { limit: 500 })) as { id: string; name: string }[];
          const acctRef = resolveRef("account", account, accounts);
          if ("error" in acctRef) return fail(acctRef.error);
          const createdTx = (await rest.insert("transactions", {
            id: crypto.randomUUID(),
            account_id: acctRef.ok,
            type: "refund",
            amount: totalApplied,
            merchant: `Settlement: ${personName}`,
            date: now,
            is_external_to_account: false,
            is_cash_spend: false,
            is_settlement: true,
            tags: [],
            splits: [],
            sync_status: "synced",
            created_at: now,
            updated_at: now,
          })) as { id: string };
          settledTransactionId = createdTx.id;
        }

        const updated = [];
        for (const u of updates) {
          updated.push(
            await rest.patch("split_participants", u.id, {
              settled_amount: u.newSettled,
              settled_at: now,
              settled_transaction_id: settledTransactionId,
              updated_at: now,
            }),
          );
        }
        return ok({
          applied: totalApplied,
          unapplied: remaining,
          transaction_id: settledTransactionId,
          updated_participants: updated,
        });
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "add_payable",
    "Log money you owe someone — they paid for something, or it's a personal loan. " +
      "Separate from a bill you paid and split with others (use add_split_expense for that). " +
      "Doesn't touch any account until settled.",
    {
      person: z.string().describe("Name or id — a new name is created automatically."),
      amount: z.number().positive(),
      description: z.string().trim().min(1),
      date: z.string().datetime({ offset: true }).optional(),
    },
    async (a) => {
      try {
        const people = (await rest.list("people", { limit: 500 })) as { id: string; name: string }[];
        const ref = resolveRef("person", a.person, people);
        let personId: string;
        if ("error" in ref) {
          if (people.some((x) => x.name.toLowerCase() === a.person.toLowerCase())) return fail(ref.error);
          const now0 = new Date().toISOString();
          const created = (await rest.insert("people", {
            id: crypto.randomUUID(), name: a.person, created_at: now0, updated_at: now0,
          })) as { id: string };
          personId = created.id;
        } else {
          personId = ref.ok;
        }
        const now = new Date().toISOString();
        const created = await rest.insert("payables", {
          id: crypto.randomUUID(),
          person_id: personId,
          amount: a.amount,
          description: a.description,
          date: a.date ?? now,
          settled_amount: 0,
          created_at: now,
          updated_at: now,
        });
        return ok(created);
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "settle_payable",
    "Pay off money you owe a person, applied to their oldest unsettled payables first — " +
      "fully covering each before moving to the next (partial settlement allowed, capped at " +
      "what's actually owed). Pass `account` when you actually pay them from an account/card " +
      "— this records a real expense debiting that account, excluded from income/expense " +
      "reports since it's a balance transfer, not new spending.",
    {
      person: z.string().describe("Name or id."),
      amount: z.number().positive(),
      account: z.string().optional().describe("If given, records a transaction debiting this account."),
    },
    async ({ person, amount, account }) => {
      try {
        const people = (await rest.list("people", { limit: 500 })) as { id: string; name: string }[];
        const personRef = resolveRef("person", person, people);
        if ("error" in personRef) return fail(personRef.error);
        const personId = personRef.ok;
        const personName = people.find((p) => p.id === personId)?.name ?? person;

        const payables = (await rest.list("payables", {
          eq: { person_id: personId },
          limit: 500,
        })) as Record<string, any>[];
        const rows = payables
          .filter((p) => p.amount - (p.settled_amount ?? 0) > 0.01)
          .sort((a2, b2) => ((a2.date as string) < (b2.date as string) ? -1 : (a2.date as string) > (b2.date as string) ? 1 : 0));
        if (rows.length === 0) return fail(`${personName} has no unsettled payables.`);

        let remaining = amount;
        const updates: { id: string; newSettled: number }[] = [];
        for (const row of rows) {
          if (remaining <= 0.01) break;
          const owed = row.amount - (row.settled_amount ?? 0);
          const applied = Math.min(remaining, owed);
          updates.push({ id: row.id, newSettled: (row.settled_amount ?? 0) + applied });
          remaining -= applied;
        }
        const totalApplied = amount - remaining;
        if (totalApplied <= 0.01) return fail("Nothing to settle.");

        const now = new Date().toISOString();
        let settledTransactionId: string | null = null;
        if (account) {
          const accounts = (await rest.list("accounts", { limit: 500 })) as { id: string; name: string }[];
          const acctRef = resolveRef("account", account, accounts);
          if ("error" in acctRef) return fail(acctRef.error);
          const createdTx = (await rest.insert("transactions", {
            id: crypto.randomUUID(),
            account_id: acctRef.ok,
            type: "expense",
            amount: totalApplied,
            merchant: `Settlement: ${personName}`,
            date: now,
            is_external_to_account: false,
            is_cash_spend: false,
            is_settlement: true,
            tags: [],
            splits: [],
            sync_status: "synced",
            created_at: now,
            updated_at: now,
          })) as { id: string };
          settledTransactionId = createdTx.id;
        }

        const updated = [];
        for (const u of updates) {
          updated.push(
            await rest.patch("payables", u.id, {
              settled_amount: u.newSettled,
              settled_at: now,
              settled_transaction_id: settledTransactionId,
              updated_at: now,
            }),
          );
        }
        return ok({
          applied: totalApplied,
          unapplied: remaining,
          transaction_id: settledTransactionId,
          updated_payables: updated,
        });
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "person_balance",
    "Net balance with one person, computed live from unsettled split shares minus " +
      "unsettled payables — never stored, so it can't drift. Positive = they owe you, " +
      "negative = you owe them.",
    { person: z.string().describe("Name or id.") },
    async ({ person }) => {
      try {
        const people = (await rest.list("people", { limit: 500 })) as { id: string; name: string }[];
        const ref = resolveRef("person", person, people);
        if ("error" in ref) return fail(ref.error);
        const [participants, payables] = (await Promise.all([
          rest.list("split_participants", { eq: { person_id: ref.ok }, limit: 500 }),
          rest.list("payables", { eq: { person_id: ref.ok }, limit: 500 }),
        ])) as [ReceivableRow[], PayableRow[]];
        const balance = computePersonBalance(ref.ok, participants, payables);
        const name = people.find((p) => p.id === ref.ok)?.name ?? person;
        return ok({ person_id: ref.ok, name, balance });
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "list_balances",
    "List every person with a non-zero net balance (unsettled split shares minus " +
      "unsettled payables). Positive = they owe you, negative = you owe them.",
    {},
    async () => {
      try {
        const [people, participants, payables] = (await Promise.all([
          rest.list("people", { limit: 500 }),
          rest.list("split_participants", { limit: 500 }),
          rest.list("payables", { limit: 500 }),
        ])) as [{ id: string; name: string }[], ReceivableRow[], PayableRow[]];
        return ok(computeAllBalances(people, participants, payables));
      } catch (e) {
        return toToolError(e);
      }
    },
  );
}
