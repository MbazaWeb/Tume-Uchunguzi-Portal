drop policy if exists "Group owners upload media" on storage.objects;
create policy "Group owners upload media" on storage.objects for insert to authenticated
with check (
 bucket_id='community-media'
 and (storage.foldername(storage.objects.name))[1]='groups'
 and exists(select 1 from public.community_groups g where g.id::text=(storage.foldername(storage.objects.name))[2] and g.owner_id=(select auth.uid()))
);
drop policy if exists "Group owners update media" on storage.objects;
create policy "Group owners update media" on storage.objects for update to authenticated
using (
 bucket_id='community-media'
 and (storage.foldername(storage.objects.name))[1]='groups'
 and exists(select 1 from public.community_groups g where g.id::text=(storage.foldername(storage.objects.name))[2] and g.owner_id=(select auth.uid()))
)
with check (
 bucket_id='community-media'
 and (storage.foldername(storage.objects.name))[1]='groups'
 and exists(select 1 from public.community_groups g where g.id::text=(storage.foldername(storage.objects.name))[2] and g.owner_id=(select auth.uid()))
);
