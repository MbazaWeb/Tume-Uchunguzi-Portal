create or replace function public.notify_suggestion_change() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.status is distinct from old.status then insert into public.notifications(user_id,kind,title,body,href)
values(new.user_id,'proposal','Pendekezo lako limesasishwa','Hali mpya: '||replace(new.status::text,'_',' '),case when new.article_id is null then '/proposed' else '/katiba/'||split_part(new.article_id,':',1)||'/'||split_part(new.article_id,':',2) end); end if; return new; end $$;
drop trigger if exists trg_notify_suggestion_change on public.suggestions;
create trigger trg_notify_suggestion_change after update on public.suggestions for each row execute function public.notify_suggestion_change();

create or replace function public.notify_submission_change() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.status is distinct from old.status then insert into public.notifications(user_id,kind,title,body,href)
values(new.author_id,'proposal','Submission yako imepitia hatua mpya','Hali mpya: '||replace(new.status::text,'_',' '),'/proposed'); end if; return new; end $$;
drop trigger if exists trg_notify_submission_change on public.citizen_submissions;
create trigger trg_notify_submission_change after update on public.citizen_submissions for each row execute function public.notify_submission_change();

create or replace function public.notify_poll_status() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.status is distinct from old.status and new.status in ('open','closed') then
 insert into public.notifications(user_id,kind,title,body,href)
 select p.id,'poll',case when new.status='open' then 'Kura mpya imefunguliwa' else 'Kura imefungwa' end,new.title,'/polls'
 from public.profiles p where p.id<>coalesce(new.created_by,'00000000-0000-0000-0000-000000000000'::uuid);
end if; return new; end $$;
drop trigger if exists trg_notify_poll_status on public.workflow_polls;
create trigger trg_notify_poll_status after update on public.workflow_polls for each row execute function public.notify_poll_status();

create or replace function public.notify_draft_decision() returns trigger language plpgsql security definer set search_path='' as $$
declare owner_id uuid; begin select dv.created_by into owner_id from public.draft_articles da join public.draft_versions dv on dv.id=da.version_id where da.id=new.article_id;
if owner_id is not null and owner_id<>new.actor_id then insert into public.notifications(user_id,kind,title,body,href)
values(owner_id,'draft_review',case when new.stage='legal_review' then 'Legal review decision' else 'Committee decision' end,new.decision||case when nullif(new.rationale,'') is not null then ': '||new.rationale else '' end,'/proposed'); end if; return new; end $$;
drop trigger if exists trg_notify_draft_decision on public.approval_decisions;
create trigger trg_notify_draft_decision after insert on public.approval_decisions for each row execute function public.notify_draft_decision();