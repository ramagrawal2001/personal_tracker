-- 0006_companies.sql
--
-- Employer registry (Companies) + the supporting columns for the Salary/PF
-- workflow: which company a transaction/recurring-reminder belongs to, and
-- the "this leg is a reference account, not real money movement" flag a
-- salary-linked PF contribution needs (see accountsWithCalculatedBalances /
-- FinanceNotifier.logSalary in the app).
--
-- Same conventions as every table added in 0002 (see its header): composite
-- PK (user_id, id), no cross-entity FKs, is_deleted/deleted_at tombstones,
-- set_updated_at trigger, owner-only RLS, watermark index, replica identity
-- full, added to the supabase_realtime publication.
--
-- Apply with:  supabase db push   (or paste into the SQL editor)

-- ===========================================================================
-- 1. New columns on existing tables
-- ===========================================================================
alter table public.transactions
  add column if not exists company_id text,
  add column if not exists is_external_to_account boolean not null default false;

alter table public.recurring_payments
  add column if not exists is_income boolean not null default false,
  add column if not exists company_id text;

alter table public.investments
  add column if not exists reference_number text;

-- ===========================================================================
-- 2. companies
-- ===========================================================================
create table if not exists public.companies (
  id                      text not null,
  user_id                 uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name                    text not null,
  joined_date             timestamptz,
  is_current_employer     boolean not null default false,
  default_bank_account_id text,
  default_pf_amount       double precision,
  is_deleted              boolean not null default false,
  deleted_at              timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists companies_user_id_idx on public.companies (user_id);
create index if not exists companies_watermark_idx on public.companies (user_id, updated_at desc);

drop trigger if exists companies_set_updated_at on public.companies;
create trigger companies_set_updated_at
  before update on public.companies
  for each row execute function public.set_updated_at();

alter table public.companies enable row level security;
drop policy if exists "companies_owner_all" on public.companies;
create policy "companies_owner_all"
  on public.companies
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.companies replica identity full;

do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.companies';
  exception
    when duplicate_object then null;
    when others then null;
  end;
end $$;
