-- ==========================================================
-- Rate limiting table for edge function submissions
-- ==========================================================
-- The rate_limits table already exists (created previously).
-- This migration adds the updated_at column and ensures RLS.

-- Add updated_at column if missing
alter table public.rate_limits
  add column if not exists updated_at timestamptz not null default now();

-- Create index for cleanup queries
create index if not exists rate_limits_updated_at_idx
  on public.rate_limits(updated_at);

-- RLS: enable but no policies — only service_role can access.
alter table public.rate_limits enable row level security;
revoke all on public.rate_limits from anon, authenticated;
grant all on public.rate_limits to service_role;

-- Comment
comment on table public.rate_limits is 'Rate limiting for edge functions. Only service_role can access.';