-- ===========================================================================
-- 0004 — Encrypted card / bank secrets + free-form card colour + DEK envelope
-- ===========================================================================
-- All of the enc_* / sec_* columns hold opaque AES-256-GCM ciphertext produced
-- on-device by SecretCipherService. The server (and anyone with Postgres
-- access) only ever sees ciphertext; the plaintext key material never leaves
-- the user's devices. Safe to run more than once.

-- ── Credit cards: full number / CVV / ATM PIN (encrypted) + custom colour ──
alter table public.credit_cards add column if not exists enc_card_number text;
alter table public.credit_cards add column if not exists enc_cvv text;
alter table public.credit_cards add column if not exists enc_pin text;
alter table public.credit_cards add column if not exists color_hex text;

-- ── Bank accounts: full account number / IFSC (encrypted) ──
alter table public.accounts add column if not exists enc_account_number text;
alter table public.accounts add column if not exists enc_ifsc text;

-- ── user_settings: per-user envelope-encryption key material ──
--   sec_wrapped_dek     — DEK wrapped by a KEK derived from the login password
--   sec_kek_salt        — PBKDF2 salt for the password KEK
--   sec_wrapped_dek_rc  — DEK wrapped by a KEK derived from the recovery code
--   sec_rc_salt         — PBKDF2 salt for the recovery-code KEK
alter table public.user_settings add column if not exists sec_wrapped_dek text;
alter table public.user_settings add column if not exists sec_kek_salt text;
alter table public.user_settings add column if not exists sec_wrapped_dek_rc text;
alter table public.user_settings add column if not exists sec_rc_salt text;
