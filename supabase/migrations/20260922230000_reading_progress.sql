create table if not exists public.reading_progress (
 user_id uuid not null references public.profiles(id) on delete cascade,
 document_id text not null,
 article_id text not null,
 last_read_at timestamptz not null default now(),
 primary key(user_id,document_id,article_id)
);
alter table public.reading_progress enable row level security;
create policy "Users read own reading progress" on public.reading_progress for select to authenticated using ((select auth.uid())=user_id);
create policy "Users create own reading progress" on public.reading_progress for insert to authenticated with check ((select auth.uid())=user_id);
create policy "Users update own reading progress" on public.reading_progress for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create policy "Users delete own reading progress" on public.reading_progress for delete to authenticated using ((select auth.uid())=user_id);
grant select,insert,update,delete on public.reading_progress to authenticated;
