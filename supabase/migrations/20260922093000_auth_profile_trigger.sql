-- Create a safe public profile row whenever a new Auth user is created.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, display_name, role, verification_tier, language_pref)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name',''), split_part(coalesce(new.email,''),'@',1), 'Mwananchi'),
    'registered',
    case when new.email_confirmed_at is not null then 'email' else 'none' end,
    'sw'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Backfill is harmless on a fresh project and makes this migration reusable.
insert into public.profiles (id, display_name, role, verification_tier, language_pref)
select id,
       coalesce(nullif(raw_user_meta_data ->> 'display_name',''), split_part(coalesce(email,''),'@',1), 'Mwananchi'),
       'registered',
       case when email_confirmed_at is not null then 'email' else 'none' end,
       'sw'
from auth.users
on conflict (id) do nothing;
