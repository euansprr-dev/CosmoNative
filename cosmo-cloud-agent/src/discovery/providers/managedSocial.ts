import { config } from '../../config';
import type { DiscoveredPostInput, SocialPlatform, SocialSourceRow } from '../types';
import type { DiscoveryProvider, DiscoveryRefreshResult } from './provider';
import { DiscoveryProviderNotConfiguredError } from './provider';

type ManagedPlatform = Extract<SocialPlatform, 'instagram' | 'tiktok' | 'linkedin' | 'x'>;

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
    return config.brightDataApiKey.length > 0;
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
    const datasetId = config.brightDataDatasets[platform];
    if (!datasetId) {
      throw new DiscoveryProviderNotConfiguredError(this.id, `BRIGHT_DATA_DATASET_${platform.toUpperCase()}`);
    }

    const response = await fetch(
      `https://api.brightdata.com/datasets/v3/scrape?dataset_id=${encodeURIComponent(datasetId)}&include_errors=true`,
      {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.brightDataApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ input: [{ url: source.profile_url ?? source.query ?? source.label }] }),
      }
    );

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
