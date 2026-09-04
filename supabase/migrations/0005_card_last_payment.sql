-- 0005_card_last_payment.sql
--
-- Credit-card last-payment tracking. Drives the "paid this cycle → suppress
-- the due-date reminders" logic in lib/core/services/payment_reminders.dart.
-- Backward compatible; nullable.
--
-- Apply with:  supabase db push   (or paste into the SQL editor)

alter table public.credit_cards add column if not exists last_payment_date   timestamptz;
alter table public.credit_cards add column if not exists last_payment_amount double precision;
