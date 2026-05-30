alter table public.social_sources
  add column if not exists last_successful_run_at timestamptz,
  add column if not exists last_successful_posted_at timestamptz,
  add column if not exists refresh_cursor jsonb not null default '{}'::jsonb;

create index if not exists social_sources_success_cursor_idx
  on public.social_sources(user_id, platform, last_successful_posted_at desc nulls last);

update public.social_sources source
set last_successful_posted_at = latest.latest_posted_at,
    last_successful_run_at = coalesce(source.last_run_at, source.updated_at),
    refresh_cursor = jsonb_build_object('latestPostedAt', latest.latest_posted_at)
from (
  select source_uuid, max(posted_at) as latest_posted_at
  from public.social_discovered_posts
  where source_uuid is not null
  group by source_uuid
) latest
where source.uuid = latest.source_uuid
  and source.last_successful_posted_at is null
  and latest.latest_posted_at is not null;
