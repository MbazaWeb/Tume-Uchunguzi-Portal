-- ==========================================================
-- Migration: RLS policies for reviewer and committee roles
-- ==========================================================
-- Allows reviewer and committee members to read inquiry submissions.
-- Uses a SECURITY DEFINER helper function to avoid recursive RLS issues.

-- Helper function: check if the current user has a given role
-- SECURITY DEFINER to bypass RLS on profiles (avoids recursion).
create or replace function public.current_user_has_role(allowed_roles text[])
returns boolean
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = any(allowed_roles)
  );
$$;

revoke all on function public.current_user_has_role(text[]) from public, anon;
grant execute on function public.current_user_has_role(text[]) to authenticated;

comment on function public.current_user_has_role(text[]) is 
  'Returns true if the current authenticated user has one of the allowed roles. SECURITY DEFINER to avoid RLS recursion.';

-- ----------------------------------------------------------
-- Reviewer + Committee can read inquiry_submissions
-- ----------------------------------------------------------
drop policy if exists "Reviewers and committee read all inquiry submissions"
  on public.inquiry_submissions;

create policy "Reviewers and committee read all inquiry submissions"
  on public.inquiry_submissions
  for select
  to authenticated
  using (public.current_user_has_role(array['admin', 'reviewer', 'committee']));

-- ----------------------------------------------------------
-- Reviewer + Committee can read follow-ups
-- ----------------------------------------------------------
drop policy if exists "Reviewers and committee read all follow-ups"
  on public.inquiry_followups;

create policy "Reviewers and committee read all follow-ups"
  on public.inquiry_followups
  for select
  to authenticated
  using (public.current_user_has_role(array['admin', 'reviewer', 'committee']));

-- ----------------------------------------------------------
-- Reviewer can post follow-ups (as staff)
-- ----------------------------------------------------------
drop policy if exists "Reviewers can post staff follow-ups"
  on public.inquiry_followups;

create policy "Reviewers can post staff follow-ups"
  on public.inquiry_followups
  for insert
  to authenticated
  with check (
    sender_role = 'staff'
    and public.current_user_has_role(array['admin', 'reviewer'])
  );

-- ----------------------------------------------------------
-- Reviewer + Committee can read evidence (storage)
-- ----------------------------------------------------------
drop policy if exists "Reviewers and committee read inquiry evidence"
  on storage.objects;

create policy "Reviewers and committee read inquiry evidence"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'inquiry-evidence'
    and public.current_user_has_role(array['admin', 'reviewer', 'committee'])
  );