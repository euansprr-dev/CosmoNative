import { normalizeDiscoveredPost } from './normalize';
import {
  fetchDueSources,
  recordDiscoveryRun,
  updateSourceAfterRun,
  upsertDiscoveredPost,
} from './db';
import { ApifyInstagramDiscoveryProvider } from './providers/apifyInstagram';
import { ManagedSocialDiscoveryProvider } from './providers/managedSocial';
import type { DiscoveryProvider } from './providers/provider';
import { SubstackDiscoveryProvider } from './providers/substack';
import { YouTubeDiscoveryProvider } from './providers/youtube';
import type { SocialSourceRow } from './types';

const providers: DiscoveryProvider[] = [
  new YouTubeDiscoveryProvider(),
  new SubstackDiscoveryProvider(),
  new ManagedSocialDiscoveryProvider(),
  new ApifyInstagramDiscoveryProvider(),
];

export function discoveryProviders(): DiscoveryProvider[] {
  return providers;
}

function providerFor(source: SocialSourceRow): DiscoveryProvider | null {
  return providers.find(provider => provider.canRefresh(source) && provider.isConfigured()) ??
    providers.find(provider => provider.canRefresh(source)) ??
    null;
}

export async function refreshDiscoverySource(source: SocialSourceRow): Promise<{ found: number; upserted: number; provider: string }> {
  const startedAt = new Date().toISOString();
  const provider = providerFor(source);

  if (!provider) {
    const message = `No discovery provider can refresh ${source.platform ?? 'unknown'} source ${source.uuid}`;
    await recordDiscoveryRun({ sourceUuid: source.uuid, provider: 'none', status: 'error', startedAt, errorMessage: message });
    await updateSourceAfterRun(source, 'error', message);
    throw new Error(message);
  }

  try {
    const result = await provider.refreshSource(source);
    let upserted = 0;
    for (const input of result.posts) {
      await upsertDiscoveredPost(normalizeDiscoveredPost(input));
      upserted += 1;
    }
    await recordDiscoveryRun({
      sourceUuid: source.uuid,
      provider: result.provider,
      status: 'success',
      startedAt,
      postsFound: result.posts.length,
      postsUpserted: upserted,
    });
    await updateSourceAfterRun(source, 'active');
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

export async function refreshDueDiscoverySources(limit = 25): Promise<{ sources: number; posts: number }> {
  const sources = await fetchDueSources(limit);
  let posts = 0;
  for (const source of sources) {
    try {
      const result = await refreshDiscoverySource(source);
      posts += result.upserted;
    } catch (error) {
      console.error(`Discovery refresh failed for ${source.uuid}:`, error);
    }
  }
  return { sources: sources.length, posts };
}
