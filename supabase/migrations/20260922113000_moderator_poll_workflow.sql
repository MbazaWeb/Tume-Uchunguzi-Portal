-- Moderator/Admin RPC surface for suggestion review and advisory poll management.
create or replace function public.is_moderator_or_admin()
returns boolean language sql stable security invoker set search_path=''
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role in ('moderator','admin')); $$;

create or replace function public.review_suggestion(p_suggestion_id uuid,p_status public.suggestion_status)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 if p_status not in ('under_review','accepted','rejected') then raise exception 'Invalid review status'; end if;
 update public.suggestions set status=p_status,updated_at=now() where id=p_suggestion_id;
 if not found then raise exception 'Suggestion not found'; end if;
end; $$;

create or replace function public.create_advisory_poll(p_suggestion_id uuid,p_stage public.poll_stage,p_title text,p_description text,p_options text[])
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_article text; v_opt text; v_i int:=0;
begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 select article_id into v_article from public.suggestions where id=p_suggestion_id and status in ('accepted','under_review');
 if v_article is null then raise exception 'Suggestion must exist and be under review or accepted'; end if;
 if coalesce(array_length(p_options,1),0)<2 then raise exception 'At least two poll options are required'; end if;
 insert into public.workflow_polls(article_id,stage,title,description,status,created_by,auto_approved,human_reviewed)
 values(v_article,p_stage,p_title,coalesce(p_description,''),'draft',auth.uid(),false,true) returning id into v_id;
 foreach v_opt in array p_options loop
   v_i:=v_i+1;
   if nullif(trim(v_opt),'') is not null then insert into public.workflow_poll_options(poll_id,label,order_index) values(v_id,trim(v_opt),v_i); end if;
 end loop;
 update public.suggestions set status='polled',updated_at=now() where id=p_suggestion_id;
 return v_id;
end; $$;

create or replace function public.set_advisory_poll_status(p_poll_id uuid,p_status public.poll_stage_status)
returns void language plpgsql security definer set search_path=''
as $$ begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 if p_status not in ('open','closed','cancelled') then raise exception 'Invalid poll status'; end if;
 update public.workflow_polls set status=p_status,opens_at=case when p_status='open' then now() else opens_at end,
 closes_at=case when p_status='closed' then now() when p_status='open' then null else closes_at end,
 updated_at=now(),human_reviewed=true,auto_approved=false where id=p_poll_id;
 if not found then raise exception 'Poll not found'; end if;
end; $$;

revoke all on function public.is_moderator_or_admin() from public,anon;
revoke all on function public.review_suggestion(uuid,public.suggestion_status) from public,anon;
revoke all on function public.create_advisory_poll(uuid,public.poll_stage,text,text,text[]) from public,anon;
revoke all on function public.set_advisory_poll_status(uuid,public.poll_stage_status) from public,anon;
grant execute on function public.is_moderator_or_admin() to authenticated;
grant execute on function public.review_suggestion(uuid,public.suggestion_status) to authenticated;
grant execute on function public.create_advisory_poll(uuid,public.poll_stage,text,text,text[]) to authenticated;
grant execute on function public.set_advisory_poll_status(uuid,public.poll_stage_status) to authenticated;
