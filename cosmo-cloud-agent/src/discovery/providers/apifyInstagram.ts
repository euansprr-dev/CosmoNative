import { config } from '../../config';
import type { SocialSourceRow } from '../types';
import type { DiscoveryProvider, DiscoveryProviderContext, DiscoveryRefreshResult } from './provider';
import { DiscoveryProviderNotConfiguredError } from './provider';
import { managedSocialRecordToPost } from './managedSocial';

interface ApifyRunResponse {
  data?: {
    id?: string;
    defaultDatasetId?: string;
    status?: string;
    statusMessage?: string;
  };
}

export function apifyInstagramInputForSource(source: SocialSourceRow): Record<string, unknown> {
  const handle = instagramHandle(source);
  if (!handle) {
    throw new Error('Instagram creator source is missing a handle.');
  }

  return {
    username: [handle],
    resultsLimit: config.apifyInstagramPostLimit,
    dataDetailLevel: 'detailedData',
  };
}

export class ApifyInstagramDiscoveryProvider implements DiscoveryProvider {
  readonly id = 'apify-instagram';
  readonly platforms = ['instagram'] as const;
  private readonly profileActorId = 'apify~instagram-profile-scraper';
  private readonly postActorId = 'apify~instagram-post-scraper';

  isConfigured(context?: DiscoveryProviderContext): boolean {
    return this.apiKey(context).length > 0;
  }

  canRefresh(source: SocialSourceRow): boolean {
    return source.platform === 'instagram';
  }

  async refreshSource(source: SocialSourceRow, context?: DiscoveryProviderContext): Promise<DiscoveryRefreshResult> {
    const apiKey = this.apiKey(context);
    if (!apiKey) {
      throw new DiscoveryProviderNotConfiguredError(this.id, 'APIFY_API_KEY');
    }

    const input = apifyInstagramInputForSource(source);
    const handle = ((input.username as string[]) ?? [source.label])[0];

    console.log('[discovery-apify] trigger', {
      sourceUuid: source.uuid,
      actorId: this.postActorId,
      handle,
      resultsLimit: config.apifyInstagramPostLimit,
      tokenSource: context?.providerKeys?.apifyApiKey ? 'request' : 'environment',
    });

    const postRun = await runActor(this.postActorId, input, apiKey);
    await waitForRun(postRun.runId, apiKey);

    console.log('[discovery-apify] dataset ready', {
      sourceUuid: source.uuid,
      runId: postRun.runId,
      datasetId: postRun.datasetId,
    });

    const items = await fetchDatasetItems(postRun.datasetId, apiKey);
    const profile = await this.fetchProfile(handle, apiKey, source.uuid);
    const enrichedItems = items.map(item => enrichInstagramRecord(item, profile, handle, source));
    console.log('[discovery-apify] dataset fetched', {
      sourceUuid: source.uuid,
      itemCount: enrichedItems.length,
      hasProfile: Boolean(profile),
    });

    return {
      provider: this.id,
      source,
      posts: enrichedItems.map(item => managedSocialRecordToPost('instagram', this.id, item, source)),
    };
  }

  private apiKey(context?: DiscoveryProviderContext): string {
    return context?.providerKeys?.apifyApiKey || config.apifyApiKey;
  }

  private async fetchProfile(
    handle: string,
    apiKey: string,
    sourceUuid: string
  ): Promise<Record<string, unknown> | null> {
    try {
      const run = await runActor(this.profileActorId, {
        usernames: [handle],
        resultsLimit: 1,
      }, apiKey);
      await waitForRun(run.runId, apiKey);
      const profiles = await fetchDatasetItems(run.datasetId, apiKey);
      return profiles[0] ?? null;
    } catch (error) {
      console.warn('[discovery-apify] profile enrichment failed', {
        sourceUuid,
        handle,
        error: error instanceof Error ? error.message : String(error),
      });
      return null;
    }
  }
}

export function instagramHandle(source: SocialSourceRow): string {
  const value = source.profile_url ?? source.query ?? source.label;
  if (/^https?:\/\//i.test(value)) {
    try {
      const url = new URL(value);
      const firstSegment = url.pathname.split('/').filter(Boolean)[0];
      if (firstSegment && !['p', 'reel', 'reels', 'stories', 'explore', 'accounts'].includes(firstSegment.toLowerCase())) {
        return firstSegment.replace(/^@/, '');
      }
    } catch {
      // Fall through to string cleanup.
    }
  }

  return value
    .replace(/^@/, '')
    .replace(/^https?:\/\//i, '')
    .replace(/^www\./i, '')
    .replace(/^instagram\.com\//i, '')
    .split(/[/?#]/)[0]
    .trim();
}

async function waitForRun(runId: string, apiKey: string): Promise<void> {
  const statusUrl = `https://api.apify.com/v2/actor-runs/${encodeURIComponent(runId)}?token=${encodeURIComponent(apiKey)}`;
  for (let attempt = 0; attempt < 160; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 3_000));
    const response = await fetch(statusUrl);
    if (!response.ok) continue;

    const payload = await response.json() as ApifyRunResponse;
    const status = payload.data?.status;
    if (status === 'SUCCEEDED') return;
    if (status === 'FAILED' || status === 'ABORTED' || status === 'TIMED-OUT') {
      throw new Error(payload.data?.statusMessage ?? `Apify Instagram run ${status.toLowerCase()}`);
    }
  }

  throw new Error('Apify Instagram run timed out while waiting for posts.');
}

async function runActor(
  actorId: string,
  input: Record<string, unknown>,
  apiKey: string
): Promise<{ runId: string; datasetId: string }> {
  const runResponse = await fetch(
    `https://api.apify.com/v2/acts/${actorId}/runs?token=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(input),
    }
  );

  if (!runResponse.ok) {
    const body = await runResponse.text();
    throw new Error(`Apify ${actorId} ${runResponse.status}: ${body.slice(0, 300)}`);
  }

  const run = await runResponse.json() as ApifyRunResponse;
  const runId = run.data?.id;
  const datasetId = run.data?.defaultDatasetId;
  if (!runId || !datasetId) {
    throw new Error(`Apify ${actorId} did not return a run ID and dataset ID.`);
  }

  return { runId, datasetId };
}

async function fetchDatasetItems(datasetId: string, apiKey: string): Promise<Array<Record<string, unknown>>> {
  const datasetResponse = await fetch(
    `https://api.apify.com/v2/datasets/${encodeURIComponent(datasetId)}/items?token=${encodeURIComponent(apiKey)}&format=json&clean=true`
  );
  if (!datasetResponse.ok) {
    const body = await datasetResponse.text();
    throw new Error(`Apify dataset ${datasetResponse.status}: ${body.slice(0, 300)}`);
  }

  return await datasetResponse.json() as Array<Record<string, unknown>>;
}

function stringValue(record: Record<string, unknown>, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return undefined;
}

function numberValue(record: Record<string, unknown>, keys: string[]): number | undefined {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string') {
      const parsed = Number.parseInt(value.replace(/[,_]/g, ''), 10);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return undefined;
}

function enrichInstagramRecord(
  record: Record<string, unknown>,
  profile: Record<string, unknown> | null,
  handle: string,
  source: SocialSourceRow
): Record<string, unknown> {
  if (!profile) {
    return {
      ownerUsername: handle,
      ownerUrl: source.profile_url ?? `https://www.instagram.com/${handle}/`,
      ...record,
    };
  }

  return {
    ownerUsername: stringValue(profile, ['username']) ?? handle,
    ownerFullName: stringValue(profile, ['fullName', 'full_name', 'name']),
    ownerProfilePicUrl: stringValue(profile, ['profilePicUrl', 'profilePicUrlHD', 'profile_pic_url']),
    ownerFollowersCount: numberValue(profile, ['followersCount', 'followedByCount', 'followers', 'follower_count']),
    ownerUrl: source.profile_url ?? `https://www.instagram.com/${handle}/`,
    ...record,
  };
}
