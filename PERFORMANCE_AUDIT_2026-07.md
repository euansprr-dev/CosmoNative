# CosmoOS macOS Performance Audit — July 10, 2026

Deep audit of launch, ⌘K command center + subpages, swipe file, inbox, canvas/thinkspace
mode switching, document open/close, and the deep dive experience. Every finding carries a
file:line reference. Ranked by expected impact. No fix here changes any visible UI.

---

## Part 1 — Root causes found

### P0.1 — Daily 257MB database backup runs synchronously on the main thread at launch
`CosmoDatabase.init` → `setupDatabase()` runs during `@StateObject` creation in
`CosmoApp` (Core/CosmoApp.swift:11), i.e. **before the first frame**. It opens the DB, runs
PRAGMAs and migrations — and once per day, `performDailyBackupIfNeeded`
(Data/Database/CosmoDatabase.swift:80, 119–137) copies the whole database via
`source.backup(to:)`. The live DB is **257MB** (backups confirm it runs daily). This is the
"sometimes it takes a second or two to open" — first launch of each day pays a full-file
copy on the main thread.

**Fix:** keep open+migrations synchronous (schema must exist), move the backup to a
background task ~10s after launch. GRDB's backup API is safe against a live WAL database;
run it from a `Task.detached` using a separate `DatabaseQueue` exactly as it does today.

### P0.2 — Database file hygiene: 38% dead space, 26MB of already-synced queue rows
- `PRAGMA freelist_count` = 25,010 of 65,917 pages → ~100MB of the 257MB file is free pages.
- `sync_queue` holds 1,299 rows with status `synced` (~26MB of dead payloads) and 1 pending.
- FTS shadow tables total ~71MB (`atoms_fts_*`, `context_chunks_fts_*`).

**Fix:** (1) prune `synced` sync_queue rows on launch (deferred, after sync engine confirms
they're safe to drop — keep a small tail if the sync fence needs it); (2) one-time `VACUUM`
at idle (the file is shared with CosmoVoiceDaemon — do it when the daemon is quiescent;
busy_timeout already covers contention); (3) `INSERT INTO atoms_fts(atoms_fts)
VALUES('optimize')` periodically. Smaller file → faster daily backup, less IO, smaller mmap
footprint. Expect ~257MB → ~150MB immediately.

### P0.3 — AtomRepository re-decodes the ENTIRE atoms table on every write
`AtomRepository.observeAtoms()` (Data/Repositories/AtomRepository.swift:39–66) installs a
ValueObservation that runs `fetchAll` of **all** non-deleted atoms (4,672 rows, ~14MB of
bodies+metadata, 44MB table) and delivers the decoded array to the main thread into
`@Published var atoms` — **on every write to the atoms table**: every debounced typing
autosave, every task tick, every sync pull. The array has exactly one consumer:
`ContentStrategyEngine` does `atoms.first(where:)` (Agent/Intelligence/ContentStrategyEngine.swift:547).

**Fix:** delete the observation and the `@Published atoms` mirror; replace the one consumer
with `try await AtomRepository.shared.fetch(uuid:)`. This removes a full-table decode +
main-thread delivery from *every save in the app*. Zero UI impact.

### P0.4 — Command Center dashboard: 41-@Published ObservableObject invalidates everything
`CommandCenterDashboardViewModel` (Canvas/CommandCenter/CommandCenterDashboardViewModel.swift:465)
is an `ObservableObject` with **41 `@Published` properties**. Under ObservableObject
semantics, any single change re-renders every subscribed view — the whole dashboard
(task lists, calendar, habit panel, reports) re-evaluates when one checkbox ticks.
Compounding it, `CommandCenterDashboard` re-publishes agent context on **every**
`objectWillChange` via a main-queue hop (Canvas/CommandCenter/CommandCenterDashboard.swift:62–66).

**Fix:** migrate the VM to `@Observable` (project convention already mandates it — this is
the biggest remaining violator). Per-property tracking makes each dashboard section
re-render only when the properties it reads change. Replace the `objectWillChange`
republish with targeted `.onChange` on the few fields the context provider actually
reflects (or make the provider pull lazily — it holds the VM reference already).

### P0.5 — Launch-time work storm from the dashboard VM
The VM is created at MainView init (Navigation/MainView.swift:161) and its `init`
immediately runs `RecurringSeriesEngine.runCleanSlateMigrationIfNeeded()` +
`TaskDayPinRepair.runIfNeeded()` + `refreshAll()` — nine sequential awaited loads
(CommandCenterDashboardViewModel.swift:639–648, 811–824), several of which each call
`fetchAll(type: .task)` separately. All of this competes with first paint.

**Fix:** (1) make `refreshAll` fetch the task table **once** into a snapshot shared by
refreshTasks/upcoming/logbook/anytime/someday derivations; (2) run the two migrations
deferred (after first paint, like the interactive startup pipeline); (3) parallelize the
independent loads with `async let` instead of nine sequential awaits.

---

## Part 2 — Main-thread hazards

### P1.1 — Synchronous GRDB writes on the main thread (up to 5s stall risk)
`config.busyMode = .timeout(5.0)` (CosmoDatabase.swift:76) means a synchronous write can
block the calling thread up to **5 seconds** if CosmoVoiceDaemon/web app holds the write
lock. These run on the main actor:
- UI/FocusMode/Connection/ConnectionFocusModeView.swift:623 (title save)
- UI/FocusMode/Content/ContentFocusModeView.swift:3323, 3690 (`writeToAtomSync`)
- UI/FocusMode/Ideas/IdeaFocusModeViewModel.swift:1261
- Canvas/NoteBlockView.swift:860, Canvas/StickyNoteBlockView.swift:589 (block create)

Several fire in close paths — i.e. **during the focus-mode exit animation** ("closing
documents" lag).

**Fix:** capture the state snapshot on main, perform the write via `database.asyncWrite`.
The app-termination guarantee stays with `DirtyEditorRegistry.flushAll()` (already
synchronous at terminate). Where ordering with `onDocumentChange` matters (the note editor's
one-frame defer), keep the sequencing but make the write itself async.

### P1.2 — Synchronous full-res image decodes inside view bodies
- UI/Inbox/CaptureLanesView.swift:764 — `NSImage(contentsOfFile:)` **per row, per body
  re-evaluation, uncached**. Every inbox render decodes JPEGs from disk on main.
- UI/CommandK/CortexDatabaseBrowser.swift:745 — same pattern in the ⌘K database browser
  grid (`localThumbnail`), full resolution, uncached, fires while scrolling a LazyVGrid.
- UI/Library/LibraryGridView.swift:259 — same.
- Canvas/ThinkspaceLibraryView.swift:1462 — NSCache'd, but first decode is sync-on-main and
  full-res.

**Fix:** all four should use the already-built async downsampling pipeline
(`ThumbnailCacheService` / `CachedAsyncImage`, Data/ThumbnailCacheService.swift — it does
CGImageSource thumbnailing, NSCache with cost limits, disk cache). This is a drop-in: same
visual, decode off-main at display size.

### P1.3 — Focus-mode close does deferred saves mid-exit-animation
NoteFocusModeView.onDisappear (UI/FocusMode/Notes/NoteFocusModeView.swift:495–509) defers
`saveAtomImmediately()` + `floatingBlocksManager.saveImmediately()` by one frame — landing
exactly when the exit spring is animating. Combined with P1.1 this is the "closing
documents" hitch.

**Fix:** snapshot the document state synchronously in onDisappear (cheap), run the
persistence async. Audit the same close path in Content/Connection/Idea focus modes.

---

## Part 3 — Observation-graph over-invalidation (MainView)

MainView's body is ~3,200 lines of view code and it directly observes several chatty
stores (Navigation/MainView.swift:114–183):

- `CosmoInlineAssistantStore` (23 @Published, MainView.swift:177): `composerText` publishes
  **per keystroke** while typing to the assistant; `currentRunSteps`/`paneMessages`/`phase`
  publish per stream event during a run. Each publish re-runs MainView.body.
- `DeepWorkSessionEngine` (MainView.swift:180): `elapsedSeconds` publishes **every second**
  while a session timer runs (AI/DeepWorkSessionEngine.swift:160) → MainView.body re-runs
  at 1Hz for the whole session.
- `ThinkspaceManager` (MainView.swift:121): `navigationCache`/`childDocsCache` are
  @Published dictionaries that change on every library-inventory fetch.
- Because destination views are constructed with closures (SwipeHomePage's destination
  callback, ConstellationOverlayHost's handlers), SwiftUI can't prove them equal, so these
  subtrees re-evaluate on every MainView invalidation.

**Fix (proven pattern in this codebase):** extract the reads into tiny leaf host views —
exactly what `ConstellationOverlayHost` and `CanvasWorldTransformHost` already do for
120Hz writes. Concretely:
1. Remove `@ObservedObject inlineAssistantStore` / `sessionEngine` from MainView; move the
   few reads (pane visibility, session chrome) into small host views that observe the
   store themselves.
2. Split ThinkspaceManager: the caches don't need to be @Published on the object MainView
   observes (only library views read them — have those views observe a separate cache
   store, or drop @Published and use the existing notification).
3. Keep `AppState`/`thinkspaces` observation — they change rarely.

---

## Part 4 — Repository query patterns

### P2.1 — `fetchAll(type:)` + in-memory JSON-metadata filtering
Pattern (e.g. Data/Repositories/InquiryRepository.swift:225–247): fetch **every atom of a
type** (full bodies included) then filter by a metadata field. `metadataValue(as:)`
(Data/Models/Atom.swift:1595) decodes JSON **on every call** — so
`sorted { $0.inquirySessionMetadata?.lastActiveAt ... }` (InquiryRepository.swift:240)
decodes twice per comparison, O(n log n) decodes.

**Fixes, in order of safety:**
1. Decode once: map to `(atom, meta)` pairs before filter/sort. Trivial, no schema change.
2. Batch UUID fetches: `fetchSources`/`fetchConnections` (InquiryRepository.swift:250–260,
   363–373) await one query **per uuid, serially** — add `fetch(uuids:)` with
   `WHERE uuid IN (...)` and use it.
3. Where a scoped query is hot, push the filter into SQL:
   `json_extract(metadata, '$.parentDeepDiveUUID') = ?`. Only add a generated column +
   index if measurement says so (schema is shared with iOS/daemon — keep drift low).

### P2.2 — Dashboard refetches the whole task table per list
`refreshTasks`, `loadUpcomingTasks`, `loadCompletedTasks`, `loadAnytimeTasks`,
`loadSomedayTasks`, `loadProjectTasks` each call `fetchAll(type: .task)`
(CommandCenterDashboardViewModel.swift:980, 1049, 1415, 1481, 1511, 1529). `refreshAll` and
the dashboard `.task` run several of them back-to-back.

**Fix:** one task-table snapshot per refresh wave; derive every list from it. The domain
debounce machinery (`scheduleRefresh`, line 878) already coalesces triggers — give it a
shared snapshot instead of per-domain refetches.

### P2.3 — Command center `.task` refires on every destination switch
CommandCenterDashboard.swift:43–54: every visit re-runs `loadAreas` +
`loadAnytimeTasks` + `loadSomedaTasks` (3× full task fetch, sequential), and the view-local
`hasAppeared` (line 15) resets so the arrival cascade re-animates **every visit**, making
mode switching feel slower than it is.

**Fix:** `loadIfNeeded` guards in the VM (it's persistent in MainView — data is already
warm); hoist `hasAppeared` into the VM so the cascade plays once per app session and
revisits are instant. (Design intent per the code comment is "assembles once, never
loops" — the @State reset defeats it.)

### P2.4 — Deep dive load duplicates its own queries
`DeepDiveOverviewViewModel.load()` fetches questions/extracts in parallel (good), then
`InquiryGardener.review` re-fetches **the same questions and extracts**
(AI/InquiryGardener.swift:296–297). Pass the loaded arrays into `review`.

---

## Part 5 — Document open cost (long notes)

`BlockListView` mounts **every block eagerly in a plain VStack**
(Editor/BlockEditor/BlockListView.swift:111–112), and each text block is a full
NSViewRepresentable TextKit stack (scroll view + text view + layout manager —
Editor/TextKitCoordinator.swift:1681). Document-open cost scales linearly with block count;
a long note pays hundreds of NSTextView creations synchronously inside the focus-enter
transition.

**This is regression-sensitive:** cross-block drag selection and doc-level undo depend on
all rows being mounted (see line 617 comment + note_focus_block_editor_v2 invariants).
**Fix (measure-gated, last phase):** hybrid rows — blocks far outside the viewport render
as static styled `Text` with identical geometry, promoted to full editor rows on
scroll-approach or focus. Keep geometry + hit-testing identical so drag selection still
sees every row. Only do this if profiling shows real notes are slow (typical notes may be
fine; transcripts/long docs are the risk case).

---

## Part 6 — Small wins

- **Dead 30s timer**: Core/CosmoApp.swift:294 schedules a repeating timer with an empty
  closure. Delete.
- **⌘K swipe gallery load** (CommandKViewModel.swift:4240): `search(query: "", ...)`
  compiles to `LIKE '%%'` over all research atoms with full bodies. Works, but a
  column-projected record (skip `body`) would cut the decode. Low priority — it runs once
  per palette lifetime.
- **`enumerated()` ForEach with index-captured stagger** (CortexDatabaseBrowser.swift:64,
  DeepDiveOverviewView.swift:471 etc.): index shifts re-render all subsequent rows on
  insert/remove. Fine for bounded lists; avoid for long ones.
- **Theme toggle** rebuilds the entire window via `.id(themeRefreshID)`
  (CosmoApp.swift:33) — acceptable (rare), but explains slow theme switches.

## What's already healthy (don't touch)
- ⌘K search pipeline: 30ms debounce, generation guards, detached index build, order-lock,
  preview excerpts, prewarm + stale-while-revalidate. (3 prior passes)
- Canvas pan/zoom/drag: gesture frames never re-enter CanvasView.body; equatable layers;
  quantized transforms; grid tile cache; snapshot prewarm. (July 4 pass)
- Constellation: off-main screenshot pipeline, 1x captures, scrub host isolation.
- Swipe file media: CachedAsyncImage + CGImageSource downsampling + NSCache limits +
  disk cache; `loadIfNeeded` everywhere; filter recompute detached + debounced.
- Inbox data layer: ValueObservation + 350ms debounce + visibility-gated taxonomy pass.
- FilmGrainOverlay/ThinkspaceAuroraView: static, one-time bitmap.

---

## Implementation plan

**Phase 1 — Zero-risk, biggest wins first (one session)**
1. Delete AtomRepository full-table observation; fix ContentStrategyEngine consumer (P0.3).
2. Move daily DB backup off the launch path to a deferred background task (P0.1).
3. DB hygiene: sync_queue prune + one-time VACUUM at idle + FTS optimize (P0.2).
4. Replace the four sync image decodes with ThumbnailCacheService (P1.2).
5. Delete the dead 30s timer; pass loaded arrays into InquiryGardener.review (P2.4).

**Phase 2 — Command center (one session)**
6. Migrate CommandCenterDashboardViewModel to @Observable; kill the objectWillChange
   republish (P0.4).
7. Single task-table snapshot per refresh wave; async-let refreshAll; defer launch
   migrations (P0.5, P2.2).
8. loadIfNeeded + once-per-session arrival cascade (P2.3).

**Phase 3 — MainView observation graph (one session)**
9. Leaf-host extraction for inlineAssistantStore + sessionEngine reads (Part 3).
10. Split ThinkspaceManager caches out of MainView's observed object.

**Phase 4 — Repositories + close paths (one session)**
11. `fetch(uuids:)` batch API; decode-once-then-sort; SQL-scoped hot queries (P2.1).
12. Async-ify main-thread GRDB writes in focus-mode save/close paths; async close saves
    (P1.1, P1.3).

**Phase 5 — Measure-gated (only if profiling demands)**
13. Hybrid static/editor block rows for long documents (Part 5) — respect drag-selection
    and undo invariants.

## Verification protocol (every phase)
- Build: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`;
  tests: `swift test --filter <touched suites>`.
- Judge smoothness on **Release** (Debug loads libMainThreadChecker).
- Add os_signpost intervals: app-launch→first-frame, destination switch, focus open/close,
  deep dive load (mirroring CommandKPerformanceInstrumentation). Capture before/after in
  Instruments (Time Profiler + Hangs + SwiftUI).
- Invariants to preserve (from project memory): ⌘K prewarm choreography + both animation
  drivers; `loadDatabaseCount` stays `count(types:)`; equatable canvas layers list all
  render params in `==`; tombstone cascade; `replaceStorageDroppingUndo` on out-of-band
  storage replaces; DirtyEditorRegistry terminate flush; canvas snapshot/prewarm contracts.
