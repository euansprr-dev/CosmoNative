import { v4 as uuidv4 } from 'uuid';
import { supabase, userId } from '../db/client';
import { createAtom, updateAtom } from '../db/queries';
import { applyScore, scorePost } from './scoring';
import type {
  DiscoveryCreatorInput,
  NormalizedDiscoveredPost,
  SocialCreatorRow,
  SocialDiscoveredPostRow,
  SocialPlatform,
  SocialSourceKind,
  SocialSourceRow,
} from './types';

function nowISO(): string {
  return new Date().toISOString();
}

function handle(input: string): string {
  return input.replace(/^@/, '').trim().toLowerCase();
}

function reachFor(row: Pick<SocialDiscoveredPostRow, 'view_count' | 'like_count' | 'comment_count' | 'repost_count'>): number | null {
  return row.view_count ?? row.like_count ?? row.comment_count ?? row.repost_count ?? null;
}

export async function upsertCreator(input: DiscoveryCreatorInput): Promise<SocialCreatorRow> {
  const row = {
    user_id: userId,
    platform: input.platform,
    platform_creator_id: input.platformCreatorId ?? null,
    handle: handle(input.handle),
    display_name: input.displayName ?? input.handle,
    bio: input.bio ?? null,
    avatar_url: input.avatarUrl ?? null,
    profile_url: input.profileUrl ?? null,
    follower_count: input.followerCount ?? null,
    following_count: input.followingCount ?? null,
    post_count: input.postCount ?? null,
    language: input.language ?? null,
    niche_tags: input.nicheTags ?? [],
    source_tags: input.sourceTags ?? [],
    last_seen_at: nowISO(),
    updated_at: nowISO(),
  };

  const { data, error } = await supabase
    .from('social_creators')
    .upsert(row, { onConflict: 'user_id,platform,handle' })
    .select('*')
    .single();

  if (error || !data) {
    throw new Error(`upsertCreator failed: ${error?.message ?? 'no data'}`);
  }
  return data as SocialCreatorRow;
}

async function creatorReachBaseline(creatorUuid: string): Promise<number[]> {
  const { data, error } = await supabase
    .from('social_discovered_posts')
    .select('view_count,like_count,comment_count,repost_count')
    .eq('user_id', userId)
    .eq('creator_uuid', creatorUuid)
    .order('posted_at', { ascending: false, nullsFirst: false })
    .limit(30);

  if (error || !data) return [];
  return (data as Array<Pick<SocialDiscoveredPostRow, 'view_count' | 'like_count' | 'comment_count' | 'repost_count'>>)
    .map(reachFor)
    .filter((value): value is number => typeof value === 'number' && value > 0);
}

export async function upsertDiscoveredPost(input: NormalizedDiscoveredPost): Promise<SocialDiscoveredPostRow> {
  const creator = await upsertCreator(input.creator);
  const baseline = await creatorReachBaseline(creator.uuid);
  const scored = applyScore(input, scorePost({ post: input, creatorRecentReach: baseline }));
  const timestamp = nowISO();

  const row = {
    user_id: userId,
    platform: scored.platform,
    platform_post_id: scored.platform_post_id,
    creator_uuid: creator.uuid,
    source_uuid: scored.source_uuid,
    canonical_url: scored.canonical_url,
    title: scored.title,
    caption: scored.caption,
    transcript: scored.transcript,
    language: scored.language,
    posted_at: scored.posted_at,
    media_type: scored.media_type,
    media_urls: scored.media_urls,
    thumbnail_url: scored.thumbnail_url,
    duration_seconds: scored.duration_seconds,
    view_count: scored.view_count,
    like_count: scored.like_count,
    comment_count: scored.comment_count,
    repost_count: scored.repost_count,
    share_count: scored.share_count,
    engagement_rate: scored.engagement_rate,
    outlier_score: scored.outlier_score,
    outlier_grade: scored.outlier_grade,
    velocity_score: scored.velocity_score,
    ranking_score: scored.ranking_score,
    niche_tags: scored.niche_tags,
    format_tags: scored.format_tags,
    hook_tags: scored.hook_tags,
    raw_payload: scored.raw_payload,
    last_refreshed_at: timestamp,
    updated_at: timestamp,
  };

  const { data, error } = await supabase
    .from('social_discovered_posts')
    .upsert(row, { onConflict: 'user_id,platform,platform_post_id' })
    .select('*')
    .single();

  if (error || !data) {
    throw new Error(`upsertDiscoveredPost failed: ${error?.message ?? 'no data'}`);
  }

  const saved = data as SocialDiscoveredPostRow;
  await supabase.from('social_metric_snapshots').insert({
    uuid: uuidv4(),
    user_id: userId,
    post_uuid: saved.uuid,
    view_count: saved.view_count,
    like_count: saved.like_count,
    comment_count: saved.comment_count,
    repost_count: saved.repost_count,
    share_count: saved.share_count,
  });
  return saved;
}

export async function createSource(params: {
  kind: SocialSourceKind;
  platform?: SocialPlatform | null;
  label: string;
  query?: string | null;
  profileUrl?: string | null;
  creatorUuid?: string | null;
  nicheTags?: string[];
  priority?: number;
  cadenceMinutes?: number;
}): Promise<SocialSourceRow> {
  const { data, error } = await supabase
    .from('social_sources')
    .insert({
      uuid: uuidv4(),
      user_id: userId,
      kind: params.kind,
      platform: params.platform ?? null,
      label: params.label,
      query: params.query ?? null,
      profile_url: params.profileUrl ?? null,
      creator_uuid: params.creatorUuid ?? null,
      niche_tags: params.nicheTags ?? [],
      priority: params.priority ?? 50,
      cadence_minutes: params.cadenceMinutes ?? 1440,
      status: 'active',
      next_run_at: nowISO(),
    })
    .select('*')
    .single();

  if (error || !data) {
    throw new Error(`createSource failed: ${error?.message ?? 'no data'}`);
  }
  return data as SocialSourceRow;
}

export async function fetchDueSources(limit = 25): Promise<SocialSourceRow[]> {
  const { data, error } = await supabase
    .from('social_sources')
    .select('*')
    .eq('user_id', userId)
    .eq('status', 'active')
    .or(`next_run_at.is.null,next_run_at.lte.${nowISO()}`)
    .order('priority', { ascending: false })
    .limit(limit);

  if (error || !data) return [];
  return data as SocialSourceRow[];
}

export async function fetchActiveSources(limit = 25): Promise<SocialSourceRow[]> {
  const { data, error } = await supabase
    .from('social_sources')
    .select('*')
    .eq('user_id', userId)
    .eq('status', 'active')
    .order('priority', { ascending: false })
    .limit(limit);

  if (error || !data) return [];
  return data as SocialSourceRow[];
}

export async function updateSourceAfterRun(source: SocialSourceRow, status: 'active' | 'error' | 'rate_limited', errorMessage?: string): Promise<void> {
  const next = new Date(Date.now() + source.cadence_minutes * 60_000).toISOString();
  await supabase
    .from('social_sources')
    .update({
      status,
      last_run_at: nowISO(),
      next_run_at: status === 'active' ? next : new Date(Date.now() + 60 * 60_000).toISOString(),
      last_error: errorMessage ?? null,
      updated_at: nowISO(),
    })
    .eq('uuid', source.uuid)
    .eq('user_id', userId);
}

export async function recordDiscoveryRun(params: {
  sourceUuid: string | null;
  provider: string;
  status: string;
  startedAt: string;
  postsFound?: number;
  postsUpserted?: number;
  errorMessage?: string;
}): Promise<void> {
  await supabase.from('social_discovery_runs').insert({
    uuid: uuidv4(),
    user_id: userId,
    source_uuid: params.sourceUuid,
    provider: params.provider,
    status: params.status,
    started_at: params.startedAt,
    finished_at: nowISO(),
    posts_found: params.postsFound ?? 0,
    posts_upserted: params.postsUpserted ?? 0,
    error_message: params.errorMessage ?? null,
  });
}

export async function fetchDiscoveryFeed(filters: {
  platforms?: SocialPlatform[];
  minOutlier?: number;
  postedAfter?: string;
  creatorUuid?: string;
  query?: string;
  limit?: number;
}): Promise<SocialDiscoveredPostRow[]> {
  let query = supabase
    .from('social_discovered_posts')
    .select('*')
    .eq('user_id', userId)
    .order('ranking_score', { ascending: false, nullsFirst: false })
    .order('posted_at', { ascending: false, nullsFirst: false })
    .limit(filters.limit ?? 100);

  if (filters.platforms?.length) query = query.in('platform', filters.platforms);
  if (filters.minOutlier) query = query.gte('outlier_score', filters.minOutlier);
  if (filters.postedAfter) query = query.gte('posted_at', filters.postedAfter);
  if (filters.creatorUuid) query = query.eq('creator_uuid', filters.creatorUuid);
  if (filters.query) {
    query = query.or(`title.ilike.%${filters.query}%,caption.ilike.%${filters.query}%`);
  }

  const { data, error } = await query;
  if (error || !data) return [];
  return data as SocialDiscoveredPostRow[];
}

export async function fetchCreators(limit = 200): Promise<SocialCreatorRow[]> {
  const { data, error } = await supabase
    .from('social_creators')
    .select('*')
    .eq('user_id', userId)
    .order('follower_count', { ascending: false, nullsFirst: false })
    .limit(limit);

  if (error || !data) return [];
  return data as SocialCreatorRow[];
}

export async function saveDiscoveredPostToSwipe(postUuid: string, boardId?: string): Promise<string> {
  const { data, error } = await supabase
    .from('social_discovered_posts')
    .select('*')
    .eq('uuid', postUuid)
    .eq('user_id', userId)
    .single();

  if (error || !data) throw new Error(`Post not found: ${postUuid}`);
  const post = data as SocialDiscoveredPostRow;

  if (post.saved_atom_uuid) {
    if (boardId) {
      await updateAtom(post.saved_atom_uuid, {
        metadata: { boardId },
      });
    }
    return post.saved_atom_uuid;
  }

  const atom = await createAtom({
    type: 'research',
    title: post.title ?? post.caption?.slice(0, 120) ?? post.canonical_url,
    body: post.caption ?? post.transcript ?? post.canonical_url,
    structured: {
      source: post.platform,
      url: post.canonical_url,
      transcript: post.transcript,
      metrics: {
        views: post.view_count,
        likes: post.like_count,
        comments: post.comment_count,
        reposts: post.repost_count,
        shares: post.share_count,
        outlierScore: post.outlier_score,
      },
    },
    metadata: {
      source: 'discovery',
      platform: post.platform,
      boardId: boardId ?? null,
      thumbnailUrl: post.thumbnail_url,
      discoveredPostUuid: post.uuid,
    },
  });

  if (!atom) throw new Error(`Failed to create swipe atom for ${postUuid}`);

  await supabase
    .from('social_discovered_posts')
    .update({ saved_atom_uuid: atom.uuid, updated_at: nowISO() })
    .eq('uuid', post.uuid)
    .eq('user_id', userId);

  return atom.uuid;
}
