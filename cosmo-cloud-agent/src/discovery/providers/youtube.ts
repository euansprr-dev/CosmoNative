import { config } from '../../config';
import type { DiscoveredPostInput, SocialSourceRow } from '../types';
import type { DiscoveryProvider, DiscoveryRefreshResult } from './provider';
import { DiscoveryProviderNotConfiguredError } from './provider';

interface YouTubeThumbnail {
  url: string;
  width?: number;
  height?: number;
}

interface YouTubeVideoResource {
  id: string;
  snippet?: {
    channelId?: string;
    channelTitle?: string;
    title?: string;
    description?: string;
    publishedAt?: string;
    thumbnails?: Record<string, YouTubeThumbnail>;
  };
  statistics?: {
    viewCount?: string;
    likeCount?: string;
    commentCount?: string;
  };
  contentDetails?: {
    duration?: string;
  };
}

interface YouTubeChannelResource {
  id: string;
  snippet?: {
    title?: string;
    customUrl?: string;
    description?: string;
    thumbnails?: Record<string, YouTubeThumbnail>;
  };
  statistics?: {
    subscriberCount?: string;
    videoCount?: string;
  };
  contentDetails?: {
    relatedPlaylists?: {
      uploads?: string;
    };
  };
}

function intFromString(value: string | undefined): number | undefined {
  if (!value) return undefined;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function bestThumbnail(thumbnails: Record<string, YouTubeThumbnail> | undefined): YouTubeThumbnail | undefined {
  if (!thumbnails) return undefined;
  return thumbnails.maxres ?? thumbnails.standard ?? thumbnails.high ?? thumbnails.medium ?? thumbnails.default;
}

export function parseYouTubeDurationSeconds(duration: string | undefined): number | undefined {
  if (!duration) return undefined;
  const match = duration.match(/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!match) return undefined;
  const hours = Number.parseInt(match[1] ?? '0', 10);
  const minutes = Number.parseInt(match[2] ?? '0', 10);
  const seconds = Number.parseInt(match[3] ?? '0', 10);
  return hours * 3600 + minutes * 60 + seconds;
}

function handleFromChannel(channel: YouTubeChannelResource | undefined, fallback: string): string {
  const custom = channel?.snippet?.customUrl?.replace(/^@/, '').trim();
  if (custom) return custom;
  return fallback.replace(/^@/, '').trim();
}

export function youtubeVideoToPost(
  video: YouTubeVideoResource,
  creator: {
    handle: string;
    profileUrl?: string;
    followerCount?: number;
    avatarUrl?: string;
    bio?: string;
    postCount?: number;
  },
  sourceUuid?: string
): DiscoveredPostInput {
  const thumbnail = bestThumbnail(video.snippet?.thumbnails);
  const durationSeconds = parseYouTubeDurationSeconds(video.contentDetails?.duration);
  const formatTags = durationSeconds && durationSeconds <= 90 ? ['shorts'] : ['video'];

  return {
    platform: 'youtube',
    provider: 'youtube',
    platformPostId: video.id,
    canonicalUrl: `https://www.youtube.com/watch?v=${video.id}`,
    sourceUuid,
    creator: {
      platform: 'youtube',
      platformCreatorId: video.snippet?.channelId,
      handle: creator.handle,
      displayName: video.snippet?.channelTitle ?? creator.handle,
      bio: creator.bio,
      avatarUrl: creator.avatarUrl,
      profileUrl: creator.profileUrl,
      followerCount: creator.followerCount,
      postCount: creator.postCount,
    },
    title: video.snippet?.title,
    caption: video.snippet?.description,
    postedAt: video.snippet?.publishedAt,
    mediaType: durationSeconds && durationSeconds <= 90 ? 'short_video' : 'video',
    mediaUrls: thumbnail ? [{ kind: 'thumbnail', url: thumbnail.url, width: thumbnail.width, height: thumbnail.height }] : [],
    thumbnailUrl: thumbnail?.url,
    durationSeconds,
    metrics: {
      views: intFromString(video.statistics?.viewCount),
      likes: intFromString(video.statistics?.likeCount),
      comments: intFromString(video.statistics?.commentCount),
    },
    formatTags,
    rawPayload: video as unknown as Record<string, unknown>,
  };
}

export class YouTubeDiscoveryProvider implements DiscoveryProvider {
  readonly id = 'youtube';
  readonly platforms = ['youtube'] as const;

  isConfigured(): boolean {
    return config.youtubeApiKey.length > 0;
  }

  canRefresh(source: SocialSourceRow): boolean {
    return source.platform === 'youtube' && ['youtube_channel', 'tracked_creator', 'curated_creator'].includes(source.kind);
  }

  async refreshSource(source: SocialSourceRow): Promise<DiscoveryRefreshResult> {
    if (!this.isConfigured()) {
      throw new DiscoveryProviderNotConfiguredError(this.id, 'YOUTUBE_API_KEY');
    }

    const channel = await this.resolveChannel(source);
    const uploadsPlaylist = channel.contentDetails?.relatedPlaylists?.uploads;
    if (!uploadsPlaylist) {
      return { provider: this.id, source, posts: [] };
    }

    const playlistItems = await this.fetchJSON<{ items?: Array<{ snippet?: { resourceId?: { videoId?: string } } }> }>(
      'https://www.googleapis.com/youtube/v3/playlistItems',
      {
        part: 'snippet',
        playlistId: uploadsPlaylist,
        maxResults: '25',
      }
    );
    const videoIds = (playlistItems.items ?? [])
      .map(item => item.snippet?.resourceId?.videoId)
      .filter((id): id is string => Boolean(id));

    if (videoIds.length === 0) {
      return { provider: this.id, source, posts: [] };
    }

    const videos = await this.fetchJSON<{ items?: YouTubeVideoResource[] }>(
      'https://www.googleapis.com/youtube/v3/videos',
      {
        part: 'snippet,statistics,contentDetails',
        id: videoIds.join(','),
        maxResults: '25',
      }
    );

    const thumb = bestThumbnail(channel.snippet?.thumbnails);
    const creator = {
      handle: handleFromChannel(channel, source.query ?? source.label),
      profileUrl: channel.snippet?.customUrl ? `https://www.youtube.com/${channel.snippet.customUrl}` : source.profile_url ?? undefined,
      followerCount: intFromString(channel.statistics?.subscriberCount),
      avatarUrl: thumb?.url,
      bio: channel.snippet?.description,
      postCount: intFromString(channel.statistics?.videoCount),
    };

    return {
      provider: this.id,
      source,
      posts: (videos.items ?? []).map(video => youtubeVideoToPost(video, creator, source.uuid)),
    };
  }

  private async resolveChannel(source: SocialSourceRow): Promise<YouTubeChannelResource> {
    const query = source.query ?? source.profile_url ?? source.label;
    const channelId = query.match(/(?:channel\/)(UC[\w-]+)/)?.[1] ?? (query.startsWith('UC') ? query : null);

    if (channelId) {
      const response = await this.fetchJSON<{ items?: YouTubeChannelResource[] }>(
        'https://www.googleapis.com/youtube/v3/channels',
        { part: 'snippet,statistics,contentDetails', id: channelId }
      );
      const channel = response.items?.[0];
      if (channel) return channel;
    }

    const forHandle = query.match(/@[\w.-]+/)?.[0] ?? (query.startsWith('@') ? query : `@${query}`);
    const handleResponse = await this.fetchJSON<{ items?: YouTubeChannelResource[] }>(
      'https://www.googleapis.com/youtube/v3/channels',
      { part: 'snippet,statistics,contentDetails', forHandle }
    );
    const handleChannel = handleResponse.items?.[0];
    if (handleChannel) return handleChannel;

    const searchResponse = await this.fetchJSON<{ items?: Array<{ snippet?: { channelId?: string } }> }>(
      'https://www.googleapis.com/youtube/v3/search',
      { part: 'snippet', q: query, type: 'channel', maxResults: '1' }
    );
    const foundChannelId = searchResponse.items?.[0]?.snippet?.channelId;
    if (!foundChannelId) throw new Error(`No YouTube channel found for ${query}`);

    const channelResponse = await this.fetchJSON<{ items?: YouTubeChannelResource[] }>(
      'https://www.googleapis.com/youtube/v3/channels',
      { part: 'snippet,statistics,contentDetails', id: foundChannelId }
    );
    const channel = channelResponse.items?.[0];
    if (!channel) throw new Error(`No YouTube channel details found for ${query}`);
    return channel;
  }

  private async fetchJSON<T>(url: string, params: Record<string, string>): Promise<T> {
    const search = new URLSearchParams({ ...params, key: config.youtubeApiKey });
    const response = await fetch(`${url}?${search.toString()}`);
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`YouTube API ${response.status}: ${body.slice(0, 300)}`);
    }
    return await response.json() as T;
  }
}
