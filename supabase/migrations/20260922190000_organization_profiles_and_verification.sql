alter table public.profiles add column if not exists account_type text not null default 'individual' check(account_type in ('individual','institution','university','ngo','law_society','court','ministry','media','professional_body','other'));
alter table public.profiles add column if not exists organization_name text;
alter table public.profiles add column if not exists organization_registration_no text;
alter table public.profiles add column if not exists organization_website text;
alter table public.profiles add column if not exists organization_verified boolean not null default false;
alter table public.profiles add column if not exists organization_verification_notes text;
alter table public.profiles add column if not exists organization_verified_at timestamptz;
alter table public.profiles add column if not exists organization_verified_by uuid references auth.users(id);

create or replace function public.set_organization_verification(p_user_id uuid,p_verified boolean,p_notes text default '')
returns void language plpgsql security definer set search_path=''
as $$ begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Admin or moderator required'; end if;
 update public.profiles set organization_verified=p_verified,organization_verification_notes=coalesce(p_notes,''),organization_verified_at=case when p_verified then now() else null end,organization_verified_by=case when p_verified then auth.uid() else null end,updated_at=now() where id=p_user_id and account_type<>'individual';
 if not found then raise exception 'Non-individual profile not found'; end if;
end; $$;
revoke all on function public.set_organization_verification(uuid,boolean,text) from public,anon;
grant execute on function public.set_organization_verification(uuid,boolean,text) to authenticated;

create or replace function public.protect_profile_authorization()
returns trigger language plpgsql set search_path=''
as $$ begin
 if auth.uid() is not null and not public.is_moderator_or_admin() then
   new.role=old.role; new.verification_tier=old.verification_tier; new.nida_verified=old.nida_verified; new.phone_verified=old.phone_verified;
   new.organization_verified=old.organization_verified; new.organization_verification_notes=old.organization_verification_notes; new.organization_verified_at=old.organization_verified_at; new.organization_verified_by=old.organization_verified_by;
 end if;
 return new;
end; $$;