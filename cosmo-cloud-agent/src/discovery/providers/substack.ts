import { XMLParser } from 'fast-xml-parser';
import type { DiscoveredPostInput, SocialSourceRow } from '../types';
import type { DiscoveryProvider, DiscoveryRefreshResult } from './provider';

interface ParsedRSS {
  rss?: {
    channel?: {
      title?: string;
      link?: string;
      item?: ParsedRSSItem | ParsedRSSItem[];
    };
  };
}

interface ParsedRSSItem {
  title?: string;
  link?: string;
  guid?: string | { '#text'?: string };
  pubDate?: string;
  description?: string;
  encoded?: string;
  enclosure?: { url?: string; type?: string };
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '',
  cdataPropName: '#text',
});

function arrayOf<T>(value: T | T[] | undefined): T[] {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

function publicationHandle(publicationUrl: string): string {
  try {
    const host = new URL(publicationUrl).hostname;
    return host.replace(/^www\./, '').split('.')[0];
  } catch {
    return publicationUrl.replace(/^https?:\/\//, '').split('.')[0];
  }
}

function rssUrl(publicationUrl: string): string {
  const trimmed = publicationUrl.replace(/\/$/, '');
  return trimmed.endsWith('/feed') ? trimmed : `${trimmed}/feed`;
}

function guidValue(guid: ParsedRSSItem['guid'], fallback: string): string {
  if (!guid) return fallback;
  if (typeof guid === 'string') return guid;
  return guid['#text'] ?? fallback;
}

function textValue(value: unknown): string | undefined {
  if (!value) return undefined;
  if (typeof value === 'string') return value;
  if (typeof value === 'object' && '#text' in value) {
    const text = (value as { '#text'?: unknown })['#text'];
    return typeof text === 'string' ? text : undefined;
  }
  return undefined;
}

function stripHTML(value: unknown): string | undefined {
  const text = textValue(value);
  if (!text) return undefined;
  return text.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

export function parseSubstackFeed(
  xml: string,
  options: { publicationUrl: string; sourceUuid?: string }
): DiscoveredPostInput[] {
  const parsed = parser.parse(xml) as ParsedRSS;
  const channel = parsed.rss?.channel;
  const publication = channel?.title ?? publicationHandle(options.publicationUrl);
  const profileUrl = channel?.link ?? options.publicationUrl;
  const handle = publicationHandle(profileUrl);

  return arrayOf(channel?.item).map(item => {
    const link = item.link ?? profileUrl;
    return {
      platform: 'substack',
      provider: 'substack-rss',
      platformPostId: guidValue(item.guid, link),
      canonicalUrl: link,
      sourceUuid: options.sourceUuid,
      creator: {
        platform: 'substack',
        handle,
        displayName: publication,
        profileUrl,
      },
      title: item.title,
      caption: stripHTML(item.description ?? item.encoded),
      postedAt: item.pubDate ? new Date(item.pubDate).toISOString() : undefined,
      mediaType: 'article',
      mediaUrls: item.enclosure?.url ? [{ kind: 'image', url: item.enclosure.url }] : [],
      thumbnailUrl: item.enclosure?.type?.startsWith('image/') ? item.enclosure.url : undefined,
      metrics: {},
      rawPayload: item as unknown as Record<string, unknown>,
    };
  });
}

export class SubstackDiscoveryProvider implements DiscoveryProvider {
  readonly id = 'substack-rss';
  readonly platforms = ['substack'] as const;

  isConfigured(): boolean {
    return true;
  }

  canRefresh(source: SocialSourceRow): boolean {
    return source.platform === 'substack' && ['publication_feed', 'tracked_creator', 'curated_creator'].includes(source.kind);
  }

  async refreshSource(source: SocialSourceRow): Promise<DiscoveryRefreshResult> {
    const publicationUrl = source.profile_url ?? source.query;
    if (!publicationUrl) {
      throw new Error(`Substack source ${source.uuid} has no publication URL`);
    }

    const response = await fetch(rssUrl(publicationUrl));
    if (!response.ok) {
      throw new Error(`Substack RSS ${response.status} for ${publicationUrl}`);
    }

    const xml = await response.text();
    return {
      provider: this.id,
      source,
      posts: parseSubstackFeed(xml, { publicationUrl, sourceUuid: source.uuid }),
    };
  }
}
