-- Citizen submission pipeline entry point with immutable original submission content.
create or replace function public.submit_citizen_proposal_safe(p_title text,p_topic public.constitutional_topic,p_article_id text,p_problem text,p_wording text,p_rationale text,p_evidence text,p_region text,p_district text,p_anonymous boolean)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(p_title))<3 or length(trim(p_problem))<10 or length(trim(p_rationale))<10 then raise exception 'Submission needs a title, problem and rationale'; end if;
 insert into public.citizen_submissions(title,topic,affected_article_id,problem,proposed_wording_sw,rationale,supporting_evidence,region,district,anonymous,author_id,status)
 values(trim(p_title),p_topic,nullif(trim(p_article_id),''),trim(p_problem),nullif(trim(p_wording),''),trim(p_rationale),nullif(trim(p_evidence),''),nullif(trim(p_region),''),nullif(trim(p_district),''),p_anonymous,auth.uid(),'submitted') returning id into v_id;
 insert into public.moderation_events(submission_id,kind,outcome,reason,moderator_id) values(v_id,'validation','passed','Required submission fields validated at intake',null);
 return v_id;
end; $$;

create or replace function public.review_citizen_submission(p_submission_id uuid,p_outcome public.moderation_outcome,p_reason text)
returns void language plpgsql security definer set search_path=''
as $$ declare v_status public.submission_status; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 v_status:=case p_outcome when 'passed' then 'in_moderation' when 'flagged' then 'flagged' when 'rejected' then 'rejected_by_moderator' when 'restored' then 'in_moderation' else 'in_moderation' end;
 update public.citizen_submissions set status=v_status,updated_at=now() where id=p_submission_id;
 if not found then raise exception 'Submission not found'; end if;
 insert into public.moderation_events(submission_id,kind,outcome,reason,moderator_id) values(p_submission_id,'human_review',p_outcome,coalesce(p_reason,''),auth.uid());
end; $$;

revoke all on function public.submit_citizen_proposal_safe(text,public.constitutional_topic,text,text,text,text,text,text,text,boolean) from public,anon;
revoke all on function public.review_citizen_submission(uuid,public.moderation_outcome,text) from public,anon;
grant execute on function public.submit_citizen_proposal_safe(text,public.constitutional_topic,text,text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.review_citizen_submission(uuid,public.moderation_outcome,text) to authenticated;
