alter table public.inquiry_submissions
	alter column reference_code set default (
		'COI-' || to_char(now(), 'YYYY') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))
	),
	add column title text not null default 'Untitled' check (char_length(title) between 5 and 200),
	add column submission_type text not null default 'other' check (submission_type in ('eyewitness', 'photo', 'video', 'document', 'audio', 'other')),
	add column reporter_role text not null default 'witness' check (reporter_role in ('victim', 'witness', 'third_party', 'anonymous')),
	add column submission_mode text not null default 'identified' check (submission_mode in ('identified', 'confidential', 'anonymous')),
	add column incident_time text not null default 'unknown' check (incident_time in ('morning', 'afternoon', 'evening', 'night', 'unknown')),
	add column ward text not null default '' check (char_length(ward) <= 160),
	add column violation_types text[] not null default '{}',
	add column people_involved text not null default '' check (char_length(people_involved) <= 3000),
	add column authorities_present text not null default 'unsure' check (authorities_present in ('police', 'military', 'unknown', 'no', 'unsure')),
	add column reported_elsewhere boolean not null default false,
	add column reporting_place text not null default '' check (char_length(reporting_place) <= 500),
	add column evidence_category text not null default 'none' check (evidence_category in ('none', 'image', 'video', 'audio', 'document', 'other', 'mixed')),
	add column contact_method text not null default 'none' check (contact_method in ('phone', 'sms', 'email', 'none')),
	add column contact_consent boolean not null default false,
	add column truth_declared boolean not null default false,
	add column details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
	add constraint inquiry_description_min_length check (char_length(description) >= 100);

create table public.inquiry_drafts (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null unique references auth.users(id) on delete cascade,
	current_step smallint not null default 1 check (current_step between 1 and 6),
	form_data jsonb not null default '{}'::jsonb check (jsonb_typeof(form_data) = 'object'),
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create index inquiry_drafts_user_id_idx on public.inquiry_drafts(user_id);
alter table public.inquiry_drafts enable row level security;
revoke all on public.inquiry_drafts from anon, authenticated;
grant select, insert, update, delete on public.inquiry_drafts to authenticated;

create policy "Users manage their own inquiry draft"
	on public.inquiry_drafts for all to authenticated
	using ((select auth.uid()) = user_id)
	with check ((select auth.uid()) = user_id);

update storage.buckets
set allowed_mime_types = array[
	'application/pdf',
	'application/msword',
	'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
	'image/jpeg',
	'image/png',
	'image/webp',
	'video/mp4',
	'video/webm',
	'video/quicktime',
	'audio/mpeg',
	'audio/wav',
	'audio/mp4',
	'audio/ogg'
]
where id = 'inquiry-evidence';
