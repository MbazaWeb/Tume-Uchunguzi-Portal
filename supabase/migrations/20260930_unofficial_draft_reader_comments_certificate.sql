alter table public.unofficial_constitution_drafts add column if not exists certificate_token uuid;
alter table public.unofficial_constitution_drafts add column if not exists submitted_at timestamptz;
alter table public.unofficial_constitution_drafts add column if not exists published_at timestamptz;
create unique index if not exists unofficial_draft_certificate_token_idx on public.unofficial_constitution_drafts(certificate_token) where certificate_token is not null;
create table if not exists public.unofficial_draft_comments (
 id uuid primary key default gen_random_uuid(),
 draft_id uuid not null references public.unofficial_constitution_drafts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 body text not null check (char_length(body) between 2 and 3000),
 created_at timestamptz not null default now()
);
alter table public.unofficial_draft_comments enable row level security;
revoke all on table public.unofficial_draft_comments from anon, authenticated;
grant select on table public.unofficial_draft_comments to anon;
grant select,insert,delete on table public.unofficial_draft_comments to authenticated;
create policy "Public reads comments on published drafts" on public.unofficial_draft_comments for select to anon,authenticated using (exists(select 1 from public.unofficial_constitution_drafts d where d.id=draft_id and d.status='published'));
create policy "Users comment as themselves" on public.unofficial_draft_comments for insert to authenticated with check ((select auth.uid())=user_id and exists(select 1 from public.unofficial_constitution_drafts d where d.id=draft_id and d.status='published'));
create policy "Users delete own comments" on public.unofficial_draft_comments for delete to authenticated using ((select auth.uid())=user_id);
create index if not exists unofficial_draft_comments_draft_idx on public.unofficial_draft_comments(draft_id,created_at desc);
