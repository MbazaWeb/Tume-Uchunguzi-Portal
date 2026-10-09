-- New columns for the citizen submission pipeline:
--   street_village      -> granular location below ward level (free text)
--   short_title_category -> dropdown key the citizen picked (e.g. mwonekano_wa_polisi)
--   people_involved_data -> structured list of {name, role} entries (JSONB)
--   anonymous_flag      -> true when the submission was made without an account
--
-- We also allow user_id to be NULL so that anonymous submissions can be stored
-- (the inquiry-intake edge function will gate this with turnstile verification).
--
-- Finally, we add the inquiry_followups table that powers the two-way conversation
-- between the citizen and the Commission staff on the My Submissions page.

alter table public.inquiry_submissions
        add column if not exists street_village text not null default '' check (char_length(street_village) <= 200),
        add column if not exists short_title_category text not null default '' check (char_length(short_title_category) <= 80),
        add column if not exists people_involved_data jsonb not null default '[]'::jsonb check (jsonb_typeof(people_involved_data) = 'array'),
        add column if not exists anonymous_flag boolean not null default false;

-- Allow user_id to be NULL for anonymous submissions.
alter table public.inquiry_submissions
        alter column user_id drop not null;

-- Add a foreign-key friendly column to profiles when null, fallback: we keep
-- the existing reference but allow null values; administrators will see
-- "(anonymous)" in the inbox view.

create table if not exists public.inquiry_followups (
        id uuid primary key default gen_random_uuid(),
        submission_id uuid not null references public.inquiry_submissions(id) on delete cascade,
        sender_role text not null check (sender_role in ('citizen', 'staff')),
        body text not null default '' check (char_length(body) <= 5000),
        attachment_path text,
        attachment_name text,
        attachment_size bigint,
        created_at timestamptz not null default now()
);

create index if not exists inquiry_followups_submission_idx on public.inquiry_followups(submission_id, created_at);

alter table public.inquiry_followups enable row level security;
revoke all on public.inquiry_followups from anon, authenticated;
grant select, insert on public.inquiry_followups to authenticated;
grant all on public.inquiry_followups to service_role;

-- Citizens can read follow-ups for their own submissions and insert new follow-ups
create policy "Citizens read follow-ups for own submissions"
        on public.inquiry_followups for select to authenticated
        using (
                exists (select 1 from public.inquiry_submissions s
                        where s.id = submission_id
                        and (s.user_id = (select auth.uid()) or s.user_id is null))
        );

create policy "Citizens add follow-ups to own submissions"
        on public.inquiry_followups for insert to authenticated
        with check (
                sender_role = 'citizen'
                and exists (select 1 from public.inquiry_submissions s
                        where s.id = submission_id
                        and s.user_id = (select auth.uid()))
        );

-- Commission admins can read all follow-ups and post staff responses
create policy "Admins manage all follow-ups"
        on public.inquiry_followups for all to authenticated
        using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'))
        with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

-- Storage policy for the new attachment paths under the inquiry-evidence bucket:
-- citizens can write into their own folder and read their own folder; admins
-- can read everything. The existing policies cover this, so we just add an
-- explicit allow-rule for the new follow-up attachments.
drop policy if exists "Citizens upload follow-up evidence" on storage.objects;
create policy "Citizens upload follow-up evidence"
        on storage.objects for insert to authenticated
        with check (
                bucket_id = 'inquiry-evidence'
                and (storage.foldername(name))[1] = (select auth.uid())::text
        );

-- Allow authenticated users to read their own objects in the inquiry-evidence bucket
-- (the original migration only granted this to admins and the user_id prefix).
drop policy if exists "Users read their own inquiry evidence"
        on storage.objects;
create policy "Users read their own inquiry evidence"
        on storage.objects for select to authenticated
        using (
                bucket_id = 'inquiry-evidence'
                and ((storage.foldername(name))[1] = (select auth.uid())::text
                     or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'))
        );

-- Allow users to upload to the inquiry-evidence bucket into their own folder.
-- This is needed so the citizen's follow-up attachment upload from the
-- tracking page can write the file directly to storage without going through
-- the edge function (which is only used for the initial submission).
drop policy if exists "Users upload their own inquiry evidence"
        on storage.objects;
create policy "Users upload their own inquiry evidence"
        on storage.objects for insert to authenticated
        with check (
                bucket_id = 'inquiry-evidence'
                and (storage.foldername(name))[1] = (select auth.uid())::text
        );
