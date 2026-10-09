-- =============================================================================
-- Katiba Yetu — Migration 002: Workflow tables & database functions
-- Covers: citizen submissions, moderation, proposal clusters, multi-stage
-- polling, draft builder, approval workflow, audit events, full-text search,
-- vote tallies, and all helper functions / triggers.
-- =============================================================================

-- ─── Extensions ──────────────────────────────────────────────────────────────
create extension if not exists unaccent;

-- ─── Enums ───────────────────────────────────────────────────────────────────

create type public.submission_status as enum (
  'submitted',
  'validation_failed',
  'in_moderation',
  'flagged',
  'duplicate_detected',
  'merged',
  'topic_classified',
  'clustered',
  'rejected_by_moderator',
  'withdrawn'
);

create type public.constitutional_topic as enum (
  'state','union','equality','expression','religion','association',
  'property','duties','governance','judiciary','legislature','executive',
  'citizenship','rights_arrest','labor','education','health','environment','other'
);

create type public.moderation_event_kind as enum (
  'validation','harmful_screening','duplicate_detection','topic_classification',
  'clustering','human_review','rejection','restoration'
);

create type public.moderation_outcome as enum (
  'passed','flagged','rejected','merged','restored','manual_override'
);

create type public.poll_stage as enum (
  'problem_confirmation','policy_direction','article_wording','approval_for_draft'
);

create type public.poll_stage_status as enum ('draft','open','closed','cancelled');

create type public.draft_builder_action_kind as enum (
  'create_version','select_article','assign_chapter','assign_article_number',
  'reorder_chapter','edit_wording','attach_reviewer_notes','send_back_for_discussion',
  'request_poll','mark_legally_reviewed','publish_version','archive_version',
  'restore_from_version'
);

create type public.draft_version_status as enum ('draft','published','archived');

create type public.approval_stage as enum (
  'citizen_input','moderation','clustering','legal_review',
  'committee_approval','published'
);

create type public.audit_event_kind as enum (
  'submission_created','submission_status_changed','moderation_event',
  'cluster_created','cluster_merged','ai_generation_run','poll_created',
  'poll_status_changed','vote_cast','draft_version_created','draft_version_published',
  'draft_version_archived','draft_version_restored','wording_edited',
  'legal_review_completed','committee_decision','article_published'
);

-- ─── Citizen Submissions ─────────────────────────────────────────────────────

create table public.citizen_submissions (
  id               uuid primary key default gen_random_uuid(),
  title            text not null check (char_length(title) between 5 and 200),
  topic            public.constitutional_topic not null default 'other',
  affected_article_id text references public.constitution_articles(id) on delete set null,
  problem          text not null check (char_length(problem) between 10 and 3000),
  proposed_wording_sw text,
  proposed_wording_en text,
  rationale        text not null check (char_length(rationale) between 10 and 5000),
  supporting_evidence text,
  region           text,
  anonymous        boolean not null default false,
  author_id        uuid not null references public.profiles(id) on delete cascade,
  status           public.submission_status not null default 'submitted',
  cluster_id       uuid, -- FK added below after clusters table
  classification_label      public.constitutional_topic,
  classification_confidence numeric(5,4) check (classification_confidence between 0 and 1),
  classification_alternatives jsonb not null default '[]'::jsonb,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ─── Proposal Clusters ───────────────────────────────────────────────────────
-- Duplicate submissions are merged into clusters; originals are never deleted.

create table public.proposal_clusters (
  id               uuid primary key default gen_random_uuid(),
  topic            public.constitutional_topic not null default 'other',
  affected_article_id text references public.constitution_articles(id) on delete set null,
  title            text not null,
  summary          text,
  supporting_count integer not null default 0,
  opposing_count   integer not null default 0,
  neutral_count    integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table public.citizen_submissions
  add constraint fk_submission_cluster
  foreign key (cluster_id) references public.proposal_clusters(id) on delete set null;

-- ─── Moderation Events ───────────────────────────────────────────────────────

create table public.moderation_events (
  id              uuid primary key default gen_random_uuid(),
  submission_id   uuid not null references public.citizen_submissions(id) on delete cascade,
  kind            public.moderation_event_kind not null,
  outcome         public.moderation_outcome not null,
  reason          text not null default '',
  moderator_id    uuid references public.profiles(id) on delete set null,
  at              timestamptz not null default now()
);

-- ─── Multi-stage Polls ───────────────────────────────────────────────────────

create table public.workflow_polls (
  id                        uuid primary key default gen_random_uuid(),
  article_id                text, -- proposed article (not FK — may not exist in DB yet)
  cluster_id                uuid references public.proposal_clusters(id) on delete set null,
  stage                     public.poll_stage not null,
  title                     text not null check (char_length(title) between 5 and 300),
  description               text not null default '',
  opens_at                  timestamptz not null default now(),
  closes_at                 timestamptz,
  status                    public.poll_stage_status not null default 'draft',
  minimum_participation     integer not null default 0,
  is_representative         boolean not null default false,
  representativeness_warning text not null default 'Matokeo haya hayawakilishi taifa. Ni mkusanyiko wa maoni ya washiriki waliojisajili.',
  total_votes               integer not null default 0,
  verified_votes            integer not null default 0,
  abstentions               integer not null default 0,
  -- Governance invariant: a poll NEVER auto-approves an article.
  auto_approved             boolean not null default false check (auto_approved = false),
  human_reviewed            boolean not null default false,
  region_distribution       jsonb not null default '{}'::jsonb,
  verification_tier_distribution jsonb not null default '{}'::jsonb,
  created_by                uuid references public.profiles(id) on delete set null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create table public.workflow_poll_options (
  id           uuid primary key default gen_random_uuid(),
  poll_id      uuid not null references public.workflow_polls(id) on delete cascade,
  label        text not null check (char_length(label) between 1 and 300),
  description  text,
  order_index  integer not null default 0,
  votes        integer not null default 0,
  verified_votes integer not null default 0,
  unique(poll_id, order_index)
);

create table public.workflow_votes (
  id             uuid primary key default gen_random_uuid(),
  poll_id        uuid not null references public.workflow_polls(id) on delete cascade,
  option_id      uuid references public.workflow_poll_options(id) on delete set null, -- null = abstain
  voter_id       uuid not null references public.profiles(id) on delete cascade,
  is_verified    boolean not null default false,
  region         text,
  created_at     timestamptz not null default now(),
  unique(poll_id, voter_id)
);

-- ─── Draft Versions ───────────────────────────────────────────────────────────

create table public.draft_versions (
  id              uuid primary key default gen_random_uuid(),
  version_number  integer not null,
  title           text not null,
  status          public.draft_version_status not null default 'draft',
  legally_reviewed boolean not null default false,
  reviewer_notes  text,
  generation_method text not null default 'manual',
  generation_date timestamptz,
  source_submission_ids jsonb not null default '[]'::jsonb,
  ai_generated    boolean not null default false,
  -- Immutability: published drafts cannot be overwritten; restoration creates new version
  published_at    timestamptz,
  archived_at     timestamptz,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique(version_number)
);

create table public.draft_articles (
  id              uuid primary key default gen_random_uuid(),
  version_id      uuid not null references public.draft_versions(id) on delete cascade,
  chapter_id      text,
  article_number  text,
  title_sw        text not null default '',
  title_en        text,
  wording_sw      text not null default '',
  wording_en      text,
  plain_sw        text,
  plain_en        text,
  source_cluster_ids jsonb not null default '[]'::jsonb,
  minority_positions jsonb not null default '[]'::jsonb,
  legal_risks     jsonb not null default '[]'::jsonb,
  ai_generated    boolean not null default false,
  legally_reviewed boolean not null default false,
  order_index     integer not null default 0,
  approval_stage  public.approval_stage not null default 'citizen_input',
  -- Governance: proposed wording never overwrites official text
  proposal_disclaimer text not null default 'Maandishi haya ni pendekezo tu na hayawakilishi katiba rasmi.',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ─── Draft Builder Audit Trail ───────────────────────────────────────────────

create table public.draft_builder_actions (
  id          uuid primary key default gen_random_uuid(),
  version_id  uuid not null references public.draft_versions(id) on delete cascade,
  actor_id    uuid not null references public.profiles(id) on delete cascade,
  kind        public.draft_builder_action_kind not null,
  article_id  uuid references public.draft_articles(id) on delete set null,
  chapter_id  text,
  description text not null default '',
  before_val  text,
  after_val   text,
  at          timestamptz not null default now()
);

-- ─── Approval Workflow ───────────────────────────────────────────────────────

create table public.approval_rules (
  id                         uuid primary key default gen_random_uuid(),
  min_verified_participants  integer not null default 0,
  min_regions                integer not null default 0,
  min_support_pct            numeric(5,2) not null default 0,
  required_poll_stages       jsonb not null default '[]'::jsonb,
  requires_legal_review      boolean not null default true,
  requires_committee_approval boolean not null default true,
  created_at                 timestamptz not null default now()
);

create table public.approval_decisions (
  id              uuid primary key default gen_random_uuid(),
  article_id      uuid not null references public.draft_articles(id) on delete cascade,
  stage           public.approval_stage not null,
  decision        text not null check (decision in ('approved','rejected','sent_back')),
  rationale       text not null check (char_length(rationale) >= 5),
  actor_id        uuid not null references public.profiles(id) on delete cascade,
  at              timestamptz not null default now()
);

-- ─── Public Audit Events ─────────────────────────────────────────────────────
-- Every significant action is logged here; personal/moderation data is excluded.

create table public.audit_events (
  id          uuid primary key default gen_random_uuid(),
  kind        public.audit_event_kind not null,
  subject_id  text,             -- submission_id / cluster_id / version_id etc. as text
  actor_id    uuid references public.profiles(id) on delete set null,
  payload     jsonb not null default '{}'::jsonb,
  at          timestamptz not null default now()
);

-- ─── Full-text search on constitution articles ────────────────────────────────

alter table public.constitution_articles
  add column if not exists search_sw tsvector
    generated always as (to_tsvector('simple', coalesce(title_sw,'') || ' ' || coalesce(body_sw,''))) stored,
  add column if not exists search_en tsvector
    generated always as (to_tsvector('english', coalesce(title_en,'') || ' ' || coalesce(body_en,''))) stored;

create index articles_search_sw_idx on public.constitution_articles using gin(search_sw);
create index articles_search_en_idx on public.constitution_articles using gin(search_en);

-- ─── Indexes ─────────────────────────────────────────────────────────────────

create index submissions_author_idx   on public.citizen_submissions(author_id);
create index submissions_status_idx   on public.citizen_submissions(status);
create index submissions_cluster_idx  on public.citizen_submissions(cluster_id) where cluster_id is not null;
create index submissions_topic_idx    on public.citizen_submissions(topic);
create index moderation_submission_idx on public.moderation_events(submission_id, at desc);
create index workflow_polls_stage_idx  on public.workflow_polls(stage, status);
create index workflow_polls_cluster_idx on public.workflow_polls(cluster_id) where cluster_id is not null;
create index workflow_votes_poll_idx   on public.workflow_votes(poll_id);
create index workflow_votes_voter_idx  on public.workflow_votes(voter_id);
create index draft_articles_version_idx on public.draft_articles(version_id, order_index);
create index draft_actions_version_idx  on public.draft_builder_actions(version_id, at desc);
create index audit_events_kind_idx     on public.audit_events(kind, at desc);
create index audit_events_subject_idx  on public.audit_events(subject_id);

-- ─── RLS ─────────────────────────────────────────────────────────────────────

alter table public.citizen_submissions      enable row level security;
alter table public.proposal_clusters        enable row level security;
alter table public.moderation_events        enable row level security;
alter table public.workflow_polls           enable row level security;
alter table public.workflow_poll_options    enable row level security;
alter table public.workflow_votes           enable row level security;
alter table public.draft_versions           enable row level security;
alter table public.draft_articles           enable row level security;
alter table public.draft_builder_actions    enable row level security;
alter table public.approval_rules           enable row level security;
alter table public.approval_decisions       enable row level security;
alter table public.audit_events             enable row level security;

-- Submissions: authors see their own; everyone sees non-sensitive clustered/accepted
create policy "Authors see own submissions" on public.citizen_submissions
  for select to authenticated using ((select auth.uid()) = author_id);
create policy "Public sees non-sensitive submissions" on public.citizen_submissions
  for select to anon, authenticated using (
    status in ('clustered','topic_classified') and not anonymous
  );
create policy "Authenticated users submit" on public.citizen_submissions
  for insert to authenticated with check ((select auth.uid()) = author_id);
create policy "Authors withdraw submissions" on public.citizen_submissions
  for update to authenticated
  using ((select auth.uid()) = author_id and status = 'submitted')
  with check ((select auth.uid()) = author_id);

-- Moderator / admin write access via helper
create policy "Moderators manage submissions" on public.citizen_submissions
  for all to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

-- Clusters: public read
create policy "Clusters are public" on public.proposal_clusters
  for select to anon, authenticated using (true);
create policy "Moderators manage clusters" on public.proposal_clusters
  for all to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

-- Moderation events: only moderators/admins
create policy "Moderators see moderation events" on public.moderation_events
  for select to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));
create policy "Moderators create moderation events" on public.moderation_events
  for insert to authenticated
  with check (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

-- Workflow polls: open/closed polls are public
create policy "Open polls are public" on public.workflow_polls
  for select to anon, authenticated using (status in ('open','closed'));
create policy "Moderators manage workflow polls" on public.workflow_polls
  for all to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

create policy "Options for visible polls" on public.workflow_poll_options
  for select to anon, authenticated
  using (exists (select 1 from public.workflow_polls p where p.id = poll_id and p.status in ('open','closed')));
create policy "Moderators manage poll options" on public.workflow_poll_options
  for all to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

-- Workflow votes
create policy "Users read own workflow votes" on public.workflow_votes
  for select to authenticated using ((select auth.uid()) = voter_id);
create policy "Users cast workflow vote" on public.workflow_votes
  for insert to authenticated
  with check (
    (select auth.uid()) = voter_id
    and exists (
      select 1 from public.workflow_polls p
      where p.id = poll_id and p.status = 'open'
        and p.opens_at <= now()
        and (p.closes_at is null or p.closes_at > now())
    )
  );

-- Draft versions: published versions are public; drafts visible to committee/admin
create policy "Published draft versions are public" on public.draft_versions
  for select to anon, authenticated using (status = 'published');
create policy "Committee sees all draft versions" on public.draft_versions
  for select to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));
create policy "Committee manages draft versions" on public.draft_versions
  for all to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

create policy "Published draft articles are public" on public.draft_articles
  for select to anon, authenticated
  using (exists (select 1 from public.draft_versions v where v.id = version_id and v.status = 'published'));
create policy "Committee manages draft articles" on public.draft_articles
  for all to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

create policy "Committee sees draft builder actions" on public.draft_builder_actions
  for select to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));
create policy "Committee creates draft builder actions" on public.draft_builder_actions
  for insert to authenticated
  with check (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

create policy "Approval rules are public" on public.approval_rules for select to anon, authenticated using (true);
create policy "Admin manages approval rules" on public.approval_rules
  for all to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin'));

create policy "Approval decisions are public" on public.approval_decisions for select to anon, authenticated using (true);
create policy "Committee creates approval decisions" on public.approval_decisions
  for insert to authenticated
  with check (exists (select 1 from public.profiles where id = (select auth.uid()) and role in ('moderator','admin')));

-- Audit events: fully public (no personal/moderation detail stored here)
create policy "Audit events are public" on public.audit_events for select to anon, authenticated using (true);
create policy "System inserts audit events" on public.audit_events
  for insert to authenticated with check (true);

-- ─── Grants ───────────────────────────────────────────────────────────────────

grant usage on schema public to anon, authenticated;

grant select on
  public.proposal_clusters, public.workflow_polls, public.workflow_poll_options,
  public.draft_versions, public.draft_articles, public.approval_rules,
  public.approval_decisions, public.audit_events
to anon, authenticated;

grant insert on public.citizen_submissions, public.workflow_votes, public.audit_events to authenticated;
grant update(status, cluster_id) on public.citizen_submissions to authenticated;
grant select, insert on public.workflow_votes to authenticated;
grant select on public.citizen_submissions, public.moderation_events to authenticated;

-- ─── updated_at trigger function ─────────────────────────────────────────────

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger set_updated_at_citizen_submissions
  before update on public.citizen_submissions
  for each row execute function public.set_updated_at();

create trigger set_updated_at_proposal_clusters
  before update on public.proposal_clusters
  for each row execute function public.set_updated_at();

create trigger set_updated_at_workflow_polls
  before update on public.workflow_polls
  for each row execute function public.set_updated_at();

create trigger set_updated_at_draft_versions
  before update on public.draft_versions
  for each row execute function public.set_updated_at();

create trigger set_updated_at_draft_articles
  before update on public.draft_articles
  for each row execute function public.set_updated_at();

-- ─── FUNCTION: log_audit_event ────────────────────────────────────────────────
-- Safe wrapper used by the app to write public audit entries.

create or replace function public.log_audit_event(
  p_kind    public.audit_event_kind,
  p_subject text default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  insert into public.audit_events(kind, subject_id, actor_id, payload)
  values (p_kind, p_subject, auth.uid(), p_payload)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.log_audit_event from public, anon;
grant execute on function public.log_audit_event to authenticated;

-- ─── FUNCTION: cast_workflow_vote ─────────────────────────────────────────────
-- Atomically records a vote and updates option/poll tallies.

create or replace function public.cast_workflow_vote(
  p_poll_id   uuid,
  p_option_id uuid default null  -- null = abstain
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_voter    uuid := auth.uid();
  v_poll     record;
  v_verified boolean;
  v_region   text;
begin
  -- Validate poll is open
  select * into v_poll from public.workflow_polls
  where id = p_poll_id and status = 'open'
    and opens_at <= now()
    and (closes_at is null or closes_at > now());
  if not found then
    raise exception 'Poll is not open' using errcode = 'P0002';
  end if;

  -- Get voter verification tier for tally
  select (verification_tier in ('phone','nida')), region
    into v_verified, v_region
  from public.profiles where id = v_voter;

  -- Insert vote (unique constraint prevents double voting)
  insert into public.workflow_votes(poll_id, option_id, voter_id, is_verified, region)
  values (p_poll_id, p_option_id, v_voter, coalesce(v_verified, false), v_region);

  -- Update option tallies
  if p_option_id is not null then
    update public.workflow_poll_options
    set votes = votes + 1,
        verified_votes = verified_votes + (case when v_verified then 1 else 0 end)
    where id = p_option_id and poll_id = p_poll_id;
  end if;

  -- Update poll-level tallies
  update public.workflow_polls
  set total_votes   = total_votes + 1,
      verified_votes = verified_votes + (case when v_verified then 1 else 0 end),
      abstentions   = abstentions + (case when p_option_id is null then 1 else 0 end)
  where id = p_poll_id;

  -- Audit
  perform public.log_audit_event(
    'vote_cast',
    p_poll_id::text,
    jsonb_build_object('poll_id', p_poll_id, 'abstain', p_option_id is null)
  );

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.cast_workflow_vote from public, anon;
grant execute on function public.cast_workflow_vote to authenticated;

-- ─── FUNCTION: submit_citizen_proposal ────────────────────────────────────────
-- Validates and inserts a citizen submission, creates the first audit event.

create or replace function public.submit_citizen_proposal(
  p_title               text,
  p_topic               public.constitutional_topic,
  p_problem             text,
  p_rationale           text,
  p_proposed_wording_sw text default null,
  p_proposed_wording_en text default null,
  p_supporting_evidence text default null,
  p_affected_article_id text default null,
  p_region              text default null,
  p_anonymous           boolean default false
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  insert into public.citizen_submissions(
    title, topic, affected_article_id, problem, proposed_wording_sw, proposed_wording_en,
    rationale, supporting_evidence, region, anonymous, author_id
  ) values (
    p_title, p_topic, p_affected_article_id, p_problem, p_proposed_wording_sw,
    p_proposed_wording_en, p_rationale, p_supporting_evidence, p_region,
    p_anonymous, auth.uid()
  ) returning id into v_id;

  perform public.log_audit_event(
    'submission_created',
    v_id::text,
    jsonb_build_object('topic', p_topic, 'anonymous', p_anonymous)
  );

  return v_id;
end;
$$;
revoke all on function public.submit_citizen_proposal from public, anon;
grant execute on function public.submit_citizen_proposal to authenticated;

-- ─── FUNCTION: update_submission_status ───────────────────────────────────────
-- Moderators/admins only. Updates status and creates moderation event + audit.

create or replace function public.update_submission_status(
  p_submission_id uuid,
  p_status        public.submission_status,
  p_event_kind    public.moderation_event_kind,
  p_outcome       public.moderation_outcome,
  p_reason        text default ''
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('moderator','admin')
  ) then
    raise exception 'Insufficient role' using errcode = 'P0001';
  end if;

  update public.citizen_submissions
  set status = p_status
  where id = p_submission_id;

  insert into public.moderation_events(submission_id, kind, outcome, reason, moderator_id)
  values (p_submission_id, p_event_kind, p_outcome, p_reason, auth.uid());

  perform public.log_audit_event(
    'submission_status_changed',
    p_submission_id::text,
    jsonb_build_object('status', p_status, 'outcome', p_outcome)
  );
end;
$$;
revoke all on function public.update_submission_status from public, anon;
grant execute on function public.update_submission_status to authenticated;

-- ─── FUNCTION: merge_into_cluster ─────────────────────────────────────────────
-- Merges a submission into a cluster without deleting the original.

create or replace function public.merge_into_cluster(
  p_submission_id uuid,
  p_cluster_id    uuid,
  p_reason        text default 'Duplicate detected'
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('moderator','admin')
  ) then
    raise exception 'Insufficient role' using errcode = 'P0001';
  end if;

  update public.citizen_submissions
  set cluster_id = p_cluster_id, status = 'merged'
  where id = p_submission_id;

  insert into public.moderation_events(submission_id, kind, outcome, reason, moderator_id)
  values (p_submission_id, 'clustering', 'merged', p_reason, auth.uid());

  perform public.log_audit_event(
    'cluster_merged',
    p_cluster_id::text,
    jsonb_build_object('submission_id', p_submission_id)
  );
end;
$$;
revoke all on function public.merge_into_cluster from public, anon;
grant execute on function public.merge_into_cluster to authenticated;

-- ─── FUNCTION: publish_draft_version ──────────────────────────────────────────
-- Marks a draft version as published (immutable). Admins/committee only.

create or replace function public.publish_draft_version(p_version_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('moderator','admin')
  ) then
    raise exception 'Insufficient role' using errcode = 'P0001';
  end if;

  update public.draft_versions
  set status = 'published', published_at = now()
  where id = p_version_id and status = 'draft';

  if not found then
    raise exception 'Version not found or already published' using errcode = 'P0002';
  end if;

  perform public.log_audit_event(
    'draft_version_published',
    p_version_id::text,
    jsonb_build_object('published_by', auth.uid())
  );
end;
$$;
revoke all on function public.publish_draft_version from public, anon;
grant execute on function public.publish_draft_version to authenticated;

-- ─── FUNCTION: restore_draft_version ──────────────────────────────────────────
-- Creates a new draft based on a prior version — never overwrites published drafts.

create or replace function public.restore_draft_version(
  p_source_version_id uuid,
  p_new_title         text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_new_id      uuid;
  v_next_number integer;
  v_source      record;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('moderator','admin')
  ) then
    raise exception 'Insufficient role' using errcode = 'P0001';
  end if;

  select * into v_source from public.draft_versions where id = p_source_version_id;
  if not found then
    raise exception 'Source version not found' using errcode = 'P0002';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_number from public.draft_versions;

  insert into public.draft_versions(version_number, title, generation_method, ai_generated, created_by)
  values (v_next_number, p_new_title, 'restored_from_v' || v_source.version_number, false, auth.uid())
  returning id into v_new_id;

  -- Copy articles from source version into new draft
  insert into public.draft_articles(
    version_id, chapter_id, article_number, title_sw, title_en, wording_sw, wording_en,
    plain_sw, plain_en, source_cluster_ids, minority_positions, legal_risks,
    ai_generated, order_index, approval_stage
  )
  select v_new_id, chapter_id, article_number, title_sw, title_en, wording_sw, wording_en,
         plain_sw, plain_en, source_cluster_ids, minority_positions, legal_risks,
         ai_generated, order_index, 'citizen_input'
  from public.draft_articles where version_id = p_source_version_id;

  perform public.log_audit_event(
    'draft_version_restored',
    v_new_id::text,
    jsonb_build_object('source_version_id', p_source_version_id, 'new_version', v_next_number)
  );

  return v_new_id;
end;
$$;
revoke all on function public.restore_draft_version from public, anon;
grant execute on function public.restore_draft_version to authenticated;

-- ─── FUNCTION: search_articles ────────────────────────────────────────────────
-- Full-text search across published articles. Supports Swahili and English.

create or replace function public.search_articles(
  p_query    text,
  p_lang     text default 'sw',   -- 'sw' or 'en'
  p_doc_id   text default null,   -- optional filter by document
  p_limit    integer default 20,
  p_offset   integer default 0
)
returns table (
  id            text,
  document_id   text,
  article_number text,
  title_sw      text,
  title_en      text,
  body_sw       text,
  body_en       text,
  is_muungano   boolean,
  rank          real
) language plpgsql stable security definer set search_path = public as $$
declare
  v_tsq tsquery;
begin
  v_tsq := plainto_tsquery(case when p_lang = 'en' then 'english'::regconfig else 'simple'::regconfig end, p_query);

  return query
  select
    a.id, a.document_id, a.article_number, a.title_sw, a.title_en, a.body_sw, a.body_en,
    a.is_muungano,
    ts_rank(case when p_lang = 'en' then a.search_en else a.search_sw end, v_tsq) as rank
  from public.constitution_articles a
  where a.is_published
    and (p_doc_id is null or a.document_id = p_doc_id)
    and (
      case when p_lang = 'en' then a.search_en @@ v_tsq
           else a.search_sw @@ v_tsq end
    )
  order by rank desc
  limit p_limit offset p_offset;
end;
$$;
grant execute on function public.search_articles to anon, authenticated;

-- ─── FUNCTION: get_poll_results ───────────────────────────────────────────────
-- Returns a poll with per-option percentages. Visible after poll closes.

create or replace function public.get_poll_results(p_poll_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_poll   record;
  v_opts   jsonb;
begin
  select * into v_poll from public.workflow_polls where id = p_poll_id;
  if not found then raise exception 'Poll not found' using errcode = 'P0002'; end if;

  select jsonb_agg(
    jsonb_build_object(
      'id',             o.id,
      'label',          o.label,
      'order_index',    o.order_index,
      'votes',          o.votes,
      'verified_votes', o.verified_votes,
      'percentage',     case when v_poll.total_votes > 0
                             then round((o.votes::numeric / v_poll.total_votes) * 100, 2)
                             else 0 end
    ) order by o.order_index
  ) into v_opts from public.workflow_poll_options o where o.poll_id = p_poll_id;

  return jsonb_build_object(
    'id',                     v_poll.id,
    'stage',                  v_poll.stage,
    'title',                  v_poll.title,
    'status',                 v_poll.status,
    'total_votes',            v_poll.total_votes,
    'verified_votes',         v_poll.verified_votes,
    'abstentions',            v_poll.abstentions,
    'auto_approved',          false,
    'human_reviewed',         v_poll.human_reviewed,
    'representativeness_warning', v_poll.representativeness_warning,
    'region_distribution',    v_poll.region_distribution,
    'options',                coalesce(v_opts, '[]'::jsonb)
  );
end;
$$;
grant execute on function public.get_poll_results to anon, authenticated;

-- ─── FUNCTION: record_committee_decision ──────────────────────────────────────

create or replace function public.record_committee_decision(
  p_article_id uuid,
  p_stage      public.approval_stage,
  p_decision   text,
  p_rationale  text
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('moderator','admin')
  ) then
    raise exception 'Insufficient role' using errcode = 'P0001';
  end if;

  insert into public.approval_decisions(article_id, stage, decision, rationale, actor_id)
  values (p_article_id, p_stage, p_decision, p_rationale, auth.uid())
  returning id into v_id;

  if p_decision = 'approved' then
    update public.draft_articles
    set approval_stage = p_stage
    where id = p_article_id;
  end if;

  perform public.log_audit_event(
    'committee_decision',
    p_article_id::text,
    jsonb_build_object('stage', p_stage, 'decision', p_decision)
  );

  return v_id;
end;
$$;
revoke all on function public.record_committee_decision from public, anon;
grant execute on function public.record_committee_decision to authenticated;

-- ─── FUNCTION: get_article_participation_summary ──────────────────────────────
-- Returns participation stats for a draft article's linked polls.

create or replace function public.get_article_participation_summary(p_article_id text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'article_id',         p_article_id,
    'total_submissions',  count(s.id),
    'cluster_count',      count(distinct s.cluster_id),
    'topic_distribution', jsonb_object_agg(s.topic, count(*)) filter (where s.topic is not null)
  ) into v_result
  from public.citizen_submissions s
  where s.affected_article_id = p_article_id
    and s.status not in ('validation_failed','withdrawn');

  return coalesce(v_result, '{}'::jsonb);
end;
$$;
grant execute on function public.get_article_participation_summary to anon, authenticated;

