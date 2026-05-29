create table if not exists public.social_creators (
  uuid uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  platform text not null check (platform in ('youtube', 'substack', 'instagram', 'tiktok', 'linkedin', 'x')),
  platform_creator_id text,
  handle text not null,
  display_name text,
  bio text,
  avatar_url text,
  profile_url text,
  follower_count bigint,
  following_count bigint,
  post_count bigint,
  language text,
  niche_tags text[] not null default '{}',
  source_tags text[] not null default '{}',
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, platform, handle)
);

create table if not exists public.social_sources (
  uuid uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  kind text not null check (kind in ('tracked_creator', 'curated_creator', 'publication_feed', 'youtube_channel', 'keyword', 'hashtag', 'list', 'adjacent_creator')),
  platform text check (platform is null or platform in ('youtube', 'substack', 'instagram', 'tiktok', 'linkedin', 'x')),
  label text not null,
  query text,
  profile_url text,
  creator_uuid uuid references public.social_creators(uuid) on delete set null,
  niche_tags text[] not null default '{}',
  priority int not null default 50,
  cadence_minutes int not null default 1440,
  status text not null default 'active' check (status in ('active', 'paused', 'error', 'rate_limited')),
  last_run_at timestamptz,
  next_run_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_discovered_posts (
  uuid uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  platform text not null check (platform in ('youtube', 'substack', 'instagram', 'tiktok', 'linkedin', 'x')),
  platform_post_id text not null,
  creator_uuid uuid references public.social_creators(uuid) on delete set null,
  source_uuid uuid references public.social_sources(uuid) on delete set null,
  canonical_url text not null,
  title text,
  caption text,
  transcript text,
  language text,
  posted_at timestamptz,
  media_type text not null default 'unknown' check (media_type in ('video', 'short_video', 'image', 'carousel', 'text', 'article', 'unknown')),
  media_urls jsonb not null default '[]'::jsonb,
  thumbnail_url text,
  duration_seconds int,
  view_count bigint,
  like_count bigint,
  comment_count bigint,
  repost_count bigint,
  share_count bigint,
  engagement_rate numeric,
  outlier_score numeric,
  outlier_grade text not null default 'insufficient_data' check (outlier_grade in ('S', 'A', 'B', 'C', 'insufficient_data')),
  velocity_score numeric,
  ranking_score numeric,
  niche_tags text[] not null default '{}',
  format_tags text[] not null default '{}',
  hook_tags text[] not null default '{}',
  raw_payload jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_refreshed_at timestamptz,
  saved_atom_uuid text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, platform, platform_post_id)
);

create table if not exists public.social_metric_snapshots (
  uuid uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  post_uuid uuid references public.social_discovered_posts(uuid) on delete cascade,
  captured_at timestamptz not null default now(),
  view_count bigint,
  like_count bigint,
  comment_count bigint,
  repost_count bigint,
  share_count bigint
);

create table if not exists public.social_source_edges (
  uuid uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  from_source_uuid uuid references public.social_sources(uuid) on delete cascade,
  from_creator_uuid uuid references public.social_creators(uuid) on delete cascade,
  to_creator_uuid uuid references public.social_creators(uuid) on delete cascade,
  to_source_uuid uuid references public.social_sources(uuid) on delete cascade,
  edge_type text not null,
  confidence numeric not null default 0.5,
  created_at timestamptz not null default now()
);

create table if not exists public.social_discovery_runs (
  uuid uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  source_uuid uuid references public.social_sources(uuid) on delete set null,
  provider text not null,
  status text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  posts_found int not null default 0,
  posts_upserted int not null default 0,
  error_message text,
  rate_limited_until timestamptz
);

create index if not exists social_creators_user_platform_idx on public.social_creators(user_id, platform);
create index if not exists social_sources_due_idx on public.social_sources(user_id, status, next_run_at, priority desc);
create index if not exists social_posts_feed_idx on public.social_discovered_posts(user_id, ranking_score desc nulls last, posted_at desc nulls last);
create index if not exists social_posts_platform_idx on public.social_discovered_posts(user_id, platform, posted_at desc nulls last);
create index if not exists social_posts_outlier_idx on public.social_discovered_posts(user_id, outlier_score desc nulls last);
create index if not exists social_posts_creator_idx on public.social_discovered_posts(user_id, creator_uuid, posted_at desc nulls last);
create index if not exists social_metric_snapshots_post_idx on public.social_metric_snapshots(user_id, post_uuid, captured_at desc);
create index if not exists social_runs_source_idx on public.social_discovery_runs(user_id, source_uuid, started_at desc);

alter table public.social_creators enable row level security;
alter table public.social_sources enable row level security;
alter table public.social_discovered_posts enable row level security;
alter table public.social_metric_snapshots enable row level security;
alter table public.social_source_edges enable row level security;
alter table public.social_discovery_runs enable row level security;

create policy "Users can read own social creators" on public.social_creators for select using (auth.uid() = user_id);
create policy "Users can read own social sources" on public.social_sources for select using (auth.uid() = user_id);
create policy "Users can read own social posts" on public.social_discovered_posts for select using (auth.uid() = user_id);
create policy "Users can read own social metric snapshots" on public.social_metric_snapshots for select using (auth.uid() = user_id);
create policy "Users can read own social source edges" on public.social_source_edges for select using (auth.uid() = user_id);
create policy "Users can read own social discovery runs" on public.social_discovery_runs for select using (auth.uid() = user_id);
