create table if not exists public.article_highlights (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 document_id text not null,
 article_id text not null,
 highlighted_text text not null check (char_length(highlighted_text) between 2 and 1800),
 created_at timestamptz not null default now(),
 unique(user_id,document_id,article_id,highlighted_text)
);
create index if not exists article_highlights_user_article_idx on public.article_highlights(user_id,document_id,article_id,created_at desc);
alter table public.article_highlights enable row level security;
create policy "Users read own highlights" on public.article_highlights for select to authenticated using ((select auth.uid())=user_id);
create policy "Users create own highlights" on public.article_highlights for insert to authenticated with check ((select auth.uid())=user_id);
create policy "Users delete own highlights" on public.article_highlights for delete to authenticated using ((select auth.uid())=user_id);
grant select,insert,delete on public.article_highlights to authenticated;
