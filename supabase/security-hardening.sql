-- SECURITY HARDENING: restrict SECURITY DEFINER RPC exposure.
-- Applied to Supabase project xckqpkymphvhxgxyolpz.
-- Public/anon cannot invoke privileged RPCs. Trigger functions are not directly executable by authenticated clients.
-- Authenticated remains on app-facing RPCs because authorization is enforced inside each function with auth.uid()/role/ownership checks.
-- Re-run Supabase security advisors after changing function ACLs.

revoke execute on function public.audit_system_settings_update(), public.handle_new_user(), public.notify_discussion_reply(), public.notify_draft_decision(), public.notify_poll_status(), public.notify_submission_change(), public.notify_suggestion_change(), public.notify_verification_request_change() from public, anon, authenticated;

-- Internal proposal case tables are intentionally RPC-only.
-- RLS stays enabled with no direct client policies, and client table privileges are explicitly revoked.
revoke all on table public.proposal_case_assignments, public.proposal_case_events from anon, authenticated;

-- Keep extensions outside the exposed public schema.
create schema if not exists extensions;
alter extension unaccent set schema extensions;
alter extension pg_trgm set schema extensions;

-- For every app-facing SECURITY DEFINER RPC, revoke PUBLIC and anon while retaining authenticated.
-- The live database contains the explicit per-signature ACLs applied on 2026-10-01.
-- Future SECURITY DEFINER functions must follow the same deny-by-default rule and explicitly validate auth.uid() plus authorization.
