alter table public.workflow_stage_actions drop constraint workflow_stage_actions_action_check;
alter table public.workflow_stage_actions add constraint workflow_stage_actions_action_check check (action = any (array['approve','return','flag','reject','merge','classify','cluster','legal_clear','committee_accept','committee_return','committee_hold','resubmit']::text[]));

create or replace function public.workflow_save_committee_decision(p_submission_id uuid,p_decision text,p_rationale text,p_conditions text default '',p_committee_note text default '')
returns integer language plpgsql set search_path to '' as $function$
declare v_version int; v_author uuid; v_role uuid;
begin
 if p_decision not in ('draft','accepted','returned','rejected','held') then raise exception 'Invalid committee decision'; end if;
 select r.id into v_role from public.workflow_role_assignments a join public.workflow_roles r on r.id=a.workflow_role_id where a.user_id=auth.uid() and a.is_active and r.is_active and r.code='committee' and r.step_order=7 limit 1;
 if v_role is null then raise exception 'Committee role access required'; end if;
 if not exists(select 1 from public.citizen_submissions s where s.id=p_submission_id and s.workflow_step=7 and not s.revision_required) then raise exception 'Application is not active at Committee stage'; end if;
 if not exists(select 1 from public.proposal_legal_reviews l where l.submission_id=p_submission_id and l.review_status='completed') then raise exception 'Completed legal review is required before committee decision'; end if;
 if p_decision<>'draft' and nullif(trim(coalesce(p_rationale,'')),'') is null then raise exception 'Committee rationale is required'; end if;
 if p_decision='returned' and nullif(trim(coalesce(p_conditions,'')),'') is null then raise exception 'Correction instructions are required when returning a proposal'; end if;
 select author_id into v_author from public.citizen_submissions where id=p_submission_id;
 select coalesce(max(version),0)+1 into v_version from public.proposal_committee_decisions where submission_id=p_submission_id;
 insert into public.proposal_committee_decisions(submission_id,committee_member_id,version,decision,rationale,conditions,committee_note,decided_at) values(p_submission_id,auth.uid(),v_version,p_decision,coalesce(p_rationale,''),coalesce(p_conditions,''),coalesce(p_committee_note,''),case when p_decision='draft' then null else now() end);
 if p_decision='returned' then
  update public.citizen_submissions set revision_required=true,revision_return_step=7,revision_requested_at=now(),workflow_updated_at=now(),updated_at=now() where id=p_submission_id;
  insert into public.workflow_stage_actions(submission_id,workflow_role_id,actor_id,action,note,metadata) values(p_submission_id,v_role,auth.uid(),'committee_return',trim(p_conditions),jsonb_build_object('revision_required',true,'resume_step',7,'committee_version',v_version,'decision',p_decision));
 elsif p_decision='accepted' then
  update public.citizen_submissions set workflow_step=8,revision_required=false,revision_return_step=null,workflow_updated_at=now(),updated_at=now() where id=p_submission_id;
  insert into public.workflow_stage_actions(submission_id,workflow_role_id,actor_id,action,note,metadata) values(p_submission_id,v_role,auth.uid(),'committee_accept',trim(p_rationale),jsonb_build_object('committee_version',v_version,'decision',p_decision));
 elsif p_decision='rejected' then
  update public.citizen_submissions set status='rejected_by_moderator'::public.submission_status,revision_required=false,revision_return_step=null,workflow_updated_at=now(),updated_at=now() where id=p_submission_id;
  insert into public.workflow_stage_actions(submission_id,workflow_role_id,actor_id,action,note,metadata) values(p_submission_id,v_role,auth.uid(),'reject',trim(p_rationale),jsonb_build_object('committee_version',v_version,'decision',p_decision));
 elsif p_decision='held' then
  insert into public.workflow_stage_actions(submission_id,workflow_role_id,actor_id,action,note,metadata) values(p_submission_id,v_role,auth.uid(),'committee_hold',trim(p_rationale),jsonb_build_object('committee_version',v_version,'decision',p_decision));
 end if;
 if p_decision<>'draft' and v_author is not null then insert into public.notifications(user_id,kind,title,body,href) values(v_author,'proposal_workflow',case p_decision when 'accepted' then 'Pendekezo limekubaliwa na Committee' when 'returned' then 'Marekebisho yanahitajika' when 'rejected' then 'Committee imetoa uamuzi' else 'Committee imesasisha pendekezo' end,case when p_decision='returned' then trim(p_conditions) else trim(p_rationale) end,'/account?tab=reviews'); end if;
 return v_version;
end $function$;