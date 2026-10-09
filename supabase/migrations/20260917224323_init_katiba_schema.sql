create extension if not exists pgcrypto;

create type public.app_role as enum ('registered', 'verified_citizen', 'institution', 'law_society', 'academic', 'moderator', 'admin');
create type public.contribution_status as enum ('active', 'reported', 'removed');
create type public.suggestion_status as enum ('submitted', 'under_review', 'accepted', 'rejected', 'merged', 'polled');
create type public.poll_status as enum ('draft', 'open', 'closed', 'archived');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Mwananchi' check (char_length(display_name) between 2 and 80),
  role public.app_role not null default 'registered',
  verification_tier text not null default 'email' check (verification_tier in ('none','email','phone','nida')),
  nida_verified boolean not null default false,
  anonymity_default boolean not null default false,
  region text,
  language_pref text not null default 'sw' check (language_pref in ('sw','en')),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.constitution_documents (
  id text primary key,
  title_sw text not null,
  title_en text,
  year integer not null,
  version text not null,
  source_url text,
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.constitution_articles (
  id text primary key,
  document_id text not null references public.constitution_documents(id) on delete cascade,
  chapter_id text,
  article_number text not null,
  title_sw text,
  title_en text,
  body_sw text,
  body_en text,
  order_index integer not null default 0,
  is_muungano boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  is_published boolean not null default false,
  updated_at timestamptz not null default now(),
  unique(document_id, article_number)
);

create table public.discussions (
  id uuid primary key default gen_random_uuid(),
  article_id text not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default '',
  body text not null check (char_length(body) between 2 and 5000),
  is_anonymous boolean not null default false,
  status public.contribution_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.suggestions (
  id uuid primary key default gen_random_uuid(),
  article_id text not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default '',
  rationale text not null check (char_length(rationale) between 2 and 5000),
  proposed_text_sw text,
  proposed_text_en text,
  status public.suggestion_status not null default 'submitted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.polls (
  id uuid primary key default gen_random_uuid(),
  article_id text not null,
  title_sw text not null,
  title_en text,
  status public.poll_status not null default 'draft',
  opens_at timestamptz not null default now(),
  closes_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  label_sw text not null,
  label_en text,
  order_index integer not null default 0,
  unique(poll_id, order_index)
);

create table public.votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  poll_option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(poll_id, user_id)
);

create table public.bookmarks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  article_id text not null,
  created_at timestamptz not null default now(),
  primary key(user_id, article_id)
);

create table public.discussion_reactions (
  discussion_id uuid not null references public.discussions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(discussion_id, user_id)
);

create table public.suggestion_reactions (
  suggestion_id uuid not null references public.suggestions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null check (reaction in ('endorse','oppose')),
  created_at timestamptz not null default now(),
  primary key(suggestion_id, user_id)
);

create index discussions_article_created_idx on public.discussions(article_id, created_at desc) where status = 'active';
create index suggestions_article_created_idx on public.suggestions(article_id, created_at desc);
create index polls_article_status_idx on public.polls(article_id, status);
create index votes_poll_idx on public.votes(poll_id);

alter table public.profiles enable row level security;
alter table public.constitution_documents enable row level security;
alter table public.constitution_articles enable row level security;
alter table public.discussions enable row level security;
alter table public.suggestions enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.votes enable row level security;
alter table public.bookmarks enable row level security;
alter table public.discussion_reactions enable row level security;
alter table public.suggestion_reactions enable row level security;

create policy "Published documents are public" on public.constitution_documents for select to anon, authenticated using (is_published);
create policy "Published articles are public" on public.constitution_articles for select to anon, authenticated using (is_published);
create policy "Profiles are publicly readable" on public.profiles for select to anon, authenticated using (true);
create policy "Users update their profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "Active discussions are public" on public.discussions for select to anon, authenticated using (status = 'active');
create policy "Users create discussions" on public.discussions for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Users update discussions" on public.discussions for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users delete discussions" on public.discussions for delete to authenticated using ((select auth.uid()) = user_id);

create policy "Visible suggestions are public" on public.suggestions for select to anon, authenticated using (status <> 'rejected');
create policy "Users create suggestions" on public.suggestions for insert to authenticated with check ((select auth.uid()) = user_id and status = 'submitted');
create policy "Users update pending suggestions" on public.suggestions for update to authenticated using ((select auth.uid()) = user_id and status = 'submitted') with check ((select auth.uid()) = user_id and status = 'submitted');
create policy "Users delete pending suggestions" on public.suggestions for delete to authenticated using ((select auth.uid()) = user_id and status = 'submitted');

create policy "Open and closed polls are public" on public.polls for select to anon, authenticated using (status in ('open','closed'));
create policy "Options for visible polls are public" on public.poll_options for select to anon, authenticated using (exists (select 1 from public.polls p where p.id = poll_id and p.status in ('open','closed')));
create policy "Users read their votes" on public.votes for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users cast their vote" on public.votes for insert to authenticated with check ((select auth.uid()) = user_id and exists (select 1 from public.polls p where p.id = poll_id and p.status = 'open' and p.opens_at <= now() and (p.closes_at is null or p.closes_at > now())) and exists (select 1 from public.poll_options o where o.id = poll_option_id and o.poll_id = votes.poll_id));
create policy "Users change their vote" on public.votes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id and exists (select 1 from public.poll_options o where o.id = poll_option_id and o.poll_id = votes.poll_id));

create policy "Users read bookmarks" on public.bookmarks for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users create bookmarks" on public.bookmarks for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Users remove bookmarks" on public.bookmarks for delete to authenticated using ((select auth.uid()) = user_id);
create policy "Reactions are public" on public.discussion_reactions for select to anon, authenticated using (true);
create policy "Users create discussion reactions" on public.discussion_reactions for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Users remove discussion reactions" on public.discussion_reactions for delete to authenticated using ((select auth.uid()) = user_id);
create policy "Suggestion reactions are public" on public.suggestion_reactions for select to anon, authenticated using (true);
create policy "Users create suggestion reactions" on public.suggestion_reactions for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Users change suggestion reactions" on public.suggestion_reactions for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users remove suggestion reactions" on public.suggestion_reactions for delete to authenticated using ((select auth.uid()) = user_id);

create schema if not exists private;
create or replace function private.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, language_pref)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(new.email, 'Mwananchi'), '@', 1)), coalesce(nullif(new.raw_user_meta_data ->> 'language_pref', ''), 'sw'));
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.handle_new_user();

grant usage on schema public to anon, authenticated;
grant select on public.constitution_documents, public.constitution_articles, public.profiles, public.discussions, public.suggestions, public.polls, public.poll_options, public.discussion_reactions, public.suggestion_reactions to anon, authenticated;
grant insert, update, delete on public.discussions, public.suggestions, public.votes, public.bookmarks, public.discussion_reactions, public.suggestion_reactions to authenticated;
grant update(display_name, anonymity_default, region, language_pref, avatar_url) on public.profiles to authenticated;
