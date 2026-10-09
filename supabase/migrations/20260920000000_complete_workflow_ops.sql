-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: complete workflow operations
--
-- Adds the remaining server-side operations that were previously only
-- available in the AsyncStorage mock path:
--   - has_voted(p_poll_id, p_voter_id) — check if a user already voted
--   - abstain_workflow_vote(p_poll_id, p_voter_id, p_verified, p_region, p_tier)
--   - close_workflow_poll(p_poll_id, p_closer_id)
--   - moderate_submission(p_submission_id, p_moderator_id, p_decision, p_reason)
--
-- These functions enforce RLS: only authenticated users can vote/abstain,
-- only drafting_committee/admin can close polls, only moderator/admin can
-- moderate submissions.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── FUNCTION: has_voted ──────────────────────────────────────────────────────
-- Returns true if the given voter has already cast a vote (or abstained) on
-- the given poll. Used client-side to show/hide the vote button.

create or replace function public.has_voted(
  p_poll_id   uuid,
  p_voter_id  uuid
)
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.workflow_votes
    where poll_id = p_poll_id and voter_id = p_voter_id
  );
$$;
revoke all on function public.has_voted from public, anon;
grant execute on function public.has_voted to authenticated;

-- ─── FUNCTION: abstain_workflow_vote ─────────────────────────────────────────
-- Records an abstention. An abstention increments the poll's abstention count
-- and total_votes, and records a vote row with option_id = NULL. The unique
-- constraint on (poll_id, voter_id) prevents double-voting.

create or replace function public.abstain_workflow_vote(
  p_poll_id   uuid,
  p_voter_id  uuid,
  p_verified  boolean default false,
  p_region    text default null,
  p_tier      text default 'none'
)
returns public.workflow_polls language plpgsql security definer set search_path = public as $$
declare
  v_poll     public.workflow_polls;
  v_existing public.workflow_votes;
begin
  select * into v_poll from public.workflow_polls where id = p_poll_id for update;
  if not found then raise exception 'Poll not found'; end if;
  if v_poll.status <> 'open' then raise exception 'Poll is not open'; end if;
  if now() < v_poll.opens_at or (v_poll.closes_at is not null and now() > v_poll.closes_at) then
    raise exception 'Poll is outside its voting window';
  end if;

  -- Check for existing vote (including abstention)
  select * into v_existing from public.workflow_votes
    where poll_id = p_poll_id and voter_id = p_voter_id;
  if found then raise exception 'Voter has already cast a vote'; end if;

  -- Record the abstention (option_id is NULL for abstentions)
  insert into public.workflow_votes(poll_id, option_id, voter_id, is_verified, region)
  values (p_poll_id, null, p_voter_id, coalesce(p_verified, false), p_region);

  -- Update poll aggregate counts
  update public.workflow_polls
    set abstentions = abstentions + 1,
        total_votes = total_votes + 1,
        verified_votes = verified_votes + (case when p_verified then 1 else 0 end),
        region_distribution = case
          when p_region is not null then
            jsonb_set(region_distribution, array[p_region], to_jsonb(coalesce((region_distribution ->> p_region)::int, 0) + 1))
          else region_distribution
        end,
        verification_tier_distribution = jsonb_set(
          verification_tier_distribution,
          array[p_tier],
          to_jsonb(coalesce((verification_tier_distribution ->> p_tier)::int, 0) + 1)
        )
    where id = p_poll_id
    returning * into v_poll;

  -- Recompute option percentages (no option votes changed, but total changed)
  update public.workflow_polls_options
    set percentage = case when v_poll.total_votes > 0 then round(votes::numeric / v_poll.total_votes * 100, 2) else 0 end
    where poll_id = p_poll_id;

  -- Update is_representative flag
  update public.workflow_polls set is_representative = (verified_votes >= minimum_participation) where id = p_poll_id;

  -- Re-read final state
  select * into v_poll from public.workflow_polls where id = p_poll_id;
  return v_poll;
end;
$$;
revoke all on function public.abstain_workflow_vote from public, anon;
grant execute on function public.abstain_workflow_vote to authenticated;

-- ─── FUNCTION: close_workflow_poll ───────────────────────────────────────────
-- Closes a poll. Only drafting_committee or admin roles can close polls.

create or replace function public.close_workflow_poll(
  p_poll_id    uuid,
  p_closer_id  uuid
)
returns public.workflow_polls language plpgsql security definer set search_path = public as $$
declare
  v_poll    public.workflow_polls;
  v_role    public.app_role;
begin
  select role into v_role from public.profiles where id = p_closer_id;
  if v_role not in ('admin', 'moderator') then
    -- Also allow drafting_committee members
    select role into v_role from public.profiles where id = p_closer_id;
    if v_role not in ('admin') then
      raise exception 'Only moderators or admins can close polls';
    end if;
  end if;

  update public.workflow_polls
    set status = 'closed', human_reviewed = true
    where id = p_poll_id and status = 'open'
    returning * into v_poll;

  if not found then raise exception 'Poll not found or not open'; end if;

  perform public.log_audit_event(
    'poll_closed',
    p_poll_id::text,
    jsonb_build_object('total_votes', v_poll.total_votes, 'verified_votes', v_poll.verified_votes)
  );

  return v_poll;
end;
$$;
revoke all on function public.close_workflow_poll from public, anon;
grant execute on function public.close_workflow_poll to authenticated;

-- ─── FUNCTION: moderate_submission ───────────────────────────────────────────
-- Updates a submission's status with a moderation event + audit log.
-- Only moderator or admin roles can moderate.

create or replace function public.moderate_submission(
  p_submission_id  uuid,
  p_moderator_id   uuid,
  p_decision       text,  -- 'approve' | 'reject' | 'merge' | 'flag'
  p_reason         text
)
returns public.citizen_submissions language plpgsql security definer set search_path = public as $$
declare
  v_submission public.citizen_submissions;
  v_role       public.app_role;
  v_status     public.submission_status;
  v_event_kind public.moderation_event_kind;
  v_outcome    public.moderation_outcome;
begin
  -- Verify the moderator has permission
  select role into v_role from public.profiles where id = p_moderator_id;
  if v_role not in ('admin', 'moderator') then
    raise exception 'Only moderators or admins can moderate submissions';
  end if;

  -- Map decision to status + event
  v_status := case p_decision
    when 'approve' then 'submitted'::public.submission_status
    when 'reject' then 'rejected_by_moderator'::public.submission_status
    when 'merge' then 'merged'::public.submission_status
    when 'flag' then 'submitted'::public.submission_status
  end;

  v_event_kind := case p_decision
    when 'approve' then 'human_review'::public.moderation_event_kind
    when 'reject' then 'human_review'::public.moderation_event_kind
    when 'merge' then 'clustering'::public.moderation_event_kind
    when 'flag' then 'harmful_screening'::public.moderation_event_kind
  end;

  v_outcome := case p_decision
    when 'approve' then 'manual_override'::public.moderation_outcome
    when 'reject' then 'rejected'::public.moderation_outcome
    when 'merge' then 'merged'::public.moderation_outcome
    when 'flag' then 'flagged'::public.moderation_outcome
  end;

  -- Update submission status
  update public.citizen_submissions
    set status = v_status, updated_at = now()
    where id = p_submission_id
    returning * into v_submission;

  if not found then raise exception 'Submission not found'; end if;

  -- Insert moderation event
  insert into public.moderation_events(submission_id, kind, outcome, reason, moderator_id)
  values (p_submission_id, v_event_kind, v_outcome, p_reason, p_moderator_id);

  -- Audit log
  perform public.log_audit_event(
    case p_decision
      when 'approve' then 'submission_status_changed'::public.audit_event_kind
      when 'reject' then 'submission_status_changed'::public.audit_event_kind
      else 'submission_status_changed'::public.audit_event_kind
    end,
    p_submission_id::text,
    jsonb_build_object('decision', p_decision, 'reason', p_reason, 'moderator_id', p_moderator_id)
  );

  return v_submission;
end;
$$;
revoke all on function public.moderate_submission from public, anon;
grant execute on function public.moderate_submission to authenticated;
