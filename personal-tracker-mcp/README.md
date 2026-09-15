# personal-tracker-mcp

Remote MCP server for the PersonalTracker (Aspyric) app. Lets any Claude client
on your account do CRUD against your finance data, after a one-time web login
backed by Supabase.

Design: [`../docs/superpowers/specs/2026-09-08-personal-tracker-mcp-design.md`](../docs/superpowers/specs/2026-09-08-personal-tracker-mcp-design.md).

## What it can do

13 entities — `accounts`, `transactions`, `categories`, `credit_cards`, `loans`,
`budgets`, `recurring_payments`, `investments`, `goals`, `companies`, `people`,
`split_expenses`, `split_participants`.

Tools:

| Tool | Purpose |
|---|---|
| `whoami` | Which account this connector is signed in as. |
| `list_records` | List one entity (deleted rows excluded). `accounts` + `with_account_balance` attaches a live-computed `calculated_balance`; `budgets` + `with_budget_spent` recomputes `spent_amount`. |
| `get_record` | One record by id. |
| `create_record` | Create a record; `data` is validated per entity (the error names the bad field). |
| `update_record` | Patch fields on a record. |
| `delete_record` | Soft-delete (recoverable in the app). |
| `add_transaction` | Add income / expense / transfer, resolving account & category by name. |

Not supported: `notes` (encrypted at rest), full card/account numbers, IFSC, CVV
(client-side encrypted — the server has no key). Deletes are soft.

## Prerequisites

- A free Cloudflare account.
- A Claude plan that allows custom connectors (Pro / Max / Team / Enterprise).
- A real PersonalTracker account (email + password). Demo accounts
  (`test@aspyric.app`) are app-local and will not work.

## Deploy (once)

```bash
cd personal-tracker-mcp
npm install
npx wrangler login                            # opens your browser -> your Cloudflare account
npx wrangler kv namespace create OAUTH_KV
#   -> copy the printed id into wrangler.jsonc  (kv_namespaces[0].id)
npx wrangler deploy
#   -> prints https://personal-tracker-mcp.<your-subdomain>.workers.dev
npm test
```

The `.dev` build is ~0.6 MB gzipped — inside the Workers free-plan limit.
SQLite-backed Durable Objects (used for MCP session state) are free-plan
eligible. No Worker secrets are needed.

## Connect it to Claude (once)

1. claude.ai -> Settings -> Connectors -> **Add custom connector**.
2. URL: `https://personal-tracker-mcp.<your-subdomain>.workers.dev/mcp`
3. Claude opens a login page -> enter your PersonalTracker email + password.
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
# Transport: "Streamable HTTP"   URL: http://localhost:8787/mcp
# It runs the OAuth flow -> the login page opens -> sign in with your account.
```

## Manual integration checklist (run once after deploy)

With the Inspector connected to the deployed URL and signed in:

- [ ] `whoami` -> shows your email + `supabaseUserId`.
- [ ] `list_records { "entity": "accounts", "with_account_balance": true }` -> your
      accounts, each with `calculated_balance` and `calculated_balance_synced`.
- [ ] `create_record { "entity": "categories", "data": { "name": "MCP Test", "type": "expense" } }`
      -> returns the new row with an `id`.
- [ ] `get_record { "entity": "categories", "id": "<that id>" }` -> same row.
- [ ] `update_record { "entity": "categories", "id": "<id>", "changes": { "icon": "gift" } }`
      -> `icon` changed, other fields untouched.
- [ ] `add_transaction { "type": "expense", "amount": 1, "account": "<one of your account names>", "category": "MCP Test", "merchant": "inspector" }`
      -> returns a transaction row; check it appears in the app.
- [ ] `delete_record { "entity": "transactions", "id": "<that transaction id>" }` -> `{ "deleted": true }`.
- [ ] `delete_record { "entity": "categories", "id": "<id>" }` -> cleanup.
- [ ] Open the app -> confirm the test category and transaction are gone
      (soft-deleted) and nothing else changed.

## How auth works

`@cloudflare/workers-oauth-provider` runs the OAuth 2.1 flow Claude's connector
needs (dynamic client registration, PKCE, discovery docs). The `/authorize` page
validates your email + password against Supabase GoTrue and stashes the Supabase
session in the encrypted OAuth grant. Tool calls use your Supabase access token
against PostgREST; Row-Level Security limits every read/write to your rows. The
access token is refreshed automatically and the new tokens are persisted for the
session (`McpAgent.updateProps`); the refresh token lasts as long as the
connector is used at least monthly. No Cloudflare secrets, no service-role key.

## Project layout

```
src/
  index.ts             OAuthProvider composition (Worker entry)
  types.ts             Env, AuthProps
  auth/
    supabase-auth.ts   GoTrue password + refresh
    login-handler.ts   Hono /authorize page + grant completion
  data/
    entities.ts        per-entity Zod schemas + enum constants
    derive.ts          account-balance + budget-spent (ported from the app)
    supabase-rest.ts   PostgREST client with transparent token refresh + retry
  mcp/
    tools.ts           the 7 tool definitions
    agent.ts           McpAgent subclass (Durable Object)
test/                  vitest unit tests (mocked fetch; no live Supabase)
```
