-- ==========================================================
-- Migration: inquiry_assignments table
-- ==========================================================
-- Allows admins to assign submissions to reviewers.
-- Reviewers see assigned submissions on their workflow dashboard.
-- Admin can reassign or unassign at any time.

create table if not exists public.inquiry_assignments (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.inquiry_submissions(id) on delete cascade,
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  status text not null default 'assigned' check (status in ('assigned', 'in_review', 'reviewed', 'returned')),
  notes text not null default '' check (char_length(notes) <= 2000),
  unique (submission_id, reviewer_id)
);

create index if not exists inquiry_assignments_reviewer_idx
  on public.inquiry_assignments(reviewer_id, status, assigned_at desc);

create index if not exists inquiry_assignments_submission_idx
  on public.inquiry_assignments(submission_id);

-- RLS
alter table public.inquiry_assignments enable row level security;
revoke all on public.inquiry_assignments from anon, authenticated;
grant select, insert, update, delete on public.inquiry_assignments to authenticated;

-- Admin can do everything
create policy "Admins manage all assignments"
  on public.inquiry_assignments
  for all
  to authenticated
  using (public.current_user_has_role(array['admin']))
  with check (public.current_user_has_role(array['admin']));

-- Reviewer can read their own assignments
create policy "Reviewers read own assignments"
  on public.inquiry_assignments
  for select
  to authenticated
  using (
    reviewer_id = auth.uid()
    and public.current_user_has_role(array['reviewer'])
  );

-- Reviewer can update their own assignment status
create policy "Reviewers update own assignment status"
  on public.inquiry_assignments
  for update
  to authenticated
  using (
    reviewer_id = auth.uid()
    and public.current_user_has_role(array['reviewer'])
  )
  with check (
    reviewer_id = auth.uid()
    and public.current_user_has_role(array['reviewer'])
  );

-- Committee can read all assignments (for context)
create policy "Committee read all assignments"
  on public.inquiry_assignments
  for select
  to authenticated
  using (public.current_user_has_role(array['committee']));