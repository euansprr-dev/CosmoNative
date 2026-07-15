# Swipe Niche Taxonomy — Canonical Niches + Cross-Platform Filtering

**Status:** SHIPPED · July 15, 2026 — all six phases implemented.
Key artifacts: `SwipeFile/NicheRegistry.swift` (registry + NicheMatcher),
`SwipeFile/SwipeNicheBackfill.swift` (consolidation, runs on next launch via
SwipeMediaMirrorCoordinator), `cosmo-cloud-agent/src/swipes/niche.ts` (worker
port), Swift tests `Tests/CosmoOSTests/NicheRegistryTests.swift`, worker tests
`tests/nicheMatcher.test.ts`. insightVersion bumped 3 → 4.
**Goal:** Every swipe gets classified into a *canonical* niche (core vertical like
"Real Estate Wholesaling", "Content Creation", "Health & Wellness", "Fitness").
The classifier never invents a near-duplicate of an existing niche, new niches
are created only when genuinely new, and the niche list drives filters in the
swipe library / studio on both macOS and iOS.

---

## 1. Current state (audited)

### The problem, measured
Local DB today: **330 swipes → 140 distinct free-text niches, 36 with none.**
Fragmentation examples from real data:
- "Real Estate Investing" (35) / "Real Estate Investment" (1) / "Airbnb Real Estate Investing" (11) / "Real Estate Investing - Airbnb" (3) / "Real Estate Investing - Short-Term Rentals" (1)
- "Personal Development" (15) / "Personal Development & Productivity" (3) / "Personal Development & Wealth" (2) / "Mindset & Personal Development" (2) / "Self-Improvement / Mindset Psychology" (1)
- "Tax Strategy & Vending Machine Business" (2) / "Tax Strategy & Vending Machines" (1)

Root cause: all three classification paths ask the LLM for a free-text label
(`Niche: A short label for the content vertical`) with no vocabulary, no
normalization, and no memory of previous answers.

### The three classification paths (all emit free-text `niche`)
| Path | File | Model | Owns |
|---|---|---|---|
| Railway worker | `cosmo-cloud-agent/src/swipes/analyze.ts` (`classify()` called from `processor.ts persistAndAnalyze`) | Gemini 3 Flash (OpenRouter) | instagram / youtube / twitter swipes (Railway-first policy in `SwipeProcessingService`) |
| Mac insight pass | `SwipeFile/SwipeInsightEngine.swift` (Sonnet 5, insightVersion 3) | Sonnet 5 | non-worker platforms + Study "Reanalyze" |
| Mac legacy unified | `SwipeFile/SwipeClassificationEngine.swift` | Gemini flash / ResearchService default | legacy callers, creator resolution, merge helpers |

### Existing infrastructure to build on (do NOT reinvent)
- **`taxonomy_value` atom type** (`AtomType.taxonomyValue`, `TaxonomyValueMetadata`
  in `Data/Models/Atom.swift:2233`) with `dimension` / `value` / `sortOrder` /
  `isDefault` / `usageCount` / `color`. `AtomRepository.fetchTaxonomyValues(dimension:)`
  and `createTaxonomyValue(...)` already exist. **Zero rows today.** Atoms sync
  Mac ↔ Supabase ↔ iOS through the normal pipeline; the worker reads/writes the
  same Supabase `atoms` table (`fetchAllByType('creator')` precedent in
  `analyze.ts resolveCreator`).
- **`BeatPatternService`** (`AI/BeatPatternService.swift`) is the proven template
  for exactly this problem: canonical vocabulary → injected into the prompt
  (`canonicalLabelsForPrompt`) → deterministic post-pass normalization
  (`normalizeBeats`: exact → known-variant → fuzzy ≥ 0.55 bigram-Jaccard) →
  variants recorded → `trackUsage`. Its only flaw for niches: it persists to a
  local JSON file, which can't be shared with iOS or the worker. Niches use the
  same *algorithm* with taxonomy atoms as the *store*.
- **Creator resolution** (`resolveCreator` on both Mac and worker) is the proven
  find-or-create + cache + bidirectional-consistency pattern for shared entities.
- **`SwipeAnalysis.preservingCuratedFields`**: manual taxonomy overrides
  (`classificationSource == .aiOverridden`) already survive re-analysis — niche
  included (`SwipeAnalysis.swift:393`).
- **macOS niche filter already exists** (`SwipeLibraryFilterState.niche`,
  `SwipeLibraryFiltering.availableNiches`, facet menu in
  `SwipeLibraryFilterPanel.creatorNicheSection`) — it's just useless with 140
  fragments. Canonicalization makes it work with near-zero UI change.
- **`TaxonomyManagementView`** already has a Niches tab that loads
  `taxonomy_value` atoms (currently always empty).
- **iOS** (`CosmoiOS/Sources/Swipes/SwipesView.swift`): filtering is board pills +
  text search only. `SwipeDisplay` (CosmoCoreKit `SwipeCapture.swift`) does not
  carry niche. iOS repo is XcodeGen — regenerate, never hand-edit pbxproj.

---

## 2. Architecture

### 2.1 The canonical store: `taxonomy_value` atoms, dimension `"niche"`
One atom per canonical niche. This is the single source of truth shared by Mac,
iOS, and the Railway worker — no new tables, no new sync surface, offline-capable,
and the existing TaxonomyManagementView + repository methods light up for free.

Extend `TaxonomyValueMetadata` (additive, Codable-safe, mirror in
`CosmoOS-iOS/CosmoCoreKit/Sources/Models/Atom.swift`):

```swift
struct TaxonomyValueMetadata: Codable, Sendable {
    // …existing fields…
    var aliases: [String]?        // raw labels normalized into this niche
                                  // (mirrors CanonicalBeat.originalVariants)
}
```

`SwipeAnalysis.niche` **stays a plain display string** — now always a canonical
value. No `nicheUUID`, no schema churn: every existing consumer (filter panel,
pattern weaver, search text, iOS lenient decode, worker JSON) keeps working with
zero migration. Rename/merge operations rewrite the affected swipes' strings
(the library is hundreds of atoms; a rewrite pass is cheap and explicit).

### 2.2 `NicheRegistry` (Mac) — the one brain for niche identity

New file `SwipeFile/NicheRegistry.swift`, `@MainActor`, modeled on
BeatPatternService + the creator cache in SwipeClassificationEngine:

```
resolve(raw: String) async -> String   // canonical display value
```

Resolution tiers (deterministic, in order):
1. **Exact** — case/whitespace-insensitive match on canonical `value`.
2. **Alias** — raw label already recorded in some niche's `aliases`.
3. **Fuzzy** — BeatPatternService-style similarity (substring containment +
   bigram Jaccard) against value AND aliases, threshold ≥ 0.60. Plus a
   niche-specific pre-pass: strip combo separators (`&`, `/`, `-` subtitles) and
   match on the head term, so "Tax Strategy & Vending Machines" folds into
   "Tax Strategy & Vending Machine Business" and "Real Estate Investing -
   Airbnb" folds into "Airbnb Real Estate Investing" — whichever canonical
   exists.
4. **Create** — clean the label (title-case, trim, cap ~4 words), create a new
   `taxonomy_value` atom via `AtomRepository.createTaxonomyValue` (which goes
   through the normal write path → sync queue; never raw SQL — see
   `orphaned_local_pending_shield`).

On tiers 2–3 the raw variant is appended to `aliases` and `usageCount` bumps
(field-level metadata update). A 60-second in-memory cache mirrors the creator
cache so batch processing doesn't refetch per swipe.

**Duplicate reconciliation:** worker and Mac can race to create the same niche
(same as creators). On registry load, detect case-insensitive duplicate values →
keep the older atom, fold the newer one's aliases/usage in, tombstone the newer.
Runs opportunistically; keeps the registry convergent without coordination.

Also exposed:
- `canonicalListForPrompt` — usage-ordered list injected into classification prompts.
- `rename(niche:to:)` / `merge(source:into:)` — update the atom, then rewrite
  `analysis.niche` on affected swipes via `updateFields(structured:)` with the
  curated-field merge (same single-write discipline as `persistAnalysis`).

### 2.3 Prompt changes — teach, then verify (all three paths)

Per `feedback_teach_not_tell` + `feedback_no_bandaids`: the LLM is *taught* the
vocabulary and the rules (systemic, state-based — the state being the live
registry), and the deterministic normalizer is the safety net, exactly like
canonical beats.

Replace the one-line niche instruction in **`SwipeInsightEngine.buildPrompt`**,
**`SwipeClassificationEngine.buildUnifiedPrompt`**, and the worker's
**`analyze.ts buildUnifiedPrompt`** with:

```
niche — the content's core vertical.
EXISTING NICHES (choose one of these whenever it fits — matching an existing
niche is strongly preferred): {canonical list, usage-ordered}
Only introduce a NEW niche when the content genuinely belongs to a vertical not
represented above. A niche is a CORE CATEGORY someone builds an audience in
("Fitness", "Content Creation", "Real Estate Wholesaling") — never a sub-topic,
a combo ("X & Y", "X / Y"), or a hook-level description. If the content spans
two verticals, pick the one the creator's audience follows them for.
```

The worker's prompt takes the list as a new `AnalyzeContext` field so
`buildUnifiedPrompt` stays a pure function (its tests keep passing with an empty
list).

### 2.4 Post-parse normalization (the deterministic net)

- **Mac:** in `SwipeInsightEngine.analyze` (and `SwipeClassificationEngine.classifyAndAnalyze`),
  after parsing: `analysis.niche = await NicheRegistry.shared.resolve(raw:)`.
  `preservingCuratedFields` continues to protect `aiOverridden` niches unchanged.
- **Worker:** new `src/swipes/niche.ts` — a port of the resolve tiers against
  Supabase `taxonomy_value` atoms (`fetchAllByType('taxonomy_value')` filtered to
  `metadata.dimension === 'niche'`), with the same in-process TTL cache and the
  same create-on-miss via `createAtom`. Wired into `processor.ts
  persistAndAnalyze` between `classify(ctx)` and `buildAnalysisJSON` (pass the
  resolved canonical string in, exactly like `creatorUUID` is passed today).
  Same string-similarity functions ported 1:1 (Mac Swift ↔ worker TS parity, the
  established porting convention in `analyze.ts`'s header).

### 2.5 One-time consolidation backfill (fixes the existing 140)

New `SwipeFile/SwipeNicheBackfill.swift`, one-shot behind an `app_flags` gate
(same pattern as `SwipeTitleBackfill`):

1. Collect distinct raw niches + counts from local swipes (the 140).
2. **One Sonnet call**: "Cluster these raw labels into core niches. Prefer 10–20
   broad verticals. Return JSON: `[{canonical, rawLabels[]}]`" — with the same
   core-category rules as the classification prompt. LLM does semantics;
   deterministic code does everything after.
3. Create/seed the `taxonomy_value` atoms (canonical value + rawLabels as
   aliases + usage counts). Seeds double as the fuzzy-match corpus forever after.
4. Rewrite each swipe's `analysis.niche` to its canonical value — field-level
   `updateFields(structured:)` after a fresh fetch + `preservingCuratedFields`
   merge (never clobber concurrent edits; `aiOverridden` swipes get the same
   value-level mapping — the user's chosen label still normalizes, their
   *choice* of override is preserved).
5. The 36 null-niche swipes are left for the existing Reanalyze path — no
   special machinery.

Because taxonomy atoms and swipe rewrites all flow through the normal sync
pipeline, iOS and the worker converge on the canonical vocabulary automatically.

### 2.6 Filters & UI

**macOS library** (mostly free):
- `SwipeLibraryViewModel.availableNiches` switches from "distinct strings in
  items" to the registry's canonical list intersected with in-library values,
  usage-ordered. The existing facet menu in `SwipeLibraryFilterPanel` needs no
  structural change.
- Keep single-select `niche: String?` — the existing contract.

**macOS Study details rail** (`SwipeStudyDetailsSection.nicheRow`):
- Upgrade the read-only pill to a dropdown in the existing
  `taxonomyDropdownRow` grammar: canonical niches (usage-ordered) + "New niche…"
  input that routes through `NicheRegistry.resolve`. Selection sets
  `classificationSource = .aiOverridden` via the existing
  `SwipeStudyModel` taxonomy-override path (`taxonomyOverride` persist).

**macOS Taxonomy Management** (`TaxonomyManagementView`, Niches tab):
- Now lists real canonical niches with live usage counts.
- Add **Rename** and **Merge into…** actions (calling
  `NicheRegistry.rename/merge`, which handle the swipe rewrites). Archive
  already exists.

**iOS** (`SwipesView` + CosmoCoreKit):
- `SwipeDisplay` gains `niche: String?`, decoded inside `computedSwipeDisplay`
  from `structured.swipeAnalysis.niche` (already-decoded JSON dict is at hand;
  memoization means zero extra per-frame cost).
- Filter UI honoring the established grammar ("board pills are objects, not
  abstract filters"): a **second, visually quieter chip row for niches** under
  the board pills — chips are the canonical niches present in the current scope,
  usage-ordered, single-select, combining AND-style with board + search in the
  existing `filtered` computed property. No new sheet, no new navigation.
- Regenerate the Xcode project via XcodeGen after adding files.

### 2.7 What deliberately does NOT change
- `SwipeAnalysis` schema (niche stays `String?`) — both platforms.
- Railway-first ownership policy, single-write discipline, curated-field merge.
- Narrative/format/hookType enums and their filters.
- `BeatPatternService` (beats stay file-local; they're Mac-only analysis internals).

---

## 3. Implementation phases

**Phase 1 — Registry + model plumbing (Mac)**
`TaxonomyValueMetadata.aliases`, `NicheRegistry.swift` (resolve tiers, cache,
prompt list, reconciliation, rename/merge + rewrite), unit tests for the
matcher (exact/alias/fuzzy/combo-split/create + duplicate reconciliation).

**Phase 2 — Classifier integration**
- Mac: prompt injection + post-parse resolve in `SwipeInsightEngine` and
  `SwipeClassificationEngine`; bump `insightVersion` → 4.
- Worker: `src/swipes/niche.ts` + `AnalyzeContext.canonicalNiches` + wiring in
  `processor.ts`; TS tests mirroring the Swift matcher tests (parity fixtures).
- Deploy worker (Railway root = `cosmo-cloud-agent`).

**Phase 3 — Consolidation backfill**
`SwipeNicheBackfill` one-shot: cluster call → seed registry → rewrite swipes.
Verify counts: distinct niches collapses 140 → ~10–20; spot-check the
real-estate cluster.

**Phase 4 — macOS UI**
Library facet source swap (usage-ordered), Study niche dropdown + override,
Taxonomy Management rename/merge.

**Phase 5 — iOS**
`SwipeDisplay.niche`, niche chip row + filter predicate, XcodeGen regenerate,
build.

**Phase 6 — Verification**
`swift test --filter` new suites; `xcodebuild` both apps; end-to-end: capture a
fresh IG reel → worker classifies against the seeded list → niche lands
canonical on Mac + iOS → filter chip shows it.

## 4. Risks & mitigations
- **Concurrent niche creation (worker vs Mac):** find-or-create races → load-time
  duplicate reconciliation (§2.2). Same accepted risk profile as creators today.
- **LLM ignores the list:** deterministic resolve catches near-misses; genuine
  new labels are *supposed* to create niches. The combo-split pre-pass kills the
  worst historical failure mode ("X & Y" mashups).
- **Registry unavailable on worker (Supabase hiccup):** resolve falls back to
  passing the raw label through (current behavior) — never blocks processing;
  the Mac-side resolve normalizes it on next touch, or reconciliation folds it.
- **Backfill clobbering live edits:** fresh-fetch + `preservingCuratedFields` +
  field-level `structured` write — the exact `persistAnalysis` discipline.
