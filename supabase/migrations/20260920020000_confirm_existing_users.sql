-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: confirm email for all existing users
--
-- "Confirm email" is disabled in the Supabase Auth provider settings, but
-- users who signed up before that toggle was turned off have a NULL
-- email_confirmed_at in auth.users. Supabase still blocks sign-in for those
-- accounts with "Email not confirmed".
--
-- This one-time migration sets email_confirmed_at = created_at for every
-- auth user whose email has not yet been confirmed. Safe to run multiple
-- times (the WHERE clause is a no-op for already-confirmed accounts).
-- ─────────────────────────────────────────────────────────────────────────────

update auth.users
set
  email_confirmed_at = coalesce(email_confirmed_at, created_at, now()),
  updated_at         = now()
where email_confirmed_at is null;
