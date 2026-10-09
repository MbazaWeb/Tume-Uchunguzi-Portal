create table if not exists public.notifications(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null, title text not null, body text not null default '', href text, read_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists notifications_user_created_idx on public.notifications(user_id,created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "Users read own notifications" on public.notifications;
create policy "Users read own notifications" on public.notifications for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists "Users update own notifications" on public.notifications;
create policy "Users update own notifications" on public.notifications for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
revoke insert,delete on public.notifications from anon,authenticated;
grant select,update on public.notifications to authenticated;

create or replace function public.notify_verification_request_change() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.status is distinct from old.status or new.admin_note is distinct from old.admin_note then
 insert into public.notifications(user_id,kind,title,body,href) values(new.user_id,'verification',
 case new.status when 'approved' then 'Verification imekubaliwa' when 'rejected' then 'Verification imekataliwa' when 'more_info_requested' then 'Taarifa zaidi zinahitajika' else 'Verification inafanyiwa mapitio' end,
 coalesce(new.admin_note,'Ombi lako la verification limesasishwa.'),'/account');
end if; return new; end $$;
drop trigger if exists trg_notify_verification_request_change on public.verification_requests;
create trigger trg_notify_verification_request_change after update on public.verification_requests for each row execute function public.notify_verification_request_change();

create or replace function public.notify_discussion_reply() returns trigger language plpgsql security definer set search_path='' as $$
declare owner_id uuid; begin if new.parent_id is not null then select user_id into owner_id from public.discussions where id=new.parent_id;
 if owner_id is not null and owner_id<>new.user_id then insert into public.notifications(user_id,kind,title,body,href) values(owner_id,'discussion_reply','Jibu jipya kwenye mjadala','Mshiriki amejibu hoja yako.','/discussions'); end if;
end if; return new; end $$;
drop trigger if exists trg_notify_discussion_reply on public.discussions;
create trigger trg_notify_discussion_reply after insert on public.discussions for each row execute function public.notify_discussion_reply();

create or replace function public.mark_all_notifications_read() returns integer language plpgsql security invoker set search_path='' as $$
declare n integer; begin update public.notifications set read_at=now() where user_id=auth.uid() and read_at is null; get diagnostics n=row_count; return n; end $$;
revoke all on function public.mark_all_notifications_read() from public,anon; grant execute on function public.mark_all_notifications_read() to authenticated;