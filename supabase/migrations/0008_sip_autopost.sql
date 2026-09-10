-- 0008_sip_autopost.sql
--
-- SIP auto-invest: a per-investment "auto-invest on SIP day" toggle and a
-- month-granularity idempotency marker so the client posts each SIP at most
-- once per calendar month, across devices.
--
-- Backward compatible; nullable / defaulted. Apply with: supabase db push

alter table public.investments
  add column if not exists auto_invest_enabled boolean not null default false,
  add column if not exists last_auto_posted_month text;
