-- Keep proposal Legal Review completion and workflow traceability atomic.
create or replace function public.workflow_save_legal_review_v2(
 p_submission_id uuid,p_constitutional_issue text,p_affected_constitutional_provision text,
 p_related_constitutional_provisions text,p_related_laws text,p_legal_conflict_risk text,
 p_rights_impact text,p_institutional_governance_impact text,p_drafting_observation text,
 p_recommended_wording_direction text,p_legal_conclusion text,p_reviewer_note text,
 p_review_status text default 'draft'
) returns uuid language plpgsql set search_path to '' as $$
declare v_id uuid; v_version integer; v_role uuid;
begin
 if p_review_status not in ('draft','completed','returned_for_clarification') then raise exception 'Invalid legal review status'; end if;
 select r.id into v_role from public.workflow_role_assignments a join public.workflow_roles r on r.id=a.workflow_role_id where a.user_id=auth.uid() and a.is_active and r.is_active and r.code='legal_review' limit 1;
 if v_role is null then raise exception 'Active Legal Review assignment required'; end if;
 if not exists(select 1 from public.citizen_submissions s where s.id=p_submission_id and s.workflow_step=6 and not s.revision_required) then raise exception 'Application is not active in Legal Review stage'; end if;
 select coalesce(max(version),0)+1 into v_version from public.proposal_legal_reviews where submission_id=p_submission_id;
 insert into public.proposal_legal_reviews(submission_id,reviewer_id,version,constitutional_issue,affected_constitutional_provision,related_constitutional_provisions,related_laws,legal_conflict_risk,rights_impact,institutional_governance_impact,drafting_observation,recommended_wording_direction,legal_conclusion,reviewer_note,review_status,reviewed_at)
 values(p_submission_id,auth.uid(),v_version,nullif(trim(p_constitutional_issue),''),nullif(trim(p_affected_constitutional_provision),''),nullif(trim(p_related_constitutional_provisions),''),nullif(trim(p_related_laws),''),nullif(trim(p_legal_conflict_risk),''),nullif(trim(p_rights_impact),''),nullif(trim(p_institutional_governance_impact),''),nullif(trim(p_drafting_observation),''),nullif(trim(p_recommended_wording_direction),''),nullif(trim(p_legal_conclusion),''),nullif(trim(p_reviewer_note),''),p_review_status,case when p_review_status='completed' then now() else null end) returning id into v_id;
 if p_review_status='completed' then
   insert into public.workflow_stage_actions(submission_id,workflow_role_id,actor_id,action,note,metadata) values(p_submission_id,v_role,auth.uid(),'legal_clear',nullif(trim(coalesce(p_reviewer_note,'')),''),jsonb_build_object('legal_review_id',v_id,'review_version',v_version));
   update public.citizen_submissions set workflow_step=7,revision_required=false,revision_return_step=null,workflow_updated_at=now(),updated_at=now() where id=p_submission_id;
 elsif p_review_status='returned_for_clarification' then
   insert into public.workflow_stage_actions(submission_id,workflow_role_id,actor_id,action,note,metadata) values(p_submission_id,v_role,auth.uid(),'return',coalesce(nullif(trim(p_reviewer_note),''),'Legal review requested clarification'),jsonb_build_object('legal_review_id',v_id,'review_version',v_version,'revision_required',true,'resume_step',6));
   update public.citizen_submissions set revision_required=true,revision_return_step=6,revision_requested_at=now(),workflow_updated_at=now(),updated_at=now() where id=p_submission_id;
 end if;
 return v_id;
end $$;