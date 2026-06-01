import assert from 'node:assert/strict';
import { creatorInputFromSourceRequest } from '../src/discovery/sourceCreator';

const instagramCreator = creatorInputFromSourceRequest({
  kind: 'tracked_creator',
  platform: 'instagram',
  label: 'theandrewlamb',
  query: 'theandrewlamb',
  profileUrl: 'https://www.instagram.com/theandrewlamb/',
});

assert.deepEqual(instagramCreator, {
  platform: 'instagram',
  handle: 'theandrewlamb',
  displayName: 'theandrewlamb',
  profileUrl: 'https://www.instagram.com/theandrewlamb/',
  nicheTags: [],
  sourceTags: ['discovery_source'],
});

const keywordSource = creatorInputFromSourceRequest({
  kind: 'keyword',
  platform: 'instagram',
  label: 'habit stacking',
  query: 'habit stacking',
});

assert.equal(keywordSource, null);

const instagramPostUrl = creatorInputFromSourceRequest({
  kind: 'tracked_creator',
  platform: 'instagram',
  label: 'p',
  query: 'p',
  profileUrl: 'https://www.instagram.com/p/ABC123/',
});

assert.equal(instagramPostUrl, null);

const instagramReelUrl = creatorInputFromSourceRequest({
  kind: 'tracked_creator',
  platform: 'instagram',
  label: 'reel',
  query: 'reel',
  profileUrl: 'https://www.instagram.com/reel/ABC123/',
});

assert.equal(instagramReelUrl, null);

console.log('discovery.sourceCreator.test.ts passed');
