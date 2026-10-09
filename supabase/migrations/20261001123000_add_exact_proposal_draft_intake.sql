-- Add draft articles from an exact committee-accepted proposal source.
create or replace function public.add_draft_article_from_proposal(p_version_id uuid,p_submission_id uuid,p_article_number text,p_title text,p_wording text)
returns uuid language plpgsql set search_path to '' as $$
declare v_id uuid; v_cluster uuid;
begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 if not exists(select 1 from public.draft_versions where id=p_version_id and status='draft') then raise exception 'Only draft versions may be edited'; end if;
 select cluster_id into v_cluster from public.citizen_submissions where id=p_submission_id and workflow_step>=8 and not revision_required;
 if not found then raise exception 'Proposal is not eligible for drafting'; end if;
 if not exists(select 1 from public.proposal_committee_decisions where submission_id=p_submission_id and decision='accepted' and decided_at is not null) then raise exception 'Accepted committee decision is required'; end if;
 insert into public.draft_articles(version_id,article_number,title_sw,wording_sw,source_cluster_ids,ai_generated,proposal_disclaimer)
 values(p_version_id,nullif(trim(p_article_number),''),trim(p_title),p_wording,case when v_cluster is null then '[]'::jsonb else jsonb_build_array(v_cluster) end,false,'Maandishi haya ni pendekezo tu na hayawakilishi katiba rasmi.') returning id into v_id;
 insert into public.draft_article_lineage(draft_article_id,source_type,source_submission_id,source_label,note)
 values(v_id,'citizen_proposal',p_submission_id,'Committee-accepted citizen proposal','Explicit proposal-to-article drafting source');
 insert into public.draft_builder_actions(version_id,actor_id,kind,article_id,description,after_val)
 values(p_version_id,auth.uid(),'select_article',v_id,'Draft article added from committee-accepted citizen proposal',p_wording);
 update public.draft_versions set source_submission_ids=(select jsonb_agg(distinct x) from jsonb_array_elements(coalesce(source_submission_ids,'[]'::jsonb)||jsonb_build_array(p_submission_id)) x),updated_at=now() where id=p_version_id;
 return v_id;
end $$;
revoke all on function public.add_draft_article_from_proposal(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.add_draft_article_from_proposal(uuid,uuid,text,text,text) to authenticated;