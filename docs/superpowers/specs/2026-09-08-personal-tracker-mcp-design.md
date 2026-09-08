# PersonalTracker MCP Server — Design

**Date:** 2026-09-08
**Status:** Approved
**Folder:** `personal-tracker-mcp/` (repo root)

## Goal

A remote MCP server that lets any Claude client on the user's account (mobile,
web, desktop) perform full CRUD against the Aspyric / PersonalTracker data model.
It authenticates the user through a web login (Supabase email/password) via the
standard MCP OAuth flow, then performs reads/writes against the app's existing
Supabase project under that user's identity, with row-level security doing the
per-user isolation.

## Constraints

- **Free only.** Cloudflare Workers free plan (100k req/day), Workers KV free
  plan (100k reads, 1k writes/day, 1 GB), `workers.dev` subdomain, existing
  Supabase project. No paid services, no credit card.
- **No service-role key.** All Supabase access uses the signed-in user's access
  token + the publishable anon key. RLS (`auth.uid() = user_id`) is the entire
  authorization model — identical to the Flutter app.
- **Sign-in only.** No sign-up or password reset in the MCP; those stay in the
  app. The user already has a real Supabase account.
- **No encrypted fields.** `enc_account_number`, `enc_ifsc`, and card PAN/CVV-ish
  fields require the client-side cipher key the server cannot hold. Reads omit
  them; writes reject them.
- **Scope:** all 11 entities — accounts, transactions, credit_cards, loans,
  budgets, goals, categories, investments, companies, recurring_payments, notes.

## Prerequisites (outside our control)

- A free Cloudflare account (`ramagrawal0610@gmail.com`).
- A Claude plan that supports custom connectors (Pro/Max/Team/Enterprise).
- The app's Supabase project stays reachable: `https://zztvtryevtzqmlfgiiir.supabase.co`,
  publishable key `sb_publishable_3TVjGyvtiCIUMkdZNOJMQw_PDC-slq_` (both already
  shipped in the public Flutter binary).

## Architecture

One Cloudflare Worker (TypeScript) composing three parts:

1. **`OAuthProvider`** (`@cloudflare/workers-oauth-provider`) wraps everything and
   owns `/authorize`, `/token`, `/register`, and the `/.well-known/oauth-*`
   discovery docs — the surface Claude's connector requires (DCR + PKCE).
2. **Login handler** — a small Hono app the provider delegates to for
   `/authorize`: `GET` renders an inline-styled email+password form, `POST`
   validates against Supabase GoTrue and completes the grant.
3. **MCP server** — an `McpAgent` (`agents` package) mounted at `/mcp` and `/sse`,
   behind the OAuth provider. Every tool handler receives `this.props` — the
   decrypted per-user grant: `{ supabaseUserId, email, accessToken,
   refreshToken, expiresAt }`.

**Storage:** one KV namespace `OAUTH_KV` used by the provider for client
registrations, auth codes, encrypted grants, and tokens. No database of our own.

### Folder layout

```
personal-tracker-mcp/
  src/
    index.ts             # Worker entry: OAuthProvider wiring
    auth/
      login-handler.ts   # Hono: GET/POST /authorize + login page HTML
      supabase-auth.ts   # GoTrue: password grant + token refresh
    mcp/
      agent.ts           # McpAgent subclass; registers tools
      tools.ts           # the 7 tool definitions
    data/
      supabase-rest.ts   # PostgREST client; transparent token refresh
      entities.ts        # registry: table, Zod schemas, field map per entity
      derive.ts          # account-balance computation (ported from FinanceState)
    types.ts
  test/
    entities.test.ts
    derive.test.ts
    supabase-rest.test.ts
    login-handler.test.ts
  wrangler.jsonc
  package.json
  tsconfig.json
  vitest.config.ts
  .dev.vars.example
  README.md
```

### Data flow for one tool call

1. Claude client → `POST /mcp` with `Authorization: Bearer <mcp-token>` + tool call.
2. `OAuthProvider` validates the token, decrypts the grant → `props`.
3. Tool handler calls `supabaseRest(props, …)`.
4. The client checks `props.expiresAt`; if `expiresAt - now < 60s` it refreshes
   via the stored Supabase refresh token and persists new tokens back to KV
   (`this.updateProps`).
5. `fetch('https://…supabase.co/rest/v1/<table>?…', { headers: { apikey,
   Authorization: Bearer <supabase access token> } })`.
6. RLS scopes rows to `props.supabaseUserId`. Response mapped through the
   entity field map → returned to Claude.

## Auth flow

### One-time connector setup

claude.ai → Settings → Connectors → *Add custom connector* →
`https://personal-tracker-mcp.<subdomain>.workers.dev/mcp`. Claude reads
`/.well-known/oauth-protected-resource`, discovers the auth server, registers
itself (DCR, stored in KV), starts OAuth.

### Login flow (on connect; again only if the refresh token is revoked)

1. Claude opens a browser tab → `GET /authorize?response_type=code&client_id=…&code_challenge=…&state=…`.
2. `OAuthProvider` validates params, hands to the login handler → minimal HTML
   page (heading, email, password, Sign in). OAuth request params ride in a
   signed hidden field so they survive the POST.
3. Submit → `POST /authorize` → `POST https://…supabase.co/auth/v1/token?grant_type=password`
   with `{ email, password }` + `apikey`.
   - Failure → re-render the form with an inline error (GoTrue rate-limits).
   - Success → `{ access_token, refresh_token, expires_at, user: { id, email } }`.
4. Handler calls `completeAuthorization({ userId: user.id, metadata: { email },
   props: { supabaseUserId, email, accessToken, refreshToken, expiresAt } })`.
   Provider mints an MCP auth code, redirects to Claude with `code` + `state`.
5. Claude exchanges at `POST /token` (PKCE verifier) → opaque MCP access token +
   refresh token. Provider encrypts `props` into KV keyed by the token.
6. Every later tool call carries the MCP access token; provider decrypts `props`.

### Token lifetimes

- **Supabase access token** (~1 h): refreshed proactively by `supabase-rest.ts`
  when within 60 s of expiry, via `grant_type=refresh_token`; new tokens written
  back into `props`.
- **Supabase refresh token** (long-lived, rotates on use): never lapses if the
  connector is used at least monthly. If it does, the next call returns
  "session expired — reconnect"; Claude re-triggers OAuth on the 401.
- **MCP tokens:** managed by `workers-oauth-provider` defaults.

### Stored where

- **KV:** OAuth client registrations, short-lived auth codes, encrypted grants
  (`supabaseUserId`, `email`, both Supabase tokens, `expiresAt`), MCP tokens.
- **`wrangler.jsonc` (committed):** `SUPABASE_URL`, `SUPABASE_ANON_KEY` (both
  already public).
- **`wrangler secret` (never committed):** `OAUTH_ENCRYPTION_KEY` (pinned for
  reproducibility).
- The password is never stored or logged — forwarded once to GoTrue over TLS.

## Tool & schema layer

### The 7 tools

| Tool | Input | Behavior |
|---|---|---|
| `list_records` | `entity`, `filter?`, `limit?` (def 100, cap 500) | Mapped rows, `is_deleted=false`, encrypted fields omitted. Per-entity light filters. |
| `get_record` | `entity`, `id` | One record or `{ found: false }`. |
| `create_record` | `entity`, `data` (discriminated union on `entity`) | Generate UUID `id`, set `created_at`/`updated_at`, upsert, return row. |
| `update_record` | `entity`, `id`, `changes` (partial per-entity schema) | Fetch → merge → bump `updated_at` → upsert. |
| `delete_record` | `entity`, `id` | Soft delete: upsert `{ is_deleted:true, deleted_at:now, updated_at:now }`. |
| `add_transaction` | `type` (`income`/`expense`/`transfer`), `amount`, `account` (name/id), `category?` (name/id), `to_account?`, `merchant?`, `note?`, `date?` | Resolve names → ids (case-insensitive; error with candidates on miss/ambiguity; never guess). Build the transactions row(s). |
| `whoami` | — | `{ email, supabaseUserId, connectedAt }`. |

### Entity registry (`data/entities.ts`)

One object per entity:

```ts
{
  table: 'accounts',
  displayName: 'account',
  rowSchema,        // full row (reads / mapping)
  createSchema,     // user-facing fields only — no id/timestamps/encrypted/derived
  updateSchema,     // createSchema.partial()
  omitFields: ['enc_account_number', 'enc_ifsc'],
  derive?: (row, ctx) => Promise<row>,   // optional post-read hook
}
```

Enum values (`AccountType`, `TransactionType`, `PaymentFrequency`,
`InvestmentType`, category `type`, card `network` / `card_type`, note `color`)
copied verbatim from `lib/core/constants/app_constants.dart` and the migrations,
with a parity test asserting the hard-coded lists match.

### Conventions

- **Field naming:** DB columns stay **snake_case** in the tool API
  (`opening_balance`, `monthly_emi`, `next_due_date`) — 1:1 with the schema, no
  translation layer that can drift.
- **Dates:** ISO-8601 strings in and out (`timestamptz` in the DB).
- **IDs:** server generates `crypto.randomUUID()` for new rows. `user_id` is
  never sent — the DB column defaults to `auth.uid()`.
- **Deletes:** soft only (tombstone), matching the app; recoverable via the app
  or a later `restore` tool.

### Excluded from v1

`enc_account_number`, `enc_ifsc`, card PAN/CVV fields, `user_settings`.

## Derived values

Only **account balance** is genuinely derived. `credit_cards.current_outstanding`,
`goals.current_saved_amount`, `investments.current_value`, `budgets.spent_amount`
are stored on the row.

- Account `list`/`get` attach a computed `calculated_balance` via the `derive`
  hook: fetch that account's non-deleted transactions and fold them (`+amount`
  income, `-amount` expense, transfer in/out by `account_id` / `to_account_id`)
  — a direct port of `FinanceState.accountsWithCalculatedBalances` in a pure,
  unit-tested `derive.ts`. The stored column is also returned as
  `calculated_balance_synced` to expose drift.
- `list_records{ entity:'budgets', filter:{ with_spent:true } }` recomputes
  `spent_amount` from that `month_year` + `category_id`'s transactions. Opt-in,
  off by default.
- Everything else: returned straight from the row.
- No pagination in v1: `limit` default 100, hard cap 500.

## Error handling

- **Session expired / revoked** → MCP error "Your PersonalTracker session has
  expired. Reconnect the connector in Claude settings." Provider returns 401;
  Claude re-runs OAuth.
- **Validation** → Zod errors flattened to `"Invalid <entity> data: <field>
  <message>"`, returned as a tool error (not a throw) so the assistant retries.
- **Name resolution** (`add_transaction`) → miss: `"No account named 'X' — did
  you mean: …"`; ambiguous: candidate list. Never guesses.
- **PostgREST failure** → surface `status` + PostgREST `message` / `hint`,
  prefixed `"Supabase rejected the write: …"`. RLS violations read as permission
  errors.
- **Network / 5xx** → one retry with 500 ms backoff, then
  `"Couldn't reach Supabase, try again."`
- No partial application — each tool is a single upsert, except an
  `add_transaction` transfer (two rows): if the second fails, the first is
  soft-deleted and the failure reported.
- Errors → `console.error` (`wrangler tail`). Never log tokens, passwords, or
  full rows.

## Testing

### Unit (vitest, `npm test`)

- `entities.test.ts` — each entity's `createSchema` accepts a valid fixture,
  rejects a bad one; enum parity with hard-coded Dart-constant lists.
- `derive.test.ts` — balance folding: opening only, +income, -expense, transfers
  both directions, deleted-txn exclusion.
- `supabase-rest.test.ts` — mocked `fetch`: URL/headers correct, refresh fires
  near expiry, 5xx retried once, RLS error mapped.
- `login-handler.test.ts` — mocked GoTrue: success completes authorization, bad
  creds re-render with error, OAuth params survive the POST round-trip.

### Integration (manual; documented in README)

`wrangler dev` + `npx @modelcontextprotocol/inspector` → real OAuth against
Supabase with the real account → create → list → get → update → delete for one
entity + `add_transaction` with name resolution + `whoami`. Test rows
soft-deleted after.

No live Supabase in unit tests.

## Deployment (what the user runs)

```bash
cd personal-tracker-mcp
npm install
npx wrangler login
npx wrangler kv namespace create OAUTH_KV        # paste id into wrangler.jsonc
openssl rand -hex 32 | npx wrangler secret put OAUTH_ENCRYPTION_KEY
npx wrangler deploy                              # prints the workers.dev URL
npm test
```

Then claude.ai → Settings → Connectors → Add custom connector →
`https://…workers.dev/mcp` → login page → Supabase email + password → connected
on every device on the account.

Local dev: `cp .dev.vars.example .dev.vars`, fill the two Supabase values + a dev
encryption key, `npx wrangler dev`.

## Out of scope for v1 (possible follow-ups)

- `restore` tool (un-tombstone a soft-deleted row).
- `user_settings` read/write.
- Encrypted-field writes (would need a companion cipher mechanism).
- Pagination / cursoring on reads.
- Domain helpers beyond `add_transaction` (e.g. `pay_card_bill`,
  `add_funds_to_goal`) — trivial to add on the same CRUD base.
- A remote/stdio dual transport (currently HTTP-only).
