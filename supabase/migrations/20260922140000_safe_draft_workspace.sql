-- Safe draft workspace RPCs. Published versions are immutable.
create or replace function public.create_draft_version(p_title text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; v_no int; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 select coalesce(max(version_number),0)+1 into v_no from public.draft_versions;
 insert into public.draft_versions(version_number,title,status,created_by,generation_method,ai_generated) values(v_no,p_title,'draft',auth.uid(),'manual',false) returning id into v_id;
 insert into public.draft_builder_actions(version_id,actor_id,kind,description) values(v_id,auth.uid(),'create_version','Draft version created manually');
 return v_id;
end; $$;

create or replace function public.add_draft_article(p_version_id uuid,p_article_number text,p_title text,p_wording text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 if not exists(select 1 from public.draft_versions where id=p_version_id and status='draft') then raise exception 'Only draft versions may be edited'; end if;
 insert into public.draft_articles(version_id,article_number,title_sw,wording_sw,ai_generated,proposal_disclaimer)
 values(p_version_id,nullif(trim(p_article_number),''),trim(p_title),p_wording,false,'Maandishi haya ni pendekezo tu na hayawakilishi katiba rasmi.') returning id into v_id;
 insert into public.draft_builder_actions(version_id,actor_id,kind,article_id,description,after_val) values(p_version_id,auth.uid(),'select_article',v_id,'Draft article added',p_wording);
 return v_id;
end; $$;

create or replace function public.mark_draft_article_reviewed(p_article_id uuid,p_reviewed boolean)
returns void language plpgsql security definer set search_path=''
as $$ declare v_version uuid; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 select version_id into v_version from public.draft_articles where id=p_article_id;
 if not exists(select 1 from public.draft_versions where id=v_version and status='draft') then raise exception 'Published or archived versions are immutable'; end if;
 update public.draft_articles set legally_reviewed=p_reviewed,updated_at=now() where id=p_article_id;
 insert into public.draft_builder_actions(version_id,actor_id,kind,article_id,description) values(v_version,auth.uid(),'mark_legally_reviewed',p_article_id,case when p_reviewed then 'Marked legally reviewed' else 'Legal review mark removed' end);
end; $$;

create or replace function public.publish_draft_safe(p_version_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 if not exists(select 1 from public.draft_versions where id=p_version_id and status='draft') then raise exception 'Draft version not found'; end if;
 if exists(select 1 from public.draft_articles where version_id=p_version_id and legally_reviewed=false) then raise exception 'All draft articles must be legally reviewed before publication'; end if;
 update public.draft_versions set status='published',legally_reviewed=true,published_at=now(),updated_at=now() where id=p_version_id;
 insert into public.draft_builder_actions(version_id,actor_id,kind,description) values(p_version_id,auth.uid(),'publish_version','Draft version published after human legal review');
end; $$;

revoke all on function public.create_draft_version(text) from public,anon;
revoke all on function public.add_draft_article(uuid,text,text,text) from public,anon;
revoke all on function public.mark_draft_article_reviewed(uuid,boolean) from public,anon;
revoke all on function public.publish_draft_safe(uuid) from public,anon;
grant execute on function public.create_draft_version(text) to authenticated;
grant execute on function public.add_draft_article(uuid,text,text,text) to authenticated;
grant execute on function public.mark_draft_article_reviewed(uuid,boolean) to authenticated;
grant execute on function public.publish_draft_safe(uuid) to authenticated;
