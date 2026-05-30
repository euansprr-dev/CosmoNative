import assert from 'node:assert/strict';
import {
  brightDataInputForSource,
  brightDataDatasetForSource,
} from '../src/discovery/providers/managedSocial';
import type { SocialSourceRow } from '../src/discovery/types';

function source(overrides: Partial<SocialSourceRow>): SocialSourceRow {
  return {
    uuid: 'source-1',
    user_id: 'user-1',
    kind: 'tracked_creator',
    platform: 'instagram',
    label: 'cats_of_world_',
    query: 'cats_of_world_',
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

const endpointConfig = {
  instagram: {
    profilesByUrl: 'gd_instagram_profile_url',
    profilesByUsername: 'gd_instagram_username',
    reelsByUrl: 'gd_instagram_reel_url',
    postsByUrl: 'gd_instagram_post_url',
  },
  tiktok: {
    profilesByUrl: 'gd_tiktok_profile_url',
    postsByUrl: 'gd_tiktok_post_url',
  },
  linkedin: {
    profilesByUrl: 'gd_linkedin_profile_url',
    postsByUrl: 'gd_linkedin_post_url',
  },
  x: {
    profilesByUrl: 'gd_x_profile_url',
    postsByUrl: 'gd_x_post_url',
  },
};

const instagramProfileURL = source({
  profile_url: 'https://www.instagram.com/cats_of_world_/',
});
assert.equal(brightDataDatasetForSource(instagramProfileURL, endpointConfig), 'gd_instagram_reel_url');
assert.deepEqual(brightDataInputForSource(instagramProfileURL), [
  { url: 'https://www.instagram.com/cats_of_world_/' },
]);

const instagramUsername = source({
  profile_url: null,
  query: 'cats_of_world_',
});
assert.equal(brightDataDatasetForSource(instagramUsername, endpointConfig), 'gd_instagram_username');
assert.deepEqual(brightDataInputForSource(instagramUsername), [
  { username: 'cats_of_world_' },
]);

const instagramReel = source({
  kind: 'list',
  profile_url: 'https://www.instagram.com/reel/ABC123/',
});
assert.equal(brightDataDatasetForSource(instagramReel, endpointConfig), 'gd_instagram_reel_url');

const tiktokPost = source({
  platform: 'tiktok',
  profile_url: 'https://www.tiktok.com/@creator/video/123',
});
assert.equal(brightDataDatasetForSource(tiktokPost, endpointConfig), 'gd_tiktok_post_url');

console.log('discovery.brightdata.test.ts passed');
