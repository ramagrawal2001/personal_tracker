-- ===========================================================================
-- 0011 — Stop storing full card / bank secrets
-- ===========================================================================
-- The app no longer keeps the full card number, CVV, ATM PIN, full bank
-- account number or IFSC — only the plaintext last-4 digits (last4 /
-- account_number_last4) remain. This drops the encrypted columns added in
-- 0004 so the existing ciphertext is deleted from the server too.
--
-- The sec_* columns on user_settings are KEPT: the per-user encryption key
-- still protects Notes.
--
-- Run this AFTER every device is on the app build that stops sending these
-- columns; an older build would fail its card/account upserts once they are
-- gone. Safe to run more than once.

alter table public.credit_cards drop column if exists enc_card_number;
alter table public.credit_cards drop column if exists enc_cvv;
alter table public.credit_cards drop column if exists enc_pin;

alter table public.accounts drop column if exists enc_account_number;
alter table public.accounts drop column if exists enc_ifsc;
