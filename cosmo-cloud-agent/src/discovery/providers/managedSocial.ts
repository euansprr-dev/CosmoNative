import { config } from '../../config';
import type { DiscoveredPostInput, SocialPlatform, SocialSourceRow } from '../types';
import type { DiscoveryProvider, DiscoveryRefreshResult } from './provider';
import { DiscoveryProviderNotConfiguredError } from './provider';

type ManagedPlatform = Extract<SocialPlatform, 'instagram' | 'tiktok' | 'linkedin' | 'x'>;
type BrightDataInput = { url: string } | { username: string };

type BrightDataDatasetConfig = typeof config.brightDataDatasets;

interface ManagedSocialPayload {
  posts?: Array<Record<string, unknown>>;
  data?: Array<Record<string, unknown>>;
  items?: Array<Record<string, unknown>>;
}

function stringValue(payload: Record<string, unknown>, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return undefined;
}

function numberValue(payload: Record<string, unknown>, keys: string[]): number | undefined {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string') {
      const parsed = Number.parseInt(value.replace(/[,_]/g, ''), 10);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return undefined;
}

function arrayPayload(payload: ManagedSocialPayload): Array<Record<string, unknown>> {
  return payload.posts ?? payload.data ?? payload.items ?? [];
}

function sourceValue(source: SocialSourceRow): string {
  return source.profile_url ?? source.query ?? source.label;
}

function isInstagramReelURL(value: string): boolean {
  return /instagram\.com\/reel\//i.test(value);
}

function isInstagramPostURL(value: string): boolean {
  return /instagram\.com\/p\//i.test(value);
}

function isPlatformPostURL(platform: ManagedPlatform, value: string): boolean {
  switch (platform) {
    case 'instagram':
      return isInstagramReelURL(value) || isInstagramPostURL(value);
    case 'tiktok':
      return /tiktok\.com\/@[^/]+\/video\//i.test(value);
    case 'linkedin':
      return /linkedin\.com\/posts\/|linkedin\.com\/feed\/update\//i.test(value);
    case 'x':
      return /(?:x|twitter)\.com\/[^/]+\/status\//i.test(value);
  }
}

function isCreatorSource(source: SocialSourceRow): boolean {
  return source.kind === 'tracked_creator' || source.kind === 'curated_creator';
}

function cleanUsername(value: string): string {
  return value
    .replace(/^@/, '')
    .replace(/^https?:\/\//, '')
    .replace(/^www\./, '')
    .split(/[/?#]/)[0]
    .trim();
}

export function brightDataInputForSource(source: SocialSourceRow): BrightDataInput[] {
  const value = sourceValue(source);
  if (/^https?:\/\//i.test(value)) {
    return [{ url: value }];
  }
  return [{ username: cleanUsername(value) }];
}

export function brightDataDatasetForSource(
  source: SocialSourceRow,
  datasets: BrightDataDatasetConfig = config.brightDataDatasets
): string | null {
  if (!source.platform || !['instagram', 'tiktok', 'linkedin', 'x'].includes(source.platform)) {
    return null;
  }

  const platform = source.platform as ManagedPlatform;
  const value = sourceValue(source);
  if (platform === 'instagram') {
    const platformDatasets = datasets.instagram;
    if (isInstagramReelURL(value)) return platformDatasets.reelsByUrl || null;
    if (isInstagramPostURL(value)) return platformDatasets.postsByUrl || null;
    if (isCreatorSource(source) && /^https?:\/\//i.test(value)) {
      return platformDatasets.reelsByUrl
        || platformDatasets.postsByUrl
        || platformDatasets.profilesByUsername
        || platformDatasets.profilesByUrl
        || null;
    }
    if (/^https?:\/\//i.test(value)) return platformDatasets.profilesByUrl || null;
    return platformDatasets.profilesByUsername || platformDatasets.profilesByUrl || null;
  }

  const platformDatasets = datasets[platform];
  if (isPlatformPostURL(platform, value)) {
    return platformDatasets.postsByUrl || null;
  }

  return platformDatasets.profilesByUrl || platformDatasets.postsByUrl || null;
}

export function managedSocialRecordToPost(
  platform: ManagedPlatform,
  provider: string,
  record: Record<string, unknown>,
  source: SocialSourceRow
): DiscoveredPostInput {
  const id = stringValue(record, ['id', 'post_id', 'shortcode', 'urn', 'tweet_id', 'url']) ?? crypto.randomUUID();
  const url = stringValue(record, ['url', 'post_url', 'permalink', 'canonical_url']) ?? source.profile_url ?? source.query ?? '';
  const authorHandle = stringValue(record, ['author_handle', 'username', 'handle', 'screen_name']) ?? source.label;
  const authorName = stringValue(record, ['author_name', 'full_name', 'name', 'display_name']) ?? authorHandle;
  const thumbnail = stringValue(record, ['thumbnail_url', 'thumbnail', 'image_url', 'cover_url']);
  const videoUrl = stringValue(record, ['video_url', 'video']);
  const imageUrl = stringValue(record, ['image_url', 'image', 'display_url']);

  return {
    platform,
    provider,
    platformPostId: id,
    canonicalUrl: url,
    sourceUuid: source.uuid,
    creator: {
      platform,
      platformCreatorId: stringValue(record, ['author_id', 'user_id', 'creator_id']),
      handle: authorHandle,
      displayName: authorName,
      avatarUrl: stringValue(record, ['avatar_url', 'profile_image_url']),
      profileUrl: stringValue(record, ['author_url', 'profile_url']) ?? source.profile_url ?? undefined,
      followerCount: numberValue(record, ['followers', 'follower_count', 'followers_count']),
    },
    title: stringValue(record, ['title', 'headline']),
    caption: stringValue(record, ['caption', 'text', 'description', 'body']),
    postedAt: stringValue(record, ['posted_at', 'timestamp', 'created_at', 'date']),
    mediaType: videoUrl ? 'short_video' : imageUrl ? 'image' : 'text',
    mediaUrls: [
      ...(thumbnail ? [{ kind: 'thumbnail' as const, url: thumbnail }] : []),
      ...(videoUrl ? [{ kind: 'video' as const, url: videoUrl }] : []),
      ...(imageUrl ? [{ kind: 'image' as const, url: imageUrl }] : []),
    ],
    thumbnailUrl: thumbnail ?? imageUrl,
    metrics: {
      views: numberValue(record, ['views', 'view_count', 'play_count']),
      likes: numberValue(record, ['likes', 'like_count', 'favorite_count']),
      comments: numberValue(record, ['comments', 'comment_count', 'reply_count']),
      reposts: numberValue(record, ['reposts', 'retweets', 'share_count', 'shares']),
      shares: numberValue(record, ['shares', 'share_count']),
    },
    rawPayload: record,
  };
}

export class ManagedSocialDiscoveryProvider implements DiscoveryProvider {
  readonly id = 'brightdata';
  readonly platforms = ['instagram', 'tiktok', 'linkedin', 'x'] as const;

  isConfigured(): boolean {
    return config.brightDataApiKey.length > 0
      && Object.values(config.brightDataDatasets).some(platformConfig => (
        Object.values(platformConfig).some(Boolean)
      ));
  }

  canRefresh(source: SocialSourceRow): boolean {
    return Boolean(source.platform && this.platforms.includes(source.platform as ManagedPlatform));
  }

  async refreshSource(source: SocialSourceRow): Promise<DiscoveryRefreshResult> {
    if (!this.isConfigured()) {
      throw new DiscoveryProviderNotConfiguredError(this.id, 'BRIGHT_DATA_API_KEY');
    }
    if (!source.platform || !this.platforms.includes(source.platform as ManagedPlatform)) {
      throw new Error(`Unsupported managed social platform: ${source.platform}`);
    }

    const platform = source.platform as ManagedPlatform;
    const datasetId = brightDataDatasetForSource(source);
    if (!datasetId) {
      throw new DiscoveryProviderNotConfiguredError(this.id, `Bright Data ${platform} endpoint dataset ID`);
    }
    const brightDataInput = brightDataInputForSource(source);
    console.log('[discovery-brightdata] trigger', {
      sourceUuid: source.uuid,
      platform,
      datasetId,
      inputMode: 'url' in brightDataInput[0] ? 'url' : 'username',
      inputCount: brightDataInput.length,
    });

    const response = await fetch(
      `https://api.brightdata.com/datasets/v3/scrape?dataset_id=${encodeURIComponent(datasetId)}&include_errors=true`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${config.brightDataApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(brightDataInput),
      }
    );

    console.log('[discovery-brightdata] response', {
      sourceUuid: source.uuid,
      platform,
      status: response.status,
      ok: response.ok,
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Bright Data trigger ${response.status}: ${body.slice(0, 300)}`);
    }

    const payload = await response.json() as ManagedSocialPayload | Array<Record<string, unknown>>;
    const records = Array.isArray(payload) ? payload : arrayPayload(payload);
    return {
      provider: this.id,
      source,
      posts: records.map(record => managedSocialRecordToPost(platform, this.id, record, source)),
    };
  }
}
