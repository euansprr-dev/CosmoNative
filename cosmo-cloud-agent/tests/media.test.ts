// Media download tests: FNA cache-node URLs are retried through the canonical
// CDN host, transport failures retry once, dead URLs fall through. Stubs fetch.
// Run: npm run test:media

import assert from 'node:assert/strict';
import {
  canonicalInstagramCDNURL, downloadBinary, downloadCandidates, downloadTuning, INSTAGRAM_CANONICAL_CDN_HOST,
  mirrorCarouselBuffers, sniffImageMime,
} from '../src/swipes/media';

// tsx compiles tests as CommonJS — no top-level await.
async function main(): Promise<void> {

  downloadTuning.retryDelayMs = 0;

  const FNA = 'https://instagram.frtm1-1.fna.fbcdn.net/v/t51.82787-15/785257941_n.jpg?stp=dst-jpg&_nc_ht=instagram.frtm1-1.fna&oh=abc&oe=123';
  const SCONTENT = 'https://scontent-sin6-1.cdninstagram.com/v/t51.82787-15/785257941_n.jpg?oh=abc&oe=123';

  // ── Canonicalization ────────────────────────────────────────────────────────
  const canonical = canonicalInstagramCDNURL(FNA);
  assert.ok(canonical);
  assert.equal(new URL(canonical!).hostname, INSTAGRAM_CANONICAL_CDN_HOST);
  assert.equal(new URL(canonical!).pathname, '/v/t51.82787-15/785257941_n.jpg');
  assert.equal(new URL(canonical!).searchParams.get('_nc_ht'), 'instagram.frtm1-1.fna', 'signed params are left untouched');
  assert.equal(canonicalInstagramCDNURL(SCONTENT), null, 'only FNA hosts are rewritten');
  assert.equal(canonicalInstagramCDNURL('not a url'), null);
  assert.deepEqual(downloadCandidates(SCONTENT), [SCONTENT]);
  assert.deepEqual(downloadCandidates(FNA).map(u => new URL(u).hostname), [INSTAGRAM_CANONICAL_CDN_HOST, 'instagram.frtm1-1.fna.fbcdn.net']);

  // ── Magic bytes ─────────────────────────────────────────────────────────────
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(2000, 1)]);
  assert.equal(sniffImageMime(jpeg), 'image/jpeg');
  assert.equal(sniffImageMime(Buffer.from('hello world')), null);

  // ── Download: canonical host first; transport failure retried once ─────────
  let hosts: string[] = [];
  function stub(route: (host: string, n: number) => Response | Error): void {
    hosts = [];
    globalThis.fetch = (async (input: string | URL | Request) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      const host = new URL(url).hostname;
      hosts.push(host);
      const out = route(host, hosts.length);
      if (out instanceof Error) throw out;
      return out;
    }) as typeof fetch;
  }
  const okJPEG = () => new Response(new Uint8Array(jpeg), { status: 200 });

  stub(host => host === INSTAGRAM_CANONICAL_CDN_HOST ? okJPEG() : new Error('should not reach FNA host'));
  const bytes = await downloadBinary(FNA, 'image', 1000);
  assert.equal(bytes.length, jpeg.length);
  assert.deepEqual(hosts, [INSTAGRAM_CANONICAL_CDN_HOST]);

  // canonical host: ECONNRESET twice → falls back to the original FNA host
  stub(host => host === INSTAGRAM_CANONICAL_CDN_HOST
    ? new TypeError('fetch failed', { cause: { code: 'ECONNRESET' } })
    : okJPEG());
  await downloadBinary(FNA, 'image', 1000);
  assert.deepEqual(hosts, [INSTAGRAM_CANONICAL_CDN_HOST, INSTAGRAM_CANONICAL_CDN_HOST, 'instagram.frtm1-1.fna.fbcdn.net']);

  // a dead URL (403) is NOT retried on the same host
  stub(host => host === INSTAGRAM_CANONICAL_CDN_HOST ? new Response('', { status: 403 }) : okJPEG());
  await downloadBinary(FNA, 'image', 1000);
  assert.deepEqual(hosts, [INSTAGRAM_CANONICAL_CDN_HOST, 'instagram.frtm1-1.fna.fbcdn.net']);

  // every candidate dead → the last error surfaces
  stub(() => new Response('', { status: 404 }));
  await assert.rejects(() => downloadBinary(SCONTENT, 'image', 1000), /download 404/);
  assert.deepEqual(hosts, ['scontent-sin6-1.cdninstagram.com']);

  // wrong content type is a content problem, not a transport one — no retry
  stub(() => new Response(new Uint8Array(Buffer.alloc(3000, 7)), { status: 200 }));
  await assert.rejects(() => downloadBinary(SCONTENT, 'image', 1000), /not an image/);
  assert.equal(hosts.length, 1);

  // ── Carousel mirror stays all-or-nothing ────────────────────────────────────
  assert.equal(await mirrorCarouselBuffers('ATOM', [jpeg, null, jpeg]), null, 'a missing slide blocks the whole array');
  assert.equal(await mirrorCarouselBuffers('ATOM', []), null);

  console.log('✅ media download tests passed');
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
