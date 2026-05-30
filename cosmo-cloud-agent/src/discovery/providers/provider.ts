import type { DiscoveredPostInput, SocialPlatform, SocialSourceRow } from '../types';

export interface DiscoveryRefreshResult {
  provider: string;
  source: SocialSourceRow;
  posts: DiscoveredPostInput[];
  adjacentCreators?: Array<{
    platform: SocialPlatform;
    handle: string;
    profileUrl?: string;
    confidence: number;
  }>;
}

export interface DiscoveryProviderContext {
  providerKeys?: {
    apifyApiKey?: string;
  };
}

export interface DiscoveryProvider {
  readonly id: string;
  readonly platforms: readonly SocialPlatform[];

  isConfigured(context?: DiscoveryProviderContext): boolean;
  canRefresh(source: SocialSourceRow): boolean;
  refreshSource(source: SocialSourceRow, context?: DiscoveryProviderContext): Promise<DiscoveryRefreshResult>;
}

export class DiscoveryProviderNotConfiguredError extends Error {
  constructor(provider: string, envKey: string) {
    super(`${provider} is not configured. Missing ${envKey}.`);
    this.name = 'DiscoveryProviderNotConfiguredError';
  }
}
