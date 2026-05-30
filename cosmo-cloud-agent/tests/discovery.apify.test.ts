import assert from 'node:assert/strict';
import { config } from '../src/config';
import {
  ApifyInstagramDiscoveryProvider,
  apifyInstagramInputForSource,
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

console.log('discovery.apify.test.ts passed');
