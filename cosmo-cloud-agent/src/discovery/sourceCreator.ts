import type { DiscoveryCreatorInput, SocialPlatform, SocialSourceKind } from './types';

export interface SourceCreatorRequest {
  kind?: SocialSourceKind;
  platform?: SocialPlatform;
  label?: string;
  query?: string;
  profileUrl?: string;
  nicheTags?: string[];
}

function cleanHandle(value: string): string {
  return value
    .replace(/^@/, '')
    .replace(/^https?:\/\//i, '')
    .replace(/^www\./i, '')
    .split(/[/?#]/)[0]
    .trim();
}

const instagramReservedSegments = new Set([
  'p',
  'reel',
  'reels',
  'tv',
  'stories',
  'explore',
  'accounts',
  'direct',
  'about',
  'privacy',
  'terms',
  'developer',
  'web',
]);

function handleFromProfileUrl(profileUrl?: string, platform?: SocialPlatform): string | null {
  if (!profileUrl) return null;

  try {
    const url = new URL(profileUrl);
    const host = url.hostname.replace(/^www\./i, '').toLowerCase();
    const firstPathSegment = url.pathname.split('/').filter(Boolean)[0];

    if (host.endsWith('substack.com') && host !== 'substack.com') {
      return cleanHandle(host.replace(/\.substack\.com$/i, ''));
    }

    if (!firstPathSegment) return null;
    if ((platform === 'instagram' || host === 'instagram.com') && instagramReservedSegments.has(firstPathSegment.toLowerCase())) {
      return null;
    }

    return cleanHandle(firstPathSegment);
  } catch {
    return cleanHandle(profileUrl);
  }

  return null;
}

export function creatorInputFromSourceRequest(body: SourceCreatorRequest): DiscoveryCreatorInput | null {
  const kind = body.kind ?? 'tracked_creator';
  if (kind !== 'tracked_creator' && kind !== 'curated_creator') return null;
  if (!body.platform) return null;

  const profileHandle = handleFromProfileUrl(body.profileUrl, body.platform);
  const handle = profileHandle ?? cleanHandle(body.query ?? body.label ?? '');
  if (!handle) return null;
  if (body.platform === 'instagram' && instagramReservedSegments.has(handle.toLowerCase())) return null;

  return {
    platform: body.platform,
    handle,
    displayName: body.label ?? handle,
    profileUrl: body.profileUrl,
    nicheTags: body.nicheTags ?? [],
    sourceTags: ['discovery_source'],
  };
}
