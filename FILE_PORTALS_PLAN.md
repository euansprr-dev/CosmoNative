# File Portals — XLSX / CSV / PDF (and any file) as live blocks on the canvas

**Goal:** drop a spreadsheet, PDF, or any file onto a thinkspace canvas and *see it* — the actual table, the actual pages — without opening anything. A portal, not an icon. Resize it, sticky-note on top of it, draw over it, peek into it, and only "open fully" when you choose to.

**Status:** SHIPPED (2026-07-18) — Phases 1–3 built the same day, plus the Phase-4 search-extraction slice. One deviation from the plan below: XLSX parsing is a self-contained in-house reader (`Services/XLSXWorkbookReader.swift`, ZIP + XML via Foundation/Compression) instead of the CoreXLSX dependency — no pbxproj/package surgery, `swift test`-covered, degrades to the thumbnail tier on anything it can't read.

**Round 2 (same day, after real-file feedback):** grid fidelity (file column widths / row heights, merged cells, Excel empty-neighbor overflow, styles.xml fills + fonts + theme colors with tint), sheet tabs moved above the enter gate (always clickable), `FilePortalSessionState` so entered/sheet state survives block rebuilds, debounced view-state persistence, and **in-portal cell editing** — `XLSXCellPatcher` string-surgery on the one sheet part + `ZipArchiveWriter` verbatim-copy archive rebuild (verify-before-overwrite; never regenerate the workbook from the parsed model), CSV re-serialization, thumbStamp-driven cache invalidation, cloud re-mirror. Editing requires local bytes (importing device). Remaining future work: range portals, docx live rendering, styled number formats (dates render as serials), true vertical merge spans, peer remote-cache busting after edits.

---

## 0. What already exists (leverage, don't rebuild)

| Capability | Where | Reuse |
|---|---|---|
| Atom-backed canvas block pattern | `.image`: `Atom(type:.image)` + `canvas_blocks` row + `ImageBlockView` | The exact template for file portals |
| External-file drop on canvas | `CanvasImageDropController` (`Canvas/CanvasView.swift:28`), `CanvasDropDelegate` (`:6090`), `createImageBlock` (`:5501`) | Extend UTTypes + add a file branch |
| PDF rendering | `PDFSourceView` (`UI/FocusMode/Inquiry/Source/PDFSourceView.swift`) — `NSViewRepresentable`→`PDFView`, search, thumbnails, OCR fallback, highlight store | Tier-1 embed + peek reader |
| File bytes + cloud mirror | `media_attachments` domain: `CaptureMediaStorage` (local), `AttachmentCloudStore` (Supabase `capture-media` bucket), `MediaAttachment.makeLocal` | Solves cross-device blob sync (which image blocks never got) |
| Import choke point | `InboxDropIngestService` — UTType→kind mapping, 100MB cap, text extraction (PDFKit + Vision OCR) | Extend `attachmentKind(for:)` + `extractText` |
| Viewport-gated heavy views | `MediaBlockView` `isViewportActive` pattern: thumbnail off-screen, live view only when visible | Mandatory for portals |
| Peek tier | `PeekController` / `PeekOverlayView` (`Navigation/PeekOverlay.swift`) — Quick-Look-idiom glass panel, Open ⏎ / Open-in-Pane ⌘⏎ | The "expand portal without opening" tier |
| Resize | `SimpleResizeOverlay` (`Canvas/CosmoBlockWrapper.swift:505`) | As-is |
| Annotate on top | Sticky notes are plain zIndex blocks; `Canvas/Drawing/` freehand/shape/text layer sits above blocks | Free — verify, don't build |
| Old portal spec | `LIVING_WORKSPACE_PLAN.md` Phase 4: portals render **cached bitmaps, "never a live canvas"**, recessed chrome (inner shadow, hairline), refreshed on save | Inherit the law and the chrome language |

**Not existing anywhere:** spreadsheet parsing (no CoreXLSX, no CSV code), editor table blocks, QuickLook usage. All net-new.

---

## 1. Data model

### 1.1 New types

- **`AtomType.file`** (`Data/Models/Atom.swift:12`) — one atom type for all file portals. `body` = original filename (searchable), format discriminated in metadata.
- **`EntityType.file`** (`Core/CosmoApp.swift:502`) — ⚠️ do **not** reuse the dead `EntityType.portal`: `SpatialEngine.swift:140` and `CanvasView.swift:2417` actively filter `entity_type == "portal"` out (thinkspace portals removed July 2026). New case, mapped in `CanvasBlock.entityType(for:)` (`Canvas/CanvasBlock.swift:329`), sizes in `defaultSize` + `fromAtom`.
- **`MediaAttachmentKind.spreadsheet`** — safe to add; lenient decode already degrades unknown raws to `.unknown` on old builds. `.pdf` already exists.

### 1.2 Metadata — `FilePortalMetadata`

Written **only** via `Atom.mergingMetadataKeys` (`Atom.swift:1705`) — never whole-blob replace (the app's #1 data-loss vector, per `AtomRepository.swift:470`). Every field lenient-decoded.

```
attachmentUUID: String        // → media_attachments row (owner: atom/<uuid>)
originalFilename, fileExtension, byteSize
portalKind: String            // "pdf" | "spreadsheet" | "csv" | "generic" (raw string, lenient)
pageCount: Int?               // pdf
sheetNames: [String]?         // xlsx
viewState: { page: Int?, sheetIndex: Int?, scrollFraction: CGFloat? }   // what the portal shows
thumbStamp: String?           // content stamp for thumbnail cache invalidation
```

`CanvasBlock.metadata` (the `[String:String]` on the placement row) carries only `attachmentUUID` + `portalKind` for frame-1 render; the atom is the source of truth (enrich via `SpatialEngine.buildBlocks` allowlist, `SpatialEngine.swift:311`).

### 1.3 Bytes & sync — the decision image blocks never made

File bytes go through the **`media_attachments` domain**, not `ImageStore`:

1. Import **copies** bytes into `CaptureMediaStorage` (PDFSourceStore's "copy, never reference" law — sandbox-proof, sync-able; app is currently unsandboxed so no bookmark dance).
2. `MediaAttachment.makeLocal(owner: atom, ownerUUID: atom.uuid, kind: …)`; `AttachmentCloudStore.kick()` mirrors original + thumbnail to the private `capture-media` bucket.
3. Remote device: portal renders instantly from the synced `-thumb.jpg`; full blob downloads on demand via `localOriginalURL(for:)` when the portal goes live or is peeked.
4. Delete: atom tombstone already cascades to `canvas_blocks`; add attachment cleanup on hard-delete only (tombstoned atoms keep bytes for resurrection, per the `restoredAt` contract).

Placement row, atom, and attachment row all sync automatically (`SyncEngine.pushTables` already covers `atoms` + `canvas_blocks`; `media_attachments` is `Syncable`).

---

## 2. Rendering — three tiers, one law

**The portal law (inherited from Phase-4 portals):** what lives on the canvas is cheap; live AppKit views mount only when earned; during gestures, *transforms only, never re-layout*.

### Tier 0 — Skin (always): cached thumbnail card
- A bitmap snapshot + filename strip + kind glyph. This is what renders off-viewport, during pan/zoom gestures, and for every format we don't render live (docx, pptx, unknown).
- Generated off-main by **`QLThumbnailGenerator`** (QuickLook Thumbnailing — handles pdf/xlsx/docx/everything, async, no entitlement needed unsandboxed). New `FilePortalThumbnailStore`: disk cache keyed `attachmentUUID + thumbStamp`, sized for the block at 2×.
- PDF fallback path: first-page render via PDFKit if QL declines.

### Tier 1 — Live portal (viewport-active + not mid-gesture)
- **PDF:** `NSViewRepresentable`→`PDFView`, distilled from `PDFSourceView` (`autoScales`, `.singlePageContinuous`, clear background, no page shadows). Identity-gated `updateNSView` (compare document URL), teardown in `dismantle` — the `CosmoVideoPlayerView` convention. Minimal hover chrome: page counter + prev/next.
- **XLSX/CSV:** parse off-main into an immutable `SheetModel` (rows, columns, display strings, column widths), render with a **custom virtualized SwiftUI grid** (`FilePortalGridView`): fixed row height, only visible cells materialized, header row/column pinned, sheet-tab strip when multi-sheet. Read-only in v1.
  - XLSX: add **CoreXLSX** via SPM (Package.swift keeps Swift-5 language mode pins). CSV: small in-house parser (RFC 4180 quoting), no dependency.
  - Parsed models cached in a `SheetModelCache` actor keyed by attachmentUUID (the `DecodedColumnCache` lesson: decode-per-access is THE lag).
- **Generic files:** stay Tier 0 permanently (thumbnail card + peek + "Open in default app").

### Tier 2 — Peek & open
- Double-tap / spacebar → `PeekController.peek(...)`: PDF gets the full `PDFSourceView` reader (search, thumbnail rail, highlights — already built); spreadsheets get a full-size grid with sheet tabs.
- From peek: **⏎ Open** → v1: `NSWorkspace.open` in the default app. A dedicated focus mode is explicitly out of scope until the portal proves demand.

### 2.1 The two hard rendering problems (solve in Phase 2, not later)

1. **AppKit views under canvas zoom.** `scaleEffect` on an `NSViewRepresentable` transforms the hosting layer — blurry/unstable under live pinch. **Mitigation:** any active gesture (pan/zoom/block-drag) swaps the portal to its Tier-0 bitmap; the live view remounts on gesture end. This is the glass-layer-frame-latch philosophy applied to portals, and it's also what keeps `CanvasView.body` out of gesture frames (the 120fps invariants at `CanvasView.swift:318` stay intact — portals read `isViewportActive` + a new `isGestureQuiescent` signal, both plumbed through the existing render snapshot, and the portal views are `Equatable`-gated like every block).
2. **Scroll-event stealing.** An embedded `PDFView`/grid would eat two-finger scroll meant for canvas pan. **Policy: portals are inert until entered.** Unselected → `allowsHitTesting(false)` on the live content; single-click selects (block chrome only); click-again / double-click "enters" the portal (internal scroll + page-flip active, Esc or click-outside exits). Same mental model as Figma frames; reuses the existing block-selection notification flow.

### 2.2 Chrome
Recessed-window treatment per the Phase-4 spec + `MediaBlockView` precedent (wrapper-less, content-first): hairline border, subtle inner shadow, 14pt radius, filename strip in the ⌘K paper register tokens (`CommandKPreviewPaper`) so document content reads as honest paper. Selection = standard accent stroke + glow. Consult **peakui** at build time — this section names intent, not final values.

---

## 3. Import paths (all funnel into one creator)

New `createFilePortalBlock(fileURL:/data:position:)` in `CanvasView`, mirroring `createImageBlock` (`:5501`): copy bytes → attachment → atom → `spatialEngine.addBlock` (undo via existing `CreateBlockAction`).

1. **Drag from Finder** — extend the drop pipeline (`CanvasDropDelegate.supportedTypes` `:6091`): accept `.pdf`, `.spreadsheet`, `.commaSeparatedText`, `UTType(filenameExtension:"xlsx")`, and generic `.fileURL` fallback→generic portal. Images keep their existing branch; everything else routes to the file creator.
2. **⌘V paste** of copied files — extend `handleCanvasPaste` (`:5350`).
3. **⌘K / create-at-position** — new case in `handleCreateEntityAtPosition` (`:3725`) → `NSOpenPanel` (the app's convention; no `.fileImporter`).
4. **Guardrails** — reuse `InboxDropIngestService.maxFileBytes` (100MB); oversized or >200k-cell sheets degrade gracefully to Tier-0 + peek-in-default-app, never a beachball.

Also extend `InboxDropIngestService.attachmentKind(for:)` so xlsx/csv classify as `.spreadsheet` app-wide (currently `.document`/`.textFile`).

---

## 4. Phases

**Phase 1 — Universal file portal (foundation, ships value on day one)**
`AtomType.file` + `EntityType.file` + metadata shape; drop/paste/⌘K import; `media_attachments` storage + cloud mirror; `FilePortalThumbnailStore` (QLThumbnailGenerator); Tier-0 card view registered in the `CanvasBlockStaticView` switch (`CanvasView.swift:5955`); resize; peek→open-in-default-app; delete/undo/sync round-trip. *Every file type is now placeable and visible on canvas.*

**Phase 2 — Live PDF portal**
`PDFView` embed with identity-gated wrapper; enter-to-interact policy; gesture→bitmap swap; page state persisted to `viewState`; peek reuses the full `PDFSourceView` reader. This phase retires the two hard rendering problems for all future live portals.

**Phase 3 — Live spreadsheet portal**
CoreXLSX dependency + CSV parser; `SheetModel` + `SheetModelCache`; virtualized `FilePortalGridView` with pinned headers + sheet tabs; cell-count guardrails; peek→full-size grid. Read-only.

**Phase 4 — Portal power (post-validation)**
Range portals (a portal showing a *chosen* sheet range — true portal semantics); text extraction into search (`extractedText` on the attachment → ⌘K/Cortex indexing); remote-device blob UX polish (download progress on the card); consider docx live rendering only if demanded.

**Per-phase hygiene:** new Swift files registered via the existing pbxproj hook/`scripts/add_files_to_target.rb`; build via `xcodebuild`; tests via `swift test`.

---

## 5. Tests

- `FilePortalMetadata` codable: lenient decode (unknown keys, missing fields, old builds), merge-not-replace round-trip.
- CSV parser: RFC 4180 edge cases (quoted commas, newlines-in-cells, BOM, ragged rows).
- Grid virtualization math (visible-range calculation) — pure functions, `ImageResizeMathTests` style.
- Import pipeline: UTType routing, size caps, dedup of the attachment path.
- Sync: placement + atom + attachment enqueue on create; tombstone cascade on delete (existing invariants extended).

## 6. Risks (ranked)

1. **AppKit-under-zoom fidelity** — mitigated by gesture-time bitmap swap (Phase 2 gate; prototype first).
2. **Huge/hostile XLSX** — hard cell caps + streaming parse + Tier-0 fallback; CoreXLSX is DOM-based, so cap before parse by uncompressed-size heuristic.
3. **Scroll ambiguity** — enter-to-interact policy; usability-check that the affordance reads.
4. **Blob-sync gaps** (portal on device B before blob mirrors) — thumbnail-first rendering + explicit "downloading" state on the card.
5. **Canvas perf regressions** — every new view `Equatable`-gated, no `@Observable` reads in gesture paths, bench with `BlockEditorPerformanceBenchTests` habits.
