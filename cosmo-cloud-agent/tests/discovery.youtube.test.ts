import assert from 'node:assert/strict';
import { youtubeVideoToPost } from '../src/discovery/providers/youtube';

const video = {
  id: 'abc123',
  snippet: {
    channelId: 'UC123',
    channelTitle: 'Useful Creator',
    title: 'How to build a daily note system',
    description: 'A practical walkthrough',
    publishedAt: '2026-05-28T08:00:00.000Z',
    thumbnails: {
      high: { url: 'https://i.ytimg.com/vi/abc123/hqdefault.jpg', width: 480, height: 360 },
    },
  },
  statistics: {
    viewCount: '120000',
    likeCount: '9000',
    commentCount: '320',
  },
  contentDetails: {
    duration: 'PT12M34S',
  },
};

const normalized = youtubeVideoToPost(video, {
  handle: 'usefulcreator',
  profileUrl: 'https://www.youtube.com/@usefulcreator',
  followerCount: 250_000,
});

assert.equal(normalized.platform, 'youtube');
assert.equal(normalized.platformPostId, 'abc123');
assert.equal(normalized.creator.handle, 'usefulcreator');
assert.equal(normalized.metrics?.views, 120_000);
assert.equal(normalized.metrics?.likes, 9_000);
assert.equal(normalized.durationSeconds, 754);
assert.equal(normalized.thumbnailUrl, 'https://i.ytimg.com/vi/abc123/hqdefault.jpg');

console.log('discovery.youtube.test.ts passed');
