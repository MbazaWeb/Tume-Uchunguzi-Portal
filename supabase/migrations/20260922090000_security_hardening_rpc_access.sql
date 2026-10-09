-- Security hardening after restoring the legacy Katiba Yetu schema.
-- Public read RPCs run as caller so table RLS remains effective.
alter function public.get_article_participation_summary(text) security invoker;
alter function public.get_poll_results(uuid) security invoker;
alter function public.search_articles(text,text,text,integer,integer) security invoker;

-- Lock trigger helper search_path.
alter function public.set_updated_at() set search_path = public, pg_temp;

-- Prevent Postgres PUBLIC from inheriting EXECUTE on privileged RPCs.
revoke execute on all functions in schema public from public;
alter default privileges in schema public revoke execute on functions from public;

-- Explicit client API surface.
grant execute on function public.get_article_participation_summary(text) to anon, authenticated;
grant execute on function public.get_poll_results(uuid) to anon, authenticated;
grant execute on function public.search_articles(text,text,text,integer,integer) to anon, authenticated;

grant execute on function public.abstain_workflow_vote(uuid) to authenticated;
grant execute on function public.cast_workflow_vote(uuid,uuid) to authenticated;
grant execute on function public.close_workflow_poll(uuid) to authenticated;
grant execute on function public.has_voted(uuid) to authenticated;
grant execute on function public.log_audit_event(public.audit_event_kind,text,jsonb) to authenticated;
grant execute on function public.merge_into_cluster(uuid,uuid,text) to authenticated;
grant execute on function public.moderate_submission(uuid,text,text) to authenticated;
grant execute on function public.publish_draft_version(uuid) to authenticated;
grant execute on function public.record_committee_decision(uuid,public.approval_stage,text,text) to authenticated;
grant execute on function public.restore_draft_version(uuid,text) to authenticated;
grant execute on function public.submit_citizen_proposal(text,public.constitutional_topic,text,text,text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.update_submission_status(uuid,public.submission_status,public.moderation_event_kind,public.moderation_outcome,text) to authenticated;
