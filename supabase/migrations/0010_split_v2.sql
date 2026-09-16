-- 0010_split_v2.sql
--
-- People-based splitting v2: phone/UPI/notes on people, per-participant
-- category/note + partial settlement on split_participants, a new payables
-- table for "money I owe someone else", and is_settlement on transactions.
--
-- Mirrors the local Drift v10 -> v11 migration exactly, including the
-- is_settled -> settled_amount backfill (existing true rows become fully
-- settled at their own share_amount; false rows become 0) — a lossless
-- translation of the same meaning, not a change to any existing financial
-- record. No existing transaction amount is touched.
--
-- payables follows the same conventions as every table added in 0002/0009
-- (see their headers): composite PK (user_id, id), no cross-entity FKs,
-- is_deleted/deleted_at tombstones, set_updated_at trigger, owner-only RLS,
-- watermark index, replica identity full, added to the supabase_realtime
-- publication.
--
-- Apply with:  supabase db push   (or paste into the SQL editor)

-- ===========================================================================
-- 1. people — phone / upi_id / notes
-- ===========================================================================
alter table public.people
  add column if not exists phone   text,
  add column if not exists upi_id  text,
  add column if not exists notes   text;

-- ===========================================================================
-- 2. split_participants — category_id / note / settled_amount
-- ===========================================================================
alter table public.split_participants
  add column if not exists category_id     text,
  add column if not exists note            text,
  add column if not exists settled_amount  double precision not null default 0;

update public.split_participants
  set settled_amount = share_amount
  where is_settled and settled_amount = 0;

-- is_settled stays as a real column (kept for backward-compat readers) but
-- is no longer the source of truth — settled_amount >= share_amount - 0.01
-- is. Not dropped: dropping a synced column is a breaking change for any
-- client still mid-upgrade.

-- ===========================================================================
-- 3. transactions — is_settlement
-- ===========================================================================
alter table public.transactions
  add column if not exists is_settlement boolean not null default false;

-- ===========================================================================
-- 4. payables — "money I owe someone else", mirrors split_participants'
-- settlement shape but isn't linked to one of my own transactions at
-- creation time.
-- ===========================================================================
create table if not exists public.payables (
  id                     text not null,
  user_id                uuid not null default auth.uid() references auth.users (id) on delete cascade,
  person_id              text not null,
  amount                 double precision not null,
  description            text not null,
  date                   timestamptz not null,
  settled_amount         double precision not null default 0,
  settled_at             timestamptz,
  settled_transaction_id text,
  is_deleted             boolean not null default false,
  deleted_at             timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists payables_user_id_idx on public.payables (user_id);
create index if not exists payables_watermark_idx on public.payables (user_id, updated_at desc);

drop trigger if exists payables_set_updated_at on public.payables;
create trigger payables_set_updated_at
  before update on public.payables
  for each row execute function public.set_updated_at();

alter table public.payables enable row level security;
drop policy if exists "payables_owner_all" on public.payables;
create policy "payables_owner_all"
  on public.payables
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.payables replica identity full;

do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.payables';
  exception
    when duplicate_object then null;
    when others then null;
  end;
end $$;
