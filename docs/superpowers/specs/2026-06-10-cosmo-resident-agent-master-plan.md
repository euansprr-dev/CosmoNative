# Cosmo Resident Agent — Master Plan

> **Implementation status (2026-06-10):** Phases 1–5 implemented in one pass; Phase 6 partially (phase-driven orb states, example-taught personality; full character-sheet editor + metrics HUD deferred).
>
> - **Phase 1 (speed & spine):** real Anthropic SSE streaming (`completeStreamingEvents` with tool-arg deltas); OpenRouter streaming now keeps `cache_control` blocks; cache-ordered prompt split (static instructions cached, volatile context post-breakpoint via `volatileContextOverride`); pinned inline intents (`.correct`/`.analyze`) replacing keyword-classification noise; deterministic tool-bundle ordering; `LLMCacheTelemetry` rolling read-ratio; pre-warm on orb hover + surface registration (`CosmoInlineAssistantCacheWarmer`); live pane-answer streaming decoded from partial `answer_in_assistant_pane` JSON (`LLMPartialToolArguments`); typed `CosmoInlineAssistantPhase` machine + verb-first status grammar.
> - **Phase 2 (hands):** locator fallback chain extended (paragraph-anchored + bounded unique fuzzy, conflict-over-guess) with property tests; editable surfaces wired for Idea (body + hook anchors), Synthesis workspace, Canvas note/sticky blocks (atom-backed, GRDB-observation refresh); atom-backed fallback applier so proposals apply when the target isn't open; `append_to_note` tool (UUID or fuzzy title). Inquiry rail deliberately skipped (structured capture-routing, no free-text body).
> - **Phase 3 (craft):** `inline_assistant_skills` GRDB table + store with one-time UserDefaults migration; skill definitions gained `triggerDescription`, `examples` (input→ideal-output, injected into the skill prompt), `verification` post-conditions; embedding auto-routing via local nomic daemon with ghost chip + Tab-to-accept (`CosmoInlineSkillAutoRouter`, ambiguity refuses); `/New Skill` builder built-in (interview ≤4 questions, dry-run before save); proposals stamped with `skillID`, accept/reject feeds `AgentOutcomeTracker` under `skill:<id>`.
> - **Phase 4 (sight & legs):** `CosmoInlineAmbientContextPack` prefetches related work on surface activation into the volatile prompt layer; unified `recall` tool over the whole atom graph; `.navigation` tool bundle (`open_atom`, `go_to_thinkspace`, `go_to_area`, `focus_canvas_block`); `CosmoNotification.Canvas.focusBlock` + `CanvasViewportTransform.centeringOffset` camera glide.
> - **Phase 5 (synthesis):** `/Synthesize` built-in skill — gather (recall + ambient digest) → outline in pane → section-by-section reviewed diffs with per-section source citations in rationales.
> - **Deferred items — implemented in second pass (same day):**
>   - **Assistant Studio** (`UI/InlineAssistant/CosmoAssistantStudioView.swift`, opened from the slash menu → "Assistant Studio..."): three tabs — *Skills* (custom skills: enable/disable, edit name/summary/trigger description/phrases/route/model tier/instructions/verification, delete; built-ins read-only with "Duplicate" to fork an editable copy; per-skill accept rates from `AgentOutcomeTracker` `skill:<id>` events), *Personality* (live character-sheet editor backed by `CosmoInlineAssistantPersonalityStore`, byte-stable into the cached prefix, reset-to-default), *Metrics* (cache read ratio, avg TTFT, avg proposal latency, accept rate, conflict rate, activity counts via `CosmoInlineAssistantMetrics`).
>   - **Context chips:** `CosmoAssistantSourceRef` recorded by the executor (`recall` hits) + ambient-pack refs, attached to pane answers/proposal messages, rendered as clickable chips ("Sources") that open the atom as a pane.
>   - **Pane UI polish (peakui pass):** `CosmoInlineAssistantPaneView` rebuilt — answers render as plain prose (content-as-hero, reading measure, selectable, line spacing) with source chips underneath; user prompts are quiet accent-washed chips; system titles are small-caps labels; the thinking row is phase-aware (orb symbol vocabulary + verb-first status, Reduce Motion gated); auto-scroll follows new messages and streaming growth; teaching empty state with three starter chips; proposal cards gained a decision bar (Accept all / Reject all) plus hover-lifted pill buttons; composer uses `dsGlassInput` focus styling, Return sends, Esc closes. All typography through DS tokens, all motion through ProMotionSprings.
>   - **Skills Supabase sync:** evaluated and *correctly remains deferred* — no client-side custom-table sync engine exists (atoms sync via `Syncable`; `custom_agent_profiles` has the same dormant `_sync` columns). The skills table ships with sync columns ready; actual sync needs server schema + a table-sync engine, out of scope for a client-only change.

**Date:** 2026-06-10
**Scope:** Inline assistant revamp — personality, skills, universal inline editing, retrieval, navigation, Haiku 4.5 + Anthropic caching, thinking states, synthesis pipeline.
**Thesis:** Cosmo wins not by having a smarter model than ChatGPT, but by fusing the assistant into the three layers no general AI can touch: the **data model** (atoms + links + embeddings), the **render layer** (canvas, focus modes, diffs), and the **capture pipeline** (swipes, research, ideas). This plan turns the inline assistant from a feature into the app's nervous system.

---

## 0. Current state (verified against code, 2026-06-10)

### What exists and is good
- **Inline assistant** (`UI/InlineAssistant/`, ~5,500 lines): bottom orb + morphing composer + side pane, 8 built-in skills, slash menu, route system (`.action` stages diffs / `.answer` goes to pane), working-context cache (600s TTL), proposal/operation model with `sourceHash` staleness detection.
- **Diff system**: `CosmoInlineDiffLocator` (exact → whitespace-normalized matching), `CosmoInlineDiffReviewView` (red strikethrough / green additions in-editor), per-op + global accept/reject, `inverseOperation()` revert.
- **Surface protocol**: `CosmoEditableSurfaceProvider` (snapshot / apply / reject) + weak registry. Wired: Note, Content, Connection (partial).
- **Agent core**: shared `CosmoAgentService` (responseMode `.inlineAssistant`, early-exit on `propose_workspace_edit` / `answer_in_assistant_pane`), 50+ tools, 4-layer context assembler with `cache_control` on static layers.
- **Retrieval**: `HybridSearchEngine` — FTS5 BM25 pre-filter → 256-dim nomic vector rerank (daemon XPC), 70/30 blend. `EmbeddingCache` (1h), `QueryResultCache` (5m), `HotContextCache` exist.
- **Personality**: a good-but-thin "sharp, chill creative friend" block in `CosmoInlineAssistantInstructionPrompt`.

### Verified problems
| # | Problem | Evidence |
|---|---------|----------|
| P1 | **Default model is Gemini Flash, not Haiku** | `CosmoAgentService.defaultModelTier(for:)` returns `.geminiFlashLatest` for ALL intents. Only `inlineEdit`/`factFill` skills override to `.sensor`. Mixed providers per-request → Anthropic cache never warms, personality drifts between models. |
| P2 | **AnthropicProvider does not stream** | `LLMProviderAdapter.swift:1027` — delegates to non-streaming. The whole response latency is paid before the first token shows. |
| P3 | **Cache-hostile prompt assembly** | Inline path injects compact context block + skill plan + working context + instructions per-request into the system prompt. Volatile bytes early in the prefix invalidate everything after. No `cache_read_input_tokens` telemetry. Stale beta header `prompt-caching-2024-07-31` (caching is GA). |
| P4 | **6 of 9 surfaces can't take inline edits** | Idea (context/hooks/outline), Canvas blocks, Inquiry notes, Synthesis, Research annotations unwired. The "same diff UI everywhere" promise is 1/3 delivered. |
| P5 | **Skills stored in UserDefaults** | `cosmo.inline.skills.custom.v1`. No sync, no linking, no search, design doc's GRDB table unimplemented. No builder UI, no examples field, no skill-scoped learning. |
| P6 | **Keyword-heuristic skill routing** | `CosmoInlineAssistantSkillRuntime.plan()` matches substrings ("variation", "canvas"). Brittle; embeddings sit unused for this. |
| P7 | **No navigation tools** | Agent can propose canvas plans but cannot open an atom, fly the camera, or take you anywhere. All the `CosmoNotification.Navigation` plumbing exists, unexposed. |
| P8 | **Context fetched reactively** | Every request that needs client/voice/related-atoms context pays tool round-trips at ask-time instead of being prefetched when the surface activates. |
| P9 | **Thinking states are generic** | "Working…" + compacted tool labels. No state taxonomy, no personality in the narration. |

---

## 1. North-star architecture

Five faculties, one agent:

```
                    ┌─────────────────────────────────────────────┐
                    │            COSMO RESIDENT AGENT             │
                    │  (one Anthropic conversation, Haiku spine)  │
                    └─────┬──────┬──────┬──────┬──────┬───────────┘
                          │      │      │      │      │
                       SIGHT  MEMORY  HANDS  LEGS  CRAFT
                          │      │      │      │      │
              surface snapshot  atoms  diff   nav   skills
              ambient pack      links  apply  tools  + lessons
              canvas state      lessons everywhere camera
```

- **Sight** — ambient context pack: the agent already knows what you're looking at before you ask.
- **Memory** — atom graph + embeddings + lessons, served through one high-signal `recall` tool.
- **Hands** — `CosmoEditableSurfaceProvider` on every surface; one diff UI; proposals only, never silent mutation.
- **Legs** — navigation tool bundle riding existing notifications + a new camera-focus primitive.
- **Craft** — skills as durable, evolvable operating modes with examples, verification, and attached lessons.

Underneath: **one provider (Anthropic), one spine model (Haiku 4.5), a byte-stable cached prefix, real streaming.**

---

## 2. Pillar 1 — The cognition core (Haiku 4.5 + caching + streaming)

### 2.1 Consolidate on Anthropic for the inline path
- Inline assistant default tier → `.sensor` (claude-haiku-4-5, $1/$5 per MTok, 200K ctx).
- Escalation (contentReview, voiceVariations, synthesis judgment) → Sonnet via a **separate scoped call** (subagent pattern), not a mid-conversation model switch — switching models invalidates the whole cache.
- Gemini Flash stays for Telegram pre-routing (FlashLiteRouter); it never touches the inline path.

### 2.2 Cache-ordered prompt assembly (the big one)
Restructure to strict stability ordering. Anthropic render order is `tools → system → messages`; any byte change invalidates everything after it.

```
[CACHED PREFIX — byte-stable, ≥4096 tokens (Haiku minimum), 1h TTL]
  1. Tool definitions          (deterministic order, sorted by name)
  2. Identity + personality    (frozen "character sheet", versioned)
  3. Output contracts          (proposal JSON shape, diff rules)
  4. Skill library INDEX       (name + trigger description per skill —
                                changes only when user edits skills)
  ── cache_control: ephemeral, ttl 1h ──
[PER-CONVERSATION — cached incrementally, 5m TTL]
  5. Conversation history      (breakpoint on last appended turn)
[PER-REQUEST — never cached, lives in the FINAL user message]
  6. Surface snapshot (text, selection, sourceHash)
  7. Resolved skill context (client profile, voice, evidence)
  8. Selected skill's FULL instructions + examples
  9. User prompt
```

Key rules:
- **Selected-skill instructions go in the user turn, not the system prompt.** Injecting them into system text re-keys the prefix per skill. In the final message they cost nothing cache-wise.
- **No timestamps, UUIDs, or unsorted JSON** anywhere in layers 1–4 (silent invalidators).
- **Telemetry**: log `cache_read_input_tokens` / `cache_creation_input_tokens` per request; dashboard target ≥85% read ratio. If reads are 0, a silent invalidator regressed.
- Remove the stale `prompt-caching-2024-07-31` beta header.

**Economics**: ~6–8K-token prefix. Uncached: ~$0.007/request input. Cached: write once at 1.25–2×, then ~$0.0007/read. A heavy day of 200 inline interactions ≈ $0.50 in input. Output dominates anyway → which is why streaming matters more than anything.

### 2.3 Real SSE streaming for AnthropicProvider
- Implement `StreamingLLMProvider` for Anthropic (`content_block_delta` events).
- Stream pane answers token-by-token; stream proposal assembly structurally (operation list materializes as tool-input JSON streams).
- Cache reads also slash time-to-first-token — the cached prefix isn't re-processed.

### 2.4 Cache pre-warming
- On surface activation (focus mode open, note focused) and on orb hover, fire a `max_tokens: 0` warm request against the current prefix. Costs one cache write, makes the first real keystroke-to-token feel instant.
- Skip when a request happened < 4 minutes ago (cache still warm).

### 2.5 Latency budget (the contract)
| Phase | Target p50 |
|---|---|
| Keypress → request out (context pre-resolved) | < 50ms |
| Request → first streamed token (warm cache) | < 600ms |
| Inline edit proposal fully staged | < 2.5s |
| `/skill` answer first token | < 800ms |

---

## 3. Pillar 2 — Personality as a system, not a paragraph

Personality = consistency across four channels. Research-backed rules: positive instructions over prohibitions; explain WHY so the model generalizes; teach with 3–5 examples, not adjectives; no aggressive "CRITICAL/MUST" (modern Claude overtriggers).

### 3.1 The Character Sheet (frozen, cached, versioned)
A single `CosmoCharacterSheet` document, stored in GRDB, rendered byte-identically into cached layer 2:
- **Voice**: sharp, chill creative friend — kept, but taught through 4–6 paired examples (bad reply → Cosmo reply) instead of adjective lists. Examples are the highest-leverage upgrade for Haiku, which imitates far better than it abstracts.
- **Behavioral norms**: when to push back (thin evidence, weak hooks — with one worked example), when to ask (never for minor choices; only scope changes/destruction), when to stay silent.
- **Knowledge honesty**: never invent client facts/metrics/voice; cite which context was actually used.
- User-editable in settings (sliders → regenerated sheet → new version → cache re-warms once). Versioning means personality changes are deliberate, not drift.

### 3.2 Narration grammar — thinking states ARE the personality
Replace generic "Working…" with a typed state machine, each state with its own micro-copy voice and orb animation:

```
idle → listening → planning → gathering → drafting → reviewing → applied
                      │           │           │
                 skill chip   per-tool     streaming
                 glows        status lines  tokens
```

- **Gathering** lines are generated from tool activity with a status grammar: `<verb-ing> <object in user's vocabulary>` — "Reading your draft", "Checking Hormozi's voice profile", "Pulling 3 swipes on curiosity hooks". Built from tool name + arguments client-side (no LLM cost), ≤72 chars (existing compactor).
- **Silence default for action routes**: terse craftsman — status lines only, then the diff. **Conversational register for answer routes**: the friend. This split mirrors how the best coding agents calibrate narration and is encoded in route-specific instructions.
- Orb states: breathing (idle) → ripple (listening) → spin-shimmer (planning) → pulse-per-tool (gathering) → text-flow shimmer (drafting) → green ring (reviewing). All through `peakui` / ProMotionSprings.

### 3.3 Continuity
- Personality requires memory: the agent references prior sessions naturally ("same angle as your retention thread last week") via lessons + conversation summaries already in context. Add accepted/rejected proposal outcomes to `AgentOutcomeTracker` so Cosmo learns the user's taste *and can say so*.

---

## 4. Pillar 3 — Skills as the operating system

A skill = a contract, not a prompt snippet:

```swift
struct CosmoInlineSkillDefinition {   // upgraded
    id, name, icon, summary
    triggerDescription: String        // for embedding-based routing
    triggerPhrases: [String]
    route: .action | .answer
    modelTier: AgentModelTier         // Haiku default, Sonnet for judgment
    requiredContext: [ContextKind]    // pre-resolved before the call
    toolBundles: [AgentToolBundle]
    instructions: [String]
    examples: [SkillExample]          // NEW — input → ideal output pairs
    outputContract: String
    verification: String?             // NEW — post-conditions checked before staging
    panePolicy, tokenBudget, isEnabled, version, createdAt, updatedAt
}
```

### 4.1 Durable storage + sync
- Migrate UserDefaults → GRDB table `inline_assistant_skills` (already spec'd in the 2026-06-09 design doc) → Supabase sync. Skills become first-class, linkable, searchable data.
- Built-ins ship as seed rows; user edits create overrides (never mutate seeds — reset is always possible).

### 4.2 Embedding-based auto-routing (zero-LLM, instant)
- Embed each skill's `triggerDescription + summary + triggerPhrases` via the existing nomic daemon at save time; store the 256-dim vector on the row.
- On composer input (debounced), embed the prompt (EmbeddingCache makes repeats free) → cosine match → if top score > threshold, show a **ghost chip** ("Fact Fill?") the user can Tab to confirm. Explicit `/slash` always wins.
- Kills the brittle substring heuristics in `plan()`; routing accuracy compounds as users write trigger descriptions in their own vocabulary.

### 4.3 Conversational skill builder (`/new-skill`)
- Built-in skill, runs on Sonnet, `panePolicy: .alwaysOpenWithResult`.
- Interview (≤4 questions): what should it do, when should it trigger, what does great output look like, what context does it need.
- Drafts the full definition **including examples** — it asks the user to paste or point at one great example ("show me a reel script you loved") and synthesizes the contract from it.
- **Dry-run before save**: executes the draft skill against the current surface as a normal proposal. The user sees the actual diff/answer it would produce, then saves, tweaks, or discards. Skills are born tested.
- `create_inline_skill` tool (already registered) persists it; appears in the slash menu immediately.

### 4.4 Skills that learn
- After any skill run, accept/reject/edit outcomes attach as **skill-scoped lessons** (existing `save_lessons` machinery, new scope key `skill:<id>`). Next invocation injects the top lessons into the per-request block (post-cache, cheap).
- A skill detail view shows its lessons; users can promote a lesson into the skill's permanent instructions ("crystallize").
- This is the moat: after a month, the user's `/reel-script` skill is unreproducible anywhere else.

### 4.5 Skill management UI
- Pane "Skills" tab: list (built-in + custom), enable/disable, edit, duplicate, model-tier badge, run count, accept rate. Slash menu shows model badges (design doc parity).

---

## 5. Pillar 4 — Universal inline editing (the diff, everywhere)

### 5.1 Wire every surface (protocol exists; this is conformance work)
| Surface | Work |
|---|---|
| **Idea** (context, hooks, outline notes) | `IdeaEditableSurfaceProvider` — context body as `.text`; hooks + outline as `.structuredFieldReplacement` ops keyed by stable field IDs |
| **Canvas blocks** (notes, stickies) | `CanvasBlockSurfaceProvider` registered per focused/selected block; surfaceID `canvasBlock:<uuid>` |
| **Inquiry notes rail** | confirm/complete provider, surfaceID `inquiry:<uuid>` |
| **Synthesis workspace** | text provider over synthesis body |
| **Connection** | finish structured-field apply path + tests |
| **Research** | annotations only (transcript stays read-only) — insertion ops into annotation list |

- Build a `CosmoDiffReviewHost` wrapper so any provider gets in-editor diff rendering for free; a new surface should be ~50 lines.

### 5.2 Locator hardening (apply reliability is the product)
Extend `CosmoInlineDiffLocator` fallback chain:
1. exact → 2. whitespace-normalized (existing) → 3. **paragraph-anchored**: match the op's surrounding context lines, then locate within → 4. **bounded fuzzy**: Levenshtein ≤ ~10% of needle length, single candidate only → else `.conflicted` (never guess).
- Property tests: random doc mutations (smart quotes, re-wraps, emoji, concurrent edits) must locate or conflict — never mis-apply. This addresses the known reliability gap (see memory: apply reliability needs the locator in every surface's apply path).

### 5.3 Cross-surface and append operations
- Proposals already carry per-op `targetID` — route ops to different surfaces/atoms in one proposal ("split this note into three": one source edit + two `create` ops).
- New lightweight tools: `append_to_note(uuid, text, position)`, `create_note_with_content` — staged as insertion ops so the same review UI covers "add this to my swipe-learnings note" from anywhere in the app.

---

## 6. Pillar 5 — Retrieval that feels telepathic

### 6.1 Ambient context pack (prefetch, don't fetch)
- On surface activation, a background task assembles a pack: active atom + linked atoms (1 hop) + client profile + top-5 `searchRelatedToContext()` results + relevant lessons → stored in `HotContextCache` keyed by surfaceID.
- The inline request includes the pack's compact digest in the per-request block. The common case ("tighten this hook") needs **zero tool round-trips**.
- Refresh on save debounce; TTL aligned with working-context cache (600s).

### 6.2 One `recall` tool for the inline path
- Haiku picks better from few tools than many. Inline requests get: `recall(query, kind?, clientName?, limit)` wrapping HybridSearchEngine + repository lookups, returning compact high-signal results (title, type, snippet, uuid, updatedAt — semantic names, no opaque blobs).
- The 50-tool registry stays for the full agent; inline tool surface = recall + propose_workspace_edit + answer_in_assistant_pane + navigation + skill-declared bundles.

### 6.3 Trust UI — context chips
- Pane answers and proposals show chips for every source actually read ("Hormozi profile", "3 swipes", "Retention thread"). Click → opens the atom. Anti-hallucination made visible; also a navigation affordance.

### 6.4 Index hygiene
- Vector stage is O(n) over `semantic_chunks`; fine now, so just instrument it. If p95 > 150ms at scale, shard by entity_type or add an IVF-style coarse quantizer — decision deferred until telemetry says so.

---

## 7. Pillar 6 — Legs: visual navigation

### 7.1 Navigation tool bundle (thin wrappers over existing notifications)
- `open_atom(uuid, mode: focus|pane|canvas)` → `Navigation.openBlockInFocusMode` / `openAsPane` / `NodeGraph.addToCanvas`
- `go_to_thinkspace(uuid)` → `navigateToThinkspaceById`
- `go_to(area: commandCenter|library|inbox|plannerum|sanctuary)`
- `focus_block(uuid)` → NEW camera primitive
- `show_search_results_on_canvas(query)` → existing `place_search` op
- All reversible → no confirmation friction. Mutations remain proposal-gated.

### 7.2 Camera primitive
- `CanvasViewportTransform.animate(to: blockFrame, padding:)` — springs `committedOffset`/`committedScale` to frame a block/cluster. Needed for "show me", and for **guided tours**: "where did I save that pricing research?" → Cosmo answers AND the canvas glides to the cluster, blocks pulse once.

### 7.3 Why this matters
Spatial memory is the canvas's whole premise. An assistant that *answers about* your space is a search box; one that *moves through* it with you is a colleague. No general AI can do this — it requires owning the render layer.

---

## 8. Pillar 7 — The synthesis flagship (`/synthesize`)

The app's stated purpose: research → save → structure → **synthesize into outputs**. One skill family makes the whole machine visible:

1. **Gather** — `recall` + link traversal collects sources for a topic; places them as a canvas cluster (visible working set, user can add/remove blocks = curating the agent's context spatially).
2. **Structure** — proposes an outline as a structured proposal into a new Note/Content atom (reviewable, editable like any diff). Sonnet call (judgment work).
3. **Draft** — writes **section-by-section** as sequential inline proposals into the draft surface. Each section: one reviewable diff, one cacheable Haiku/Sonnet call, with the conversation prefix compounding (each section's call reuses the cached sources + outline).
4. **Cite** — every section carries context chips back to source atoms; click-through verification.

Variants ship as skills: `/newsletter`, `/chapter`, `/thread` — same engine, different output contracts + examples. Section-wise drafting is deliberately the cache-and-review-friendly shape: no 5,000-token wall of unreviewable slop, no blown latency budget.

---

## 9. What gets measured (the assistant's own scorecard)
- **Cache read ratio** (target ≥85%), TTFT p50/p95, proposal-staged p50.
- **Apply success rate** (located vs conflicted), **accept rate** per skill, edit-after-accept rate (slop detector).
- **Tool round-trips per request** (target: 0 for ambient-pack-covered asks).
- Surface in a debug HUD + weekly digest. These numbers are the definition of "most efficient AI assistant," not vibes.

---

## 10. Phasing

| Phase | Contents | Why first |
|---|---|---|
| **1. Speed & spine** (foundation) | Anthropic default for inline, SSE streaming, cache-ordered prompt assembly, pre-warm, cache telemetry, status-grammar thinking states | Everything else inherits the latency + cost win; perceptually 3–5× faster immediately |
| **2. Hands everywhere** | Idea/Canvas/Inquiry/Synthesis providers, DiffReviewHost, locator hardening + property tests, append tools | Delivers the user-visible promise: same diff UI in every surface |
| **3. Craft** | GRDB skill storage + sync, examples field, embedding auto-routing + ghost chip, `/new-skill` builder with dry-run, skill-scoped lessons, management UI | The moat; depends on Phase 1's prompt structure |
| **4. Sight & legs** | Ambient context pack, `recall` tool, context chips, navigation bundle, camera primitive | Telepathic retrieval + guided navigation |
| **5. Synthesis flagship** | `/synthesize` family, multi-atom proposals, canvas-guided gathering, citations | The demo that *is* the product thesis |
| **6. Character & polish** | Character sheet editor, orb state animations (peakui), scorecard HUD, personality example tuning | Continuous from Phase 1; formalized last |

Each phase is independently shippable; 1→2 are the highest ROI-per-line in the codebase.

---

## 11. Risks & mitigations
- **Haiku quality ceiling on judgment tasks** → examples in skills (Haiku imitates well), Sonnet escalation per skill tier, verification post-conditions before staging.
- **Cache regression via accidental invalidators** → telemetry alarm on read-ratio drop; assembly code keeps stable layers in a single frozen renderer with a unit test asserting byte-stability across two renders.
- **Locator mis-applies** → bounded fuzzy only with unique candidates; conflict is always preferred over guess; property tests in CI.
- **Skill sprawl** → ghost-chip routing degrades gracefully (falls back to researchAnswer); management UI surfaces accept-rate so dead skills are visible.
- **Provider lock-in** → tier abstraction stays; only the inline *default* is pinned to Anthropic for cache coherence.
