import { z } from "zod";
import { AuthError } from "../auth/supabase-auth";
import {
  computeAccountBalance, computeBudgetSpent, type BalanceTxn, type SpentTxn,
} from "../data/derive";
import { ENTITIES, ENTITY_NAMES, type EntityDef, type EntityName } from "../data/entities";
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
  kind: "account" | "category",
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
}
