-- ==========================================================
-- SECURITY FIX: Anonymous submissions cannot have follow-ups
-- ==========================================================
-- Anonymous submissions (user_id = NULL) have no owner, so no
-- authenticated user can prove ownership. To prevent any user
-- from reading or writing follow-ups for anonymous submissions,
-- we restrict follow-up access to submissions that BELONG to
-- the current authenticated user.

-- Drop the overly-permissive policy from migration 20261009140000
drop policy if exists "Citizens read follow-ups for own submissions"
  on public.inquiry_followups;

-- New policy: only the actual owner of the submission can read follow-ups.
create policy "Citizens read follow-ups for own submissions"
  on public.inquiry_followups for select to authenticated
  using (
    exists (
      select 1 from public.inquiry_submissions s
      where s.id = submission_id
        and s.user_id = (select auth.uid())
    )
  );

-- Also restrict INSERT to owned submissions (unchanged logic, kept here
-- for clarity so this migration is self-contained).
drop policy if exists "Citizens add follow-ups to own submissions"
  on public.inquiry_followups;

create policy "Citizens add follow-ups to own submissions"
  on public.inquiry_followups for insert to authenticated
  with check (
    sender_role = 'citizen'
    and exists (
      select 1 from public.inquiry_submissions s
      where s.id = submission_id
        and s.user_id = (select auth.uid())
    )
  );