// cosmo-cloud-agent/src/swipes/fetchers.ts
// Non-Instagram transcript sources: YouTube caption tracks and X/Twitter
// oEmbed — minimal ports of the Mac's YouTubeTranscriptFetcher / XEmbedFetcher.

import { XMLParser } from 'fast-xml-parser';
import { SpeechSegmentJSON } from './types';

export function youtubeVideoId(url: string): string | null {
  const patterns = [
    /youtube\.com\/watch\?.*v=([A-Za-z0-9_-]{6,})/i,
    /youtu\.be\/([A-Za-z0-9_-]{6,})/i,
    /youtube\.com\/shorts\/([A-Za-z0-9_-]{6,})/i,
    /youtube\.com\/embed\/([A-Za-z0-9_-]{6,})/i,
  ];
  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }
  return null;
}

/** Fetch YouTube caption track via the watch page's player response. */
export async function fetchYouTubeTranscript(videoId: string): Promise<SpeechSegmentJSON[]> {
  const watchResponse = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
    headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' },
    signal: AbortSignal.timeout(20_000),
  });
  if (!watchResponse.ok) throw new Error(`YouTube watch page ${watchResponse.status}`);
  const html = await watchResponse.text();

  const marker = '"captionTracks":';
  const start = html.indexOf(marker);
  if (start < 0) throw new Error('No caption tracks found');
  const arrayStart = html.indexOf('[', start);
  const arrayEnd = findBalancedEnd(html, arrayStart);
  if (arrayStart < 0 || arrayEnd < 0) throw new Error('Malformed caption track JSON');

  const tracks = JSON.parse(html.slice(arrayStart, arrayEnd + 1)) as Array<{
    baseUrl?: string;
    languageCode?: string;
    kind?: string;
  }>;
  const track = tracks.find(t => t.languageCode?.startsWith('en') && t.kind !== 'asr')
    ?? tracks.find(t => t.languageCode?.startsWith('en'))
    ?? tracks[0];
  if (!track?.baseUrl) throw new Error('No usable caption track');

  const captionResponse = await fetch(track.baseUrl.replace(/\\u0026/g, '&'), {
    signal: AbortSignal.timeout(20_000),
  });
  if (!captionResponse.ok) throw new Error(`caption track ${captionResponse.status}`);
  const xml = await captionResponse.text();

  const parsed = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@_' }).parse(xml) as {
    transcript?: { text?: Array<{ '#text'?: string; '@_start'?: string; '@_dur'?: string }> | { '#text'?: string; '@_start'?: string; '@_dur'?: string } };
  };
  const rawEntries = parsed.transcript?.text;
  const entries = Array.isArray(rawEntries) ? rawEntries : rawEntries ? [rawEntries] : [];

  return entries
    .map(entry => {
      const startSec = parseFloat(entry['@_start'] ?? '0');
      const duration = parseFloat(entry['@_dur'] ?? '0');
      const text = decodeXMLEntities(String(entry['#text'] ?? '')).trim();
      return { start: startSec, end: startSec + duration, text };
    })
    .filter(segment => segment.text.length > 0);
}

function findBalancedEnd(source: string, openIndex: number): number {
  let depth = 0;
  let inString = false;
  for (let i = openIndex; i < source.length; i += 1) {
    const char = source[i];
    if (inString) {
      if (char === '\\') i += 1;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') inString = true;
    else if (char === '[') depth += 1;
    else if (char === ']') {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function decodeXMLEntities(text: string): string {
  return text
    .replace(/&amp;#39;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\n/g, ' ');
}

/** X/Twitter oEmbed → plain post text. */
export async function fetchTweetText(url: string): Promise<string | null> {
  const response = await fetch(
    `https://publish.twitter.com/oembed?omit_script=1&url=${encodeURIComponent(url)}`,
    { signal: AbortSignal.timeout(15_000) }
  );
  if (!response.ok) return null;
  const payload = await response.json() as { html?: string; author_name?: string };
  if (!payload.html) return null;
  // Strip tags; the oEmbed html is a blockquote containing the tweet text.
  const text = payload.html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&mdash;.*$/s, '')
    .trim();
  return decodeXMLEntities(text) || null;
}
