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

console.log('discovery.sourceCreator.test.ts passed');
