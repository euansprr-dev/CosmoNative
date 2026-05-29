import assert from 'node:assert/strict';
import { parseSubstackFeed } from '../src/discovery/providers/substack';

const feed = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Useful Publication</title>
    <link>https://useful.substack.com</link>
    <item>
      <title>Deep work for founders</title>
      <link>https://useful.substack.com/p/deep-work</link>
      <guid>post-1</guid>
      <pubDate>Thu, 28 May 2026 08:00:00 GMT</pubDate>
      <description><![CDATA[A useful essay.]]></description>
      <enclosure url="https://substackcdn.com/image.jpg" type="image/jpeg" />
    </item>
  </channel>
</rss>`;

const posts = parseSubstackFeed(feed, {
  publicationUrl: 'https://useful.substack.com',
  sourceUuid: 'source-1',
});

assert.equal(posts.length, 1);
assert.equal(posts[0].platform, 'substack');
assert.equal(posts[0].platformPostId, 'post-1');
assert.equal(posts[0].creator.handle, 'useful');
assert.equal(posts[0].title, 'Deep work for founders');
assert.equal(posts[0].thumbnailUrl, 'https://substackcdn.com/image.jpg');

console.log('discovery.substack.test.ts passed');
