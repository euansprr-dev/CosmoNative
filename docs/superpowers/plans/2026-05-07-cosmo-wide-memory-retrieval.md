# Cosmo-Wide Memory and Retrieval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shared Cosmo-wide memory and retrieval substrate that makes pinned docs, profiles, swipes, conversation memory, and source evidence durable and reusable across all AI surfaces.

**Architecture:** Add an `Agent/Context/` subsystem that models pinned sources, sessions, chunks, retrieval, memory tiers, and prompt-ready context packs. Reuse existing GRDB atoms, `atoms_fts`, `HybridSearchEngine`, `VectorDatabase`, `DaemonXPCClient`, and `ConversationMemoryService` rather than creating a parallel database. Integrate Option+A first, then Writing Mode, focus panels, CommandK, voice, and automations.

**Tech Stack:** Swift 5, SwiftUI, GRDB, SQLite FTS, local Nomic embeddings through `DaemonXPCClient`, existing `VectorDatabase`, OpenRouter/OpenAI/Anthropic LLM providers, XCTest once the test harness is restored.

---

## File Map

- Modify `CosmoOS.xcodeproj/project.pbxproj`
  - Add `CosmoOSTests` test target or otherwise wire the existing tests into an Xcode test action.
- Modify `CosmoOS.xcodeproj/xcshareddata/xcschemes/CosmoOS.xcscheme`
  - Add the test target to `TestAction`.
- Create `Agent/Context/ContextSource.swift`
  - Source, session, chunk, retrieval request, retrieval result, and context pack value types.
- Create `Agent/Context/ContextChunker.swift`
  - Deterministic chunking with overlap and exact phrase preservation.
- Create `Agent/Context/ContextIndexStore.swift`
  - GRDB persistence for context sources, sessions, chunks, and BM25 rows.
- Create `Agent/Context/ContextualChunkAnnotator.swift`
  - Lazy 50 to 100 token contextual headers for high-value chunks.
- Create `Agent/Context/CosmoRetrievalService.swift`
  - Pinned-source exact search, BM25, semantic merge, reciprocal rank fusion, and deterministic reranking.
- Create `Agent/Context/CosmoMemoryService.swift`
  - Core, working, recall, and archival memory API.
- Create `Agent/Context/ContextPackAssembler.swift`
  - Builds prompt-ready context packs with provenance and token budgets.
- Modify `Agent/Core/AgentContextAssembler.swift`
  - Consume `AgentContextPack` instead of directly truncating linked atoms.
- Modify `Agent/Core/AgentToolRegistry.swift`
  - Add shared retrieval and memory tools.
- Modify `Agent/Core/AgentToolExecutor.swift`
  - Execute shared retrieval and memory tools through the new services.
- Modify `UI/CosmoWindow/CosmoWindowViewModel.swift`
  - Pin `@` mentioned atoms to a `ContextSession` and request a context pack per turn.
- Modify `UI/CosmoWindow/CosmoWindowMessage.swift`
  - Keep mention metadata compatible with context sessions.
- Modify `Services/PromptTemplateStore.swift` and writing pipeline call sites as needed
  - Pass context source UUIDs and retrieved snippets to writing requests.
- Modify focus-panel view models under `UI/FocusMode/`
  - Use shared context sessions for active atoms.
- Modify `UI/CommandK/CommandKViewModel.swift`
  - Optionally surface chunk-level results and pin selected chunks/sources.
- Test files:
  - `Tests/CosmoOSTests/CosmoContextChunkerTests.swift`
  - `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`
  - `Tests/CosmoOSTests/CosmoContextPackAssemblerTests.swift`
  - `Tests/CosmoOSTests/CosmoMemoryServiceTests.swift`
  - `Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift`

## Phase 0: Restore a Runnable Test Harness

### Task 1: Wire Existing Tests Into Xcode

**Files:**
- Modify: `CosmoOS.xcodeproj/project.pbxproj`
- Modify: `CosmoOS.xcodeproj/xcshareddata/xcschemes/CosmoOS.xcscheme`

- [ ] **Step 1: Reproduce current blocker**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test
```

Expected: FAIL with:

```text
xcodebuild: error: Scheme CosmoOS is not currently configured for the test action.
```

- [ ] **Step 2: Inspect current project targets**

Run:

```bash
xcodebuild -list -project CosmoOS.xcodeproj
```

Expected: targets list does not include `CosmoOSTests`.

- [ ] **Step 3: Add a macOS XCTest target**

Add a `CosmoOSTests` native test target to `CosmoOS.xcodeproj` with:

```text
Product type: com.apple.product-type.bundle.unit-test
Product name: CosmoOSTests
Host application: CosmoOS.app
Bundle identifier: com.cosmo.CosmoOS.Tests
Sources: Tests/CosmoOSTests/*.swift
Dependency: CosmoOS
```

Set build settings:

```text
GENERATE_INFOPLIST_FILE = YES
PRODUCT_BUNDLE_IDENTIFIER = com.cosmo.CosmoOS.Tests
TEST_HOST = "$(BUILT_PRODUCTS_DIR)/CosmoOS.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CosmoOS"
BUNDLE_LOADER = "$(TEST_HOST)"
SWIFT_VERSION = 5.0
MACOSX_DEPLOYMENT_TARGET = 26.0
```

- [ ] **Step 4: Add target to scheme test action**

Update `CosmoOS.xcscheme` so `TestAction` contains a `TestableReference` for `CosmoOSTests.xctest` and keeps `CosmoOS.app` as the macro expansion target.

- [ ] **Step 5: Verify the test runner now starts**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowRoutingTests
```

Expected: test action starts. Individual tests may fail or compile errors may surface, but the scheme-level "not configured for the test action" error is gone.

- [ ] **Step 6: Commit test harness only**

```bash
git add CosmoOS.xcodeproj/project.pbxproj CosmoOS.xcodeproj/xcshareddata/xcschemes/CosmoOS.xcscheme
git commit -m "test: wire CosmoOS unit test target"
```

## Phase 1: Context Source and Session Foundation

### Task 2: Add Context Source Models

**Files:**
- Create: `Agent/Context/ContextSource.swift`
- Test: `Tests/CosmoOSTests/CosmoContextChunkerTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `Tests/CosmoOSTests/CosmoContextChunkerTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoContextChunkerTests: XCTestCase {
    func testContextSourceKeepsAtomIdentityAndHashes() {
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-123",
            bodyHash: "body-hash",
            metadataHash: "meta-hash",
            clientUUID: "client-1",
            pinState: .pinned
        )

        XCTAssertEqual(source.kind, .atom)
        XCTAssertEqual(source.atomUUID, "atom-123")
        XCTAssertEqual(source.pinState, .pinned)
        XCTAssertTrue(source.needsReindex(currentBodyHash: "new-hash", currentMetadataHash: "meta-hash"))
        XCTAssertFalse(source.needsReindex(currentBodyHash: "body-hash", currentMetadataHash: "meta-hash"))
    }

    func testContextSessionKeepsPinnedSourcesInOrderWithoutDuplicates() {
        var session = ContextSession(id: "conversation-1", surface: .cosmoWindow)
        session.pinSourceID("source-a")
        session.pinSourceID("source-b")
        session.pinSourceID("source-a")

        XCTAssertEqual(session.pinnedSourceIDs, ["source-a", "source-b"])
    }
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoContextChunkerTests
```

Expected: FAIL because `ContextSource`, `ContextSession`, and related enums do not exist.

- [ ] **Step 3: Implement minimal models**

Create `Agent/Context/ContextSource.swift`:

```swift
import Foundation

enum ContextSourceKind: String, Codable, Sendable, Equatable {
    case atom
    case clientProfile
    case swipe
    case content
    case conversation
    case webCapture
    case externalFile
}

enum ContextPinState: String, Codable, Sendable, Equatable {
    case unpinned
    case pinned
    case active
}

enum ContextSurface: String, Codable, Sendable, Equatable {
    case cosmoWindow
    case writingMode
    case focusPanel
    case commandK
    case voice
    case automation
}

enum RetrievalPurpose: String, Codable, Sendable, Equatable {
    case factLookup
    case brainstorm
    case writing
    case memory
    case globalSynthesis
    case general
}

struct ContextSource: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var kind: ContextSourceKind
    var title: String
    var atomUUID: String?
    var externalID: String?
    var bodyHash: String
    var metadataHash: String
    var clientUUID: String?
    var pinState: ContextPinState
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        kind: ContextSourceKind,
        title: String,
        atomUUID: String? = nil,
        externalID: String? = nil,
        bodyHash: String,
        metadataHash: String,
        clientUUID: String? = nil,
        pinState: ContextPinState = .unpinned,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.atomUUID = atomUUID
        self.externalID = externalID
        self.bodyHash = bodyHash
        self.metadataHash = metadataHash
        self.clientUUID = clientUUID
        self.pinState = pinState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func needsReindex(currentBodyHash: String, currentMetadataHash: String) -> Bool {
        bodyHash != currentBodyHash || metadataHash != currentMetadataHash
    }
}

struct ContextSession: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var surface: ContextSurface
    var activeAtomUUID: String?
    var activeClientUUID: String?
    var pinnedSourceIDs: [String]
    var recentDecisionSummaries: [String]
    var updatedAt: Date

    init(
        id: String,
        surface: ContextSurface,
        activeAtomUUID: String? = nil,
        activeClientUUID: String? = nil,
        pinnedSourceIDs: [String] = [],
        recentDecisionSummaries: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.surface = surface
        self.activeAtomUUID = activeAtomUUID
        self.activeClientUUID = activeClientUUID
        self.pinnedSourceIDs = pinnedSourceIDs
        self.recentDecisionSummaries = recentDecisionSummaries
        self.updatedAt = updatedAt
    }

    mutating func pinSourceID(_ sourceID: String) {
        guard !pinnedSourceIDs.contains(sourceID) else { return }
        pinnedSourceIDs.append(sourceID)
        updatedAt = Date()
    }
}

struct ContextChunk: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let sourceID: String
    let ordinal: Int
    let rawText: String
    var contextualHeader: String
    var anchor: String?
    var tokenCount: Int
    var bodyHash: String

    var searchableText: String {
        [contextualHeader, rawText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

struct ContextRetrievalRequest: Sendable, Equatable {
    let query: String
    let conversationID: String
    let surface: ContextSurface
    let purpose: RetrievalPurpose
    let pinnedSourceIDs: [String]
    let activeAtomUUID: String?
    let activeClientUUID: String?
    let maxChunks: Int
    let tokenBudget: Int
}

struct ContextRetrievalResult: Sendable, Equatable {
    let chunk: ContextChunk
    let source: ContextSource
    let score: Double
    let matchType: String
}

struct AgentContextPack: Sendable, Equatable {
    let request: ContextRetrievalRequest
    let retrievedResults: [ContextRetrievalResult]
    let coreMemory: [String]
    let workingMemory: [String]
    let recallMemory: [String]
    let provenanceLines: [String]
    let estimatedTokens: Int
}
```

- [ ] **Step 4: Add file to Xcode sources**

Add `Agent/Context/ContextSource.swift` to the `CosmoOS` target sources in `project.pbxproj`.

- [ ] **Step 5: Verify tests pass**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoContextChunkerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Agent/Context/ContextSource.swift Tests/CosmoOSTests/CosmoContextChunkerTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: add shared context source models"
```

### Task 3: Add Deterministic Chunking

**Files:**
- Create: `Agent/Context/ContextChunker.swift`
- Test: `Tests/CosmoOSTests/CosmoContextChunkerTests.swift`

- [ ] **Step 1: Add failing chunker tests**

Append:

```swift
func testChunkerPreservesExactPhraseInLaterChunk() {
    let intro = String(repeating: "Intro setup sentence. ", count: 160)
    let phrase = "All bedroom doors need working locks on doors before tenant intake."
    let body = intro + phrase + String(repeating: " Closing details.", count: 120)

    let chunks = ContextChunker.chunk(
        sourceID: "source-1",
        title: "Walking Beam brief",
        body: body,
        bodyHash: "hash",
        maxCharacters: 900,
        overlapCharacters: 180
    )

    XCTAssertGreaterThan(chunks.count, 1)
    XCTAssertTrue(chunks.contains { $0.rawText.contains(phrase) })
}

func testChunkerAddsUsefulAnchors() {
    let body = "First paragraph.\n\nSecond paragraph about locks on doors.\n\nThird paragraph."
    let chunks = ContextChunker.chunk(
        sourceID: "source-1",
        title: "Brief",
        body: body,
        bodyHash: "hash",
        maxCharacters: 80,
        overlapCharacters: 10
    )

    XCTAssertTrue(chunks.allSatisfy { $0.anchor?.hasPrefix("chunk-") == true })
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoContextChunkerTests/testChunkerPreservesExactPhraseInLaterChunk
```

Expected: FAIL because `ContextChunker` does not exist.

- [ ] **Step 3: Implement chunker**

Create `Agent/Context/ContextChunker.swift`:

```swift
import Foundation

enum ContextChunker {
    static func chunk(
        sourceID: String,
        title: String,
        body: String,
        bodyHash: String,
        maxCharacters: Int = 2_800,
        overlapCharacters: Int = 500
    ) -> [ContextChunk] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let safeMax = max(300, maxCharacters)
        let safeOverlap = min(max(0, overlapCharacters), safeMax / 2)
        var chunks: [ContextChunk] = []
        var start = trimmed.startIndex
        var ordinal = 0

        while start < trimmed.endIndex {
            let roughEnd = trimmed.index(start, offsetBy: safeMax, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let end = adjustedEnd(in: trimmed, start: start, roughEnd: roughEnd)
            let raw = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !raw.isEmpty {
                chunks.append(
                    ContextChunk(
                        id: "\(sourceID)-chunk-\(ordinal)",
                        sourceID: sourceID,
                        ordinal: ordinal,
                        rawText: raw,
                        contextualHeader: "Source: \(title). Chunk \(ordinal + 1).",
                        anchor: "chunk-\(ordinal + 1)",
                        tokenCount: max(1, raw.count / 4),
                        bodyHash: bodyHash
                    )
                )
                ordinal += 1
            }

            guard end < trimmed.endIndex else { break }
            let overlapStart = trimmed.index(end, offsetBy: -safeOverlap, limitedBy: trimmed.startIndex) ?? start
            start = overlapStart > start ? overlapStart : end
        }

        return chunks
    }

    private static func adjustedEnd(in text: String, start: String.Index, roughEnd: String.Index) -> String.Index {
        guard roughEnd < text.endIndex else { return text.endIndex }
        let searchRange = start..<roughEnd
        let punctuation = [". ", "\n\n", "\n", " "]

        for marker in punctuation {
            if let range = text.range(of: marker, options: .backwards, range: searchRange),
               text.distance(from: start, to: range.upperBound) > 200 {
                return range.upperBound
            }
        }

        return roughEnd
    }
}
```

- [ ] **Step 4: Add file to Xcode sources**

Add `Agent/Context/ContextChunker.swift` to the `CosmoOS` target sources.

- [ ] **Step 5: Verify chunker tests pass**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoContextChunkerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Agent/Context/ContextChunker.swift Tests/CosmoOSTests/CosmoContextChunkerTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: add context chunking"
```

## Phase 2: Chunk Indexing and Retrieval

### Task 4: Add Context Index Store

**Files:**
- Create: `Agent/Context/ContextIndexStore.swift`
- Test: `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`

- [ ] **Step 1: Write failing index tests**

Create `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoRetrievalServiceTests: XCTestCase {
    func testIndexStoreCanRoundTripSourceAndChunksInMemory() async throws {
        let store = ContextIndexStore.inMemoryForTests()
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-1",
            bodyHash: "body-hash",
            metadataHash: "meta-hash",
            pinState: .pinned
        )
        let chunks = ContextChunker.chunk(
            sourceID: source.id,
            title: source.title,
            body: "This brief mentions locks on doors and intake sequencing.",
            bodyHash: source.bodyHash,
            maxCharacters: 200,
            overlapCharacters: 20
        )

        try await store.upsert(source: source, chunks: chunks)
        let loaded = try await store.source(id: "source-1")
        let loadedChunks = try await store.chunks(sourceIDs: ["source-1"])

        XCTAssertEqual(loaded?.title, "Walking Beam brief")
        XCTAssertEqual(loadedChunks.count, 1)
        XCTAssertTrue(loadedChunks[0].rawText.contains("locks on doors"))
    }
}
```

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testIndexStoreCanRoundTripSourceAndChunksInMemory
```

Expected: FAIL because `ContextIndexStore` does not exist.

- [ ] **Step 3: Implement first in-memory store**

Create `Agent/Context/ContextIndexStore.swift`:

```swift
import Foundation

actor ContextIndexStore {
    static let shared = ContextIndexStore()

    private var sourcesByID: [String: ContextSource] = [:]
    private var chunksBySourceID: [String: [ContextChunk]] = [:]

    static func inMemoryForTests() -> ContextIndexStore {
        ContextIndexStore()
    }

    func upsert(source: ContextSource, chunks: [ContextChunk]) async throws {
        sourcesByID[source.id] = source
        chunksBySourceID[source.id] = chunks
    }

    func source(id: String) async throws -> ContextSource? {
        sourcesByID[id]
    }

    func sources(ids: [String]) async throws -> [ContextSource] {
        ids.compactMap { sourcesByID[$0] }
    }

    func chunks(sourceIDs: [String]) async throws -> [ContextChunk] {
        sourceIDs.flatMap { chunksBySourceID[$0] ?? [] }
    }
}
```

- [ ] **Step 4: Add file to Xcode sources**

Add `Agent/Context/ContextIndexStore.swift` to the `CosmoOS` target sources.

- [ ] **Step 5: Verify tests pass**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testIndexStoreCanRoundTripSourceAndChunksInMemory
```

Expected: PASS.

- [ ] **Step 6: Replace in-memory implementation with GRDB-backed persistence**

Keep the actor API unchanged and add durable tables:

```sql
CREATE TABLE IF NOT EXISTS context_sources (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    atom_uuid TEXT,
    external_id TEXT,
    body_hash TEXT NOT NULL,
    metadata_hash TEXT NOT NULL,
    client_uuid TEXT,
    pin_state TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS context_chunks (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    raw_text TEXT NOT NULL,
    contextual_header TEXT NOT NULL,
    anchor TEXT,
    token_count INTEGER NOT NULL,
    body_hash TEXT NOT NULL,
    FOREIGN KEY(source_id) REFERENCES context_sources(id) ON DELETE CASCADE
);

CREATE VIRTUAL TABLE IF NOT EXISTS context_chunks_fts USING fts5(
    id UNINDEXED,
    source_id UNINDEXED,
    title,
    searchable_text,
    tokenize='porter unicode61'
);
```

The public methods remain:

```swift
func upsert(source: ContextSource, chunks: [ContextChunk]) async throws
func source(id: String) async throws -> ContextSource?
func sources(ids: [String]) async throws -> [ContextSource]
func chunks(sourceIDs: [String]) async throws -> [ContextChunk]
func keywordSearch(query: String, sourceIDs: [String], limit: Int) async throws -> [(ContextSource, ContextChunk, Double)]
```

- [ ] **Step 7: Add BM25 exact phrase test**

Append:

```swift
func testKeywordSearchFindsExactPhraseInsidePinnedChunk() async throws {
    let store = ContextIndexStore.inMemoryForTests()
    let source = ContextSource(
        id: "source-1",
        kind: .atom,
        title: "Walking Beam brief",
        atomUUID: "atom-1",
        bodyHash: "hash",
        metadataHash: "meta",
        pinState: .pinned
    )
    let chunks = ContextChunker.chunk(
        sourceID: source.id,
        title: source.title,
        body: "Kitchen checklist.\n\nBedroom setup requires locks on doors before move-in.",
        bodyHash: "hash",
        maxCharacters: 120,
        overlapCharacters: 20
    )
    try await store.upsert(source: source, chunks: chunks)

    let results = try await store.keywordSearch(query: "\"locks on doors\"", sourceIDs: ["source-1"], limit: 5)

    XCTAssertEqual(results.first?.0.title, "Walking Beam brief")
    XCTAssertTrue(results.first?.1.rawText.contains("locks on doors") == true)
}
```

- [ ] **Step 8: Verify BM25 test passes**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testKeywordSearchFindsExactPhraseInsidePinnedChunk
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Agent/Context/ContextIndexStore.swift Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: index context chunks for retrieval"
```

### Task 5: Add Pinned-Source Retrieval Service

**Files:**
- Create: `Agent/Context/CosmoRetrievalService.swift`
- Test: `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`

- [ ] **Step 1: Add failing retrieval behavior test**

Append:

```swift
func testRetrievalSearchesPinnedSourcesBeforeAnsweringFactLookup() async throws {
    let store = ContextIndexStore.inMemoryForTests()
    let source = ContextSource(
        id: "source-1",
        kind: .atom,
        title: "Walking Beam brief",
        atomUUID: "atom-1",
        bodyHash: "hash",
        metadataHash: "meta",
        pinState: .pinned
    )
    let chunks = ContextChunker.chunk(
        sourceID: source.id,
        title: source.title,
        body: "The setup checklist says locks on doors are required before residents arrive.",
        bodyHash: "hash"
    )
    try await store.upsert(source: source, chunks: chunks)

    let service = CosmoRetrievalService(indexStore: store)
    let request = ContextRetrievalRequest(
        query: "does the brief mention locks on doors?",
        conversationID: "conversation-1",
        surface: .cosmoWindow,
        purpose: .factLookup,
        pinnedSourceIDs: ["source-1"],
        activeAtomUUID: nil,
        activeClientUUID: nil,
        maxChunks: 4,
        tokenBudget: 1_200
    )

    let results = try await service.retrieve(request)

    XCTAssertEqual(results.first?.source.title, "Walking Beam brief")
    XCTAssertTrue(results.first?.chunk.rawText.localizedCaseInsensitiveContains("locks on doors") == true)
    XCTAssertEqual(results.first?.matchType, "keyword")
}
```

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testRetrievalSearchesPinnedSourcesBeforeAnsweringFactLookup
```

Expected: FAIL because `CosmoRetrievalService` does not exist.

- [ ] **Step 3: Implement keyword-first retrieval**

Create `Agent/Context/CosmoRetrievalService.swift`:

```swift
import Foundation

actor CosmoRetrievalService {
    static let shared = CosmoRetrievalService()

    private let indexStore: ContextIndexStore
    private var chunkEmbeddingCache: [String: [Float]] = [:]

    init(indexStore: ContextIndexStore = .shared) {
        self.indexStore = indexStore
    }

    func retrieve(_ request: ContextRetrievalRequest) async throws -> [ContextRetrievalResult] {
        guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let keywordResults = try await indexStore.keywordSearch(
            query: keywordQuery(for: request.query, purpose: request.purpose),
            sourceIDs: request.pinnedSourceIDs,
            limit: max(request.maxChunks * 2, request.maxChunks)
        )

        var merged: [ContextRetrievalResult] = keywordResults.map { source, chunk, score in
            ContextRetrievalResult(
                chunk: chunk,
                source: source,
                score: score,
                matchType: "keyword"
            )
        }

        merged = dedupe(merged)
        return Array(merged.prefix(request.maxChunks))
    }

    private func keywordQuery(for query: String, purpose: RetrievalPurpose) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard purpose == .factLookup else { return trimmed }

        if trimmed.contains("\"") { return trimmed }
        let importantWords = trimmed
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .filter { !Self.stopWords.contains($0) }
        return importantWords.isEmpty ? trimmed : importantWords.joined(separator: " ")
    }

    private func dedupe(_ results: [ContextRetrievalResult]) -> [ContextRetrievalResult] {
        var seen = Set<String>()
        var output: [ContextRetrievalResult] = []
        for result in results where seen.insert(result.chunk.id).inserted {
            output.append(result)
        }
        return output
    }

    private static let stopWords: Set<String> = [
        "does", "the", "brief", "mention", "what", "where", "when", "how",
        "this", "that", "there", "with", "about", "from"
    ]
}
```

- [ ] **Step 4: Add file to Xcode sources**

Add `Agent/Context/CosmoRetrievalService.swift` to the `CosmoOS` target sources.

- [ ] **Step 5: Add semantic fallback**

Extend `retrieve(_:)` after keyword results:

```swift
if merged.count < request.maxChunks {
    let semanticResults = try await semanticSearch(request)
    merged.append(contentsOf: semanticResults)
}
```

Add:

```swift
private func semanticSearch(_ request: ContextRetrievalRequest) async throws -> [ContextRetrievalResult] {
    let chunks = try await indexStore.chunks(sourceIDs: request.pinnedSourceIDs)
    let sources = try await indexStore.sources(ids: request.pinnedSourceIDs)
    let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

    let queryVector = try? await DaemonXPCClient.shared.embed(text: request.query)
    guard let queryVector else { return [] }

    var scored: [ContextRetrievalResult] = []
    for chunk in chunks {
        guard let source = sourceByID[chunk.sourceID] else { continue }
        let cacheKey = "\(chunk.id):\(chunk.bodyHash)"
        let chunkVector: [Float]
        if let cached = chunkEmbeddingCache[cacheKey] {
            chunkVector = cached
        } else {
            let embedded = try await DaemonXPCClient.shared.embed(text: chunk.searchableText)
            chunkEmbeddingCache[cacheKey] = embedded
            chunkVector = embedded
        }

        let semanticScore = cosineSimilarity(queryVector, chunkVector)
        let lexicalBoost = chunk.searchableText.localizedCaseInsensitiveContains(request.query) ? 0.2 : 0
        let score = Double(semanticScore) + lexicalBoost
        guard score > 0.35 else { continue }
        scored.append(ContextRetrievalResult(
            chunk: chunk,
            source: source,
            score: score,
            matchType: "semantic"
        ))
    }
    return scored.sorted { $0.score > $1.score }
}

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for idx in a.indices {
        dot += a[idx] * b[idx]
        normA += a[idx] * a[idx]
        normB += b[idx] * b[idx]
    }
    let denominator = sqrt(normA) * sqrt(normB)
    return denominator > 0 ? dot / denominator : 0
}
```

Keep keyword retrieval working if embedding generation fails. The first implementation can use the actor cache above; later production hardening may move `chunkEmbeddingCache` into the durable `context_chunks` table without changing the public retrieval API.

- [ ] **Step 6: Verify focused tests pass**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Agent/Context/CosmoRetrievalService.swift Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: retrieve pinned context chunks"
```

## Phase 3: Context Pack Assembly

### Task 6: Assemble Prompt-Ready Context Packs

**Files:**
- Create: `Agent/Context/ContextPackAssembler.swift`
- Test: `Tests/CosmoOSTests/CosmoContextPackAssemblerTests.swift`

- [ ] **Step 1: Write failing context-pack tests**

Create `Tests/CosmoOSTests/CosmoContextPackAssemblerTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoContextPackAssemblerTests: XCTestCase {
    func testContextPackIncludesEvidenceBeforeMemoryForFactLookup() {
        let request = ContextRetrievalRequest(
            query: "does it mention locks?",
            conversationID: "conversation-1",
            surface: .cosmoWindow,
            purpose: .factLookup,
            pinnedSourceIDs: ["source-1"],
            activeAtomUUID: nil,
            activeClientUUID: nil,
            maxChunks: 3,
            tokenBudget: 1_000
        )
        let source = ContextSource(
            id: "source-1",
            kind: .atom,
            title: "Walking Beam brief",
            atomUUID: "atom-1",
            bodyHash: "hash",
            metadataHash: "meta",
            pinState: .pinned
        )
        let chunk = ContextChunk(
            id: "chunk-1",
            sourceID: "source-1",
            ordinal: 0,
            rawText: "Locks on doors are required.",
            contextualHeader: "Source: Walking Beam brief.",
            anchor: "chunk-1",
            tokenCount: 8,
            bodyHash: "hash"
        )
        let result = ContextRetrievalResult(chunk: chunk, source: source, score: 1.0, matchType: "keyword")

        let pack = ContextPackAssembler.assemble(
            request: request,
            retrievalResults: [result],
            coreMemory: ["User likes direct answers."],
            workingMemory: ["Current task: review brief."],
            recallMemory: []
        )

        let prompt = pack.promptBlock
        XCTAssertLessThan(
            prompt.range(of: "Locks on doors are required.")!.lowerBound,
            prompt.range(of: "User likes direct answers.")!.lowerBound
        )
        XCTAssertTrue(prompt.contains("Walking Beam brief"))
    }
}
```

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoContextPackAssemblerTests
```

Expected: FAIL because `ContextPackAssembler` and `AgentContextPack.promptBlock` do not exist.

- [ ] **Step 3: Add prompt block helper**

In `Agent/Context/ContextSource.swift`, add:

```swift
extension AgentContextPack {
    var promptBlock: String {
        var lines: [String] = ["[COSMO CONTEXT PACK]"]

        if !retrievedResults.isEmpty {
            lines.append("Retrieved source evidence:")
            for result in retrievedResults {
                let anchor = result.chunk.anchor.map { " @ \($0)" } ?? ""
                lines.append("- \(result.source.title)\(anchor) [\(result.matchType), score \(String(format: "%.3f", result.score))]")
                lines.append(result.chunk.searchableText)
            }
        }

        if !coreMemory.isEmpty {
            lines.append("Core memory:")
            lines.append(contentsOf: coreMemory.map { "- \($0)" })
        }

        if !workingMemory.isEmpty {
            lines.append("Working memory:")
            lines.append(contentsOf: workingMemory.map { "- \($0)" })
        }

        if !recallMemory.isEmpty {
            lines.append("Recall memory:")
            lines.append(contentsOf: recallMemory.map { "- \($0)" })
        }

        if !provenanceLines.isEmpty {
            lines.append("Provenance:")
            lines.append(contentsOf: provenanceLines.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Implement assembler**

Create `Agent/Context/ContextPackAssembler.swift`:

```swift
import Foundation

enum ContextPackAssembler {
    static func assemble(
        request: ContextRetrievalRequest,
        retrievalResults: [ContextRetrievalResult],
        coreMemory: [String],
        workingMemory: [String],
        recallMemory: [String]
    ) -> AgentContextPack {
        let cappedResults = capResults(retrievalResults, tokenBudget: request.tokenBudget)
        let provenance = cappedResults.map { result in
            let anchor = result.chunk.anchor.map { ":\($0)" } ?? ""
            return "\(result.source.title)\(anchor)"
        }

        let estimatedTokens =
            cappedResults.reduce(0) { $0 + $1.chunk.tokenCount } +
            coreMemory.joined(separator: "\n").count / 4 +
            workingMemory.joined(separator: "\n").count / 4 +
            recallMemory.joined(separator: "\n").count / 4

        return AgentContextPack(
            request: request,
            retrievedResults: cappedResults,
            coreMemory: coreMemory,
            workingMemory: workingMemory,
            recallMemory: recallMemory,
            provenanceLines: provenance,
            estimatedTokens: estimatedTokens
        )
    }

    private static func capResults(_ results: [ContextRetrievalResult], tokenBudget: Int) -> [ContextRetrievalResult] {
        var output: [ContextRetrievalResult] = []
        var remaining = max(0, tokenBudget)

        for result in results.sorted(by: { $0.score > $1.score }) {
            guard result.chunk.tokenCount <= remaining || output.isEmpty else { continue }
            output.append(result)
            remaining -= result.chunk.tokenCount
            if remaining <= 0 { break }
        }

        return output
    }
}
```

- [ ] **Step 5: Add file to Xcode sources and verify**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoContextPackAssemblerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Agent/Context/ContextPackAssembler.swift Agent/Context/ContextSource.swift Tests/CosmoOSTests/CosmoContextPackAssemblerTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: assemble context packs"
```

## Phase 4: Option+A Integration

### Task 7: Pin Mentions Into Context Sessions

**Files:**
- Modify: `UI/CosmoWindow/CosmoWindowViewModel.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift`

- [ ] **Step 1: Write failing session pinning test**

Create `Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoWindowContextSessionTests: XCTestCase {
    func testMentionedAtomBecomesPinnedContextSource() async throws {
        let atom = Atom.new(type: .content, title: "Walking Beam brief", body: "Locks on doors are required.")
        let source = CosmoWindowViewModel.contextSource(for: atom)

        XCTAssertEqual(source.kind, .content)
        XCTAssertEqual(source.title, "Walking Beam brief")
        XCTAssertEqual(source.atomUUID, atom.uuid)
        XCTAssertEqual(source.pinState, .pinned)
    }
}
```

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowContextSessionTests
```

Expected: FAIL because `contextSource(for:)` does not exist.

- [ ] **Step 3: Add conversion helper**

In `CosmoWindowViewModel.swift`, add:

```swift
nonisolated static func contextSource(for atom: Atom) -> ContextSource {
    let body = atom.body ?? ""
    let metadata = atom.metadata ?? ""
    return ContextSource(
        kind: contextSourceKind(for: atom),
        title: atom.title ?? "Untitled",
        atomUUID: atom.uuid,
        bodyHash: stableHash(body),
        metadataHash: stableHash(metadata),
        clientUUID: atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID,
        pinState: .pinned
    )
}

nonisolated private static func contextSourceKind(for atom: Atom) -> ContextSourceKind {
    if atom.type == .clientProfile { return .clientProfile }
    if atom.isSwipeFileAtom { return .swipe }
    if atom.type == .content { return .content }
    return .atom
}

nonisolated private static func stableHash(_ text: String) -> String {
    String(text.hashValue)
}
```

Replace `stableHash` with SHA256 in the implementation pass if a crypto helper already exists locally.

- [ ] **Step 4: Index pinned mentions when added**

In `addMention(_:)`, after `linkedAtomUUIDs.insert(atom.uuid)`, add:

```swift
Task {
    let source = Self.contextSource(for: atom)
    let chunks = ContextChunker.chunk(
        sourceID: source.id,
        title: source.title,
        body: atom.body ?? "",
        bodyHash: source.bodyHash
    )
    try? await ContextIndexStore.shared.upsert(source: source, chunks: chunks)
}
```

- [ ] **Step 5: Preserve source IDs in session**

Add a property:

```swift
private var pinnedContextSourceIDs: [String] = []
```

When a source is created for a mention:

```swift
if !pinnedContextSourceIDs.contains(source.id) {
    pinnedContextSourceIDs.append(source.id)
}
```

- [ ] **Step 6: Verify tests pass**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowContextSessionTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CosmoWindow/CosmoWindowViewModel.swift Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift
git commit -m "feat: pin cosmo window mentions as context sources"
```

### Task 8: Use Context Packs In Option+A Agent Calls

**Files:**
- Modify: `UI/CosmoWindow/CosmoWindowViewModel.swift`
- Modify: `Agent/Core/AgentContextAssembler.swift`
- Test: `Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift`

- [ ] **Step 1: Add failing context pack request test**

Append:

```swift
func testContextPackRequestUsesCurrentQuestionAndPinnedSources() {
    let request = CosmoWindowViewModel.contextRetrievalRequest(
        text: "does it mention locks on doors?",
        conversationId: "conversation-1",
        pinnedSourceIDs: ["source-1"],
        activeAtomUUID: "atom-1",
        activeClientUUID: nil
    )

    XCTAssertEqual(request.purpose, .factLookup)
    XCTAssertEqual(request.pinnedSourceIDs, ["source-1"])
    XCTAssertEqual(request.surface, .cosmoWindow)
}
```

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowContextSessionTests/testContextPackRequestUsesCurrentQuestionAndPinnedSources
```

Expected: FAIL because `contextRetrievalRequest` does not exist.

- [ ] **Step 3: Add request classifier helper**

In `CosmoWindowViewModel.swift`, add:

```swift
nonisolated static func contextRetrievalRequest(
    text: String,
    conversationId: String,
    pinnedSourceIDs: [String],
    activeAtomUUID: String?,
    activeClientUUID: String?
) -> ContextRetrievalRequest {
    ContextRetrievalRequest(
        query: text,
        conversationID: conversationId,
        surface: .cosmoWindow,
        purpose: retrievalPurpose(for: text),
        pinnedSourceIDs: pinnedSourceIDs,
        activeAtomUUID: activeAtomUUID,
        activeClientUUID: activeClientUUID,
        maxChunks: 8,
        tokenBudget: 3_500
    )
}

nonisolated private static func retrievalPurpose(for text: String) -> RetrievalPurpose {
    let lower = text.lowercased()
    if containsAny(lower, ["mention", "does it say", "does the doc", "where does", "find", "quote", "locks on doors"]) {
        return .factLookup
    }
    if containsAny(lower, ["draft", "write", "revise", "slide", "script", "post", "carousel"]) {
        return .writing
    }
    if containsAny(lower, ["remember", "what did we decide", "last time", "previously"]) {
        return .memory
    }
    if containsAny(lower, ["themes", "across", "summarize all", "patterns"]) {
        return .globalSynthesis
    }
    if containsAny(lower, ["brainstorm", "ideas", "think through", "angles"]) {
        return .brainstorm
    }
    return .general
}
```

- [ ] **Step 4: Request and inject a context pack before agent call**

In `routeToAgentService(text:)`, before building `systemPromptOverride`, add:

```swift
let retrievalRequest = Self.contextRetrievalRequest(
    text: text,
    conversationId: conversationId,
    pinnedSourceIDs: pinnedContextSourceIDs,
    activeAtomUUID: activeContext.data.currentAtomUUID,
    activeClientUUID: nil
)
let retrievalResults = (try? await CosmoRetrievalService.shared.retrieve(retrievalRequest)) ?? []
let contextPack = ContextPackAssembler.assemble(
    request: retrievalRequest,
    retrievalResults: retrievalResults,
    coreMemory: [],
    workingMemory: [],
    recallMemory: []
)
```

Add the context pack to the runtime prompt layer:

```swift
let systemPromptOverride = [
    contextPack.promptBlock,
    runtimePromptLayer(
        collaboratorPrompt: collaboratorPreset?.runtimePrompt,
        agentProfile: activeProfile,
        forcedBundles: forcedBundles
    )
]
.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
.joined(separator: "\n\n")
```

Before invoking `CosmoAgentService`, pass both existing atom UUID context and new context-source IDs into the shared tool executor:

```swift
let toolExecutor = AgentToolExecutor.shared
toolExecutor.contextAtomUUIDs = Array(linkedAtomUUIDs)
toolExecutor.contextSourceIDs = pinnedContextSourceIDs
defer {
    toolExecutor.contextSourceIDs = []
}
```

- [ ] **Step 5: Remove redundant linked-atom truncation for pinned sources**

In `AgentContextAssembler.injectLinkedContext`, keep linked atom summaries for compatibility, but do not rely on `prefix(1500)` for the active pinned source path. Add a note:

```swift
parts.append("  NOTE: Full pinned-source retrieval is provided in [COSMO CONTEXT PACK]. This linked summary is compatibility context only.")
```

- [ ] **Step 6: Verify Option+A tests and build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowContextSessionTests
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: tests PASS and build succeeds.

- [ ] **Step 7: Commit**

```bash
git add UI/CosmoWindow/CosmoWindowViewModel.swift Agent/Core/AgentContextAssembler.swift Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift
git commit -m "feat: use context packs in cosmo window"
```

## Phase 5: Shared Retrieval Tools

### Task 9: Add Agent Retrieval Tools

**Files:**
- Modify: `Agent/Core/AgentToolRegistry.swift`
- Modify: `Agent/Core/AgentToolExecutor.swift`
- Test: `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`

- [ ] **Step 1: Add failing tool registry test**

Append:

```swift
func testAgentRegistryIncludesSharedRetrievalTool() {
    let names = AgentToolRegistry.shared.allTools.map(\.name)
    XCTAssertTrue(names.contains("retrieve_context"))
    XCTAssertTrue(names.contains("inspect_pinned_sources"))
}
```

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testAgentRegistryIncludesSharedRetrievalTool
```

Expected: FAIL because tools are missing.

- [ ] **Step 3: Register tools**

In `AgentToolRegistry`, add:

```swift
private var contextTools: [LLMToolDefinition] {
    [
        LLMToolDefinition(
            name: "retrieve_context",
            description: "Search active pinned documents, profiles, swipes, content, and memory before answering. Use this for source-grounded questions, exact fact lookup, and references to attached @ context.",
            parametersSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Natural language or exact phrase query"] as [String: Any],
                    "purpose": ["type": "string", "description": "factLookup, brainstorm, writing, memory, globalSynthesis, or general"] as [String: Any],
                    "limit": ["type": "integer", "description": "Maximum chunks to return"] as [String: Any]
                ] as [String: Any],
                "required": ["query"]
            ]
        ),
        LLMToolDefinition(
            name: "inspect_pinned_sources",
            description: "List active pinned context sources for the current conversation, including titles, types, and UUIDs.",
            parametersSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        )
    ]
}
```

Add `contextTools` to `registerAllTools()`.

- [ ] **Step 4: Execute tools**

Add session source IDs beside the existing atom UUID context:

```swift
var contextSourceIDs: [String] = []
```

In `AgentToolExecutor.execute`, add:

```swift
case "retrieve_context": return try await retrieveContext(arguments)
case "inspect_pinned_sources": return try await inspectPinnedSources(arguments)
```

Add methods:

```swift
private func retrieveContext(_ args: [String: Any]) async throws -> String {
    guard let query = args["query"] as? String else {
        return jsonError("Missing required parameter: query")
    }
    let purpose = (args["purpose"] as? String).flatMap(RetrievalPurpose.init(rawValue:)) ?? .general
    let limit = args["limit"] as? Int ?? 8
    let sourceIDs = contextSourceIDs

    let request = ContextRetrievalRequest(
        query: query,
        conversationID: "tool-context",
        surface: .cosmoWindow,
        purpose: purpose,
        pinnedSourceIDs: sourceIDs,
        activeAtomUUID: nil,
        activeClientUUID: nil,
        maxChunks: limit,
        tokenBudget: 3_500
    )
    let results = try await CosmoRetrievalService.shared.retrieve(request)
    let payload = results.map { result in
        [
            "sourceTitle": result.source.title,
            "sourceId": result.source.id,
            "atomUUID": result.source.atomUUID ?? "",
            "anchor": result.chunk.anchor ?? "",
            "matchType": result.matchType,
            "score": result.score,
            "text": result.chunk.rawText
        ] as [String: Any]
    }
    return jsonEncode(["results": payload, "count": payload.count])
}

private func inspectPinnedSources(_ args: [String: Any]) async throws -> String {
    let sources = try await ContextIndexStore.shared.sources(ids: contextSourceIDs)
    let payload = sources.map { source in
        [
            "id": source.id,
            "title": source.title,
            "kind": source.kind.rawValue,
            "atomUUID": source.atomUUID ?? ""
        ]
    }
    return jsonEncode(["sources": payload, "count": payload.count])
}
```

- [ ] **Step 5: Verify registry test and build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testAgentRegistryIncludesSharedRetrievalTool
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: PASS and build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Agent/Core/AgentToolRegistry.swift Agent/Core/AgentToolExecutor.swift Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift
git commit -m "feat: expose shared context retrieval tools"
```

## Phase 6: Memory Hierarchy

### Task 10: Add Core and Working Memory API

**Files:**
- Create: `Agent/Context/CosmoMemoryService.swift`
- Test: `Tests/CosmoOSTests/CosmoMemoryServiceTests.swift`

- [ ] **Step 1: Write failing memory tests**

Create `Tests/CosmoOSTests/CosmoMemoryServiceTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoMemoryServiceTests: XCTestCase {
    func testMemoryServiceSeparatesCoreAndWorkingMemory() async throws {
        let service = CosmoMemoryService.inMemoryForTests()
        try await service.upsertCoreMemory("prefers concise direct answers", key: "style.directness")
        try await service.upsertWorkingMemory("conversation-1", value: "Current task: Walking Beam brief review")

        let core = try await service.coreMemory()
        let working = try await service.workingMemory(conversationID: "conversation-1")

        XCTAssertEqual(core, ["prefers concise direct answers"])
        XCTAssertEqual(working, ["Current task: Walking Beam brief review"])
    }
}
```

- [ ] **Step 2: Run focused test and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoMemoryServiceTests
```

Expected: FAIL because `CosmoMemoryService` does not exist.

- [ ] **Step 3: Implement memory service**

Create `Agent/Context/CosmoMemoryService.swift`:

```swift
import Foundation

actor CosmoMemoryService {
    static let shared = CosmoMemoryService()

    private var coreByKey: [String: String] = [:]
    private var workingByConversationID: [String: [String]] = [:]
    private var archival: [String] = []

    static func inMemoryForTests() -> CosmoMemoryService {
        CosmoMemoryService()
    }

    func upsertCoreMemory(_ value: String, key: String) async throws {
        coreByKey[key] = value
    }

    func coreMemory() async throws -> [String] {
        coreByKey.keys.sorted().compactMap { coreByKey[$0] }
    }

    func upsertWorkingMemory(_ conversationID: String, value: String) async throws {
        var values = workingByConversationID[conversationID] ?? []
        if !values.contains(value) {
            values.append(value)
        }
        workingByConversationID[conversationID] = values
    }

    func workingMemory(conversationID: String) async throws -> [String] {
        workingByConversationID[conversationID] ?? []
    }

    func addArchivalMemory(_ value: String) async throws {
        archival.append(value)
    }

    func searchArchivalMemory(query: String, limit: Int = 5) async throws -> [String] {
        let lower = query.lowercased()
        return archival
            .filter { $0.lowercased().contains(lower) }
            .prefix(limit)
            .map { $0 }
    }
}
```

- [ ] **Step 4: Add file to Xcode sources**

Add `Agent/Context/CosmoMemoryService.swift` to the `CosmoOS` target sources.

- [ ] **Step 5: Wire memory into context packs**

In `routeToAgentService(text:)`, replace empty memory arrays with:

```swift
let coreMemory = (try? await CosmoMemoryService.shared.coreMemory()) ?? []
let workingMemory = (try? await CosmoMemoryService.shared.workingMemory(conversationID: conversationId)) ?? []
let contextPack = ContextPackAssembler.assemble(
    request: retrievalRequest,
    retrievalResults: retrievalResults,
    coreMemory: coreMemory,
    workingMemory: workingMemory,
    recallMemory: []
)
```

- [ ] **Step 6: Verify tests pass**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoMemoryServiceTests
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: PASS and build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Agent/Context/CosmoMemoryService.swift UI/CosmoWindow/CosmoWindowViewModel.swift Tests/CosmoOSTests/CosmoMemoryServiceTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: add shared memory hierarchy"
```

### Task 11: Add Memory Tools

**Files:**
- Modify: `Agent/Core/AgentToolRegistry.swift`
- Modify: `Agent/Core/AgentToolExecutor.swift`
- Test: `Tests/CosmoOSTests/CosmoMemoryServiceTests.swift`

- [ ] **Step 1: Add failing memory tool tests**

Append:

```swift
func testAgentRegistryIncludesSharedMemoryTools() {
    let names = AgentToolRegistry.shared.allTools.map(\.name)
    XCTAssertTrue(names.contains("remember_context"))
    XCTAssertTrue(names.contains("search_memory"))
}
```

- [ ] **Step 2: Register tools**

Add to `contextTools`:

```swift
LLMToolDefinition(
    name: "remember_context",
    description: "Save durable memory only when the user states a stable preference, decision, client rule, or reusable fact. Do not save speculative brainstorm ideas as memory.",
    parametersSchema: [
        "type": "object",
        "properties": [
            "key": ["type": "string", "description": "Stable memory key, such as user.style.directness or client.josh.voice"] as [String: Any],
            "value": ["type": "string", "description": "Memory value to save"] as [String: Any],
            "scope": ["type": "string", "description": "core, working, or archival"] as [String: Any]
        ] as [String: Any],
        "required": ["key", "value", "scope"]
    ]
),
LLMToolDefinition(
    name: "search_memory",
    description: "Search durable Cosmo memory and previous conversation recall for relevant prior context.",
    parametersSchema: [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Search query"] as [String: Any],
            "limit": ["type": "integer", "description": "Maximum memories to return"] as [String: Any]
        ] as [String: Any],
        "required": ["query"]
    ]
)
```

- [ ] **Step 3: Execute tools**

Add cases:

```swift
case "remember_context": return try await rememberContext(arguments)
case "search_memory": return try await searchMemory(arguments)
```

Add methods:

```swift
private func rememberContext(_ args: [String: Any]) async throws -> String {
    guard let key = args["key"] as? String,
          let value = args["value"] as? String,
          let scope = args["scope"] as? String else {
        return jsonError("Missing required parameters: key, value, scope")
    }

    switch scope {
    case "core":
        try await CosmoMemoryService.shared.upsertCoreMemory(value, key: key)
    case "working":
        try await CosmoMemoryService.shared.upsertWorkingMemory("tool-context", value: value)
    case "archival":
        try await CosmoMemoryService.shared.addArchivalMemory(value)
    default:
        return jsonError("Invalid scope: \(scope)")
    }

    return jsonEncode(["success": true, "scope": scope, "key": key])
}

private func searchMemory(_ args: [String: Any]) async throws -> String {
    guard let query = args["query"] as? String else {
        return jsonError("Missing required parameter: query")
    }
    let limit = args["limit"] as? Int ?? 5
    let archival = try await CosmoMemoryService.shared.searchArchivalMemory(query: query, limit: limit)
    return jsonEncode(["results": archival, "count": archival.count])
}
```

- [ ] **Step 4: Verify tests and build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoMemoryServiceTests/testAgentRegistryIncludesSharedMemoryTools
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: PASS and build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Agent/Core/AgentToolRegistry.swift Agent/Core/AgentToolExecutor.swift Tests/CosmoOSTests/CosmoMemoryServiceTests.swift
git commit -m "feat: expose shared memory tools"
```

## Phase 7: Shared Adoption Beyond Option+A

### Task 12: Writing Mode Context Pack Integration

**Files:**
- Modify writing request builders in `UI/FocusMode/Content/` and `Agent/Core/AgentToolExecutor.swift`
- Test: `Tests/CosmoOSTests/WritingAIContextTests.swift`

- [ ] **Step 1: Add failing writing context test**

Add:

```swift
func testWritingRequestsCanCarrySharedContextPack() {
    let request = ContextRetrievalRequest(
        query: "draft from the brief",
        conversationID: "conversation-1",
        surface: .writingMode,
        purpose: .writing,
        pinnedSourceIDs: ["source-1"],
        activeAtomUUID: "content-1",
        activeClientUUID: "client-1",
        maxChunks: 8,
        tokenBudget: 5_000
    )

    XCTAssertEqual(request.surface, .writingMode)
    XCTAssertEqual(request.purpose, .writing)
}
```

- [ ] **Step 2: Add `contextPack` to writing request payloads**

Where writing calls are assembled, add:

```swift
let retrievalRequest = ContextRetrievalRequest(
    query: prompt,
    conversationID: contentUUID,
    surface: .writingMode,
    purpose: .writing,
    pinnedSourceIDs: AgentToolExecutor.shared.contextSourceIDs,
    activeAtomUUID: contentUUID,
    activeClientUUID: clientUUID,
    maxChunks: 10,
    tokenBudget: 6_000
)
let retrievalResults = (try? await CosmoRetrievalService.shared.retrieve(retrievalRequest)) ?? []
let contextPack = ContextPackAssembler.assemble(
    request: retrievalRequest,
    retrievalResults: retrievalResults,
    coreMemory: (try? await CosmoMemoryService.shared.coreMemory()) ?? [],
    workingMemory: (try? await CosmoMemoryService.shared.workingMemory(conversationID: contentUUID)) ?? [],
    recallMemory: []
)
```

Add `contextPack.promptBlock` to the writing API's context field.

- [ ] **Step 3: Verify build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add UI/FocusMode/Content Agent/Core/AgentToolExecutor.swift Tests/CosmoOSTests/WritingAIContextTests.swift
git commit -m "feat: pass shared context into writing mode"
```

### Task 13: Focus Panels and CommandK Integration

**Files:**
- Modify: focus panel view models under `UI/FocusMode/`
- Modify: `UI/CommandK/CommandKViewModel.swift`
- Test: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`

- [ ] **Step 1: Add failing CommandK chunk result test**

Add:

```swift
func testCommandKCanRepresentContextChunkResult() {
    let result = RankedResult(
        atomUUID: "atom-1#chunk-2",
        atomType: .content,
        title: "Walking Beam brief",
        snippet: "locks on doors are required",
        semanticWeight: 0.8,
        structuralWeight: 0.9,
        recencyWeight: 0.5,
        usageWeight: 0.5,
        updatedAt: "2026-05-07T00:00:00Z",
        accessCount: 0
    )

    XCTAssertTrue(result.atomUUID.contains("#chunk-2"))
    XCTAssertTrue(result.snippet.contains("locks on doors"))
}
```

- [ ] **Step 2: Add focus session creation helper**

For focus panels, create context retrieval requests with:

```swift
ContextRetrievalRequest(
    query: userPrompt,
    conversationID: focusConversationID,
    surface: .focusPanel,
    purpose: .general,
    pinnedSourceIDs: activeContextSourceIDs,
    activeAtomUUID: activeAtomUUID,
    activeClientUUID: activeClientUUID,
    maxChunks: 6,
    tokenBudget: 2_500
)
```

- [ ] **Step 3: Add CommandK chunk result adapter**

In CommandK search conversion, include chunk anchors:

```swift
let atomUUID = result.source.atomUUID.map { "\($0)#\(result.chunk.anchor ?? result.chunk.id)" } ?? result.chunk.id
```

- [ ] **Step 4: Verify tests and build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CommandKSearchPipelineTests
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: tests PASS and build succeeds.

- [ ] **Step 5: Commit**

```bash
git add UI/FocusMode UI/CommandK/CommandKViewModel.swift Tests/CosmoOSTests/CommandKSearchPipelineTests.swift
git commit -m "feat: share context retrieval with focus and command k"
```

## Phase 8: Contextual Retrieval, Reranking, and Sensemaking

### Task 14: Lazy Contextual Chunk Headers

**Files:**
- Create: `Agent/Context/ContextualChunkAnnotator.swift`
- Modify: `Agent/Context/ContextIndexStore.swift`
- Test: `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`

- [ ] **Step 1: Add failing annotator test**

Append:

```swift
func testContextualHeaderIncludesSourceTitleAndRole() async throws {
    let source = ContextSource(
        id: "source-1",
        kind: .content,
        title: "Walking Beam brief",
        atomUUID: "atom-1",
        bodyHash: "hash",
        metadataHash: "meta",
        pinState: .pinned
    )
    let header = ContextualChunkAnnotator.deterministicHeader(
        source: source,
        chunkOrdinal: 2,
        totalChunks: 5
    )

    XCTAssertTrue(header.contains("Walking Beam brief"))
    XCTAssertTrue(header.contains("content"))
    XCTAssertTrue(header.contains("chunk 3 of 5"))
}
```

- [ ] **Step 2: Implement deterministic first pass**

Create `Agent/Context/ContextualChunkAnnotator.swift`:

```swift
import Foundation

enum ContextualChunkAnnotator {
    static func deterministicHeader(source: ContextSource, chunkOrdinal: Int, totalChunks: Int) -> String {
        "Source: \(source.title). Type: \(source.kind.rawValue). This is chunk \(chunkOrdinal + 1) of \(max(totalChunks, 1))."
    }
}
```

- [ ] **Step 3: Apply headers during indexing**

Before upserting chunks, replace the chunk headers:

```swift
let contextualizedChunks = chunks.enumerated().map { index, chunk in
    var mutable = chunk
    mutable.contextualHeader = ContextualChunkAnnotator.deterministicHeader(
        source: source,
        chunkOrdinal: index,
        totalChunks: chunks.count
    )
    return mutable
}
```

- [ ] **Step 4: Add optional LLM annotation path**

Add a method that can be called asynchronously for high-value pinned docs:

```swift
static func shouldLLMAnnotate(source: ContextSource) -> Bool {
    source.pinState == .pinned && [.content, .clientProfile, .swipe, .atom].contains(source.kind)
}
```

Do not block the user turn on LLM annotation. Deterministic headers are the first-pass quality floor.

- [ ] **Step 5: Verify**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testContextualHeaderIncludesSourceTitleAndRole
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: PASS and build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Agent/Context/ContextualChunkAnnotator.swift Agent/Context/ContextIndexStore.swift Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: add contextual chunk headers"
```

### Task 15: Add Reranking and Global Sensemaking Stubs

**Files:**
- Modify: `Agent/Context/CosmoRetrievalService.swift`
- Create: `Agent/Context/CosmoSensemakingIndex.swift`
- Test: `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`

- [ ] **Step 1: Add rerank ordering test**

Append:

```swift
func testFactLookupRerankerPrefersExactPhraseMatches() {
    let exact = CosmoRetrievalService.rerankScore(
        query: "locks on doors",
        candidateText: "The brief says locks on doors are required.",
        baseScore: 0.4,
        purpose: .factLookup
    )
    let fuzzy = CosmoRetrievalService.rerankScore(
        query: "locks on doors",
        candidateText: "The brief talks about resident safety.",
        baseScore: 0.9,
        purpose: .factLookup
    )

    XCTAssertGreaterThan(exact, fuzzy)
}
```

- [ ] **Step 2: Implement deterministic reranking**

In `CosmoRetrievalService`, add:

```swift
nonisolated static func rerankScore(
    query: String,
    candidateText: String,
    baseScore: Double,
    purpose: RetrievalPurpose
) -> Double {
    let q = query.lowercased()
    let c = candidateText.lowercased()
    var score = baseScore

    if purpose == .factLookup {
        if c.contains(q) {
            score += 2.0
        }
        let queryTerms = q
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        let matches = queryTerms.filter { c.contains($0) }.count
        score += Double(matches) * 0.25
    }

    return score
}
```

Apply this before returning results:

```swift
merged = merged
    .map { result in
        ContextRetrievalResult(
            chunk: result.chunk,
            source: result.source,
            score: Self.rerankScore(
                query: request.query,
                candidateText: result.chunk.searchableText,
                baseScore: result.score,
                purpose: request.purpose
            ),
            matchType: result.matchType
        )
    }
    .sorted { $0.score > $1.score }
```

- [ ] **Step 3: Add sensemaking index stub**

Create `Agent/Context/CosmoSensemakingIndex.swift`:

```swift
import Foundation

struct SensemakingSummary: Codable, Sendable, Equatable {
    let id: String
    let scopeID: String
    let summaryType: String
    let title: String
    let body: String
    let sourceIDs: [String]
    let createdAt: Date
}

actor CosmoSensemakingIndex {
    static let shared = CosmoSensemakingIndex()

    private var summaries: [SensemakingSummary] = []

    func upsert(_ summary: SensemakingSummary) async {
        summaries.removeAll { $0.id == summary.id }
        summaries.append(summary)
    }

    func summaries(scopeID: String) async -> [SensemakingSummary] {
        summaries.filter { $0.scopeID == scopeID }
    }
}
```

- [ ] **Step 4: Verify**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testFactLookupRerankerPrefersExactPhraseMatches
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: PASS and build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Agent/Context/CosmoRetrievalService.swift Agent/Context/CosmoSensemakingIndex.swift Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: rerank context retrieval and seed sensemaking index"
```

## Phase 9: Evaluation and Rollout

### Task 16: Add Retrieval Evals

**Files:**
- Create: `Tests/CosmoOSTests/CosmoRetrievalEvalTests.swift`
- Create: `Tests/Fixtures/context-retrieval-fixtures.json`

- [ ] **Step 1: Add fixture**

Create `Tests/Fixtures/context-retrieval-fixtures.json`:

```json
[
  {
    "name": "locks_on_doors_exact_lookup",
    "title": "Walking Beam brief",
    "body": "Setup requirements include clean rooms, documented intake, and locks on doors before residents arrive.",
    "query": "does the brief mention locks on doors?",
    "expectedPhrase": "locks on doors"
  },
  {
    "name": "client_voice_semantic_lookup",
    "title": "Josh profile",
    "body": "Josh's voice is blunt, practical, and direct. Avoid polished corporate phrasing.",
    "query": "how should this sound for Josh?",
    "expectedPhrase": "blunt, practical, and direct"
  }
]
```

- [ ] **Step 2: Add eval test**

Create `Tests/CosmoOSTests/CosmoRetrievalEvalTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoRetrievalEvalTests: XCTestCase {
    struct Fixture: Decodable {
        let name: String
        let title: String
        let body: String
        let query: String
        let expectedPhrase: String
    }

    func testPinnedSourceRetrievalFixtures() async throws {
        let data = try XCTUnwrap(
            Bundle.module.url(forResource: "context-retrieval-fixtures", withExtension: "json")
        ).dataRepresentation
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)

        for fixture in fixtures {
            let store = ContextIndexStore.inMemoryForTests()
            let source = ContextSource(
                id: fixture.name,
                kind: .atom,
                title: fixture.title,
                atomUUID: fixture.name,
                bodyHash: "hash",
                metadataHash: "meta",
                pinState: .pinned
            )
            let chunks = ContextChunker.chunk(sourceID: source.id, title: source.title, body: fixture.body, bodyHash: "hash")
            try await store.upsert(source: source, chunks: chunks)

            let service = CosmoRetrievalService(indexStore: store)
            let request = ContextRetrievalRequest(
                query: fixture.query,
                conversationID: "eval",
                surface: .cosmoWindow,
                purpose: .factLookup,
                pinnedSourceIDs: [source.id],
                activeAtomUUID: nil,
                activeClientUUID: nil,
                maxChunks: 3,
                tokenBudget: 1_200
            )
            let results = try await service.retrieve(request)

            XCTAssertTrue(
                results.contains { $0.chunk.rawText.localizedCaseInsensitiveContains(fixture.expectedPhrase) },
                "Expected \(fixture.name) to retrieve \(fixture.expectedPhrase)"
            )
        }
    }
}
```

- [ ] **Step 3: Verify eval**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalEvalTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/CosmoOSTests/CosmoRetrievalEvalTests.swift Tests/Fixtures/context-retrieval-fixtures.json
git commit -m "test: add context retrieval eval fixtures"
```

### Task 17: Add Runtime Trace and Degraded Mode

**Files:**
- Modify: `Agent/Context/CosmoRetrievalService.swift`
- Modify: `UI/CosmoWindow/CosmoWindowViewModel.swift`
- Test: `Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift`

- [ ] **Step 1: Add degraded-mode test**

Append:

```swift
func testRetrievalStillWorksWithoutEmbeddingsForExactLookup() async throws {
    let store = ContextIndexStore.inMemoryForTests()
    let source = ContextSource(
        id: "source-1",
        kind: .atom,
        title: "Brief",
        atomUUID: "atom-1",
        bodyHash: "hash",
        metadataHash: "meta",
        pinState: .pinned
    )
    let chunks = ContextChunker.chunk(
        sourceID: source.id,
        title: source.title,
        body: "Locks on doors are required.",
        bodyHash: "hash"
    )
    try await store.upsert(source: source, chunks: chunks)

    let service = CosmoRetrievalService(indexStore: store)
    let request = ContextRetrievalRequest(
        query: "locks on doors",
        conversationID: "conversation-1",
        surface: .cosmoWindow,
        purpose: .factLookup,
        pinnedSourceIDs: ["source-1"],
        activeAtomUUID: nil,
        activeClientUUID: nil,
        maxChunks: 3,
        tokenBudget: 1_200
    )

    let results = try await service.retrieve(request)

    XCTAssertFalse(results.isEmpty)
    XCTAssertEqual(results.first?.matchType, "keyword")
}
```

- [ ] **Step 2: Add trace rows**

Add trace lines to `AgentContextPack.provenanceLines`:

```swift
"Searched \(request.pinnedSourceIDs.count) pinned source(s) for: \(request.query)"
```

In Option+A `pendingContextTraceSections`, append retrieval trace rows from `contextPack.provenanceLines`.

- [ ] **Step 3: Verify**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoRetrievalServiceTests/testRetrievalStillWorksWithoutEmbeddingsForExactLookup
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: PASS and build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Agent/Context/CosmoRetrievalService.swift Agent/Context/ContextSource.swift UI/CosmoWindow/CosmoWindowViewModel.swift Tests/CosmoOSTests/CosmoRetrievalServiceTests.swift
git commit -m "feat: trace retrieval and support degraded mode"
```

## Final Verification

- [ ] **Run full focused test suite**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test \
  -only-testing:CosmoOSTests/CosmoContextChunkerTests \
  -only-testing:CosmoOSTests/CosmoRetrievalServiceTests \
  -only-testing:CosmoOSTests/CosmoContextPackAssemblerTests \
  -only-testing:CosmoOSTests/CosmoMemoryServiceTests \
  -only-testing:CosmoOSTests/CosmoWindowContextSessionTests \
  -only-testing:CosmoOSTests/CosmoRetrievalEvalTests
```

Expected: PASS.

- [ ] **Run app build**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Manual Option+A check**

1. Open Option+A.
2. Attach a long doc with `@`.
3. Ask: `does this doc mention locks on doors?`
4. Expected: Cosmo searches pinned context, cites the doc title, and returns the exact phrase if present.
5. Ask a second unrelated message.
6. Expected: Cosmo answers the new message, not the previous one.
7. Ask: `what did we decide about this brief?`
8. Expected: Cosmo searches working or recall memory and separates decisions from suggestions.

- [ ] **Manual Writing Mode check**

1. Attach a client profile and source brief.
2. Ask for a short draft.
3. Expected: writing output reflects retrieved client voice and brief facts.
4. Ask for a revision.
5. Expected: revision uses prior feedback and the same pinned sources.

## Rollout Notes

- Ship Phase 1 through Phase 4 first. This directly fixes the user-visible failure mode where attached docs are forgotten or truncated.
- Hide GraphRAG/RAPTOR UI until Phase 8. Those features should improve global synthesis without blocking basic fact lookup.
- Keep BM25 exact phrase retrieval as the reliability floor. Embeddings and rerankers improve quality but must not be required for literal source questions.
- Do not remove existing `linkedAtomUUIDs` until all surfaces consume `ContextSession`; keep it as a compatibility bridge.

## Plan Self-Review

- Spec coverage: all design requirements map to phases: source/session, chunking, retrieval, context packs, Option+A, tools, memory hierarchy, shared adoption, sensemaking, evals.
- Template-marker scan: no unfinished markers remain.
- Type consistency: all new core types are introduced in `ContextSource.swift` before later tasks use them.
- Risk note: `CosmoOSTests` is not currently runnable through Xcode, so Phase 0 is mandatory before TDD work can proceed reliably.
