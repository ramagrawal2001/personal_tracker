-- 0002_sync_all_entities.sql
--
-- Extends the cloud mirror from 2 tables (0001) to the full app data model:
-- every local Drift entity + a per-user settings row. Backward compatible —
-- no client references these tables until the sync layer ships.
--
-- Conventions (same as 0001, applied to every table):
--   * user_id uuid not null default auth.uid() references auth.users(id) on delete cascade
--   * composite primary key (user_id, id) so constant ids (e.g. default category
--     ids "cat_food") never collide between users, and mixed local id schemes
--     (uuid vs "cat_*") are fine because id is text
--   * NO cross-entity foreign keys — a child row (transaction) can sync before
--     its parent (account); ordering/partial-failure resilience
--   * is_deleted / deleted_at tombstones — deletes are LWW upserts, never hard
--     deletes, so an offline device cannot resurrect a removed row
--   * set_updated_at() BEFORE UPDATE trigger (defined in 0001) keeps updated_at
--     server-authoritative for last-writer-wins
--   * RLS "<t>_owner_all" FOR ALL USING/WITH CHECK (auth.uid() = user_id)
--   * <t>_user_id_idx and <t>_watermark_idx (user_id, updated_at desc)
--   * replica identity full + added to the supabase_realtime publication so
--     realtime change payloads carry the whole row (needed for tombstone deletes)
--
-- Apply with:  supabase db push      (or paste into the SQL editor)

-- ===========================================================================
-- 1. Bring the existing 0001 tables up to the new conventions
-- ===========================================================================

alter table public.accounts
  add column if not exists account_number_last4 text,
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz;

alter table public.transactions
  add column if not exists tags jsonb not null default '[]'::jsonb,
  add column if not exists splits jsonb not null default '[]'::jsonb,
  add column if not exists attachment_path text,
  add column if not exists investment_id text,
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz;

-- Drop cross-entity FKs (kept ids as plain text; see header rationale).
alter table public.transactions drop constraint if exists transactions_account_id_fkey;
alter table public.transactions drop constraint if exists transactions_to_account_id_fkey;

-- Widen id / reference columns to text and move to composite PKs.
-- (No-ops on a fresh 0002 apply where 0001 already ran; guarded for re-runs.)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'accounts'
      and column_name = 'id' and data_type = 'uuid'
  ) then
    alter table public.accounts     alter column id type text using id::text;
    alter table public.transactions alter column id type text using id::text;
    alter table public.transactions alter column account_id type text using account_id::text;
    alter table public.transactions alter column to_account_id type text using to_account_id::text;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.accounts'::regclass and contype = 'p'
      and pg_get_constraintdef(oid) = 'PRIMARY KEY (user_id, id)'
  ) then
    alter table public.accounts     drop constraint if exists accounts_pkey;
    alter table public.accounts     add  constraint accounts_pkey primary key (user_id, id);
    alter table public.transactions drop constraint if exists transactions_pkey;
    alter table public.transactions add  constraint transactions_pkey primary key (user_id, id);
  end if;
end $$;

create index if not exists accounts_watermark_idx     on public.accounts     (user_id, updated_at desc);
create index if not exists transactions_watermark_idx on public.transactions (user_id, updated_at desc);

alter table public.accounts     replica identity full;
alter table public.transactions replica identity full;

-- ===========================================================================
-- 2. Eight new entity tables
-- ===========================================================================

-- --------------------------------------------------------------------------
create table if not exists public.categories (
  id          text not null,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null,
  parent_id   text,
  type        text not null,
  icon        text not null default 'tag',
  color_hex   text not null default '0xFF6366F1',
  is_deleted  boolean not null default false,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (user_id, id)
);

-- --------------------------------------------------------------------------
create table if not exists public.credit_cards (
  id                   text not null,
  user_id              uuid not null default auth.uid() references auth.users (id) on delete cascade,
  card_type            text not null default 'credit',
  name                 text not null,
  bank                 text not null default '',
  last4                text not null default '',
  network              text not null default 'visa',
  cardholder_name      text not null default '',
  expiry_month         integer,
  expiry_year          integer,
  color_preset         text not null default 'midnight',
  is_virtual           boolean not null default false,
  notes                text,
  credit_limit         double precision not null default 0,
  current_outstanding  double precision not null default 0,
  statement_day        integer not null default 1,
  due_day              integer not null default 15,
  linked_account_id    text,
  balance              double precision,
  currency             text,
  is_deleted           boolean not null default false,
  deleted_at           timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  primary key (user_id, id)
);

-- --------------------------------------------------------------------------
create table if not exists public.loans (
  id                       text not null,
  user_id                  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name                     text not null,
  provider                 text not null default '',
  principal_amount         double precision not null default 0,
  outstanding_amount       double precision not null default 0,
  interest_rate            double precision not null default 0,
  monthly_emi              double precision not null default 0,
  due_day                  integer not null default 1,
  start_date               timestamptz not null default now(),
  remaining_tenure_months  integer not null default 0,
  is_deleted               boolean not null default false,
  deleted_at               timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  primary key (user_id, id)
);

-- --------------------------------------------------------------------------
create table if not exists public.budgets (
  id             text not null,
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category_id    text not null,
  monthly_limit  double precision not null default 0,
  month_year     text not null,
  spent_amount   double precision not null default 0,
  is_deleted     boolean not null default false,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (user_id, id)
);

-- --------------------------------------------------------------------------
create table if not exists public.recurring_payments (
  id             text not null,
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title          text not null,
  amount         double precision not null default 0,
  frequency      text not null default 'monthly',
  next_due_date  timestamptz not null default now(),
  category_id    text,
  account_id     text,
  is_auto_pay    boolean not null default false,
  is_deleted     boolean not null default false,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (user_id, id)
);

-- --------------------------------------------------------------------------
create table if not exists public.investments (
  id                  text not null,
  user_id             uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name                text not null,
  type                text not null default 'other',
  invested_amount     double precision not null default 0,
  current_value       double precision not null default 0,
  monthly_sip_amount  double precision not null default 0,
  sip_day             integer not null default 1,
  is_deleted          boolean not null default false,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  primary key (user_id, id)
);

-- --------------------------------------------------------------------------
create table if not exists public.goals (
  id                    text not null,
  user_id               uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name                  text not null,
  target_amount         double precision not null default 0,
  current_saved_amount  double precision not null default 0,
  target_date           timestamptz,
  icon                  text not null default 'target',
  color_hex             text not null default '0xFF6366F1',
  is_deleted            boolean not null default false,
  deleted_at            timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  primary key (user_id, id)
);

-- --------------------------------------------------------------------------
create table if not exists public.notes (
  id               text not null,
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title            text not null default '',
  body             text not null default '',
  color            text not null default 'defaultColor',
  is_pinned        boolean not null default false,
  is_archived      boolean not null default false,
  is_checklist     boolean not null default false,
  checklist_items  jsonb not null default '[]'::jsonb,
  labels           jsonb not null default '[]'::jsonb,
  is_deleted       boolean not null default false,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  primary key (user_id, id)
);

-- ===========================================================================
-- 3. Per-user settings (single row keyed by user_id; biometric stays local)
-- ===========================================================================
create table if not exists public.user_settings (
  user_id                 uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  emergency_buffer        double precision not null default 20000,
  currency_symbol         text not null default '₹',
  is_round_up_enabled     boolean not null default false,
  is_auto_backup_enabled  boolean not null default false,
  updated_at              timestamptz not null default now()
);

-- ===========================================================================
-- 4. Indexes, triggers, RLS, realtime for every table added above
-- ===========================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'categories','credit_cards','loans','budgets',
    'recurring_payments','investments','goals','notes'
  ]
  loop
    execute format('create index if not exists %I on public.%I (user_id)', t || '_user_id_idx', t);
    execute format('create index if not exists %I on public.%I (user_id, updated_at desc)', t || '_watermark_idx', t);

    execute format('drop trigger if exists %I on public.%I', t || '_set_updated_at', t);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t);

    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_owner_all', t);
    execute format(
      'create policy %I on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      t || '_owner_all', t);

    execute format('alter table public.%I replica identity full', t);
  end loop;
end $$;

-- user_settings: trigger + RLS (no watermark index needed — one row per user)
drop trigger if exists user_settings_set_updated_at on public.user_settings;
create trigger user_settings_set_updated_at
  before update on public.user_settings
  for each row execute function public.set_updated_at();

alter table public.user_settings enable row level security;
drop policy if exists "user_settings_owner_all" on public.user_settings;
create policy "user_settings_owner_all"
  on public.user_settings
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.user_settings replica identity full;

-- ===========================================================================
-- 5. Realtime publication (idempotent — ignore "already member" errors)
-- ===========================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts','transactions','categories','credit_cards','loans','budgets',
    'recurring_payments','investments','goals','notes','user_settings'
  ]
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null;
      when others then null;
    end;
  end loop;
end $$;
