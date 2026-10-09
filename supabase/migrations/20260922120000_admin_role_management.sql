-- Only administrators may assign application roles.
create or replace function public.set_user_role(p_user_id uuid,p_role public.app_role)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
   raise exception 'Administrator required';
 end if;
 if p_user_id=auth.uid() and p_role<>'admin' then
   raise exception 'Administrator cannot remove their own admin role';
 end if;
 update public.profiles set role=p_role,updated_at=now() where id=p_user_id;
 if not found then raise exception 'User profile not found'; end if;
end; $$;
revoke all on function public.set_user_role(uuid,public.app_role) from public,anon;
grant execute on function public.set_user_role(uuid,public.app_role) to authenticated;

-- Prevent ordinary users from changing protected identity/authorization fields
-- while still allowing edits to their non-sensitive profile fields.
create or replace function public.protect_profile_authorization()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid()=old.id and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then
   new.role:=old.role;
   new.verification_tier:=old.verification_tier;
   new.nida_verified:=old.nida_verified;
   new.phone_verified:=old.phone_verified;
 end if;
 return new;
end; $$;
revoke all on function public.protect_profile_authorization() from public,anon,authenticated;
drop trigger if exists protect_profile_authorization_fields on public.profiles;
create trigger protect_profile_authorization_fields before update on public.profiles
for each row execute function public.protect_profile_authorization();
