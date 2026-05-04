import assert from 'node:assert/strict';
import {
  extractTelegramMedia,
  parseCaptureLanePrefix,
  telegramMediaPlaceholder,
} from '../src/agent/captureLane';

const parsed = parseCaptureLanePrefix('books: quote from chapter 3');
assert.deepEqual(parsed, {
  commandText: 'books',
  destinationName: 'books',
  subroute: undefined,
  body: 'quote from chapter 3',
});

const mediaOnly = parseCaptureLanePrefix('books:', { allowsEmptyBody: true });
assert.deepEqual(mediaOnly, {
  commandText: 'books',
  destinationName: 'books',
  subroute: undefined,
  body: '',
});

assert.equal(parseCaptureLanePrefix('books:'), null);
assert.equal(parseCaptureLanePrefix('https://example.com: thing'), null);
assert.equal(parseCaptureLanePrefix('idea: already handled by idea capture'), null);

const subroute = parseCaptureLanePrefix('books/source: ISBN note');
assert.deepEqual(subroute, {
  commandText: 'books/source',
  destinationName: 'books',
  subroute: 'source',
  body: 'ISBN note',
});

const media = extractTelegramMedia({
  caption: 'books:',
  message_id: 42,
  photo: [
    { file_id: 'small', file_unique_id: 'small-u', file_size: 100 },
    { file_id: 'large', file_unique_id: 'large-u', file_size: 200 },
  ],
});
assert.deepEqual(media, [
  {
    kind: 'image',
    fileId: 'large',
    fileUniqueId: 'large-u',
    filename: undefined,
    mimeType: 'image/jpeg',
    fileSize: 200,
    caption: 'books:',
  },
]);
assert.equal(telegramMediaPlaceholder(media), 'Telegram media capture: 1 image');

console.log('captureLane tests passed');
