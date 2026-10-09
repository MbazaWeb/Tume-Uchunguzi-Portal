-- Human legal review and committee approval for draft articles.
create or replace function public.record_legal_review(p_article_id uuid,p_approved boolean,p_notes text,p_minority_position text)
returns void language plpgsql security definer set search_path=''
as $$ declare v_version uuid; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 select version_id into v_version from public.draft_articles where id=p_article_id;
 if v_version is null then raise exception 'Draft article not found'; end if;
 if not exists(select 1 from public.draft_versions where id=v_version and status='draft') then raise exception 'Only draft versions may be reviewed'; end if;
 update public.draft_articles set legally_reviewed=p_approved,approval_stage=case when p_approved then 'committee_approval'::public.approval_stage else 'legal_review'::public.approval_stage end,
 minority_positions=case when nullif(trim(p_minority_position),'') is null then minority_positions else minority_positions || jsonb_build_array(jsonb_build_object('text',trim(p_minority_position),'recorded_at',now(),'recorded_by',auth.uid())) end,
 updated_at=now() where id=p_article_id;
 insert into public.approval_decisions(article_id,stage,decision,rationale,actor_id) values(p_article_id,'legal_review',case when p_approved then 'approved_for_committee' else 'returned_for_revision' end,coalesce(p_notes,''),auth.uid());
 insert into public.draft_builder_actions(version_id,actor_id,kind,article_id,description) values(v_version,auth.uid(),'mark_legally_reviewed',p_article_id,case when p_approved then 'Legal review approved; moved to committee approval' else 'Legal review returned article for revision' end);
end; $$;

create or replace function public.record_committee_approval_safe(p_article_id uuid,p_approved boolean,p_rationale text)
returns void language plpgsql security definer set search_path=''
as $$ declare v_version uuid; v_reviewed boolean; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 select version_id,legally_reviewed into v_version,v_reviewed from public.draft_articles where id=p_article_id;
 if v_version is null then raise exception 'Draft article not found'; end if;
 if not exists(select 1 from public.draft_versions where id=v_version and status='draft') then raise exception 'Only draft versions may receive committee decisions'; end if;
 if not v_reviewed then raise exception 'Legal review is required before committee approval'; end if;
 update public.draft_articles set approval_stage=case when p_approved then 'published'::public.approval_stage else 'legal_review'::public.approval_stage end,legally_reviewed=case when p_approved then true else false end,updated_at=now() where id=p_article_id;
 insert into public.approval_decisions(article_id,stage,decision,rationale,actor_id) values(p_article_id,'committee_approval',case when p_approved then 'approved_for_draft_publication' else 'returned_to_legal_review' end,coalesce(p_rationale,''),auth.uid());
 insert into public.draft_builder_actions(version_id,actor_id,kind,article_id,description) values(v_version,auth.uid(),'attach_reviewer_notes',p_article_id,case when p_approved then 'Committee approved article for draft publication' else 'Committee returned article to legal review' end);
end; $$;

create or replace function public.publish_draft_safe(p_version_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 if not exists(select 1 from public.draft_versions where id=p_version_id and status='draft') then raise exception 'Draft version not found'; end if;
 if not exists(select 1 from public.draft_articles where version_id=p_version_id) then raise exception 'Draft has no articles'; end if;
 if exists(select 1 from public.draft_articles where version_id=p_version_id and (legally_reviewed=false or approval_stage<>'published')) then raise exception 'Every article requires legal review and committee approval before publication'; end if;
 update public.draft_versions set status='published',legally_reviewed=true,published_at=now(),updated_at=now() where id=p_version_id;
 insert into public.draft_builder_actions(version_id,actor_id,kind,description) values(p_version_id,auth.uid(),'publish_version','Draft version published after legal review and committee approval');
end; $$;

revoke all on function public.record_legal_review(uuid,boolean,text,text) from public,anon;
revoke all on function public.record_committee_approval_safe(uuid,boolean,text) from public,anon;
revoke all on function public.publish_draft_safe(uuid) from public,anon;
grant execute on function public.record_legal_review(uuid,boolean,text,text) to authenticated;
grant execute on function public.record_committee_approval_safe(uuid,boolean,text) to authenticated;
grant execute on function public.publish_draft_safe(uuid) to authenticated;