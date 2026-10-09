alter table public.unofficial_constitution_drafts
  add column if not exists review_status text not null default 'not_submitted',
  add column if not exists review_note text,
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz;
alter table public.unofficial_constitution_drafts drop constraint if exists unofficial_constitution_drafts_review_status_check;
alter table public.unofficial_constitution_drafts add constraint unofficial_constitution_drafts_review_status_check check (review_status in ('not_submitted','pending','returned','approved'));

drop policy if exists "Users update own unofficial drafts" on public.unofficial_constitution_drafts;
drop policy if exists "Users update own editable unofficial drafts" on public.unofficial_constitution_drafts;
create policy "Users update own editable unofficial drafts" on public.unofficial_constitution_drafts for update to authenticated
using ((select auth.uid()) = user_id and status <> 'published')
with check ((select auth.uid()) = user_id and status in ('draft','submitted') and review_status in ('not_submitted','pending','returned') and certificate_token is null and published_at is null and reviewed_by is null and reviewed_at is null);

create or replace function public.submit_unofficial_draft_for_review(p_draft_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 update public.unofficial_constitution_drafts set status='submitted',review_status='pending',review_note=null,submitted_at=coalesce(submitted_at,now()),reviewed_by=null,reviewed_at=null,updated_at=now() where id=p_draft_id and user_id=auth.uid() and status<>'published';
 if not found then raise exception 'Draft not found or cannot be submitted'; end if;
end $$;
create or replace function public.review_unofficial_draft(p_draft_id uuid,p_action text,p_note text default null) returns void language plpgsql security definer set search_path='' as $$
declare v_role text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select role::text into v_role from public.profiles where id=auth.uid();
 if v_role not in ('admin','moderator') then raise exception 'Admin or moderator access required'; end if;
 if p_action not in ('approve','return') then raise exception 'Invalid review action'; end if;
 if p_action='return' and length(trim(coalesce(p_note,'')))<3 then raise exception 'A return note is required'; end if;
 update public.unofficial_constitution_drafts set review_status=case when p_action='approve' then 'approved' else 'returned' end,review_note=nullif(trim(coalesce(p_note,'')),''),reviewed_by=auth.uid(),reviewed_at=now(),status=case when p_action='approve' then 'published' else 'draft' end,published_at=case when p_action='approve' then coalesce(published_at,now()) else null end,certificate_token=case when p_action='approve' then coalesce(certificate_token,gen_random_uuid()) else null end,updated_at=now() where id=p_draft_id and review_status='pending' and status='submitted';
 if not found then raise exception 'Draft is not pending review'; end if;
end $$;
revoke execute on function public.submit_unofficial_draft_for_review(uuid) from public,anon;
grant execute on function public.submit_unofficial_draft_for_review(uuid) to authenticated;
revoke execute on function public.review_unofficial_draft(uuid,text,text) from public,anon;
grant execute on function public.review_unofficial_draft(uuid,text,text) to authenticated;