-- Profile verification workflow. Verification is admin-controlled; users cannot self-verify.
alter table public.profiles add column if not exists phone_verified boolean not null default false;

create or replace function public.set_user_verification(p_user_id uuid,p_tier text)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then raise exception 'Administrator required'; end if;
 if p_tier not in ('email','phone','nida') then raise exception 'Invalid verification tier'; end if;
 update public.profiles set
   verification_tier=p_tier,
   phone_verified=(p_tier in ('phone','nida')),
   nida_verified=(p_tier='nida'),
   role=case when p_tier in ('phone','nida') and role='registered' then 'verified_citizen'::public.app_role else role end,
   updated_at=now()
 where id=p_user_id;
 if not found then raise exception 'User profile not found'; end if;
end; $$;
revoke all on function public.set_user_verification(uuid,text) from public,anon;
grant execute on function public.set_user_verification(uuid,text) to authenticated;

create or replace function public.protect_profile_authorization()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid()=old.id and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') then
   new.role:=old.role; new.verification_tier:=old.verification_tier;
   new.nida_verified:=old.nida_verified; new.phone_verified:=old.phone_verified;
 end if;
 return new;
end; $$;
