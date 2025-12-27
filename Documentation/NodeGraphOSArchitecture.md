# NodeGraph OS Architecture

## The Consciousness Constellation Engine

**Version:** 1.0 (Initial Design)
**Last Updated:** December 2024
**Status:** Design Complete, Ready for Implementation

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Core Philosophy](#2-core-philosophy)
3. [Architecture Overview](#3-architecture-overview)
4. [Data Model](#4-data-model)
5. [Semantic Pipeline](#5-semantic-pipeline)
6. [Graph Engine](#6-graph-engine)
7. [Relevance Ranking](#7-relevance-ranking)
8. [Focus Awareness](#8-focus-awareness)
9. [Command-K UI Specification](#9-command-k-ui-specification)
10. [Metal Rendering Pipeline](#10-metal-rendering-pipeline)
11. [Real-time Update System](#11-real-time-update-system)
12. [Caching Architecture](#12-caching-architecture)
13. [Edge Cases (30+)](#13-edge-cases)
14. [File Reference](#14-file-reference)
15. [Implementation Sequence](#15-implementation-sequence)
16. [Integration Patterns](#16-integration-patterns)
17. [Testing Strategy](#17-testing-strategy)
18. [Future Considerations](#18-future-considerations)

---

## 1. Executive Summary

NodeGraph OS is CosmoOS's universal graph intelligence engine - a living semantic constellation that powers Command-K search, contextual relevance, and dynamic visualization of the user's knowledge network. Unlike traditional search that scans text, NodeGraph OS **understands relationships**, surfacing the right ATOM at the right moment based on context, similarity, and usage patterns.

### Key Characteristics

| Aspect | Implementation |
|--------|----------------|
| **Data Model** | 100% ATOM Architecture - nodes are ATOMs, edges are relationships |
| **Embeddings** | Nomic 256-dim vectors via existing VectorDatabase |
| **Rendering** | Metal GPU-accelerated constellation (matches Sanctuary) |
| **Updates** | Real-time incremental (not batch rebuilds) |
| **Latency** | <50ms instant results, <500ms semantic results |
| **Memory** | <200MB for 100K+ node graphs on 16GB RAM |
| **Platform** | macOS only (keyboard-driven Command-K) |

### What Makes It "Conscious"

1. **Context-aware centering** - The focus ATOM becomes your constellation's center
2. **Multi-signal relevance** - Combines semantic + structural + recency + usage
3. **Incremental intelligence** - Graph updates as you work, not on-demand
4. **Graceful fallbacks** - Never fails silently, always returns useful results
5. **Sanctuary-aligned** - Magical orbs, not utilitarian circles

---

## 2. Core Philosophy

### The Constellation Mental Model

```
┌─────────────────────────────────────────────────────────────────┐
│                     NODEGRAPH OS ARCHITECTURE                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Your Knowledge as a Constellation                              │
│                                                                  │
│              ○ research                                          │
│           ╱                                                      │
│      ○ idea ──────── ★ FOCUS ──────── ○ task                    │
│           ╲             │             ╱                          │
│              ○ content  │  ○ connection                          │
│                         │                                        │
│                    ○ project                                     │
│                                                                  │
│   The star (★) is always YOUR current context:                  │
│   • Writing a thread? It's the center                           │
│   • Viewing research? It's the center                           │
│   • In Plannerum? Today's schedule is the center                │
│                                                                  │
│   Everything orbits based on RELEVANCE to your focus            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Everything is an ATOM**
   - GraphNodes reference ATOMs by UUID
   - Edges encode AtomLinks + semantic similarity
   - No new entity types, only graph metadata

2. **Incremental, Not Rebuild**
   - ATOM created → Add node, compute edges
   - ATOM edited → Update node, recompute affected edges
   - Never full graph recomputation

3. **Context is King**
   - Focus context determines constellation center
   - Search adapts to where user is working
   - Results boosted by contextual proximity

4. **Sanctuary Aesthetic**
   - Nodes are magical orbs with glow layers
   - Edges flow with energy animation
   - Dark void background, dimension colors

5. **Graceful Degradation**
   - No embedding? Use BM25
   - Embedding service down? Use structural links
   - Empty query? Show hot context neighbors

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      COMMAND-K OVERLAY                           │
│              (70% screen, glass material, Sanctuary style)       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    COMMAND-K VIEW MODEL                          │
│         Query processing, result ranking, constellation state    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
┌─────────▼──────┐  ┌───────▼───────┐  ┌─────▼─────────┐
│  GRAPH QUERY   │  │    FOCUS      │  │  CONSTELLATION │
│    ENGINE      │  │   CONTEXT     │  │    LAYOUT      │
│                │  │   DETECTOR    │  │    ENGINE      │
│ • Neighborhood │  │               │  │                │
│ • Top-K search │  │ • Context     │  │ • Radial       │
│ • Filtering    │  │   detection   │  │   positioning  │
└───────┬────────┘  │ • Adaptation  │  │ • Force        │
        │           └───────┬───────┘  │   refinement   │
        │                   │          └────────────────┘
        │                   │
┌───────▼───────────────────▼─────────────────────────────────────┐
│                    NODE GRAPH ENGINE                             │
│               (Central actor, change detection)                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
┌─────────▼──────┐  ┌───────▼───────┐  ┌─────▼─────────┐
│   GRAPH NODE   │  │  GRAPH EDGE   │  │    WEIGHT     │
│    STORE       │  │    STORE      │  │  CALCULATOR   │
│                │  │               │  │               │
│ • SQLite table │  │ • SQLite table│  │ • Semantic    │
│ • Indexes      │  │ • Indexes     │  │ • Structural  │
│ • PageRank     │  │ • Weight      │  │ • Recency     │
└───────┬────────┘  └───────┬───────┘  │ • Usage       │
        │                   │          └───────────────┘
        │                   │
┌───────▼───────────────────▼─────────────────────────────────────┐
│                    ATOM REPOSITORY                               │
│              (CRUD hooks notify NodeGraphEngine)                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    VECTOR DATABASE                               │
│         (Nomic 256-dim, HNSW index, semantic search)            │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Purpose |
|-----------|---------|
| **Command-K Overlay** | 70% glass overlay with constellation, results, preview |
| **ViewModel** | Query state, result merging, keyboard navigation |
| **GraphQueryEngine** | Neighborhood traversal, top-K relevance |
| **FocusContextDetector** | Detect user context from view hierarchy |
| **ConstellationLayoutEngine** | Radial + force-directed node positioning |
| **NodeGraphEngine** | Central actor for incremental updates |
| **WeightCalculator** | 4-component relevance scoring |
| **GraphNode/Edge Stores** | SQLite persistence with indexes |

---

## 4. Data Model

### 4.1 GraphNode Schema

```swift
// CosmoOS/Graph/Models/GraphNode.swift

public struct GraphNode: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "graph_nodes"

    // ═══════════════════════════════════════════════════════════════
    // IDENTITY - References the Atom
    // ═══════════════════════════════════════════════════════════════

    public var id: Int64?
    public var atomUUID: String          // FK to atoms.uuid (PRIMARY KEY concept)
    public var atomType: String          // Denormalized for O(1) filtering
    public var atomCategory: String      // AtomCategory for clustering

    // ═══════════════════════════════════════════════════════════════
    // POSITION HINTS - For constellation visualization
    // ═══════════════════════════════════════════════════════════════

    public var positionX: Double?        // Cached X in 2D projection
    public var positionY: Double?        // Cached Y in 2D projection
    public var clusterHint: String?      // Semantic cluster assignment

    // ═══════════════════════════════════════════════════════════════
    // RELEVANCE CACHE - Pre-computed for ranking
    // ═══════════════════════════════════════════════════════════════

    public var pageRank: Double          // 0-1, computed periodically
    public var inDegree: Int             // Incoming edge count
    public var outDegree: Int            // Outgoing edge count
    public var accessCount: Int          // Usage frequency
    public var lastAccessedAt: String?   // ISO8601 timestamp

    // ═══════════════════════════════════════════════════════════════
    // EMBEDDING STATE - Vector availability
    // ═══════════════════════════════════════════════════════════════

    public var hasEmbedding: Bool        // True if vector exists
    public var embeddingUpdatedAt: String?

    // ═══════════════════════════════════════════════════════════════
    // TIMESTAMPS
    // ═══════════════════════════════════════════════════════════════

    public var createdAt: String
    public var updatedAt: String
    public var atomUpdatedAt: String     // Staleness detection
}
```

### 4.2 GraphEdge Schema

```swift
// CosmoOS/Graph/Models/GraphEdge.swift

public enum GraphEdgeType: String, Codable, CaseIterable, Sendable {
    // Structural edges (from AtomLinks)
    case explicit       // Direct AtomLink (project, parentIdea, etc.)
    case reference      // Reference in Connection mental model

    // Semantic edges (computed)
    case semantic       // Vector similarity > 0.6
    case conceptual     // Shared keywords/concepts
    case contextual     // Same project or dimension

    // Derived edges
    case transitive     // 2-hop inference (A→B→C implies A↔C)
}

public struct GraphEdge: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "graph_edges"

    // ═══════════════════════════════════════════════════════════════
    // IDENTITY
    // ═══════════════════════════════════════════════════════════════

    public var id: Int64?
    public var sourceUUID: String        // Source atom UUID
    public var targetUUID: String        // Target atom UUID

    // ═══════════════════════════════════════════════════════════════
    // EDGE PROPERTIES
    // ═══════════════════════════════════════════════════════════════

    public var edgeType: String          // GraphEdgeType.rawValue
    public var linkType: String?         // AtomLinkType if explicit
    public var isDirected: Bool          // False for semantic edges

    // ═══════════════════════════════════════════════════════════════
    // WEIGHT COMPONENTS - Stored separately for incremental update
    // ═══════════════════════════════════════════════════════════════

    public var structuralWeight: Double  // 0-1: From explicit AtomLinks
    public var semanticWeight: Double    // 0-1: From vector similarity
    public var recencyWeight: Double     // 0-1: Time decay factor
    public var usageWeight: Double       // 0-1: Access frequency
    public var combinedWeight: Double    // Final computed weight

    // ═══════════════════════════════════════════════════════════════
    // METADATA
    // ═══════════════════════════════════════════════════════════════

    public var lastComputedAt: String
    public var createdAt: String
    public var updatedAt: String
}
```

### 4.3 SQL DDL

```sql
-- ═══════════════════════════════════════════════════════════════
-- GRAPH NODES TABLE
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS graph_nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    atom_uuid TEXT NOT NULL UNIQUE,
    atom_type TEXT NOT NULL,
    atom_category TEXT NOT NULL,

    -- Position hints
    position_x REAL,
    position_y REAL,
    cluster_hint TEXT,

    -- Relevance cache
    page_rank REAL DEFAULT 0.0,
    in_degree INTEGER DEFAULT 0,
    out_degree INTEGER DEFAULT 0,
    access_count INTEGER DEFAULT 0,
    last_accessed_at TEXT,

    -- Embedding state
    has_embedding INTEGER DEFAULT 0,
    embedding_updated_at TEXT,

    -- Timestamps
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    atom_updated_at TEXT NOT NULL,

    FOREIGN KEY (atom_uuid) REFERENCES atoms(uuid) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX idx_graph_nodes_type ON graph_nodes(atom_type);
CREATE INDEX idx_graph_nodes_category ON graph_nodes(atom_category);
CREATE INDEX idx_graph_nodes_page_rank ON graph_nodes(page_rank DESC);
CREATE INDEX idx_graph_nodes_cluster ON graph_nodes(cluster_hint);
CREATE INDEX idx_graph_nodes_access ON graph_nodes(last_accessed_at DESC);

-- ═══════════════════════════════════════════════════════════════
-- GRAPH EDGES TABLE
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS graph_edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_uuid TEXT NOT NULL,
    target_uuid TEXT NOT NULL,

    -- Edge properties
    edge_type TEXT NOT NULL,
    link_type TEXT,
    is_directed INTEGER DEFAULT 1,

    -- Weight components
    structural_weight REAL DEFAULT 0.0,
    semantic_weight REAL DEFAULT 0.0,
    recency_weight REAL DEFAULT 1.0,
    usage_weight REAL DEFAULT 0.0,
    combined_weight REAL DEFAULT 0.0,

    -- Metadata
    last_computed_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,

    -- Composite unique (directed edge uniqueness)
    UNIQUE(source_uuid, target_uuid, edge_type),

    FOREIGN KEY (source_uuid) REFERENCES graph_nodes(atom_uuid) ON DELETE CASCADE,
    FOREIGN KEY (target_uuid) REFERENCES graph_nodes(atom_uuid) ON DELETE CASCADE
);

-- Indexes for graph traversal
CREATE INDEX idx_graph_edges_source ON graph_edges(source_uuid);
CREATE INDEX idx_graph_edges_target ON graph_edges(target_uuid);
CREATE INDEX idx_graph_edges_type ON graph_edges(edge_type);
CREATE INDEX idx_graph_edges_weight ON graph_edges(combined_weight DESC);
CREATE INDEX idx_graph_edges_source_weight ON graph_edges(source_uuid, combined_weight DESC);
```

---

## 5. Semantic Pipeline

### 5.1 Embedding Lifecycle

```
ATOM Created/Edited
        │
        ▼
┌───────────────────┐
│  DEBOUNCE (500ms) │  ← Prevents embedding storm on rapid typing
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  TEXT EXTRACTION  │  ← title + body + structured (JSON summary)
│  (max 10K chars)  │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  HASH CHECK       │  ← Skip if text unchanged (deduplication)
│  (first 200 chars)│
└─────────┬─────────┘
          │ (hash different)
          ▼
┌───────────────────┐
│  VECTOR DATABASE  │  ← VectorDatabase.index()
│  (Nomic 256-dim)  │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  MARK NODE        │  ← hasEmbedding = true, embeddingUpdatedAt = now
│  (graph_nodes)    │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  SEMANTIC EDGE    │  ← Discover top-10 similar nodes (> 0.6)
│  DISCOVERY        │
└───────────────────┘
```

### 5.2 Embedding Triggers

| Trigger | Action | Debounce |
|---------|--------|----------|
| ATOM created | Queue embedding | 500ms |
| ATOM title changed | Re-embed | 500ms |
| ATOM body changed | Re-embed | 500ms |
| ATOM structured changed | Re-embed | 500ms |
| Bulk import (100+) | Batch embed (32/batch) | None |

### 5.3 Vector Storage (Existing)

Uses existing `VectorDatabase.swift`:
- **Dimensions**: 256 (Nomic Matryoshka truncated)
- **Index**: HNSW when sqlite-vec available, else brute-force
- **Parameters**: M=16, efConstruction=200, efSearch=100
- **Similarity**: Cosine (Accelerate vDSP optimized)

---

## 6. Graph Engine

### 6.1 NodeGraphEngine Actor

```swift
// CosmoOS/Graph/NodeGraphEngine.swift

@MainActor
public final class NodeGraphEngine: ObservableObject {
    public static let shared = NodeGraphEngine()

    // ═══════════════════════════════════════════════════════════════
    // PUBLISHED STATE
    // ═══════════════════════════════════════════════════════════════

    @Published public private(set) var isInitialized = false
    @Published public private(set) var nodeCount: Int = 0
    @Published public private(set) var edgeCount: Int = 0
    @Published public private(set) var isUpdating = false

    // ═══════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════

    private let semanticEdgeThreshold: Float = 0.6
    private let maxSemanticEdgesPerNode = 10
    private let debounceInterval: TimeInterval = 0.5
    private let batchSize = 100

    // ═══════════════════════════════════════════════════════════════
    // DEBOUNCING
    // ═══════════════════════════════════════════════════════════════

    private var pendingUpdates: Set<String> = []  // Atom UUIDs
    private var updateTimer: Timer?
}
```

### 6.2 Incremental Update Algorithm

**On ATOM Created:**
```
1. GraphNode.from(atom) → INSERT graph_nodes
2. For each AtomLink in atom.linksList:
   → INSERT graph_edges (type: explicit, linkType: AtomLink.type)
   → UPDATE degree counts for source and target
3. Queue embedding generation (async, debounced)
4. After embedding ready → discoverSemanticEdges()
```

**On ATOM Edited:**
```
1. UPDATE graph_nodes (atomType, atomCategory, atomUpdatedAt)
2. Reconcile explicit edges:
   → Get current AtomLinks
   → Get existing explicit edges
   → DELETE removed edges, UPDATE degree counts
   → INSERT new edges, UPDATE degree counts
3. If content changed (title, body, structured):
   → Queue re-embedding (debounced)
   → After embedding ready → re-discover semantic edges
```

**On ATOM Deleted:**
```
1. Get all edges involving this node
2. UPDATE neighbor degree counts (decrement)
3. DELETE FROM graph_nodes WHERE atom_uuid = ? (edges CASCADE)
4. Invalidate caches containing this node
```

### 6.3 Semantic Edge Discovery

```swift
func discoverSemanticEdges(for atomUUID: String) async {
    // 1. Get atom content
    guard let atom = await atomRepository.fetch(uuid: atomUUID) else { return }

    // 2. Search VectorDatabase for similar
    let results = try? await vectorDatabase.search(
        query: atom.searchableText,
        limit: maxSemanticEdgesPerNode + 1,  // +1 to exclude self
        entityTypeFilter: nil,
        minSimilarity: semanticEdgeThreshold
    )

    // 3. Create/update semantic edges
    for result in results where result.entityUUID != atomUUID {
        await createOrUpdateSemanticEdge(
            sourceUUID: atomUUID,
            targetUUID: result.entityUUID,
            similarity: result.similarity
        )
    }
}
```

### 6.4 PageRank Computation

Run periodically (weekly or on significant graph changes):

```swift
func computePageRank(iterations: Int = 20, dampingFactor: Double = 0.85) async {
    // Power iteration method
    // 1. Initialize all nodes with 1/N
    // 2. For each iteration:
    //    - Sum incoming edge contributions weighted by combined_weight
    //    - Apply damping factor
    // 3. UPDATE graph_nodes SET page_rank = ?
}
```

---

## 7. Relevance Ranking

### 7.1 The Formula

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   TOTAL RELEVANCE = 0.55 × semantic_similarity                  │
│                   + 0.25 × structural_relevance                 │
│                   + 0.10 × recency_decay                        │
│                   + 0.10 × usage_weight                         │
│                                                                  │
│   All components normalized to [0.0, 1.0]                       │
│   Total clamped to [0.0, 1.0]                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Component Computation

**Semantic Similarity (55%)**
```
Source: VectorDatabase cosine similarity
Normalization: Direct (already 0-1)
Fallback: BM25 score / 25.0 (clamped)
```

**Structural Relevance (25%)**
```
Explicit AtomLink:        1.0
Shared project:           0.7
Canvas proximity:         0.6 × distance_decay
Transitive (2-hop):       0.4
Shared concepts:          0.35
```

**Recency Decay (10%)**
```
Formula: exp(-ln(2) × days_since / half_life)
Half-life: 7 days
Floor: 0.1 (even old items have value)
Boost: Items updated today get 1.0
```

**Usage Weight (10%)**
```
Access types: view (0.5), edit (1.0), search (0.3), reference (0.7)
Formula: sigmoid(weighted_sum - 3)
Logarithmic scaling to prevent outlier dominance
```

### 7.3 Fallback Cascade

```
┌──────────────────────────────────────────────────────────────────┐
│                       FALLBACK CASCADE                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│   TRY: Semantic similarity from VectorDatabase                   │
│         │                                                         │
│         ▼ (no embedding)                                          │
│   TRY: BM25 keyword matching (HybridSearchEngine)                │
│         │                                                         │
│         ▼ (BM25 fails)                                           │
│   TRY: Structural links only (AtomLinks + ConnectionDiscovery)   │
│         │                                                         │
│         ▼ (no links)                                              │
│   LAST: Recency + usage only (hot context, recent items)         │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### 7.4 Tie-Breaking Strategy

When scores are equal:
```
1. Recency: Updated within 1 hour wins
2. Entity type priority: task > idea > content > research > connection > project
3. Alphabetical: By title
4. Stable ID: By entity ID (deterministic)
```

---

## 8. Focus Awareness

### 8.1 Context Types

```swift
public enum FocusContextType: String, CaseIterable, Sendable {
    case home           // Home/Lobby - no specific focus
    case thinkspace     // Canvas editing (Thinkspace)
    case plannerum      // Schedule/calendar view
    case dimension      // Sanctuary dimension drill-down
    case research       // Reading research
    case client         // Connection focus (client pipeline)
    case thread         // Writing content
    case idea           // Editing idea
    case task           // Task detail view
    case project        // Project overview
    case library        // Browsing library section

    var searchBoostMultiplier: Float {
        switch self {
        case .thinkspace, .thread, .idea: return 1.2
        case .plannerum: return 1.1
        case .research, .library: return 1.0
        default: return 0.8
        }
    }
}
```

### 8.2 Context Detection Flow

```
View Appears
     │
     ▼
┌─────────────────────┐
│ onViewActivated()   │  ← Called by view lifecycle
│ section, entityType,│
│ entityId, dimension │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ DEBOUNCE (300ms)    │  ← Prevents thrashing on rapid navigation
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ BUILD CONTEXT       │
│ • Determine type    │
│ • Fetch focus atom  │
│ • Get/compute       │
│   embedding         │
│ • Extract concepts  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ PUBLISH CONTEXT     │
│ NotificationCenter  │
│ .focusContextChanged│
└─────────────────────┘
```

### 8.3 Context-Aware Search Adaptation

| Context | Entity Type Boosts |
|---------|-------------------|
| Thread (writing) | Research 1.3×, Ideas 1.2×, Content 0.8× |
| Client (pipeline) | Project 1.3×, Tasks 1.2×, Ideas 1.1× |
| Plannerum | Tasks 1.5×, Projects 1.2× |
| Research (reading) | Ideas 1.4×, Content 1.2×, Connections 1.1× |
| Dimension | Dimension-specific ATOMs boosted |
| Thinkspace | Canvas proximity boost enabled |

### 8.4 FocusContext Structure

```swift
public struct FocusContext: Sendable {
    public let type: FocusContextType
    public let focusAtom: Atom?              // The centered ATOM
    public let focusAtomVector: [Float]?     // Embedding for similarity
    public let navigationSection: NavigationSection
    public let dimensionType: DimensionType? // If in Sanctuary dimension
    public let scheduleDate: Date?           // If in Plannerum
    public let timestamp: Date
    public let hotContext: HotContext?       // From TelepathyEngine
    public let extractedConcepts: [String]
    public let projectId: Int64?

    public var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 300  // 5 minutes
    }

    public var cacheKey: String {
        "\(type.rawValue):\(focusAtom?.type.rawValue ?? "none"):\(focusAtom?.id ?? 0)"
    }
}
```

---

## 9. Command-K UI Specification

### 9.1 Overlay Positioning

```
┌──────────────────────────────────────────────────────────────────┐
│                       SCREEN (100%)                               │
│                                                                   │
│   ┌───────────────────────────────────────────────────────────┐  │
│   │                   10% margin top                           │  │
│   │   ┌───────────────────────────────────────────────────┐   │  │
│   │   │                                                   │   │  │
│   │   │              COMMAND-K OVERLAY                    │   │  │
│   │   │                                                   │   │  │
│   │   │            75% width × 70% height                 │   │  │
│   │   │            min: 900 × 600                         │   │  │
│   │   │            max: 1400 × 900                        │   │  │
│   │   │                                                   │   │  │
│   │   │            Corner radius: 24px                    │   │  │
│   │   │                                                   │   │  │
│   │   └───────────────────────────────────────────────────┘   │  │
│   │                                                           │  │
│   └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│   Background: voidPrimary @ 70% + 20px Gaussian blur             │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### 9.2 Internal Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ Search your knowledge...         [Voice] [Filter Chips]          │ 72px
├──────────────────────────────────────────────────────────────────┤
│ [Ideas] [Tasks] [Research] [Content] [Connections] [All]         │ 48px
├────────────────────────────────────┬─────────────────────────────┤
│                                    │                             │
│        CONSTELLATION VIEW          │       RESULTS LIST          │
│         (Metal Canvas)             │      (Ranked Matches)       │
│                                    │                             │
│       ○ idea     ○ research        │  ┌─────────────────────┐   │
│          ╲         ╱               │  │ Idea Title          │   │
│           ★ FOCUS ★               │  │    Snippet text...   │   │
│          ╱         ╲               │  │    Relevance: 95%    │   │
│       ○ task    ○ content          │  └─────────────────────┘   │
│                                    │                             │
│         60% width                  │       40% width             │
│                                    │                             │
├────────────────────────────────────┴─────────────────────────────┤
│                     PREVIEW DRAWER (slides up)                   │ 160-320px
│  [Type Icon] Title                              [Open] [Pin]     │
│  Preview text excerpt...                        [View Links]     │
│  Metadata: Modified 2h ago • 5 connections                       │
└──────────────────────────────────────────────────────────────────┘
```

### 9.3 Visual Styling (Sanctuary-Aligned)

**Background Layers:**
```swift
ZStack {
    // Layer 1: Blur underlying content
    Rectangle()
        .fill(.ultraThinMaterial)
        .blur(radius: 20)

    // Layer 2: Void overlay
    SanctuaryColors.voidPrimary.opacity(0.7)

    // Layer 3: Subtle aurora glow
    RadialGradient(
        colors: [SanctuaryColors.cognitive.opacity(0.05), .clear],
        center: .center,
        startRadius: 100,
        endRadius: 600
    )
}
```

**Glass Container:**
```swift
.modifier(SanctuaryGlassSurface(
    type: .frosted,
    cornerRadius: 24,
    borderPosition: .all,
    accentColor: nil
))
.shadow(color: .black.opacity(0.3), radius: 40, y: 20)
```

**Color Mapping (ATOM Type → Dimension):**

| ATOM Type | Dimension Color | Hex |
|-----------|-----------------|-----|
| idea, task | Cognitive (Indigo) | #6366F1 |
| content | Creative (Amber) | #F59E0B |
| research, connection | Knowledge (Purple) | #8B5CF6 |
| journalEntry | Reflection (Pink) | #EC4899 |
| project, scheduleBlock | Behavioral (Blue) | #3B82F6 |
| health atoms | Physiological (Teal) | #10B981 |

### 9.4 Keyboard Interactions

| Key | Action | Context |
|-----|--------|---------|
| `Cmd+K` | Open/Close overlay | Global |
| `Escape` | Close overlay / Clear selection | Overlay open |
| `↑ / ↓` | Navigate results list | Results focused |
| `← / →` | Navigate constellation nodes | Constellation focused |
| `Enter` | Open selected node | Any selection |
| `Tab` | Cycle focus: Search → Filters → Constellation → Results | Always |
| `Shift+Tab` | Reverse cycle | Always |
| `Space` | Toggle voice input | Search focused |
| `1-6` | Quick filter by type | Any |
| `Cmd+Enter` | Open in Focus Mode | Node selected |
| `Cmd+P` | Pin selected node | Node selected |

### 9.5 Animation Choreography

**Entry Sequence (700ms total):**

| Phase | Element | Delay | Duration | Animation |
|-------|---------|-------|----------|-----------|
| 1 | Backdrop blur + dim | 0ms | 250ms | Ease-out opacity |
| 2 | Glass container | 50ms | 350ms | Spring scale 0.95→1.0 + opacity |
| 3 | Search bar glow | 150ms | 300ms | Focus ring animation |
| 4 | Filter chips | 200ms | 250ms | Stagger 50ms each |
| 5 | Constellation nodes | 250ms | 400ms | Radial burst from center |
| 6 | Connection lines | 350ms | 200ms | Fade in with glow |
| 7 | Results list | 400ms | 300ms | Slide-up + fade |

**Exit Animation:**
- All elements fade + scale 0.95 simultaneously
- Duration: 250ms

---

## 10. Metal Rendering Pipeline

### 10.1 Constellation Renderer Integration

Extend `SanctuaryMetalRenderer` with new pipelines:

```swift
// CosmoOS/Graph/ConstellationRenderer.swift

final class ConstellationRenderer {
    // Reuse SanctuaryMetalRenderer infrastructure
    private let metalRenderer = SanctuaryMetalRenderer.shared

    // New pipelines
    private(set) var nodeOrbPipeline: MTLRenderPipelineState?
    private(set) var nodeGlowPipeline: MTLRenderPipelineState?
    private(set) var connectionPipeline: MTLRenderPipelineState?
}
```

### 10.2 Node Orb Shader Concept

```
┌─────────────────────────────────────────────────────────────────┐
│                    NODE ORB LAYERS                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   LAYER 3: AMBIENT GLOW (outermost)                             │
│   • Gaussian blur at 2× radius                                  │
│   • Dimension color @ 20-40% opacity                            │
│   • Intensity = relevance score                                 │
│                                                                  │
│   LAYER 2: OUTER GLOW RING                                      │
│   • Ring at 1.1× radius                                         │
│   • Animated rotation                                           │
│   • 6-segment angular gradient                                  │
│                                                                  │
│   LAYER 1: CORE ORB (innermost)                                 │
│   • Radial gradient with highlight                              │
│   • Top-left light source                                       │
│   • Surface noise animation (fbm)                               │
│   • Dimension-colored fill                                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.3 Node Uniforms

```swift
struct NodeOrbUniforms {
    var primaryColor: SIMD4<Float>    // Dimension base color
    var secondaryColor: SIMD4<Float>  // Lighter variant
    var glowColor: SIMD4<Float>       // Glow tint
    var center: SIMD2<Float>          // Screen-space center
    var radius: Float                 // Orb radius in pixels
    var time: Float                   // Animation time
    var relevance: Float              // 0.0 to 1.0 (glow intensity)
    var importance: Float             // 0.0 to 1.0 (size multiplier)
    var isSelected: Float             // 1.0 if selected
    var isHovered: Float              // 1.0 if hovered
    var pulsePhase: Float             // For high-relevance pulse
}
```

### 10.4 Connection Line Shader Concept

```
┌─────────────────────────────────────────────────────────────────┐
│                  CONNECTION LINE RENDERING                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   GEOMETRY: Quadratic Bezier curve                              │
│   • Control point = perpendicular offset from midpoint          │
│   • Curve amount = min(distance × 0.3, 80px)                    │
│                                                                  │
│   VISUAL MAPPING:                                               │
│   • Edge weight 0.0-0.3: 1.0px, 20% opacity, 0.5× flow speed   │
│   • Edge weight 0.3-0.6: 1.5px, 40% opacity, 1.0× flow speed   │
│   • Edge weight 0.6-0.8: 2.0px, 60% opacity, 1.5× flow speed   │
│   • Edge weight 0.8-1.0: 2.5px, 80% opacity, 2.0× flow speed   │
│                                                                  │
│   ANIMATION: Energy flow particles                              │
│   • 8 particles traveling along line                            │
│   • Speed based on edge weight                                  │
│   • Glow trail effect                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.5 Layout Algorithm

**Hybrid Radial + Force-Directed:**

```
Phase 1: Radial Ring Placement
┌────────────────────────────────────────┐
│                                        │
│           ○   ○   ○  ← 3rd degree      │
│         ╱           ╲   (320px)        │
│       ○               ○ ← 2nd degree   │
│      ╱                 ╲  (220px)      │
│    ○                     ○ ← 1st deg   │
│     ╲       ★           ╱   (120px)    │
│      ○     FOCUS       ○               │
│        ╲             ╱                 │
│         ○   ○   ○   ○                  │
│                                        │
└────────────────────────────────────────┘

Phase 2: Force Refinement (10 iterations)
• Node-node repulsion: Push apart if < 80px
• Edge spring forces: Pull together if connected
• Damping: 0.8
• Focus node fixed at center
```

---

## 11. Real-time Update System

### 11.1 Update Triggers

| Event | Handler | Debounce |
|-------|---------|----------|
| Text typing | Update EditingContextTracker | 100ms |
| Text commit | Re-embed ATOM | 500ms |
| Task completed | Boost usage, update project | None |
| Context change | Re-center constellation | 300ms |
| Enter Thinkspace | Build spatial index | None |
| Enter Plannerum | Compute schedule relevance | None |

### 11.2 Real-time Update Flow

```
USER ACTION (typing, navigating, completing)
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    REALTIME UPDATE HANDLER                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   TEXT UPDATE:                                                  │
│   • Update EditingContextTracker immediately                    │
│   • Debounce embedding (500ms)                                  │
│   • Fast local edge update (100ms)                              │
│                                                                  │
│   TASK COMPLETION:                                              │
│   • Record access event (type: edit)                            │
│   • Boost project usage if linked                               │
│   • Update Sanctuary dimension metrics                          │
│   • Refresh hot context if in Plannerum                         │
│                                                                  │
│   CONTEXT CHANGE:                                               │
│   • Re-center constellation on new focus                        │
│   • Prefetch 2-hop neighborhood                                 │
│   • Update hot context cache                                    │
│   • Clear stale query cache                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 12. Caching Architecture

### 12.1 Three-Tier Cache Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                       CACHE HIERARCHY                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   TIER 1: HOT CONTEXT CACHE (Actor)                             │
│   • Focus neighborhood (2-hop)                                  │
│   • TTL: 60 seconds                                             │
│   • Size: 50 entries max                                        │
│   • Invalidation: Focus change                                  │
│                                                                  │
│   TIER 2: QUERY RESULT CACHE (LRU)                              │
│   • Search results by query + context                           │
│   • TTL: 5 minutes                                              │
│   • Size: 100 entries max                                       │
│   • Invalidation: ATOM update containing result                 │
│                                                                  │
│   TIER 3: EMBEDDING CACHE (Actor)                               │
│   • Text → embedding mappings                                   │
│   • TTL: 1 hour                                                 │
│   • Size: 1000 entries max                                      │
│   • Invalidation: Text content change                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.2 Cache Invalidation Triggers

| Event | Invalidates |
|-------|-------------|
| ATOM updated | Query cache (if contains), Embedding cache |
| ATOM deleted | Query cache, Hot context, Edge cache |
| Context changed | Hot context (partial) |
| Bulk import | All caches |
| Manual refresh | All caches |

---

## 13. Edge Cases

### 13.1 Graph State (5 cases)

| # | Edge Case | Handling |
|---|-----------|----------|
| 1 | **Empty graph** (new user) | Show onboarding: "Create your first idea...", template suggestions |
| 2 | **Single node** | Return that node for any query, suggest templates |
| 3 | **100K+ nodes** | Use HNSW index, limit brute-force to 10K, pagination |
| 4 | **Disconnected subgraphs** | Search all subgraphs, no penalty for isolation |
| 5 | **Star topology** (hub dominance) | Cap hub contribution to prevent monopoly |

### 13.2 Search Signals (5 cases)

| # | Edge Case | Handling |
|---|-----------|----------|
| 6 | **No semantic match** | Fall back to BM25 keyword matching |
| 7 | **Conflicting signals** | Trust semantic for search, structural for navigation |
| 8 | **All scores equal** | Apply tie-breaker: recency → type → alpha → ID |
| 9 | **Many exact matches** | Boost exact, disambiguate by context proximity |
| 10 | **Empty query** | Return hot context neighbors, recent items |

### 13.3 Data Modification (5 cases)

| # | Edge Case | Handling |
|---|-----------|----------|
| 11 | **Delete hub node** | Cascade invalidate caches, recompute async |
| 12 | **Rapid edits** | Debounce embedding at 500ms |
| 13 | **Bulk import (100+)** | Batch embed (32/batch), invalidate all caches |
| 14 | **Undo/redo** | Restore cached state if available, else recompute |
| 15 | **Merge duplicates** | Transfer edges to survivor, invalidate both |

### 13.4 Content (5 cases)

| # | Edge Case | Handling |
|---|-----------|----------|
| 16 | **PDF ingestion** | Chunk 500 chars, per-chunk vectors, aggregate search |
| 17 | **Very long (50K+)** | Index first 10K + summary, cursor context |
| 18 | **Non-text (images)** | Use alt-text/caption, show but skip semantic |
| 19 | **Duplicate titles** | Disambiguate with type icon + snippet |
| 20 | **No content** | Use title only, penalize in ranking |

### 13.5 System State (5 cases)

| # | Edge Case | Handling |
|---|-----------|----------|
| 21 | **Offline mode** | Use cached embeddings, BM25 fallback, queue updates |
| 22 | **Embedding service down** | BM25 + structural, warn user of degraded search |
| 23 | **Memory pressure** | Aggressive LRU eviction, reduce hot context size |
| 24 | **Database locked** | Retry with exponential backoff, show cached |
| 25 | **Vector dimension mismatch** | Skip incompatible, log for reindex |

### 13.6 User Behavior (5 cases)

| # | Edge Case | Handling |
|---|-----------|----------|
| 26 | **Frequent context switching** | Extend debounce to 500ms |
| 27 | **Stale context (>5min)** | Mark stale, re-fetch on interaction |
| 28 | **Multi-window** | Each window tracks own context |
| 29 | **Voice + typing** | Prefer voice transcript for hot context |
| 30 | **Search during indexing** | Partial results + progress indicator |

---

## 14. File Reference

### 14.1 Files to CREATE

**Graph Core (New Directory: `CosmoOS/Graph/`)**

| File | Purpose |
|------|---------|
| `Models/GraphNode.swift` | Node schema, GRDB conformance |
| `Models/GraphEdge.swift` | Edge schema, types, GRDB conformance |
| `NodeGraphEngine.swift` | Main engine actor, change detection |
| `GraphQueryEngine.swift` | Neighborhood, top-K, filtering |
| `WeightCalculator.swift` | 4-component relevance scoring |
| `ConstellationLayoutEngine.swift` | Radial + force-directed layout |

**Caching (New Directory: `CosmoOS/Graph/Caches/`)**

| File | Purpose |
|------|---------|
| `HotContextCache.swift` | Focus neighborhood cache |
| `QueryResultCache.swift` | LRU query result cache |
| `EmbeddingCache.swift` | Text → embedding cache |

**Focus (New Directory: `CosmoOS/Focus/`)**

| File | Purpose |
|------|---------|
| `FocusContextDetector.swift` | Context detection from views |
| `ContextAwareSearchAdapter.swift` | Search adaptation by context |

**Command-K UI (New Directory: `CosmoOS/UI/CommandK/`)**

| File | Purpose |
|------|---------|
| `CommandKView.swift` | Main overlay (replaces CommandHubView) |
| `CommandKViewModel.swift` | State, query processing |
| `ConstellationMetalView.swift` | Metal canvas for nodes |
| `ConstellationRenderer.swift` | Metal shader integration |
| `ConstellationShaders.metal` | Node/edge shaders |
| `CommandKSearchBar.swift` | Glass search input |
| `CommandKFilterChips.swift` | Type filter chips |
| `CommandKResultsList.swift` | Ranked results |
| `PreviewDrawer.swift` | ATOM preview panel |
| `CommandKFocusManager.swift` | Keyboard focus handling |

### 14.2 Files to MODIFY

| File | Changes |
|------|---------|
| `Data/Database/CosmoDatabase.swift` | Add graph_nodes, graph_edges table creation |
| `Data/Repositories/AtomRepository.swift` | Add hooks to notify NodeGraphEngine |
| `AI/VectorDatabase.swift` | Expose embedding retrieval for edge discovery |
| `UI/Sanctuary/SanctuaryMetalRenderer.swift` | Add node/connection pipelines (optional extend) |
| `Navigation/CommandHub/CommandHubView.swift` | REPLACE entirely with new CommandKView |

### 14.3 Files UNCHANGED

| File | Reason |
|------|--------|
| `Data/Models/Atom.swift` | No changes, just referenced |
| `UI/Sanctuary/*` | Sanctuary preserved, patterns reused |
| `Voice/*` | Voice commands can be added later |
| `AI/BigBrain/*` | Intelligence engines unchanged |

---

## 15. Implementation Sequence

### Phase 1: Core Data Model

```
1. Create CosmoOS/Graph/ directory structure
2. Implement GraphNode.swift with GRDB conformance
3. Implement GraphEdge.swift with edge types
4. Add graph tables to CosmoDatabase.swift
5. Create indexes for performance
6. Write unit tests for models
7. Build initial graph from existing ATOMs

MILESTONE: Graph tables populated, basic queries working
```

### Phase 2: Incremental Engine

```
8. Implement NodeGraphEngine actor
9. Add AtomRepository hooks for change detection
10. Implement debounced embedding updates
11. Build semantic edge discovery
12. Implement WeightCalculator
13. Add periodic PageRank computation
14. Write integration tests

MILESTONE: Graph updates automatically on ATOM changes
```

### Phase 3: Query & Caching

```
15. Implement GraphQueryEngine
16. Build neighborhood traversal
17. Build top-K relevance search
18. Integrate with HybridSearchEngine
19. Implement 3-tier caching strategy
20. Add cache invalidation triggers
21. Performance testing

MILESTONE: Sub-100ms query performance
```

### Phase 4: Focus Awareness

```
22. Implement FocusContextDetector
23. Build context detection from view hierarchy
24. Add context-aware search adaptation
25. Implement hot context prefetching
26. Handle context transitions
27. Integration testing

MILESTONE: Search adapts to user context
```

### Phase 5: Metal Rendering

```
28. Design node orb shader (3-layer glow)
29. Design connection line shader (energy flow)
30. Create ConstellationRenderer
31. Integrate with SanctuaryMetalRenderer patterns
32. Implement GPU buffer management
33. Add animation uniforms
34. Visual testing

MILESTONE: Nodes render as magical orbs
```

### Phase 6: Layout Algorithm

```
35. Implement ConstellationLayoutEngine
36. Build radial degree ring positioning
37. Add force-directed refinement
38. Handle dynamic graph changes
39. Optimize for 60fps on 16GB RAM
40. Add position caching

MILESTONE: Smooth constellation animations
```

### Phase 7: Command-K UI

```
41. Build CommandKView overlay container
42. Implement glass material styling
43. Build search bar with voice toggle
44. Add filter chips
45. Build results list with keyboard nav
46. Create preview drawer
47. Wire up to GraphQueryEngine
48. Keyboard interaction testing

MILESTONE: Full Command-K UI functional
```

### Phase 8: Integration & Polish

```
49. Remove old CommandHubView
50. Wire Cmd+K shortcut globally
51. Animation choreography (entry/exit)
52. Keyboard interaction refinement
53. Edge case handling
54. Performance optimization
55. End-to-end testing
56. Documentation

MILESTONE: Production-ready release
```

---

## 16. Integration Patterns

### Pattern 1: Adding ATOM Change Hooks

```swift
// AtomRepository.swift

@discardableResult
func createWithGraph(_ atom: Atom) async throws -> Atom {
    let savedAtom = try await create(atom)
    try await NodeGraphEngine.shared.handleAtomCreated(savedAtom)
    return savedAtom
}

@discardableResult
func updateWithGraph(_ atom: Atom) async throws -> Atom {
    let previous = try await fetch(uuid: atom.uuid)
    let updated = try await update(atom)

    var changedFields: [String] = []
    if previous?.title != updated.title { changedFields.append("title") }
    if previous?.body != updated.body { changedFields.append("body") }
    if previous?.links != updated.links { changedFields.append("links") }

    try await NodeGraphEngine.shared.handleAtomUpdated(updated, changedFields: changedFields)
    return updated
}

func deleteWithGraph(uuid: String) async throws {
    try await delete(uuid: uuid)
    try await NodeGraphEngine.shared.handleAtomDeleted(atomUUID: uuid)
}
```

### Pattern 2: Context Detection from Views

```swift
// Any view that should update focus context

struct IdeaDetailView: View {
    let idea: Idea

    var body: some View {
        // ... view content ...
        .onAppear {
            FocusContextDetector.shared.onViewActivated(
                section: .ideas,
                entityType: .idea,
                entityId: idea.id
            )
        }
    }
}
```

### Pattern 3: Keyboard Shortcut Registration

```swift
// MainView.swift or equivalent

.keyboardShortcut("k", modifiers: .command)
.onReceive(NotificationCenter.default.publisher(for: .openCommandK)) { _ in
    showCommandK = true
}
```

---

## 17. Testing Strategy

### 17.1 Unit Tests

```
Tests/CosmoOSTests/Graph/
├── GraphNodeTests.swift          # Model CRUD
├── GraphEdgeTests.swift          # Edge operations
├── WeightCalculatorTests.swift   # Scoring accuracy
├── GraphQueryEngineTests.swift   # Query correctness
└── CacheTests.swift              # Cache behavior
```

### 17.2 Integration Tests

```
Tests/CosmoOSTests/Integration/
├── NodeGraphEngineIntegrationTests.swift  # End-to-end updates
├── SearchPipelineTests.swift              # Query → results
└── FocusContextTests.swift                # Context detection
```

### 17.3 Performance Benchmarks

| Metric | Target |
|--------|--------|
| Query latency (instant) | < 50ms |
| Query latency (semantic) | < 500ms |
| Graph update (single ATOM) | < 100ms |
| Rendering (500 nodes) | 60fps |
| Memory (100K nodes) | < 200MB |

### 17.4 Visual Tests

- Node appearance matches Sanctuary aesthetic
- Glow intensity corresponds to relevance
- Connection lines animate smoothly
- Preview drawer transitions correctly
- Filter chips toggle properly

---

## 18. Future Considerations

### Near-term Enhancements

1. **Voice search in Command-K**: Integrate VoiceEngine for voice queries
2. **Quick actions**: Create ATOM directly from Command-K
3. **Clipboard awareness**: Detect URLs, auto-create research
4. **Recent searches**: Show search history

### Medium-term Enhancements

1. **3D constellation**: Optional Z-axis depth for immersion
2. **Cluster visualization**: Group related ATOMs visually
3. **Time-based view**: Show graph evolution over time
4. **Export graph**: Share constellation as image

### Long-term Vision

1. **Collaborative graphs**: Shared knowledge networks
2. **AI-suggested connections**: LLM-powered link discovery
3. **Cross-device sync**: Graph state syncs with cloud
4. **Plugin system**: Custom node types and edges

---

## Appendix A: Design Token Reference

### Colors (from SanctuaryTokens.swift)

```swift
// Dimension Colors
SanctuaryColors.cognitive      // #6366F1 (Indigo)
SanctuaryColors.creative       // #F59E0B (Amber)
SanctuaryColors.physiological  // #10B981 (Teal)
SanctuaryColors.behavioral     // #3B82F6 (Blue)
SanctuaryColors.knowledge      // #8B5CF6 (Purple)
SanctuaryColors.reflection     // #EC4899 (Pink)

// Background
SanctuaryColors.voidPrimary    // #0A0A0F
SanctuaryColors.voidSecondary  // #12121A
SanctuaryColors.voidTertiary   // #1A1A25

// Glass
SanctuaryColors.glassPrimary   // white @ 8%
SanctuaryColors.glassBorder    // white @ 15%

// Text
SanctuaryColors.textPrimary    // white
SanctuaryColors.textSecondary  // white @ 70%
SanctuaryColors.textTertiary   // white @ 50%
```

### Animation Springs (from SanctuaryTokens.swift)

```swift
SanctuarySprings.press      // response: 0.08, damping: 0.92
SanctuarySprings.hover      // response: 0.15, damping: 0.78
SanctuarySprings.select     // response: 0.2,  damping: 0.85
SanctuarySprings.snappy     // response: 0.25, damping: 0.68
SanctuarySprings.smooth     // response: 0.35, damping: 0.78
SanctuarySprings.gentle     // response: 0.5,  damping: 0.85
SanctuarySprings.cinematic  // response: 0.8,  damping: 0.75
```

### Layout Constants

```swift
// Command-K Overlay
let overlayWidthPercent: CGFloat = 0.75
let overlayHeightPercent: CGFloat = 0.70
let overlayMinSize = CGSize(width: 900, height: 600)
let overlayMaxSize = CGSize(width: 1400, height: 900)
let overlayCornerRadius: CGFloat = 24

// Constellation
let constellationDegreeRadii: [CGFloat] = [0, 120, 220, 320]  // Focus, 1st, 2nd, 3rd
let nodeMinSize: CGFloat = 24
let nodeMaxSize: CGFloat = 72
let nodeSeparation: CGFloat = 80

// Preview Drawer
let drawerCollapsedHeight: CGFloat = 0
let drawerPreviewHeight: CGFloat = 160
let drawerExpandedHeight: CGFloat = 320
```

---

## Appendix B: Quick Reference

### Key Singletons

```swift
NodeGraphEngine.shared          // Graph updates
GraphQueryEngine()              // Queries (instantiate per use)
FocusContextDetector.shared     // Context detection
HotContextCache.shared          // Focus cache
QueryResultCache.shared         // Query cache
EmbeddingCache.shared           // Embedding cache
```

### Key Notifications

```swift
.focusContextChanged     // userInfo: FocusContext
.graphNodeUpdated        // userInfo: ["atomUUID": String]
.graphEdgeUpdated        // userInfo: ["sourceUUID", "targetUUID"]
.openCommandK            // no userInfo
.closeCommandK           // no userInfo
```

### Key Published Properties

```swift
// NodeGraphEngine
@Published var isInitialized: Bool
@Published var nodeCount: Int
@Published var edgeCount: Int
@Published var isUpdating: Bool

// CommandKViewModel
@Published var query: String
@Published var results: [RankedResult]
@Published var selectedNodeId: String?
@Published var isSearching: Bool
@Published var currentPhase: SearchPhase

// FocusContextDetector
@Published var currentContext: FocusContext?
@Published var previousContext: FocusContext?
```

---

*This specification is maintained alongside the codebase. For implementation details, refer to the source files listed in Section 14.*
