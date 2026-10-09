insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('verification-documents','verification-documents',false,5242880,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Users upload own verification documents" on storage.objects;
create policy "Users upload own verification documents" on storage.objects for insert to authenticated
with check(bucket_id='verification-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);

drop policy if exists "Users read own verification documents" on storage.objects;
create policy "Users read own verification documents" on storage.objects for select to authenticated
using(bucket_id='verification-documents' and ((storage.foldername(name))[1]=(select auth.uid())::text or public.is_moderator_or_admin()));

drop policy if exists "Users delete own verification documents" on storage.objects;
create policy "Users delete own verification documents" on storage.objects for delete to authenticated
using(bucket_id='verification-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);