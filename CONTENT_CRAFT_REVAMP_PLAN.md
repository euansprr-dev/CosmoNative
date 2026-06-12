# Content Craft Revamp — From Generation Engine to Craft Assistant

**Date:** June 11, 2026
**Status:** IMPLEMENTED June 11, 2026 — `AI/Craft/` (CraftTypes, CraftComparableSelector, CraftStatsBuilder, CraftStudyMethod, CosmoCraftEngine, CosmoCraftSkillRunner), intercepted in `CosmoInlineAssistantAgentBridge.live`, tests in `CraftEngineTests.swift`. `/review` and `/riff` (aliases `/vary`, `/variations`) ride the existing `contentReview` / `voiceVariations` built-in skills.
**Replaces (in spirit, not in code):** the codex-based cloud writing pipeline for day-to-day work. The old system stays in place untouched (augment, don't remove); these skills are additive.

---

## 1. Diagnosis — why the old system cost $10/task and stalled at 60–70%

The investigation mapped the whole pipeline. The expense and the quality ceiling come from the same root cause: **the system was built to replace the writer, so it had to carry the entire weight of the task in every call.**

### Where the money went

| Cost driver | Detail |
|---|---|
| Mega-context | 40–50K tokens per call: methodology + client profile + intelligence model + 30 full swipe transcripts + beat patterns + knowledge layer ([WritingContextAssembler.swift](AI/WritingContextAssembler.swift)) |
| Agentic loop | 3–6 Opus turns per task (brainstorm → draft iterations → polish), each re-sending the mega-context ([UnifiedWritingEngine.swift](AI/UnifiedWritingEngine.swift)) |
| Old pricing | Cost logging at UnifiedWritingEngine.swift:148-152 is hard-coded to legacy Opus pricing — 15¢/1M uncached in, 75¢/1M out. Current Opus 4.8 is $5/$25 (3× cheaper) |
| Cache fragility | 1h TTL caches help only inside a burst; client switches, blueprint changes, and the known cache-eviction bugs caused frequent full-price re-sends |
| Sidecar pipelines | SwipeAdaptationEngine 2-pass runs, scorecard calls, codex generation/refresh on the cloud agent |
| Cloud hosting | Railway server (cosmo-cloud-agent) running 24/7 for a task that originates in-app |

### Why quality plateaued

1. **The codex taught taxonomy, not craft.** 118 elements across 17 categories (Speech Acts, Reader Deltas, RSV Dimensions, Antimatter, Physics Events…) is an impressive *description* of content, but description ≠ generation. The model drowned in vocabulary about content instead of studying actual content. The parts that demonstrably worked are the **six craft modules** in [PromptTemplateStore.swift](Services/PromptTemplateStore.swift) (dinner-table test, slide density, causal chaining, hook craft, voice absorption, CTA craft) — concrete procedures with pass/fail tests.
2. **Generation has no error correction.** When the model writes the whole draft, every weak beat compounds. A 90%-right slide 2 poisons slides 3–8. Human-in-the-loop review inverts this: the human supplies intent and taste, the model supplies pattern recall across hundreds of transcripts — each side doing what it's actually best at.
3. **Profiles abstracted away the evidence.** SwipeAnalysis profiles, codex profiles, and client intelligence summaries are lossy compressions *of transcripts*. The model was reasoning over summaries of summaries. The raw transcript + engagement numbers is the ground truth, and modern models read raw transcripts extremely well if you teach them *how to study one*.

---

## 2. The new design — one small engine, two skills

### CosmoCraftEngine (new, local, no cloud)

A single lightweight Swift engine, `AI/Craft/CosmoCraftEngine.swift`, shared by both skills. It **never generates a draft**. It does exactly one thing: assemble a deterministic, cache-friendly context and make **one structured Opus call** (occasionally a follow-up turn for conversation). No tool loop, no think-tool stalls, no cloud server, no NDJSON streaming infrastructure. It calls the Anthropic API directly through the same provider plumbing the inline assistant already uses.

```
User invokes /review or /riff in the inline assistant
        │
        ▼
1. SURFACE READ (0 tokens) — open content atom via ContentContextProvider
   • draft text, title, client UUID, platform
   • format detection: WritingContentFormat.detect(from:) at
     UnifiedWritingTypes.swift:480 + density heuristic
     (≈1 sentence/slide → reel · multi-sentence slides → carousel/thread)
        │
        ▼
2. COMPARABLE SELECTION (0 tokens) — new CraftComparableSelector (pure Swift/GRDB)
   • filter: same format + same niche/client space
   • rank: local embedding similarity (nomic daemon, already running)
     to the draft's topic + beat-fingerprint proximity
   • output: 6–8 full raw transcripts + their real engagement numbers
   • plus: client's own top performers (3 reels / 3 carousels, raw transcripts)
   • NOTE: no hookScore gating — every swipe in the library is curated
     and eligible; engagement numbers are evidence, never a filter
        │
        ▼
3. STATS TABLE (0 tokens) — computed in Swift from SwipeAnalysis engagement
   fields: views/ER medians for this format+niche, top hook openers by
   actual views, slide-count distribution of the best performers
        │
        ▼
4. ONE STRUCTURED OPUS 4.8 CALL
   [cached 1h] Transcript Study Method (~4-5K tok)   ← the "bones"
   [cached 1h] Client voice pack: top transcripts + failure rules (~6-8K)
   [fresh]     Comparables w/ engagement + stats table (~6-8K)
   [fresh]     The draft + task instruction (~1-2K)
   → structured output (JSON schema enforced) → rendered natively in the pane
```

### What we keep (the bones) and what we drop

| Keep | Drop |
|---|---|
| The 6 craft modules + self-edit pass (PromptTemplateStore) — verbatim, full detail | Codex element/walkthrough atoms as LLM context (the Codex UI browser can stay for human study) |
| Raw swipe transcripts + real engagement metrics | Per-swipe analysis *profiles* as prose context (SwipeAnalysis stays in GRDB — we still use its fields for retrieval/stats, we just stop narrating it to the model) |
| Client top-performer transcripts + failure fingerprint | Client adaptation profiles, intelligence-model summaries as primary context |
| Beat fingerprints + embeddings (for retrieval only, zero-cost) | The multi-turn generation loop, outline/hooks/draft tools, cloud session streaming |
| The learned-lessons mechanism (rules appended from real corrections) | Codex generation/refresh pipeline costs |

### The Transcript Study Method (one-time distillation)

The single most important new asset. A ~4–5K-token teaching document that tells the model **how to read, study, and break down a transcript** — built once by distilling the genuinely operational parts of the codex (Pass 2 generation recipes, anti-example-with-fix entries, walkthrough composition lessons) and fusing them with the six craft modules. Structure:

1. **How to read a swipe** — first pass aloud for rhythm; second pass marking the job of each slide (hook → tension → payoff → CTA); third pass asking "what did the creator deliberately NOT do."
2. **What to extract** — the hook mechanism in one sentence; the causal chain between slides; where the open loop closes; density per slide (reels: one breath per slide; carousels: ~4 sentences per slide).
3. **How to compare** — same-beat comparison only (hook vs hooks, CTA vs CTAs), never whole-post vibes; always cite the engagement numbers attached to the pattern you're citing.
4. **The six craft tests** — dinner-table, density, chain, hook cover/scroll test, same-person voice test, CTA-as-next-sentence — imported with full detail, not compressed.
5. **Format addenda** — reel rules vs carousel/thread rules (slide density, hook length, CTA placement), selected per detected format.

Stored as editable modules in PromptTemplateStore (so it benefits from the existing learned-rules append mechanism and you can tune it without recompiling). Cached with 1h TTL — it's identical across every review for every client, the perfect cache prefix.

---

## 3. Skill One: `/review` — "The Editor"

**Route:** `.answer` (pane) — review is advisory; nothing touches the draft without you.

**What it does, in order:**

1. Detects format (reel vs carousel vs thread) and announces its read: *"Reading this as a 9-slide carousel for [client]."*
2. **Performance read** — compares the draft beat-by-beat against the comparables and the client's own top performers, and gives a *relative, evidenced* prediction: not a fake view count, but "top-quartile potential / middle of your range / below your median, because…" — each claim tied to a named comparable and its real numbers. (Example of the kind of output: "Your hook is a how-to opener. Your three highest-view comparables in this niche all open with a curiosity gap and average 480K views; the how-to openers in your library average 90K.")
3. **Slide-by-slide notes** — only slides with a real issue, each note naming the failed craft test (chain break, density violation, voice drift, unfunded promise) and quoting the comparable that does that beat well.
4. **Top 3 moves** — ranked by predicted impact. For the single weakest beat only, 2–3 worded micro-variations so you can feel the direction (this is the limited "give me a few variations" you asked for — it never rewrites the piece).
5. **Verdict** — one paragraph, dinner-table voice, what this piece is one fix away from.

The output is schema-enforced (structured outputs), so the pane can render it as a real scorecard UI — verdict header, evidence rows with engagement numbers, slide notes anchored to slide indices — rather than a wall of markdown.

Follow-up turns ("what about slide 4?", "is the CTA too soft?") ride the same conversation with the whole prefix cached → each costs pennies.

## 4. Skill Two: `/riff` — "The Variation Partner"

**Route:** `.answer` pane for the options, with one-click **apply-as-diff** per variation (through the existing `CosmoInlineDiffLocator` accept/reject path — human approves every change).

**Invocation shapes:**
- Selection-scoped: select a slide → `/riff` → variations of that beat.
- Direction-scoped: `/riff I want the hook to feel more like a confession than a tip`.
- Struggle-scoped: `/riff I can't get slides 3–4 to land, they feel flat`.

**What it does:** identifies which beat you're working (hook / tension / proof / CTA), pulls how the 6–8 comparables execute *that same beat*, then returns **5–7 variations across genuinely different mechanisms** — not seven rewordings of one idea. Each variation card carries: the text (format-correct density), the mechanism in five words ("curiosity gap via absence"), and which comparable's pattern it borrows (with its numbers). One line at the end says which one it would bet on and why.

This is deliberately the inverse of `/review`: review is whole-piece and judgmental, riff is single-beat and generative-on-demand. Together they cover the two moments you actually hit while writing: *"is this good?"* and *"I'm stuck right here."*

### Why these names
- **/review** — matches your own words, zero learning curve, embedding-routes naturally from "check this," "score this," "how will this do."
- **/riff** — short, evocative of a writing partner riffing with you (not outsourcing to a ghostwriter), and won't collide with other commands. Aliases `/vary` and `/variations` registered as trigger phrases. Both are `CosmoInlineSkillDefinition` rows in GRDB — renaming is a data edit, not a code change.

---

## 5. Cost model (current API pricing, verified June 2026)

Opus 4.8: $5/M input, $25/M output. Cache reads ≈ 0.1× input. Cache write premium 2× for 1h TTL on the cached portion only.

| Task | Input | Output | Cold (first of the hour) | Warm (cache hit) |
|---|---|---|---|---|
| `/review` | ~25K (≈13K cached) | ~4K | ≈ $0.29 | ≈ $0.15 |
| `/riff` | ~14K (≈11K cached) | ~1.5K | ≈ $0.13 | ≈ $0.05 |
| Follow-up turn | mostly cached | ~1K | — | ≈ $0.03–0.05 |

**Every task lands at $0.05–0.30 — 3–10× under the $1 ceiling, and ~30–70× under the old $10 real-world cost.** The headroom is deliberate: it pays for the best available model (Opus 4.8, not a downgrade), full raw transcripts instead of clipped summaries, and free follow-up conversation. The cost collapse comes from four compounding factors:

1. **1 call instead of 3–6** (no agentic loop) → ~5×
2. **~25K context instead of ~50K** (no codex, no profiles, no 30-swipe dump — 6–8 *selected* transcripts) → ~2×
3. **Current Opus pricing vs what the engine was built on** ($5/$25 vs $15/$75) → 3×
4. **All retrieval/ranking/stats done in Swift for free** (the old system paid Sonnet to screen swipes)

Guardrails to build in: per-call cost computed from the `usage` block with **current** pricing constants (fixing the stale ones), logged to GRDB per skill run, with a rolling monthly total visible in settings.

---

## 6. Why this beats the old system on quality (the sell)

**1. It puts the model on the task models are best at.** Frontier-model writing taste tops out below a great human's; frontier-model *pattern recall across 500 transcripts with perfect memory of every number* is superhuman. The old system bet on the weak capability (generation) and ignored the strong one (comparative analysis). This design is built entirely on the strong one. That's why the old system stalled at 60–70% — and why a reviewer that says "slide 5 breaks the causal chain; here's how [comparable, 1.2M views] bridges the same gap" gets you to 95%: *you* write the fix in your voice, which was always the missing 30%.

**2. Evidence replaces vibes.** The old scorecard ("Hook: 7/10") was unfalsifiable. Every claim the new system makes is anchored to a named transcript and a real engagement number. When it's wrong, you can see *why* it's wrong and correct the method doc — the system is debuggable for the first time.

**3. The teaching finally matches how learning works.** Writers don't get good by memorizing a 118-element periodic table; they get good by studying great pieces with a method. The codex's one durable insight — its operational recipes and anti-patterns — survives, distilled into the Transcript Study Method. The taxonomy overhead dies.

**4. Human-in-the-loop is an error-correction architecture, not a compromise.** Generation compounds errors forward; review catches them at each beat. Your taste stays in the loop at exactly the points where taste matters.

**5. It gets better with use, cheaply.** The learned-rules channel already exists (PromptTemplateStore). When a review misses or a riff lands, one appended rule improves every future call — no codex regeneration pipeline, no retraining run, no cloud job.

**6. It's simpler than what it replaces by an order of magnitude.** No Railway server, no engine-per-contentUUID cache with eviction bugs, no plain-string-vs-JSON tool boundary, no session streaming. One Swift type, one API call, one schema. Less surface area = fewer of the eight known bugs class of problems.

---

## 7. Implementation plan

### Phase 1 — Foundations (no LLM code yet)
- `AI/Craft/CraftComparableSelector.swift`: format+niche filter → embedding similarity (DaemonXPCClient, same as skill auto-router) → 6–8 transcripts + client top performers. No hookScore gating anywhere.
- `AI/Craft/CraftStatsBuilder.swift`: medians/quartiles for views & ER per format+niche, hook-opener leaderboard, slide-count distribution.
- Format detection wrapper: `WritingContentFormat.detect(from:)` + sentence-density fallback for ambiguous metadata.
- Unit tests against the existing swipe fixtures.

### Phase 2 — Distill the Transcript Study Method (one-time, assisted)
- Mine codex Pass 2 fields (`operationalRecipe`, `generationRecipe`, `antiExampleFix`, walkthrough `compositionLesson`s) + the 6 modules into the method doc described in §2.
- Land as new PromptTemplateStore modules: `transcript_study_method`, `format_reel_addendum`, `format_carousel_addendum`, `format_thread_addendum`. Full detail preserved — no compression of procedures or examples.

### Phase 3 — CosmoCraftEngine
- Context assembly with explicit cache blocks (method doc + client pack = cached 1h; comparables + draft = fresh). Cache prefix kept byte-stable (no timestamps, deterministic ordering).
- One structured call per task; JSON schemas for `ReviewResult` and `RiffResult`.
- Cost tracking from `usage` with current pricing constants; per-run GRDB log.

### Phase 4 — `/review` skill + pane rendering
- `CosmoInlineSkillDefinition` row: triggers `["/review"]`, route `.answer`, embedding `triggerDescription` covering "score / check / how will this perform."
- Pane renderer for `ReviewResult`: verdict header, evidence rows (comparable name + numbers), slide-anchored notes, top-3 moves, micro-variation chips on the weakest beat.
- Conversation continuity for follow-ups on the cached prefix.

### Phase 5 — `/riff` skill + apply path
- Skill row: triggers `["/riff", "/vary", "/variations"]`, selection-aware context, route `.answer`.
- Variation cards with mechanism labels + source comparable; per-card "Apply" → targeted diff via `CosmoInlineDiffLocator` → existing accept/reject UI.

### Phase 6 — Polish & feedback loop
- Settings panel: monthly spend, per-skill cost history.
- Learned-rule capture: when you reject/edit a recommendation, offer to append a rule.
- After 2–4 weeks of real use: decide whether the Railway cloud agent still earns its hosting bill.

### Explicit non-goals
- No deletion of UnifiedWritingEngine, the cloud agent, codex atoms, or the Codex UI (augment, don't replace). Retirement is a separate later decision.
- No absolute view-count predictions — relative, evidenced reads only.
- No auto-apply anywhere. Every text change goes through the reviewed-diff path.
