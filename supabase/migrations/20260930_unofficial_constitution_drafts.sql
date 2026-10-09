-- Unofficial public constitution drafts: separate from official Constitution source files.
create table if not exists public.unofficial_constitution_drafts (
id uuid primary key,user_id uuid references auth.users(id) on delete cascade,title text not null default '',creator_name text not null default '',creator_type text not null default 'citizen',constitution_type text not null default 'full',summary text not null default '',status text not null default 'draft' check (status in ('draft','submitted','published')),chapters jsonb not null default '[]'::jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table public.unofficial_constitution_drafts enable row level security;
revoke all on table public.unofficial_constitution_drafts from anon, authenticated;
grant select on table public.unofficial_constitution_drafts to anon;
grant select,insert,update,delete on table public.unofficial_constitution_drafts to authenticated;
drop policy if exists "Public can read published unofficial drafts" on public.unofficial_constitution_drafts;
create policy "Public can read published unofficial drafts" on public.unofficial_constitution_drafts for select to anon,authenticated using (status='published' or (select auth.uid())=user_id);
drop policy if exists "Users create own unofficial drafts" on public.unofficial_constitution_drafts;
create policy "Users create own unofficial drafts" on public.unofficial_constitution_drafts for insert to authenticated with check ((select auth.uid())=user_id);
drop policy if exists "Users update own unofficial drafts" on public.unofficial_constitution_drafts;
create policy "Users update own unofficial drafts" on public.unofficial_constitution_drafts for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
drop policy if exists "Users delete own unofficial drafts" on public.unofficial_constitution_drafts;
create policy "Users delete own unofficial drafts" on public.unofficial_constitution_drafts for delete to authenticated using ((select auth.uid())=user_id);
create index if not exists unofficial_constitution_drafts_user_idx on public.unofficial_constitution_drafts(user_id);
create index if not exists unofficial_constitution_drafts_status_updated_idx on public.unofficial_constitution_drafts(status,updated_at desc);
