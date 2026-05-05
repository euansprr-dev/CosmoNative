export interface CaptureLaneCommand {
  commandText: string;
  destinationName: string;
  subroute?: string;
  body: string;
}

export interface TelegramCapturedMedia {
  kind: 'image' | 'screenshot' | 'pdf' | 'epub' | 'text_file' | 'markdown' | 'audio' | 'video' | 'document' | 'unknown';
  fileId: string;
  fileUniqueId?: string;
  filename?: string;
  mimeType?: string;
  fileSize?: number;
  caption?: string;
}

export function parseCaptureLanePrefix(
  text: string,
  options: { allowsEmptyBody?: boolean } = {},
): CaptureLaneCommand | null {
  const trimmed = text.trim();
  const colonIndex = trimmed.indexOf(':');
  if (colonIndex <= 0) return null;
  const firstLineBreak = trimmed.search(/[\r\n]/);
  if (firstLineBreak >= 0 && colonIndex > firstLineBreak) return null;

  const prefix = trimmed.slice(0, colonIndex).trim();
  const body = trimmed.slice(colonIndex + 1).trim();
  if (!prefix || (!options.allowsEmptyBody && !body)) return null;
  if (prefix.length < 2 || prefix.length > 64) return null;
  if (/^\d+$/.test(prefix)) return null;

  const parts = prefix.split('/');
  if (parts.length > 2) return null;

  const destinationName = parts[0]?.trim();
  const subroute = parts[1]?.trim() || undefined;
  if (!destinationName) return null;

  const normalizedDestination = normalizeAlias(destinationName);
  const normalizedPrefix = normalizeAlias(prefix);
  const urlSchemes = new Set(['http', 'https', 'ftp', 'mailto', 'tel', 'file']);
  const prefixTokens = normalizedPrefix.split(' ');
  const trailingPrefixToken = prefixTokens[prefixTokens.length - 1];
  if (
    prefixTokens.length > 1 &&
    ['http', 'https', 'ftp'].includes(trailingPrefixToken) &&
    body.startsWith('//')
  ) return null;
  if (urlSchemes.has(normalizedPrefix) || urlSchemes.has(normalizedDestination)) return null;

  const reservedPrefixes = new Set([
    'inbox',
    'idea',
    'save idea',
    'new idea',
    'capture idea',
    'task',
    'todo',
    'to do',
    'swipe',
    'research',
    'content',
    'lesson',
    'rule',
    'current',
    'current inquiry',
    'inquiry',
  ]);
  if (reservedPrefixes.has(normalizedDestination)) return null;

  return {
    commandText: prefix,
    destinationName,
    subroute,
    body,
  };
}

export function extractTelegramMessageText(message: Record<string, any>): string | undefined {
  return typeof message.text === 'string'
    ? message.text
    : typeof message.caption === 'string'
      ? message.caption
      : undefined;
}

export function extractTelegramMedia(message: Record<string, any>): TelegramCapturedMedia[] {
  const caption = typeof message.caption === 'string' ? message.caption : undefined;

  if (Array.isArray(message.photo)) {
    const largest = message.photo
      .filter((item: any) => typeof item?.file_id === 'string')
      .sort((a: any, b: any) => (Number(b.file_size) || 0) - (Number(a.file_size) || 0))[0];
    if (largest) {
      return [{
        kind: 'image',
        fileId: largest.file_id,
        fileUniqueId: largest.file_unique_id,
        filename: undefined,
        mimeType: 'image/jpeg',
        fileSize: numberOrUndefined(largest.file_size),
        caption,
      }];
    }
  }

  if (message.document && typeof message.document.file_id === 'string') {
    const document = message.document;
    const filename = typeof document.file_name === 'string' ? document.file_name : undefined;
    const mimeType = typeof document.mime_type === 'string' ? document.mime_type : undefined;
    return [{
      kind: mediaKind(filename, mimeType),
      fileId: document.file_id,
      fileUniqueId: document.file_unique_id,
      filename,
      mimeType,
      fileSize: numberOrUndefined(document.file_size),
      caption,
    }];
  }

  if (message.voice && typeof message.voice.file_id === 'string') {
    const voice = message.voice;
    return [{
      kind: 'audio',
      fileId: voice.file_id,
      fileUniqueId: voice.file_unique_id,
      filename: 'telegram-voice.ogg',
      mimeType: typeof voice.mime_type === 'string' ? voice.mime_type : 'audio/ogg',
      fileSize: numberOrUndefined(voice.file_size),
      caption,
    }];
  }

  if (message.audio && typeof message.audio.file_id === 'string') {
    const audio = message.audio;
    return [{
      kind: 'audio',
      fileId: audio.file_id,
      fileUniqueId: audio.file_unique_id,
      filename: typeof audio.file_name === 'string' ? audio.file_name : 'telegram-audio',
      mimeType: typeof audio.mime_type === 'string' ? audio.mime_type : undefined,
      fileSize: numberOrUndefined(audio.file_size),
      caption,
    }];
  }

  if (message.video && typeof message.video.file_id === 'string') {
    const video = message.video;
    return [{
      kind: 'video',
      fileId: video.file_id,
      fileUniqueId: video.file_unique_id,
      filename: typeof video.file_name === 'string' ? video.file_name : 'telegram-video.mp4',
      mimeType: typeof video.mime_type === 'string' ? video.mime_type : 'video/mp4',
      fileSize: numberOrUndefined(video.file_size),
      caption,
    }];
  }

  return [];
}

export function telegramMediaPlaceholder(media: TelegramCapturedMedia[]): string {
  if (media.length === 0) return 'Telegram media capture';
  const counts = new Map<string, number>();
  for (const item of media) {
    counts.set(item.kind, (counts.get(item.kind) || 0) + 1);
  }
  const parts = Array.from(counts.entries()).map(([kind, count]) => `${count} ${kindLabel(kind, count)}`);
  return `Telegram media capture: ${parts.join(', ')}`;
}

function normalizeAlias(raw: string): string {
  return raw
    .toLowerCase()
    .trim()
    .replace(/[\u201C\u201D]/g, '')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function mediaKind(filename?: string, mimeType?: string): TelegramCapturedMedia['kind'] {
  const lowerName = (filename || '').toLowerCase();
  const lowerMime = (mimeType || '').toLowerCase();
  if (lowerMime === 'application/pdf' || lowerName.endsWith('.pdf')) return 'pdf';
  if (lowerName.endsWith('.md') || lowerName.endsWith('.markdown') || lowerMime === 'text/markdown') return 'markdown';
  if (lowerMime.startsWith('text/') || lowerName.endsWith('.txt')) return 'text_file';
  if (lowerMime.startsWith('image/')) return 'image';
  if (lowerMime.startsWith('audio/')) return 'audio';
  if (lowerMime.startsWith('video/')) return 'video';
  if (lowerName.endsWith('.epub')) return 'epub';
  return 'document';
}

function kindLabel(kind: string, count: number): string {
  const label = kind === 'text_file' ? 'text file' : kind;
  return count === 1 ? label : `${label}s`;
}

function numberOrUndefined(value: unknown): number | undefined {
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}
