-- 0007_accounts_sort_order.sql
--
-- User-reorderable Accounts list: a plain display-position column, lower
-- sorts first. Every account starts at 0 until the user actually drags to
-- reorder (see FinanceNotifier.accountsWithCalculatedBalances /
-- reorderAccounts in the app) — no backfill needed, existing rows keep
-- their current relative order via the createdAt tiebreak client-side.
--
-- Apply with:  supabase db push   (or paste into the SQL editor)

alter table public.accounts
  add column if not exists sort_order integer not null default 0;
