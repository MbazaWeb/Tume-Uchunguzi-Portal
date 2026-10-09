create table if not exists public.verification_requests(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 account_type text not null, organization_name text not null, registration_no text, website text, contact_person text,
 contact_phone text, supporting_document_url text, status text not null default 'submitted' check(status in ('submitted','under_review','more_info_requested','approved','rejected')),
 applicant_note text, admin_note text, reviewed_by uuid references auth.users(id), reviewed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.verification_requests enable row level security;
drop policy if exists "Applicant reads verification requests" on public.verification_requests;
create policy "Applicant reads verification requests" on public.verification_requests for select to authenticated using(user_id=auth.uid() or public.is_moderator_or_admin());
drop policy if exists "Applicant creates verification request" on public.verification_requests;
create policy "Applicant creates verification request" on public.verification_requests for insert to authenticated with check(user_id=auth.uid() and account_type<>'individual');
revoke update,delete on public.verification_requests from anon,authenticated;
grant select,insert on public.verification_requests to authenticated;

create or replace function public.review_verification_request(p_request_id uuid,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path=''
as $$ declare r public.verification_requests; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Admin or moderator required'; end if;
 if p_status not in ('under_review','more_info_requested','approved','rejected') then raise exception 'Invalid review status'; end if;
 select * into r from public.verification_requests where id=p_request_id for update;
 if r.id is null then raise exception 'Verification request not found'; end if;
 update public.verification_requests set status=p_status,admin_note=coalesce(p_note,''),reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=p_request_id;
 if p_status='approved' then
   update public.profiles set account_type=r.account_type,organization_name=r.organization_name,organization_registration_no=r.registration_no,organization_website=r.website,organization_verified=true,organization_verification_notes=coalesce(p_note,''),organization_verified_at=now(),organization_verified_by=auth.uid(),updated_at=now() where id=r.user_id;
 elsif p_status='rejected' then
   update public.profiles set organization_verified=false,organization_verification_notes=coalesce(p_note,''),organization_verified_at=null,organization_verified_by=null,updated_at=now() where id=r.user_id;
 end if;
end; $$;
revoke all on function public.review_verification_request(uuid,text,text) from public,anon;
grant execute on function public.review_verification_request(uuid,text,text) to authenticated;