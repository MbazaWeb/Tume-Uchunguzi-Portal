-- Security hotfix: never trust user IDs or verification data from clients.

drop function if exists public.has_voted(uuid, uuid);
drop function if exists public.abstain_workflow_vote(uuid, uuid, boolean, text, text);
drop function if exists public.close_workflow_poll(uuid, uuid);
drop function if exists public.moderate_submission(uuid, uuid, text, text);

create or replace function public.has_voted(p_poll_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workflow_votes
    where poll_id = p_poll_id
      and voter_id = (select auth.uid())
  );
$$;

revoke all on function public.has_voted(uuid) from public, anon;
grant execute on function public.has_voted(uuid) to authenticated;


create or replace function public.abstain_workflow_vote(p_poll_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_verified boolean := false;
  v_region text;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select
    coalesce(nida_verified, false),
    region
  into v_verified, v_region
  from public.profiles
  where id = v_user;

  if not exists (
    select 1
    from public.workflow_polls
    where id = p_poll_id
      and status = 'open'
      and opens_at <= now()
      and closes_at >= now()
  ) then
    raise exception 'Poll not found or not open';
  end if;

  insert into public.workflow_votes (
    poll_id,
    option_id,
    voter_id,
    is_verified,
    region
  )
  values (
    p_poll_id,
    null,
    v_user,
    v_verified,
    v_region
  );

  update public.workflow_polls
  set
    total_votes = total_votes + 1,
    abstentions = abstentions + 1,
    verified_votes =
      verified_votes + case when v_verified then 1 else 0 end
  where id = p_poll_id;

exception
  when unique_violation then
    raise exception 'You have already voted in this poll';
end;
$$;

revoke all on function public.abstain_workflow_vote(uuid)
from public, anon;

grant execute on function public.abstain_workflow_vote(uuid)
to authenticated;


create or replace function public.close_workflow_poll(p_poll_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = v_user
      and role::text in ('admin', 'moderator', 'drafting_committee')
  ) then
    raise exception 'Insufficient permission to close polls';
  end if;

  update public.workflow_polls
  set
    status = 'closed',
    human_reviewed = true
  where id = p_poll_id
    and status = 'open';

  if not found then
    raise exception 'Poll not found or already closed';
  end if;
end;
$$;

revoke all on function public.close_workflow_poll(uuid)
from public, anon;

grant execute on function public.close_workflow_poll(uuid)
to authenticated;


create or replace function public.moderate_submission(
  p_submission_id uuid,
  p_decision text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = v_user
      and role::text in ('admin', 'moderator')
  ) then
    raise exception 'Insufficient permission to moderate submissions';
  end if;

  if p_decision not in ('approve', 'reject', 'merge', 'flag') then
    raise exception 'Invalid moderation decision';
  end if;

  update public.citizen_submissions
  set
    status = case p_decision
      when 'approve' then 'submitted'::public.submission_status
      when 'reject' then 'rejected'::public.submission_status
      when 'merge' then 'merged'::public.submission_status
      when 'flag' then 'submitted'::public.submission_status
    end,
    updated_at = now()
  where id = p_submission_id;

  if not found then
    raise exception 'Submission not found';
  end if;

  insert into public.moderation_events (
    submission_id,
    kind,
    outcome,
    reason,
    moderator_id
  )
  values (
    p_submission_id,
    case p_decision
      when 'merge'
        then 'clustering'::public.moderation_event_kind
      when 'flag'
        then 'harmful_screening'::public.moderation_event_kind
      else 'human_review'::public.moderation_event_kind
    end,
    case p_decision
      when 'approve'
        then 'manual_override'::public.moderation_outcome
      when 'reject'
        then 'rejected'::public.moderation_outcome
      when 'merge'
        then 'merged'::public.moderation_outcome
      when 'flag'
        then 'flagged'::public.moderation_outcome
    end,
    nullif(trim(p_reason), ''),
    v_user
  );
end;
$$;

revoke all on function public.moderate_submission(uuid, text, text)
from public, anon;

grant execute on function public.moderate_submission(uuid, text, text)
to authenticated;