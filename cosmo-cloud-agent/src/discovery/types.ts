export type SocialPlatform = 'youtube' | 'substack' | 'instagram' | 'tiktok' | 'linkedin' | 'x';

export type SocialSourceKind =
  | 'tracked_creator'
  | 'curated_creator'
  | 'publication_feed'
  | 'youtube_channel'
  | 'keyword'
  | 'hashtag'
  | 'list'
  | 'adjacent_creator';

export type SocialSourceStatus = 'active' | 'paused' | 'error' | 'rate_limited';

export type SocialMediaType =
  | 'video'
  | 'short_video'
  | 'image'
  | 'carousel'
  | 'text'
  | 'article'
  | 'unknown';

export type SocialOutlierGrade = 'S' | 'A' | 'B' | 'C' | 'insufficient_data';

export interface DiscoveryCreatorInput {
  platform: SocialPlatform;
  platformCreatorId?: string;
  handle: string;
  displayName?: string;
  bio?: string;
  avatarUrl?: string;
  profileUrl?: string;
  followerCount?: number;
  followingCount?: number;
  postCount?: number;
  language?: string;
  nicheTags?: string[];
  sourceTags?: string[];
}

export interface DiscoveryMediaInput {
  kind: 'image' | 'video' | 'thumbnail' | 'document';
  url: string;
  width?: number;
  height?: number;
  durationSeconds?: number;
}

export interface DiscoveryMetricsInput {
  views?: number;
  likes?: number;
  comments?: number;
  reposts?: number;
  shares?: number;
  saves?: number;
}

export interface DiscoveredPostInput {
  platform: SocialPlatform;
  provider: string;
  platformPostId: string;
  canonicalUrl: string;
  creator: DiscoveryCreatorInput;
  sourceUuid?: string;
  title?: string;
  caption?: string;
  transcript?: string;
  language?: string;
  postedAt?: string;
  mediaType?: SocialMediaType;
  mediaUrls?: DiscoveryMediaInput[];
  thumbnailUrl?: string;
  durationSeconds?: number;
  metrics?: DiscoveryMetricsInput;
  nicheTags?: string[];
  formatTags?: string[];
  hookTags?: string[];
  rawPayload?: Record<string, unknown>;
}

export interface NormalizedDiscoveredPost {
  platform: SocialPlatform;
  provider: string;
  platform_post_id: string;
  canonical_url: string;
  creator: DiscoveryCreatorInput;
  source_uuid: string | null;
  title: string | null;
  caption: string | null;
  transcript: string | null;
  language: string | null;
  posted_at: string | null;
  media_type: SocialMediaType;
  media_urls: DiscoveryMediaInput[];
  thumbnail_url: string | null;
  duration_seconds: number | null;
  view_count: number | null;
  like_count: number | null;
  comment_count: number | null;
  repost_count: number | null;
  share_count: number | null;
  engagement_rate: number | null;
  outlier_score: number | null;
  outlier_grade: SocialOutlierGrade;
  velocity_score: number | null;
  ranking_score: number | null;
  niche_tags: string[];
  format_tags: string[];
  hook_tags: string[];
  raw_payload: Record<string, unknown>;
}

export interface SocialCreatorRow {
  uuid: string;
  user_id: string;
  platform: SocialPlatform;
  platform_creator_id: string | null;
  handle: string;
  display_name: string | null;
  bio: string | null;
  avatar_url: string | null;
  profile_url: string | null;
  follower_count: number | null;
  following_count: number | null;
  post_count: number | null;
  language: string | null;
  niche_tags: string[];
  source_tags: string[];
  last_seen_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface SocialSourceRow {
  uuid: string;
  user_id: string;
  kind: SocialSourceKind;
  platform: SocialPlatform | null;
  label: string;
  query: string | null;
  profile_url: string | null;
  creator_uuid: string | null;
  niche_tags: string[];
  priority: number;
  cadence_minutes: number;
  status: SocialSourceStatus;
  last_run_at: string | null;
  next_run_at: string | null;
  last_error: string | null;
  last_successful_run_at: string | null;
  last_successful_posted_at: string | null;
  refresh_cursor: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
}

export interface SocialDiscoveredPostRow {
  uuid: string;
  user_id: string;
  platform: SocialPlatform;
  platform_post_id: string;
  creator_uuid: string | null;
  source_uuid: string | null;
  canonical_url: string;
  title: string | null;
  caption: string | null;
  transcript: string | null;
  language: string | null;
  posted_at: string | null;
  media_type: SocialMediaType;
  media_urls: DiscoveryMediaInput[];
  thumbnail_url: string | null;
  duration_seconds: number | null;
  view_count: number | null;
  like_count: number | null;
  comment_count: number | null;
  repost_count: number | null;
  share_count: number | null;
  engagement_rate: number | null;
  outlier_score: number | null;
  outlier_grade: SocialOutlierGrade;
  velocity_score: number | null;
  ranking_score: number | null;
  niche_tags: string[];
  format_tags: string[];
  hook_tags: string[];
  raw_payload: Record<string, unknown>;
  first_seen_at: string;
  last_refreshed_at: string | null;
  saved_atom_uuid: string | null;
  created_at: string;
  updated_at: string;
}
