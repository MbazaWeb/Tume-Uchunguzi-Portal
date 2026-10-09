-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: add district column to profiles and citizen_submissions
--
-- Companion to src/constants/regions.ts which defines 31 Tanzania regions
-- and 180 districts. The district column stores the lowercase kebab-case
-- district id (e.g. 'ilala', 'rungwe', 'nyamagana') — see RegionEntry in
-- src/constants/regions.ts for the authoritative list.
--
-- A district is always scoped to a region. The application enforces that
-- district belongs to region client-side via getDistricts(region). The DB
-- does NOT enforce a foreign key to a districts table (the list may evolve
-- with TAMISEMI gazettes), so the application is the source of truth for
-- validity. NULL or unknown district values are tolerated.
--
-- Verification status of the districts list is `pending` (see
-- REGIONS_DISCLAIMER in src/constants/regions.ts).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add district to profiles.
alter table public.profiles
  add column if not exists district text;

comment on column public.profiles.district is
  'Lowercase kebab-case district id from src/constants/regions.ts (e.g. ilala, rungwe). Scoped to region. NULL when the user did not select a district.';

-- 2. Add district to citizen_submissions.
alter table public.citizen_submissions
  add column if not exists district text;

comment on column public.citizen_submissions.district is
  'Lowercase kebab-case district id from src/constants/regions.ts. Scoped to region. NULL when the submitter did not select a district.';

-- 3. Allow citizens to update their own district.
-- The existing grant allows update(display_name, anonymity_default, region,
-- language_pref, avatar_url). Add district to that list.
grant update(district) on public.profiles to authenticated;

-- 4. Update the submit_citizen_proposal function to accept p_district.
-- Must DROP the old version first because the parameter list changed.
-- PostgreSQL treats functions with different parameter lists as distinct
-- signatures; "create or replace" cannot change a function's signature.
drop function if exists public.submit_citizen_proposal(
  text, public.constitutional_topic, text, text, text, text, text, text, text, boolean
);
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
  p_district            text default null,
  p_anonymous           boolean default false
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  insert into public.citizen_submissions(
    title, topic, affected_article_id, problem, proposed_wording_sw, proposed_wording_en,
    rationale, supporting_evidence, region, district, anonymous, author_id
  ) values (
    p_title, p_topic, p_affected_article_id, p_problem, p_proposed_wording_sw,
    p_proposed_wording_en, p_rationale, p_supporting_evidence, p_region, p_district,
    p_anonymous, auth.uid()
  ) returning id into v_id;

  perform public.log_audit_event(
    'submission_created',
    v_id::text,
    jsonb_build_object(
      'topic', p_topic,
      'region', p_region,
      'district', p_district,
      'anonymous', p_anonymous
    )
  );

  return v_id;
end;
$$;
revoke all on function public.submit_citizen_proposal from public, anon;
grant execute on function public.submit_citizen_proposal to authenticated;
