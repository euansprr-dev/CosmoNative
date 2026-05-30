import assert from 'node:assert/strict';
import { config } from '../src/config';
import {
  ApifyInstagramDiscoveryProvider,
  apifyInstagramInputForSource,
  enrichInstagramRecord,
  instagramHandle,
} from '../src/discovery/providers/apifyInstagram';
import type { SocialSourceRow } from '../src/discovery/types';

function source(overrides: Partial<SocialSourceRow>): SocialSourceRow {
  return {
    uuid: 'source-1',
    user_id: 'user-1',
    kind: 'tracked_creator',
    platform: 'instagram',
    label: 'theandrewlamb',
    query: 'theandrewlamb',
    profile_url: null,
    creator_uuid: null,
    niche_tags: [],
    priority: 50,
    cadence_minutes: 1440,
    status: 'active',
    last_run_at: null,
    next_run_at: null,
    last_error: null,
    last_successful_run_at: null,
    last_successful_posted_at: null,
    refresh_cursor: null,
    created_at: '2026-05-30T00:00:00.000Z',
    updated_at: '2026-05-30T00:00:00.000Z',
    ...overrides,
  };
}

const provider = new ApifyInstagramDiscoveryProvider();
assert.equal(provider.isConfigured({ providerKeys: { apifyApiKey: 'apify-token' } }), true);

assert.equal(instagramHandle(source({
  profile_url: 'https://www.instagram.com/theandrewlamb/',
})), 'theandrewlamb');

assert.equal(instagramHandle(source({
  query: '@theandrewlamb',
})), 'theandrewlamb');

assert.deepEqual(apifyInstagramInputForSource(source({
  profile_url: 'https://www.instagram.com/theandrewlamb/',
})), {
  username: ['theandrewlamb'],
  resultsLimit: config.apifyInstagramPostLimit,
  dataDetailLevel: 'detailedData',
});

assert.deepEqual(apifyInstagramInputForSource(source({
  profile_url: 'https://www.instagram.com/theandrewlamb/',
  last_successful_posted_at: '2026-05-29T12:00:00.000Z',
})), {
  username: ['theandrewlamb'],
  resultsLimit: 50,
  dataDetailLevel: 'detailedData',
  onlyPostsNewerThan: '2026-05-26T12:00:00.000Z',
  skipPinnedPosts: true,
});

const enriched = enrichInstagramRecord(
  {
    shortCode: 'abc123',
    ownerUsername: 'collab_account',
    ownerFullName: 'Collaborator',
    ownerFollowersCount: 12,
    url: 'https://www.instagram.com/p/abc123/',
  },
  {
    username: 'theandrewlamb',
    fullName: 'Andrew Lamb',
    followersCount: 257_900,
    profilePicUrl: 'https://example.com/avatar.jpg',
  },
  'theandrewlamb',
  source({ profile_url: 'https://www.instagram.com/theandrewlamb/' })
);

assert.equal(enriched.ownerUsername, 'theandrewlamb');
assert.equal(enriched.ownerFullName, 'Andrew Lamb');
assert.equal(enriched.ownerFollowersCount, 257_900);
assert.equal(enriched.ownerProfilePicUrl, 'https://example.com/avatar.jpg');

console.log('discovery.apify.test.ts passed');
