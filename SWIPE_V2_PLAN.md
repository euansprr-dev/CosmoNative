# Swipe V2 — Cloud-First Processing Pipeline

**Goal:** capture a swipe anywhere (iPhone, Mac, Telegram) and have the full result — permanent video + thumbnails in Supabase, transcript, analysis, engagement data — within ~1–2 minutes, **with the Mac off**. Apify becomes the primary Instagram source; the Railway cloud agent (`cosmo-cloud-agent/`, deployed as `cosmonative-production.up.railway.app`) becomes the processor; the Mac pipeline stays as an automatic fallback (augment, don't replace).

**Decisions locked (July 3, 2026):** Railway does everything · Whisper API for reel speech · engagement captured once at capture + manual refresh · Mac pipeline kept as fallback · **anything that can be instant IS instant** (thumbnail at capture, before any processing).

## Instant-thumbnail principle

Verified July 3: `https://www.instagram.com/p/<shortcode>/media/?size=l` 302-redirects to the post's CDN JPEG with no auth in <1s (works for reels and posts alike; cobalt's JPEG fallback is a ~2s backup). Three layers use this:

1. **At capture (on-device, both apps):** for Instagram URLs, resolve the `/media/?size=l` redirect (3s timeout, best-effort) and write the CDN URL to `metadata.thumbnailUrl` before saving the atom. The card shows an image the moment it lands in the grid. CDN URLs expire in days — acceptable, because:
2. **Worker quick-stage (first thing after claim):** if the atom has no `thumbnailStorageURL`, fetch the same redirect (cobalt JPEG as fallback), mirror to `atom-images/<user>/swipe-thumbs/<uuid>.jpg`, and write `thumbnailStorageURL` in an immediate small update — the permanent thumbnail syncs to devices within seconds, well before transcription finishes.
3. **Full pipeline** then replaces/adds video, slides, transcript, analysis as before.

**Processing UI copy:** while a swipe is processing, opening it shows a status-specific line — `pending/extracting` → "Getting this post…", `transcribing` → "This post is transcribing…", `analyzing` → "Analyzing…". Cards keep the small orange dot. Stuck >30 min → "Taking longer than usual — Retry".

---

## Why this shape

- **Today** every swipe waits for the Mac app to be open and awake: extraction (cobalt chain — currently fully blocked by Instagram), local frame extraction + speech recognition, local NLP, one Gemini Flash classification call, then three drain loops upload media to Supabase. Sleep/closed = nothing happens. iOS shows "Your Mac is transcribing…" indefinitely.
- **Apify** (`apify/instagram-scraper`, ~$2.30/1k results) returns in one call: playable `videoUrl`, carousel `childPosts` images, `displayUrl` thumbnail, caption, `ownerUsername`, `timestamp`, `likesCount`, `commentsCount`, `videoViewCount`. Engagement is free with the same call. The user's $25/mo Apify plan covers thousands of swipes/month.
- **The cloud agent already has**: `APIFY_API_KEY` (used by discovery), `OPENROUTER_API_KEY`, node-cron scheduler, Express API with auth, and a **Supabase service-role client** — which bypasses storage RLS and therefore also fixes the long-standing `atom-images` 403 that has blocked thumbnail mirroring.
- **The sync contract is already built**: worker writes rows with `_source: "cloud"`; both clients' pull filters accept non-self sources, and both ConflictResolvers use `preferRemoteForStatus` metadata merging for cloud-sourced rows (processingStatus/status fields win, user edits survive).

**Monthly cost at ~300 swipes:** Apify ~$0.70 · Whisper ~$1.80 (300 × ~1 min × $0.006) · Gemini Flash vision-OCR for slides ~$0.10 · classification ~$0.10 → **≈ $3/month**.

---

## Phase 1 — Railway swipe worker (the core)

New module `cosmo-cloud-agent/src/swipes/`:

1. **`processor.ts` — the worker loop.** node-cron every 30s: query Supabase `atoms` for `type='research'`, metadata `isSwipeFile:true`, `processingStatus IN ('pending','partial')` plus `extraction_failed` older than 30 min (retry backoff, max ~5 attempts). Claim by setting `processingStatus='extracting'` + `processingWorker:'cloud'` + `processingClaimedAt` (ISO). A claim older than 15 min is stale and reclaimable — by the worker or the Mac fallback.
2. **`instagram.ts` — Apify extraction.** One `apify/instagram-scraper` run per swipe URL (the existing Mac `ApifyInstagramProvider` request shape is the reference; the agent already talks to Apify for discovery). Output → internal shape: contentType (reel/video/carousel/image), videoUrl, thumbnail, ordered slide URLs, caption, author, publishedAt, shortcode, engagement counts. If Apify errors: mark `extraction_failed` (backoff retries), never burn credits in a tight loop.
3. **`media.ts` — permanent mirroring.** Download media from the CDN URLs Apify returns (they expire — mirror immediately, same run):
   - video → `swipe-videos/<user>/<atomUUID>.mp4` → metadata `videoStorageURL`
   - thumbnail → `atom-images/<user>/swipe-thumbs/<atomUUID>.jpg` → `thumbnailStorageURL`
   - each slide → `atom-images/<user>/swipe-carousel/<atomUUID>-<i>.jpg` → ordered `carouselImageStorageURLs` (written only when ALL slides succeed — same contract as the Mac mirror, so both apps need zero display changes).
4. **`transcribe.ts` + `reelPipeline.ts`.**
   - **Reels/videos:** OpenAI Whisper API (`whisper-1`, `verbose_json`) on the downloaded MP4 → timestamped segments → `swipeAnalysis.transcriptSpeechSegments` (existing schema: start/end/text). **PLUS the full Mac-parity multi-slide pipeline (`reelPipeline.ts`):** ffmpeg extracts frames at 4fps (max 240, ffmpeg baked into the Docker image), Gemini vision reads 20-frame batches with the Mac's verbatim batch prompt, batches merge with boundary + global dedup (Jaccard ≥0.92 / containment ≥0.90), and the Mac's modality-arbitration engine (lyricRisk / voiceoverScore / textScore) decides textOnly vs voiceoverOnly vs voiceoverPlusText — so text-card reels keep every slide, nothing duplicates, and music/lyrics are never stored as a voiceover transcript (textOnly verdict drops the speech segments). A final LLM cleanup pass (Mac's verbatim prompt) fixes OCR artifacts without merging or dropping slides; raw merge output persists as `rawTranscriptSlides`.
   - **Carousels/images:** one Gemini Flash vision call via OpenRouter with all slide images → verbatim per-slide text → `swipeAnalysis.transcriptSlides` (slideNumber/text). Port the Mac's slide-transcription prompt from `InstagramAutoTranscriber` **verbatim** — do not compress it (prompt detail drives quality).
5. **`analyze.ts` — classification.** Port the `SwipeClassificationEngine` prompt and JSON response contract verbatim (model: `google/gemini-3-flash-preview` via OpenRouter, temp 0.2). Writes the same fields: narrative, niche, contentFormat, framework, sections, emotional arc, persuasion, hook + hookScore, creatorHandle. Creator-atom resolution/linking: done in the worker against Supabase atoms (one prefetch of creator atoms per batch, not 4 queries per swipe like the Mac does today).
6. **Engagement.** Write `likesCount, viewsCount, commentsCount, sharesCount, engagementRate ((likes+comments)/views), publishedAt, postShortcode` into `swipeAnalysis`. The fields and their re-analysis merge protection already exist in both apps.
7. **YouTube / Twitter / web swipes:** port the two trivial fetchers (YouTube caption track — `fast-xml-parser` is already a dependency; Twitter oEmbed) so ALL swipe types complete cloud-side. Web articles: keep current behavior (title/caption only).
8. **Status vocabulary unchanged:** pending → extracting → transcribing → analyzing → complete | partial | extraction_failed. iOS/Mac already parse these.
9. **API endpoint** `POST /api/swipes/refresh-stats { swipeUUID }` (existing Express auth): re-runs the Apify call, updates engagement fields only. Also `POST /api/swipes/process { swipeUUID }` for an instant kick (capture surfaces can call it fire-and-forget so processing starts in seconds instead of on the next cron tick).
10. **Version discipline:** every atom update bumps `_version`, sets `_source:'cloud'`, `updated_at` — and NEVER flips `is_deleted` 1→0 (deletes are one-way; guard in the worker's update helper too).

**Testing:** unit tests in `cosmo-cloud-agent/tests/` for the Apify→shape mapping and status transitions; live test: capture reel + carousel on iPhone with the Mac app closed, expect complete swipes with playing video in ≤2 min.

## Phase 2 — Clients: display, kick, fallback

**Both apps:**
- **Capture kick:** after saving a pending swipe, fire-and-forget `POST /api/swipes/process` (auth header already stored: discovery API key / service key). Failure is fine — the cron tick catches it.
- **Engagement UI:** SwipeHeroView (iOS) meta row + Mac SwipeStudy header get a quiet stats line: `▶ 1.2M · ♥ 48K · 💬 312 · posted May 12`. Formatting: compact (K/M). Only shown when data exists. "Refresh stats" in the actions menu → the refresh endpoint → reload.
- **Stuck-state UX:** a swipe `pending/extracting` for >30 min shows "Taking longer than usual — Retry" (sets `pending` + kicks the endpoint). Replaces today's indefinite "Your Mac is transcribing…" (copy also updated — it's no longer the Mac).

**Mac (fallback gating):**
- `SwipeProcessingService.scanForPendingSwipes()` skips swipes claimed by `processingWorker:'cloud'` unless the claim is stale (>15 min). Net effect: Railway wins the race when up; the Mac transparently takes over when it isn't. The full local pipeline is otherwise untouched.
- Mac extraction chain (fallback path only): try `ApifyInstagramProvider` FIRST, cobalt second, embed/GraphQL/HTML/yt-dlp last. (Apify provider + key field already exist on Mac.)
- Drain loops: unchanged — they skip atoms whose storage URLs are already set, so cloud-processed swipes cost them nothing; they still backfill legacy swipes.

## Phase 3 — Waste removal / simplification (verified in code)

1. **URL dedup at capture** (both apps + worker): normalize URL (strip `igsh`/query junk, resolve `/reels/`→`/reel/`), check for an existing live swipe with the same normalized URL or `postShortcode`; if found, surface it instead of creating a duplicate atom.
2. **Creator resolution batching** on Mac (`SwipeClassificationEngine.resolveCreator`): prefetch creators once per batch instead of 4 queries per swipe.
3. **Fix the `transcriptEditedByUser` contradiction:** partial-carousel upgrade path must also respect the user-edit terminal lock (today it re-attempts and can clobber intent).
4. **Delete the 2-second partial-carousel sleep/retry** on the cloud path (Apify returns complete carousels; the retry dance was a cobalt workaround). Keep on Mac fallback.
5. **Classification skip is NOT adopted** — one Flash call per swipe is ~free and the deep fields are used everywhere; not worth the quality risk.

## Phase 4 — Ops & hardening

- Railway env additions: `OPENAI_API_KEY` (Whisper). Everything else already configured.
- Worker logging mirrors PersistenceHealth style; `/health` reports swipe-worker lag (oldest pending age) so a dead worker is visible.
- Apify budget guard: hard monthly cap counter (env, default 3,000 runs) — beyond it, worker leaves swipes pending for the Mac fallback and logs loudly.
- Storage RLS: service role bypasses it (thumbnail 403 gone for new swipes). Optionally still apply the dashboard policy so the Mac fallback can upload too.
- Rollout order: deploy worker → verify with Mac app closed → ship client changes (kick + engagement UI + gating) → watch a week → tighten Mac scan interval if desired.

## Explicitly NOT in V2

- No always-on background processing on iOS (the cloud does it).
- No engagement auto-polling (capture snapshot + manual refresh only).
- No removal of the Mac pipeline, WhisperKit, or the cobalt chain — they are the fallback tier.
- Transcription model on Mac fallback unchanged.
