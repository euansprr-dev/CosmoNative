# Cosmo Universal Asset OS Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Cosmo into a local-first Universal Knowledge + Asset OS where every captured file, image, video, audio note, PDF, web page, swipe, source, and generated output becomes durable, searchable, segmented, connected, and reusable from Command-K, Thinkspaces, Canvas, Inquiry, Writing Mode, and agents.

**Architecture:** Add a first-class `Asset` subsystem beside `Atom`, not inside it. `Asset` owns raw files, previews, storage, processing state, segments, tags, embeddings, and relations; `Atom` continues to represent cognition, workflow, drafts, projects, sources, clients, and canvas entities. Search composes existing `AtomSearchEngine`, `HybridSearchEngine`, `ContextIndexStore`, and new asset indexes into one Command-K retrieval layer.

**Tech Stack:** Swift, SwiftUI, GRDB, SQLite FTS5, existing Cosmo Nomic embedding daemon, AVFoundation, Vision, PDFKit, Speech or WhisperKit path, AppKit thumbnails, local Application Support storage, existing Sync/Supabase abstractions, future S3/R2/B2-compatible object storage.

---

## Scope Check

This is too large for one implementation plan. Treat it as a program made of independent, testable subplans. Each subplan should ship value on its own and should be executed from a clean worktree.

Subplans:

1. Durable Asset Core
2. Local Storage Provider and File Ingest
3. Processing Queue and Status Model
4. Image and Screenshot Understanding
5. PDF, EPUB, Text, and Web Understanding
6. Video and Audio Moment Understanding
7. Asset Search Index and Retrieval Fusion
7.5. Smart Cluster Organizer and Zero-Query Command-K
8. Command-K Universal Asset Recall
9. Thinkspace Library Mode
10. Content Focus Asset Picker and Evidence Finder
11. Canvas, Inquiry, and Agent Integration
12. Cloud Storage and Sync Abstraction
13. Cost, Privacy, and Processing Controls
14. Epistemic Layer: Claims, Evidence, Contradictions

Do not start by implementing all processors. Start by making raw assets durable and searchable by explicit metadata. Then add understanding layers incrementally.

## Product Priorities

Build order and design decisions must optimize for these priorities:

1. Search any video, image, text file, PDF, source, swipe, Readwise import, idea, note, or segment by keyword. A query like `bed` must retrieve images of beds, video moments containing beds, PDF pages mentioning beds, notes about beds, and linked canvas/context objects.
2. Auto-sort uploads into intuitive zero-query Command-K clusters. Opening Command-K with an empty search should already feel like the system understands the library, active Thinkspace, current canvas, recent imports, active drafts, and useful next actions.
3. Integrate into the current Cosmo system without creating duplicate silos. Swipe file, Readwise, ideas, sources, notes, canvas objects, and captures remain their existing domain objects where appropriate; assets become the durable media/source substrate and relations connect everything.
4. Let the user upload anything and have it become immediately preserved, previewable, progressively processed, searchable, clusterable, and retrievable by manual search or AI retrieval.

These priorities mean Subplans 1 through 8 are the first shippable milestone. Thinkspace Library, Content Focus, Canvas, Inquiry, cloud sync, and epistemic evidence should build on top of that substrate rather than introducing separate search/indexing systems.

## Product Thesis

Google Drive stores files. Cosmo should understand raw creative material and make it callable at the point of work.

The core user failure is not "bad folder organization." It is that files, screenshots, videos, links, transcripts, notes, swipes, and evidence are scattered across apps and remembered by fragile clues. Folders represent project understanding, so Cosmo should keep folders as a projection. The canonical model must be relations plus searchable segments.

The product promise:

```text
Capture anything
-> preserve the original immediately
-> understand it asynchronously
-> attach it to active context
-> index it at asset and segment level
-> retrieve it naturally
-> reuse it in canvas, writing, inquiry, drafts, clips, claims, and outputs
```

The hard rule:

```text
An asset is usable before it is processed.
Processing improves recall. Processing is never required for preservation.
```

## Existing Codebase Context

Current primitives to reuse:

- `Data/Models/MediaAttachment.swift`: capture media exists but is tied to Telegram captured items.
- `Services/CaptureMediaStorage.swift`: local-first capture storage already preserves originals and thumbnails.
- `Agent/Context/ContextSource.swift`: shared context sources and chunks exist for retrieval.
- `Agent/Context/ContextIndexStore.swift`: persistent chunk store and `context_chunks_fts` exist.
- `Cosmo/HybridSearchEngine.swift`: atom hybrid search exists.
- `Data/Search/AtomSearchEngine.swift`: atom FTS exists.
- `UI/CommandK/CommandKViewModel.swift`: unified search and result cards exist.
- `UI/Library/LibraryView.swift`: Library item model and view model exist.
- `Canvas/ThinkspaceManager.swift`: Thinkspace project hierarchy and canvas block membership exist.
- `UI/FocusMode/Content/ContentFocusModeView.swift`: Writing workflow already searches swipes and related atoms.
- `UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift`: inquiry has a source consumption surface.

Architectural decision:

`MediaAttachment` becomes an ingest adapter or legacy bridge. It should not be stretched into the universal asset model because it is capture-lane-specific and lacks relations, versions, segment semantics, storage providers, and reusable processing jobs.

Integration rule:

Do not replace existing Cosmo object types with assets when those objects already have product meaning. Instead, link them.

- Swipe file items remain swipe/research atoms. Attached screenshots, videos, captions, pages, and source files become related assets.
- Readwise books and highlights remain Readwise/book/highlight objects. Imported PDFs, EPUBs, cover images, chapter pages, and quote source pages become related assets or asset segments.
- Ideas remain atoms. Images, voice notes, screenshots, documents, and links that caused or support an idea become related assets.
- Canvas blocks remain canvas appearances. A media block points to an `Asset` or `AssetSegment` instead of duplicating the underlying file.
- Inquiry sources remain source/workflow entries. PDF pages, video transcript chunks, web sections, and screenshots become asset segments that can be attached as source evidence.
- Telegram and other capture lanes remain capture lanes. Their media attachments flow through `AssetIngestService` and keep provenance relations back to the capture object.

## Target Mental Model

```text
Asset
  Original file or external source
  Stable identity, title, type, storage, processing status

AssetVersion
  Original, proxy, thumbnail, transcript, extracted text, page preview

AssetSegment
  Video scene, transcript chunk, image region, PDF page, book chapter, web section

AssetTag
  Manual, OCR, transcript, visual, AI, imported metadata

AssetRelation
  Links asset or segment to Thinkspace, client, question, claim, draft, canvas appearance, output

AssetProcessingJob
  Idempotent queued work that creates versions, segments, tags, and context chunks
```

## Primary Data Model

### `Asset`

Fields:

- `id: String`
- `title: String`
- `kind: AssetKind`
- `mimeType: String?`
- `fileHash: String?`
- `sourceApp: String?`
- `captureMethod: AssetCaptureMethod`
- `originalFilename: String?`
- `fileSize: Int64?`
- `duration: Double?`
- `pageCount: Int?`
- `pixelWidth: Int?`
- `pixelHeight: Int?`
- `canonicalURL: String?`
- `storageProvider: AssetStorageProviderKind`
- `storageKey: String?`
- `localCachePath: String?`
- `previewPath: String?`
- `thumbnailPath: String?`
- `processingStatus: AssetProcessingStatus`
- `syncStatus: AssetSyncStatus`
- `metadataJSON: String`
- `createdAt: String`
- `updatedAt: String`
- `isDeleted: Bool`

Kinds:

- image
- screenshot
- video
- audio
- voiceNote
- pdf
- epub
- webPage
- youtube
- instagram
- document
- markdown
- text
- archive
- unknown

### `AssetVersion`

Fields:

- `id`
- `assetId`
- `kind`: original, proxy, thumbnail, extractedText, transcript, pagePreview, frameSample, waveform
- `storageProvider`
- `storageKey`
- `localPath`
- `mimeType`
- `size`
- `metadataJSON`
- `createdAt`

### `AssetSegment`

Fields:

- `id`
- `assetId`
- `segmentType`: videoScene, videoFrame, transcriptChunk, audioChunk, pdfPage, bookChapter, webSection, imageRegion, fullAsset
- `ordinal`
- `startTime`
- `endTime`
- `pageNumber`
- `chapterTitle`
- `title`
- `text`
- `caption`
- `thumbnailPath`
- `anchor`
- `metadataJSON`
- `createdAt`
- `updatedAt`

Segment anchors:

- video: `00:35-00:47`
- transcript: `00:35.2`
- PDF: `p12`
- book: `chapter:3`
- web: `section:introduction`
- image: `region:x,y,w,h`

### `AssetTag`

Fields:

- `id`
- `assetId`
- `segmentId`
- `tag`
- `normalizedTag`
- `source`: user, filename, OCR, transcript, visual, metadata, AI
- `confidence`
- `createdAt`

### `AssetRelation`

Fields:

- `id`
- `assetId`
- `segmentId`
- `targetType`: atom, thinkspace, client, project, inquirySession, question, claim, draft, canvasBlock, output
- `targetId`
- `relationshipType`: belongsToThinkspace, sourceForQuestion, evidenceForClaim, usedInDraft, appearsOnCanvas, relatedToClient, partOfDeal, visualForOutput, importedFromCapture, clippedFromAsset
- `metadataJSON`
- `createdAt`

### `AssetProcessingJob`

Fields:

- `id`
- `assetId`
- `jobType`: metadata, thumbnail, proxy, OCR, transcription, frameSampling, visualTagging, embedding, pdfExtraction, webExtraction, relationSuggestion
- `status`: queued, running, completed, failed, skipped
- `priority`
- `attemptCount`
- `lastError`
- `createdAt`
- `startedAt`
- `completedAt`
- `updatedAt`

Idempotency key:

```text
assetId + jobType + sourceHash + processorVersion
```

## Storage Model

Storage is a separate concern from asset identity.

```text
AssetStorageProvider
  local
  iCloudDrive
  s3Compatible
  supabaseStorage
  externalURL
```

First shipping provider:

```text
~/Library/Application Support/Cosmo/Assets/
  originals/YYYY/MM/<asset-id>/<filename>
  thumbnails/YYYY/MM/<asset-id>.png
  previews/YYYY/MM/<asset-id>/
  derived/YYYY/MM/<asset-id>/
```

Never store user originals inside transient cache. Use Application Support for durable local originals. Use Caches only for regenerated previews.

## Processing Status Model

Asset-level status is a summary of jobs:

- `rawOnly`: original saved, no derived data.
- `previewReady`: thumbnail or proxy available.
- `partiallyIndexed`: at least one searchable field or segment exists.
- `indexed`: expected cheap processors completed.
- `aiEnhanced`: optional AI tagging/captions completed.
- `failed`: at least one required processor failed and no searchable result exists.
- `skipped`: unsupported or user disabled processing.

The UI should show job-level status when useful:

```text
Original saved
Thumbnail ready
OCR indexed
Transcript pending
Visual search pending
```

## Search Architecture

Command-K should not call each feature surface directly. Add an asset search service:

```text
AssetSearchService.search(request) -> AssetSearchResponse
```

Search request:

- query
- scope: global, thinkspace, project, client, activeDraft, activeInquiry
- allowedKinds
- includeSegments
- includeRelations
- maxResults
- purpose: recall, attachVisual, findEvidence, citeSource, createClip

Search response:

- groupedResults
- flatResults
- resultActions
- traceRows

Retrieval stages:

1. Normalize query and detect intent.
2. Exact title, filename, tag, URL, and metadata search.
3. FTS over asset title, captions, OCR, transcripts, extracted text.
4. Context chunk retrieval over indexed segments.
5. Vector search over segment embeddings.
6. Relation boost for active Thinkspace, client, draft, inquiry, question, and canvas.
7. Result fusion.
8. Deterministic rerank.
9. Optional cheap AI rerank for ambiguous visual/evidence searches.

Zero-query stages:

1. Resolve active context: current Thinkspace, canvas, selected block, active draft, active inquiry, frontmost pane, recent uploads, and pinned project.
2. Fetch recent and context-related assets, segments, swipes, Readwise highlights, ideas, sources, and canvas objects.
3. Build candidate clusters from relations, kinds, semantic neighborhoods, recency bursts, processing status, and action usefulness.
4. Score clusters by user intent probability: continue current work, review recent imports, attach visual, cite proof, resume source, open active Thinkspace media, inspect processing issues.
5. Deduplicate near-identical items and collapse low-value variants under a representative result.
6. Render stable cluster lanes with compact explanations, not opaque "AI sorted" labels.

Result types:

- asset
- assetSegment
- assetRelation
- atom
- thinkspace
- source
- readwiseBook
- swipe

Command-K should render these as rich cards, not text rows.

Cluster types:

- `Most Relevant`: best cross-type results for the active context or typed query.
- `Recent Imports`: new assets that were just preserved and may still be processing.
- `Video Moments`: timestamped segments with matching transcript, OCR, visual tags, or captions.
- `Images and Screenshots`: visual assets with OCR, captions, tags, and source provenance.
- `Documents and Pages`: PDF, EPUB, text, and web sections with page/chapter context.
- `Proof and Evidence`: assets or segments already linked to claims, questions, drafts, or source rails.
- `Swipes and References`: swipe atoms plus related media assets and source pages.
- `Readwise and Books`: book/highlight objects plus related PDFs, chapters, and pages.
- `Ideas and Notes`: idea/note atoms plus media or sources that support them.
- `Canvas Appearances`: current or related canvas objects pointing to assets or segments.
- `Processing Attention`: assets that are preserved but need user action, failed extraction, or optional enrichment.

Cluster output must be deterministic for the same library state. AI can generate labels or captions during processing, but the live cluster ordering should be explainable and testable.

## UI Moment

The emotional arc:

The user arrives with a vague clue and a working task. They leave with the exact reusable asset, moment, page, or proof already attached to the work surface.

### Command-K Universal Recall Layout

Empty search should show an understood library, not a blank grid:

```text
+--------------------------------------------------------------------------+
|  Search anything in Cosmo...                                  Database   |
+--------------------------------------------------------------------------+
|  Smart Clusters                                                491 items |
|                                                                          |
|  Most Relevant                                                           |
|  +----------------+  Josh / Walking Beam media                           |
|  | thumbnails     |  22 assets  rooms, tour footage, rent docs            |
|  +----------------+  Open   Browse   Attach to draft                      |
|                                                                          |
|  Recent Imports                  Video Moments                           |
|  +---------------+ +----------+  +----------------+  00:35 bedroom / bed  |
|  | room photos   | | rent PDF |  | frame thumb    |  Walking Beam Tour    |
|  +---------------+ +----------+  +----------------+  Open   Clip   Canvas |
|                                                                          |
|  Proof and Evidence              Swipes and References                    |
|  +----------------+  Page 3     +----------------+  Best Airbnb reel refs |
|  | page preview   |  bed count  | swipe thumb     |  screenshots + notes  |
|  +----------------+  Cite       +----------------+  Open   Use            |
+--------------------------------------------------------------------------+
```

Typed search narrows the same clustered surface:

```text
+--------------------------------------------------------------------------+
|  Search anything in Cosmo...                                  Filters    |
+--------------------------------------------------------------------------+
|  bed                                                                     |
|                                                                          |
|  Video Moments                                                           |
|  +----------------+  Walking Beam Tour                                   |
|  | thumbnail      |  00:35-00:47  bedroom / bed / window                 |
|  | frame          |  Josh / Walking Beam Deal                            |
|  +----------------+  Open   Preview   Attach   Canvas   Clip             |
|                                                                          |
|  Images                                                                  |
|  +----------------+  Room 2 Bedroom                                      |
|  | image thumb    |  bedroom / twin bed / dresser                        |
|  +----------------+  Open   Attach   Canvas                              |
|                                                                          |
|  Evidence                                                                |
|  +----------------+  Rent Breakdown PDF                                  |
|  | page preview   |  Page 3  bedroom count affects revenue               |
|  +----------------+  Open   Cite   Link claim                            |
+--------------------------------------------------------------------------+
```

Command-K stays keyboard-first:

- Up/down moves through every flat result.
- Tab moves through actions on the selected result.
- Return triggers the primary action for the current surface.
- Space opens preview.
- Command-Return opens source.
- Option-Return attaches to current draft or canvas if context exists.

### Thinkspace Library Mode

```text
Josh
+-------------------------------------------------------------------------+
| Canvas | Library | Inquiry | Model | Outputs                             |
+-------------------------------------------------------------------------+
|  Search Josh assets...            Type  Status  Source  Used In          |
|                                                                         |
|  Property Media                                                         |
|  [video] Walking Beam Tour       18 segments  indexed   3 drafts         |
|  [image] Room 2 Bedroom          bedroom     indexed   canvas            |
|                                                                         |
|  Deal Docs                                                              |
|  [pdf] Rent Breakdown            12 pages    indexed   claim evidence    |
|                                                                         |
|  Swipe References                                                       |
|  [ig] Sober Living Reel          caption     partial   source rail       |
+-------------------------------------------------------------------------+
```

Thinkspace Library is inventory plus scoping. Canvas remains curated spatial thought.

### Content Focus Asset Picker

```text
+-------------------------------- Writing --------------------------------+
| Slide 2                                                                  |
| Look at this bedroom...                                                   |
|                                                                          |
+----------------------------- Asset Assist ------------------------------+
| Suggested visuals                                                        |
| [thumb] Walking Beam Tour  00:35-00:47  bedroom with bed                 |
| [thumb] Room 2 Bedroom     image       twin bed and dresser              |
|                                                                          |
| Suggested proof                                                          |
| [page]  Rent Breakdown     p3          bedroom count affects revenue     |
|                                                                          |
| Attach selected   Cite proof   Bring to canvas                           |
+-------------------------------------------------------------------------+
```

The asset picker reads active paragraph, active Thinkspace, active client, draft metadata, and selected outline item.

## Program Execution Rules

1. Use TDD for repository, search, ranking, queue, and processor behavior.
2. Use preview-driven visual checks for Command-K, Library mode, and picker cards.
3. Keep all processors idempotent.
4. Never block capture on AI.
5. Never delete originals when processing fails.
6. Use local cheap processors first.
7. Cache AI outputs with processor version and asset hash.
8. Every search result must explain why it matched.
9. Every asset must support at least one useful action.
10. Every user-facing processing failure must preserve the asset and offer retry.

---

# Subplan 1: Durable Asset Core

**Goal:** Add asset schema, models, repository, migrations, and tests without changing UI behavior.

**Primary files:**

- Create `Data/Models/Asset.swift`
- Create `Data/Models/AssetVersion.swift`
- Create `Data/Models/AssetSegment.swift`
- Create `Data/Models/AssetTag.swift`
- Create `Data/Models/AssetRelation.swift`
- Create `Data/Models/AssetProcessingJob.swift`
- Create `Data/Repositories/AssetRepository.swift`
- Create `Data/Repositories/AssetSegmentRepository.swift`
- Create `Data/Repositories/AssetRelationRepository.swift`
- Modify `Data/Database/CosmoDatabase.swift`
- Create `Tests/CosmoOSTests/AssetRepositoryTests.swift`

**Tasks:**

- [ ] Add GRDB models with explicit `databaseTableName`, `Codable`, `Equatable`, `FetchableRecord`, `PersistableRecord`, and `Sendable`.
- [ ] Add migrations for `assets`, `asset_versions`, `asset_segments`, `asset_tags`, `asset_relations`, and `asset_processing_jobs`.
- [ ] Add indexes for `assetId`, `kind`, `processingStatus`, `fileHash`, relation target, and queued jobs.
- [ ] Add `assets_fts` virtual table indexing title, filename, metadata, tags, captions, OCR text, transcript text, and segment text.
- [ ] Add repository methods:
  - `createAsset(_:)`
  - `fetchAsset(id:)`
  - `fetchAssets(scope:)`
  - `updateProcessingStatus(assetId:status:)`
  - `upsertVersion(_:)`
  - `upsertSegment(_:)`
  - `upsertTag(_:)`
  - `upsertRelation(_:)`
  - `enqueueJob(_:)`
  - `claimNextJob(types:)`
  - `completeJob(id:)`
  - `failJob(id:error:)`
- [ ] Write tests proving:
  - duplicate `fileHash` can be detected before a second original is stored.
  - an asset can exist without any segment.
  - segment anchors persist.
  - relation target lookup works for Thinkspaces and drafts.
  - job claiming is atomic enough that two workers do not claim the same job.

**Verification command:**

```bash
swift test --filter AssetRepositoryTests
```

Expected result:

```text
Test Suite 'AssetRepositoryTests' passed
```

**Commit:**

```bash
git add Data/Models Data/Repositories Data/Database/CosmoDatabase.swift Tests/CosmoOSTests/AssetRepositoryTests.swift
git commit -m "feat: add durable asset core"
```

---

# Subplan 2: Local Storage Provider and File Ingest

**Goal:** Save any incoming file as a durable local asset with hash, metadata, thumbnail when cheap, and initial relations.

**Primary files:**

- Create `Services/Assets/AssetStorageProvider.swift`
- Create `Services/Assets/LocalAssetStorageProvider.swift`
- Create `Services/Assets/AssetIngestService.swift`
- Create `Services/Assets/AssetFileInspector.swift`
- Create `Services/Assets/AssetHashing.swift`
- Modify `Services/CaptureMediaStorage.swift`
- Modify `Data/Repositories/MediaAttachmentRepository.swift`
- Create `Tests/CosmoOSTests/AssetIngestServiceTests.swift`

**Storage API:**

```swift
protocol AssetStorageProvider: Sendable {
    func storeOriginal(data: Data, filename: String?, assetId: String, date: Date) throws -> StoredAssetObject
    func storeDerived(data: Data, filename: String, assetId: String, kind: AssetVersionKind, date: Date) throws -> StoredAssetObject
    func localURL(for object: StoredAssetObject) -> URL?
    func deleteLocalObject(_ object: StoredAssetObject) throws
}
```

**Ingest API:**

```swift
struct AssetIngestRequest: Sendable {
    var data: Data
    var originalFilename: String?
    var mimeType: String?
    var sourceApp: String?
    var captureMethod: AssetCaptureMethod
    var activeThinkspaceId: String?
    var activeAtomUUID: String?
    var metadata: [String: String]
}
```

**Tasks:**

- [ ] Write a failing ingest test that creates an image asset from raw data and asserts original file path, hash, kind, and queued thumbnail/OCR jobs.
- [ ] Implement SHA-256 hashing in `AssetHashing`.
- [ ] Implement MIME and extension inference in `AssetFileInspector`.
- [ ] Implement `LocalAssetStorageProvider` using Application Support.
- [ ] Implement `AssetIngestService.ingest(request:)`.
- [ ] Add relation creation to active Thinkspace and active Atom when provided.
- [ ] Add media attachment bridge:
  - When a `MediaAttachment` reaches downloaded status, create or link an `Asset`.
  - Store `MediaAttachment.sourceObjectId = asset.id`.
- [ ] Add tests for dedupe:
  - Same bytes do not create two stored originals unless explicitly imported as a separate asset.
  - Same bytes can have multiple relations.

**Verification command:**

```bash
swift test --filter AssetIngestServiceTests
```

**Commit:**

```bash
git add Services/Assets Data/Repositories Tests/CosmoOSTests
git commit -m "feat: add local asset ingest"
```

---

# Subplan 3: Processing Queue and Status Model

**Goal:** Add an idempotent local processing queue that runs cheap processors in priority order and updates asset status.

**Primary files:**

- Create `Services/Assets/Processing/AssetProcessingCoordinator.swift`
- Create `Services/Assets/Processing/AssetProcessor.swift`
- Create `Services/Assets/Processing/AssetProcessingStatusResolver.swift`
- Create `Services/Assets/Processing/AssetProcessingScheduler.swift`
- Create `Tests/CosmoOSTests/AssetProcessingQueueTests.swift`

**Processor protocol:**

```swift
protocol AssetProcessor: Sendable {
    var jobType: AssetProcessingJobType { get }
    var processorVersion: String { get }
    func canProcess(asset: Asset) -> Bool
    func process(asset: Asset, repository: AssetRepository) async throws -> AssetProcessingOutput
}
```

**Tasks:**

- [ ] Write tests for job ordering by priority and creation date.
- [ ] Write tests for idempotency key behavior.
- [ ] Implement scheduler that enqueues expected jobs based on asset kind.
- [ ] Implement coordinator that claims one job, marks running, executes processor, stores output, and completes or fails.
- [ ] Implement status resolver:
  - no successful jobs -> `rawOnly`
  - thumbnail or proxy complete -> `previewReady`
  - any searchable segment or text complete -> `partiallyIndexed`
  - all required cheap jobs complete -> `indexed`
  - AI jobs complete -> `aiEnhanced`
- [ ] Add retry rules:
  - auto retry up to 2 times for transient file read failures.
  - mark failed with `lastError` after max attempts.
  - leave asset usable.

**Verification command:**

```bash
swift test --filter AssetProcessingQueueTests
```

**Commit:**

```bash
git add Services/Assets/Processing Tests/CosmoOSTests/AssetProcessingQueueTests.swift
git commit -m "feat: add asset processing queue"
```

---

# Subplan 4: Image and Screenshot Understanding

**Goal:** Make images and screenshots searchable by title, OCR, visual labels, caption, and thumbnail.

**Primary files:**

- Create `Services/Assets/Processing/ImageThumbnailProcessor.swift`
- Create `Services/Assets/Processing/ImageOCRProcessor.swift`
- Create `Services/Assets/Processing/ImageCaptionProcessor.swift`
- Create `Services/Assets/Processing/ImageMetadataProcessor.swift`
- Create `Data/Search/AssetFTSIndexer.swift`
- Create `Tests/CosmoOSTests/ImageAssetProcessingTests.swift`

**Processor behavior:**

- Thumbnail: AppKit resize to max side 768 px.
- Metadata: dimensions, color profile where easy, file size.
- OCR: Vision `VNRecognizeTextRequest`.
- Caption: first version can be deterministic local tags from OCR, filename, and metadata. AI caption is optional job after cheap index works.

**Tasks:**

- [ ] Add a fixture image with text and assert OCR text creates a searchable segment.
- [ ] Add a fixture bedroom/property image and assert manually supplied test caption can be indexed.
- [ ] Generate thumbnail version and set `asset.thumbnailPath`.
- [ ] Create one `AssetSegment` of type `fullAsset` for image-level OCR/caption.
- [ ] Add `AssetTag` rows from OCR terms and visual labels.
- [ ] Update `assets_fts` on segment/tag changes.
- [ ] Search test:
  - query "bedroom"
  - returns image asset by tag or caption.
  - query OCR word
  - returns screenshot/image segment.

**Verification command:**

```bash
swift test --filter ImageAssetProcessingTests
```

**Commit:**

```bash
git add Services/Assets/Processing Data/Search Tests/CosmoOSTests/ImageAssetProcessingTests.swift
git commit -m "feat: index image and screenshot assets"
```

---

# Subplan 5: PDF, EPUB, Text, and Web Understanding

**Goal:** Make documents searchable by page, section, chapter, URL metadata, citations, and extracted text.

**Primary files:**

- Create `Services/Assets/Processing/PDFExtractionProcessor.swift`
- Create `Services/Assets/Processing/PDFThumbnailProcessor.swift`
- Create `Services/Assets/Processing/TextDocumentProcessor.swift`
- Create `Services/Assets/Processing/WebAssetExtractionProcessor.swift`
- Modify `Cosmo/WebsiteCapture.swift`
- Modify `Cosmo/YouTubeProcessor.swift`
- Create `Tests/CosmoOSTests/DocumentAssetProcessingTests.swift`

**PDF behavior:**

- Extract page count with PDFKit.
- Create one segment per page.
- Store `anchor = p<pageNumber>`.
- Store page preview thumbnails for first N pages, with N configurable and first pass at 12.
- If a page has no text, enqueue OCR page processing.

**Text and Markdown behavior:**

- Split by headings when possible.
- Fall back to chunk size of roughly 800 to 1200 tokens.
- Preserve line or section anchors when easy.

**Web behavior:**

- Store canonical URL, title, preview image, source site.
- Extract page text through existing `WebsiteCapture` where possible.
- Create segments per heading/section.

**YouTube behavior:**

- Store URL and metadata as an asset.
- Transcript processor creates transcript chunks.
- Thumbnail is from YouTube metadata when available.

**Tasks:**

- [ ] Add a small fixture PDF and test page segments.
- [ ] Add markdown fixture and test heading anchors.
- [ ] Add URL fixture with injected extraction response and test canonical URL storage.
- [ ] Ensure document segments are upserted into `ContextIndexStore` as `ContextChunk`.
- [ ] Ensure Command-K can display PDF result as page preview with page number.

**Verification command:**

```bash
swift test --filter DocumentAssetProcessingTests
```

**Commit:**

```bash
git add Services/Assets/Processing Cosmo Data/Search Tests/CosmoOSTests/DocumentAssetProcessingTests.swift
git commit -m "feat: index document and web assets"
```

---

# Subplan 6: Video and Audio Moment Understanding

**Goal:** Make videos and audio searchable by transcript, sampled frames, merged scenes, and exact timestamps.

**Primary files:**

- Create `Services/Assets/Processing/VideoMetadataProcessor.swift`
- Create `Services/Assets/Processing/VideoThumbnailProcessor.swift`
- Create `Services/Assets/Processing/VideoFrameSampler.swift`
- Create `Services/Assets/Processing/VideoSceneMerger.swift`
- Create `Services/Assets/Processing/AudioTranscriptionProcessor.swift`
- Create `Services/Assets/Processing/TranscriptSegmenter.swift`
- Create `Tests/CosmoOSTests/VideoAssetProcessingTests.swift`

**Video pipeline:**

```text
original saved
-> metadata
-> poster thumbnail
-> proxy when file is large
-> audio transcription
-> frame samples every 2-5 seconds
-> frame labels/captions
-> merge adjacent similar frames into scenes
-> index scenes and transcript chunks
```

**Scene merge rules:**

- Adjacent frames with overlapping tags and similar captions merge.
- Scene max duration defaults to 30 seconds.
- Transcript segments can overlap scenes by time.
- Search can return a visual scene, transcript moment, or combined moment.

**Tasks:**

- [ ] Add test fixture metadata abstraction so tests do not require a large video.
- [ ] Test that frame samples at 0, 5, 10 seconds merge into one scene when tags overlap.
- [ ] Test that unrelated frame tags create separate scenes.
- [ ] Test transcript query "rent structure" returns a timestamp segment.
- [ ] Test visual query "bed" returns a video scene segment with `startTime` and `endTime`.
- [ ] Add action payload for `openAtTimestamp`.
- [ ] Add action payload for `createClip`.

**Verification command:**

```bash
swift test --filter VideoAssetProcessingTests
```

**Commit:**

```bash
git add Services/Assets/Processing Tests/CosmoOSTests/VideoAssetProcessingTests.swift
git commit -m "feat: index video and audio moments"
```

---

# Subplan 7: Asset Search Index and Retrieval Fusion

**Goal:** Search assets and segments across exact, FTS, tags, semantic chunks, timestamps, and relations.

**Primary files:**

- Create `Data/Search/AssetSearchService.swift`
- Create `Data/Search/AssetSearchTypes.swift`
- Create `Data/Search/AssetSearchRanker.swift`
- Create `Data/Search/AssetContextChunkAdapter.swift`
- Create `Tests/CosmoOSTests/AssetSearchServiceTests.swift`

**Result model:**

```swift
struct AssetSearchResult: Identifiable, Sendable, Equatable {
    var id: String
    var assetId: String
    var segmentId: String?
    var kind: AssetSearchResultKind
    var title: String
    var subtitle: String
    var snippet: String?
    var thumbnailPath: String?
    var score: Double
    var matchReasons: [String]
    var actions: [AssetResultAction]
}
```

**Ranking inputs:**

- exact title match
- filename match
- tag match
- FTS BM25
- semantic score
- active Thinkspace relation
- active client relation
- active draft relation
- recency
- processing completeness
- action usefulness for current surface

**Tasks:**

- [ ] Write test where "bed" finds image tag, video scene, and PDF page, grouped correctly.
- [ ] Write test where active Thinkspace boosts related asset over global asset with same tag.
- [ ] Write test where exact filename beats semantic near match.
- [ ] Write test where segment result includes action list.
- [ ] Implement `AssetSearchService.search`.
- [ ] Implement deterministic fusion and ranking in `AssetSearchRanker`.
- [ ] Add trace rows for debugging search quality.

**Verification command:**

```bash
swift test --filter AssetSearchServiceTests
```

**Commit:**

```bash
git add Data/Search Tests/CosmoOSTests/AssetSearchServiceTests.swift
git commit -m "feat: add asset search service"
```

---

# Subplan 7.5: Smart Cluster Organizer and Zero-Query Command-K

**Goal:** Make Command-K useful before the user types by auto-sorting uploads and existing Cosmo objects into stable, intuitive, explainable clusters.

**Primary files:**

- Create `Data/Search/SmartClusterService.swift`
- Create `Data/Search/SmartClusterTypes.swift`
- Create `Data/Search/SmartClusterRanker.swift`
- Create `Data/Search/SmartClusterExplainer.swift`
- Create `Data/Search/UnifiedCosmoSearchAdapter.swift`
- Create `Tests/CosmoOSTests/SmartClusterServiceTests.swift`

**Cluster model:**

```swift
struct SmartCluster: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var intent: SmartClusterIntent
    var score: Double
    var items: [SmartClusterItem]
    var explanation: String
}

struct SmartClusterItem: Identifiable, Sendable, Equatable {
    var id: String
    var sourceKind: SmartClusterItemKind
    var sourceId: String
    var assetId: String?
    var segmentId: String?
    var title: String
    var subtitle: String
    var thumbnailPath: String?
    var matchReasons: [String]
    var actions: [AssetResultAction]
}

enum SmartClusterIntent: String, Sendable {
    case continueCurrentWork
    case reviewRecentImports
    case attachVisual
    case findProof
    case resumeSource
    case browseThinkspace
    case inspectProcessing
    case exploreRelated
}

enum SmartClusterItemKind: String, Sendable {
    case asset
    case assetSegment
    case atom
    case swipe
    case readwiseHighlight
    case readwiseBook
    case idea
    case source
    case canvasObject
    case thinkspace
}
```

**Ranking contract:**

- Empty query ranking is not alphabetical, not raw recency, and not folder-like.
- Ranking combines active context, recent upload bursts, relations, semantic neighborhoods, item quality, processing readiness, and action usefulness.
- Upload bursts become clusters such as "Imported just now", "Josh / Walking Beam media", "Rooms and property visuals", or "Documents to extract".
- Existing Cosmo objects appear in clusters through `UnifiedCosmoSearchAdapter`; they are not copied into asset tables.
- Every item must expose at least one concrete reason, such as `recent import`, `linked to Josh`, `bedroom visual tag`, `used in current draft`, `appears on canvas`, or `PDF page match`.
- Cluster titles can be deterministic templates. AI-generated titles are allowed only when cached and backed by deterministic fallback labels.

**Tasks:**

- [ ] Write test where empty Command-K groups recent uploaded bedroom photos and videos into a visual cluster.
- [ ] Write test where active Thinkspace assets outrank global recent assets.
- [ ] Write test where swipe, Readwise, idea, and asset results coexist without duplicated cards.
- [ ] Write test where failed or pending processing assets appear under `Processing Attention` instead of disappearing.
- [ ] Write test where cluster explanations include deterministic match reasons.
- [ ] Implement `UnifiedCosmoSearchAdapter` to collect existing atoms, swipes, Readwise items, ideas, sources, canvas objects, and asset results into one candidate type.
- [ ] Implement `SmartClusterRanker` with weighted scoring for context, relation strength, recency burst, semantic similarity, processing readiness, and action usefulness.
- [ ] Implement `SmartClusterService.clusters(for:)` for empty-query and typed-query cluster output.
- [ ] Implement `SmartClusterExplainer` so UI can show concise reasons without exposing raw weights.
- [ ] Add tracing rows for cluster score debugging.

**Suggested deterministic weights:**

```text
active Thinkspace relation: +35
current draft or inquiry relation: +30
appears on active canvas: +24
recent upload burst: +20
exact typed match: +40
visual/OCR/transcript/PDF tag match: +28
semantic neighborhood match: +18
manual tag: +16
AI tag with high confidence: +12
thumbnail or preview ready: +6
action useful for current surface: +8
processing failed but user-actionable: +10 inside Processing Attention only
near duplicate penalty: -18
stale unrelated item penalty: -12
```

Weights are starting values. Keep them in a small configuration type and expose trace rows so search quality can be tuned without changing UI code.

**Verification command:**

```bash
swift test --filter SmartClusterServiceTests
```

**Commit:**

```bash
git add Data/Search Tests/CosmoOSTests/SmartClusterServiceTests.swift
git commit -m "feat: add smart command-k clusters"
```

---

# Subplan 8: Command-K Universal Asset Recall

**Goal:** Extend Command-K unified search to include asset and asset segment results with rich cards and contextual actions.

**Primary files:**

- Modify `UI/CommandK/CommandKViewModel.swift`
- Modify `UI/CommandK/UnifiedSearchResultsView.swift`
- Create `UI/CommandK/AssetSearchResultCard.swift`
- Create `UI/CommandK/AssetMomentResultCard.swift`
- Create `UI/CommandK/AssetResultActionBar.swift`
- Create `UI/CommandK/AssetPreviewPopover.swift`
- Create `Tests/CosmoOSTests/CommandKAssetSearchTests.swift`

**View model integration:**

- Add `assetSearchResults`.
- Add `smartClusters`.
- Add `assetCardItems`.
- Add `.asset` and `.assetSegment` to unified source/card enums.
- Add `performAssetSearch(query:)` inside unified search update.
- Add `performSmartClusterSearch(query:)` for empty-query and typed-query clustered layout.
- Merge asset results with existing atom, swipe, idea, Readwise, and Thinkspace results.

**Card behavior:**

- Video moment card shows thumbnail, title, timestamp range, tags, Thinkspace path, and actions.
- Image card shows thumbnail, title, tags, Thinkspace path, and actions.
- PDF card shows page preview, page number, matching snippet, and actions.
- Audio card shows waveform preview, timestamp, transcript snippet, and actions.

**Actions:**

- Open
- Preview
- Bring to Canvas
- Attach to Draft
- Copy Timestamp
- Create Clip
- Link to Active Question
- Use as Evidence

**Tasks:**

- [ ] Write ViewModel test proving asset results appear in `unifiedFlatResults`.
- [ ] Write ViewModel test proving empty query renders smart clusters instead of an unstructured database grid.
- [ ] Write ViewModel test proving selected result actions are surface-aware.
- [ ] Implement asset card enum cases.
- [ ] Implement cluster lane rendering for zero-query Command-K.
- [ ] Implement reusable `AssetResultActionBar`.
- [ ] Implement preview popover for images, PDFs, video frame, and transcript snippet.
- [ ] Add keyboard handling for primary and secondary asset actions.
- [ ] Add empty state copy that mentions media, pages, transcripts, and assets.

**Verification commands:**

```bash
swift test --filter CommandKAssetSearchTests
swift build
```

**Commit:**

```bash
git add UI/CommandK Tests/CosmoOSTests/CommandKAssetSearchTests.swift
git commit -m "feat: add assets to command-k recall"
```

---

# Subplan 9: Thinkspace Library Mode

**Goal:** Add a Library tab inside Thinkspace that shows all assets related to the current Thinkspace and child Thinkspaces.

**Primary files:**

- Modify `Canvas/CanvasView.swift` only at the mode routing boundary.
- Create `UI/ThinkspaceLibrary/ThinkspaceLibraryView.swift`
- Create `UI/ThinkspaceLibrary/ThinkspaceLibraryViewModel.swift`
- Create `UI/ThinkspaceLibrary/ThinkspaceAssetGrid.swift`
- Create `UI/ThinkspaceLibrary/ThinkspaceAssetInspector.swift`
- Create `UI/ThinkspaceLibrary/ThinkspaceAssetFilters.swift`
- Create `Tests/CosmoOSTests/ThinkspaceLibraryTests.swift`

**Information architecture:**

- Property Media
- Deal Docs
- Swipe References
- Research Sources
- Voice Notes
- Draft Attachments
- Canvas Appearances
- Unsorted in This Thinkspace

**Tasks:**

- [ ] Add a Thinkspace mode enum if the current routing does not already support Canvas/Library/Inquiry/Model/Outputs.
- [ ] Implement view model query:
  - direct `belongsToThinkspace` relations.
  - assets related to atoms appearing on the Thinkspace canvas.
  - assets related to child Thinkspaces when "include children" is enabled.
- [ ] Implement filters by type, processing status, source app, relation type, and used-in-output.
- [ ] Implement grid and list modes.
- [ ] Implement inspector showing segments, tags, relations, processing jobs, and retry buttons.
- [ ] Add drag action from asset card to canvas.
- [ ] Add test proving Thinkspace scope excludes unrelated global assets.
- [ ] Add test proving child Thinkspace inclusion works.

**Verification commands:**

```bash
swift test --filter ThinkspaceLibraryTests
swift build
```

**Commit:**

```bash
git add UI/ThinkspaceLibrary Canvas/CanvasView.swift Tests/CosmoOSTests/ThinkspaceLibraryTests.swift
git commit -m "feat: add thinkspace asset library"
```

---

# Subplan 10: Content Focus Asset Picker and Evidence Finder

**Goal:** Let Writing Mode ask for visuals or proof based on the current draft, selected paragraph, active client, and Thinkspace.

**Primary files:**

- Create `UI/FocusMode/Content/AssetAssist/ContentAssetPickerView.swift`
- Create `UI/FocusMode/Content/AssetAssist/ContentAssetPickerViewModel.swift`
- Create `UI/FocusMode/Content/AssetAssist/ContentEvidenceFinder.swift`
- Create `UI/FocusMode/Content/AssetAssist/ContentAssetAttachmentService.swift`
- Modify `UI/FocusMode/Content/ContentFocusModeState.swift`
- Modify `UI/FocusMode/Content/ContentFocusModeView.swift`
- Create `Tests/CosmoOSTests/ContentAssetPickerTests.swift`

**Modes:**

- Find Visual
- Find Proof
- Find Swipe
- Attach Current Result
- Cite Source

**Query assembly inputs:**

- selected text or paragraph
- current outline item
- draft title
- active client profile UUID
- active Thinkspace UUID
- inherited swipe UUIDs
- active inquiry/question if present

**Tasks:**

- [ ] Add state for attached asset IDs and segment IDs in `ContentFocusModeState`.
- [ ] Add tests for query assembly from selected paragraph plus Thinkspace.
- [ ] Implement visual search request with allowed kinds image, screenshot, video.
- [ ] Implement evidence search request with allowed kinds pdf, webPage, youtube, document, note, research.
- [ ] Implement attachment service that records `AssetRelation.usedInDraft`.
- [ ] Render attached assets inside the draft sidebar/source rail.
- [ ] Add "Find me a visual for this" command in Writing AI card action list.
- [ ] Add "Find strongest proof" command.

**Verification commands:**

```bash
swift test --filter ContentAssetPickerTests
swift build
```

**Commit:**

```bash
git add UI/FocusMode/Content/AssetAssist UI/FocusMode/Content Tests/CosmoOSTests/ContentAssetPickerTests.swift
git commit -m "feat: add content asset picker"
```

---

# Subplan 11: Canvas, Inquiry, and Agent Integration

**Goal:** Make assets usable across core Cosmo workflows rather than searchable only.

**Primary files:**

- Create `Canvas/AssetBlockView.swift`
- Create `Canvas/AssetSegmentBlockView.swift`
- Modify `Canvas/CanvasBlock.swift`
- Modify `Canvas/SpatialEngine.swift`
- Modify `UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift`
- Modify `Agent/Context/ContextSource.swift`
- Modify `Agent/Context/ContextIndexStore.swift`
- Create `Agent/Context/AssetContextBridge.swift`
- Create `Tests/CosmoOSTests/AssetWorkflowIntegrationTests.swift`

**Canvas behavior:**

- Dropping an asset creates a canvas appearance relation.
- Dropping a segment creates a segment block with timestamp/page anchor.
- Opening a video segment opens asset preview at timestamp.
- Opening a PDF segment opens source pane at page.

**Inquiry behavior:**

- Assets can be source rail items.
- Segments can be evidence for questions or claims.
- Citation/export includes asset title and anchor.

**Agent behavior:**

- Assets and segments become context sources.
- Agents can search asset segments when tool permissions allow.
- Context packs include provenance lines with asset anchors.

**Tasks:**

- [ ] Add asset entity cases without breaking existing canvas block persistence.
- [ ] Add relation creation when canvas block appears.
- [ ] Add Inquiry source row for asset segments.
- [ ] Add `AssetContextBridge` to convert asset segments into `ContextSource` and `ContextChunk`.
- [ ] Add tests for asset segment included in context pack.
- [ ] Add tests for canvas relation creation.

**Verification commands:**

```bash
swift test --filter AssetWorkflowIntegrationTests
swift build
```

**Commit:**

```bash
git add Canvas UI/FocusMode/Inquiry Agent/Context Tests/CosmoOSTests/AssetWorkflowIntegrationTests.swift
git commit -m "feat: connect assets to canvas inquiry and agents"
```

---

# Subplan 12: Cloud Storage and Sync Abstraction

**Goal:** Prepare assets for terabyte-scale storage without breaking local-first behavior.

**Primary files:**

- Create `Services/Assets/Storage/AssetStorageProviderRegistry.swift`
- Create `Services/Assets/Storage/AssetSyncPlanner.swift`
- Create `Services/Assets/Storage/AssetCachePolicy.swift`
- Create `Sync/AssetSyncService.swift`
- Modify `Sync/SupabaseClient.swift` only if needed for storage primitives.
- Create `Tests/CosmoOSTests/AssetSyncPlanningTests.swift`

**Behavior:**

- Originals can be local-only, cloud-backed, or external URL-backed.
- Thumbnails and previews stay cached locally.
- Search indexes stay local.
- Missing originals download on demand.
- Asset metadata syncs before large binary sync.

**Sync statuses:**

- localOnly
- queuedUpload
- uploading
- synced
- queuedDownload
- downloading
- remoteOnly
- conflict
- failed

**Tasks:**

- [ ] Add sync status fields to repository queries.
- [ ] Implement cache policy:
  - keep recent originals.
  - keep all thumbnails.
  - keep all text indexes.
  - allow offloading large originals only after successful upload.
- [ ] Implement sync planner test for local-only to queued upload.
- [ ] Implement sync planner test for remote-only asset opening.
- [ ] Implement conflict handling rule:
  - metadata conflict keeps newest metadata.
  - binary conflict creates new `AssetVersion`, never overwrites silently.

**Verification command:**

```bash
swift test --filter AssetSyncPlanningTests
```

**Commit:**

```bash
git add Services/Assets/Storage Sync Tests/CosmoOSTests/AssetSyncPlanningTests.swift
git commit -m "feat: add asset sync planning"
```

---

# Subplan 13: Cost, Privacy, and Processing Controls

**Goal:** Give users and the system clear control over local/cloud processing cost, privacy, and quality.

**Primary files:**

- Create `Settings/AssetProcessingSettingsTab.swift`
- Create `Services/Assets/Processing/AssetProcessingPolicy.swift`
- Create `Services/Assets/Processing/AssetCostEstimator.swift`
- Create `Tests/CosmoOSTests/AssetProcessingPolicyTests.swift`

**Policies:**

- Local only
- Local first, cheap cloud allowed
- Cloud enhanced on demand
- Never process sensitive assets
- Process only when attached to project or Thinkspace

**Controls:**

- OCR images
- Transcribe audio/video
- Sample video frames
- Generate AI captions
- Generate embeddings
- Process while on battery
- Monthly AI budget
- Per-asset retry/reprocess

**Tasks:**

- [ ] Add policy object and defaults.
- [ ] Add tests for policy gating:
  - sensitive asset blocks cloud AI job.
  - low battery blocks expensive job.
  - user-triggered reprocess overrides queue delay but not privacy rules.
- [ ] Add settings UI with toggles and estimated cost labels.
- [ ] Add processing trace view in asset inspector.

**Verification commands:**

```bash
swift test --filter AssetProcessingPolicyTests
swift build
```

**Commit:**

```bash
git add Settings Services/Assets/Processing Tests/CosmoOSTests/AssetProcessingPolicyTests.swift
git commit -m "feat: add asset processing controls"
```

---

# Subplan 14: Epistemic Layer: Claims, Evidence, Contradictions

**Goal:** Upgrade assets from recall objects into evidence objects that support claims, questions, and source-backed output.

**Primary files:**

- Create `Data/Models/Claim.swift`
- Create `Data/Models/ClaimEvidence.swift`
- Create `Data/Repositories/ClaimRepository.swift`
- Create `UI/FocusMode/Inquiry/Evidence/ClaimEvidencePanel.swift`
- Create `Services/Knowledge/EvidenceSearchService.swift`
- Create `Services/Knowledge/ContradictionScanner.swift`
- Create `Tests/CosmoOSTests/EpistemicAssetTests.swift`

**Claim model:**

- claim text
- status: draft, supported, speculative, contradicted, retired
- confidence
- owning Thinkspace/question/client/project
- created source

**Evidence model:**

- claimId
- assetId
- segmentId
- quote or extracted snippet
- support type: supports, weaklySupports, contradicts, contextOnly
- provenance title and anchor
- confidence

**Tasks:**

- [ ] Add claim/evidence schema.
- [ ] Add tests for linking PDF page and video moment as evidence.
- [ ] Add evidence search from active claim.
- [ ] Add "Use as evidence" action from Command-K asset result.
- [ ] Add contradiction scan over retrieved evidence candidates.
- [ ] Add UI state that separates strongest evidence, weak evidence, and contradictions.

**Verification commands:**

```bash
swift test --filter EpistemicAssetTests
swift build
```

**Commit:**

```bash
git add Data/Models Data/Repositories UI/FocusMode/Inquiry/Evidence Services/Knowledge Tests/CosmoOSTests/EpistemicAssetTests.swift
git commit -m "feat: add asset-backed evidence layer"
```

---

## Acceptance Criteria

Program-level acceptance:

- User can import an image, video, PDF, audio note, text document, and web link.
- Original survives processing failure.
- Command-K can find assets by filename, title, OCR text, transcript, PDF page text, tag, and relation.
- Empty Command-K shows useful smart clusters before the user types.
- Recent uploads are auto-sorted into intuitive clusters using context, content, relations, processing state, and action usefulness.
- Swipe file, Readwise, ideas, sources, notes, and assets appear in one unified recall surface without duplicate silos.
- Video search can return a timestamped moment.
- PDF search can return a page result.
- Image search can return OCR and caption matches.
- Thinkspace Library shows only relevant scoped assets by default.
- Content Focus can attach a visual or evidence result to a draft.
- Canvas can contain asset appearances without duplicating the asset.
- Inquiry can use asset segments as sources and evidence.
- Agents can retrieve asset segments through the shared context substrate.
- Processing policy prevents expensive or cloud jobs when disabled.
- Sync planning can distinguish metadata, thumbnails, previews, and originals.

## Testing Matrix

Repository tests:

- Asset CRUD
- Segment CRUD
- Relation lookup
- Job claiming
- FTS indexing
- Deduplication

Processor tests:

- Image OCR
- Thumbnail generation
- PDF page extraction
- Text chunking
- Video scene merge
- Transcript segmentation
- Web extraction adapter

Search tests:

- Exact match
- FTS match
- Tag match
- Context chunk match
- Relation boost
- Empty-query cluster ranking
- Recent upload burst grouping
- Duplicate suppression across asset, swipe, Readwise, and idea results
- Processing Attention cluster
- Deterministic match-reason explanations
- Surface-aware actions
- Result grouping

UI tests or preview checks:

- Command-K asset cards
- Command-K smart clusters with empty search
- Command-K keyboard selection
- Thinkspace Library empty/loading/indexed states
- Asset picker in Writing Mode
- Asset inspector job status

Integration tests:

- Telegram media -> Asset -> Command-K result
- File import -> Thinkspace relation -> scoped Library
- Video segment -> Canvas block -> open timestamp
- PDF page -> Claim evidence -> citation
- Asset segment -> Context pack -> agent answer provenance

## Build and Verification Commands

Run after each subplan:

```bash
swift test --filter <RelevantTestSuite>
swift build
```

Run before merging the full program branch:

```bash
swift test
swift build
```

If Xcode project is the authoritative build path for this repo at execution time, use the macOS app build skill and run the configured scheme through Xcode instead of relying only on SwiftPM.

## Migration Strategy

Existing data should continue working.

Migration bridge:

- `MediaAttachment` rows with `localStoragePath` become assets through a one-time backfill.
- `Atom.type == .image` with `imageMetadata.imagePath` becomes an asset relation and optionally a linked image asset.
- Research atoms with `videoId`, `sourceURL`, or thumbnail metadata can be linked to web/youtube assets.
- Existing swipes stay research atoms but can gain related assets for media, screenshots, captions, and transcripts.

Backfill phases:

1. Create assets for media attachments only.
2. Link image atoms to assets.
3. Link research URL atoms to web/youtube assets.
4. Create context chunks for extracted asset segments.
5. Enable Command-K asset results after backfill has trace logging.

## Privacy and Safety

Local-first defaults:

- Originals local.
- OCR local.
- PDF text extraction local.
- Metadata local.
- Thumbnails local.
- Transcription local if existing daemon or WhisperKit path is available.

Cloud AI is opt-in by policy:

- image captions
- video frame captions
- long summaries
- contradiction scans
- source reliability analysis

Sensitive asset handling:

- user can mark an asset or Thinkspace sensitive.
- sensitive scope disables cloud processing.
- sensitive scope hides assets from global Command-K unless the active context is inside that scope.

## Cost Strategy

Cheap first:

- hash
- metadata
- thumbnail
- text extraction
- local OCR
- local embeddings

Medium:

- transcription
- image captioning
- video frame captions
- document summaries

Expensive:

- full video analysis
- all-frame captioning
- full-library AI reasoning
- top-model source synthesis

Cost rules:

- sample video frames every 2 to 5 seconds, not every frame.
- process once per asset hash and processor version.
- use stored segments for search.
- use AI only after retrieval unless enriching an asset at ingest time.
- batch low-priority AI jobs.
- surface estimated cost before bulk reprocess.

## Definition of Done

The feature is done when the user can perform this flow without touching folders:

```text
Import Walking Beam property videos, room photos, rent docs, screenshots, and voice notes.
Open Josh Thinkspace.
Open Command-K without typing and see recent imports, Josh / Walking Beam media, room visuals, deal documents, and processing status already clustered intelligibly.
Search Command-K for "bedroom bed".
See video moments, images, notes, and PDF evidence grouped visually.
Preview the video at the exact bedroom timestamp.
Attach that moment to a content draft.
Bring another result to canvas.
Use a PDF page as evidence for a claim.
Ask Cosmo to find the strongest proof for a slide and receive source-backed results.
```

## Execution Handoff

Recommended execution:

1. Create an isolated branch or worktree named `codex/universal-asset-os-core`.
2. Execute Subplans 1 through 3 first.
3. Stop and verify the raw asset substrate before adding AI processing.
4. Execute Subplans 4 through 7 to make keyword retrieval work across images, videos, text, and PDFs.
5. Execute Subplan 7.5 so zero-query Command-K becomes smart before expanding workflow surfaces.
6. Execute Subplan 8 to render the clustered, visual, action-rich Command-K experience.
7. Execute Subplans 9 through 11 to make assets usable in workflows.
8. Execute Subplans 12 through 14 after the local-first system is proven.

Use frequent commits exactly as listed in each subplan. Do not combine unrelated subplans into one large commit.
