-- Dedicated minimal schema for the Tume Uchunguzi portal.
-- This database contains inquiry reporting only; it does not install Katiba Yetu features.

create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Mwananchi' check (char_length(display_name) between 2 and 80),
  role text not null default 'citizen' check (role in ('citizen','admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update(display_name) on public.profiles to authenticated;

create policy "Users read their own Tume profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Users update their own Tume display name"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create or replace function public.guard_tume_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.role is distinct from old.role
     and coalesce(auth.role(), '') <> 'service_role'
     and coalesce(old.role, '') <> 'admin' then
    raise exception 'Only an authorized Tume administrator can change account roles'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_tume_profile_role_change() from public, anon, authenticated;

create trigger guard_tume_profile_role_change
  before update of role on public.profiles
  for each row execute function public.guard_tume_profile_role_change();

create or replace function public.handle_tume_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(new.email, 'Mwananchi'), '@', 1))
  );
  return new;
end;
$$;

revoke all on function public.handle_tume_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_tume_new_user();
