import { config } from '../../config';
import type { SocialSourceRow } from '../types';
import type { DiscoveryProvider, DiscoveryRefreshResult } from './provider';
import { DiscoveryProviderNotConfiguredError } from './provider';
import { managedSocialRecordToPost } from './managedSocial';

interface ApifyRunResponse {
  data?: {
    defaultDatasetId?: string;
  };
}

export class ApifyInstagramDiscoveryProvider implements DiscoveryProvider {
  readonly id = 'apify-instagram';
  readonly platforms = ['instagram'] as const;

  isConfigured(): boolean {
    return config.apifyApiKey.length > 0;
  }

  canRefresh(source: SocialSourceRow): boolean {
    return source.platform === 'instagram';
  }

  async refreshSource(source: SocialSourceRow): Promise<DiscoveryRefreshResult> {
    if (!this.isConfigured()) {
      throw new DiscoveryProviderNotConfiguredError(this.id, 'APIFY_API_KEY');
    }

    const directUrls = [source.profile_url ?? source.query ?? source.label].filter(Boolean);
    const runResponse = await fetch(
      `https://api.apify.com/v2/acts/apify~instagram-scraper/run-sync?token=${encodeURIComponent(config.apifyApiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          directUrls,
          resultsType: 'posts',
          resultsLimit: 24,
          addParentData: true,
        }),
      }
    );

    if (!runResponse.ok) {
      const body = await runResponse.text();
      throw new Error(`Apify Instagram ${runResponse.status}: ${body.slice(0, 300)}`);
    }

    const run = await runResponse.json() as ApifyRunResponse;
    const datasetId = run.data?.defaultDatasetId;
    if (!datasetId) return { provider: this.id, source, posts: [] };

    const datasetResponse = await fetch(
      `https://api.apify.com/v2/datasets/${datasetId}/items?token=${encodeURIComponent(config.apifyApiKey)}`
    );
    if (!datasetResponse.ok) {
      const body = await datasetResponse.text();
      throw new Error(`Apify dataset ${datasetResponse.status}: ${body.slice(0, 300)}`);
    }

    const items = await datasetResponse.json() as Array<Record<string, unknown>>;
    return {
      provider: this.id,
      source,
      posts: items.map(item => managedSocialRecordToPost('instagram', this.id, item, source)),
    };
  }
}
