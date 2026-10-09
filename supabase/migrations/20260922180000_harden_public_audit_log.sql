-- Harden public audit log: clients may read, but only controlled moderator/admin RPC writes.
drop policy if exists "System inserts audit events" on public.audit_events;
revoke insert, update, delete on public.audit_events from anon, authenticated;
create or replace function public.log_audit_event(p_kind public.audit_event_kind,p_subject text default null,p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 insert into public.audit_events(kind,subject_id,actor_id,payload) values(p_kind,p_subject,auth.uid(),coalesce(p_payload,'{}'::jsonb)) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.log_audit_event(public.audit_event_kind,text,jsonb) from public,anon;
grant execute on function public.log_audit_event(public.audit_event_kind,text,jsonb) to authenticated;