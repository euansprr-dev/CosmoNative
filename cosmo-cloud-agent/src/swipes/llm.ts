// cosmo-cloud-agent/src/swipes/llm.ts
// Provider-resilient model calls for the swipe pipeline.
//
// Sept 4 2026: every vision and insight call in this pipeline was hard-wired
// to OpenRouter. When the OpenRouter balance hit zero (Aug 29) every carousel
// OCR, reel frame batch and insight pass failed with a bare "402" for six
// days — while GEMINI_API_KEY and ANTHROPIC_API_KEY, both funded, sat unused.
// Every call now walks a chain of providers and only gives up when all of
// them fail. A billing/auth failure parks that provider for a while so a
// 15-slide carousel does not pay the dead round-trip fifteen times, and every
// failure logs provider + status + a body excerpt (the old log lines carried
// only the status code).
//
// Chains:
//   vision (slide OCR, reel frame batches)   gemini → openrouter
//   text, default (cleanup passes)           gemini → openrouter
//   text, insight pass (analyze.ts)          anthropic → openrouter → gemini
//
// Images always travel INLINE (base64) — the worker already holds the bytes
// for the storage mirror, and no provider has to reach Instagram's CDN.

import { config } from '../config';
import { describeFetchError, sleep } from './http';

export type Provider = 'gemini' | 'openrouter' | 'anthropic';

export interface InlineImage {
  data: Buffer;
  mimeType: string;
}

interface BaseRequest {
  /** For logs — "carousel slide 3", "reel batch 0", "insight pass". */
  label: string;
  prompt: string;
  maxTokens: number;
  temperature?: number;
  timeoutMs: number;
  /** Ask for a JSON body where the provider supports it natively (Gemini). */
  jsonMode?: boolean;
  /** Structured-extraction prompts tuned for no-thinking models. */
  noThinking?: boolean;
  /** Per-provider model overrides; defaults come from config. */
  models?: Partial<Record<Provider, string>>;
}

export interface VisionRequest extends BaseRequest {
  images: InlineImage[];
}

export interface TextRequest extends BaseRequest {
  chain?: Provider[];
}

/** Mutable so tests can zero the delays. */
export const llmTuning = {
  retryDelayMs: 2_000,
  cooldownMs: 15 * 60_000,
};

export const VISION_PROVIDER_CHAIN: Provider[] = ['gemini', 'openrouter'];
export const TEXT_PROVIDER_CHAIN: Provider[] = ['gemini', 'openrouter'];

type CallResult =
  | { ok: true; text: string }
  | { ok: false; status: number; detail: string; retryable: boolean; fatal: boolean };

// ── Provider availability + cooldowns ───────────────────────────────────────

const cooldownUntil = new Map<Provider, number>();

export function resetProviderStateForTests(): void {
  cooldownUntil.clear();
}

/** ISO timestamps of providers currently parked after a billing/auth failure. */
export function providerCooldowns(): Record<string, string> {
  const now = Date.now();
  const out: Record<string, string> = {};
  for (const [provider, until] of cooldownUntil) {
    if (until > now) out[provider] = new Date(until).toISOString();
  }
  return out;
}

function providerKey(provider: Provider): string {
  switch (provider) {
    case 'gemini': return config.geminiApiKey;
    case 'openrouter': return config.openRouterApiKey;
    case 'anthropic': return config.anthropicApiKey;
  }
}

function configured(chain: Provider[]): Provider[] {
  return chain.filter(provider => providerKey(provider).length > 0);
}

export function visionConfigured(): boolean {
  return configured(VISION_PROVIDER_CHAIN).length > 0;
}

export function textConfigured(chain: Provider[] = TEXT_PROVIDER_CHAIN): boolean {
  return configured(chain).length > 0;
}

export function visionProviderChain(): Provider[] {
  return configured(VISION_PROVIDER_CHAIN);
}

export function textProviderChain(chain: Provider[] = TEXT_PROVIDER_CHAIN): Provider[] {
  return configured(chain);
}

// ── Entry points ────────────────────────────────────────────────────────────

export async function generateVision(request: VisionRequest): Promise<string | null> {
  return runChain(VISION_PROVIDER_CHAIN, request, provider => callProvider(provider, request, request.images));
}

export async function generateText(request: TextRequest): Promise<string | null> {
  return runChain(request.chain ?? TEXT_PROVIDER_CHAIN, request, provider => callProvider(provider, request, []));
}

/**
 * URL-addressed vision — only OpenRouter can fetch a remote image itself.
 * Last resort for a slide whose bytes could not be downloaded by the worker.
 */
export async function generateVisionFromURL(
  request: Omit<BaseRequest, 'models'> & { imageUrl: string }
): Promise<string | null> {
  if (!config.openRouterApiKey) return null;
  const result = await callOpenRouter(config.openRouterVisionModel, request, [
    { type: 'text', text: request.prompt },
    { type: 'image_url', image_url: { url: request.imageUrl } },
  ]);
  if (result.ok) return result.text;
  console.warn(`⚠️ ${request.label}: openrouter (by URL) ${result.status || 'network'} — ${result.detail}`);
  return null;
}

async function runChain(
  chain: Provider[],
  request: BaseRequest,
  call: (provider: Provider) => Promise<CallResult>
): Promise<string | null> {
  const live = configured(chain);
  if (live.length === 0) {
    console.warn(`⚠️ ${request.label}: no model provider configured`);
    return null;
  }
  const now = Date.now();
  let candidates = live.filter(provider => (cooldownUntil.get(provider) ?? 0) <= now);
  if (candidates.length === 0) {
    // Everything is parked — try anyway; a balance may have been topped up.
    candidates = live;
  }

  for (const provider of candidates) {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const result = await call(provider);
      if (result.ok) return result.text;
      console.warn(`⚠️ ${request.label}: ${provider} ${result.status || 'network'} — ${result.detail}`);
      if (result.fatal) {
        cooldownUntil.set(provider, Date.now() + llmTuning.cooldownMs);
        console.warn(
          `⛔ ${provider} parked for ${Math.round(llmTuning.cooldownMs / 60_000)} min after a billing/auth failure — ` +
          `falling through to the next provider`
        );
        break;
      }
      if (!result.retryable) break;
      if (attempt === 0) await sleep(llmTuning.retryDelayMs);
    }
  }
  console.warn(`❌ ${request.label}: every provider failed (${candidates.join(' → ')})`);
  return null;
}

async function callProvider(provider: Provider, request: BaseRequest, images: InlineImage[]): Promise<CallResult> {
  switch (provider) {
    case 'gemini':
      return callGemini(
        request.models?.gemini ?? (images.length > 0 ? config.geminiVisionModel : config.geminiTextModel),
        request,
        images
      );
    case 'openrouter': {
      const content: unknown = images.length > 0
        ? [
          { type: 'text', text: request.prompt },
          ...images.map(image => ({
            type: 'image_url',
            image_url: { url: `data:${image.mimeType};base64,${image.data.toString('base64')}` },
          })),
        ]
        : request.prompt;
      return callOpenRouter(request.models?.openrouter ?? config.openRouterVisionModel, request, content);
    }
    case 'anthropic':
      return callAnthropic(request.models?.anthropic ?? config.anthropicInsightModel, request, images);
  }
}

// ── Status classification ───────────────────────────────────────────────────

function classify(status: number): { retryable: boolean; fatal: boolean } {
  // 401/402/403: key revoked, balance exhausted, project denied — nothing a
  // retry fixes, and every further call to this provider is wasted latency.
  if (status === 401 || status === 402 || status === 403) return { retryable: false, fatal: true };
  if (status === 408 || status === 409 || status === 429 || status >= 500) return { retryable: true, fatal: false };
  return { retryable: false, fatal: false };
}

function httpFailure(status: number, body: string): CallResult {
  return { ok: false, status, detail: body.replace(/\s+/g, ' ').trim().slice(0, 200), ...classify(status) };
}

function networkFailure(error: unknown): CallResult {
  return { ok: false, status: 0, detail: describeFetchError(error), retryable: true, fatal: false };
}

// ── Gemini (direct Google AI API) ───────────────────────────────────────────

async function callGemini(model: string, request: BaseRequest, images: InlineImage[]): Promise<CallResult> {
  const parts: Array<Record<string, unknown>> = [{ text: request.prompt }];
  for (const image of images) {
    parts.push({ inlineData: { mimeType: image.mimeType, data: image.data.toString('base64') } });
  }
  const generationConfig: Record<string, unknown> = { maxOutputTokens: request.maxTokens };
  if (request.temperature !== undefined) generationConfig.temperature = request.temperature;
  if (request.jsonMode) generationConfig.responseMimeType = 'application/json';
  // thinkingBudget is a 2.5-family knob (3.x uses thinkingLevel and rejects it).
  if (request.noThinking && /^gemini-2\.5/.test(model)) generationConfig.thinkingConfig = { thinkingBudget: 0 };

  let response: Response;
  try {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(config.geminiApiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contents: [{ parts }], generationConfig }),
        signal: AbortSignal.timeout(request.timeoutMs),
      }
    );
  } catch (error) {
    return networkFailure(error);
  }
  if (!response.ok) return httpFailure(response.status, await response.text().catch(() => ''));

  const payload = await response.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> }; finishReason?: string }>;
    promptFeedback?: { blockReason?: string };
  };
  const candidate = payload.candidates?.[0];
  const text = candidate?.content?.parts?.map(part => part.text ?? '').join('') ?? '';
  if (!text.trim()) {
    const reason = candidate?.finishReason ?? payload.promptFeedback?.blockReason ?? 'unknown';
    return { ok: false, status: 200, detail: `empty response (${reason})`, retryable: false, fatal: false };
  }
  if (candidate?.finishReason === 'MAX_TOKENS') {
    console.warn(`⚠️ ${request.label}: gemini hit maxOutputTokens (${request.maxTokens}) — output may be truncated`);
  }
  return { ok: true, text };
}

// ── OpenRouter ──────────────────────────────────────────────────────────────

async function callOpenRouter(model: string, request: BaseRequest, content: unknown): Promise<CallResult> {
  const body: Record<string, unknown> = {
    model,
    messages: [{ role: 'user', content }],
    max_tokens: request.maxTokens,
  };
  if (request.temperature !== undefined) body.temperature = request.temperature;
  // Claude models on OpenRouter run adaptive thinking by default, and
  // max_tokens caps thinking + text COMBINED — a long transcript once burned
  // the whole budget thinking and returned empty content (July 22 pileup).
  if (request.noThinking) body.reasoning = { enabled: false };

  let response: Response;
  try {
    response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.openRouterApiKey}`,
        'X-Title': 'CosmoOS',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(request.timeoutMs),
    });
  } catch (error) {
    return networkFailure(error);
  }
  if (!response.ok) return httpFailure(response.status, await response.text().catch(() => ''));

  const payload = await response.json() as {
    choices?: Array<{ message?: { content?: string }; finish_reason?: string }>;
    error?: { message?: string; code?: number };
  };
  if (payload.error) {
    // OpenRouter can answer 200 with an error envelope.
    return httpFailure(payload.error.code ?? 200, payload.error.message ?? 'error envelope');
  }
  const choice = payload.choices?.[0];
  const text = choice?.message?.content ?? '';
  if (!text.trim()) {
    return { ok: false, status: 200, detail: `empty response (finish=${choice?.finish_reason ?? '?'})`, retryable: false, fatal: false };
  }
  return { ok: true, text };
}

// ── Anthropic (direct) ──────────────────────────────────────────────────────

async function callAnthropic(model: string, request: BaseRequest, images: InlineImage[]): Promise<CallResult> {
  const content: unknown = images.length > 0
    ? [
      ...images.map(image => ({
        type: 'image',
        source: { type: 'base64', media_type: image.mimeType, data: image.data.toString('base64') },
      })),
      { type: 'text', text: request.prompt },
    ]
    : request.prompt;
  const body: Record<string, unknown> = {
    model,
    max_tokens: request.maxTokens,
    messages: [{ role: 'user', content }],
  };
  // Sonnet 5 runs adaptive thinking unless told not to; the insight prompt is
  // tuned for no-thinking extraction. (No sampling params — the 5-family
  // rejects temperature.)
  if (request.noThinking) body.thinking = { type: 'disabled' };

  let response: Response;
  try {
    response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': config.anthropicApiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(request.timeoutMs),
    });
  } catch (error) {
    return networkFailure(error);
  }
  if (!response.ok) return httpFailure(response.status, await response.text().catch(() => ''));

  const payload = await response.json() as {
    content?: Array<{ type?: string; text?: string }>;
    stop_reason?: string;
  };
  const text = (payload.content ?? [])
    .filter(block => block.type === 'text')
    .map(block => block.text ?? '')
    .join('');
  if (payload.stop_reason === 'refusal') {
    return { ok: false, status: 200, detail: 'refusal', retryable: false, fatal: false };
  }
  if (!text.trim()) {
    return { ok: false, status: 200, detail: `empty response (stop=${payload.stop_reason ?? '?'})`, retryable: false, fatal: false };
  }
  if (payload.stop_reason === 'max_tokens') {
    console.warn(`⚠️ ${request.label}: anthropic hit max_tokens (${request.maxTokens}) — output may be truncated`);
  }
  return { ok: true, text };
}
