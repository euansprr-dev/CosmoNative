# Reel Transcription V3 — Native Video Understanding

**Status: IMPLEMENTED July 4, 2026** — `src/swipes/reelVideoUnderstanding.ts` (tiers 1+2), processor reel branch (Whisper parallel + tier-3 fallback), carousel 6-concurrent parallelization, tests green. Optional env: `GEMINI_API_KEY` (tier 1, 4fps), `GEMINI_VIDEO_MODEL`, `REEL_VIDEO_FPS`.

## The architectural insight

The Mac pipeline (and its cloud port, "V2") reconstructs understanding from separate channels because an on-device app in early 2026 had no other option:

```
V2:  ffmpeg 4fps frames ─→ 12× Gemini vision batch calls ─→ JS merge/dedup
     Whisper audio      ─→ speech segments                ─→ ~30 hand-tuned
                                                              thresholds decide
                                                              voiceover vs text
                                                           ─→ LLM cleanup call
```

Every fragile part of V2 — the `lyricRisk` score, caption-mirror token-overlap ratios, batch-boundary dedup, the oversegmentation guard — exists **only** because no single component could both see and hear the reel. Modern Gemini models accept [native video input with the audio track](https://ai.google.dev/gemini-api/docs/video-understanding): configurable frame sampling (`videoMetadata.fps`), `media_resolution` control, audio tokenized alongside frames, timestamps every second. One model, full audiovisual context, one judgment.

```
V3:  MP4 (already downloaded for mirroring) ─→ ONE Gemini video call
     → { modality, slides[{text,startSec,endSec}], speechTranscript[], notes }
     Whisper in parallel (when key present) → precision timestamped segments
```

The user's hardest case — **voiceover with burned captions on screen** — becomes trivial: the model hears the narration and sees the captions *at the same time* and is directly instructed "if on-screen text is subtitles of the speech, output the speech transcript and NO slides." No token-overlap heuristic can beat that.

## The three content types, V3 treatment

| Type | V3 pipeline | Output |
|---|---|---|
| Carousel (images/text) | Per-slide Gemini vision (unchanged prompt) — **parallelized, 6 concurrent** (today: sequential) | One transcript slide per card |
| Multi-slider reel (text cards + music) | One native-video call, fps=4 | Every card as a slide, timestamps; music explicitly ignored (model hears it's music) |
| Voiceover reel (talking, ± captions) | Same call | Speech transcript; caption text suppressed; Whisper segments replace Gemini's for tap-to-seek precision |
| Dual (authored slides + distinct narration) | Same call | Slides + `[Voiceover:]` annotations, decided by the model with full context |

## Tiered reliability (augment, don't replace)

1. **Tier 1 — direct Gemini API** (`GEMINI_API_KEY`, new env): Files API upload of the already-downloaded MP4, `videoMetadata.fps: 4` (guarantees sub-second text cards are sampled — same rate the Mac used), default media resolution (258 tok/frame keeps text crisp), `responseSchema` structured output (no parse fragility). Model: `gemini-3-flash-preview` (already the classification model).
2. **Tier 2 — OpenRouter `video_url`** (existing key, [supported with base64 data URLs](https://openrouter.ai/docs/guides/overview/multimodal/videos)): same prompt/schema; sampling is provider-default (~1fps) so very fast cards may need tier 3; used when no Gemini key.
3. **Tier 3 — the shipped V2 frame-batch pipeline**: kept verbatim as the fallback when both video routes fail. Zero code deleted.

All tiers converge on the same output shape → the existing dedup post-pass (cheap insurance) → same persist path.

## Speech strategy

- The video call **always** returns a speech transcript with ~second timestamps — good enough for the tap-to-seek UI. This removes the "reels are partial until OPENAI_API_KEY is added" limitation entirely.
- When `OPENAI_API_KEY` is present, Whisper (`whisper-1` `verbose_json`) runs **in parallel** with the video call; its segments replace Gemini's when the modality verdict is voiceover (dedicated ASR is still the most verbatim on noisy audio, and its timestamps are tighter).
- Music/lyrics: the model hears the audio and is instructed to return `speechTranscript: []` with `audioIsMusic: true` for music beds — lyrics never enter storage. (V2's `lyricRisk` heuristic remains only in tier 3.)

## Speed & cost (60s multi-slider reel)

| | V2 (shipped) | V3 |
|---|---|---|
| Vision calls | 12 sequential batches (~60–120s) | 1 video call (~15–25s) |
| Speech | Whisper serial | parallel with video call |
| Cleanup | +1 LLM call | not needed (single-shot output is clean) |
| Modality decision | 30 thresholds on partial info | model judgment on full audiovisual context |
| End-to-end capture→complete | ~2–4 min | **~45–75s** (Apify run is now the long pole) |
| Marginal cost | ~$0.015 | ~$0.02 (64K video tokens on Flash) — same ballpark |

Carousels: parallelizing the per-slide calls cuts a 10-slide carousel from ~30s to ~4s with identical accuracy.

## Implementation slices

1. `reelVideoUnderstanding.ts`: Gemini Files API upload + video call (tier 1), OpenRouter video_url (tier 2), shared prompt (taught with the full taxonomy: hook-first, every-unique-card, captions-vs-authored-slides discrimination, music handling, complete-text rule — carrying over every hard requirement from the Mac batch prompt) + JSON schema.
2. `processor.ts`: reel branch → try tier 1/2; on result, run Whisper-segment substitution + dedup post-pass; fall back to `transcribeReel` (tier 3) on failure. Log which tier served each reel (`processingWorker` note) so accuracy can be compared in the wild.
3. Carousel parallelization in `transcribe.ts` (6-concurrent pool).
4. Config: `GEMINI_API_KEY` (optional — tier 2 works without it), `REEL_VIDEO_FPS` (default 4).
5. Tests: schema-parse fixtures, tier-fallback logic, Whisper-substitution rule; keep all V2 pipeline tests (tier 3 must stay green).

## Risks & mitigations

- **Gemini misses a <1s flash card at 1fps (tier 2 only):** tier 1 samples at 4fps; if only tier 2 is available and the reel is <90s, escalate to tier 3 when the video call returns suspiciously few slides for a text-heavy reel (model self-reports `visualTextDensity`).
- **Video-call hallucination on dense stat tables:** `media_resolution` default (not low); the complete-text rule + "if uncertain, transcribe exactly what is visible" instruction; dedup pass unchanged.
- **20MB inline limit:** reels are 5–15MB; Files API (tier 1) has no practical limit; tier 2 base64 inflates 1.37× — reels >14MB skip to tier 1/3.

## What deliberately does NOT change

- Carousel per-slide prompt (accuracy-proven), only parallelized.
- Whisper as the precision ASR when available.
- The classification call, engagement capture, media mirroring, claim protocol, all client code — untouched.
- V2 pipeline code — becomes tier 3, byte-identical.
