# PersonalTracker MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A remote MCP server on Cloudflare Workers that lets any Claude client on the user's account do full CRUD against the PersonalTracker (Aspyric) data model, authenticating the user via a web login backed by Supabase.

**Architecture:** One Worker composes `@cloudflare/workers-oauth-provider` (owns `/authorize`, `/token`, `/register`, discovery docs), a Hono login handler that validates email/password against Supabase GoTrue and completes the OAuth grant, and an `McpAgent` (Durable Object, SQLite-backed, free-plan eligible) at `/mcp` + `/sse` whose tools call Supabase PostgREST with the signed-in user's token. Supabase Row-Level Security is the entire authorization model — no service-role key.

**Tech Stack:** TypeScript, Cloudflare Workers + Workers KV + SQLite Durable Objects, `@cloudflare/workers-oauth-provider`, `agents` (`McpAgent`), `@modelcontextprotocol/sdk`, `hono`, `zod`, `vitest`, `wrangler`.

**Spec:** `docs/superpowers/specs/2026-09-08-personal-tracker-mcp-design.md` — read it alongside this plan.

## Global Constraints

- **Location:** everything lives in `personal-tracker-mcp/` at the repo root. Never touch `lib/`, `supabase/`, or any Flutter code.
- **Free tier only:** Workers free plan, Workers KV free plan, SQLite-backed Durable Objects (free-plan eligible via `new_sqlite_classes`), `workers.dev` subdomain. No paid Cloudflare products, no Worker secrets, no credit card.
- **No service-role key.** All Supabase data access uses the signed-in user's access token + the publishable anon key. RLS does per-user isolation.
- **Supabase project (public values, safe to commit):**
  - `SUPABASE_URL` = `https://zztvtryevtzqmlfgiiir.supabase.co`
  - `SUPABASE_ANON_KEY` = `sb_publishable_3TVjGyvtiCIUMkdZNOJMQw_PDC-slq_`
- **10 entities** (v1): `accounts`, `transactions`, `categories`, `credit_cards`, `loans`, `budgets`, `recurring_payments`, `investments`, `goals`, `companies`. **`notes` is excluded** — encrypted at rest, no server key.
- **Excluded columns** (never read or written): `enc_account_number`, `enc_ifsc` (accounts); `enc_card_number`, `enc_cvv`, `enc_pin` (credit_cards); `attachment_path` (transactions).
- **Enum wire values** are Dart enum `.name` strings — copied verbatim in Task 2. Do not invent or reformat them.
- **IDs:** `accounts` and `transactions` have Postgres `uuid` id columns — new rows use `crypto.randomUUID()`. Other tables use `text` ids (UUID is still fine). `user_id` is NEVER sent (DB default `auth.uid()`).
- **Deletes are soft:** set `is_deleted=true, deleted_at=<now>, updated_at=<now>`. Never hard-DELETE.
- **Dates:** ISO-8601 strings with offset, in and out.
- **Every task ends by running `npm test` (and `npm run typecheck` where noted) from `personal-tracker-mcp/` and committing.** Commit messages are prefixed `feat(mcp):` / `test(mcp):` / `chore(mcp):`.
- **Library API drift:** the exact surface of `@cloudflare/workers-oauth-provider` and `agents` can change between versions. Where a task's code calls those libraries, verify signatures against the installed `node_modules` types and, if needed, load the `cloudflare:build-mcp` skill for the current pattern. The Supabase GoTrue / PostgREST HTTP surface used here is stable.

---

## File structure

| File | Responsibility |
|---|---|
| `personal-tracker-mcp/package.json` | deps + scripts |
| `personal-tracker-mcp/tsconfig.json` | strict TS, Workers types |
| `personal-tracker-mcp/vitest.config.ts` | node-env unit tests |
| `personal-tracker-mcp/wrangler.jsonc` | Worker name, vars, KV + DO bindings, migration |
| `personal-tracker-mcp/.gitignore` | node_modules, .dev.vars, .wrangler |
| `personal-tracker-mcp/.dev.vars.example` | local-dev vars template |
| `personal-tracker-mcp/src/types.ts` | `Env`, `AuthProps` |
| `personal-tracker-mcp/src/auth/supabase-auth.ts` | GoTrue password + refresh; `Session`; `AuthError` |
| `personal-tracker-mcp/src/auth/login-handler.ts` | Hono app: `GET`/`POST /authorize` + login page HTML |
| `personal-tracker-mcp/src/data/entities.ts` | enum constants + per-entity Zod schemas + registry |
| `personal-tracker-mcp/src/data/derive.ts` | `computeAccountBalance` (port of `FinanceState`) |
| `personal-tracker-mcp/src/data/supabase-rest.ts` | PostgREST client: `list`/`get`/`insert`/`patch` + transparent token refresh + retry |
| `personal-tracker-mcp/src/mcp/tools.ts` | `registerTools(server, deps)` — the 7 tools |
| `personal-tracker-mcp/src/mcp/agent.ts` | `PersonalTrackerMCP extends McpAgent` — state seed + wiring |
| `personal-tracker-mcp/src/index.ts` | `OAuthProvider` composition; Worker default export |
| `personal-tracker-mcp/test/*.test.ts` | one file per source module under test |
| `personal-tracker-mcp/README.md` | deploy + connect + manual integration checklist |

---

## Task 1: Scaffold the project

**Files:**
- Create: `personal-tracker-mcp/package.json`
- Create: `personal-tracker-mcp/tsconfig.json`
- Create: `personal-tracker-mcp/vitest.config.ts`
- Create: `personal-tracker-mcp/wrangler.jsonc`
- Create: `personal-tracker-mcp/.gitignore`
- Create: `personal-tracker-mcp/.dev.vars.example`
- Create: `personal-tracker-mcp/src/types.ts`
- Create: `personal-tracker-mcp/src/index.ts` (temporary stub)
- Create: `personal-tracker-mcp/test/smoke.test.ts`

**Interfaces:**
- Produces: `Env` (`{ OAUTH_KV: KVNamespace; MCP_OBJECT: DurableObjectNamespace; SUPABASE_URL: string; SUPABASE_ANON_KEY: string }`), `AuthProps` (re-exported later from `Session`).

- [ ] **Step 1: Create `personal-tracker-mcp/package.json`**

```json
{
  "name": "personal-tracker-mcp",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@cloudflare/workers-oauth-provider": "latest",
    "@modelcontextprotocol/sdk": "^1",
    "agents": "latest",
    "hono": "^4",
    "zod": "^3"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "latest",
    "typescript": "^5",
    "vitest": "^2",
    "wrangler": "^4"
  }
}
```

- [ ] **Step 2: Create `personal-tracker-mcp/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "es2022",
    "module": "es2022",
    "moduleResolution": "bundler",
    "lib": ["es2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "verbatimModuleSyntax": false
  },
  "include": ["src", "test", "*.ts"]
}
```

- [ ] **Step 3: Create `personal-tracker-mcp/vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: { environment: "node", include: ["test/**/*.test.ts"] },
});
```

- [ ] **Step 4: Create `personal-tracker-mcp/wrangler.jsonc`**

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "personal-tracker-mcp",
  "main": "src/index.ts",
  "compatibility_date": "2025-09-01",
  "compatibility_flags": ["nodejs_compat"],
  "vars": {
    "SUPABASE_URL": "https://zztvtryevtzqmlfgiiir.supabase.co",
    "SUPABASE_ANON_KEY": "sb_publishable_3TVjGyvtiCIUMkdZNOJMQw_PDC-slq_"
  },
  "kv_namespaces": [
    { "binding": "OAUTH_KV", "id": "PLACEHOLDER_RUN_wrangler_kv_namespace_create_OAUTH_KV" }
  ],
  "durable_objects": {
    "bindings": [{ "name": "MCP_OBJECT", "class_name": "PersonalTrackerMCP" }]
  },
  "migrations": [
    { "tag": "v1", "new_sqlite_classes": ["PersonalTrackerMCP"] }
  ],
  "observability": { "enabled": true }
}
```

- [ ] **Step 5: Create `personal-tracker-mcp/.gitignore`**

```
node_modules/
.wrangler/
.dev.vars
dist/
*.log
```

- [ ] **Step 6: Create `personal-tracker-mcp/.dev.vars.example`**

```
# Copy to .dev.vars for `wrangler dev`. Same public values as wrangler.jsonc;
# override only when pointing at a different Supabase project.
SUPABASE_URL=https://zztvtryevtzqmlfgiiir.supabase.co
SUPABASE_ANON_KEY=sb_publishable_3TVjGyvtiCIUMkdZNOJMQw_PDC-slq_
```

- [ ] **Step 7: Create `personal-tracker-mcp/src/types.ts`**

```ts
export interface Env {
  OAUTH_KV: KVNamespace;
  MCP_OBJECT: DurableObjectNamespace;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
}
```

- [ ] **Step 8: Create `personal-tracker-mcp/src/index.ts` (stub)**

```ts
// Replaced in Task 10 with the real OAuthProvider composition.
export default {
  fetch(): Response {
    return new Response("personal-tracker-mcp: not wired yet", { status: 503 });
  },
};
```

- [ ] **Step 9: Create `personal-tracker-mcp/test/smoke.test.ts`**

```ts
import { expect, test } from "vitest";

test("toolchain runs", () => {
  expect(1 + 1).toBe(2);
});
```

- [ ] **Step 10: Install and verify**

Run (from `personal-tracker-mcp/`):
```bash
npm install
npm test
npm run typecheck
```
Expected: `npm install` resolves; `npm test` → 1 passed; `npm run typecheck` → no errors.

- [ ] **Step 11: Commit**

```bash
git add personal-tracker-mcp
git commit -m "chore(mcp): scaffold Cloudflare Worker project"
```

---

## Task 2: Entity registry + enum constants

**Files:**
- Create: `personal-tracker-mcp/src/data/entities.ts`
- Test: `personal-tracker-mcp/test/entities.test.ts`

**Interfaces:**
- Produces:
  - `EntityName` (union of the 10 table names), `ENTITY_NAMES: [EntityName, ...EntityName[]]`
  - `ENTITIES: Record<EntityName, EntityDef>` where `EntityDef = { table: string; displayName: string; uuidId: boolean; createSchema: z.ZodTypeAny; updateSchema: z.ZodTypeAny; omitFields: readonly string[]; fixed?: Record<string, unknown>; derived?: "accountBalance" }`
  - enum arrays: `ACCOUNT_TYPES`, `TRANSACTION_TYPES`, `PAYMENT_FREQUENCIES`, `INVESTMENT_TYPES`, `CARD_TYPES`, `CARD_NETWORKS`, `CARD_COLOR_PRESETS`, `CATEGORY_TYPES`

- [ ] **Step 1: Write the failing test — `personal-tracker-mcp/test/entities.test.ts`**

```ts
import { describe, expect, test } from "vitest";
import {
  ACCOUNT_TYPES, TRANSACTION_TYPES, PAYMENT_FREQUENCIES, INVESTMENT_TYPES,
  CARD_TYPES, CARD_NETWORKS, CARD_COLOR_PRESETS, CATEGORY_TYPES,
  ENTITIES, ENTITY_NAMES,
} from "../src/data/entities";

describe("enum parity with the Flutter app", () => {
  test("values match app_constants.dart / models.dart exactly", () => {
    expect(ACCOUNT_TYPES).toEqual([
      "bankAccount", "cash", "savingsAccount", "currentAccount", "wallet",
      "fd", "rd", "investmentAccount", "otherAsset",
    ]);
    expect(TRANSACTION_TYPES).toEqual([
      "income", "expense", "transfer", "creditCardPayment", "loanPayment",
      "investment", "refund", "adjustment",
    ]);
    expect(PAYMENT_FREQUENCIES).toEqual(["daily", "weekly", "monthly", "quarterly", "yearly"]);
    expect(INVESTMENT_TYPES).toEqual([
      "mutualFundSip", "stocks", "fixedDeposit", "recurringDeposit", "gold",
      "ppf", "epf", "crypto", "other",
    ]);
    expect(CARD_TYPES).toEqual(["credit", "debit", "prepaid", "store", "forex"]);
    expect(CARD_NETWORKS).toEqual(["visa", "mastercard", "rupay", "amex", "diners", "other"]);
    expect(CARD_COLOR_PRESETS).toEqual([
      "midnight", "gold", "rose", "emerald", "slate", "violet", "crimson", "ocean",
    ]);
    expect(CATEGORY_TYPES).toEqual(["income", "expense"]);
  });
});

describe("entity registry", () => {
  test("exactly the 10 v1 entities, notes excluded", () => {
    expect([...ENTITY_NAMES].sort()).toEqual([
      "accounts", "budgets", "categories", "companies", "credit_cards",
      "goals", "investments", "loans", "recurring_payments", "transactions",
    ]);
  });

  test("every entity has table, schemas, omitFields", () => {
    for (const name of ENTITY_NAMES) {
      const def = ENTITIES[name];
      expect(typeof def.table).toBe("string");
      expect(def.createSchema).toBeDefined();
      expect(def.updateSchema).toBeDefined();
      expect(Array.isArray(def.omitFields)).toBe(true);
    }
  });

  test("accounts: valid create parses, bad type rejected, derived flag set", () => {
    const good = ENTITIES.accounts.createSchema.safeParse({ name: "HDFC", type: "savingsAccount" });
    expect(good.success).toBe(true);
    const bad = ENTITIES.accounts.createSchema.safeParse({ name: "X", type: "checking" });
    expect(bad.success).toBe(false);
    expect(ENTITIES.accounts.derived).toBe("accountBalance");
    expect(ENTITIES.accounts.omitFields).toContain("enc_account_number");
  });

  test("transactions: account_id must be a uuid, fixed sync_status present", () => {
    const bad = ENTITIES.transactions.createSchema.safeParse({
      account_id: "not-a-uuid", type: "expense", amount: 10,
    });
    expect(bad.success).toBe(false);
    const good = ENTITIES.transactions.createSchema.safeParse({
      account_id: "11111111-1111-1111-1111-111111111111", type: "expense", amount: 10,
    });
    expect(good.success).toBe(true);
    expect(ENTITIES.transactions.fixed).toMatchObject({ sync_status: "synced" });
  });

  test("credit_cards: applies defaults", () => {
    const r = ENTITIES.credit_cards.createSchema.parse({ name: "Regalia" });
    expect(r).toMatchObject({ card_type: "credit", network: "visa", due_day: 15, statement_day: 1 });
  });

  test("budgets: month_year must be YYYY-MM", () => {
    expect(ENTITIES.budgets.createSchema.safeParse({ category_id: "c1", month_year: "Sept" }).success).toBe(false);
    expect(ENTITIES.budgets.createSchema.safeParse({ category_id: "c1", month_year: "2026-09" }).success).toBe(true);
  });

  test("updateSchema is partial (empty object parses)", () => {
    expect(ENTITIES.goals.updateSchema.safeParse({}).success).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- entities`
Expected: FAIL — `Cannot find module '../src/data/entities'`.

- [ ] **Step 3: Write `personal-tracker-mcp/src/data/entities.ts`**

```ts
import { z } from "zod";

/**
 * Enum wire values = Dart enum `.name` strings. Keep in sync with:
 *   AccountType / TransactionType / PaymentFrequency / InvestmentType
 *     -> lib/core/constants/app_constants.dart
 *   CardType / CardNetwork / CardColorPreset -> lib/domain/models/models.dart
 *   category `type` -> CategoryModel ('income' | 'expense')
 */
export const ACCOUNT_TYPES = [
  "bankAccount", "cash", "savingsAccount", "currentAccount", "wallet",
  "fd", "rd", "investmentAccount", "otherAsset",
] as const;
export const TRANSACTION_TYPES = [
  "income", "expense", "transfer", "creditCardPayment", "loanPayment",
  "investment", "refund", "adjustment",
] as const;
export const PAYMENT_FREQUENCIES = ["daily", "weekly", "monthly", "quarterly", "yearly"] as const;
export const INVESTMENT_TYPES = [
  "mutualFundSip", "stocks", "fixedDeposit", "recurringDeposit", "gold",
  "ppf", "epf", "crypto", "other",
] as const;
export const CARD_TYPES = ["credit", "debit", "prepaid", "store", "forex"] as const;
export const CARD_NETWORKS = ["visa", "mastercard", "rupay", "amex", "diners", "other"] as const;
export const CARD_COLOR_PRESETS = [
  "midnight", "gold", "rose", "emerald", "slate", "violet", "crimson", "ocean",
] as const;
export const CATEGORY_TYPES = ["income", "expense"] as const;

const isoDate = z.string().datetime({ offset: true });
const optStr = z.string().trim().min(1).optional();

export interface EntityDef {
  table: string;
  displayName: string;
  uuidId: boolean;
  createSchema: z.ZodTypeAny;
  updateSchema: z.ZodTypeAny;
  omitFields: readonly string[];
  fixed?: Record<string, unknown>;
  derived?: "accountBalance";
}

const accountCreate = z.object({
  name: z.string().trim().min(1),
  type: z.enum(ACCOUNT_TYPES),
  bank: optStr,
  account_number_last4: z.string().regex(/^\d{4}$/).optional(),
  opening_balance: z.number().default(0),
  currency: z.string().trim().min(1).default("INR"),
  is_active: z.boolean().default(true),
}).strict();

const transactionCreate = z.object({
  account_id: z.string().uuid(),
  to_account_id: z.string().uuid().optional(),
  type: z.enum(TRANSACTION_TYPES),
  amount: z.number(),
  category_id: optStr,
  merchant: optStr,
  date: isoDate.optional(),
  description: optStr,
  notes: optStr,
  credit_card_id: optStr,
  loan_id: optStr,
  investment_id: optStr,
  company_id: optStr,
  is_external_to_account: z.boolean().default(false),
  tags: z.array(z.string()).default([]),
}).strict();

const categoryCreate = z.object({
  name: z.string().trim().min(1),
  type: z.enum(CATEGORY_TYPES),
  parent_id: optStr,
  icon: z.string().trim().min(1).default("tag"),
  color_hex: z.string().trim().min(1).default("0xFF6366F1"),
}).strict();

const creditCardCreate = z.object({
  name: z.string().trim().min(1),
  card_type: z.enum(CARD_TYPES).default("credit"),
  bank: z.string().default(""),
  last4: z.string().regex(/^\d{0,4}$/).default(""),
  network: z.enum(CARD_NETWORKS).default("visa"),
  cardholder_name: z.string().default(""),
  expiry_month: z.number().int().min(1).max(12).optional(),
  expiry_year: z.number().int().min(2000).max(2100).optional(),
  color_preset: z.enum(CARD_COLOR_PRESETS).default("midnight"),
  color_hex: optStr,
  is_virtual: z.boolean().default(false),
  notes: optStr,
  credit_limit: z.number().default(0),
  current_outstanding: z.number().default(0),
  statement_day: z.number().int().min(1).max(31).default(1),
  due_day: z.number().int().min(1).max(31).default(15),
  linked_account_id: optStr,
  balance: z.number().optional(),
  currency: optStr,
}).strict();

const loanCreate = z.object({
  name: z.string().trim().min(1),
  provider: z.string().default(""),
  principal_amount: z.number().default(0),
  outstanding_amount: z.number().default(0),
  interest_rate: z.number().default(0),
  monthly_emi: z.number().default(0),
  due_day: z.number().int().min(1).max(31).default(1),
  start_date: isoDate.optional(),
  remaining_tenure_months: z.number().int().min(0).default(0),
}).strict();

const budgetCreate = z.object({
  category_id: z.string().trim().min(1),
  monthly_limit: z.number().default(0),
  month_year: z.string().regex(/^\d{4}-\d{2}$/, 'must be "YYYY-MM"'),
  spent_amount: z.number().default(0),
}).strict();

const recurringCreate = z.object({
  title: z.string().trim().min(1),
  amount: z.number().default(0),
  frequency: z.enum(PAYMENT_FREQUENCIES).default("monthly"),
  next_due_date: isoDate,
  category_id: optStr,
  account_id: optStr,
  is_auto_pay: z.boolean().default(false),
  is_income: z.boolean().default(false),
  company_id: optStr,
}).strict();

const investmentCreate = z.object({
  name: z.string().trim().min(1),
  type: z.enum(INVESTMENT_TYPES).default("other"),
  invested_amount: z.number().default(0),
  current_value: z.number().default(0),
  monthly_sip_amount: z.number().default(0),
  sip_day: z.number().int().min(1).max(31).default(1),
  reference_number: optStr,
}).strict();

const goalCreate = z.object({
  name: z.string().trim().min(1),
  target_amount: z.number().default(0),
  current_saved_amount: z.number().default(0),
  target_date: isoDate.optional(),
  icon: z.string().trim().min(1).default("target"),
  color_hex: z.string().trim().min(1).default("0xFF6366F1"),
}).strict();

const companyCreate = z.object({
  name: z.string().trim().min(1),
  joined_date: isoDate.optional(),
  is_current_employer: z.boolean().default(false),
  default_bank_account_id: optStr,
  default_pf_amount: z.number().optional(),
}).strict();

export const ENTITIES = {
  accounts: {
    table: "accounts", displayName: "account", uuidId: true,
    createSchema: accountCreate, updateSchema: accountCreate.partial(),
    omitFields: ["enc_account_number", "enc_ifsc"], derived: "accountBalance",
  },
  transactions: {
    table: "transactions", displayName: "transaction", uuidId: true,
    createSchema: transactionCreate, updateSchema: transactionCreate.partial(),
    omitFields: ["attachment_path"], fixed: { sync_status: "synced", splits: [] },
  },
  categories: {
    table: "categories", displayName: "category", uuidId: false,
    createSchema: categoryCreate, updateSchema: categoryCreate.partial(), omitFields: [],
  },
  credit_cards: {
    table: "credit_cards", displayName: "credit card", uuidId: false,
    createSchema: creditCardCreate, updateSchema: creditCardCreate.partial(),
    omitFields: ["enc_card_number", "enc_cvv", "enc_pin"],
  },
  loans: {
    table: "loans", displayName: "loan", uuidId: false,
    createSchema: loanCreate, updateSchema: loanCreate.partial(), omitFields: [],
  },
  budgets: {
    table: "budgets", displayName: "budget", uuidId: false,
    createSchema: budgetCreate, updateSchema: budgetCreate.partial(), omitFields: [],
  },
  recurring_payments: {
    table: "recurring_payments", displayName: "recurring payment", uuidId: false,
    createSchema: recurringCreate, updateSchema: recurringCreate.partial(), omitFields: [],
  },
  investments: {
    table: "investments", displayName: "investment", uuidId: false,
    createSchema: investmentCreate, updateSchema: investmentCreate.partial(), omitFields: [],
  },
  goals: {
    table: "goals", displayName: "goal", uuidId: false,
    createSchema: goalCreate, updateSchema: goalCreate.partial(), omitFields: [],
  },
  companies: {
    table: "companies", displayName: "company", uuidId: false,
    createSchema: companyCreate, updateSchema: companyCreate.partial(), omitFields: [],
  },
} satisfies Record<string, EntityDef>;

export type EntityName = keyof typeof ENTITIES;
export const ENTITY_NAMES = Object.keys(ENTITIES) as [EntityName, ...EntityName[]];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- entities`
Expected: PASS (all cases).

- [ ] **Step 5: Typecheck**

Run: `npm run typecheck`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add personal-tracker-mcp/src/data/entities.ts personal-tracker-mcp/test/entities.test.ts
git commit -m "feat(mcp): entity registry + enum constants (10 entities)"
```

---

## Task 3: Account-balance derivation

**Files:**
- Create: `personal-tracker-mcp/src/data/derive.ts`
- Test: `personal-tracker-mcp/test/derive.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `BalanceTxn = { account_id: string; to_account_id: string | null; type: string; amount: number; credit_card_id: string | null; is_external_to_account: boolean }`
  - `computeAccountBalance(account: { id: string; opening_balance: number }, txns: readonly BalanceTxn[], creditCardIds: ReadonlySet<string>): number`
  - `SpentTxn = { category_id: string | null; type: string; amount: number; date: string }`
  - `computeBudgetSpent(budget: { category_id: string; month_year: string }, txns: readonly SpentTxn[]): number` — sum of `amount` for non-deleted `expense` transactions whose `category_id` matches and whose `date` (ISO string) starts with `<month_year>` (`"YYYY-MM"`).

- [ ] **Step 1: Write the failing test — `personal-tracker-mcp/test/derive.test.ts`**

```ts
import { describe, expect, test } from "vitest";
import {
  computeAccountBalance, computeBudgetSpent, type BalanceTxn, type SpentTxn,
} from "../src/data/derive";

const acc = { id: "A", opening_balance: 1000 };
const tx = (p: Partial<BalanceTxn>): BalanceTxn => ({
  account_id: "A", to_account_id: null, type: "expense", amount: 0,
  credit_card_id: null, is_external_to_account: false, ...p,
});

describe("computeAccountBalance — port of FinanceState.accountsWithCalculatedBalances", () => {
  test("opening balance only", () => {
    expect(computeAccountBalance(acc, [], new Set())).toBe(1000);
  });
  test("income and refund add", () => {
    expect(computeAccountBalance(acc, [tx({ type: "income", amount: 500 }), tx({ type: "refund", amount: 100 })], new Set())).toBe(1600);
  });
  test("expense / transfer / cc payment / loan payment / investment / adjustment subtract", () => {
    const txns = ["expense", "transfer", "creditCardPayment", "loanPayment", "investment", "adjustment"]
      .map((t) => tx({ type: t, amount: 100 }));
    expect(computeAccountBalance(acc, txns, new Set())).toBe(1000 - 600);
  });
  test("incoming transfer (to_account_id) adds regardless of type", () => {
    expect(computeAccountBalance(acc, [tx({ account_id: "B", to_account_id: "A", type: "transfer", amount: 250 })], new Set())).toBe(1250);
  });
  test("is_external_to_account rows are skipped on the account_id leg", () => {
    expect(computeAccountBalance(acc, [tx({ type: "expense", amount: 300, is_external_to_account: true })], new Set())).toBe(1000);
  });
  test("credit-card charge rows are skipped (credit card id + expense/refund)", () => {
    const credit = new Set(["card1"]);
    expect(computeAccountBalance(acc, [
      tx({ type: "expense", amount: 400, credit_card_id: "card1" }),
      tx({ type: "refund", amount: 50, credit_card_id: "card1" }),
    ], credit)).toBe(1000);
  });
  test("a charge on a NON-credit card still counts", () => {
    expect(computeAccountBalance(acc, [tx({ type: "expense", amount: 400, credit_card_id: "debit9" })], new Set(["card1"]))).toBe(600);
  });
  test("rows for other accounts are ignored", () => {
    expect(computeAccountBalance(acc, [tx({ account_id: "Z", type: "expense", amount: 999 })], new Set())).toBe(1000);
  });
});

describe("computeBudgetSpent", () => {
  const b = { category_id: "food", month_year: "2026-09" };
  const st = (p: Partial<SpentTxn>): SpentTxn => ({
    category_id: "food", type: "expense", amount: 0, date: "2026-09-15T10:00:00.000Z", ...p,
  });
  test("sums matching expense rows in the month", () => {
    expect(computeBudgetSpent(b, [st({ amount: 100 }), st({ amount: 250 })])).toBe(350);
  });
  test("ignores other categories, other months, and non-expense types", () => {
    expect(computeBudgetSpent(b, [
      st({ amount: 100, category_id: "rent" }),
      st({ amount: 100, date: "2026-08-31T23:59:59.000Z" }),
      st({ amount: 100, type: "income" }),
      st({ amount: 40 }),
    ])).toBe(40);
  });
  test("null category never matches", () => {
    expect(computeBudgetSpent(b, [st({ amount: 100, category_id: null })])).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- derive`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `personal-tracker-mcp/src/data/derive.ts`**

```ts
export interface BalanceTxn {
  account_id: string;
  to_account_id: string | null;
  type: string;
  amount: number;
  credit_card_id: string | null;
  is_external_to_account: boolean;
}

const DEBIT_TYPES = new Set([
  "expense", "transfer", "creditCardPayment", "loanPayment", "investment", "adjustment",
]);

/**
 * Port of FinanceState.accountsWithCalculatedBalances
 * (lib/core/database/finance_repository.dart).
 *
 * balance = opening_balance
 *   + income/refund posted to this account
 *   - expense/transfer/creditCardPayment/loanPayment/investment/adjustment posted to this account
 *   + amount for every transaction whose to_account_id is this account
 * Skips rows where is_external_to_account is true, and "card charge" rows whose
 * credit_card_id belongs to a credit card and whose type is expense or refund.
 */
export function computeAccountBalance(
  account: { id: string; opening_balance: number },
  txns: readonly BalanceTxn[],
  creditCardIds: ReadonlySet<string>,
): number {
  let calc = account.opening_balance;
  for (const t of txns) {
    if (t.account_id === account.id) {
      const isCardCharge =
        t.credit_card_id != null &&
        creditCardIds.has(t.credit_card_id) &&
        (t.type === "expense" || t.type === "refund");
      if (!isCardCharge && !t.is_external_to_account) {
        if (t.type === "income" || t.type === "refund") calc += t.amount;
        else if (DEBIT_TYPES.has(t.type)) calc -= t.amount;
      }
    }
    if (t.to_account_id === account.id) calc += t.amount;
  }
  return calc;
}

export interface SpentTxn {
  category_id: string | null;
  type: string;
  amount: number;
  date: string;
}

/**
 * Recomputes a budget's spent_amount from live transactions — the same rule the
 * app's Budgets screen uses: non-deleted `expense` rows in the budget's category
 * whose date falls inside `month_year` ("YYYY-MM"). Callers pass only
 * non-deleted rows (the PostgREST list already filters is_deleted).
 */
export function computeBudgetSpent(
  budget: { category_id: string; month_year: string },
  txns: readonly SpentTxn[],
): number {
  let spent = 0;
  for (const t of txns) {
    if (
      t.type === "expense" &&
      t.category_id != null &&
      t.category_id === budget.category_id &&
      typeof t.date === "string" &&
      t.date.startsWith(budget.month_year)
    ) {
      spent += t.amount;
    }
  }
  return spent;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- derive`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add personal-tracker-mcp/src/data/derive.ts personal-tracker-mcp/test/derive.test.ts
git commit -m "feat(mcp): account-balance derivation ported from FinanceState"
```

---

## Task 4: Supabase GoTrue auth client

**Files:**
- Create: `personal-tracker-mcp/src/auth/supabase-auth.ts`
- Test: `personal-tracker-mcp/test/supabase-auth.test.ts`

**Interfaces:**
- Produces:
  - `Session = { supabaseUserId: string; email: string; accessToken: string; refreshToken: string; expiresAt: number }` (`expiresAt` = epoch seconds)
  - `class AuthError extends Error`
  - `GoTrueConfig = { url: string; anonKey: string }`
  - `signInWithPassword(cfg: GoTrueConfig, email: string, password: string): Promise<Session>`
  - `refreshSession(cfg: GoTrueConfig, refreshToken: string): Promise<Session>` — throws `AuthError("SESSION_EXPIRED")` on failure

- [ ] **Step 1: Write the failing test — `personal-tracker-mcp/test/supabase-auth.test.ts`**

```ts
import { afterEach, describe, expect, test, vi } from "vitest";
import { AuthError, refreshSession, signInWithPassword } from "../src/auth/supabase-auth";

const cfg = { url: "https://x.supabase.co", anonKey: "anon" };
const goodBody = {
  access_token: "at", refresh_token: "rt", expires_at: 1893456000,
  user: { id: "user-1", email: "me@example.com" },
};

afterEach(() => vi.unstubAllGlobals());

function stubFetch(status: number, body: unknown) {
  const fn = vi.fn().mockResolvedValue(
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } }),
  );
  vi.stubGlobal("fetch", fn);
  return fn;
}

describe("signInWithPassword", () => {
  test("maps a successful GoTrue token to a Session", async () => {
    const fetchFn = stubFetch(200, goodBody);
    const s = await signInWithPassword(cfg, "me@example.com", "pw");
    expect(s).toEqual({
      supabaseUserId: "user-1", email: "me@example.com",
      accessToken: "at", refreshToken: "rt", expiresAt: 1893456000,
    });
    const [url, init] = fetchFn.mock.calls[0];
    expect(String(url)).toBe("https://x.supabase.co/auth/v1/token?grant_type=password");
    expect((init as RequestInit).method).toBe("POST");
    expect((init!.headers as Record<string, string>).apikey).toBe("anon");
  });

  test("throws AuthError with GoTrue's message on 400", async () => {
    stubFetch(400, { error_description: "Invalid login credentials" });
    await expect(signInWithPassword(cfg, "me@example.com", "bad")).rejects.toThrowError(AuthError);
    await expect(signInWithPassword(cfg, "me@example.com", "bad")).rejects.toThrow("Invalid login credentials");
  });
});

describe("refreshSession", () => {
  test("returns a fresh Session on success", async () => {
    stubFetch(200, { ...goodBody, access_token: "at2", refresh_token: "rt2" });
    const s = await refreshSession(cfg, "rt");
    expect(s.accessToken).toBe("at2");
    expect(s.refreshToken).toBe("rt2");
  });
  test("throws AuthError('SESSION_EXPIRED') on failure", async () => {
    stubFetch(401, { error: "invalid_grant" });
    await expect(refreshSession(cfg, "rt")).rejects.toThrow("SESSION_EXPIRED");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- supabase-auth`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `personal-tracker-mcp/src/auth/supabase-auth.ts`**

```ts
export interface Session {
  supabaseUserId: string;
  email: string;
  accessToken: string;
  refreshToken: string;
  /** epoch seconds */
  expiresAt: number;
}

export interface GoTrueConfig {
  url: string;
  anonKey: string;
}

export class AuthError extends Error {}

interface GoTrueToken {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  user: { id: string; email: string };
  error_description?: string;
  error?: string;
  msg?: string;
}

function toSession(t: GoTrueToken): Session {
  return {
    supabaseUserId: t.user.id,
    email: t.user.email,
    accessToken: t.access_token,
    refreshToken: t.refresh_token,
    expiresAt: t.expires_at,
  };
}

async function tokenRequest(cfg: GoTrueConfig, grant: string, payload: Record<string, string>): Promise<GoTrueToken> {
  const res = await fetch(`${cfg.url}/auth/v1/token?grant_type=${grant}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: cfg.anonKey },
    body: JSON.stringify(payload),
  });
  const body = (await res.json().catch(() => ({}))) as GoTrueToken;
  if (!res.ok || !body.access_token) {
    const msg = body.error_description || body.msg || body.error || `Auth failed (${res.status})`;
    throw new AuthError(grant === "refresh_token" ? "SESSION_EXPIRED" : msg);
  }
  return body;
}

export async function signInWithPassword(cfg: GoTrueConfig, email: string, password: string): Promise<Session> {
  return toSession(await tokenRequest(cfg, "password", { email, password }));
}

export async function refreshSession(cfg: GoTrueConfig, refreshToken: string): Promise<Session> {
  return toSession(await tokenRequest(cfg, "refresh_token", { refresh_token: refreshToken }));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- supabase-auth`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add personal-tracker-mcp/src/auth/supabase-auth.ts personal-tracker-mcp/test/supabase-auth.test.ts
git commit -m "feat(mcp): Supabase GoTrue password + refresh client"
```

---

## Task 5: Supabase PostgREST client

**Files:**
- Create: `personal-tracker-mcp/src/data/supabase-rest.ts`
- Test: `personal-tracker-mcp/test/supabase-rest.test.ts`

**Interfaces:**
- Consumes: `Session`, `AuthError`, `refreshSession`, `GoTrueConfig` from `supabase-auth.ts`.
- Produces:
  - `SessionStore = { get(): Session; set(s: Session): void | Promise<void> }`
  - `SupabaseRest = {`
    - `list(table: string, opts?: { eq?: Record<string, string>; order?: string; limit?: number }): Promise<any[]>`
    - `get(table: string, id: string): Promise<any | null>`
    - `insert(table: string, row: Record<string, unknown>): Promise<any>`
    - `patch(table: string, id: string, changes: Record<string, unknown>): Promise<any | null>` }
  - `class RestError extends Error`
  - `makeSupabaseRest(cfg: GoTrueConfig, store: SessionStore): SupabaseRest`
- Notes for later tasks: `insert` POSTs `[row]` to `<table>` with `Prefer: return=representation` and returns `rows[0]`. `patch` PATCHes `<table>?id=eq.<id>` and returns `rows[0] ?? null`. `list` always adds `is_deleted=eq.false` and `select=*`, clamps `limit` to 500 (default 100).

- [ ] **Step 1: Write the failing test — `personal-tracker-mcp/test/supabase-rest.test.ts`**

```ts
import { afterEach, describe, expect, test, vi } from "vitest";
import { AuthError, type Session } from "../src/auth/supabase-auth";
import { makeSupabaseRest } from "../src/data/supabase-rest";

const cfg = { url: "https://x.supabase.co", anonKey: "anon" };
const future = Math.floor(Date.now() / 1000) + 3600;

function store(overrides: Partial<Session> = {}) {
  let s: Session = {
    supabaseUserId: "u1", email: "e", accessToken: "at", refreshToken: "rt",
    expiresAt: future, ...overrides,
  };
  return { get: () => s, set: vi.fn(async (n: Session) => { s = n; }), _peek: () => s };
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

afterEach(() => vi.unstubAllGlobals());

describe("makeSupabaseRest", () => {
  test("list builds the URL: select, is_deleted filter, eq filters, clamped limit", async () => {
    const fetchFn = vi.fn().mockResolvedValue(json(200, [{ id: "1" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    const rows = await rest.list("transactions", { eq: { type: "expense" }, limit: 9999 });
    expect(rows).toEqual([{ id: "1" }]);
    const url = new URL(String(fetchFn.mock.calls[0][0]));
    expect(url.pathname).toBe("/rest/v1/transactions");
    expect(url.searchParams.get("select")).toBe("*");
    expect(url.searchParams.get("is_deleted")).toBe("eq.false");
    expect(url.searchParams.get("type")).toBe("eq.expense");
    expect(url.searchParams.get("limit")).toBe("500");
    const headers = (fetchFn.mock.calls[0][1] as RequestInit).headers as Record<string, string>;
    expect(headers.apikey).toBe("anon");
    expect(headers.Authorization).toBe("Bearer at");
  });

  test("get returns the first row, or null when empty", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(200, [])));
    const rest = makeSupabaseRest(cfg, store());
    expect(await rest.get("accounts", "abc")).toBeNull();
  });

  test("insert POSTs an array and returns the representation row", async () => {
    const fetchFn = vi.fn().mockResolvedValue(json(201, [{ id: "new", name: "HDFC" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    const row = await rest.insert("accounts", { id: "new", name: "HDFC" });
    expect(row).toEqual({ id: "new", name: "HDFC" });
    const init = fetchFn.mock.calls[0][1] as RequestInit;
    expect(init.method).toBe("POST");
    expect(JSON.parse(String(init.body))).toEqual([{ id: "new", name: "HDFC" }]);
    expect((init.headers as Record<string, string>).Prefer).toContain("return=representation");
  });

  test("patch targets id=eq.<id> and returns the row", async () => {
    const fetchFn = vi.fn().mockResolvedValue(json(200, [{ id: "x", is_deleted: true }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    const row = await rest.patch("goals", "x", { is_deleted: true });
    expect(row).toEqual({ id: "x", is_deleted: true });
    const url = new URL(String(fetchFn.mock.calls[0][0]));
    expect(url.searchParams.get("id")).toBe("eq.x");
    expect((fetchFn.mock.calls[0][1] as RequestInit).method).toBe("PATCH");
  });

  test("refreshes the token when the session is within 60s of expiry", async () => {
    const near = Math.floor(Date.now() / 1000) + 30;
    const s = store({ expiresAt: near });
    const fetchFn = vi.fn()
      .mockResolvedValueOnce(json(200, {
        access_token: "at2", refresh_token: "rt2", expires_at: future,
        user: { id: "u1", email: "e" },
      }))
      .mockResolvedValueOnce(json(200, [{ id: "1" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, s);
    await rest.list("accounts");
    expect(s.set).toHaveBeenCalledOnce();
    expect(s._peek().accessToken).toBe("at2");
    expect((fetchFn.mock.calls[1][1] as RequestInit).headers as Record<string, string>).toMatchObject({ Authorization: "Bearer at2" });
  });

  test("retries once on a 5xx then succeeds", async () => {
    const fetchFn = vi.fn()
      .mockResolvedValueOnce(json(503, { message: "upstream" }))
      .mockResolvedValueOnce(json(200, [{ id: "1" }]));
    vi.stubGlobal("fetch", fetchFn);
    const rest = makeSupabaseRest(cfg, store());
    expect(await rest.list("loans")).toEqual([{ id: "1" }]);
    expect(fetchFn).toHaveBeenCalledTimes(2);
  });

  test("maps a 401 to AuthError", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(json(401, { message: "JWT expired" })));
    const rest = makeSupabaseRest(cfg, store());
    await expect(rest.list("loans")).rejects.toThrowError(AuthError);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- supabase-rest`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `personal-tracker-mcp/src/data/supabase-rest.ts`**

```ts
import { AuthError, refreshSession, type GoTrueConfig, type Session } from "../auth/supabase-auth";

export interface SessionStore {
  get(): Session;
  set(s: Session): void | Promise<void>;
}

export interface SupabaseRest {
  list(table: string, opts?: { eq?: Record<string, string>; order?: string; limit?: number }): Promise<any[]>;
  get(table: string, id: string): Promise<any | null>;
  insert(table: string, row: Record<string, unknown>): Promise<any>;
  patch(table: string, id: string, changes: Record<string, unknown>): Promise<any | null>;
}

export class RestError extends Error {}

const REFRESH_SKEW_SECONDS = 60;
const LIMIT_DEFAULT = 100;
const LIMIT_MAX = 500;

export function makeSupabaseRest(cfg: GoTrueConfig, store: SessionStore): SupabaseRest {
  async function bearer(): Promise<string> {
    let s = store.get();
    if (s.expiresAt - Math.floor(Date.now() / 1000) < REFRESH_SKEW_SECONDS) {
      try {
        s = await refreshSession(cfg, s.refreshToken);
        await store.set(s);
      } catch {
        throw new AuthError("SESSION_EXPIRED");
      }
    }
    return s.accessToken;
  }

  async function req(method: string, pathAndQuery: string, body?: unknown): Promise<any[]> {
    const token = await bearer();
    const send = () =>
      fetch(`${cfg.url}/rest/v1/${pathAndQuery}`, {
        method,
        headers: {
          apikey: cfg.anonKey,
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });

    let res = await send();
    if (res.status >= 500) {
      await new Promise((r) => setTimeout(r, 500));
      res = await send();
    }
    if (!res.ok) {
      if (res.status === 401) throw new AuthError("SESSION_EXPIRED");
      const err = (await res.json().catch(() => ({}))) as { message?: string; hint?: string };
      throw new RestError(`Supabase rejected the request (${res.status}): ${err.message || err.hint || res.statusText}`);
    }
    if (res.status === 204) return [];
    return (await res.json()) as any[];
  }

  return {
    async list(table, opts = {}) {
      const q = new URLSearchParams();
      q.set("select", "*");
      q.set("is_deleted", "eq.false");
      for (const [k, v] of Object.entries(opts.eq ?? {})) q.set(k, `eq.${v}`);
      if (opts.order) q.set("order", opts.order);
      q.set("limit", String(Math.min(opts.limit ?? LIMIT_DEFAULT, LIMIT_MAX)));
      return req("GET", `${table}?${q.toString()}`);
    },
    async get(table, id) {
      const rows = await req("GET", `${table}?id=eq.${encodeURIComponent(id)}&select=*&limit=1`);
      return rows[0] ?? null;
    },
    async insert(table, row) {
      const rows = await req("POST", table, [row]);
      return rows[0] ?? row;
    },
    async patch(table, id, changes) {
      const rows = await req("PATCH", `${table}?id=eq.${encodeURIComponent(id)}`, changes);
      return rows[0] ?? null;
    },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- supabase-rest`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
npm run typecheck
git add personal-tracker-mcp/src/data/supabase-rest.ts personal-tracker-mcp/test/supabase-rest.test.ts
git commit -m "feat(mcp): PostgREST client with transparent token refresh + retry"
```

---

## Task 6: Login handler (Hono `/authorize`)

**Files:**
- Create: `personal-tracker-mcp/src/auth/login-handler.ts`
- Test: `personal-tracker-mcp/test/login-handler.test.ts`

**Interfaces:**
- Consumes: `signInWithPassword`, `AuthError` from `supabase-auth.ts`; `Env` from `types.ts`.
- Produces: `loginApp` — a `Hono` instance. Expects `c.env` to carry `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `OAUTH_PROVIDER` (an object with `parseAuthRequest(request): Promise<AuthRequest>`, `lookupClient(id): Promise<unknown | null>`, `completeAuthorization(opts): Promise<{ redirectTo: string }>`), injected by `@cloudflare/workers-oauth-provider` into the `defaultHandler` env.
- Behavior: `GET /authorize` renders the login form with the parsed auth request serialized into a hidden `auth_request` field. `POST /authorize` reads `email`/`password`/`auth_request`, calls `signInWithPassword`, then `completeAuthorization({ request, userId, metadata:{email}, scope, props: session })`, and 302-redirects to `redirectTo`. Bad credentials re-render the form (HTTP 401) with an inline error. Any other path → 404.

- [ ] **Step 1: Write the failing test — `personal-tracker-mcp/test/login-handler.test.ts`**

```ts
import { afterEach, describe, expect, test, vi } from "vitest";
import { loginApp } from "../src/auth/login-handler";

const authReq = { clientId: "c1", redirectUri: "https://claude.ai/cb", scope: ["personal-tracker"], state: "s1" };

function env(overrides: Record<string, unknown> = {}) {
  return {
    SUPABASE_URL: "https://x.supabase.co",
    SUPABASE_ANON_KEY: "anon",
    OAUTH_PROVIDER: {
      parseAuthRequest: vi.fn().mockResolvedValue(authReq),
      lookupClient: vi.fn().mockResolvedValue({ clientId: "c1" }),
      completeAuthorization: vi.fn().mockResolvedValue({ redirectTo: "https://claude.ai/cb?code=abc&state=s1" }),
    },
    ...overrides,
  };
}

function goTrue(status: number, body: unknown) {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } }),
  ));
}

afterEach(() => vi.unstubAllGlobals());

describe("GET /authorize", () => {
  test("renders a form carrying the serialized auth request", async () => {
    const e = env();
    const res = await loginApp.request("https://mcp.example/authorize?client_id=c1", {}, e);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain('name="email"');
    expect(body).toContain('name="password"');
    expect(body).toContain('name="auth_request"');
    expect(e.OAUTH_PROVIDER.parseAuthRequest).toHaveBeenCalled();
  });
});

describe("POST /authorize", () => {
  test("valid credentials complete the grant and 302 to redirectTo", async () => {
    const e = env();
    goTrue(200, { access_token: "at", refresh_token: "rt", expires_at: 1893456000, user: { id: "u1", email: "me@x.com" } });
    const form = new URLSearchParams({ email: "me@x.com", password: "pw", auth_request: JSON.stringify(authReq) });
    const res = await loginApp.request("https://mcp.example/authorize", {
      method: "POST", body: form, headers: { "content-type": "application/x-www-form-urlencoded" },
    }, e);
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toBe("https://claude.ai/cb?code=abc&state=s1");
    const arg = e.OAUTH_PROVIDER.completeAuthorization.mock.calls[0][0];
    expect(arg.userId).toBe("u1");
    expect(arg.props).toMatchObject({ accessToken: "at", refreshToken: "rt", email: "me@x.com" });
  });

  test("bad credentials re-render the form with an error and 401", async () => {
    const e = env();
    goTrue(400, { error_description: "Invalid login credentials" });
    const form = new URLSearchParams({ email: "me@x.com", password: "bad", auth_request: JSON.stringify(authReq) });
    const res = await loginApp.request("https://mcp.example/authorize", {
      method: "POST", body: form, headers: { "content-type": "application/x-www-form-urlencoded" },
    }, e);
    expect(res.status).toBe(401);
    const body = await res.text();
    expect(body).toContain("Invalid login credentials");
    expect(body).toContain('name="password"');
    expect(e.OAUTH_PROVIDER.completeAuthorization).not.toHaveBeenCalled();
  });
});

test("unknown path 404s", async () => {
  const res = await loginApp.request("https://mcp.example/nope", {}, env());
  expect(res.status).toBe(404);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- login-handler`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `personal-tracker-mcp/src/auth/login-handler.ts`**

```ts
import { Hono } from "hono";
import { html, raw } from "hono/html";
import { AuthError, signInWithPassword } from "./supabase-auth";
import type { Env } from "../types";

interface OAuthHelpers {
  parseAuthRequest(request: Request): Promise<any>;
  lookupClient(clientId: string): Promise<unknown | null>;
  completeAuthorization(opts: {
    request: any;
    userId: string;
    metadata?: Record<string, unknown>;
    scope: string[];
    props: Record<string, unknown>;
  }): Promise<{ redirectTo: string }>;
}

type Bindings = Env & { OAUTH_PROVIDER: OAuthHelpers };

export const loginApp = new Hono<{ Bindings: Bindings }>();

loginApp.get("/authorize", async (c) => {
  let authRequest: any;
  try {
    authRequest = await c.env.OAUTH_PROVIDER.parseAuthRequest(c.req.raw);
  } catch (e: any) {
    return c.text(e?.description ?? "Invalid authorization request", 400);
  }
  const client = await c.env.OAUTH_PROVIDER.lookupClient(authRequest.clientId);
  if (!client) return c.text("Unknown client", 400);
  return c.html(page(JSON.stringify(authRequest)));
});

loginApp.post("/authorize", async (c) => {
  const form = await c.req.formData();
  const email = String(form.get("email") ?? "");
  const password = String(form.get("password") ?? "");
  const rawAuth = String(form.get("auth_request") ?? "{}");

  let authRequest: any;
  try {
    authRequest = JSON.parse(rawAuth);
  } catch {
    return c.text("Malformed authorization request", 400);
  }

  try {
    const session = await signInWithPassword(
      { url: c.env.SUPABASE_URL, anonKey: c.env.SUPABASE_ANON_KEY },
      email,
      password,
    );
    const { redirectTo } = await c.env.OAUTH_PROVIDER.completeAuthorization({
      request: authRequest,
      userId: session.supabaseUserId,
      metadata: { email: session.email },
      scope: Array.isArray(authRequest.scope) ? authRequest.scope : ["personal-tracker"],
      props: { ...session },
    });
    return c.redirect(redirectTo, 302);
  } catch (e) {
    const msg = e instanceof AuthError ? e.message : "Sign-in failed. Please try again.";
    return c.html(page(rawAuth, msg), 401);
  }
});

loginApp.all("*", (c) => c.text("Not found", 404));

function page(authRequestJson: string, error?: string) {
  return html`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Connect PersonalTracker</title>
<style>
  body { font: 16px/1.5 system-ui, -apple-system, sans-serif; background: #0f1117;
    color: #e8eaed; display: grid; place-items: center; min-height: 100vh; margin: 0; }
  form { background: #1a1d27; padding: 32px; border-radius: 16px; width: min(360px, 92vw);
    box-shadow: 0 8px 40px rgba(0,0,0,.45); }
  h1 { font-size: 20px; margin: 0 0 4px; }
  p.sub { margin: 0 0 20px; color: #9aa0a6; font-size: 14px; }
  label { display: block; font-size: 13px; margin: 14px 0 4px; color: #c7c9d1; }
  input { width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 8px;
    border: 1px solid #333747; background: #0f1117; color: #e8eaed; font-size: 15px; }
  button { margin-top: 22px; width: 100%; padding: 11px; border: 0; border-radius: 8px;
    background: #4f7cff; color: #fff; font-size: 15px; font-weight: 600; cursor: pointer; }
  .err { margin-top: 14px; color: #ff6b6b; font-size: 13px; }
</style></head><body>
<form method="post" action="/authorize">
  <h1>Connect PersonalTracker</h1>
  <p class="sub">Sign in with your PersonalTracker (Aspyric) account.</p>
  <label for="email">Email</label>
  <input id="email" name="email" type="email" autocomplete="username" required autofocus />
  <label for="password">Password</label>
  <input id="password" name="password" type="password" autocomplete="current-password" required />
  <input type="hidden" name="auth_request" value="${authRequestJson}" />
  ${error ? html`<div class="err">${error}</div>` : raw("")}
  <button type="submit">Sign in</button>
</form></body></html>`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- login-handler`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
npm run typecheck
git add personal-tracker-mcp/src/auth/login-handler.ts personal-tracker-mcp/test/login-handler.test.ts
git commit -m "feat(mcp): Hono login handler completing the OAuth grant via Supabase"
```

---

## Task 7: MCP read tools (`whoami`, `list_records`, `get_record`)

**Files:**
- Create: `personal-tracker-mcp/src/mcp/tools.ts`
- Test: `personal-tracker-mcp/test/tools.test.ts`

**Interfaces:**
- Consumes: `ENTITIES`, `ENTITY_NAMES`, `EntityName` from `entities.ts`; `computeAccountBalance`, `BalanceTxn` from `derive.ts`; `SupabaseRest` from `supabase-rest.ts`; `AuthError` from `supabase-auth.ts`.
- Produces:
  - `ToolDeps = { rest: SupabaseRest; identity: () => { email: string; supabaseUserId: string; connectedAt: string } }`
  - `registerTools(server: McpServerLike, deps: ToolDeps): void` where `McpServerLike = { tool(name: string, description: string, paramsShape: Record<string, unknown>, handler: (args: any) => Promise<ToolResult>): void }`
  - `ToolResult = { content: { type: "text"; text: string }[]; isError?: boolean }`
- Tool result convention: success → `content[0].text` is `JSON.stringify(data, null, 2)`; failure → `isError: true` with a plain-text message. `AuthError` → the message `"Your PersonalTracker session has expired. Reconnect the connector in Claude settings."`

- [ ] **Step 1: Write the failing test — `personal-tracker-mcp/test/tools.test.ts`**

```ts
import { beforeEach, describe, expect, test, vi } from "vitest";
import { registerTools, type ToolDeps } from "../src/mcp/tools";
import { AuthError } from "../src/auth/supabase-auth";

type Handler = (args: any) => Promise<any>;

function harness(rest: Partial<ToolDeps["rest"]>) {
  const handlers = new Map<string, Handler>();
  const server = {
    tool: (name: string, _d: string, _s: unknown, h: Handler) => handlers.set(name, h),
  };
  const deps: ToolDeps = {
    rest: {
      list: vi.fn(), get: vi.fn(), insert: vi.fn(), patch: vi.fn(), ...rest,
    } as ToolDeps["rest"],
    identity: () => ({ email: "me@x.com", supabaseUserId: "u1", connectedAt: "2026-09-08T00:00:00.000Z" }),
  };
  registerTools(server as any, deps);
  return { handlers, deps };
}

const parse = (r: any) => JSON.parse(r.content[0].text);

describe("whoami", () => {
  test("returns the connected identity", async () => {
    const { handlers } = harness({});
    const r = await handlers.get("whoami")!({});
    expect(parse(r)).toMatchObject({ email: "me@x.com", supabaseUserId: "u1" });
  });
});

describe("list_records", () => {
  test("lists a table and strips omitted fields", async () => {
    const list = vi.fn().mockResolvedValue([{ id: "a1", name: "HDFC", enc_ifsc: "SECRET" }]);
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "accounts" });
    expect(list).toHaveBeenCalledWith("accounts", { eq: undefined, limit: undefined });
    expect(parse(r)).toEqual([{ id: "a1", name: "HDFC" }]);
  });

  test("passes exact-match filters through", async () => {
    const list = vi.fn().mockResolvedValue([]);
    const { handlers } = harness({ list });
    await handlers.get("list_records")!({ entity: "transactions", filter: { type: "expense" }, limit: 5 });
    expect(list).toHaveBeenCalledWith("transactions", { eq: { type: "expense" }, limit: 5 });
  });

  test("accounts + with_account_balance attaches a computed calculated_balance", async () => {
    const list = vi.fn(async (t: string) => {
      if (t === "accounts") return [{ id: "A", name: "HDFC", opening_balance: 1000, calculated_balance: 999 }];
      if (t === "transactions") return [{ account_id: "A", to_account_id: null, type: "income", amount: 200, credit_card_id: null, is_external_to_account: false }];
      if (t === "credit_cards") return [];
      return [];
    });
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "accounts", with_account_balance: true });
    expect(parse(r)[0]).toMatchObject({ calculated_balance: 1200, calculated_balance_synced: 999 });
  });

  test("budgets + with_budget_spent recomputes spent_amount from transactions", async () => {
    const list = vi.fn(async (t: string) => {
      if (t === "budgets") return [{ id: "b1", category_id: "food", month_year: "2026-09", monthly_limit: 8000, spent_amount: 0 }];
      if (t === "transactions") return [
        { category_id: "food", type: "expense", amount: 1200, date: "2026-09-03T00:00:00.000Z" },
        { category_id: "food", type: "expense", amount: 800, date: "2026-08-30T00:00:00.000Z" },
      ];
      return [];
    });
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "budgets", with_budget_spent: true });
    expect(parse(r)[0]).toMatchObject({ spent_amount: 1200, spent_amount_synced: 0 });
  });

  test("AuthError becomes the reconnect message", async () => {
    const list = vi.fn().mockRejectedValue(new AuthError("SESSION_EXPIRED"));
    const { handlers } = harness({ list });
    const r = await handlers.get("list_records")!({ entity: "loans" });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/session has expired/i);
  });
});

describe("get_record", () => {
  test("returns { found: false } when missing", async () => {
    const { handlers } = harness({ get: vi.fn().mockResolvedValue(null) });
    const r = await handlers.get("get_record")!({ entity: "goals", id: "nope" });
    expect(parse(r)).toEqual({ found: false });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- tools`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `personal-tracker-mcp/src/mcp/tools.ts` (read tools only for now)**

```ts
import { z } from "zod";
import { AuthError } from "../auth/supabase-auth";
import {
  computeAccountBalance, computeBudgetSpent, type BalanceTxn, type SpentTxn,
} from "../data/derive";
import { ENTITIES, ENTITY_NAMES, type EntityName } from "../data/entities";
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
    spent_amount: computeBudgetSpent({ category_id: b.category_id, month_year: b.month_year }, txns),
  }));
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
        .record(z.string())
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
        const rows = (await rest.list(ENTITIES[entity].table, { eq: filter, limit })) as Record<string, any>[];
        let mapped = rows.map((r) => stripOmitted(entity, r));
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
        const row = (await rest.get(ENTITIES[entity].table, id)) as Record<string, any> | null;
        if (!row) return ok({ found: false });
        let mapped = stripOmitted(entity, row);
        if (entity === "accounts") [mapped] = await attachBalances(rest, [mapped]);
        return ok(mapped);
      } catch (e) {
        return toToolError(e);
      }
    },
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- tools`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
npm run typecheck
git add personal-tracker-mcp/src/mcp/tools.ts personal-tracker-mcp/test/tools.test.ts
git commit -m "feat(mcp): read tools — whoami, list_records, get_record"
```

---

## Task 8: MCP write tools (`create_record`, `update_record`, `delete_record`)

**Files:**
- Modify: `personal-tracker-mcp/src/mcp/tools.ts` (add three tools inside `registerTools`, plus a `zodMsg` helper)
- Modify: `personal-tracker-mcp/test/tools.test.ts` (append describe blocks)

**Interfaces:**
- Consumes: everything from Task 7 plus `crypto.randomUUID()` (global in Workers and Node ≥ 20).
- Produces (behavior other tasks rely on):
  - `create_record({ entity, data })` — validates `data` with `ENTITIES[entity].createSchema`; on failure returns `fail("Invalid <displayName> data: <path> — <message>")`. On success builds `{ id: randomUUID(), ...fixed, ...parsed, created_at, updated_at }`, defaults `transactions.date` to now when absent, calls `rest.insert`, returns the stripped row.
  - `update_record({ entity, id, changes })` — validates with `updateSchema`; empty → `fail("No valid fields to update.")`; else `rest.patch(table, id, { ...parsed, updated_at: now })`, returns stripped row or `{ found: false }`.
  - `delete_record({ entity, id })` — `rest.patch(table, id, { is_deleted: true, deleted_at: now, updated_at: now })`, returns `{ deleted: <bool>, id }`.

- [ ] **Step 1: Append failing tests to `personal-tracker-mcp/test/tools.test.ts`**

```ts
describe("create_record", () => {
  test("rejects invalid data with a field-specific message", async () => {
    const { handlers } = harness({});
    const r = await handlers.get("create_record")!({ entity: "accounts", data: { name: "X", type: "checking" } });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/Invalid account data: type/);
  });

  test("creates a row with id + timestamps and returns it stripped", async () => {
    const insert = vi.fn(async (_t: string, row: any) => ({ ...row, enc_ifsc: "SECRET" }));
    const { handlers } = harness({ insert });
    const r = await handlers.get("create_record")!({
      entity: "accounts",
      data: { name: "HDFC", type: "savingsAccount", opening_balance: 500 },
    });
    const [, row] = insert.mock.calls[0];
    expect(row.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(row).toMatchObject({ name: "HDFC", type: "savingsAccount", opening_balance: 500, is_active: true });
    expect(row.created_at).toEqual(row.updated_at);
    expect(parse(r).enc_ifsc).toBeUndefined();
  });

  test("transactions.date defaults to now when omitted; fixed fields applied", async () => {
    const insert = vi.fn(async (_t: string, row: any) => row);
    const { handlers } = harness({ insert });
    await handlers.get("create_record")!({
      entity: "transactions",
      data: { account_id: "11111111-1111-1111-1111-111111111111", type: "expense", amount: 100 },
    });
    const [, row] = insert.mock.calls[0];
    expect(row.date).toBeTruthy();
    expect(row.sync_status).toBe("synced");
    expect(row.splits).toEqual([]);
  });
});

describe("update_record", () => {
  test("patches only provided fields plus updated_at", async () => {
    const patch = vi.fn(async () => ({ id: "g1", name: "New Goal" }));
    const { handlers } = harness({ patch });
    await handlers.get("update_record")!({ entity: "goals", id: "g1", changes: { name: "New Goal" } });
    const [table, id, body] = patch.mock.calls[0];
    expect([table, id]).toEqual(["goals", "g1"]);
    expect(body.name).toBe("New Goal");
    expect(body.updated_at).toBeTruthy();
  });

  test("empty changes are rejected", async () => {
    const { handlers } = harness({});
    const r = await handlers.get("update_record")!({ entity: "goals", id: "g1", changes: {} });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/No valid fields/);
  });
});

describe("delete_record", () => {
  test("soft-deletes via patch and reports the result", async () => {
    const patch = vi.fn(async () => ({ id: "l1", is_deleted: true }));
    const { handlers } = harness({ patch });
    const r = await handlers.get("delete_record")!({ entity: "loans", id: "l1" });
    const [table, id, body] = patch.mock.calls[0];
    expect([table, id]).toEqual(["loans", "l1"]);
    expect(body).toMatchObject({ is_deleted: true });
    expect(body.deleted_at).toBeTruthy();
    expect(parse(r)).toEqual({ deleted: true, id: "l1" });
  });
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `npm test -- tools`
Expected: FAIL — `handlers.get("create_record")` is `undefined`.

- [ ] **Step 3: Add the write tools + `zodMsg` to `personal-tracker-mcp/src/mcp/tools.ts`**

Add this helper near `stripOmitted`:

```ts
function zodMsg(entity: EntityName, err: z.ZodError): string {
  const i = err.issues[0];
  const path = i.path.join(".") || "(root)";
  return `Invalid ${ENTITIES[entity].displayName} data: ${path} — ${i.message}`;
}
```

Add these three `server.tool(...)` calls at the end of `registerTools`:

```ts
  server.tool(
    "create_record",
    "Create one PersonalTracker record. `data` fields depend on `entity`; on a validation error the message names the offending field.",
    { entity: z.enum(ENTITY_NAMES), data: z.record(z.unknown()) },
    async ({ entity, data }) => {
      const def = ENTITIES[entity];
      const parsed = def.createSchema.safeParse(data);
      if (!parsed.success) return fail(zodMsg(entity, parsed.error));
      const now = new Date().toISOString();
      const row: Record<string, unknown> = {
        id: crypto.randomUUID(),
        ...(def.fixed ?? {}),
        ...parsed.data,
        created_at: now,
        updated_at: now,
      };
      if (entity === "transactions" && !row.date) row.date = now;
      try {
        const created = (await rest.insert(def.table, row)) as Record<string, unknown>;
        return ok(stripOmitted(entity, created));
      } catch (e) {
        return toToolError(e);
      }
    },
  );

  server.tool(
    "update_record",
    "Patch fields on one PersonalTracker record.",
    { entity: z.enum(ENTITY_NAMES), id: z.string(), changes: z.record(z.unknown()) },
    async ({ entity, id, changes }) => {
      const def = ENTITIES[entity];
      const parsed = def.updateSchema.safeParse(changes);
      if (!parsed.success) return fail(zodMsg(entity, parsed.error));
      const fields = parsed.data as Record<string, unknown>;
      if (Object.keys(fields).length === 0) return fail("No valid fields to update.");
      try {
        const updated = (await rest.patch(def.table, id, {
          ...fields,
          updated_at: new Date().toISOString(),
        })) as Record<string, unknown> | null;
        if (!updated) return ok({ found: false });
        return ok(stripOmitted(entity, updated));
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
        const updated = await rest.patch(ENTITIES[entity].table, id, {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tools`
Expected: PASS (Task 7 + Task 8 cases).

- [ ] **Step 5: Typecheck + commit**

```bash
npm run typecheck
git add personal-tracker-mcp/src/mcp/tools.ts personal-tracker-mcp/test/tools.test.ts
git commit -m "feat(mcp): write tools — create_record, update_record, delete_record"
```

---

## Task 9: `add_transaction` tool with name resolution

**Files:**
- Modify: `personal-tracker-mcp/src/mcp/tools.ts` (add `add_transaction` + a `resolveRef` helper)
- Modify: `personal-tracker-mcp/test/tools.test.ts` (append a describe block)

**Interfaces:**
- Consumes: Task 7/8 internals.
- Produces:
  - `add_transaction({ type, amount, account, category?, to_account?, merchant?, note?, date? })` where `type ∈ {"income","expense","transfer"}`, `amount > 0`.
  - Resolution: `account`/`to_account`/`category` accept an id (exact match on `row.id`) or a case-insensitive exact match on `row.name`. Miss → `fail('No <kind> named "X". Available: …')`. Ambiguous (>1 name match) → `fail('Multiple <kind>s named "X" — use its id instead.')`.
  - A `transfer` requires `to_account`; `category` is ignored for transfers.
  - Builds the same transactions row shape as `create_record` (`is_external_to_account:false`, `tags:[]`, `splits:[]`, `sync_status:"synced"`, timestamps), then `rest.insert("transactions", row)`.

- [ ] **Step 1: Append failing tests to `personal-tracker-mcp/test/tools.test.ts`**

```ts
describe("add_transaction", () => {
  const accounts = [
    { id: "a-hdfc", name: "HDFC Savings" },
    { id: "a-cash", name: "Cash" },
    { id: "a-dup", name: "Wallet" },
    { id: "a-dup2", name: "Wallet" },
  ];
  const categories = [{ id: "c-food", name: "Food & Dining" }];

  function restFor() {
    return {
      list: vi.fn(async (t: string) => (t === "accounts" ? accounts : t === "categories" ? categories : [])),
      insert: vi.fn(async (_t: string, row: any) => row),
    };
  }

  test("resolves account + category by name and builds the row", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_transaction")!({
      type: "expense", amount: 500, account: "hdfc savings", category: "Food & Dining", merchant: "Swiggy",
    });
    const [, row] = rest.insert.mock.calls[0];
    expect(row).toMatchObject({
      account_id: "a-hdfc", category_id: "c-food", type: "expense", amount: 500,
      merchant: "Swiggy", to_account_id: null, sync_status: "synced",
    });
    expect(row.date).toBeTruthy();
    expect(parse(r).account_id).toBe("a-hdfc");
  });

  test("accepts an id directly", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    await handlers.get("add_transaction")!({ type: "income", amount: 1000, account: "a-cash" });
    expect(rest.insert.mock.calls[0][1].account_id).toBe("a-cash");
  });

  test("unknown account name lists the candidates", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_transaction")!({ type: "expense", amount: 10, account: "SBI" });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/No account named "SBI"/);
    expect(r.content[0].text).toMatch(/HDFC Savings/);
  });

  test("ambiguous name is rejected", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const r = await handlers.get("add_transaction")!({ type: "expense", amount: 10, account: "Wallet" });
    expect(r.isError).toBe(true);
    expect(r.content[0].text).toMatch(/Multiple accounts named "Wallet"/);
  });

  test("transfer requires to_account and sets to_account_id", async () => {
    const rest = restFor();
    const { handlers } = harness(rest);
    const missing = await handlers.get("add_transaction")!({ type: "transfer", amount: 100, account: "HDFC Savings" });
    expect(missing.isError).toBe(true);
    expect(missing.content[0].text).toMatch(/needs `to_account`/);

    await handlers.get("add_transaction")!({ type: "transfer", amount: 100, account: "HDFC Savings", to_account: "Cash" });
    expect(rest.insert.mock.calls[0][1]).toMatchObject({ account_id: "a-hdfc", to_account_id: "a-cash" });
  });
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `npm test -- tools`
Expected: FAIL — `add_transaction` handler undefined.

- [ ] **Step 3: Add `resolveRef` + the tool to `personal-tracker-mcp/src/mcp/tools.ts`**

Add near the other helpers:

```ts
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
```

Add at the end of `registerTools`:

```ts
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
        const accounts = (await rest.list("accounts", { limit: 500 })) as { id: string; name: string }[];
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
          const cats = (await rest.list("categories", { limit: 500 })) as { id: string; name: string }[];
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test`
Expected: PASS (entire suite).

- [ ] **Step 5: Typecheck + commit**

```bash
npm run typecheck
git add personal-tracker-mcp/src/mcp/tools.ts personal-tracker-mcp/test/tools.test.ts
git commit -m "feat(mcp): add_transaction with account/category name resolution"
```

---

## Task 10: MCP agent + Worker wiring

**Files:**
- Create: `personal-tracker-mcp/src/mcp/agent.ts`
- Modify: `personal-tracker-mcp/src/index.ts` (replace the stub)
- Modify: `personal-tracker-mcp/src/types.ts` (add `AuthProps`)

**Interfaces:**
- Consumes: `registerTools`, `ToolDeps` from `tools.ts`; `makeSupabaseRest` from `supabase-rest.ts`; `Session` from `supabase-auth.ts`; `loginApp` from `login-handler.ts`; `Env` from `types.ts`.
- Produces: `class PersonalTrackerMCP extends McpAgent` (also the DO class named in `wrangler.jsonc`), and the Worker default export (an `OAuthProvider` instance). `PersonalTrackerMCP` is re-exported from `src/index.ts` so the runtime can bind the Durable Object.
- This task has **no unit test** — it is runtime wiring. Its gate is `npm run typecheck` clean plus a manual `wrangler dev` boot check (documented, run in Task 11's integration section).

- [ ] **Step 1: Add `AuthProps` to `personal-tracker-mcp/src/types.ts`**

```ts
import type { Session } from "./auth/supabase-auth";

export type AuthProps = Session;

export interface Env {
  OAUTH_KV: KVNamespace;
  MCP_OBJECT: DurableObjectNamespace;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
}
```

- [ ] **Step 2: Create `personal-tracker-mcp/src/mcp/agent.ts`**

```ts
import { McpAgent } from "agents/mcp";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Session } from "../auth/supabase-auth";
import { makeSupabaseRest } from "../data/supabase-rest";
import type { Env, AuthProps } from "../types";
import { registerTools } from "./tools";

interface AgentState {
  session: Session;
  connectedAt: string;
}

export class PersonalTrackerMCP extends McpAgent<Env, AgentState, AuthProps> {
  server = new McpServer({ name: "personal-tracker", version: "1.0.0" });

  async init(): Promise<void> {
    // Seed persistent state from the OAuth grant on first run in this DO.
    if (!this.state?.session) {
      const p = this.props;
      this.setState({
        session: {
          supabaseUserId: p.supabaseUserId,
          email: p.email,
          accessToken: p.accessToken,
          refreshToken: p.refreshToken,
          expiresAt: p.expiresAt,
        },
        connectedAt: new Date().toISOString(),
      });
    }

    const rest = makeSupabaseRest(
      { url: this.env.SUPABASE_URL, anonKey: this.env.SUPABASE_ANON_KEY },
      {
        get: () => this.state.session,
        set: (s) => this.setState({ ...this.state, session: s }),
      },
    );

    registerTools(this.server as unknown as Parameters<typeof registerTools>[0], {
      rest,
      identity: () => ({
        email: this.state.session.email,
        supabaseUserId: this.state.session.supabaseUserId,
        connectedAt: this.state.connectedAt,
      }),
    });
  }
}
```

> If the installed `agents` version does not expose `this.state` / `this.setState` on `McpAgent`, use the documented persistence primitive for that version (e.g. `this.sql` or `this.ctx.storage`) to store `{ session, connectedAt }` under a single key, keeping the same `get`/`set` closure shape passed to `makeSupabaseRest`. Load the `cloudflare:build-mcp` skill if the API is unclear.

- [ ] **Step 3: Replace `personal-tracker-mcp/src/index.ts`**

```ts
import OAuthProvider from "@cloudflare/workers-oauth-provider";
import { loginApp } from "./auth/login-handler";
import { PersonalTrackerMCP } from "./mcp/agent";
import type { Env } from "./types";

export { PersonalTrackerMCP };

export default new OAuthProvider<Env>({
  apiHandlers: {
    "/mcp": PersonalTrackerMCP.serve("/mcp") as any,
    "/sse": PersonalTrackerMCP.serveSSE("/sse") as any,
  },
  defaultHandler: loginApp as any,
  authorizeEndpoint: "/authorize",
  tokenEndpoint: "/token",
  clientRegistrationEndpoint: "/register",
  scopesSupported: ["personal-tracker"],
});
```

> Verify against installed types: some `@cloudflare/workers-oauth-provider` versions use `apiRoute` + `apiHandler` (single) instead of `apiHandlers` (map), and `McpAgent` may expose `.mount(path)` instead of `.serve()` / `.serveSSE()`. Adjust the two lines accordingly; the rest of the composition is stable. If the provider needs the KV namespace passed explicitly, add `{ kvNamespace: env.OAUTH_KV }` per its README (the binding is named `OAUTH_KV` in `wrangler.jsonc`).

- [ ] **Step 4: Typecheck**

Run: `npm run typecheck`
Expected: no errors. Fix import paths / generic arity against the installed library types until clean.

- [ ] **Step 5: Run the full test suite**

Run: `npm test`
Expected: all prior tests still PASS (no test file imports `agent.ts` / `index.ts`).

- [ ] **Step 6: Commit**

```bash
git add personal-tracker-mcp/src/mcp/agent.ts personal-tracker-mcp/src/index.ts personal-tracker-mcp/src/types.ts
git commit -m "feat(mcp): McpAgent state wiring + OAuthProvider composition"
```

---

## Task 11: README, deploy walkthrough, integration checklist

**Files:**
- Create: `personal-tracker-mcp/README.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Create `personal-tracker-mcp/README.md`**

````markdown
# personal-tracker-mcp

Remote MCP server for the PersonalTracker (Aspyric) app. Lets any Claude client
on your account do CRUD against your finance data, after a one-time web login
backed by Supabase.

Design: `../docs/superpowers/specs/2026-09-08-personal-tracker-mcp-design.md`.

## What it can do

10 entities — `accounts`, `transactions`, `categories`, `credit_cards`, `loans`,
`budgets`, `recurring_payments`, `investments`, `goals`, `companies`.

Tools: `whoami`, `list_records`, `get_record`, `create_record`, `update_record`,
`delete_record`, `add_transaction`.

Not supported: `notes` (encrypted at rest), full card/account numbers, IFSC, CVV
(client-side encrypted — the server has no key). Deletes are soft (recoverable in
the app).

## Prerequisites

- A free Cloudflare account.
- A Claude plan that allows custom connectors (Pro / Max / Team / Enterprise).
- A real PersonalTracker account (email + password). Demo accounts
  (`test@aspyric.app`) are app-local and will not work.

## Deploy (once)

```bash
cd personal-tracker-mcp
npm install
npx wrangler login                            # opens your browser → your Cloudflare account
npx wrangler kv namespace create OAUTH_KV
#   → copy the printed id into wrangler.jsonc  (kv_namespaces[0].id)
npx wrangler deploy
#   → prints https://personal-tracker-mcp.<your-subdomain>.workers.dev
npm test
```

## Connect it to Claude (once)

1. claude.ai → Settings → Connectors → **Add custom connector**.
2. URL: `https://personal-tracker-mcp.<your-subdomain>.workers.dev/mcp`
3. Claude opens a login page → enter your PersonalTracker email + password.
4. Done. The connector now works in the Claude mobile app, desktop app, and web
   for this account.

If the connector ever says the session expired, open its settings in Claude and
reconnect — you'll get the login page again.

## Local development

```bash
cp .dev.vars.example .dev.vars     # values already match the public project
npx wrangler dev                   # serves on http://localhost:8787
```

Exercise it with the MCP Inspector:

```bash
npx @modelcontextprotocol/inspector
# Transport: "Streamable HTTP"  URL: http://localhost:8787/mcp
# It will run the OAuth flow → the login page opens → sign in with your account.
```

## Manual integration checklist (run once after deploy)

With the Inspector connected to the deployed URL and signed in:

- [ ] `whoami` → shows your email + `supabaseUserId`.
- [ ] `list_records { "entity": "accounts", "with_account_balance": true }` → your
      accounts, each with `calculated_balance` and `calculated_balance_synced`.
- [ ] `create_record { "entity": "categories", "data": { "name": "MCP Test", "type": "expense" } }`
      → returns the new row with an `id`.
- [ ] `get_record { "entity": "categories", "id": "<that id>" }` → same row.
- [ ] `update_record { "entity": "categories", "id": "<id>", "changes": { "icon": "gift" } }`
      → `icon` changed.
- [ ] `add_transaction { "type": "expense", "amount": 1, "account": "<one of your account names>", "category": "MCP Test", "merchant": "inspector" }`
      → returns a transaction row; check it appears in the app.
- [ ] `delete_record { "entity": "transactions", "id": "<that transaction id>" }` → `{ "deleted": true }`.
- [ ] `delete_record { "entity": "categories", "id": "<id>" }` → cleanup.
- [ ] Open the app on the phone/simulator → confirm the test category and
      transaction are gone (soft-deleted) and nothing else changed.

## How auth works

`@cloudflare/workers-oauth-provider` runs the OAuth 2.1 flow Claude's connector
needs (dynamic client registration, PKCE, discovery docs). The `/authorize` page
validates your email + password against Supabase GoTrue and stashes the Supabase
session in the encrypted OAuth grant. Tool calls use your Supabase access token
against PostgREST; Row-Level Security limits every read/write to your rows. The
access token is refreshed automatically; the refresh token lasts as long as the
connector is used at least monthly. No Cloudflare secrets, no service-role key.
````

- [ ] **Step 2: Full verification**

Run (from `personal-tracker-mcp/`):
```bash
npm test
npm run typecheck
```
Expected: all tests pass, no type errors.

- [ ] **Step 3: Commit**

```bash
git add personal-tracker-mcp/README.md
git commit -m "docs(mcp): deploy + connect walkthrough and integration checklist"
```

---

## Execution deviations (recorded 2026-09-09, all 11 tasks complete)

- **zod 4, not 3.** `agents@0.22` peer-requires `zod@^4`; `@modelcontextprotocol/sdk@1.30` accepts it. Consequences applied throughout:
  - `z.record(z.string())` → `z.record(z.string(), z.string())` / `z.record(z.string(), z.unknown())` (two-arg form).
  - `z.string().uuid()` → `z.guid()` for `account_id` / `to_account_id` — Postgres `uuid` columns accept any RFC-shaped value and `crypto.randomUUID()` always passes; zod 4's `.uuid()` enforces version/variant and rejected valid ids.
  - `EntityDef.createSchema/updateSchema` typed `z.ZodType` (not `z.ZodTypeAny`).
- **`update_record` defaults bug fixed.** `createSchema.partial()` still injects `.default()` values for absent keys, which would clobber unrelated columns. `update_record` now forwards only the keys the caller actually supplied. Extra test added.
- **No separate Durable Object state.** The agent keeps the session in `this.props` and persists refreshed tokens via `McpAgent.updateProps(...)` (the library's documented primitive) rather than `this.setState`. `AuthProps = Session & { connectedAt: string } & Record<string, unknown>` (index signature satisfies McpAgent's `Props` constraint; `connectedAt` set at grant time in the login handler).
- **No `OAUTH_ENCRYPTION_KEY` secret** (already removed from the spec pre-execution) — `@cloudflare/workers-oauth-provider@0.10` manages its own key in KV.
- **Test-helper fix:** GoTrue/REST fetch stubs must return a *fresh* `Response` per call (a body can only be read once).
- **Task 10** carries `as never` casts on `apiHandlers` / `defaultHandler` to bridge Hono's and `McpAgent.serve()`'s handler types to `OAuthProviderOptions`; verified with `wrangler deploy --dry-run` (builds clean, 611 KiB gzip — within the free-plan limit).

## Post-implementation (manual, by the user)

These require the user's Cloudflare account and are **not** code tasks — the
implementer stops after Task 11 and hands this list back:

1. `cd personal-tracker-mcp && npm install`
2. `npx wrangler login`
3. `npx wrangler kv namespace create OAUTH_KV` → paste id into `wrangler.jsonc`
4. `npx wrangler deploy` → note the `workers.dev` URL
5. Add the custom connector in claude.ai with `<url>/mcp`, sign in
6. Walk the README "Manual integration checklist"
