-- Prevent the same citizen proposal from being attached twice to the same draft article.
-- A proposal may still legitimately contribute to multiple different draft articles.
create unique index if not exists draft_article_lineage_unique_proposal_source
on public.draft_article_lineage(draft_article_id,source_submission_id)
where source_type='citizen_proposal' and source_submission_id is not null;
