// CosmoOS/Focus/FocusContextDetector.swift
// Context detection for NodeGraph OS - tracks user focus for contextual search
// Detects current context from view hierarchy and navigation state

import Foundation
import Combine

// MARK: - FocusContextType
/// Classification of user focus context
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

    /// Search boost multiplier for this context
    public var searchBoostMultiplier: Float {
        switch self {
        case .thinkspace, .thread, .idea:
            return 1.2  // Creative contexts get boost
        case .plannerum:
            return 1.1  // Planning context
        case .research, .library:
            return 1.0  // Research/browsing - neutral
        default:
            return 0.8  // Other contexts
        }
    }

    /// Display name for this context
    public var displayName: String {
        switch self {
        case .home: return "Home"
        case .thinkspace: return "Thinkspace"
        case .plannerum: return "Plannerum"
        case .dimension: return "Sanctuary"
        case .research: return "Research"
        case .client: return "Connections"
        case .thread: return "Writing"
        case .idea: return "Idea"
        case .task: return "Task"
        case .project: return "Project"
        case .library: return "Library"
        }
    }
}

// MARK: - FocusContext
/// Represents the current user focus context
public struct FocusContext: Sendable {
    /// The type of context
    public let type: FocusContextType

    /// The currently focused Atom (if any)
    public let focusAtomUUID: String?

    /// The focused atom's type (if known)
    public let focusAtomType: AtomType?

    /// Embedding vector for the focus atom (for similarity search)
    public let focusAtomVector: [Float]?

    /// Current navigation section
    public let navigationSection: String?

    /// Sanctuary dimension (if in dimension context)
    public let dimensionType: String?

    /// Schedule date (if in Plannerum context)
    public let scheduleDate: Date?

    /// When this context was established
    public let timestamp: Date

    /// Extracted concepts/keywords from focus atom
    public let extractedConcepts: [String]

    /// Project ID (if in project context)
    public let projectUUID: String?

    // MARK: - Computed Properties

    /// Whether the context is still valid (within 5 minutes)
    public var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 300  // 5 minutes
    }

    /// Whether the context is stale (between 2-5 minutes)
    public var isStale: Bool {
        let age = Date().timeIntervalSince(timestamp)
        return age >= 120 && age < 300
    }

    /// Cache key for this context
    public var cacheKey: String {
        let typeKey = type.rawValue
        let atomKey = focusAtomUUID ?? "none"
        let atomTypeKey = focusAtomType?.rawValue ?? "none"
        return "\(typeKey):\(atomTypeKey):\(atomKey)"
    }

    // MARK: - Initialization

    public init(
        type: FocusContextType,
        focusAtomUUID: String? = nil,
        focusAtomType: AtomType? = nil,
        focusAtomVector: [Float]? = nil,
        navigationSection: String? = nil,
        dimensionType: String? = nil,
        scheduleDate: Date? = nil,
        extractedConcepts: [String] = [],
        projectUUID: String? = nil
    ) {
        self.type = type
        self.focusAtomUUID = focusAtomUUID
        self.focusAtomType = focusAtomType
        self.focusAtomVector = focusAtomVector
        self.navigationSection = navigationSection
        self.dimensionType = dimensionType
        self.scheduleDate = scheduleDate
        self.timestamp = Date()
        self.extractedConcepts = extractedConcepts
        self.projectUUID = projectUUID
    }

    /// Empty/default context
    public static let empty = FocusContext(type: .home)
}

// MARK: - FocusContextDetector
/// Singleton that tracks and detects user focus context
/// Used by Command-K and other contextual features
@MainActor
public final class FocusContextDetector: ObservableObject {

    // MARK: - Singleton
    public static let shared = FocusContextDetector()

    // MARK: - Published State
    @Published public private(set) var currentContext: FocusContext = .empty
    @Published public private(set) var previousContext: FocusContext?

    // MARK: - Configuration
    /// Debounce interval for context changes
    public let debounceInterval: TimeInterval = 0.3

    // MARK: - Private State
    private var debounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    private init() {
        setupNotificationObservers()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Observe navigation changes
        NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.focusContextChanged)
            .sink { [weak self] notification in
                if let context = notification.userInfo?["context"] as? FocusContext {
                    self?.updateContext(context)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Context Detection

    /// Called by views when they become active
    /// - Parameters:
    ///   - section: The navigation section
    ///   - entityType: The entity type being viewed
    ///   - entityUUID: The entity UUID (if specific)
    ///   - projectUUID: The project UUID (if in project context)
    ///   - dimensionType: The dimension type (if in Sanctuary)
    public func onViewActivated(
        section: String,
        entityType: AtomType? = nil,
        entityUUID: String? = nil,
        projectUUID: String? = nil,
        dimensionType: String? = nil
    ) {
        // Debounce rapid navigation
        debounceTask?.cancel()

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let contextType = detectContextType(
                section: section,
                entityType: entityType
            )

            let context = FocusContext(
                type: contextType,
                focusAtomUUID: entityUUID,
                focusAtomType: entityType,
                focusAtomVector: nil,  // Will be fetched async if needed
                navigationSection: section,
                dimensionType: dimensionType,
                scheduleDate: nil,
                extractedConcepts: [],
                projectUUID: projectUUID
            )

            await MainActor.run {
                self.updateContext(context)
            }

            // Async: Fetch embedding for focus atom
            if let uuid = entityUUID {
                await self.enrichContextWithEmbedding(atomUUID: uuid)
            }
        }
    }

    /// Called when entering Plannerum with a specific date
    public func onPlannerumActivated(date: Date) {
        let context = FocusContext(
            type: .plannerum,
            navigationSection: "plannerum",
            scheduleDate: date
        )
        updateContext(context)
    }

    /// Called when entering a Sanctuary dimension
    public func onDimensionActivated(dimension: String) {
        let context = FocusContext(
            type: .dimension,
            navigationSection: "sanctuary",
            dimensionType: dimension
        )
        updateContext(context)
    }

    /// Called when focus is cleared (e.g., returning to home)
    public func clearFocus() {
        updateContext(.empty)
    }

    // MARK: - Context Type Detection

    private func detectContextType(section: String, entityType: AtomType?) -> FocusContextType {
        // First check entity type for specific contexts
        if let type = entityType {
            switch type {
            case .idea:
                return .idea
            case .task, .scheduleBlock:
                return .task
            case .content, .contentDraft:
                return .thread
            case .research:
                return .research
            case .connection, .clientProfile:
                return .client
            case .project:
                return .project
            default:
                break
            }
        }

        // Fall back to section-based detection
        let lowercased = section.lowercased()
        switch lowercased {
        case "home", "lobby":
            return .home
        case "thinkspace", "canvas":
            return .thinkspace
        case "plannerum", "schedule", "calendar":
            return .plannerum
        case "sanctuary", "dimensions":
            return .dimension
        case "research", "library":
            return .library
        case "connections", "clients":
            return .client
        case "content", "threads":
            return .thread
        case "ideas":
            return .idea
        case "tasks":
            return .task
        case "projects":
            return .project
        default:
            return .home
        }
    }

    // MARK: - Context Updates

    private func updateContext(_ newContext: FocusContext) {
        // Don't update if same context
        if currentContext.cacheKey == newContext.cacheKey {
            return
        }

        previousContext = currentContext
        currentContext = newContext

        // Post notification
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.focusContextChanged,
            object: nil,
            userInfo: ["context": newContext]
        )

        // Prefetch neighborhood for new focus
        if let focusUUID = newContext.focusAtomUUID {
            Task {
                await prefetchNeighborhood(for: focusUUID)
            }
        }
    }

    // MARK: - Context Enrichment

    private func enrichContextWithEmbedding(atomUUID: String) async {
        // Check embedding cache first
        if let cached = await EmbeddingCache.shared.get(byAtomUUID: atomUUID) {
            // Update context with embedding
            let enriched = FocusContext(
                type: currentContext.type,
                focusAtomUUID: currentContext.focusAtomUUID,
                focusAtomType: currentContext.focusAtomType,
                focusAtomVector: cached,
                navigationSection: currentContext.navigationSection,
                dimensionType: currentContext.dimensionType,
                scheduleDate: currentContext.scheduleDate,
                extractedConcepts: currentContext.extractedConcepts,
                projectUUID: currentContext.projectUUID
            )

            await MainActor.run {
                self.currentContext = enriched
            }
        }

        // TODO: Fetch from VectorDatabase if not cached
    }

    private func prefetchNeighborhood(for atomUUID: String) async {
        // Check hot context cache first
        if await HotContextCache.shared.get(for: atomUUID) != nil {
            return  // Already cached
        }

        // Fetch and cache 2-hop neighborhood
        do {
            let queryEngine = GraphQueryEngine()
            let neighborhood = try await queryEngine.getNeighborhood(of: atomUUID, depth: 2)
            await HotContextCache.shared.set(neighborhood, for: atomUUID)
        } catch {
            print("⚠️ Failed to prefetch neighborhood for \(atomUUID): \(error)")
        }
    }

    // MARK: - Context-Aware Search Adaptation

    /// Get entity type boosts for current context
    public func getTypeBoosts() -> [AtomType: Float] {
        switch currentContext.type {
        case .thread:
            // Writing context: boost research and ideas
            return [
                .research: 1.3,
                .idea: 1.2,
                .content: 0.8  // Already in content, deprioritize
            ]
        case .client:
            // Client context: boost projects and tasks
            return [
                .project: 1.3,
                .task: 1.2,
                .idea: 1.1
            ]
        case .plannerum:
            // Planning context: boost tasks and projects
            return [
                .task: 1.5,
                .scheduleBlock: 1.3,
                .project: 1.2
            ]
        case .research:
            // Research context: boost ideas and content
            return [
                .idea: 1.4,
                .content: 1.2,
                .connection: 1.1
            ]
        case .dimension:
            // Dimension context: boost dimension-specific atoms
            return getDimensionTypeBoosts()
        case .thinkspace:
            // Canvas context: boost spatially relevant items
            return [
                .idea: 1.2,
                .research: 1.1,
                .connection: 1.1
            ]
        default:
            return [:]
        }
    }

    private func getDimensionTypeBoosts() -> [AtomType: Float] {
        guard let dimension = currentContext.dimensionType?.lowercased() else {
            return [:]
        }

        switch dimension {
        case "cognitive":
            return [.idea: 1.3, .task: 1.2]
        case "creative":
            return [.content: 1.3, .contentDraft: 1.2]
        case "physiological":
            return [.hrvMeasurement: 1.3, .sleepCycle: 1.2, .workoutSession: 1.2]
        case "behavioral":
            return [.task: 1.3, .scheduleBlock: 1.2, .project: 1.1]
        case "knowledge":
            return [.research: 1.3, .idea: 1.2, .connection: 1.1]
        case "reflection":
            return [.journalEntry: 1.3, .journalInsight: 1.2]
        default:
            return [:]
        }
    }
}

// MARK: - ContextAwareSearchAdapter
/// Adapts search queries based on current focus context
public struct ContextAwareSearchAdapter: Sendable {

    /// Apply context boosts to search results
    public static func applyContextBoosts(
        to results: [RankedResult],
        context: FocusContext,
        typeBoosts: [AtomType: Float]
    ) -> [RankedResult] {
        let multiplier = context.type.searchBoostMultiplier

        return results.map { result in
            let typeBoost = typeBoosts[result.atomType] ?? 1.0

            // Apply boosts by recreating result with adjusted relevance
            // Note: This is a simplified approach - in production,
            // we'd adjust the weight components before combining
            _ = result.relevance * Double(multiplier) * Double(typeBoost)

            return RankedResult(
                atomUUID: result.atomUUID,
                atomType: result.atomType,
                title: result.title,
                snippet: result.snippet,
                semanticWeight: result.semanticWeight,
                structuralWeight: result.structuralWeight,
                recencyWeight: result.recencyWeight,
                usageWeight: result.usageWeight * Double(typeBoost),
                updatedAt: result.updatedAt,
                accessCount: result.accessCount
            )
        }.sorted()
    }

    /// Check if an atom is contextually relevant
    public static func isContextuallyRelevant(
        atom: Atom,
        context: FocusContext
    ) -> Bool {
        // Same project?
        if let projectUUID = context.projectUUID {
            if atom.linksList.contains(where: { $0.type == "project" && $0.uuid == projectUUID }) {
                return true
            }
        }

        // Same dimension?
        if let dimension = context.dimensionType {
            if atom.type.category.rawValue.lowercased() == dimension.lowercased() {
                return true
            }
        }

        // Focus atom is linked?
        if let focusUUID = context.focusAtomUUID {
            if atom.linksList.contains(where: { $0.uuid == focusUUID }) {
                return true
            }
        }

        return false
    }
}
