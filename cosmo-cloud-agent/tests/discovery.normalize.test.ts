import assert from 'node:assert/strict';
import { normalizeDiscoveredPost } from '../src/discovery/normalize';
import { scorePost } from '../src/discovery/scoring';
import type { DiscoveredPostInput } from '../src/discovery/types';

function post(overrides: Partial<DiscoveredPostInput> = {}): DiscoveredPostInput {
  return {
    platform: 'youtube',
    provider: 'fixture',
    platformPostId: 'video-1',
    canonicalUrl: 'https://www.youtube.com/watch?v=video-1',
    creator: {
      platform: 'youtube',
      handle: 'creator',
      displayName: 'Creator',
      profileUrl: 'https://www.youtube.com/@creator',
      followerCount: 100_000,
    },
    title: 'A useful video',
    caption: 'Caption',
    postedAt: '2026-05-28T12:00:00.000Z',
    mediaType: 'video',
    mediaUrls: [{ kind: 'thumbnail', url: 'https://i.ytimg.com/vi/video-1/hqdefault.jpg' }],
    thumbnailUrl: 'https://i.ytimg.com/vi/video-1/hqdefault.jpg',
    metrics: {
      views: 50_000,
      likes: 5_000,
      comments: 250,
      reposts: 20,
      shares: 100,
    },
    rawPayload: { id: 'video-1' },
    ...overrides,
  };
}

function testNormalizesStablePostShape(): void {
  const normalized = normalizeDiscoveredPost(post());

  assert.equal(normalized.platform, 'youtube');
  assert.equal(normalized.platform_post_id, 'video-1');
  assert.equal(normalized.canonical_url, 'https://www.youtube.com/watch?v=video-1');
  assert.equal(normalized.creator.handle, 'creator');
  assert.equal(normalized.view_count, 50_000);
  assert.equal(normalized.like_count, 5_000);
  assert.equal(normalized.thumbnail_url, 'https://i.ytimg.com/vi/video-1/hqdefault.jpg');
  assert.equal(normalized.media_urls.length, 1);
}

function testScoringUsesMedianBaselineAndFreshness(): void {
  const scored = scorePost({
    post: normalizeDiscoveredPost(post({ metrics: { views: 120_000, likes: 8_000 } })),
    creatorRecentReach: [10_000, 12_000, 9_000, 11_000, 10_500, 10_100],
    now: new Date('2026-05-29T12:00:00.000Z'),
  });

  assert.equal(scored.outlierScore, 11.65);
  assert.equal(scored.outlierGrade, 'A');
  assert.ok(scored.velocityScore > 0);
  assert.ok(scored.rankingScore > scored.velocityScore);
}

function testScoringMarksInsufficientBaseline(): void {
  const scored = scorePost({
    post: normalizeDiscoveredPost(post({ metrics: { views: 120_000 } })),
    creatorRecentReach: [10_000, 12_000, 9_000],
    now: new Date('2026-05-29T12:00:00.000Z'),
  });

  assert.equal(scored.outlierScore, null);
  assert.equal(scored.outlierGrade, 'insufficient_data');
  assert.ok(scored.rankingScore > 0);
}

testNormalizesStablePostShape();
testScoringUsesMedianBaselineAndFreshness();
testScoringMarksInsufficientBaseline();

console.log('discovery.normalize.test.ts passed');
