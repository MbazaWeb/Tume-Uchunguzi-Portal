-- Moderator-controlled proposal clustering. Originals remain immutable.
create or replace function public.create_proposal_cluster(p_title text,p_topic public.constitutional_topic,p_article_id text,p_summary text)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 insert into public.proposal_clusters(title,topic,affected_article_id,summary) values(trim(p_title),p_topic,nullif(trim(p_article_id),''),nullif(trim(p_summary),'')) returning id into v_id;
 return v_id;
end; $$;

create or replace function public.assign_submission_cluster(p_submission_id uuid,p_cluster_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare old_cluster uuid; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 select cluster_id into old_cluster from public.citizen_submissions where id=p_submission_id for update;
 if not found then raise exception 'Submission not found'; end if;
 if not exists(select 1 from public.proposal_clusters where id=p_cluster_id) then raise exception 'Cluster not found'; end if;
 update public.citizen_submissions set cluster_id=p_cluster_id,status='clustered',updated_at=now() where id=p_submission_id;
 insert into public.moderation_events(submission_id,kind,outcome,reason,moderator_id) values(p_submission_id,'clustering',case when old_cluster is null then 'merged' else 'manual_override' end,'Assigned to proposal cluster '||p_cluster_id::text,auth.uid());
 update public.proposal_clusters c set supporting_count=(select count(*) from public.citizen_submissions s where s.cluster_id=c.id),updated_at=now() where c.id in (p_cluster_id,old_cluster);
end; $$;

create or replace function public.remove_submission_cluster(p_submission_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare old_cluster uuid; begin
 if auth.uid() is null or not public.is_moderator_or_admin() then raise exception 'Moderator or admin required'; end if;
 select cluster_id into old_cluster from public.citizen_submissions where id=p_submission_id for update;
 if old_cluster is null then raise exception 'Submission is not clustered'; end if;
 update public.citizen_submissions set cluster_id=null,status='in_moderation',updated_at=now() where id=p_submission_id;
 insert into public.moderation_events(submission_id,kind,outcome,reason,moderator_id) values(p_submission_id,'clustering','manual_override','Removed from proposal cluster '||old_cluster::text,auth.uid());
 update public.proposal_clusters c set supporting_count=(select count(*) from public.citizen_submissions s where s.cluster_id=c.id),updated_at=now() where c.id=old_cluster;
end; $$;

revoke all on function public.create_proposal_cluster(text,public.constitutional_topic,text,text) from public,anon;
revoke all on function public.assign_submission_cluster(uuid,uuid) from public,anon;
revoke all on function public.remove_submission_cluster(uuid) from public,anon;
grant execute on function public.create_proposal_cluster(text,public.constitutional_topic,text,text) to authenticated;
grant execute on function public.assign_submission_cluster(uuid,uuid) to authenticated;
grant execute on function public.remove_submission_cluster(uuid) to authenticated;
