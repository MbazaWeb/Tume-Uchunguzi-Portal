alter table public.library_uploads alter column uploaded_by drop not null;
comment on column public.library_uploads.uploaded_by is 'Admin uploader; null only for system-imported authoritative source documents.';
