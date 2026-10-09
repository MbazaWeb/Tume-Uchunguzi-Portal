create table if not exists public.library_uploads (
 id uuid primary key default gen_random_uuid(),
 title text not null check (char_length(title) between 3 and 240),
 document_type text not null check (document_type in ('katiba','rasimu','nyaraka_nyingine')),
 year integer, edition text, source_filename text not null,
 source_format text not null check (source_format in ('txt','pdf')),
 source_text text not null, converted_json jsonb not null default '[]'::jsonb,
 article_count integer not null default 0,
 status text not null default 'published' check (status in ('draft','published')),
 uploaded_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.library_uploads enable row level security;
create policy "Published library uploads are readable" on public.library_uploads for select to anon, authenticated using (status='published' or uploaded_by=(select auth.uid()) or public.is_moderator_or_admin());
create policy "Admins manage library uploads" on public.library_uploads for all to authenticated using (public.is_moderator_or_admin()) with check (public.is_moderator_or_admin());
grant select on public.library_uploads to anon, authenticated;
grant insert,update,delete on public.library_uploads to authenticated;
create index library_uploads_status_created_idx on public.library_uploads(status,created_at desc);
