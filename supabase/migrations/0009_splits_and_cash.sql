-- 0009_splits_and_cash.sql
--
-- Split expenses (IOU tracking) + cash as a "Pay With" option.
--
-- `is_cash_spend` on transactions is the same "accountId is a required FK
-- reference only, not real money movement" shape `is_external_to_account`
-- already has (see 0006_companies.sql) — kept as its own column so the two
-- reasons stay distinguishable.
--
-- `people`/`split_expenses`/`split_participants` follow the same conventions
-- as every table added in 0002 (see its header): composite PK (user_id, id),
-- no cross-entity FKs, is_deleted/deleted_at tombstones, set_updated_at
-- trigger, owner-only RLS, watermark index, replica identity full, added to
-- the supabase_realtime publication.
--
-- Apply with:  supabase db push   (or paste into the SQL editor)

-- ===========================================================================
-- 1. New column on transactions
-- ===========================================================================
alter table public.transactions
  add column if not exists is_cash_spend boolean not null default false;

-- ===========================================================================
-- 2. people
-- ===========================================================================
create table if not exists public.people (
  id         text not null,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists people_user_id_idx on public.people (user_id);
create index if not exists people_watermark_idx on public.people (user_id, updated_at desc);

drop trigger if exists people_set_updated_at on public.people;
create trigger people_set_updated_at
  before update on public.people
  for each row execute function public.set_updated_at();

alter table public.people enable row level security;
drop policy if exists "people_owner_all" on public.people;
create policy "people_owner_all"
  on public.people
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.people replica identity full;

do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.people';
  exception
    when duplicate_object then null;
    when others then null;
  end;
end $$;

-- ===========================================================================
-- 3. split_expenses
-- ===========================================================================
create table if not exists public.split_expenses (
  id             text not null,
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title          text not null,
  total_amount   double precision not null,
  date           timestamptz not null,
  -- No FK — the "no cross-entity FKs" convention (see 0002) means the real
  -- transaction this points at might sync before or after this row.
  transaction_id text not null,
  mode           text not null default 'equal',
  is_deleted     boolean not null default false,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists split_expenses_user_id_idx on public.split_expenses (user_id);
create index if not exists split_expenses_watermark_idx on public.split_expenses (user_id, updated_at desc);

drop trigger if exists split_expenses_set_updated_at on public.split_expenses;
create trigger split_expenses_set_updated_at
  before update on public.split_expenses
  for each row execute function public.set_updated_at();

alter table public.split_expenses enable row level security;
drop policy if exists "split_expenses_owner_all" on public.split_expenses;
create policy "split_expenses_owner_all"
  on public.split_expenses
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.split_expenses replica identity full;

do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.split_expenses';
  exception
    when duplicate_object then null;
    when others then null;
  end;
end $$;

-- ===========================================================================
-- 4. split_participants
-- ===========================================================================
create table if not exists public.split_participants (
  id                    text not null,
  user_id               uuid not null default auth.uid() references auth.users (id) on delete cascade,
  split_expense_id      text not null,
  person_id             text not null,
  share_amount          double precision not null,
  is_settled            boolean not null default false,
  settled_at            timestamptz,
  settled_transaction_id text,
  is_deleted            boolean not null default false,
  deleted_at            timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists split_participants_user_id_idx on public.split_participants (user_id);
create index if not exists split_participants_watermark_idx on public.split_participants (user_id, updated_at desc);

drop trigger if exists split_participants_set_updated_at on public.split_participants;
create trigger split_participants_set_updated_at
  before update on public.split_participants
  for each row execute function public.set_updated_at();

alter table public.split_participants enable row level security;
drop policy if exists "split_participants_owner_all" on public.split_participants;
create policy "split_participants_owner_all"
  on public.split_participants
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.split_participants replica identity full;

do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.split_participants';
  exception
    when duplicate_object then null;
    when others then null;
  end;
end $$;
