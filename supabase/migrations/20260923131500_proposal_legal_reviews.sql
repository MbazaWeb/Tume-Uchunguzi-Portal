-- Structured, versioned legal review records for workflow step 6.
create table if not exists public.proposal_legal_reviews (
 id uuid primary key default gen_random_uuid(),
 submission_id uuid not null references public.citizen_submissions(id) on delete cascade,
 reviewer_id uuid not null references public.profiles(id),
 version integer not null,
 constitutional_issue text,
 affected_constitutional_provision text,
 related_constitutional_provisions text,
 related_laws text,
 legal_conflict_risk text,
 rights_impact text,
 institutional_governance_impact text,
 drafting_observation text,
 recommended_wording_direction text,
 legal_conclusion text,
 reviewer_note text,
 review_status text not null default 'draft' check (review_status in ('draft','completed','returned_for_clarification')),
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 unique(submission_id, version)
);
alter table public.proposal_legal_reviews enable row level security;
revoke all on public.proposal_legal_reviews from anon;
grant select,insert on public.proposal_legal_reviews to authenticated;
drop policy if exists "Legal reviewers create versioned reviews" on public.proposal_legal_reviews;
create policy "Legal reviewers create versioned reviews" on public.proposal_legal_reviews for insert to authenticated
with check (reviewer_id=(select auth.uid()) and exists(select 1 from public.workflow_role_assignments a join public.workflow_roles r on r.id=a.workflow_role_id where a.user_id=(select auth.uid()) and a.is_active and r.is_active and r.code='legal_review'));
drop policy if exists "Legal review visibility" on public.proposal_legal_reviews;
create policy "Legal review visibility" on public.proposal_legal_reviews for select to authenticated
using ((reviewer_id=(select auth.uid()) and exists(select 1 from public.workflow_role_assignments a join public.workflow_roles r on r.id=a.workflow_role_id where a.user_id=(select auth.uid()) and a.is_active and r.is_active and r.code='legal_review')) or (review_status='completed' and exists(select 1 from public.workflow_role_assignments a join public.workflow_roles r on r.id=a.workflow_role_id where a.user_id=(select auth.uid()) and a.is_active and r.is_active and r.code='committee')) or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
create or replace function public.workflow_latest_legal_review(p_submission_id uuid) returns jsonb language plpgsql security invoker set search_path='' as $$ declare v jsonb; begin select to_jsonb(x) into v from (select l.*,p.display_name reviewer_name from public.proposal_legal_reviews l join public.profiles p on p.id=l.reviewer_id where l.submission_id=p_submission_id order by l.version desc limit 1) x; return v; end $$;
revoke execute on function public.workflow_latest_legal_review(uuid) from public,anon;
grant execute on function public.workflow_latest_legal_review(uuid) to authenticated;
create or replace function public.workflow_save_legal_review_v2(p_submission_id uuid,p_constitutional_issue text,p_affected_constitutional_provision text,p_related_constitutional_provisions text,p_related_laws text,p_legal_conflict_risk text,p_rights_impact text,p_institutional_governance_impact text,p_drafting_observation text,p_recommended_wording_direction text,p_legal_conclusion text,p_reviewer_note text,p_review_status text default 'draft') returns uuid language plpgsql security invoker set search_path='' as $$ declare v_id uuid; v_version integer; begin if p_review_status not in ('draft','completed','returned_for_clarification') then raise exception 'Invalid legal review status'; end if; if not exists(select 1 from public.workflow_role_assignments a join public.workflow_roles r on r.id=a.workflow_role_id where a.user_id=auth.uid() and a.is_active and r.is_active and r.code='legal_review') then raise exception 'Active Legal Review assignment required'; end if; if not exists(select 1 from public.citizen_submissions s where s.id=p_submission_id and s.workflow_step=6) then raise exception 'Application is not in Legal Review stage'; end if; select coalesce(max(version),0)+1 into v_version from public.proposal_legal_reviews where submission_id=p_submission_id; insert into public.proposal_legal_reviews(submission_id,reviewer_id,version,constitutional_issue,affected_constitutional_provision,related_constitutional_provisions,related_laws,legal_conflict_risk,rights_impact,institutional_governance_impact,drafting_observation,recommended_wording_direction,legal_conclusion,reviewer_note,review_status,reviewed_at) values(p_submission_id,auth.uid(),v_version,nullif(trim(p_constitutional_issue),''),nullif(trim(p_affected_constitutional_provision),''),nullif(trim(p_related_constitutional_provisions),''),nullif(trim(p_related_laws),''),nullif(trim(p_legal_conflict_risk),''),nullif(trim(p_rights_impact),''),nullif(trim(p_institutional_governance_impact),''),nullif(trim(p_drafting_observation),''),nullif(trim(p_recommended_wording_direction),''),nullif(trim(p_legal_conclusion),''),nullif(trim(p_reviewer_note),''),p_review_status,case when p_review_status='completed' then now() else null end) returning id into v_id; return v_id; end $$;
revoke execute on function public.workflow_save_legal_review_v2(uuid,text,text,text,text,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.workflow_save_legal_review_v2(uuid,text,text,text,text,text,text,text,text,text,text,text,text) to authenticated;
