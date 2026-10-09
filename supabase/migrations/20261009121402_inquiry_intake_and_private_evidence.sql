create table public.inquiry_submissions (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null references auth.users(id) on delete cascade,
	reference_code text not null unique default ('TUM-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
	full_name text check (full_name is null or char_length(full_name) <= 160),
	contact text check (contact is null or char_length(contact) <= 160),
	incident_date date not null,
	region text not null check (char_length(region) between 1 and 100),
	district text not null default '' check (char_length(district) <= 100),
	location text not null default '' check (char_length(location) <= 500),
	description text not null check (char_length(description) between 50 and 10000),
	attachments jsonb not null default '[]'::jsonb check (jsonb_typeof(attachments) = 'array'),
	status text not null default 'uploading' check (status in ('uploading', 'submitted', 'reviewing', 'closed')),
	review_note text,
	reviewed_by uuid references public.profiles(id) on delete set null,
	reviewed_at timestamptz,
	created_at timestamptz not null default now()
);

create index inquiry_submissions_created_at_idx on public.inquiry_submissions(created_at desc);
create index inquiry_submissions_status_idx on public.inquiry_submissions(status);

alter table public.inquiry_submissions enable row level security;
revoke all on public.inquiry_submissions from anon, authenticated;
grant all on public.inquiry_submissions to service_role;
grant select on public.inquiry_submissions to authenticated;
grant update (status, review_note, reviewed_by, reviewed_at) on public.inquiry_submissions to authenticated;

create policy "Commission admins read inquiry submissions"
	on public.inquiry_submissions for select to authenticated
	using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

create policy "Users read their own inquiry submissions"
	on public.inquiry_submissions for select to authenticated
	using ((select auth.uid()) = user_id);

create policy "Commission admins update inquiry reviews"
	on public.inquiry_submissions for update to authenticated
	using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'))
	with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
	'inquiry-evidence',
	'inquiry-evidence',
	false,
	52428800,
	array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime']
)
on conflict (id) do update set
	public = false,
	file_size_limit = excluded.file_size_limit,
	allowed_mime_types = excluded.allowed_mime_types;

create policy "Commission admins read inquiry evidence"
	on storage.objects for select to authenticated
	using (
		bucket_id = 'inquiry-evidence'
		and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin')
	);

create policy "Users read their own inquiry evidence"
	on storage.objects for select to authenticated
	using (
		bucket_id = 'inquiry-evidence'
		and (storage.foldername(name))[1] = (select auth.uid())::text
	);
