# Sanctuary Intelligence Integration Plan

## Architecture Overview: The Living Sanctuary

```
                    ┌─────────────────────────────────────┐
                    │         SANCTUARY UI LAYER          │
                    │  (All 6 Dimension Views + Home)     │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────▼───────────────────┐
                    │      SANCTUARY INTELLIGENCE HUB     │
                    │   Orchestrates Data + LLM Layers    │
                    └──────┬────────────────────┬─────────┘
                           │                    │
           ┌───────────────▼──────┐   ┌────────▼─────────────┐
           │   FunctionGemma 270M │   │    Claude API (Big   │
           │   (Micro-Brain)      │   │    Brain via OpenRouter)
           │                      │   │                      │
           │  • Node selection    │   │  • Correlation analysis│
           │  • Graph interactions│   │  • Grail extraction   │
           │  • Panel toggling    │   │  • Semantic clustering │
           │  • Zoom/search       │   │  • Cross-dimension     │
           │  • Timeline nav      │   │    pattern discovery   │
           │                      │   │  • Journaling depth    │
           │  <300ms, local       │   │  • Affective state     │
           │  deterministic       │   │                        │
           └──────────────────────┘   │  2-5s, cloud           │
                                      │  creative reasoning    │
                                      └────────────────────────┘
                                                │
                    ┌───────────────────────────▼──────────────┐
                    │        INTELLIGENT CACHE LAYER           │
                    │   • Differential Updates (12hr cycle)    │
                    │   • Staleness Detection                  │
                    │   • Relevance Scoring                    │
                    │   • Mutation Detection                   │
                    └───────────────────────────────────────────┘
```

---

## Phase 9: Polish (Sound, Particles, Level-ups, Haptics)

### 9.1 Sound Design System

**File: `UI/Sanctuary/Systems/SanctuarySoundscape.swift`**

```
Sound Categories:
├── Ambient (continuous, layered)
│   ├── sanctuary_ambient.wav      - Base drone, evolves with Cosmo Index
│   ├── dimension_cognitive.wav    - Neural synth undertones
│   ├── dimension_creative.wav     - Artistic, flowing
│   ├── dimension_physiological.wav- Heartbeat-aligned
│   ├── dimension_behavioral.wav   - Rhythmic, disciplined
│   ├── dimension_knowledge.wav    - Ethereal, vast
│   └── dimension_reflection.wav   - Meditative, calm
│
├── Transitions (event-triggered)
│   ├── dimension_enter.wav        - Whoosh + dimension tone
│   ├── dimension_exit.wav         - Reverse whoosh
│   ├── insight_reveal.wav         - Soft chime cascade
│   ├── grail_discovery.wav        - Golden bell + sparkle
│   └── panel_open.wav             - Glass slide
│
├── Feedback (micro-interactions)
│   ├── node_tap.wav               - Subtle click
│   ├── node_hover.wav             - Soft resonance
│   ├── xp_tick.wav                - Coin-like ping (pitched by amount)
│   ├── level_up_build.wav         - Rising anticipation
│   └── level_up_burst.wav         - Triumphant fanfare
│
└── Alerts
    ├── correlation_found.wav      - Discovery tone
    ├── streak_endangered.wav      - Warning pulse
    └── optimal_window.wav         - Gentle reminder
```

### 9.2 Particle System

**File: `UI/Sanctuary/Systems/SanctuaryParticleEngine.swift`**

```swift
// GPU-instanced particle system using Metal
// Target: 50,000+ particles at 120fps

Particle Types:
├── XPParticles         - Gold sparkles on achievements
├── FlowParticles       - Cognitive load visualization
├── ConstellationDust   - Ambient knowledge graph particles
├── LevelUpBurst        - Celebration explosion (500 particles)
├── InsightTrail        - Follows correlation connections
└── AmbientField        - Background 20-30 subtle particles
```

### 9.3 Level-Up Ceremony

**File: `UI/Sanctuary/Systems/LevelUpCeremony.swift`**

```
Level Up Sequence (2500ms total):
├── 0-500ms: Build-up
│   • Screen dims slightly (0.9 opacity)
│   • Dimension rings accelerate spin
│   • Rising tone plays
│   • Particles begin gathering
│
├── 500-800ms: Flash
│   • Brief white flash (200ms)
│   • Number transforms with scale bounce
│   • Haptic: .heavy
│
├── 800-1800ms: Celebration
│   • "LEVEL UP" text scales in
│   • Particle burst (500 gold particles)
│   • Dimension color pulse
│   • Fanfare plays
│
└── 1800-2500ms: Settle
    • Elements return to normal
    • New level number settles
    • Haptic: .success
```

### 9.4 Haptic Feedback

**File: `UI/Sanctuary/Systems/SanctuaryHaptics.swift`**

```swift
Haptic Patterns:
├── .nodeSelect      - UIImpactFeedbackGenerator(.light)
├── .panelOpen       - UIImpactFeedbackGenerator(.medium)
├── .insightReveal   - UINotificationFeedbackGenerator(.success)
├── .xpGain          - Custom pattern (3 quick taps)
├── .levelUp         - UINotificationFeedbackGenerator(.success) + .heavy
├── .streakAlert     - UINotificationFeedbackGenerator(.warning)
└── .grailDiscovery  - Custom celebratory pattern
```

---

## Phase 10: Neural Engine & Intelligent Refresh

### 10.1 Sanctuary Intelligence Hub

**File: `AI/Sanctuary/SanctuaryIntelligenceHub.swift`**

The central orchestrator that:
1. Manages the 12-hour intelligent refresh cycle
2. Detects what data has actually changed
3. Routes to Claude only when meaningful updates exist
4. Caches and versions all insights

```swift
public actor SanctuaryIntelligenceHub {

    // MARK: - Refresh Strategy

    /// Determines what needs updating
    struct RefreshDecision {
        let shouldRefreshCorrelations: Bool
        let shouldRefreshGrails: Bool
        let shouldRefreshPredictions: Bool
        let changedDimensions: Set<LevelDimension>
        let mutationScore: Double  // 0-1, how much changed
        let reason: String
    }

    /// Smart refresh - only updates what's stale or changed
    func performIntelligentRefresh() async throws {
        let decision = await analyzeWhatChanged()

        // If mutation score < 0.1, skip Claude entirely
        if decision.mutationScore < 0.1 {
            // Just refresh live metrics, no AI calls
            return
        }

        // Route to Claude for changed dimensions only
        if decision.shouldRefreshCorrelations {
            await refreshCorrelations(for: decision.changedDimensions)
        }

        // etc.
    }
}
```

### 10.2 Mutation Detection System

**File: `AI/Sanctuary/SanctuaryMutationDetector.swift`**

Tracks what's actually changed to avoid unnecessary API calls:

```swift
public actor SanctuaryMutationDetector {

    // Fingerprints of last known state
    private var dimensionFingerprints: [LevelDimension: DataFingerprint] = [:]
    private var lastCorrelationHash: String?
    private var lastGrailCount: Int = 0

    struct DataFingerprint: Codable {
        let atomCount: Int
        let latestAtomTimestamp: Date
        let xpTotal: Int64
        let level: Int
        let neloScore: Int
        let contentHash: String  // Hash of key content
    }

    /// Returns mutation score 0-1 (0 = nothing changed, 1 = everything changed)
    func detectMutations(since lastRefresh: Date) async -> MutationReport {
        var changedDimensions: Set<LevelDimension> = []
        var totalMutationScore: Double = 0

        for dimension in LevelDimension.allCases {
            let currentFingerprint = await computeFingerprint(for: dimension)

            if let previous = dimensionFingerprints[dimension] {
                let similarity = compareFingerprints(previous, currentFingerprint)
                if similarity < 0.95 {  // 5% change threshold
                    changedDimensions.insert(dimension)
                    totalMutationScore += (1 - similarity)
                }
            }

            dimensionFingerprints[dimension] = currentFingerprint
        }

        return MutationReport(
            changedDimensions: changedDimensions,
            mutationScore: min(1, totalMutationScore / 6),
            timestamp: Date()
        )
    }
}
```

### 10.3 Claude Sanctuary Prompts

**File: `AI/Sanctuary/SanctuaryClaudePrompts.swift`**

Specialized prompts for each Sanctuary analysis task:

```swift
enum SanctuaryClaudePrompt {

    /// Cross-dimension correlation analysis
    static func correlationAnalysis(context: CorrelationContext) -> String {
        """
        You are the Sanctuary Intelligence of CosmoOS, analyzing cross-dimensional correlations.

        USER DATA (Last 7 Days):
        \(context.formattedData)

        TASK: Identify 3-5 meaningful correlations between dimensions.

        For each correlation:
        1. Source dimension + metric
        2. Target dimension + metric
        3. Correlation strength (0-1)
        4. Causal hypothesis
        5. Actionable insight

        Return as JSON array. Be specific and grounded in the data.
        """
    }

    /// Grail Insight extraction from journal entries
    static func grailExtraction(journals: [JournalEntrySummary]) -> String {
        """
        You are mining for GRAIL INSIGHTS - breakthrough moments of self-understanding.

        JOURNAL ENTRIES:
        \(journals.map { "[\($0.date)] \($0.content)" }.joined(separator: "\n\n"))

        A Grail Insight is:
        - A non-obvious realization about self/patterns
        - Cross-dimensional (connects behavior, emotion, cognition, etc.)
        - Actionable or perspective-shifting

        Extract 0-3 Grail Insights. Quality over quantity.
        For each: insight text, journey (steps that led there), connected dimensions.

        Return as JSON. If nothing qualifies, return empty array.
        """
    }

    /// Semantic density computation for Knowledge dimension
    static func semanticDensity(nodes: [KnowledgeNodeSummary]) -> String {
        """
        Analyze the semantic density of this knowledge graph.

        NODES (\(nodes.count) total):
        \(nodes.prefix(50).map { "• \($0.title) [\($0.type)] - \($0.connectionCount) connections" }.joined(separator: "\n"))

        Compute:
        1. Overall semantic density (0-1)
        2. Top 3 emerging clusters
        3. Predicted connections (what should link?)
        4. Knowledge gaps (what's missing?)

        Return as structured JSON.
        """
    }
}
```

### 10.4 FunctionGemma Sanctuary Actions

**File: `AI/Sanctuary/SanctuaryFunctionRouter.swift`**

All instant, local actions handled by FunctionGemma:

```swift
// Available Sanctuary voice commands → FunctionGemma functions

enum SanctuaryVoiceAction: String, CaseIterable {
    // Navigation
    case openCognitive = "open_cognitive_dimension"
    case openCreative = "open_creative_dimension"
    case openPhysiological = "open_physiological_dimension"
    case openBehavioral = "open_behavioral_dimension"
    case openKnowledge = "open_knowledge_dimension"
    case openReflection = "open_reflection_dimension"
    case goHome = "return_to_sanctuary_home"

    // Knowledge Graph
    case zoomIn = "zoom_knowledge_graph_in"
    case zoomOut = "zoom_knowledge_graph_out"
    case focusNode = "focus_knowledge_node"
    case searchNodes = "search_knowledge_nodes"
    case showCluster = "show_cluster_detail"

    // Panels
    case toggleTimeline = "toggle_timeline_view"
    case showInsights = "show_correlation_insights"
    case showPredictions = "show_predictions_panel"
    case expandMetric = "expand_metric_detail"

    // Quick Actions
    case logMood = "quick_log_mood"
    case startMeditation = "start_meditation_session"
    case logJournal = "open_journal_entry"
}

/// Route voice command to local action (no API needed)
func routeSanctuaryCommand(_ transcript: String) async throws -> SanctuaryAction {
    let functionCall = try await FunctionGemmaEngine.shared.generateFunctionCall(
        transcript: transcript,
        context: VoiceContext(section: .sanctuary, currentDate: Date())
    )

    return SanctuaryAction(from: functionCall)
}
```

### 10.5 Intelligent Refresh Scheduler

**File: `AI/Sanctuary/SanctuaryRefreshScheduler.swift`**

```swift
public actor SanctuaryRefreshScheduler {

    private let refreshInterval: TimeInterval = 12 * 60 * 60  // 12 hours
    private var lastFullRefresh: Date?
    private var lastQuickRefresh: Date?

    /// Schedule strategy
    enum RefreshType {
        case full      // Claude-powered, all dimensions
        case quick     // Local only, live metrics
        case delta     // Claude-powered, changed dimensions only
        case skip      // Nothing changed
    }

    func determineRefreshType() async -> RefreshType {
        let timeSinceFullRefresh = Date().timeIntervalSince(lastFullRefresh ?? .distantPast)
        let mutations = await SanctuaryMutationDetector.shared.detectMutations(
            since: lastQuickRefresh ?? .distantPast
        )

        // Force full refresh after 12 hours
        if timeSinceFullRefresh > refreshInterval {
            return .full
        }

        // Delta refresh if significant changes
        if mutations.mutationScore > 0.15 {
            return .delta
        }

        // Quick refresh for live data
        if mutations.mutationScore > 0.05 {
            return .quick
        }

        // Skip if nothing meaningful changed
        return .skip
    }

    /// Background refresh task
    func startBackgroundRefresh() {
        Task {
            while true {
                let refreshType = await determineRefreshType()

                switch refreshType {
                case .full:
                    await SanctuaryIntelligenceHub.shared.performFullRefresh()
                    lastFullRefresh = Date()
                case .delta:
                    await SanctuaryIntelligenceHub.shared.performDeltaRefresh()
                case .quick:
                    await SanctuaryIntelligenceHub.shared.refreshLiveMetrics()
                case .skip:
                    break
                }

                lastQuickRefresh = Date()

                // Check every 30 minutes
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }
}
```

### 10.6 Insight Versioning & Persistence

**File: `Data/Models/Sanctuary/SanctuaryInsightStore.swift`**

```swift
/// Persists Claude-generated insights with versioning
public struct SanctuaryInsightStore {

    /// Stored insight with metadata
    struct VersionedInsight: Codable {
        let uuid: UUID
        let type: InsightType
        let content: String
        let generatedAt: Date
        let basedOnDataHash: String  // Hash of input data
        let confidence: Double
        let expiresAt: Date?
        let isStale: Bool
    }

    enum InsightType: String, Codable {
        case correlation
        case grail
        case prediction
        case clusterAnalysis
        case emotionalTrajectory
    }

    /// Only regenerate if data changed significantly
    func shouldRegenerate(type: InsightType, currentDataHash: String) -> Bool {
        guard let existing = fetch(type: type) else { return true }

        if existing.basedOnDataHash != currentDataHash {
            return true  // Data changed
        }

        if let expires = existing.expiresAt, Date() > expires {
            return true  // Expired
        }

        return false  // Still valid
    }
}
```

---

## Implementation Order

### Phase 9: Polish (4 files)
1. `SanctuarySoundscape.swift` - Audio engine + asset loading
2. `SanctuaryParticleEngine.swift` - GPU particle system
3. `LevelUpCeremony.swift` - Level-up animation sequence
4. `SanctuaryHaptics.swift` - Haptic feedback patterns

### Phase 10: Neural Engine (6 files)
1. `SanctuaryMutationDetector.swift` - Change detection
2. `SanctuaryInsightStore.swift` - Insight persistence
3. `SanctuaryClaudePrompts.swift` - Claude prompt templates
4. `SanctuaryFunctionRouter.swift` - FunctionGemma actions
5. `SanctuaryRefreshScheduler.swift` - Intelligent scheduling
6. `SanctuaryIntelligenceHub.swift` - Central orchestrator

---

## Key Design Principles

### 1. The Sanctuary Feels Alive
- Ambient sounds evolve with your Cosmo Index
- Particles respond to real-time data
- Insights appear organically, not on-demand

### 2. Intelligence is Invisible
- Users never wait for "loading insights"
- Claude works in background, 12-hour cycles
- FunctionGemma handles all instant interactions

### 3. Smart Caching = Cost Efficiency
- Only call Claude when data meaningfully changed
- Hash-based staleness detection
- Versioned insights with TTLs

### 4. The Dual-Brain Architecture
```
FunctionGemma (Neurons)     Claude (Cortex)
├── Fast (<300ms)           ├── Deep (2-5s)
├── Local                   ├── Cloud
├── Deterministic           ├── Creative
├── Actions                 └── Understanding
└── Instant feedback
```

This mirrors biological cognition: fast local reflexes (neurons) + slow global reasoning (cortex).
