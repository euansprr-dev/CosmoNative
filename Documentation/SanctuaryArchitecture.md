# Sanctuary Architecture

## The Living Neural Dashboard

**Version:** 2.0 (Phase 9+10 Complete)
**Last Updated:** December 2024
**Status:** Production Ready

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Core Philosophy](#2-core-philosophy)
3. [Architecture Overview](#3-architecture-overview)
4. [ATOM Integration](#4-atom-integration)
5. [Voice/LLM Unified Integration](#5-voicellm-unified-integration)
6. [Living Intelligence Engine](#6-living-intelligence-engine)
7. [Data Flow Architecture](#7-data-flow-architecture)
8. [UI Component Architecture](#8-ui-component-architecture)
9. [Sound & Haptics System](#9-sound--haptics-system)
10. [Level System Integration](#10-level-system-integration)
11. [File Reference](#11-file-reference)
12. [Integration Patterns](#12-integration-patterns)
13. [Future Considerations](#13-future-considerations)

---

## 1. Executive Summary

The Sanctuary is CosmoOS's neural interface dashboard - a living, breathing visualization of the user's holistic self. Unlike traditional dashboards that display static data, the Sanctuary **feels alive and telepathic**, surfacing insights that evolve over time and responding to voice commands with sub-300ms latency.

### Key Characteristics

| Aspect | Implementation |
|--------|----------------|
| **Data Model** | 100% ATOM Architecture - every data point is an Atom |
| **Voice Control** | Full VoiceLLMUnified 3-tier pipeline integration |
| **Intelligence** | Living Insights with lifecycle states (fresh → established → decaying) |
| **Refresh Cycle** | 12-hour intelligent sync with delta detection |
| **Latency** | <300ms for voice actions, <50ms for pattern matching |
| **Rendering** | Metal shaders for 120fps particle effects |

### What Makes It "Living"

1. **Insights don't regenerate** - they evolve, strengthen, or decay
2. **Only new data triggers analysis** - no wasteful recomputation
3. **Cross-dimensional correlations** - discovers patterns humans can't see
4. **Telepathic feel** - surfaces the right insight at the right time
5. **Voice-first** - every action is voice-accessible

---

## 2. Core Philosophy

### The Dual-Brain Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     SANCTUARY NEURAL LAYER                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   FunctionGemma 270M (Micro-Brain)    Claude API (Big Brain)   │
│   ┌─────────────────────────────┐     ┌─────────────────────┐   │
│   │ • Fast (<300ms)             │     │ • Deep (2-5s)       │   │
│   │ • Local inference           │     │ • Cloud API         │   │
│   │ • Deterministic             │     │ • Creative reasoning│   │
│   │ • Action execution          │     │ • Pattern discovery │   │
│   │                             │     │                     │   │
│   │ Handles:                    │     │ Handles:            │   │
│   │ • Dimension navigation      │     │ • Correlation       │   │
│   │ • Panel toggles             │     │   analysis          │   │
│   │ • Node selection            │     │ • Grail extraction  │   │
│   │ • Quick actions             │     │ • Semantic clusters │   │
│   └─────────────────────────────┘     └─────────────────────┘   │
│                                                                  │
│   This mirrors biological cognition:                            │
│   Fast local reflexes (neurons) + Slow global reasoning (cortex)│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Everything is an Atom**
   - No legacy tables, unified normalized schema
   - UUID-only identity for cross-entity references
   - Soft deletes only (`is_deleted = 1`)

2. **Intelligence is Invisible**
   - Users never wait for "loading insights"
   - Claude works in background, 12-hour cycles
   - FunctionGemma handles all instant interactions

3. **Smart Caching = Cost Efficiency**
   - Only call Claude when data meaningfully changed
   - Hash-based staleness detection
   - Versioned insights with TTLs

4. **The Sanctuary Feels Alive**
   - Ambient sounds evolve with Cosmo Index
   - Particles respond to real-time data
   - Insights appear organically, not on-demand

---

## 3. Architecture Overview

```
                    ┌─────────────────────────────────────┐
                    │         SANCTUARY UI LAYER          │
                    │  (All 6 Dimension Views + Home)     │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────▼───────────────────┐
                    │      SANCTUARY DATA PROVIDER        │
                    │   Unified access + Caching layer    │
                    └──────┬────────────────────┬─────────┘
                           │                    │
           ┌───────────────▼──────┐   ┌────────▼─────────────┐
           │  LIVING INTELLIGENCE │   │   CAUSALITY ENGINE   │
           │       ENGINE         │   │                      │
           │                      │   │  • 90-day window     │
           │  • Lifecycle mgmt    │   │  • Pearson r calc    │
           │  • Delta detection   │   │  • Lag analysis      │
           │  • Intelligent merge │   │  • Threshold detect  │
           └──────────────────────┘   └──────────────────────┘
                           │                    │
                    ┌──────▼────────────────────▼──────────┐
                    │           ATOM REPOSITORY            │
                    │     Unified CRUD for all entities    │
                    └──────────────────────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────┐
                    │            ATOM DATABASE            │
                    │     44+ types, 9 categories         │
                    └─────────────────────────────────────┘
```

### The Six Dimensions

| Dimension | Color | Icon | Primary Atom Types |
|-----------|-------|------|-------------------|
| **Cognitive** | Cyan | `brain.head.profile` | `.deepWorkBlock`, `.focusScore`, `.task` |
| **Creative** | Amber | `paintbrush.fill` | `.content`, `.contentPerformance`, `.idea` |
| **Physiological** | Red | `heart.fill` | `.hrvMeasurement`, `.sleepCycle`, `.workout` |
| **Behavioral** | Blue | `calendar` | `.scheduleBlock`, `.routineDefinition` |
| **Knowledge** | Purple | `book.fill` | `.research`, `.connection`, `.semanticCluster` |
| **Reflection** | Teal | `leaf.fill` | `.journalEntry`, `.emotionalState`, `.clarityScore` |

---

## 4. ATOM Integration

The Sanctuary is built entirely on the ATOM architecture. Every piece of data displayed, every insight generated, and every user interaction is stored as an Atom.

### Sanctuary-Specific Atom Types

```swift
extension AtomType {
    // Sanctuary Intelligence
    static let livingInsight = AtomType(rawValue: "living_insight")!
    static let correlationInsight = AtomType(rawValue: "correlation_insight")!
    static let syncState = AtomType(rawValue: "sync_state")!
    static let sanctuarySnapshot = AtomType(rawValue: "sanctuary_snapshot")!

    // Semantic Analysis
    static let semanticExtraction = AtomType(rawValue: "semantic_extraction")!
    static let causalityComputation = AtomType(rawValue: "causality_computation")!
}
```

### Data Flow Through Atoms

```
User Action (Voice/Touch)
    │
    ▼
┌─────────────────────┐
│   Create Atom       │  ← AtomRepository.create()
│   (task, journal,   │
│    workout, etc.)   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  DailyCronEngine    │  ← Runs at midnight
│  (aggregate 24h)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  XPCalculationEngine│  ← Base XP + Streak multiplier
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Create .xpEvent    │  ← Atom with XP amount & dimension
│  Atom               │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  CausalityEngine    │  ← 90-day rolling analysis
│  (12h cycle)        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  LivingIntelligence │  ← Delta merge, lifecycle update
│  Engine             │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Create/Update      │  ← .livingInsight Atom
│  .livingInsight     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  SanctuaryData      │  ← Publish to UI
│  Provider           │
└─────────────────────┘
```

### Atom Repository Usage

```swift
// All Sanctuary data access goes through AtomRepository
let repository = AtomRepository.shared

// Fetch recent insights
let insights = try await repository.fetch(
    type: .livingInsight,
    limit: 10,
    sortBy: .createdAt,
    order: .descending
)

// Search knowledge atoms
let knowledge = try await repository.search(
    query: "machine learning",
    types: [.research, .connection, .idea]
)

// Create new insight
let insight = try await repository.create(
    type: .livingInsight,
    title: "HRV ↔ Focus Score",
    body: "Higher morning HRV correlates with better afternoon focus",
    metadata: insightMetadataJSON
)
```

---

## 5. Voice/LLM Unified Integration

The Sanctuary fully integrates with the VoiceLLMUnified 3-tier architecture, enabling voice control of all dashboard interactions.

### Sanctuary Voice Actions (FunctionName Enum)

```swift
// AI/MicroBrain/FunctionCall.swift

enum FunctionName: String, CaseIterable {
    // ... existing functions ...

    // MARK: - Sanctuary Dimension Navigation
    case openCognitiveDimension = "open_cognitive_dimension"
    case openCreativeDimension = "open_creative_dimension"
    case openPhysiologicalDimension = "open_physiological_dimension"
    case openBehavioralDimension = "open_behavioral_dimension"
    case openKnowledgeDimension = "open_knowledge_dimension"
    case openReflectionDimension = "open_reflection_dimension"
    case returnToSanctuaryHome = "return_to_sanctuary_home"

    // MARK: - Knowledge Graph
    case zoomKnowledgeGraph = "zoom_knowledge_graph"
    case focusKnowledgeNode = "focus_knowledge_node"
    case searchKnowledgeNodes = "search_knowledge_nodes"
    case showClusterDetail = "show_cluster_detail"

    // MARK: - Sanctuary Panels
    case toggleTimelineView = "toggle_timeline_view"
    case showCorrelationInsights = "show_correlation_insights"
    case showPredictionsPanel = "show_predictions_panel"
    case expandMetricDetail = "expand_metric_detail"

    // MARK: - Quick Actions
    case quickLogMood = "quick_log_mood"
    case startMeditationSession = "start_meditation_session"
    case openJournalEntry = "open_journal_entry"
}
```

### Voice Command Flow

```
User: "Open cognitive dimension"
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│ TIER 0: PatternMatcher (<50ms)                              │
│ Pattern: "open (cognitive|creative|...) dimension"          │
│ Result: Matched! → open_cognitive_dimension                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ ToolExecutor.execute()                                      │
│ case .openCognitiveDimension:                               │
│     return executeSanctuaryNavigation(.cognitive)           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ NotificationCenter.post(.sanctuaryDimensionRequested)       │
│ userInfo: ["dimension": "cognitive"]                        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ SanctuaryView receives notification                         │
│ → Play dimension transition sound                           │
│ → Trigger haptic feedback                                   │
│ → Animate to Cognitive dimension view                       │
└─────────────────────────────────────────────────────────────┘
```

### Notification Names

```swift
// AI/MicroBrain/ToolExecutor.swift

extension Notification.Name {
    // Sanctuary Dimension Navigation
    static let sanctuaryDimensionRequested = Notification.Name("sanctuaryDimensionRequested")
    static let sanctuaryHomeRequested = Notification.Name("sanctuaryHomeRequested")

    // Knowledge Graph
    static let knowledgeGraphZoomRequested = Notification.Name("knowledgeGraphZoomRequested")
    static let knowledgeNodeFocusRequested = Notification.Name("knowledgeNodeFocusRequested")
    static let knowledgeNodeSearchRequested = Notification.Name("knowledgeNodeSearchRequested")
    static let knowledgeClusterDetailRequested = Notification.Name("knowledgeClusterDetailRequested")

    // Sanctuary Panels
    static let sanctuaryPanelToggleRequested = Notification.Name("sanctuaryPanelToggleRequested")

    // Reflection Quick Actions
    static let moodLogRequested = Notification.Name("moodLogRequested")
    static let meditationSessionRequested = Notification.Name("meditationSessionRequested")
    static let journalEntryRequested = Notification.Name("journalEntryRequested")
}
```

### ToolExecutor Implementation

```swift
// AI/MicroBrain/ToolExecutor.swift

private func executeSanctuaryNavigation(_ dimension: SanctuaryDimension) async throws -> ExecutionResult {
    await MainActor.run {
        NotificationCenter.default.post(
            name: .sanctuaryDimensionRequested,
            object: nil,
            userInfo: ["dimension": dimension.rawValue]
        )
    }

    logger.info("Sanctuary dimension opened: \(dimension.rawValue)")
    return .sanctuaryDimensionOpened(dimension)
}

private func executeQuickLogMood(_ call: FunctionCall) async throws -> ExecutionResult {
    guard let emoji = call.string("emoji") ?? call.string("mood") else {
        throw MicroBrainError.invalidParameters("quick_log_mood requires emoji or mood")
    }

    let valence = call.double("valence") ?? moodValence(for: emoji)
    let energy = call.double("energy") ?? moodEnergy(for: emoji)

    await MainActor.run {
        NotificationCenter.default.post(
            name: .moodLogRequested,
            object: nil,
            userInfo: [
                "emoji": emoji,
                "valence": valence,
                "energy": energy
            ]
        )
    }

    return .moodLogged(emoji: emoji, valence: valence, energy: energy)
}
```

---

## 6. Living Intelligence Engine

The Living Intelligence Engine is what makes the Sanctuary feel "telepathic". Instead of regenerating insights from scratch, it maintains a living ecosystem of insights that evolve over time.

### Insight Lifecycle States

```swift
public enum InsightLifecycleState: String, Codable, Sendable {
    case fresh          // Just discovered (< 24h), show "NEW" badge
    case validated      // Confirmed by new data, high confidence
    case established    // Proven pattern (5+ validations), trustworthy
    case stale          // No validation in 7+ days, may be outdated
    case decaying       // Actively losing confidence, will be removed
    case removed        // Marked for cleanup (not displayed)
}
```

### Lifecycle Visualization

```
Time →
───────────────────────────────────────────────────────────────────►

Day 1:       ★ FRESH (NEW badge)
             │
Day 2:       │ New data confirms → VALIDATED
             │
Day 5:       │ 5th confirmation → ESTABLISHED
             │
Day 12:      │ No new data for 7 days → STALE (warning shown)
             │
Day 19:      │ Still no data → DECAYING (confidence -2%/day)
             │
Day 40:      │ Confidence < 20% → REMOVED (if not pinned)
             ▼
```

### LivingInsight Structure

```swift
public struct LivingInsight: Codable, Sendable, Identifiable {
    public let id: String
    public let sourceCorrelation: String?    // CausalityEngine correlation UUID
    public let claudeInsightId: String?      // Claude-generated insight ID

    // Core content
    public var type: InsightType             // correlation, prediction, warning, etc.
    public var title: String
    public var description: String
    public var mechanism: String?            // WHY this correlation exists
    public var action: String?               // What user can do

    // Lifecycle
    public var lifecycleState: InsightLifecycleState
    public var createdAt: Date
    public var lastValidatedAt: Date
    public var validationCount: Int          // Times confirmed by new data
    public var confidenceScore: Double       // 0-1, computed from multiple factors

    // Statistical backing
    public var pearsonR: Double?
    public var effectSize: Double?
    public var sampleSize: Int?

    // Dimensions involved
    public var dimensions: [LevelDimension]
    public var variables: [String]           // Metric names

    // Display metadata
    public var isPinned: Bool                // User pinned, never auto-remove
    public var isDismissed: Bool             // User dismissed, don't show again
    public var viewCount: Int
}
```

### Sync Cycle (Every 12 Hours)

```swift
// AI/BigBrain/LivingIntelligenceEngine.swift

public func runSync(force: Bool = false) async {
    // Step 1: Determine data cutoff
    let dataCutoff = lastSyncState?.lastDataCutoff ?? Date.distantPast

    // Step 2: Count new atoms
    let newAtomCount = try await countNewAtoms(since: dataCutoff)

    guard newAtomCount > 0 || force else {
        return  // No new data, skip sync
    }

    // Step 3: Run CausalityEngine (always, it's fast and local)
    let causalityInsights = try await runCausalityAnalysis()

    // Step 4: Decide if we should call Claude
    let hoursSinceClaude = lastClaudeCallDate.map {
        Date().timeIntervalSince($0) / 3600
    } ?? 24

    if SyncState.shouldRunClaudeAnalysis(
        newAtomCount: newAtomCount,
        hoursSinceLastClaudeCall: hoursSinceClaude
    ) || force {
        claudeInsights = try await orchestrator.runAnalysis(...)
    }

    // Step 5: Intelligent merge
    await mergeInsights(causalityInsights, claudeInsights)

    // Step 6: Update lifecycle states
    await updateLifecycleStates()

    // Step 7: Save sync state
    await saveSyncState(...)
}
```

### Intelligent Merge Algorithm

```swift
private func mergeInsights(
    causalityInsights: [CorrelationInsight],
    claudeInsights: [ClaudeCorrelationOutput]
) async -> (validated: Int, new: Int, removed: Int) {

    // Create lookup for existing insights by variable combination
    var existingByVariables: [Set<String>: LivingInsight] = [:]

    for causalityInsight in causalityInsights {
        let variables = Set([causalityInsight.sourceMetric, causalityInsight.targetMetric])

        if var existing = existingByVariables[variables] {
            // VALIDATE: This insight is confirmed by new data
            existing.validationCount += 1
            existing.lastValidatedAt = Date()
            existing.confidenceScore = min(1.0, existing.confidenceScore + 0.05)

            // Update lifecycle
            if existing.validationCount >= 5 {
                existing.lifecycleState = .established
            }

            validated += 1
        } else {
            // NEW: This is a genuinely new insight
            let newInsight = LivingInsight(...)
            existingByVariables[variables] = newInsight
            newCount += 1
        }
    }

    // Claude enhances existing insights with richer context
    for claudeInsight in claudeInsights {
        if var existing = existingByVariables[Set(claudeInsight.variables)] {
            existing.mechanism = claudeInsight.mechanism
            existing.action = claudeInsight.action
            // Claude's deeper analysis enriches local discovery
        }
    }
}
```

---

## 7. Data Flow Architecture

### SanctuaryDataProvider

The central hub for all Sanctuary data access.

```swift
// Data/Models/Sanctuary/SanctuaryDataProvider.swift

@MainActor
public final class SanctuaryDataProvider: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var state: SanctuaryState?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var livingInsights: [LivingInsight] = []
    @Published public private(set) var hasNewInsights: Bool = false

    // MARK: - Dependencies

    private let database: any DatabaseWriter
    private let causalityEngine: CausalityEngine
    private let livingIntelligence: LivingIntelligenceEngine

    // MARK: - Cache Configuration

    // Cache TTLs
    static let dimensionLevelsTTL: TimeInterval = 5 * 60      // 5 minutes
    static let correlationInsightsTTL: TimeInterval = 24 * 60 * 60  // 24 hours
    static let liveMetricsTTL: TimeInterval = 30              // 30 seconds
    static let trendsTTL: TimeInterval = 60 * 60              // 1 hour
}
```

### SanctuaryState Structure

```swift
public struct SanctuaryState: Sendable {
    public let timestamp: Date
    public let cosmoIndex: CosmoIndexState        // Level, XP, Rank
    public let dimensions: [SanctuaryDimensionState]  // All 6 dimensions
    public let topInsights: [CorrelationInsight]  // Statistical insights
    public let liveMetrics: LiveMetrics           // Real-time data
    public let trends: TrendData                  // Weekly history

    public var overallHealth: Double {
        let avgNelo = dimensions.map { Double($0.nelo) }.reduce(0, +) / 6
        return min(100, avgNelo / 20)  // NELO ~2000 = 100% health
    }
}
```

### Stream Classes

```swift
// Reactive streams for UI updates

/// Dimension state changes
@MainActor
public final class DimensionStateStream: ObservableObject {
    @Published public private(set) var dimensions: [SanctuaryDimensionState] = []

    public func state(for dimension: LevelDimension) -> SanctuaryDimensionState? {
        dimensions.first { $0.dimension == dimension }
    }
}

/// Living insights with lifecycle awareness
@MainActor
public final class LivingInsightStream: ObservableObject {
    @Published public private(set) var insights: [LivingInsight] = []
    @Published public private(set) var featuredInsight: LivingInsight?
    @Published public private(set) var hasNewInsights: Bool = false

    public var freshInsights: [LivingInsight] {
        insights.filter { $0.lifecycleState == .fresh }
    }

    public var crossDimensionalInsights: [LivingInsight] {
        insights.filter { $0.dimensions.count >= 2 }
    }
}

/// Unified access to all streams
@MainActor
public final class SanctuaryStreams: ObservableObject {
    public let dimensionStream: DimensionStateStream
    public let insightStream: InsightStream
    public let livingInsightStream: LivingInsightStream

    public func startAll() async {
        provider.startLiveUpdates()
        await provider.startLivingIntelligence()
    }
}
```

---

## 8. UI Component Architecture

### Component Hierarchy

```
SanctuaryView (Main Container)
├── SanctuaryBackgroundView
│   ├── Void gradient
│   ├── Aurora Metal shader
│   └── Particle field
│
├── SanctuaryHeaderView
│   ├── Cosmo Index badge
│   ├── Live indicator
│   └── Back navigation
│
├── Constellation Zone (480pt)
│   ├── Connection lines (Metal/Canvas)
│   ├── Dimension orbs (6x DimensionOrbView)
│   └── SanctuaryHeroOrb (center)
│       ├── XP progress ring
│       ├── Level number
│       └── HRV indicator
│
├── InsightStream (140pt)
│   ├── InsightCard carousel
│   └── New insight badges
│
└── Dimension Detail Views
    ├── CognitiveDimensionView
    ├── CreativeDimensionView
    ├── PhysiologicalDimensionView
    ├── BehavioralDimensionView
    ├── KnowledgeDimensionView
    └── ReflectionDimensionView
```

### SanctuaryView Integration

```swift
// UI/Sanctuary/SanctuaryView.swift

public struct SanctuaryView: View {
    @StateObject private var dataProvider = SanctuaryDataProvider()
    @StateObject private var livingInsightStream: LivingInsightStream
    @StateObject private var choreographer = SanctuaryAnimationChoreographer()
    @StateObject private var transitionManager = SanctuaryTransitionManager()

    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            SanctuaryTransitionBackground(manager: transitionManager)

            // Aurora overlay (Metal shader)
            if useMetalRendering {
                SanctuaryAuroraMetalView(...)
            }

            VStack {
                SanctuaryHeaderView(...)
                dimensionOrbsView
                insightStreamView
            }
        }
        .onAppear {
            Task {
                await dataProvider.startLivingIntelligence()
                try await SanctuarySoundscape.shared.start()
                await SanctuarySoundscape.shared.startAmbient()
            }
            setupVoiceNotifications()
        }
    }

    private func setupVoiceNotifications() {
        // Listen for voice-triggered navigation
        NotificationCenter.default.publisher(for: .sanctuaryDimensionRequested)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                if let dimension = /* extract dimension */ {
                    SanctuaryHaptics.shared.dimensionTransition()
                    Task {
                        await SanctuarySoundscape.shared.transitionToDimension(dimension)
                        await transitionManager.transitionToDimension(dimension, ...)
                    }
                }
            }
            .store(in: &cancellables)
    }
}
```

---

## 9. Sound & Haptics System

### SanctuarySoundscape

```swift
// UI/Sanctuary/Systems/SanctuarySoundscape.swift

public actor SanctuarySoundscape {
    public static let shared = SanctuarySoundscape()

    // Sound Categories

    /// Ambient (continuous, layered)
    public enum AmbientLayer: String, CaseIterable {
        case sanctuaryBase = "sanctuary_ambient"
        case dimensionCognitive = "dimension_cognitive"
        case dimensionCreative = "dimension_creative"
        case dimensionPhysiological = "dimension_physiological"
        case dimensionBehavioral = "dimension_behavioral"
        case dimensionKnowledge = "dimension_knowledge"
        case dimensionReflection = "dimension_reflection"
    }

    /// Transitions (event-triggered)
    public enum TransitionSound: String, CaseIterable {
        case dimensionEnter = "dimension_enter"
        case dimensionExit = "dimension_exit"
        case insightReveal = "insight_reveal"
        case grailDiscovery = "grail_discovery"
        case panelOpen = "panel_open"
    }

    /// Feedback (micro-interactions)
    public enum FeedbackSound: String, CaseIterable {
        case nodeTap = "node_tap"
        case xpTick = "xp_tick"
        case levelUpBuild = "level_up_build"
        case levelUpBurst = "level_up_burst"
    }

    // Key Methods

    public func transitionToDimension(_ dimension: SanctuaryDimension) async {
        // Fade out previous dimension layer
        // Fade in new dimension layer
        // Play transition sound
    }

    public func updateCosmoIndex(_ index: Double) async {
        // Modulate ambient based on user's overall state
    }
}
```

### SanctuaryHaptics

```swift
// UI/Sanctuary/Systems/SanctuaryHaptics.swift

public final class SanctuaryHaptics {
    public static let shared = SanctuaryHaptics()

    // Haptic Patterns

    public func nodeSelect()           // UIImpactFeedbackGenerator(.light)
    public func panelOpen()            // UIImpactFeedbackGenerator(.medium)
    public func insightReveal()        // UINotificationFeedbackGenerator(.success)
    public func xpGain(amount: Int)    // Custom pattern (3 quick taps)
    public func levelUp()              // Heavy + success
    public func streakAlert()          // UINotificationFeedbackGenerator(.warning)
    public func grailDiscovery() async // Core Haptics custom pattern

    // Level-Up Ceremony (2500ms)
    public func levelUpCeremony() async {
        // Phase 1: Build-up (escalating taps)
        // Phase 2: Flash (heavy impact)
        // Phase 3: Celebration (success + medium impacts)
        // Phase 4: Settle (soft fade out)
    }
}
```

### Usage in Views

```swift
// SwiftUI extensions for easy haptic feedback

public extension View {
    func hapticOnTap(_ pattern: SanctuaryHapticPattern = .nodeSelect) -> some View {
        self.onTapGesture {
            Task { await pattern.play() }
        }
    }
}
```

---

## 10. Level System Integration

### Cosmo Index Display

```swift
public struct CosmoIndexState: Codable, Sendable {
    public let level: Int              // 1-100+
    public let currentXP: Int64        // XP within current level
    public let xpToNextLevel: Int64    // XP needed for next level
    public let xpProgress: Double      // 0-1
    public let totalXP: Int64          // Lifetime XP
    public let rank: String            // "Novice", "Adept", "Master", etc.
}
```

### Dimension State Display

```swift
public struct SanctuaryDimensionState: Codable, Sendable {
    public let dimension: LevelDimension
    public let level: Int
    public let nelo: Int               // 800-2400 (can rise/fall)
    public let currentXP: Int64
    public let xpProgress: Double
    public let streak: Int
    public let lastActivity: Date?
    public let trend: Trend            // up, down, stable
    public let isActive: Bool          // Activity in last 24h
}
```

### XP Flow to Sanctuary

```
Atom Created (e.g., .deepWorkBlock)
    │
    ▼
DailyCronEngine (midnight)
    │
    ├─── XPCalculationEngine.calculate()
    │    ├── Base XP for atom type
    │    ├── Quality multipliers
    │    └── Streak multipliers (1.0x → 3.0x)
    │
    ├─── Creates .xpEvent Atom
    │    └── Metadata: { dimension, amount, source }
    │
    ├─── Updates CosmoLevelState
    │    ├── Dimension levels
    │    ├── NELO scores
    │    └── Total XP
    │
    └─── Triggers SanctuaryDataProvider refresh
         └── UI updates dimension orbs, hero orb
```

---

## 11. File Reference

### Core Files

| File | Purpose |
|------|---------|
| `UI/Sanctuary/SanctuaryView.swift` | Main dashboard container |
| `UI/Sanctuary/SanctuaryHeroOrb.swift` | Central Cosmo Index visualization |
| `UI/Sanctuary/DimensionOrbView.swift` | Individual dimension orbs |
| `UI/Sanctuary/SanctuaryInsightStream.swift` | Insight card carousel |
| `UI/Sanctuary/Systems/SanctuarySoundscape.swift` | Audio engine |
| `UI/Sanctuary/Systems/SanctuaryHaptics.swift` | Haptic feedback |

### Data Layer

| File | Purpose |
|------|---------|
| `Data/Models/Sanctuary/SanctuaryDataProvider.swift` | Unified data access + caching |
| `Data/Models/Sanctuary/CausalityEngine.swift` | 90-day correlation analysis |
| `AI/BigBrain/LivingIntelligenceEngine.swift` | Lifecycle-managed insights |
| `AI/BigBrain/SanctuaryOrchestrator.swift` | Claude integration |

### Voice Integration

| File | Purpose |
|------|---------|
| `AI/MicroBrain/FunctionCall.swift` | FunctionName enum, ExecutionResult |
| `AI/MicroBrain/ToolExecutor.swift` | Sanctuary action handlers |
| `Voice/Pipeline/VoiceCommandPipeline.swift` | 3-tier orchestration |

### Dimension Views

| File | Purpose |
|------|---------|
| `UI/Sanctuary/Dimensions/Cognitive/CognitiveDimensionView.swift` | Deep work, focus |
| `UI/Sanctuary/Dimensions/Creative/CreativeDimensionView.swift` | Content, publishing |
| `UI/Sanctuary/Dimensions/Physiological/PhysiologicalDimensionView.swift` | Health, sleep |
| `UI/Sanctuary/Dimensions/Behavioral/BehavioralDimensionView.swift` | Routines, habits |
| `UI/Sanctuary/Dimensions/Knowledge/KnowledgeDimensionView.swift` | Research, learning |
| `UI/Sanctuary/Dimensions/Reflection/ReflectionDimensionView.swift` | Journaling, mood |

---

## 12. Integration Patterns

### Pattern 1: Adding a New Voice Action

```swift
// 1. Add to FunctionName enum (FunctionCall.swift)
case newSanctuaryAction = "new_sanctuary_action"

// 2. Add to ExecutionResult enum
case newActionResult(SomeType)

// 3. Add case in ToolExecutor.execute()
case .newSanctuaryAction:
    return try await executeNewAction(call)

// 4. Implement execution method
private func executeNewAction(_ call: FunctionCall) async throws -> ExecutionResult {
    await MainActor.run {
        NotificationCenter.default.post(
            name: .newActionRequested,
            object: nil,
            userInfo: [...]
        )
    }
    return .newActionResult(...)
}

// 5. Add notification name
static let newActionRequested = Notification.Name("newActionRequested")

// 6. Subscribe in SanctuaryView.setupVoiceNotifications()
NotificationCenter.default.publisher(for: .newActionRequested)
    .sink { notification in
        // Handle action
    }
    .store(in: &cancellables)
```

### Pattern 2: Adding a New Insight Type

```swift
// 1. Add to InsightType enum (LivingIntelligenceEngine.swift)
public enum InsightType: String, Codable, Sendable {
    // ... existing types ...
    case newType
}

// 2. Map in InsightCardModel.fromLiving()
case .newType: return .insight  // or appropriate card type

// 3. Handle in CausalityEngine or Claude prompts
```

### Pattern 3: Adding a New Dimension Panel

```swift
// 1. Create data model (e.g., NewMetricData.swift)
public struct NewMetricData: Codable, Sendable { ... }

// 2. Create panel view (e.g., NewMetricPanel.swift)
public struct NewMetricPanel: View { ... }

// 3. Add to dimension view
// e.g., CognitiveDimensionView.swift
NewMetricPanel(data: viewModel.data.newMetric)

// 4. Add to dimension data model
public struct CognitiveDimensionData {
    // ... existing ...
    public let newMetric: NewMetricData
}
```

---

## 13. Future Considerations

### Planned Enhancements

1. **Particle System** (GPU-instanced Metal)
   - 50,000+ particles at 120fps
   - XP particles, flow visualization, level-up bursts

2. **Level-Up Ceremony**
   - Full 2500ms animation sequence
   - Screen dim, number transform, particle burst

3. **Grail Insights**
   - Cross-dimensional breakthrough discoveries
   - Special UI treatment, celebratory feedback

4. **Predictive Intelligence**
   - Forward-looking correlations
   - "If you do X, expect Y tomorrow"

5. **Contextual Recommendations**
   - Time-aware suggestions
   - "Optimal deep work window detected"

### Performance Considerations

- **Metal Rendering**: Enable for devices with A12+ chips
- **Insight Caching**: 24-hour TTL prevents redundant analysis
- **Delta Sync**: Only analyze new data, never recompute
- **Background Processing**: Intelligence sync runs in background

### Extensibility Points

- **Custom Dimensions**: Add new dimensions by extending `LevelDimension`
- **Custom Atom Types**: Add new atom types for new data sources
- **Custom Correlations**: Extend CausalityEngine with new analysis types
- **Custom Sounds**: Add new ambient/transition sounds to soundscape

---

## Appendix: Quick Reference

### Key Singletons

```swift
AtomRepository.shared              // All data access
LivingIntelligenceEngine.shared    // Insight lifecycle
SanctuarySoundscape.shared         // Audio engine (actor)
SanctuaryHaptics.shared            // Haptic feedback
```

### Key Published Properties

```swift
// SanctuaryDataProvider
@Published var state: SanctuaryState?
@Published var livingInsights: [LivingInsight]
@Published var hasNewInsights: Bool

// LivingIntelligenceEngine
@Published var insights: [LivingInsight]
@Published var isSyncing: Bool
@Published var hasNewInsights: Bool
```

### Key Notifications

```swift
.sanctuaryDimensionRequested   // userInfo: ["dimension": String]
.sanctuaryHomeRequested        // no userInfo
.sanctuaryPanelToggleRequested // userInfo: ["panel": String, "show": Bool]
.moodLogRequested              // userInfo: ["emoji", "valence", "energy"]
```

---

*This documentation is maintained alongside the codebase. For implementation details, refer to the source files listed in Section 11.*
