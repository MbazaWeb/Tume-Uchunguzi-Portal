-- Threaded public discussions and moderator controls.
alter table public.discussions add column if not exists parent_id uuid references public.discussions(id) on delete cascade;
create index if not exists discussions_parent_idx on public.discussions(parent_id);

create or replace function public.moderate_discussion(p_discussion_id uuid,p_hide boolean)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role in ('moderator','admin')) then raise exception 'Moderator or admin required'; end if;
 update public.discussions set status=case when p_hide then 'hidden'::public.contribution_status else 'active'::public.contribution_status end,updated_at=now() where id=p_discussion_id;
 if not found then raise exception 'Discussion not found'; end if;
end; $$;
revoke all on function public.moderate_discussion(uuid,boolean) from public,anon;
grant execute on function public.moderate_discussion(uuid,boolean) to authenticated;
