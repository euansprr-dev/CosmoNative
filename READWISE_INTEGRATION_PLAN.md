# Readwise → Cosmo: Highlights as Evidence

*July 17, 2026. Implemented same day — see §10 for what shipped and how the
plan was reconciled with the pre-existing Readwise stack (ReadwiseService +
the Command-K Library tab), which this plan had missed.*

---

## 1. The ask, and the trap to avoid

Everything highlighted in Readwise (books, articles, Kindle, tweets) should land
in Cosmo's knowledge pipeline — above all, it should be **in the room when a
concept is being developed**: "everything I highlighted in different books is
part of that conversation and points of inspiration."

The trap is the inbox. Hundreds of highlights syncing into the triage queue
would destroy the queue's hard-won contract (INBOX_REVAMP_PLAN §1: *an item
appears in the Inbox iff it was explicitly captured — nothing the user didn't
throw there*). A Readwise highlight was thrown at Readwise, not at Cosmo.
Euan's own instinct agrees: "I don't know if it should land in the inbox
directly, since that would be a lot of stuff."

The second trap is the Seedbed. Seedlings hold the **user's own words** —
claims-in-waiting, the material of the generation effect. A highlight is
someone else's words: it is *evidence*, not a thought. Highlights must never
silently become seedling thoughts.

So the design in one line: **Readwise is a mirrored evidence library that the
knowledge graph reaches into — never a queue to triage, never a bed of
thoughts.**

## 2. Design principles

1. **Highlights are evidence.** They surface wherever evidence is wanted
   (development conversations, connection sources, seedling tending) and
   nowhere that demands a decision per item.
2. **Offered, never auto-filed.** The organize-don't-author line holds: a
   highlight enters a page only through the existing staging grammars (cited
   bullets in the collaborator, ✓/✗ ghost rows) after the user accepts it.
3. **Mirror, not fork.** Readwise stays the source of truth for highlight
   text. Cosmo upserts and prunes from the API; Cosmo-side editing of
   highlight text is out of scope (notes/links Cosmo adds live in Cosmo).
4. **Zero new sync machinery.** Books ride the atoms table; the iPhone gets
   every highlight for free through existing atom sync.

## 3. The API (verified July 2026)

- `GET https://readwise.io/api/v2/export/` — the sync endpoint Readwise
  recommends. Auth header `Authorization: Token <token>` (user token from
  readwise.io/access_token).
- First run: no params, paginate via `nextPageCursor`. Incremental:
  `updatedAfter=<ISO8601 of last sync>` + `includeDeleted=true` so removals
  prune the mirror.
- Per book: `user_book_id`, `title`, `author`, `category` (books / articles /
  tweets / podcasts), `source`, `cover_image_url`, `highlights[]`.
- Per highlight: `id`, `text`, `note`, `location`, `highlighted_at`,
  `updated_at`, `color`, `tags`, `is_deleted`, `readwise_url`.
- Rate limit 240 req/min on export — irrelevant at our polling cadence.
- Readwise **Reader** (saved articles) has a separate v3 API — explicitly out
  of scope for v1 (see §8).

## 4. Data model — one atom per book, highlights in structured

The swipe-file pattern, reused: one `.research` atom per Readwise
book/article, never one atom per highlight (thousands of library-polluting
rows), never a new synced table (nothing here needs one).

- `metadata.subtype = "readwise"`, `metadata.readwiseBookId`,
  `metadata.readwiseCategory`, `metadata.author`, `metadata.coverImageUrl`,
  `metadata.readwiseUrl`.
- `structured` = `ReadwiseSourceStructured { highlights: [ReadwiseHighlight] }`
  — a faithful mirror of the API fields per highlight (id, text, note,
  location, highlightedAt, tags, color), tolerant decode like every shared
  contract.
- `title` = readable title; `body` = concatenated highlight text → the atom
  indexes into hybrid search and the recall index **for free** (⌘K finds "that
  line about attention from Deep Work" immediately).
- Upsert by `readwiseBookId`; per-highlight dedup by highlight `id`;
  `is_deleted` highlights are removed from structured; a book whose highlights
  all vanish soft-deletes.

**Two exclusions, both load-bearing:**

1. **Never a merge/triage target.** Add `metadata.subtype == "readwise"` to
   the same defensive exclusion that keeps agent conversations out of
   `bestMergeRecommendation` and the inbox candidate pool
   (`InboxRoutingEngine`). A mirror the next sync will overwrite must never
   absorb a user's capture. (Readwise books SHOULD still appear in the Atlas
   shortlist? No — they are material, not destinations. Excluded there too;
   the router's CONCEPT PAGES / SEEDLINGS entries are where thoughts route.)
2. **Never auto-fed to seedlings.** No accrual path touches them (principle 2).

## 5. Sync service — Mac-owned, like Telegram

`Data/Services/ReadwiseSyncService.swift`, the `TelegramBridgeService`
posture: the Mac owns the integration; the iPhone consumes synced atoms.

- **Auth/Settings:** Settings → Integrations → Readwise: token field (stored
  in Keychain, never in a source file), connection check (`export/` with
  `pageCursor` probe), last-synced line, "Sync now" button, and a
  disconnect that leaves mirrored atoms in place (with a "remove imported
  highlights" option).
- **Cadence:** on launch (deferred behind interactive startup, like the
  recall backfill) + every 6 hours. Cursor (`updatedAfter`) persisted in
  `app_flags` (`readwise_sync_cursor`) so it survives UserDefaults resets.
- **First import:** paginated full export; recall indexing deferred/batched
  (the existing `RecallIndexer.backfill` picks up new atoms — no bespoke
  indexing pass). A few hundred book atoms is normal atom volume.
- **Sync writes** go through `AtomRepository` (tracked, versioned) so books
  flow to Supabase and the iPhone through the standard pipeline.

## 6. Surfacing — where highlights actually do work

### 6.1 The development conversation (the core ask)

Extend the concept collaborator's **`pull_evidence`** tool
(`AgentToolRegistry` / `AgentToolExecutor`): alongside seedbed items and
dive extracts, it searches Readwise highlights for the working concept —
concept key + aliases matched lexically against highlight text/note/book
title, plus book-level semantic match through the recall index (per-highlight
embeddings are a stretch, §8). Returned rows carry full provenance: text,
book title, author, `readwise_url`.

The collaborator then does what a great thought partner does with a
well-read friend's bookshelf: *"You claimed spacing beats cramming — you
highlighted almost exactly this in Make It Stick. Want it under Evidence?"*
Accepted → the existing cited-bullet staging (quote + source), the same
contract Deep Dive evidence already uses. Works identically in the
StudyConceptDesk (dive develops) and any `/concept` conversation on a page.

### 6.2 The connection workspace sources rail

`suggestedWellSources` (ConnectionFocusModeView) gains Readwise books among
its suggestions: a book whose highlights match the page's concept key shows
up in the rail; linking it makes it a real source whose contributions render
like any other. The page's "bring receipts" surface, no conversation needed.

### 6.3 Seedling tending (inspiration while it ripens)

- A seedling row/detail shows a computed line when highlights match its
  conceptKey/aliases: *"4 related highlights · 2 books"* (Mac dive rows, Mac
  Growing section, iOS tending sheet). Computed at load, never stored.
- **At develop time**, matching highlights are OFFERED:
  - Dive flow: they join the Concept Desk's evidence rail (the rail is
    already the offering surface).
  - Global flow: the top **3** strongest matches stage as ✓/✗ ghost rows
    (`ConnectionStagedInsert`, `sourceKind: "readwise"`, citation in the
    text) on the newborn page — the one staging grammar, capped so a
    well-read concept doesn't drown its own birth.

### 6.4 The Library

A READING shelf: book tiles (cover via `CachedAsyncImage` + `stableKey`,
title, author, highlight count, compact age of last highlight), opening to a
read-only source view — the highlights as a clean ledger, each with a
"Stage for a page…" affordance (picks a connection + section → ghost row).
This is the browse surface; deliberately quiet, never a queue.

### 6.5 What is deliberately absent

- No inbox rows, ever. No badges, no counts on the tab.
- No auto-growth of seedlings from highlights.
- No per-highlight atoms.
- At most a stretch-phase Daily Brief line ("38 new highlights from 4 books
  this week") — a receipt, not a to-do.

## 7. Build phases + reuse map

### Phase 1 — The mirror (ships value alone: search + shelf)
1. `ReadwiseSourceStructured` model + atom mapping (tolerant decode).
2. `ReadwiseSyncService`: full import → incremental cursor → deletion
   pruning; Settings → Integrations UI + Keychain token.
3. Exclusions: readwise subtype out of merge candidates, triage pool, and
   Atlas shortlist.
4. Library READING shelf + source view (read-only).
*Exit: highlights findable in ⌘K; books browsable; inbox untouched.*

### Phase 2 — Evidence in the room (the ask)
1. `pull_evidence` extension (lexical + book-level semantic match, capped
   rows, provenance fields).
2. Collaborator skill instructions gain the bookshelf move (cite
   conversationally; stage only on acceptance — same hard lines).
3. Suggested-sources rail includes matching Readwise books.

### Phase 3 — Seedbed ties
1. Related-highlights count on seedling surfaces (computed).
2. Develop-time offers: desk evidence rail (dive) / top-3 ghost rows
   (global, `sourceKind: "readwise"`).
3. Library source view's "Stage for a page…" verb.

### Phase 4 — Stretch
- Daily Brief line; per-highlight embeddings for sharper matching; Readwise
  Reader (v3) articles; a manual "Grow a thought from this highlight" verb
  (the user's OWN reaction to a highlight becomes the seedling thought, the
  highlight rides along as its first evidence — the correct way a highlight
  ever touches the Seedbed).

**Reused wholesale:** atom sync + recall indexing, swipe-file
one-atom-per-content pattern, `pull_evidence` + cited-bullet staging,
`ConnectionStagedInsert` ghost rows, suggested-sources rail,
`CachedAsyncImage`, app_flags cursors, Keychain, TelegramBridge service
posture, merge-candidate exclusion pattern.

## 8. Success criteria

- Inbox row count contribution from Readwise: **zero**, forever.
- A concept development conversation cites at least one relevant highlight
  when one exists (and never invents one — provenance on every offer).
- ⌘K finds any highlighted line within one sync cycle of highlighting it.
- Sync is idempotent: re-running a full import changes nothing.
- Removing a highlight in Readwise removes it from the mirror on next sync.

## 9. Open decisions (recommendations inline)

1. **Atom type:** `.research` with `subtype: "readwise"` (recommended — zero
   schema churn, research surfaces already render source-ish atoms) vs a new
   AtomType. Revisit only if readwise atoms need different canvas behavior.
2. **Polling cadence:** launch + 6h (recommended). A "Sync now" button covers
   impatience; webhooks don't exist in the public API.
3. **Reader (v3) articles:** defer — Reader documents are closer to the swipe
   file's territory and deserve their own thinking.
4. **iOS READING shelf in v1:** defer; book atoms already sync, so iOS search
   finds highlights on day one — the shelf can follow demand.
5. **Highlight notes (`note` field):** the user's own words! Worth surfacing
   distinctly (they're closer to thoughts than the highlight text is). V1
   mirrors them inside the highlight; the Phase-4 "grow from highlight" verb
   is where they'd shine.

## 10. As-built notes (July 17, 2026)

**Reconciliation.** The plan missed a pre-existing Readwise stack:
`ReadwiseService` (API client + Settings connection UI, token in
UserDefaults), `ReadwiseBookStore` (UserDefaults browse cache), and a full
Command-K Library tab. It also had an old atom sync creating one `.research`
atom PER HIGHLIGHT (no pruning, no updates). Resolution: one API client
(`ReadwiseService`) keeps its token storage and browse layer untouched;
`syncHighlights()` was rewritten as the book-mirror pass (this plan's §4/§5)
with a one-shot consolidation that soft-deletes the legacy per-highlight
atoms after the first FULL mirror pass (app_flag `readwise_book_mirror_v1`);
`startAutoSync()` (launch + 6h) is called from CosmoApp. The planned
separate ReadwiseSyncService and duplicate wire models were dropped.

**Shipped:** `ReadwiseMirrorReducer` + `ReadwiseSourceStructured` /
`ReadwiseMirrorHighlight` (Data/Models/ReadwiseSource.swift);
`ReadwiseEvidenceMatcher` (AI/) — deterministic, threshold-gated (floor 0.6),
whole-token, multi-word phrase rules, single-common-word abstention, book
title boosts but never qualifies; `pull_evidence` extended (works without a
dive; readwise rows carry book/author/url; seedling aliases widen the
vocabulary); suggested-sources rail offers matching books; global seedling
develop stages top-3 matches as Evidence ghost rows; Growing rows whisper
"· N highlights"; Command-K highlight rows gained right-click "Stage for a
page…"; mirrors excluded from merge/triage pools (`isReadwiseContent`).
Tests: ReadwiseMirrorTests (14) — reducer idempotence/prune/order + matcher
qualify/abstain contracts.

**Not shipped (unchanged from plan):** Reader v3, per-highlight embeddings,
Daily Brief line, iOS shelf, "grow a thought from a highlight" verb.
