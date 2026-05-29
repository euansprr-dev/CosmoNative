# Discovery Source Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Swipe File Discover and Creators into a continuously refreshed cross-platform discovery system powered by a server-side source graph, not one-off platform searches.

**Architecture:** The macOS app stays a native SwiftUI reader/control surface. `cosmo-cloud-agent` owns provider credentials, scheduled ingestion, metric snapshots, outlier scoring, ranking, and Supabase writes. Supabase stores a normalized discovery graph that the Mac app reads and filters quickly.

**Tech Stack:** Swift, SwiftUI, Supabase Postgres, TypeScript, Express, node-cron, provider adapters for YouTube, Substack RSS, Bright Data or equivalent managed social data provider, and existing Apify Instagram fallback.

---

## Operating Principle

Discover must be feed-first, not search-first.

Search is useful for steering the system, adding seeds, and filtering the warm cache, but X/Instagram/TikTok/LinkedIn search cannot be the primary discovery engine. The core loop is:

1. Maintain a graph of creators, publications, channels, hashtags, lists, keywords, and adjacent creators.
2. Refresh those sources on a schedule from the cloud agent.
3. Normalize every post into one cross-platform model.
4. Store metric snapshots over time.
5. Rank posts by outlier score, velocity, freshness, niche relevance, and quality signals.
6. Let the Mac app browse, filter, open, save, and add creators back into the graph.

## API Keys And Where They Go

Provider secrets go in the cloud agent environment, not in the shipped Mac app.

Add these to Railway/project environment variables and to local `cosmo-cloud-agent/.env` for development:

```bash
SUPABASE_URL=https://cskxozkzpzxyefqmgsgg.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
COSMO_USER_ID=...

DISCOVERY_API_KEY=...
YOUTUBE_API_KEY=...
BRIGHT_DATA_API_KEY=...
BRIGHT_DATA_DATASET_INSTAGRAM=...
BRIGHT_DATA_DATASET_TIKTOK=...
BRIGHT_DATA_DATASET_LINKEDIN=...
BRIGHT_DATA_DATASET_X=...
APIFY_API_KEY=...
X_BEARER_TOKEN=...
```

Notes:

- `SUPABASE_SERVICE_ROLE_KEY` remains server-only.
- `DISCOVERY_API_KEY` protects refresh/add-source endpoints called by the Mac app.
- `YOUTUBE_API_KEY` is safe to use server-side for public YouTube discovery and channel/video stats.
- `BRIGHT_DATA_*` is the primary public social discovery provider family for Instagram, TikTok, LinkedIn, and X if selected.
- `APIFY_API_KEY` remains the fallback/compatibility path for Instagram because the app already has an Apify integration.
- Substack public RSS does not need a key.
- TikTok Display API and LinkedIn official APIs are not the main public discovery feed path; treat them as connected-account/owned-account integrations unless product access changes.

Modify:

- `cosmo-cloud-agent/src/config.ts`: add the discovery/provider env vars.
- `Config/APIKeys.swift`: do not add provider secrets. Only add a cloud discovery endpoint/key if the Mac app needs to call protected cloud endpoints directly.

## Data Model

Create SQL migrations under `supabase/migrations/`.

### `social_creators`

Stores one creator identity per platform account.

Fields:

- `uuid uuid primary key`
- `user_id uuid not null`
- `platform text not null`
- `platform_creator_id text`
- `handle text not null`
- `display_name text`
- `bio text`
- `avatar_url text`
- `profile_url text`
- `follower_count bigint`
- `following_count bigint`
- `post_count bigint`
- `language text`
- `niche_tags text[] not null default '{}'`
- `source_tags text[] not null default '{}'`
- `last_seen_at timestamptz`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Unique index:

- `(user_id, platform, handle)`

### `social_sources`

Stores the graph nodes the system refreshes.

Fields:

- `uuid uuid primary key`
- `user_id uuid not null`
- `kind text not null`
- `platform text`
- `label text not null`
- `query text`
- `profile_url text`
- `creator_uuid uuid references social_creators(uuid)`
- `niche_tags text[] not null default '{}'`
- `priority int not null default 50`
- `cadence_minutes int not null default 1440`
- `status text not null default 'active'`
- `last_run_at timestamptz`
- `next_run_at timestamptz`
- `last_error text`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Allowed `kind` values:

- `tracked_creator`
- `curated_creator`
- `publication_feed`
- `youtube_channel`
- `keyword`
- `hashtag`
- `list`
- `adjacent_creator`

### `social_discovered_posts`

Stores normalized post snapshots.

Fields:

- `uuid uuid primary key`
- `user_id uuid not null`
- `platform text not null`
- `platform_post_id text not null`
- `creator_uuid uuid references social_creators(uuid)`
- `source_uuid uuid references social_sources(uuid)`
- `canonical_url text not null`
- `title text`
- `caption text`
- `transcript text`
- `language text`
- `posted_at timestamptz`
- `media_type text`
- `media_urls jsonb not null default '[]'`
- `thumbnail_url text`
- `duration_seconds int`
- `view_count bigint`
- `like_count bigint`
- `comment_count bigint`
- `repost_count bigint`
- `share_count bigint`
- `engagement_rate numeric`
- `outlier_score numeric`
- `outlier_grade text`
- `velocity_score numeric`
- `ranking_score numeric`
- `niche_tags text[] not null default '{}'`
- `format_tags text[] not null default '{}'`
- `hook_tags text[] not null default '{}'`
- `raw_payload jsonb not null default '{}'`
- `first_seen_at timestamptz not null default now()`
- `last_refreshed_at timestamptz`
- `saved_atom_uuid text`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Unique index:

- `(user_id, platform, platform_post_id)`

### `social_metric_snapshots`

Stores metric history so velocity and outlier scores improve over time.

Fields:

- `uuid uuid primary key`
- `user_id uuid not null`
- `post_uuid uuid references social_discovered_posts(uuid)`
- `captured_at timestamptz not null default now()`
- `view_count bigint`
- `like_count bigint`
- `comment_count bigint`
- `repost_count bigint`
- `share_count bigint`

### `social_source_edges`

Stores graph expansion provenance.

Fields:

- `uuid uuid primary key`
- `user_id uuid not null`
- `from_source_uuid uuid`
- `from_creator_uuid uuid`
- `to_creator_uuid uuid`
- `to_source_uuid uuid`
- `edge_type text not null`
- `confidence numeric not null default 0.5`
- `created_at timestamptz not null default now()`

### `social_discovery_runs`

Stores scheduler/provider health.

Fields:

- `uuid uuid primary key`
- `user_id uuid not null`
- `source_uuid uuid references social_sources(uuid)`
- `provider text not null`
- `status text not null`
- `started_at timestamptz not null default now()`
- `finished_at timestamptz`
- `posts_found int not null default 0`
- `posts_upserted int not null default 0`
- `error_message text`
- `rate_limited_until timestamptz`

## Task 1: Add Cloud Discovery Config

**Files:**

- Modify: `cosmo-cloud-agent/src/config.ts`
- Create: `cosmo-cloud-agent/src/discovery/config.ts`

- [ ] Add provider env vars to `config.ts`.
- [ ] Add `discoveryConfig` helper that exposes provider availability without leaking keys in logs.
- [ ] Update `validateConfig()` so missing discovery provider keys warn in development but do not crash the whole agent.
- [ ] Run `npm run typecheck` from `cosmo-cloud-agent`.
- [ ] Commit: `feat: add discovery provider config`

## Task 2: Add Supabase Discovery Schema

**Files:**

- Create: `supabase/migrations/20260529_social_discovery_graph.sql`
- Create: `cosmo-cloud-agent/src/discovery/types.ts`

- [ ] Add the six tables above with indexes for `user_id`, `platform`, `posted_at`, `ranking_score`, `outlier_score`, `creator_uuid`, and `source_uuid`.
- [ ] Add RLS policies that allow the logged-in user to read their rows and allow service-role writes.
- [ ] Add TypeScript types matching the table payloads.
- [ ] Apply migration locally or in Supabase SQL editor.
- [ ] Commit: `feat: add social discovery graph schema`

## Task 3: Provider Interface And Normalization

**Files:**

- Create: `cosmo-cloud-agent/src/discovery/providers/provider.ts`
- Create: `cosmo-cloud-agent/src/discovery/normalize.ts`
- Create: `cosmo-cloud-agent/src/discovery/scoring.ts`
- Create: `cosmo-cloud-agent/src/discovery/db.ts`
- Create: `cosmo-cloud-agent/tests/discovery.normalize.test.ts`

- [ ] Define `DiscoveryProvider` with methods for creator resolution, source refresh, post refresh, and transcript fetch when available.
- [ ] Normalize all providers into one `DiscoveredPostInput`.
- [ ] Implement deterministic dedupe by `(platform, platform_post_id)` and canonical URL fallback.
- [ ] Implement scoring inputs: creator baseline median, view/engagement velocity, outlier multiplier, freshness decay.
- [ ] Test normalization with fixtures for YouTube, Substack, Instagram, TikTok, LinkedIn, and X.
- [ ] Commit: `feat: add discovery provider contract`

## Task 4: YouTube Provider

**Files:**

- Create: `cosmo-cloud-agent/src/discovery/providers/youtube.ts`
- Create: `cosmo-cloud-agent/tests/discovery.youtube.test.ts`

- [ ] Use `YOUTUBE_API_KEY` server-side.
- [ ] Resolve channel URLs and handles into channel IDs.
- [ ] Pull latest uploads from channel upload playlists.
- [ ] Pull public stats and thumbnails from video resources.
- [ ] Store transcripts through the existing app transcript path when available; otherwise mark transcript as fetchable/unavailable.
- [ ] Commit: `feat: add youtube discovery provider`

## Task 5: Substack Provider

**Files:**

- Create: `cosmo-cloud-agent/src/discovery/providers/substack.ts`
- Create: `cosmo-cloud-agent/tests/discovery.substack.test.ts`

- [ ] Resolve publication URL to public RSS feed.
- [ ] Pull recent posts and notes where RSS exposes them.
- [ ] Normalize title, excerpt, URL, publish date, author/publication, and thumbnail if present.
- [ ] Mark metrics as unavailable unless a managed provider supplies them later.
- [ ] Commit: `feat: add substack discovery provider`

## Task 6: Managed Social Provider For Instagram, TikTok, LinkedIn, And X

**Files:**

- Create: `cosmo-cloud-agent/src/discovery/providers/managedSocial.ts`
- Create: `cosmo-cloud-agent/src/discovery/providers/apifyInstagram.ts`
- Create: `cosmo-cloud-agent/tests/discovery.managed-social.test.ts`

- [ ] Add Bright Data or equivalent managed-provider adapter behind one interface.
- [ ] Support source refresh for creator profiles, hashtags, lists/search URLs, and adjacent creators where provider data exposes them.
- [ ] Map platform-specific metrics to the normalized model.
- [ ] Add Apify Instagram fallback using `APIFY_API_KEY` and the existing app's Instagram assumptions.
- [ ] Do not put managed provider calls in Swift.
- [ ] Commit: `feat: add managed social discovery provider`

## Task 7: Source Graph Scheduler

**Files:**

- Create: `cosmo-cloud-agent/src/discovery/scheduler.ts`
- Create: `cosmo-cloud-agent/src/discovery/jobs.ts`
- Modify: `cosmo-cloud-agent/src/index.ts`

- [ ] Add hot-lane cron: every 2 hours, refresh high-priority tracked creators and curated creators.
- [ ] Add daily broad refresh: refresh all active sources due by `next_run_at`.
- [ ] Add weekly exploration: create `adjacent_creator` sources from high-performing creators/posts.
- [ ] Add provider backoff: if rate limited, write `rate_limited_until` and skip until safe.
- [ ] Start scheduler from `index.ts` beside the existing standing scheduler.
- [ ] Commit: `feat: schedule discovery graph refreshes`

## Task 8: Discovery API Routes

**Files:**

- Create: `cosmo-cloud-agent/src/api/discovery.ts`
- Modify: `cosmo-cloud-agent/src/index.ts`

- [ ] Add `GET /api/discovery/feed` with filters for platform, language, followers, outlier threshold, posted window, niche, format, creator, and sort.
- [ ] Add `GET /api/discovery/creators`.
- [ ] Add `POST /api/discovery/sources` for adding a creator/profile URL/keyword/source to the graph.
- [ ] Add `POST /api/discovery/sources/:uuid/refresh` for manual refresh.
- [ ] Add `POST /api/discovery/posts/:uuid/save` to convert a discovered post into a normal swipe atom and optionally attach a custom board.
- [ ] Protect write/refresh routes with `DISCOVERY_API_KEY` or the existing authenticated Supabase session.
- [ ] Commit: `feat: add discovery api routes`

## Task 9: Swift Remote Discovery Store

**Files:**

- Create: `SwipeFile/Discovery/SocialDiscoveryRemoteStore.swift`
- Modify: `SwipeFile/Discovery/SocialDiscoveryStore.swift`
- Modify: `UI/SwipeFile/SwipeFileHomeView.swift`
- Test: `Tests/CosmoOSTests/SocialDiscoveryRemoteStoreTests.swift`

- [ ] Add remote feed loading from Supabase or cloud API.
- [ ] Preserve local snapshot fallback so the UI still works offline.
- [ ] Show provider freshness states: fresh, refreshing, stale, rate-limited, provider-missing.
- [ ] Stop treating local creator catalog imports as the only Discover data source.
- [ ] Commit: `feat: load discovery feed from cloud graph`

## Task 10: Add Creator Flow

**Files:**

- Modify: `UI/SwipeFile/SwipeFileHomeView.swift`
- Create or modify focused subviews under `UI/SwipeFile/`
- Modify: `SwipeFile/Discovery/SocialPlatformResolver.swift`

- [ ] In Discover and Creators, let the user paste a profile URL or type a handle.
- [ ] Resolve platform deterministically.
- [ ] If ambiguous, show platform chips rather than guessing.
- [ ] Create a `tracked_creator` source through `POST /api/discovery/sources`.
- [ ] Enqueue immediate refresh.
- [ ] Show the creator in Creators with a `Refreshing` state before posts arrive.
- [ ] Once posts arrive, support sorting by highest outlier, most viewed, most liked, most commented, most reposted, and newest.
- [ ] Commit: `feat: add creators to discovery graph from app`

## Task 11: Card Media, Detail Sheet, Transcript, And Boards

**Files:**

- Modify focused Swipe File Discover/Creator subviews.
- Modify existing board save flow only through established board APIs.

- [ ] Cache and render thumbnails from `thumbnail_url` and `media_urls`.
- [ ] Use consistent card components across Discover and Creators.
- [ ] Add plus button on hover to save to a selected board.
- [ ] Add detail sheet with caption, transcript status, metrics, source URL, and save-to-board action.
- [ ] Fetch transcript through provider when available, then persist it to `social_discovered_posts.transcript`.
- [ ] Saving a discovered post creates a normal Swipe File atom; the original discovered post stays in Discover.
- [ ] Commit: `feat: complete discovery post actions`

## Task 12: Ranking, Monitoring, And QA

**Files:**

- Modify: `cosmo-cloud-agent/src/discovery/scoring.ts`
- Modify: `cosmo-cloud-agent/src/discovery/scheduler.ts`
- Create: `cosmo-cloud-agent/src/discovery/health.ts`
- Modify: `cosmo-cloud-agent/src/index.ts`

- [ ] Add `/api/discovery/health` with last run, provider availability, rate limit state, feed count, newest post age, and thumbnail coverage.
- [ ] Add logs for each source refresh: provider, source, posts found, posts upserted, duration, error.
- [ ] Add a dashboard-friendly JSON health response.
- [ ] Run `npm run typecheck`.
- [ ] Build the macOS app.
- [ ] Verify Discover shows more than local fixtures, has current posts, thumbnails, filter changes, creator add, and save-to-board.
- [ ] Commit: `feat: add discovery health monitoring`

## Execution Order

1. Schema and cloud config.
2. Provider contract and normalization tests.
3. YouTube and Substack first, because they are the lowest-risk real providers.
4. Managed social provider adapter for Instagram, TikTok, LinkedIn, and X.
5. Scheduler and ranking.
6. API routes.
7. Swift remote store.
8. Creator add flow.
9. Card/media/detail/board polish.
10. Monitoring and production QA.

## Acceptance Criteria

- Discover opens to a populated feed without requiring a search.
- The newest feed items refresh daily, with hot sources refreshing multiple times per day.
- YouTube, Substack, Instagram, TikTok, LinkedIn, and X are represented through the same normalized post model.
- Adding a creator from a handle/profile URL creates a graph source and refreshes it immediately.
- Creators tab can show all known posts for a creator and sort by top metrics/outlier score.
- Cards show thumbnails where the provider supplies media.
- Saving to a board creates/links a real Swipe File item while keeping the discovered post in the discovery cache.
- Provider keys are server-side only.
- The app clearly reports stale/provider-missing/rate-limited states instead of silently showing an empty feed.

## Source Notes

- YouTube Data API supports public resources such as channels, playlists, search, videos, and thumbnails.
- Substack exposes public RSS feeds for publications.
- TikTok Display API and LinkedIn official APIs are best treated as auth/owned-account APIs for this product unless access expands.
- A managed social data provider is required for robust public Instagram, TikTok, LinkedIn, and X discovery at the level shown in the reference screenshots.
