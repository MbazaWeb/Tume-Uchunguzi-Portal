-- Migration: add stakeholder_type to profiles
do $$ begin
  if not exists (select 1 from pg_type where typname = 'stakeholder_type') then
    create type stakeholder_type as enum (
      'citizen', 'institution', 'court', 'lawyer', 'ngo', 'ministry', 'media', 'other'
    );
  end if;
end $$;

alter table public.profiles
  add column if not exists stakeholder_type stakeholder_type default 'citizen';

comment on column public.profiles.stakeholder_type is
  'Self-selected stakeholder category chosen at registration. Drives personalised navigation and contribution UI.';
