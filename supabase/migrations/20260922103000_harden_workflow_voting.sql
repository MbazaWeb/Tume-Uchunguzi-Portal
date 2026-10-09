-- Harden voting RPCs while preserving one-user/one-vote semantics.
create or replace function public.cast_workflow_vote(p_poll_id uuid, p_option_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_voter uuid := auth.uid();
  v_poll record;
  v_verified boolean := false;
  v_region text;
begin
  if v_voter is null then raise exception 'Authentication required'; end if;
  select * into v_poll from public.workflow_polls
   where id=p_poll_id and status='open' and opens_at<=now()
     and (closes_at is null or closes_at>now());
  if not found then raise exception 'Poll is not open'; end if;
  if p_option_id is not null and not exists (
    select 1 from public.workflow_poll_options where id=p_option_id and poll_id=p_poll_id
  ) then raise exception 'Invalid poll option'; end if;
  select (verification_tier in ('phone','nida')), region into v_verified,v_region
    from public.profiles where id=v_voter;
  insert into public.workflow_votes(poll_id,option_id,voter_id,is_verified,region)
  values(p_poll_id,p_option_id,v_voter,coalesce(v_verified,false),v_region);
  if p_option_id is not null then
    update public.workflow_poll_options set votes=votes+1,
      verified_votes=verified_votes+(case when v_verified then 1 else 0 end)
      where id=p_option_id and poll_id=p_poll_id;
  end if;
  update public.workflow_polls set total_votes=total_votes+1,
    verified_votes=verified_votes+(case when v_verified then 1 else 0 end),
    abstentions=abstentions+(case when p_option_id is null then 1 else 0 end)
    where id=p_poll_id;
  return jsonb_build_object('ok',true);
exception when unique_violation then raise exception 'You have already voted in this poll';
end; $$;

create or replace function public.abstain_workflow_vote(p_poll_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin perform public.cast_workflow_vote(p_poll_id,null); end; $$;

revoke all on function public.cast_workflow_vote(uuid,uuid) from public,anon;
revoke all on function public.abstain_workflow_vote(uuid) from public,anon;
grant execute on function public.cast_workflow_vote(uuid,uuid) to authenticated;
grant execute on function public.abstain_workflow_vote(uuid) to authenticated;
