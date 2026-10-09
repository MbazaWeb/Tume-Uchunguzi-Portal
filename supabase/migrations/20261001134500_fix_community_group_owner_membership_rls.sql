create or replace function public.add_group_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.owner_id is null or new.owner_id <> (select auth.uid()) then
    raise exception 'Group owner must be the authenticated creator';
  end if;
  insert into public.community_group_members(group_id,user_id,role,status)
  values(new.id,new.owner_id,'owner','active')
  on conflict(group_id,user_id) do update set role='owner',status='active';
  return new;
end
$$;
revoke all on function public.add_group_owner_membership() from public, anon, authenticated;
