with ranked_sources as (
  select
    uuid,
    row_number() over (
      partition by user_id, platform, creator_uuid, kind
      order by created_at asc, uuid asc
    ) as duplicate_rank
  from public.social_sources
  where creator_uuid is not null
    and status <> 'paused'
)
update public.social_sources source
set status = 'paused',
    last_error = 'Paused automatically: duplicate discovery source for the same creator.',
    updated_at = now()
from ranked_sources ranked
where source.uuid = ranked.uuid
  and ranked.duplicate_rank > 1;

create unique index if not exists social_sources_creator_unique_active_idx
  on public.social_sources(user_id, platform, creator_uuid, kind)
  where creator_uuid is not null and status <> 'paused';
