// Provider-chain tests: a dead OpenRouter balance must never take the
// pipeline down while Gemini / Anthropic keys are funded. Stubs global fetch.
// Run: npm run test:llm-providers

import assert from 'node:assert/strict';
import {
  generateText, generateVision, llmTuning, providerCooldowns, resetProviderStateForTests,
  textProviderChain, visionProviderChain,
} from '../src/swipes/llm';
import { INSIGHT_PROVIDER_CHAIN } from '../src/swipes/analyze';

// tsx compiles tests as CommonJS — no top-level await.
async function main(): Promise<void> {

  llmTuning.retryDelayMs = 0;

  type Handler = (url: string, init: RequestInit) => Response;
  let calls: string[] = [];
  function stubFetch(route: (url: string, init: RequestInit) => Response): void {
    calls = [];
    globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      calls.push(providerOf(url));
      return route(url, init ?? {});
    }) as typeof fetch;
  }
  function providerOf(url: string): string {
    if (url.includes('anthropic.com')) return 'anthropic';
    if (url.includes('openrouter.ai')) return 'openrouter';
    if (url.includes('googleapis.com')) return 'gemini';
    return 'unknown';
  }
  const json = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  const geminiOK = (text: string) => json(200, { candidates: [{ content: { parts: [{ text }] }, finishReason: 'STOP' }] });
  const openRouterOK = (text: string) => json(200, { choices: [{ message: { content: text }, finish_reason: 'stop' }] });
  const anthropicOK = (text: string) => json(200, { content: [{ type: 'text', text }], stop_reason: 'end_turn' });
  const or402 = () => json(402, { error: { message: 'This request requires more credits', code: 402 } });

  // ── Chains reflect configured keys ──────────────────────────────────────────
  assert.deepEqual(visionProviderChain(), ['gemini', 'openrouter']);
  assert.deepEqual(textProviderChain(INSIGHT_PROVIDER_CHAIN), ['anthropic', 'openrouter', 'gemini']);

  // ── Vision: Gemini first; OpenRouter never touched when Gemini answers ──────
  resetProviderStateForTests();
  stubFetch(url => providerOf(url) === 'gemini' ? geminiOK('{"slides":[]}') : or402());
  const vision = await generateVision({
    label: 't', prompt: 'read', images: [{ data: Buffer.from('x'), mimeType: 'image/jpeg' }],
    maxTokens: 10, timeoutMs: 1000,
  });
  assert.equal(vision, '{"slides":[]}');
  assert.deepEqual(calls, ['gemini']);

  // ── Vision: Gemini 500 twice → OpenRouter answers ──────────────────────────
  resetProviderStateForTests();
  stubFetch(url => providerOf(url) === 'gemini' ? json(503, { error: 'overloaded' }) : openRouterOK('from openrouter'));
  const fallback = await generateVision({
    label: 't', prompt: 'read', images: [{ data: Buffer.from('x'), mimeType: 'image/jpeg' }],
    maxTokens: 10, timeoutMs: 1000,
  });
  assert.equal(fallback, 'from openrouter');
  assert.deepEqual(calls, ['gemini', 'gemini', 'openrouter'], '5xx retries once, then falls through');

  // ── Insight: Anthropic 402 → OpenRouter 402 → Gemini answers ───────────────
  resetProviderStateForTests();
  stubFetch(url => {
    const p = providerOf(url);
    if (p === 'anthropic') return json(402, { error: { type: 'billing', message: 'credit balance too low' } });
    if (p === 'openrouter') return or402();
    return geminiOK('{"hookType":"boldClaim"}');
  });
  const insight = await generateText({
    label: 'insight', prompt: 'classify', maxTokens: 10, timeoutMs: 1000,
    chain: INSIGHT_PROVIDER_CHAIN, noThinking: true, jsonMode: true,
  });
  assert.equal(insight, '{"hookType":"boldClaim"}');
  assert.deepEqual(calls, ['anthropic', 'openrouter', 'gemini'], '402 is not retried on the same provider');
  assert.deepEqual(Object.keys(providerCooldowns()).sort(), ['anthropic', 'openrouter'], 'billing failures park the provider');

  // ── Cooldown: the parked providers are skipped on the next call ────────────
  const second = await generateText({
    label: 'insight', prompt: 'classify', maxTokens: 10, timeoutMs: 1000, chain: INSIGHT_PROVIDER_CHAIN,
  });
  assert.equal(second, '{"hookType":"boldClaim"}');
  assert.deepEqual(calls.slice(3), ['gemini'], 'parked providers cost no round-trip');

  // ── Every provider parked → still tries (balance may be topped up) ─────────
  resetProviderStateForTests();
  stubFetch(() => or402());
  llmTuning.cooldownMs = 60_000;
  assert.equal(await generateText({ label: 't', prompt: 'x', maxTokens: 10, timeoutMs: 1000 }), null);
  stubFetch(url => providerOf(url) === 'gemini' ? geminiOK('back') : or402());
  assert.equal(await generateText({ label: 't', prompt: 'x', maxTokens: 10, timeoutMs: 1000 }), 'back');
  assert.ok(calls.includes('gemini'), 'all-parked chain is retried rather than short-circuited');

  // ── Request shapes: Anthropic disables thinking, Gemini asks for JSON ───────
  resetProviderStateForTests();
  let anthropicBody: Record<string, unknown> = {};
  let geminiBody: Record<string, unknown> = {};
  stubFetch((url, init) => {
    const p = providerOf(url);
    if (p === 'anthropic') { anthropicBody = JSON.parse(String(init.body)); return json(529, {}); }
    if (p === 'openrouter') return json(404, {});
    geminiBody = JSON.parse(String(init.body)); return geminiOK('{}');
  });
  await generateText({
    label: 'insight', prompt: 'classify', maxTokens: 8000, timeoutMs: 1000,
    chain: INSIGHT_PROVIDER_CHAIN, noThinking: true, jsonMode: true,
    models: { anthropic: 'claude-sonnet-5', openrouter: 'anthropic/claude-sonnet-5', gemini: 'gemini-2.5-flash' },
  });
  assert.deepEqual(anthropicBody.thinking, { type: 'disabled' });
  assert.equal(anthropicBody.model, 'claude-sonnet-5');
  assert.equal('temperature' in anthropicBody, false, 'the 5-family rejects sampling params');
  assert.equal((geminiBody.generationConfig as Record<string, unknown>).responseMimeType, 'application/json');
  assert.deepEqual((geminiBody.generationConfig as Record<string, unknown>).thinkingConfig, { thinkingBudget: 0 });
  assert.deepEqual(calls, ['anthropic', 'anthropic', 'openrouter', 'gemini'], '529 retried once; 404 not retried');

  // ── Transport failure carries its cause into the log path, then falls through
  resetProviderStateForTests();
  stubFetch(url => {
    if (providerOf(url) === 'gemini') throw new TypeError('fetch failed', { cause: { code: 'ECONNRESET' } });
    return openRouterOK('ok');
  });
  assert.equal(await generateText({ label: 't', prompt: 'x', maxTokens: 10, timeoutMs: 1000 }), 'ok');
  assert.deepEqual(calls, ['gemini', 'gemini', 'openrouter']);

  console.log('✅ llm provider-chain tests passed');
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
