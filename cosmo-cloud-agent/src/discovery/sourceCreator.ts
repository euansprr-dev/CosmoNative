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

function handleFromProfileUrl(profileUrl?: string): string | null {
  if (!profileUrl) return null;

  try {
    const url = new URL(profileUrl);
    const host = url.hostname.replace(/^www\./i, '').toLowerCase();
    const firstPathSegment = url.pathname.split('/').filter(Boolean)[0];

    if (host.endsWith('substack.com') && host !== 'substack.com') {
      return cleanHandle(host.replace(/\.substack\.com$/i, ''));
    }

    if (firstPathSegment) return cleanHandle(firstPathSegment);
  } catch {
    return cleanHandle(profileUrl);
  }

  return null;
}

export function creatorInputFromSourceRequest(body: SourceCreatorRequest): DiscoveryCreatorInput | null {
  const kind = body.kind ?? 'tracked_creator';
  if (kind !== 'tracked_creator' && kind !== 'curated_creator') return null;
  if (!body.platform) return null;

  const handle = cleanHandle(body.query ?? body.label ?? handleFromProfileUrl(body.profileUrl) ?? '');
  if (!handle) return null;

  return {
    platform: body.platform,
    handle,
    displayName: body.label ?? handle,
    profileUrl: body.profileUrl,
    nicheTags: body.nicheTags ?? [],
    sourceTags: ['discovery_source'],
  };
}
