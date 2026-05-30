import express from 'express';
import { randomUUID } from 'node:crypto';
import { isDiscoveryWriteAuthorized, discoveryProviderAvailability } from '../discovery/config';
import {
  createSource,
  fetchCreators,
  fetchDiscoveryFeed,
  saveDiscoveredPostToSwipe,
  upsertCreator,
} from '../discovery/db';
import { refreshDiscoverySource, refreshDueDiscoverySources } from '../discovery/jobs';
import { creatorInputFromSourceRequest } from '../discovery/sourceCreator';
import { supabase, userId } from '../db/client';
import type { SocialPlatform, SocialSourceKind, SocialSourceRow } from '../discovery/types';

export const discoveryRouter = express.Router();

const discoveryBuild = 'discovery-source-graph-2026-05-30T1118';

discoveryRouter.use((req, res, next) => {
  const startedAt = Date.now();
  const requestId = randomUUID();
  res.locals.discoveryRequestId = requestId;
  console.log(`[discovery:${requestId}] ${req.method} ${req.originalUrl} start`);
  res.on('finish', () => {
    console.log(`[discovery:${requestId}] ${req.method} ${req.originalUrl} ${res.statusCode} ${Date.now() - startedAt}ms`);
  });
  next();
});

function parsePlatforms(value: unknown): SocialPlatform[] | undefined {
  if (typeof value !== 'string' || !value.trim()) return undefined;
  const platforms = value.split(',').map(item => item.trim()).filter(Boolean);
  return platforms as SocialPlatform[];
}

function postedAfter(window: unknown): string | undefined {
  if (typeof window !== 'string') return undefined;
  const days: Record<string, number> = {
    week: 7,
    month: 30,
    '3months': 90,
    year: 365,
  };
  const count = days[window];
  if (!count) return undefined;
  return new Date(Date.now() - count * 24 * 60 * 60_000).toISOString();
}

function requireDiscoveryAccess(req: express.Request, res: express.Response): boolean {
  if (isDiscoveryWriteAuthorized(req.header('authorization'))) return true;
  res.status(401).json({ error: 'Unauthorized discovery request' });
  return false;
}

discoveryRouter.get('/feed', async (req, res) => {
  if (!requireDiscoveryAccess(req, res)) return;
  const posts = await fetchDiscoveryFeed({
    platforms: parsePlatforms(req.query.platforms),
    minOutlier: typeof req.query.minOutlier === 'string' ? Number(req.query.minOutlier) : undefined,
    postedAfter: postedAfter(req.query.window),
    creatorUuid: typeof req.query.creatorUuid === 'string' ? req.query.creatorUuid : undefined,
    query: typeof req.query.q === 'string' ? req.query.q : undefined,
    limit: typeof req.query.limit === 'string' ? Number(req.query.limit) : undefined,
  });
  res.json({ posts });
});

discoveryRouter.get('/creators', async (req, res) => {
  if (!requireDiscoveryAccess(req, res)) return;
  const limit = typeof req.query.limit === 'string' ? Number(req.query.limit) : 200;
  const creators = await fetchCreators(limit);
  res.json({ creators });
});

discoveryRouter.post('/sources', async (req, res) => {
  if (!requireDiscoveryAccess(req, res)) return;
  const body = req.body as {
    kind?: SocialSourceKind;
    platform?: SocialPlatform;
    label?: string;
    query?: string;
    profileUrl?: string;
    nicheTags?: string[];
    priority?: number;
    cadenceMinutes?: number;
  };

  if (!body.label && !body.profileUrl && !body.query) {
    res.status(400).json({ error: 'label, profileUrl, or query is required' });
    return;
  }

  console.log(`[discovery:${res.locals.discoveryRequestId}] create source`, {
    build: discoveryBuild,
    kind: body.kind ?? 'tracked_creator',
    platform: body.platform ?? null,
    label: body.label ?? null,
    hasProfileUrl: Boolean(body.profileUrl),
    hasQuery: Boolean(body.query),
  });

  const creatorInput = creatorInputFromSourceRequest(body);
  const creator = creatorInput ? await upsertCreator(creatorInput) : null;

  const source = await createSource({
    kind: body.kind ?? 'tracked_creator',
    platform: body.platform ?? null,
    label: body.label ?? body.profileUrl ?? body.query ?? 'Untitled source',
    query: body.query ?? null,
    profileUrl: body.profileUrl ?? null,
    creatorUuid: creator?.uuid,
    nicheTags: body.nicheTags ?? [],
    priority: body.priority,
    cadenceMinutes: body.cadenceMinutes,
  });

  console.log(`[discovery:${res.locals.discoveryRequestId}] source created`, {
    sourceUuid: source.uuid,
    creatorUuid: creator?.uuid ?? null,
    platform: source.platform,
  });

  res.status(201).json({ build: discoveryBuild, source, creator });
});

discoveryRouter.post('/sources/:uuid/refresh', async (req, res) => {
  if (!requireDiscoveryAccess(req, res)) return;
  const { data, error } = await supabase
    .from('social_sources')
    .select('*')
    .eq('uuid', req.params.uuid)
    .eq('user_id', userId)
    .single();

  if (error || !data) {
    res.status(404).json({ error: 'Source not found' });
    return;
  }

  console.log(`[discovery:${res.locals.discoveryRequestId}] refresh source`, {
    sourceUuid: req.params.uuid,
    platform: data.platform,
    kind: data.kind,
    hasProfileUrl: Boolean(data.profile_url),
    query: data.query,
  });

  const result = await refreshDiscoverySource(data as SocialSourceRow);
  res.json(result);
});

discoveryRouter.post('/refresh-due', async (req, res) => {
  if (!requireDiscoveryAccess(req, res)) return;
  const limit = typeof req.body?.limit === 'number' ? req.body.limit : 25;
  const result = await refreshDueDiscoverySources(limit);
  res.json(result);
});

discoveryRouter.post('/posts/:uuid/save', async (req, res) => {
  if (!requireDiscoveryAccess(req, res)) return;
  const atomUuid = await saveDiscoveredPostToSwipe(req.params.uuid, req.body?.boardId);
  res.json({ atomUuid });
});

discoveryRouter.get('/health', async (_req, res) => {
  if (!requireDiscoveryAccess(_req, res)) return;
  const [{ count: postCount }, { data: newest }, { data: runs }] = await Promise.all([
    supabase
      .from('social_discovered_posts')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId),
    supabase
      .from('social_discovered_posts')
      .select('posted_at,last_refreshed_at')
      .eq('user_id', userId)
      .order('posted_at', { ascending: false, nullsFirst: false })
      .limit(1),
    supabase
      .from('social_discovery_runs')
      .select('*')
      .eq('user_id', userId)
      .order('started_at', { ascending: false })
      .limit(10),
  ]);

  res.json({
    build: discoveryBuild,
    providers: discoveryProviderAvailability(),
    postCount: postCount ?? 0,
    newestPost: newest?.[0] ?? null,
    recentRuns: runs ?? [],
  });
});
