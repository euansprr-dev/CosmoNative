import { config } from '../config';

export type DiscoveryProviderName =
  | 'youtube'
  | 'substack'
  | 'brightdata'
  | 'apify-instagram'
  | 'x-official';

export interface DiscoveryProviderAvailability {
  name: DiscoveryProviderName;
  configured: boolean;
  platforms: string[];
  reason?: string;
}

export function discoveryProviderAvailability(): DiscoveryProviderAvailability[] {
  return [
    {
      name: 'youtube',
      configured: config.youtubeApiKey.length > 0,
      platforms: ['youtube'],
      reason: config.youtubeApiKey ? undefined : 'Missing YOUTUBE_API_KEY',
    },
    {
      name: 'substack',
      configured: true,
      platforms: ['substack'],
    },
    {
      name: 'brightdata',
      configured: config.brightDataApiKey.length > 0,
      platforms: ['instagram', 'tiktok', 'linkedin', 'x'],
      reason: config.brightDataApiKey ? undefined : 'Missing BRIGHT_DATA_API_KEY',
    },
    {
      name: 'apify-instagram',
      configured: config.apifyApiKey.length > 0,
      platforms: ['instagram'],
      reason: config.apifyApiKey ? undefined : 'Missing APIFY_API_KEY',
    },
    {
      name: 'x-official',
      configured: config.xBearerToken.length > 0,
      platforms: ['x'],
      reason: config.xBearerToken ? undefined : 'Missing X_BEARER_TOKEN',
    },
  ];
}

export function isDiscoveryWriteAuthorized(authHeader: string | undefined): boolean {
  if (!config.discoveryApiKey) return false;
  const token = authHeader?.replace(/^Bearer\s+/i, '').trim();
  return token === config.discoveryApiKey;
}
