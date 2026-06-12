# CosmoOS Data-Safety Audit — June 11, 2026

> **STATUS: ALL 8 PHASES IMPLEMENTED (same day).** Build green; `DataSafetyRegressionTests`
> + note/migration/connection regression suites green. Key invariants and APIs are recorded
> in the project memory (`data_safety_audit.md`). Remaining follow-ups (tracked separately):
> pre-existing stale tests from the same-day UI/swipe rework (InstagramAutoTranscriber,
> cluster palette/board, social discovery, swipe families), and a review UI for the
> conflict snapshots preserved in `sync_queue` with `status='conflict'`.

Seven parallel deep audits covering: core persistence (GRDB/AtomRepository/Sync), notes (block + focus mode), content (block + focus mode + pipeline), sticky notes + canvas placements, tasks + recurrence + calendar, inbox (capture → triage → route), connections + swipe files, and all AI/agent write paths.

**Verdict: the app has ~120 distinct data-safety defects. 12 are CRITICAL (data loss in normal daily use), ~30 HIGH. They cluster into 8 systemic root causes. Fixing the root causes eliminates the majority of individual findings.**

---

## PART 1 — SYSTEMIC ROOT CAUSES

### RC1. The optimistic lock is self-defeating, and its "auto-merge" destroys data
`AtomRepository.update()` bumps `_local_version` in SQL (AtomRepository.swift:423-449), then calls `ChangeTracker.trackUpdate` **without** `skipVersionIncrement: true` (:544), which bumps it AGAIN (ChangeTracker.swift:59-61). The DB ends at caller+2 while the returned atom carries caller+1 — so **every consecutive save by any caller holding the returned atom fails the version check and falls into the conflict auto-merge** (:455-541). That merge is destructive:
- `body`: stale caller wins (:466)
- `metadata`: whole-blob stale-caller-wins (:486) — wipes other writers' metadata keys
- `links`: whole-blob stale-caller-wins — wipes freshly created AtomLinks
- `structured`: key-union that **resurrects deleted keys** (:474-477)

The lock that's supposed to protect concurrent edits instead launders stale data over fresh data on routine saves. This single bug underlies dozens of downstream findings (tasks F9, swipes B7, content M6, agent #2).

**Fix:** pass `skipVersionIncrement: true` from `update()`/`updateFields()`; make the conflict path merge `metadata` key-by-key like `structured`; treat caller-missing keys as deletions when base version known; refuse to overwrite `body` when `isBeingEdited(uuid)`; log every real conflict.

### RC2. Silent JSON decode failure → default → re-save wipes everything (systemic, 60+ call sites)
`metadataValue(as:)` / `structuredData(as:)` use `try?` (Atom.swift:1475-1499). The pervasive pattern `atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()` then `withMetadata(...)` means **one corrupt/mismatched field in the JSON destroys ALL metadata on the next innocent write** (e.g. one completion tap erases a task's recurrence rule, completion log, schedule, links). `withMetadata` even sets `metadata = nil` on encode failure (Atom.swift:1502-1506). Same shape for: `linksList` → `[]` → `addingLink` wipes all links (Atom.swift:1339-1414); rich-document decode failure → flattened note re-saved (RichDocument.swift:394-405); `swipeAnalysis` getter (SwipeAnalysis.swift:893-903); content focus keys (`outline`/`generationHistory`/`conversationHistory` → empty → key deleted on save, ContentFocusModeState.swift:668-697 + 774-804); DeepDiveBodyMigration runs on every load and overwrites all of `structured` from a possibly-failed decode (DeepDiveBodyMigration.swift:61-93).
**Aggravator:** `updateFields` writes `""` instead of SQL NULL for nil (AtomRepository.swift:608-615), manufacturing exactly the undecodable state that triggers this.

**Fix:** decode failures must be loud (log + telemetry) and **non-destructive**: never overwrite a non-empty column with a default-derived re-encode; quarantine undecodable blobs under a preserved key; merge at JSON-dictionary level instead of typed-struct round-trips; fix the `""`-for-NULL bug.

### RC3. Whole-blob writes over shared JSON namespaces
`metadata` and `structured` are shared key namespaces; multiple writers re-encode a typed struct over the whole column, dropping every key the struct doesn't model:
- `ContentProfileEditor` save wipes voice intelligence, stats, top posts, clientSince (ContentProfileEditor.swift:1373-1403)
- `ConnectionStructuredData` round-trip wipes legacy mental-model keys (ConnectionFocusModeState.swift:833-855; ConnectionBlockView.swift:589-606)
- `FlashLiteRouter.postProcessIdea` re-encodes `IdeaMetadata` over whole metadata (FlashLiteRouter.swift:400-427)
- `ContentPipelineService.activateIdea` uses `toJSON()` replacement instead of `mergedMetadataJSON` (ContentPipelineService.swift:746, 795)
- `ConnectionPromotionService` crystallization replaces metadata wholesale, dropping rich title document (ConnectionPromotionService.swift:174-202)
- Latent: `setMentalModel` (AtomExtensions.swift:654-659), `debounceSaveNotes` in SwipeStudy (dead but dangerous)

**Fix:** one helper — `Atom.mergingMetadataKeys(_:)` / `mergingStructuredKeys(_:)` — that parses existing JSON as dict, overlays only the caller's keys, re-encodes. Ban direct `metadata = struct.toJSON()` by convention + lint.

### RC4. AI/agent writes have no staleness guard and ignore the editing locks
Editing locks exist (AtomRepository.swift:642-668) and are honored by SyncEngine/RealtimeSyncService/SwipeProcessingService — but **no agent tool checks them**. Direct-write tools:
- `persistGeneratedDraftLocally` (AgentToolExecutor.swift:3214-3247): generate/revise_draft replaces `atom.body` after a 30s+ cloud call with zero comparison to what it read; the `.unifiedEngineDraftUpdate` listener (ContentFocusModeView.swift:3065-3080) then force-replaces the open editor with no undo push. User keystrokes during generation are destroyed in DB **and** on screen.
- `update_content` (:3315) / `update_idea` (:499): whole-body direct writes, no review flow, no snapshot.
- `UnifiedWritingEngine.handleWriteDraft`/`handleUpdateOutline` write raw SQL with **no version bump, no `_local_pending`, no ChangeTracker** (UnifiedWritingEngine.swift:2125-2147, 1937-1953) — invisible to sync AND to optimistic concurrency.
- Engine notifications are unscoped by contentUUID (UnifiedWritingEngine.swift:2115-2119 etc.); a Telegram session writing content B can be applied + persisted into open content A (ContentFocusModeView.swift:3031-3099).
- `edit_section` is notification-only — never persisted headless; agent reports success, edit lost (UnifiedWritingEngine.swift:2318-2334).
- Inbox merge: `blendMerge` sends only `existing.prefix(3000)` to the LLM and replaces the ENTIRE destination note body — silent tail amputation of long notes (InboxActionExecutor.swift:447-481, :61-63).
- No backup of pre-AI-write content anywhere (`ContentPipelineService.saveDraft` versioning exists but is never called by AI paths).

**Fix:** every AI write to user-visible body: (1) check `isBeingEdited(uuid)` → stage as proposal instead; (2) capture `(body, _local_version)` at read, re-check at write, conflict → proposal; (3) snapshot prior body (`saveDraft` or metadata `previousDraft`) before overwrite; (4) UUID-scope all engine notifications and require exact match; (5) persist `edit_section` headless; (6) inbox merge >3000 chars → lossless append fallback.

### RC5. Debounced saves with no flush on quit / switch / close
`.cosmoAppWillTerminate` is observed only by four focus modes. Not by:
- `NoteBlockView` / `StickyNoteBlockView` (1s debounce; ⌘Q within the window loses typing — NoteBlockView.swift:547-562, StickyNoteBlockView.swift:380-393)
- `SwipeStudyFocusModeView` (1-2s debounces; switching swipes CANCELS pending saves without flushing — :4136-4140)
- Canvas position saves (`Task.detached(.background)`, no terminate flush; `DebouncedPositionSaver` with its lifecycle flush is **dead code, never wired** — SpatialEngine.swift:329-374, DebouncedPositionSaver.swift)
- Terminate handler itself relies on synchronous observers; `Task { await ... }` responders lose the write; final ~50ms of NSTextView typing not flushed (TextKitCoordinator 50ms deferred sync).

**Fix:** central `DirtyEditorRegistry` — every editing surface registers a synchronous flush closure; `applicationWillTerminate` iterates and flushes synchronously (DB-only, no network), then synchronously enqueues sync rows. Port `hasLocalEdits`-gated flush to all canvas blocks + SwipeStudy.

### RC6. Unconditional stale-snapshot saves on close (saving data you didn't edit)
- `NoteFocusModeView.onDisappear` saves unconditionally even with zero local edits — stale snapshot overwrites newer external writes (NoteFocusModeView.swift:467-481; observation deliberately skips body after load :1659-1669).
- `StickyNoteBlockView.saveNoteSync` has NO `hasLocalEdits` guard — the exact bug NoteBlockView already fixed (comment at NoteBlockView.swift:746-754) was never ported (StickyNoteBlockView.swift:478-529).
- **Connection focus mode is the worst case**: `handleAppear` wholesale replaces state — including sections — with the **UserDefaults blob from the last session**, discarding fresher DB sections (ConnectionFocusModeView.swift:176-189, 464-468); then `saveToAtom()` writes a full open-time atom snapshot through `updateSync` (no version check, full-row `save(db)` — AtomRepository.swift:562-575), reverting title/links/metadata to open-time values. Rename + edit in one session = rename silently lost; ⌘K-linked source = link wiped.
- `ConnectionBlockView` dedupes identical text across sections at parse time and persists the deletion (ConnectionBlockView.swift:541-554); UD-vs-DB reconciliation is count-based (:467-507).
- Content: stale `richDraftDocument` shadows newer `body` on load with no freshness check (ContentFocusModeState.swift:657-662); `draftEditedLocally` never resets, permanently blocking external draft updates from the editor then overwriting them (ContentFocusModeView.swift:100, 492-499).

**Fix:** gate all close saves on a dirty flag; make `atom.structured` the single source of truth for connection sections (UD = layout/viewport only); replace `updateSync` full-row saves with field-scoped versioned writes; freshness-compare (lastModified vs updated_at) wherever two stores exist.

### RC7. Sync engine: edits acknowledged-and-dropped, deletes never propagate, pulls truncated
- After one permanently-failed push, `_local_version > _server_version` forever → every future remote edit to that atom routes into `handleConflict` and is **discarded while `_server_version` advances** — multi-device edits silently vanish, no retry, no notification (SyncEngine.swift:196-218; ConflictResolver.swift:48-115).
- Batch pull filters `is_deleted=eq.false` — **remote deletions never arrive**; local edit of a remotely-deleted atom pushes `is_deleted: false` and resurrects it everywhere (SupabaseClient.swift:229; SyncEngine.swift:288-298).
- Pull limit 100 rows, no pagination, cursor set to `Date()` not max(updated_at) — offline a week = changes silently skipped forever (SupabaseClient.swift:246; SyncEngine.swift:362, 517-529).
- Push race: edit B made while push of A in flight → all pending rows marked synced, `_server_version = current _local_version` — B never pushes, bookkeeping claims it did; later remote write cleanly overwrites B locally (ChangeTracker.swift:182-191, 200-255; SyncEngine.swift:305-315).
- `DataMigrationService.markAllSynced` stamps atoms whose upload FAILED as synced (DataMigrationService.swift:112-228).
- Realtime DELETE handler bypasses pending/fence/lock shields (RealtimeSyncService.swift:148-159).
- `updateSync` (quit-time path) never enqueues sync — final edit of a session doesn't reach cloud until the atom is touched again (AtomRepository.swift:562-575).

**Fix:** pull without the tombstone filter and apply tombstones; paginate until count < limit; cursor = max pulled updated_at − overlap; mark synced `WHERE id = item.id AND local_version = pushed version`; set `_server_version = pushed version`; surface permanently-failed pushes; exclude failures from markAllSynced; same shields on realtime delete; `updateSync` enqueues a sync row in-transaction.

### RC8. Errors swallowed everywhere; the user can never learn a save failed
`try?` / catch-print-only on virtually every write path outside AtomRepository core: note close save (NoteFocusModeView.swift:1854-1856 — the LAST chance to persist a session), content writeToAtom (:3231), "Saved" indicator shown before the write commits (ContentFocusModeView.swift:2752-2763), all canvas saves, all inbox verbs, all task verbs (optimistic completion animates before persistence; `RecurringSeriesEngine.complete` silently no-ops on missing template and still awards habit credit — RecurringSeriesEngine.swift:297-299), all agent tools (`update_client_memory` returns success on swallowed failure — AgentToolExecutor.swift:2875-2897), vector indexing (silently invisible to recall, no rebuild path), Telegram capture paths. GRDB default config has **no busy timeout** while the DB file is shared with the voice daemon/web app — cross-process contention = instant SQLITE_BUSY landing in `try?` = silent loss (CosmoDatabase.swift:62-120). No backup, no integrity check, no WAL checkpoint policy.

**Fix:** central `PersistenceHealth` observable + write wrapper (log, count, toast on failure); dead-letter snapshot (UserDefaults keyed by uuid) for failed close saves, restored on next open; `Configuration.busyMode = .timeout(5)`; daily sqlite backup before migrations; success-states flip only after commit.

---

## PART 2 — CRITICAL FINDINGS BY AREA (data loss in normal use)

### Inbox / capture (the highest-volume loss path)
1. **DB-write failure at the ingest choke point returns `.consumed` — capture lost, all callers report success.** Telegram replies "Already in your system"; capture bar clears text and shows ✓ (InboxIngestService.swift:132-135; InboxViewModel.swift:176-194; FlashLiteRouter.swift:354-356).
2. **Cloud transport atom soft-deleted even when local save FAILED** — destroys the only durable copy; catch-up migration flag set even if every row failed (InboxCaptureConverter.swift:75-76, 202-212; SyncEngine.swift:120-156).
3. **Telegram capture failure replies "I saved this to Inbox" when nothing was saved**; routing crash strands `captured_items` rows with nil destination that **no view in the app displays** (TelegramCaptureRouter.swift:66-69; CaptureLanesView.swift:72-74).
4. **Merge truncation** — accepted merge replaces full note body with an LLM rewrite of the first 3,000 chars (InboxActionExecutor.swift:447-481).
5. **Launch reconciler auto-dismisses** any active capture whose normalized text matches ANY atom title/body from the last 14 days — false-positive dismissals, no undo, no UI (InboxIngestService.swift:215-230).
6. HIGH: 20-min "consumed rule" silently drops intentional duplicate captures incl. in-app quick capture (:90-93, 305-320); `updateClassification` resets dismissed/actioned items back to `.classified` (race — InboxRepository.swift:113-131); dismiss is undo-less, ⌘A + Dismiss All wipes the queue with no confirmation and no restore UI (InboxViewModel.swift:234-240, 360-370); Telegram voice failure drops capture with file_id discarded (TelegramBridgeService.swift:1507-1575).

### Tasks
7. **Clean-slate migration guard is UserDefaults, data is in the synced DB** — reinstall/new Mac/second device re-runs it: wipes `completedOccurrences`/`skippedOccurrences`/`occurrenceOverrides` on every series and re-anchors to today; the wipe syncs to all devices (RecurringSeriesEngine.swift:365-406). Partial-failure = retries every launch, re-wiping.
8. **Deleting a recurring "occurrence" silently soft-deletes the whole series + its completion history** — occurrence rows carry the template UUID; all delete entry points default to series scope, no confirmation, no undo; `occurrenceOverrides` has ZERO writers (DashboardTaskList.swift:476-490; TaskDetailPanel.swift:498-505; CommandCenterDashboardViewModel.swift:2540-2559).
9. HIGH: rescheduling/clearing date of an occurrence rewrites the TEMPLATE anchor — "clear date" makes the entire series + history unprojectable in every view (CommandCenterDashboardViewModel.swift:1028-1054, 287-326); Logbook never shows recurring completions (loadCompletedTasks:1176-1213); optimistic completion animates, persistence silently no-ops, habit credit still awarded (RecurringSeriesEngine.swift:297-299); migration hard-deletes instance atoms with NO sync tombstone → server resurrects them into a mixed-model duplicate mess (RecurringSeriesEngine.swift:390-392 + ConflictResolver applyRemoteInsert).
10. MEDIUM: uncomplete doesn't reverse backfilled "missed" days; timezone change shifts day keys (completions flip to overdue); `afterOccurrences` end condition broken across query windows; CalendarSync inbound is read-only (good — no external-delete risk) but event creation races calendar setup and orphans silently.

### Notes / sticky notes / canvas
11. **Sticky note text lost on ⌘Q** (1s debounce, no terminate hook, onDisappear not guaranteed) and **sticky color never persisted at all** — `canvas_blocks` has no metadata column; restart = yellow (StickyNoteBlockView.swift:380-393; SpatialEngine.swift:241-320).
12. **StickyNote close save has no dirty guard → resurrects stale data over focus-mode edits** — the exact documented NoteBlockView bug, unported (StickyNoteBlockView.swift:478-529).
13. **Inline-assistant apply on notes flattens the whole document** — images become literal "[Image]", mentions/elements destroyed, then persisted (NoteFocusModeView.swift:1730-1736 → RichDocument.migrateLegacy).
14. **Thinkspace-switch prefetch overlap leaves `SpatialEngine.currentThinkspaceId` stale → saves re-home blocks into the WRONG thinkspace** (vanish from theirs); rapid A→B→A shows B's blocks under A and poisons the snapshot cache (CanvasView.swift:1133-1146, 1930-2004; SpatialEngine.swift:247).
15. **Stale snapshot-cache resurrection**: returning to a thinkspace mounts stickies from a pre-edit cache; blur/teardown then writes the stale text over the newer saved text (CanvasRenderSnapshot.swift:318-380; StickyNoteBlockView.swift:300-327).
16. HIGH: voice-placed blocks never persisted (placeBlocks appends without saveBlock — SpatialEngine.swift:491-538); focus-mode close save unconditional (stale clobber — NoteFocusModeView.swift:467-481); `.updateBlockContent` silently dropped when canvas unmounted (CanvasView.swift:2476-2527); cross-thinkspace drop persists position (0,0) and races the reposition (MainView.swift:1276-1315); backspace-at-start merges 50ms-stale text (BlockTextEditorRow.swift:185-197); tag edits never saved + reverted by observation echo (NoteFocusModeView.swift:498-500, 1671); canvas close save doesn't set `_local_pending` → cloud can revert it (NoteBlockView.swift:806-823); atomless-sticky "remove from canvas" strands its only content copy (SpatialEngine.swift:402-423).

### Content
17. **"Continue Writing" accept REPLACES the entire draft** with selection + continuation — everything outside the selection destroyed, then autosaved (ContentFocusModeView.swift:2458-2460; AIWritingAssistant.swift:192). The fix helper (`draftDocumentByInsertingTextBelowSelection`) already exists unused at :2613.
18. **`update_outline` persists a schema the UI can't decode** (no id/sortOrder) → decode fails silently → next save deletes the outline key — AI outline erased before the user ever sees it (UnifiedWritingEngine.swift:1935-1953; ContentFocusModeState.swift:668-673, 770-776).
19. HIGH: cross-atom notification contamination (RC4); `edit_section` never persisted headless; `draftEditedLocally` never resets; AI draft writes have no guard/backup; ContentProfileEditor metadata wipe; engine writes invisible to sync; scheduled date + post URL never persisted at all (PostCreationPhaseView.swift:17-94).

### Connections / swipes
20. **Connection focus mode: UserDefaults sections clobber DB on open; `saveToAtom` full-row stale snapshot via version-blind `updateSync`** — deterministic rename/link loss in one session, propagates to Supabase (ConnectionFocusModeView.swift:176-189, 577-594).
21. HIGH: structured round-trip wipes sibling keys (A3); cross-section text dedupe deletes intentional duplicates and persists it (A4); re-analysis wipes curated swipe fields — engagement, studiedAt, manual taxonomy overrides, postShortcode (SwipeAnalyzer.swift:21-86; SwipeProcessingService.swift:636-657); `withSwipeAnalysis` parse-failure path discards all sibling structured keys (SwipeAnalysis.swift:908-932); background transcription overwrites body despite editing lock comment, and re-runs on user-pruned carousels (SwipeProcessingService.swift:532-562, 63-90); slide edits during a running deep analysis clobbered by stale pre-call snapshot (SwipeStudyFocusModeView.swift:4042-4120); switching swipes cancels pending saves without flush (:4136-4140).

### Agent / cross-cutting
22. **Agent draft generation overwrites live user edits in DB and editor, no undo, no staleness check** (RC4 #1).
23. HIGH: `delete_automation` is a hard DELETE, no confirmation/soft-delete/undo (AgentToolExecutor.swift:4675-4687); tool loop leaves multi-step mutations half-done on error/cancel with no rollback or summary, no `Task.isCancelled` between tools (CosmoAgentService.swift:775-908); `activateIdea` non-transactional create+update (duplicate content on retry); `update_client_memory` swallows failure, returns success; legacy-table creation paths still write to tables that never sync or show (CosmoApp.swift:398-453; CanvasView legacy creators); diff-apply: unlocatable insertions silently append at document end instead of conflicting (CosmoInlineAssistantDiffEngine.swift:343-403); `_confirmed: true` bypass of delete confirmation (AgentToolExecutor.swift:2610-2617); unscoped bridge callbacks drop proposals while reporting success (CosmoInlineAssistantAgentBridge.swift:35-58); `migrateProjectsToThinkspaces` destructively deletes `.project` atoms on EVERY launch with no one-shot flag (AtomRepository.swift:1119-1178).

Note: the Feb-2026 "8 tool-pipeline bugs" in memory are largely obsolete — the local writing-engine cache was removed (cloud client now); bugs 3/4/8 are gone, 1/5 addressed, 6 mitigated, 7 partially (orphan sanitization exists; `stop_reason` still unvalidated).

---

## PART 3 — FIX PLAN ("bulletproof" roadmap)

Ordering principle: foundation first (most findings are symptoms of RC1–RC3), then per-surface stop-the-bleeding, then sync, then guard rails, then verification. Each phase is shippable and independently testable.

### PHASE 0 — Foundation: make the repository non-destructive (1–2 days, highest leverage)
0.1 Fix the double version bump: `update()`/`updateFields()` pass `skipVersionIncrement: true` (or move bumping wholly into ChangeTracker). Add a regression test: two consecutive `update()` calls with the returned atom must NOT hit the conflict path.
0.2 Rewrite the conflict auto-merge: key-level merge for `metadata` (same as `structured`); never overwrite `body` when `isBeingEdited(uuid)`; deletions honored via a `changedFields` carrier; log every genuine conflict to PersistenceHealth.
0.3 Decode-failure safety: `metadataValue`/`structuredData`/`linksList`/`swipeAnalysis`/rich-doc readers distinguish "absent" from "failed"; on failure, log loudly and mark the atom "quarantined" — all `?? Default()` re-save paths must refuse to write when decode failed. `withMetadata` must never set nil on encode failure.
0.4 Fix `updateFields` `""`-for-NULL (use `DatabaseValue.null`); add version guard.
0.5 Add `mergingMetadataKeys`/`mergingStructuredKeys` helpers; convert the known whole-blob writers (ContentProfileEditor, ConnectionStructuredData writers, FlashLiteRouter.postProcessIdea, ContentPipelineService.activateIdea, ConnectionPromotionService, setMentalModel→delete).
0.6 GRDB `busyMode = .timeout(5)`; daily sqlite-backup-API copy before migrations; periodic WAL checkpoint.
0.7 `updateSync` → versioned field-scoped write + in-transaction sync_queue row.

### PHASE 1 — Capture must never lose (inbox + Telegram) (1–2 days)
1.1 `InboxIngestOutcome.failed(Error)`; callers branch: Telegram replies honestly + does NOT ack/soft-delete; capture bar restores text + shows error; bounded retry (3× backoff) before failing.
1.2 Transport atoms: soft-delete ONLY on `.enqueued`/genuine-consumed; catch-up flag set only when zero failures.
1.3 TelegramCaptureRouter catch: attempt raw-text inbox ingest before replying; honest failure reply. Add a "Needs review" lane for nil-destination/`needsReview`/`failed` captured_items.
1.4 Merge: notes >3000 chars use lossless append fallback; store pre-merge body in inbox item metadata as durable undo.
1.5 Reconciler: require capture-provenance match (sourceCaptureUuid) or ≥6 normalized tokens + short window; log dismissals with restore.
1.6 Consumed rule: exempt `.quickCapture`; scope Telegram match to provenance-tagged atoms.
1.7 `updateClassification`/taxonomy pass: guard prior status (one-line transactional fix).
1.8 Dismiss: register undo + toast (single and bulk); confirmation for bulk >5; "Dismissed" history view with restore.
1.9 Telegram voice: create CapturedItem with fileId BEFORE transcription; `.failed` + retry pass.

### PHASE 2 — Editor surfaces: nothing typed is ever lost (2–3 days)
2.1 `DirtyEditorRegistry`: every editing surface registers a synchronous flush; `applicationWillTerminate` flushes all, synchronously, DB-only. Wire NoteBlockView, StickyNoteBlockView, SwipeStudy, canvas position saver, connection block.
2.2 Port `hasLocalEdits` gating to StickyNoteBlockView.saveNoteSync and NoteFocusModeView close save (skip when clean); fix sticky body-vs-metadata divergent close write (canonicalize document); fix sticky NULL-metadata atom-update skip.
2.3 SwipeStudy: `resetLoadedAtomState` flushes (runs save body) instead of cancelling; re-read live slides/comments at persist time after async analysis; terminate observer.
2.4 Notes: `.plainText` lane post-snapshot generation re-check; tag edits trigger autosave + observation guard; backspace-at-start carries livePlainText like split does; failed close save → dead-letter snapshot restored on next open.
2.5 Inline-assistant note apply: block-scoped edit via locator, never `migrateLegacy(plainContent)` full rebuild.
2.6 Content: Continue Writing inserts below selection (use existing helper); decode-fail keys preserved on save; `draftEditedLocally` reset on clean autosave; richDraftDocument-vs-body freshness check on load; "Saved" indicator flips only after commit; persist scheduledDate/postURL.

### PHASE 3 — Canvas placement integrity (1–2 days)
3.1 `applyCachedThinkspaceSnapshot` also sets engine context (currentThinkspaceId/document); `saveBlock` by-id UPDATE must not rewrite `thinkspace_id`; fix rapid-revert guard.
3.2 Snapshot cache: refresh entry on every content save, or re-sync mounted editing views after authoritative fetch.
3.3 Voice `placeBlocks` → `addBlock(persist: true)`; notification fallbacks: when block lookup fails, write `canvas_blocks` directly by uuid; pending-placement queue for `.openEntityOnCanvas`/`.addSwipeToCanvas` consumed on canvas appear (replaces 0.3s timers).
3.4 Cross-thinkspace drop: shared engine, real target position, pending-reposition persistence.
3.5 Add `metadata` JSON column to `canvas_blocks`; round-trip sticky color + bodyDocument; atomless-sticky delete materializes a backing atom first; undo on all delete entry points; atom restore also restores its canvas blocks.
3.6 Atom+placement creation in one transaction; adopt or delete DebouncedPositionSaver.

### PHASE 4 — Tasks: history is sacred (1–2 days)
4.1 Migration flag into the DB (per-template `migratedAt` or settings row); never clear non-empty `completedOccurrences`; per-atom error tolerance; tombstoned (soft, synced) deletes for legacy instances; serialize via actor.
4.2 Occurrence-scoped actions: wire `occurrenceOverrides` (cancel/reschedule single occurrence); series delete requires confirmation ("…and N logged completions") + restore path; block template anchor-clear or fall back to createdAt anchor.
4.3 `RecurringSeriesEngine.complete` throws on missing template/snapshot; UI reverses animation on failure; habit/XP only after persisted commit.
4.4 Logbook projects `completedOccurrences`; uncomplete reverses backfill; day-anchors stored date-only with pinned timezone; fix `afterOccurrences` counting; remove legacy `generateNextRecurringInstance` branch with lazy tombstone migration.

### PHASE 5 — AI write safety (2 days)
5.1 Staleness guard + `isBeingEdited` check in `persistGeneratedDraftLocally`, `update_content`, `update_idea`, UnifiedWritingEngine writes → conflict routes to proposal/review flow; snapshot prior body (versioned `.contentDraft` via `ContentPipelineService.saveDraft`) before every AI overwrite.
5.2 UUID-scope all engine notifications; handlers require exact match. Persist `edit_section` headless. Engine GRDB writes go through AtomRepository (version + ChangeTracker).
5.3 `delete_automation` → two-phase confirm + soft delete; confirmation keyed off `pendingConfirmations` only (strip `_confirmed`); expire confirmations.
5.4 Tool loop: `Task.isCancelled` between tools; abnormal exit enumerates performed mutations; `activateIdea` transactional; tool errors propagate (no `try?`-then-success); `stop_reason` validation drops truncated tool calls.
5.5 Diff engine: unlocatable insertions → conflict (not append); fuzzy-stage hit on user-edited line → conflict; assert attributed/plain parity in content rich-splice; first-match-only replace.
5.6 proposeWorkspaceEdit falls back to shared store when callback nil; token-scope remaining bridge state.
5.7 Vector DB: retry queue for failed indexing; startup reconciliation (atoms without vectors); delete superseded vector rows; parameterize entityType filter.

### PHASE 6 — Sync correctness (2–3 days)
6.1 Tombstone pull (drop `is_deleted` filter, apply locally with shields); paginate; cursor = max(updated_at) − overlap.
6.2 Mark synced by `(id, pushed local_version)`; `_server_version` = pushed version; failed pushes surfaced + re-queueable; markAllSynced excludes failures.
6.3 Realtime DELETE applies the same pending/fence/lock shields; skipped-while-locked updates queued for reconciliation on lock release (not discarded).
6.4 Conflict handling: keep a `conflict_snapshot` of discarded remote content instead of dropping; per-field timestamps where feasible.
6.5 Kill remaining legacy-table creation paths (route through AtomRepository); gate `migrateProjectsToThinkspaces` behind a one-shot DB flag, single transaction, never auto-delete synced-down atoms.

### PHASE 7 — Visibility & recovery guard rails (1–2 days)
7.1 `PersistenceHealth` observable: write wrapper logs/counts failures; toast/banner on save failure; menu-bar indicator when sync/push failures pending.
7.2 Trash UI over `is_deleted = 1` atoms (restore + purge); inbox pruning becomes archival export, not DELETE.
7.3 Connection: DB as single source of truth for sections (UD = layout only); remove cross-section dedupe-by-text; transactional bidirectional link writes; `linksList` decode-failure refuses link rewrites.
7.4 Swipes: re-analysis merges into existing analysis preserving allowlisted fields (engagement, studiedAt, comments, overrides, postShortcode); `withSwipeAnalysis` bails on unparseable non-empty structured; editing lock honored for body/slides; user-edited transcripts terminal for auto-transcription; creator-import tracks actually-saved shortcodes.

### PHASE 8 — Regression test suite (ongoing, start in Phase 0)
- Repository: consecutive-save no-conflict; conflict merge preserves both writers' metadata keys; decode-failure never wipes; NULL handling.
- Per-surface "type → quit immediately → relaunch → content present" harness (notes, sticky, content, connection, swipe).
- Inbox: ingest-failure → capture preserved + honest outcome; transport atom survives failure; status-clobber race.
- Tasks: migration idempotent on fresh UserDefaults; occurrence delete never touches series; completion round-trip.
- Sync: tombstone propagation; >100-row pull; push-race bookkeeping.
- AI: generation racing user edit → proposal, never overwrite; notification scoping.

### Estimated total: ~12–17 focused days. Phases 0–2 alone eliminate every CRITICAL finding.
