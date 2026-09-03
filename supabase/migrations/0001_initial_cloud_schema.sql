-- 0001_initial_cloud_schema.sql
--
-- Cloud mirror of the two tables the app currently pushes to Supabase
-- (see lib/core/services/supabase_service.dart -> syncLocalDataToCloud and
-- lib/core/services/edge_function_service.dart -> syncLedger).
--
-- The local source of truth is the on-device SQLite (Drift) database; this is
-- a per-user backup/sync copy. Every row is owned by the authenticated user
-- via `user_id`, which defaults to `auth.uid()` so clients never send it, and
-- Row-Level Security makes each user's rows invisible to everyone else.
--
-- Apply with:  supabase db push      (or paste into the SQL editor)

-- ---------------------------------------------------------------------------
-- accounts
-- ---------------------------------------------------------------------------
create table if not exists public.accounts (
  id                  uuid primary key,
  user_id             uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name                text not null,
  type                text not null,
  bank                text,
  opening_balance     double precision not null default 0,
  calculated_balance  double precision not null default 0,
  currency            text not null default 'INR',
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists accounts_user_id_idx on public.accounts (user_id);

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
create table if not exists public.transactions (
  id              uuid primary key,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  account_id      uuid not null references public.accounts (id) on delete cascade,
  to_account_id   uuid references public.accounts (id) on delete set null,
  type            text not null,
  amount          double precision not null,
  category_id     text,
  merchant        text,
  date            timestamptz not null,
  description     text,
  notes           text,
  credit_card_id  text,
  loan_id         text,
  sync_status     text not null default 'synced',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists transactions_user_id_idx on public.transactions (user_id);
create index if not exists transactions_account_id_idx on public.transactions (account_id);
create index if not exists transactions_date_idx on public.transactions (user_id, date desc);

-- ---------------------------------------------------------------------------
-- keep updated_at fresh on every write
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists accounts_set_updated_at on public.accounts;
create trigger accounts_set_updated_at
  before update on public.accounts
  for each row execute function public.set_updated_at();

drop trigger if exists transactions_set_updated_at on public.transactions;
create trigger transactions_set_updated_at
  before update on public.transactions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row-Level Security: a user only ever sees / writes their own rows
-- ---------------------------------------------------------------------------
alter table public.accounts     enable row level security;
alter table public.transactions enable row level security;

drop policy if exists "accounts_owner_all" on public.accounts;
create policy "accounts_owner_all"
  on public.accounts
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "transactions_owner_all" on public.transactions;
create policy "transactions_owner_all"
  on public.transactions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
