create table if not exists public.law_constitution_links(id uuid primary key default gen_random_uuid(),library_upload_id uuid not null references public.library_uploads(id) on delete cascade,section_number text not null,constitution_document_id text not null,constitution_article_id text not null,note text,created_by uuid references public.profiles(id) on delete set null,created_at timestamptz not null default now(),unique(library_upload_id,section_number,constitution_document_id,constitution_article_id));
alter table public.law_constitution_links enable row level security;
create policy "Law constitution links public read" on public.law_constitution_links for select to anon,authenticated using(true);
create policy "Admins manage law constitution links" on public.law_constitution_links for all to authenticated using(public.is_moderator_or_admin()) with check(public.is_moderator_or_admin());
grant select on public.law_constitution_links to anon,authenticated;
grant insert,update,delete on public.law_constitution_links to authenticated;
create index if not exists law_constitution_links_section_idx on public.law_constitution_links(library_upload_id,section_number);