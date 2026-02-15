# CosmoOS — Thinkspace, Content & Connection Systems

Architecture reference for the three core workspace/entity systems. Each is built on the universal **Atom** model (GRDB/SQLite) with type-specific metadata stored as JSON.

---

## Table of Contents

1. [Thinkspace System](#1-thinkspace-system)
2. [Content System](#2-content-system)
3. [Connection System](#3-connection-system)
4. [Cross-System Integration](#4-cross-system-integration)

---

## 1. Thinkspace System

Thinkspaces are isolated infinite-canvas workspaces. Each thinkspace has its own set of blocks, zoom/pan state, and optional project assignment. Switching thinkspaces swaps the entire visible canvas.

### 1.1 Data Models

**ThinkspaceMetadata** — stored in `Atom.metadata` as JSON:

| Field | Type | Purpose |
|-------|------|---------|
| `name` | `String` | Display name |
| `lastOpened` | `Date` | Usage tracking / sort order |
| `zoomLevel` | `Double` | Canvas zoom (1.0 = 100%) |
| `panOffsetX` | `Double` | Canvas pan X |
| `panOffsetY` | `Double` | Canvas pan Y |
| `blockIds` | `[String]` | UUIDs of blocks in this thinkspace |
| `projectUuid` | `String?` | Assigned project (nil = unassigned) |
| `parentThinkspaceId` | `String?` | Parent thinkspace (nil = root) |
| `isRootThinkspace` | `Bool` | Auto-created with project |

**Thinkspace** — runtime display model:

```swift
struct Thinkspace: Identifiable, Equatable {
    let id: String              // Atom UUID
    var name: String
    var lastOpened: Date
    var blockCount: Int
    var zoomLevel: Double
    var panOffset: CGSize
    var projectUuid: String?
    var parentThinkspaceId: String?
    var isRootThinkspace: Bool
    var hasChildren: Bool
}
```

**Atom type**: `.thinkspace` — categorized as `.system` (not user-facing in search/library).

### 1.2 Block Isolation

The `canvas_blocks` table has a `thinkspace_id` column:

| `thinkspace_id` | Meaning |
|------------------|---------|
| UUID string | Block belongs to that thinkspace |
| `NULL` | Block belongs to the default/global canvas |

**Loading**: `SpatialEngine.loadBlocks()` filters by `thinkspace_id`:
```sql
SELECT * FROM canvas_blocks
WHERE document_type = 'home'
  AND is_deleted = false
  AND thinkspace_id = ?   -- or IS NULL for default
ORDER BY z_index
```

Blocks are always scoped to a single thinkspace. Switching thinkspaces automatically swaps the visible block set with no cross-thinkspace visibility.

### 1.3 ThinkspaceManager

**File**: `Canvas/ThinkspaceManager.swift`

Singleton `@MainActor` class managing the thinkspace lifecycle.

**Published state**:
```swift
@Published var thinkspaces: [Thinkspace]
@Published var currentThinkspace: Thinkspace?
@Published var isLoading: Bool
@Published var isSidebarVisible: Bool
```

**Key operations**:

| Method | What it does |
|--------|-------------|
| `loadThinkspaces()` | Fetches all `.thinkspace` atoms, sorted by `lastOpened` desc |
| `openLastThinkspace()` | Restores from `UserDefaults("com.cosmo.lastThinkspaceId")` |
| `switchTo(_:)` | Sets current, saves to UserDefaults, posts `thinkspaceChanged` notification |
| `switchToDefault()` | Clears current (loads blocks where `thinkspace_id IS NULL`) |
| `createThinkspace(name:projectUuid:parentThinkspaceId:isRoot:)` | Creates atom + metadata |
| `createSubThinkspace(name:parent:)` | Child inherits parent's `projectUuid` |
| `saveCurrentState(zoomLevel:panOffset:blockIds:)` | Persists canvas layout before close |
| `delete(_:)` / `restoreThinkspace(_:)` | Soft delete with 30-day retention |
| `assignThinkspace(_:to:)` | Moves thinkspace into a project |

**Notifications**: `CosmoNotification.Canvas.thinkspaceChanged` — observed by `CanvasView` to reload blocks.

### 1.4 Project Integration

Projects and thinkspaces form a hierarchy:

```
Project "Content Creation"
└── Root Thinkspace (auto-created, isRootThinkspace = true)
    ├── Sub-Thinkspace "Research"
    ├── Sub-Thinkspace "Drafting"
    └── Sub-Thinkspace "Editing"
```

**Auto-creation flow** (when creating a project):
1. Create `.project` atom
2. Create `.thinkspace` atom with `projectUuid` set, `isRootThinkspace = true`
3. Store thinkspace UUID in `ProjectMetadata.rootThinkspaceUuid`
4. Post `thinkspaceChanged` notification

**Reverse flow**: Dragging an unassigned thinkspace onto the Projects section creates a project from it via `createProjectFromThinkspace()`.

**Restrictions**: Root thinkspaces cannot be unassigned, reparented, or independently deleted.

### 1.5 UI — ThinkspaceSidebar

**File**: `Canvas/ThinkspaceSidebar.swift` (~1,740 lines)

Hover-triggered sidebar (20px left-edge trigger zone, 300ms auto-close delay) with lock button (`AppStorage`).

**Structure**:
```
Header (THINKSPACES + Lock + New)
├── PROJECTS section
│   └── ProjectTreeItem (expandable) → child thinkspaces
├── UNASSIGNED section
│   └── Loose thinkspaces + inline creation
└── RECENTLY DELETED section (30-day retention)
    └── Restore / Empty Trash
```

**Interactions**: Keyboard navigation (arrow keys, Return, Escape), drag-to-project assignment, context menus (rename, duplicate, delete, add sub-thinkspace).

---

## 2. Content System

The content system manages a creator's content lifecycle from initial brainstorm through publication and performance tracking. It uses a **3-step focus mode workflow** and an **8-phase pipeline** for lifecycle management.

### 2.1 Data Models

#### Core Metadata

**ContentAtomMetadata** — stored on `.content` atoms:

| Field | Type | Purpose |
|-------|------|---------|
| `phase` | `ContentPhase` | Current pipeline phase |
| `platform` | `SocialPlatform?` | Target platform |
| `clientProfileUUID` | `String?` | Ghostwriting client reference |
| `wordCount` | `Int` | Current word count |
| `createdPhaseAt` | `Date?` | When entered current phase |
| `lastPhaseTransition` | `Date?` | Most recent phase change |
| `predictedReach` | `Int?` | ML-predicted impressions |
| `predictedEngagement` | `Double?` | ML-predicted engagement rate |

**File**: `Data/Models/LevelSystem/ContentPipelineService.swift`

#### ContentPhase Enum (8-Phase Pipeline)

**File**: `Data/Models/LevelSystem/ContentPipelineMetadata.swift`

| Phase | XP | Icon | Description |
|-------|----|------|-------------|
| `ideation` | 5 | `lightbulb` | Initial concept |
| `outline` | 10 | `list.bullet` | Structure definition |
| `draft` | 25 | `doc.text` | First draft |
| `polish` | 15 | `sparkles` | Editing & refinement |
| `scheduled` | 5 | `calendar` | Ready for publication |
| `published` | 20 | `paperplane.fill` | Live content |
| `analyzing` | 0 | `chart.bar` | Gathering metrics |
| `archived` | 0 | `archivebox` | Historical record |

Each phase has `nextPhase` for forward progression and `completionXP` for gamification.

#### SocialPlatform Enum

Supported: `twitter`, `linkedin`, `instagram`, `tiktok`, `youtube`, `facebook`, `threads`, `substack`, `medium`, `other`

#### Supporting Atom Types

The content pipeline creates multiple atom types as records:

| Atom Type | Purpose | Key Metadata |
|-----------|---------|-------------|
| `.content` | Main content piece | `ContentAtomMetadata` |
| `.contentDraft` | Draft versions | `ContentDraftMetadata` (version, wordCount, diffSummary) |
| `.contentPhase` | Phase transitions | `ContentPhaseMetadata` (from/to phase, timeSpent, xpEarned) |
| `.contentPublish` | Publish events | `ContentPublishMetadata` (platform, postId, postUrl) |
| `.contentPerformance` | Analytics | `ContentPerformanceMetadata` (impressions, reach, engagement) |
| `.clientProfile` | Ghostwriting clients | `ClientProfileMetadata` (handles, platforms, industry) |

#### ContentPerformanceMetadata (Analytics)

Tracks: impressions, reach, likes, comments, shares, saves, profileVisits, followsGained, views, watchTimeSeconds, avgWatchPercentage, engagementRate, viralityScore, isViral.

**Virality thresholds** (per-platform):
- Twitter/X: 100K impressions, 5% engagement
- LinkedIn: 50K impressions, 3% engagement
- Instagram: 50K impressions, 4% engagement
- TikTok: 100K impressions, 10% engagement
- YouTube: 100K impressions, 5% engagement

**XP formula**: `20 base + (impressions/10k)*5 + engagement bonus + 500 viral bonus`

### 2.2 ContentPipelineService

**File**: `Data/Models/LevelSystem/ContentPipelineService.swift`

Orchestrates the content lifecycle. All operations create/update atoms.

| Method | Creates | Awards |
|--------|---------|--------|
| `createContent(title:body:platform:clientUUID:)` | `.content` atom | 5 XP |
| `saveDraft(contentUUID:body:authorNotes:)` | `.contentDraft` atom | — |
| `advancePhase(contentUUID:notes:)` | `.contentPhase` atom | phase XP |
| `recordPublish(contentUUID:platform:postId:)` | `.contentPublish` atom | 20 XP |
| `recordPerformance(contentUUID:...)` | `.contentPerformance` atom | calculated |
| `createClientProfile(name:platforms:)` | `.clientProfile` atom | — |

**Queries**: `fetchContentInPhase()`, `fetchPerformanceHistory()`, `fetchViralContent()`, `getTodayPerformanceSummary()`.

### 2.3 Focus Mode — 3-Step Workflow

**Files**:
- `UI/FocusMode/Content/ContentFocusModeView.swift` — container + routing
- `UI/FocusMode/Content/ContentFocusModeState.swift` — state model
- `UI/FocusMode/Content/ContentBrainstormView.swift` — step 1
- `UI/FocusMode/Content/ContentDraftView.swift` — step 2
- `UI/FocusMode/Content/ContentPolishView.swift` — step 3

#### ContentFocusModeState

```swift
struct ContentFocusModeState: Codable {
    let atomUUID: String
    var currentStep: ContentStep          // brainstorm / draft / polish
    var coreIdea: String                  // Central thesis
    var outline: [OutlineItem]            // Structured outline
    var relatedAtoms: [RelatedAtomRef]    // Auto-discovered context
    var draftContent: String              // Full draft text
    var polishAnalysis: PolishAnalysis?   // Readability metrics
    var aiSuggestions: [AISuggestion]     // Generated improvements
    var polishSystemPrompt: String        // Custom AI guidelines
    var lastModified: Date
}
```

**Persistence**: Atom's `metadata` JSON + `body` field (no UserDefaults). Debounced auto-save (1.5s delay).

#### Step 1: Brainstorm

**Layout**: 60% left (core idea editor + outline) | 40% right (related atoms)

- **Core Idea**: Multi-line text editor, auto-save on blur
- **Outline**: Add/edit/delete/reorder items, checkbox toggle
- **Related Atoms**: Auto-discovered via `HybridSearchEngine`, filterable by type

#### Step 2: Draft

**Layout**: Collapsible sidebar (240px) | Centered editor | Bottom bar

- **Sidebar**: Outline checklist + top 5 related atoms
- **Editor**: TextEditor with optimal reading width, auto-save indicator
- **Bottom Bar**: Navigation, word count, outline completion ratio

#### Step 3: Polish

**Layout**: Readability dashboard | Annotated text | AI suggestions sidebar (320px)

- **Dashboard**: Flesch-Kincaid circular score (color-coded), stats row
- **Annotated Text** (NSTextView): Hemingway-style highlighting:
  - Yellow: 15–25 word sentences
  - Red: >25 word sentences
  - Blue: Passive voice
  - Purple: Adverbs
- **AI Sidebar**: Generate/accept/dismiss suggestions, custom system prompt editor

### 2.4 AI Writing Analysis

#### WritingAnalyzer (On-Device)

**File**: `AI/WritingAnalyzer.swift`

Pure algorithmic analysis using Apple's NaturalLanguage framework. Zero API calls, instant results.

| Metric | Method |
|--------|--------|
| Flesch-Kincaid score | `206.835 - 1.015*(words/sentences) - 84.6*(syllables/words)` |
| Gunning Fog grade | `0.4 * ((words/sentences) + 100*(complexWords/words))` |
| Sentence complexity | Ranges for 15–25 words and >25 words |
| Passive voice | NLTagger: auxiliary verbs + past participles |
| Adverb density | Word-level POS tagging |
| Syllable counting | Vowel-group heuristic with English rules |

**Readability rating**: `good` (60–100), `moderate` (30–59), `difficult` (0–29)

#### PolishEngine (Cloud AI)

**File**: `AI/PolishEngine.swift`

| Setting | Value |
|---------|-------|
| API | OpenRouter |
| Model | `google/gemini-3-flash-preview` |
| Temperature | 0.4 |
| Max tokens | 3000 |

Sends WritingAnalyzer results + problem areas as context. Generates structured suggestions with categories: clarity, activeVoice, conciseness, structure, wordChoice. Supports custom system prompts per session.

### 2.5 Canvas Integration

**File**: `Canvas/ContentBlockView.swift`

Content blocks display a 3-step workflow card on the canvas:

- **Step indicator**: Clickable dots (filled = current, green checkmark = completed)
- **Preview content** varies by step:
  - Brainstorm: Core idea + outline items (max 3)
  - Draft: Excerpt (120 chars) + word count
  - Polish: Readability score circle + stats
- **GRDB observation**: Auto-syncs with atom changes
- **Focus mode opening**: Click badge or context menu → `ContentFocusModeView`

---

## 3. Connection System

Connections are structured mental models for deep thinking about concepts. Each connection has 8 sections that guide the user through a framework for understanding and articulating ideas.

### 3.1 Data Models

#### ConnectionMentalModel

**File**: `Data/Models/AtomExtensions.swift` — stored in `Atom.structured` as JSON.

```swift
struct ConnectionMentalModel: Codable, Sendable, Equatable {
    var idea: String?                   // Core concept
    var personalBelief: String?         // Personal interpretation
    var goal: String?                   // Desired outcome
    var problems: String?               // Pain points
    var benefit: String?                // Value proposition
    var beliefsObjections: String?      // Counterarguments
    var example: String?                // Real-world applications
    var process: String?                // Implementation steps
    var notes: String?                  // Additional notes
    var conceptName: String?            // User's framework name
    var referencesData: String?         // JSON: [ConnectionReference]
    var linkedKnowledge: String?        // JSON: [LinkedKnowledgeItem]
    var sourceText: String?             // Original source JSON
    var extractionConfidence: Double?   // 0–1
}
```

Supports both singular (`problem`, `benefit`) and plural (`problems`, `benefits`) aliases for backward compatibility.

#### ConnectionSectionType (8-Section Framework)

**File**: `UI/FocusMode/Connection/ConnectionFocusModeState.swift`

| # | Section | Color | Prompt Question |
|---|---------|-------|----------------|
| 1 | Goal | Indigo | What is the desired outcome? |
| 2 | Problems | Red | What pain points does this solve? |
| 3 | Benefits | Green | What are the positive outcomes? |
| 4 | Examples | Amber | Real-world applications? |
| 5 | Beliefs & Objections | Purple | Common views, counterarguments? |
| 6 | Process | Cyan | Step-by-step implementation? |
| 7 | Concept Name | Amber | Your unique name for this idea? |
| 8 | References | Indigo | Sources and evidence? |

Each section type provides: `displayName`, `icon` (SF Symbol), `promptQuestion`, `accentColor`, `sortOrder`.

#### ConnectionSection

```swift
struct ConnectionSection: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ConnectionSectionType
    var items: [ConnectionItem]
    var isExpanded: Bool
    var showGhostSuggestions: Bool
    var ghostSuggestions: [GhostSuggestion]
}
```

#### ConnectionItem

```swift
struct ConnectionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String                 // The item text
    var sourceAtomUUID: String?         // If pulled from another atom
    var sourceSnippet: String?          // Original text from source
    let createdAt: Date
    var updatedAt: Date
}
```

#### GhostSuggestion

AI-generated suggestions that appear with dashed borders below items:

```swift
struct GhostSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String                 // Suggested text
    let sourceAtomUUID: String          // Where it came from
    let sourceAtomTitle: String
    let sourceSnippet: String           // Original context
    let targetSectionType: ConnectionSectionType
    let confidence: Double              // 0.0–1.0 (shown if >= 0.6)
}
```

#### Supporting Types

**LinkedKnowledgeItem** — auto-discovered related content:
```swift
struct LinkedKnowledgeItem: Identifiable, Codable {
    let id: String
    let title: String
    let type: String                    // idea, research, connection
    var relevanceScore: Double?         // 0–1
    var explanation: String?            // "Why is this related?"
}
```

**ConnectionReference** — external sources:
```swift
struct ConnectionReference: Codable, Identifiable {
    var id: String
    var title: String
    var url: String?
    var author: String?
    var notes: String?
    var entityType: String?             // If internal atom
    var entityId: Int64?
}
```

**ConnectedSource** — summary of atoms referenced:
```swift
struct ConnectedSource: Identifiable {
    let atomUUID: String
    let atomType: AtomType
    let atomTitle: String
    let connectionStrength: Int         // How many items reference this
}
```

### 3.2 Dual Persistence

Connection state is persisted in two layers for responsiveness:

| Layer | Storage | Speed | Scope |
|-------|---------|-------|-------|
| **UserDefaults** | `connectionFocusMode_{atomUUID}` | ~1ms | Session state, fast UI feedback |
| **Database** | `Atom.structured` (JSON) | ~50–100ms | Durable, survives restarts, syncs to cloud |

**Write strategy**: Focus mode writes to UserDefaults immediately, then debounces (0.5s) before persisting to database.

**Read priority**: UserDefaults first (fastest), fall back to `atom.structured`.

**Canvas block sync**: `ConnectionBlockView` saves to both places simultaneously so focus mode always has the latest state.

### 3.3 ConnectionStore (Live Sync)

**File**: `Data/ConnectionStore.swift`

Shared `@MainActor` singleton providing instant reactivity across all views.

```swift
final class ConnectionStore: ObservableObject {
    static let shared = ConnectionStore()
    @Published private(set) var connections: [Int64: Connection]
    @Published var activeConnectionId: Int64?
}
```

**Live sync pattern**:
1. In-memory cache (`@Published connections`) for instant UI
2. `ValueObservation` watches database changes
3. Debounced saves (0.5s) prevent thrashing
4. Selective updates preserve local unsaved changes

**Key methods**: `connection(for:)`, `loadConnection(_:)`, `update(_:)`, `updateSection(_:keyPath:value:)`, `forceSave(_:)`.

### 3.4 GhostSuggestionEngine

**File**: `AI/GhostSuggestionEngine.swift`

Actor-based AI engine that auto-discovers suggestions from related atoms.

**Pipeline**:
1. Scan related atoms (ideas, research, connections, journal entries)
2. Extract relevant snippets (sentences/paragraphs from body, annotations, highlights)
3. Score relevance per section type:
   - Base: 0.5
   - +0.15 per keyword match
   - +0.1 per title word match
   - +0.15 for section-specific indicators (e.g., "goal", "aim", "objective" for goal section)
4. Filter: only show suggestions with confidence >= 0.6
5. Deduplicate: 70% word overlap = duplicate

**Output**: `[ConnectionSectionType: [GhostSuggestion]]`

### 3.5 KnowledgeLinker

**File**: `AI/KnowledgeLinker.swift`

Auto-discovers and ranks related content for connections using hybrid search.

**Process**:
1. Extract combined text from all connection fields
2. Search all atoms (ideas, research, other connections)
3. Calculate similarity using Jaccard index
4. Use LLM to rank and explain relationships (relevance > 30)
5. Store results in `ConnectionMentalModel.linkedKnowledge`
6. Debounced: 3-second delay, batches updates

### 3.6 Focus Mode

**Files**:
- `UI/FocusMode/Connection/ConnectionFocusModeView.swift`
- `UI/FocusMode/Connection/ConnectionFocusModeState.swift`
- `UI/FocusMode/Connection/ConnectionSectionView.swift`

**Layout**: Infinite canvas with dotted grid background.

- **Anchored**: 8 section cards in a column (centered on canvas)
- **Floating**: Related atom panels (draggable)
- **Connection lines**: `FocusConnectionLinesLayer` renders bezier lines between elements
- **Option+drag**: Creates AtomLink relationships via `FocusConnectManager`

**Section cards**: Header (icon, title, prompt, item/ghost count) → items list → ghost suggestions (dashed) → add item input.

**Ghost suggestion actions**: Accept (converts to item with source attribution) or Dismiss.

**Radial menu**: Right-click to create notes, ideas, tasks, or AI researcher blocks on the canvas.

### 3.7 Canvas Integration

**File**: `Canvas/ConnectionBlockView.swift`

Purple accent color (`blockConnection`). Displays compact section list with inline editing. Bidirectional sync: saves to both `atom.structured` and UserDefaults simultaneously.

### 3.8 Atom Extensions

**File**: `Data/Models/AtomExtensions.swift`

```swift
extension Atom {
    var mentalModel: ConnectionMentalModel?
    var mentalModelOrNew: ConnectionMentalModel
    var combinedText: String              // All fields joined for search
    var linkedKnowledgeItems: [LinkedKnowledgeItem]
    var references: [ConnectionReference]
    func withMentalModel(_:) -> Atom
}
```

Type aliases for compatibility: `typealias Connection = Atom`, `typealias ConnectionWrapper = Atom`.

---

## 4. Cross-System Integration

### 4.1 How They Relate

```
┌─────────────────────────────────────────────────────┐
│                    THINKSPACE                        │
│  (isolated canvas workspace containing blocks)       │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ Content  │  │Connection│  │ Research  │  ...     │
│  │  Block   │  │  Block   │  │  Block    │          │
│  └────┬─────┘  └────┬─────┘  └──────────┘          │
│       │              │                               │
└───────┼──────────────┼───────────────────────────────┘
        │              │
        ▼              ▼
   Focus Mode     Focus Mode
   (3-step)      (8-section)
```

- **Thinkspaces** contain canvas blocks of all types (content, connection, research, idea, etc.)
- Opening a block enters its **focus mode** (content → 3-step workflow, connection → 8-section model)
- **Content** can reference connections and research via `relatedAtoms`
- **Connections** can auto-discover content, ideas, and research via `GhostSuggestionEngine` and `KnowledgeLinker`
- **AtomLinks** connect any atoms bidirectionally across the knowledge graph

### 4.2 Shared Patterns

| Pattern | Thinkspace | Content | Connection |
|---------|-----------|---------|------------|
| **Atom type** | `.thinkspace` | `.content` | `.connection` |
| **Metadata storage** | `Atom.metadata` | `Atom.metadata` + `body` | `Atom.structured` |
| **Focus mode** | N/A (is the canvas) | 3-step workflow | 8-section model |
| **Persistence** | UserDefaults (last opened) | Atom only (debounced) | Dual: UserDefaults + Atom |
| **AI features** | — | WritingAnalyzer + PolishEngine | GhostSuggestionEngine + KnowledgeLinker |
| **Canvas block** | N/A | `ContentBlockView` | `ConnectionBlockView` |
| **XP dimension** | — | `.creative` | `.knowledge` |

### 4.3 Key Files Reference

**Thinkspace**:
- `Canvas/ThinkspaceManager.swift` — lifecycle management
- `Canvas/ThinkspaceSidebar.swift` — sidebar UI (~1,740 lines)
- `Data/Models/Atom.swift` — `ThinkspaceMetadata`, `ProjectMetadata`

**Content**:
- `UI/FocusMode/Content/ContentFocusModeView.swift` — container + routing
- `UI/FocusMode/Content/ContentFocusModeState.swift` — state model + `OutlineItem`, `PolishAnalysis`, `AISuggestion`
- `UI/FocusMode/Content/ContentBrainstormView.swift` — step 1
- `UI/FocusMode/Content/ContentDraftView.swift` — step 2
- `UI/FocusMode/Content/ContentPolishView.swift` — step 3
- `AI/WritingAnalyzer.swift` — on-device NLP analysis
- `AI/PolishEngine.swift` — cloud AI suggestions (Gemini 3 Flash)
- `Data/Models/LevelSystem/ContentPipelineService.swift` — lifecycle orchestration
- `Data/Models/LevelSystem/ContentPipelineMetadata.swift` — `ContentPhase` enum
- `Canvas/ContentBlockView.swift` — canvas block

**Connection**:
- `UI/FocusMode/Connection/ConnectionFocusModeView.swift` — focus mode + view model
- `UI/FocusMode/Connection/ConnectionFocusModeState.swift` — state model + all section/item/ghost types
- `UI/FocusMode/Connection/ConnectionSectionView.swift` — section card component
- `Data/Models/AtomExtensions.swift` — `ConnectionMentalModel`, `LinkedKnowledgeItem`, `ConnectionReference`
- `Data/ConnectionStore.swift` — live sync singleton
- `AI/GhostSuggestionEngine.swift` — AI suggestion generation
- `AI/KnowledgeLinker.swift` — related content discovery
- `Canvas/ConnectionBlockView.swift` — canvas block
