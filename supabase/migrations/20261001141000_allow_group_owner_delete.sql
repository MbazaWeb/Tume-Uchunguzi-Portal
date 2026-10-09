create policy "Owners delete groups"
on public.community_groups
for delete
to authenticated
using ((select auth.uid()) = owner_id);
