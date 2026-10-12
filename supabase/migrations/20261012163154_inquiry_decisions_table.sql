-- ==========================================================
-- Migration: inquiry_decisions table
-- ==========================================================
-- Committee members vote on reviewed submissions.

create table if not exists public.inquiry_decisions (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.inquiry_submissions(id) on delete cascade,
  committee_id uuid not null references public.profiles(id) on delete cascade,
  decision text not null check (decision in ('approve', 'reject', 'request_more_info', 'escalate')),
  rationale text not null default '' check (char_length(rationale) <= 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (submission_id, committee_id)
);

create index if not exists inquiry_decisions_submission_idx
  on public.inquiry_decisions(submission_id, created_at desc);

create index if not exists inquiry_decisions_committee_idx
  on public.inquiry_decisions(committee_id, created_at desc);

alter table public.inquiry_decisions enable row level security;
revoke all on public.inquiry_decisions from anon, authenticated;
grant select, insert, update, delete on public.inquiry_decisions to authenticated;

create policy "Admins manage all decisions"
  on public.inquiry_decisions for all to authenticated
  using (public.current_user_has_role(array['admin']))
  with check (public.current_user_has_role(array['admin']));

create policy "Committee read all decisions"
  on public.inquiry_decisions for select to authenticated
  using (public.current_user_has_role(array['admin', 'reviewer', 'committee']));

create policy "Committee insert own decision"
  on public.inquiry_decisions for insert to authenticated
  with check (
    committee_id = auth.uid()
    and public.current_user_has_role(array['committee'])
  );

create policy "Committee update own decision"
  on public.inquiry_decisions for update to authenticated
  using (
    committee_id = auth.uid()
    and public.current_user_has_role(array['committee'])
  )
  with check (
    committee_id = auth.uid()
    and public.current_user_has_role(array['committee'])
  );