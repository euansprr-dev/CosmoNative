import { normalizeDiscoveredPost } from './normalize';
import { config } from '../config';
import {
  fetchActiveSources,
  fetchDueSources,
  recordDiscoveryRun,
  updateSourceAfterRun,
  upsertDiscoveredPost,
} from './db';
import { ApifyInstagramDiscoveryProvider } from './providers/apifyInstagram';
import { ManagedSocialDiscoveryProvider } from './providers/managedSocial';
import type { DiscoveryProvider, DiscoveryProviderContext } from './providers/provider';
import { SubstackDiscoveryProvider } from './providers/substack';
import { YouTubeDiscoveryProvider } from './providers/youtube';
import type { SocialSourceRow } from './types';

const providers: DiscoveryProvider[] = [
  new YouTubeDiscoveryProvider(),
  new SubstackDiscoveryProvider(),
  new ApifyInstagramDiscoveryProvider(),
  new ManagedSocialDiscoveryProvider(),
];

type RefreshSourceResult = { found: number; upserted: number; provider: string };
const inFlightRefreshes = new Map<string, Promise<RefreshSourceResult>>();

export function discoveryProviders(): DiscoveryProvider[] {
  return providers;
}

function providerFor(source: SocialSourceRow, context?: DiscoveryProviderContext): DiscoveryProvider | null {
  return providers.find(provider => provider.canRefresh(source) && provider.isConfigured(context)) ??
    providers.find(provider => provider.canRefresh(source)) ??
    null;
}

export async function refreshDiscoverySource(
  source: SocialSourceRow,
  context?: DiscoveryProviderContext
): Promise<RefreshSourceResult> {
  const existingRefresh = inFlightRefreshes.get(source.uuid);
  if (existingRefresh) {
    console.log('[discovery-job] refresh already in flight; joining existing run', {
      sourceUuid: source.uuid,
      platform: source.platform,
      label: source.label,
    });
    return existingRefresh;
  }

  const refreshPromise = refreshDiscoverySourceInner(source, context);
  inFlightRefreshes.set(source.uuid, refreshPromise);
  try {
    return await refreshPromise;
  } finally {
    inFlightRefreshes.delete(source.uuid);
  }
}

async function refreshDiscoverySourceInner(
  source: SocialSourceRow,
  context?: DiscoveryProviderContext
): Promise<RefreshSourceResult> {
  const startedAt = new Date().toISOString();
  const provider = providerFor(source, context);

  const recentSkip = recentSuccessfulRefreshSkip(source);
  if (recentSkip) {
    console.log('[discovery-job] skipping recent successful source refresh', {
      sourceUuid: source.uuid,
      platform: source.platform,
      label: source.label,
      lastSuccessfulRunAt: source.last_successful_run_at,
      cooldownMinutes: config.discoveryRefreshCooldownMinutes,
    });
    await recordDiscoveryRun({
      sourceUuid: source.uuid,
      provider: 'cooldown',
      status: 'success',
      startedAt,
      postsFound: 0,
      postsUpserted: 0,
    });
    return { found: 0, upserted: 0, provider: 'cooldown' };
  }

  if (!provider) {
    const message = `No discovery provider can refresh ${source.platform ?? 'unknown'} source ${source.uuid}`;
    await recordDiscoveryRun({ sourceUuid: source.uuid, provider: 'none', status: 'error', startedAt, errorMessage: message });
    await updateSourceAfterRun(source, 'error', message);
    throw new Error(message);
  }

  console.log('[discovery-job] provider selected', {
    sourceUuid: source.uuid,
    platform: source.platform,
    kind: source.kind,
    provider: provider.id,
    configured: provider.isConfigured(context),
  });

  try {
    const result = await provider.refreshSource(source, context);
    let upserted = 0;
    let latestPostedAt: string | null = source.last_successful_posted_at ?? null;
    for (const input of result.posts) {
      const normalized = normalizeDiscoveredPost(input);
      await upsertDiscoveredPost(normalized);
      upserted += 1;
      if (normalized.posted_at && (!latestPostedAt || normalized.posted_at > latestPostedAt)) {
        latestPostedAt = normalized.posted_at;
      }
    }
    await recordDiscoveryRun({
      sourceUuid: source.uuid,
      provider: result.provider,
      status: 'success',
      startedAt,
      postsFound: result.posts.length,
      postsUpserted: upserted,
    });
    await updateSourceAfterRun(source, 'active', undefined, latestPostedAt);
    return { found: result.posts.length, upserted, provider: result.provider };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const rateLimited = /rate|429/i.test(message);
    await recordDiscoveryRun({
      sourceUuid: source.uuid,
      provider: provider.id,
      status: rateLimited ? 'rate_limited' : 'error',
      startedAt,
      errorMessage: message,
    });
    await updateSourceAfterRun(source, rateLimited ? 'rate_limited' : 'error', message);
    throw error;
  }
}

function recentSuccessfulRefreshSkip(source: SocialSourceRow): boolean {
  if (!source.last_successful_run_at) return false;
  const lastRun = new Date(source.last_successful_run_at).getTime();
  if (Number.isNaN(lastRun)) return false;
  const cooldownMs = Math.max(1, config.discoveryRefreshCooldownMinutes) * 60_000;
  return Date.now() - lastRun < cooldownMs;
}

export async function refreshDueDiscoverySources(
  limit = 25,
  context?: DiscoveryProviderContext,
  force = false
): Promise<{ sources: number; posts: number }> {
  const effectiveForce = force && config.discoveryAllowForceRefresh;
  const safeLimit = Math.max(1, Math.min(limit, effectiveForce ? 25 : 10));
  const sources = effectiveForce ? await fetchActiveSources(safeLimit) : await fetchDueSources(safeLimit);
  let posts = 0;
  for (const source of sources) {
    try {
      const result = await refreshDiscoverySource(source, context);
      posts += result.upserted;
    } catch (error) {
      console.error(`Discovery refresh failed for ${source.uuid}:`, error);
    }
  }
  return { sources: sources.length, posts };
}
