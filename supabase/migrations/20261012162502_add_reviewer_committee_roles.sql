-- ==========================================================
-- Migration: Add reviewer and committee roles
-- ==========================================================
-- Extends the role constraint on public.profiles to support
-- a workflow with distinct roles:
--   citizen    -> public user (can submit reports)
--   admin      -> system administrator (manages users, sees all)
--   reviewer   -> commission staff (reviews assigned submissions)
--   committee  -> commission members (vote on submissions)

-- Drop the existing 2-role constraint
alter table public.profiles
  drop constraint if exists profiles_role_check;

-- Add the new 4-role constraint
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('citizen', 'admin', 'reviewer', 'committee'));

-- Index for fast role lookups (used by RLS policies)
create index if not exists profiles_role_idx on public.profiles(role);

comment on column public.profiles.role is 'User role: citizen, admin, reviewer, or committee';