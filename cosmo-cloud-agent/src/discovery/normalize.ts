import type { DiscoveredPostInput, NormalizedDiscoveredPost, SocialMediaType } from './types';

function cleanString(value: string | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function numberOrNull(value: number | undefined): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function normalizeTags(tags: string[] | undefined): string[] {
  if (!tags) return [];
  return Array.from(new Set(tags.map(tag => tag.trim().toLowerCase()).filter(Boolean)));
}

function inferMediaType(input: DiscoveredPostInput): SocialMediaType {
  if (input.mediaType) return input.mediaType;
  const first = input.mediaUrls?.[0];
  if (!first) return input.caption || input.title ? 'text' : 'unknown';
  if (first.kind === 'video') return 'video';
  if (first.kind === 'image') return input.mediaUrls && input.mediaUrls.length > 1 ? 'carousel' : 'image';
  return 'unknown';
}

function engagementRate(input: DiscoveredPostInput): number | null {
  const metrics = input.metrics;
  if (!metrics?.views || metrics.views <= 0) return null;
  const engagements =
    (metrics.likes ?? 0) +
    (metrics.comments ?? 0) +
    (metrics.reposts ?? 0) +
    (metrics.shares ?? 0) +
    (metrics.saves ?? 0);
  return Number((engagements / metrics.views).toFixed(6));
}

export function normalizeDiscoveredPost(input: DiscoveredPostInput): NormalizedDiscoveredPost {
  return {
    platform: input.platform,
    provider: input.provider,
    platform_post_id: input.platformPostId.trim(),
    canonical_url: input.canonicalUrl.trim(),
    creator: {
      ...input.creator,
      handle: input.creator.handle.replace(/^@/, '').trim(),
      displayName: input.creator.displayName?.trim(),
      nicheTags: normalizeTags(input.creator.nicheTags),
      sourceTags: normalizeTags(input.creator.sourceTags),
    },
    source_uuid: input.sourceUuid ?? null,
    title: cleanString(input.title),
    caption: cleanString(input.caption),
    transcript: cleanString(input.transcript),
    language: cleanString(input.language ?? input.creator.language),
    posted_at: cleanString(input.postedAt),
    media_type: inferMediaType(input),
    media_urls: input.mediaUrls ?? [],
    thumbnail_url: cleanString(input.thumbnailUrl ?? input.mediaUrls?.find(media => media.kind === 'thumbnail')?.url),
    duration_seconds: numberOrNull(input.durationSeconds),
    view_count: numberOrNull(input.metrics?.views),
    like_count: numberOrNull(input.metrics?.likes),
    comment_count: numberOrNull(input.metrics?.comments),
    repost_count: numberOrNull(input.metrics?.reposts),
    share_count: numberOrNull(input.metrics?.shares),
    engagement_rate: engagementRate(input),
    outlier_score: null,
    outlier_grade: 'insufficient_data',
    velocity_score: null,
    ranking_score: null,
    niche_tags: normalizeTags(input.nicheTags),
    format_tags: normalizeTags(input.formatTags),
    hook_tags: normalizeTags(input.hookTags),
    raw_payload: input.rawPayload ?? {},
  };
}
