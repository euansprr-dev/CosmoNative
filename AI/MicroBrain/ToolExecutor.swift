// CosmoOS/AI/MicroBrain/ToolExecutor.swift
// Executes FunctionGemma function calls against AtomRepository
// Part of the Micro-Brain architecture

import Foundation
import os.log

// MARK: - Tool Executor

/// Executes FunctionGemma function calls against the AtomRepository.
///
/// This actor is the bridge between FunctionGemma's output and the Atom data layer.
/// It handles:
/// - CRUD operations on Atoms
/// - Level system queries
/// - Deep work session management
/// - Workout logging
/// - Correlation triggers (offload to Claude API)
public actor ToolExecutor {

    // MARK: - Singleton

    public static let shared = ToolExecutor()

    // MARK: - Dependencies

    private let logger = Logger(subsystem: "com.cosmo.microbrain", category: "ToolExecutor")

    // These would be injected in a real implementation
    // For now, we reference the shared instances
    private var atomRepository: AtomRepositoryProtocol?
    private var levelQueryHandler: LevelSystemQueryHandlerProtocol?
    private var deepWorkHandler: DeepWorkSessionHandlerProtocol?
    private var claudeClient: ClaudeAPIClientProtocol?

    // MARK: - Initialization

    private init() {}

    /// Configure dependencies
    public func configure(
        atomRepository: AtomRepositoryProtocol,
        levelQueryHandler: LevelSystemQueryHandlerProtocol,
        deepWorkHandler: DeepWorkSessionHandlerProtocol,
        claudeClient: ClaudeAPIClientProtocol?
    ) {
        self.atomRepository = atomRepository
        self.levelQueryHandler = levelQueryHandler
        self.deepWorkHandler = deepWorkHandler
        self.claudeClient = claudeClient
    }

    // MARK: - Execution

    /// Execute a FunctionCall and return the result
    public func execute(_ call: FunctionCall, context: VoiceContext) async throws -> ExecutionResult {
        guard let funcName = FunctionName(rawValue: call.name) else {
            throw MicroBrainError.unknownFunction(call.name)
        }

        logger.info("Executing function: \(call.name)")

        switch funcName {
        case .createAtom:
            return try await executeCreate(call, context: context)

        case .updateAtom:
            return try await executeUpdate(call, context: context)

        case .deleteAtom:
            return try await executeDelete(call, context: context)

        case .searchAtoms:
            return try await executeSearch(call)

        case .batchCreate:
            return try await executeBatch(call, context: context)

        case .navigate:
            return try await executeNavigate(call)

        case .queryLevelSystem:
            return try await executeQuery(call)

        case .startDeepWork:
            return try await executeStartDeepWork(call)

        case .stopDeepWork:
            return try await executeStopDeepWork()

        case .extendDeepWork:
            return try await executeExtendDeepWork(call)

        case .logWorkout:
            return try await executeLogWorkout(call)

        case .triggerCorrelationAnalysis:
            return try await executeTriggerCorrelation(call)

        // MARK: - Sanctuary Dimension Navigation
        case .openCognitiveDimension:
            return try await executeSanctuaryNavigation(.cognitive)
        case .openCreativeDimension:
            return try await executeSanctuaryNavigation(.creative)
        case .openPhysiologicalDimension:
            return try await executeSanctuaryNavigation(.physiological)
        case .openBehavioralDimension:
            return try await executeSanctuaryNavigation(.behavioral)
        case .openKnowledgeDimension:
            return try await executeSanctuaryNavigation(.knowledge)
        case .openReflectionDimension:
            return try await executeSanctuaryNavigation(.reflection)
        case .returnToSanctuaryHome:
            return try await executeSanctuaryHomeNavigation()

        // MARK: - Sanctuary Satellite Navigation
        case .openPlannerum:
            return try await executePlannerumNavigation()
        case .openThinkspace:
            return try await executeThinkspaceNavigation()

        // MARK: - Sanctuary Knowledge Graph
        case .zoomKnowledgeGraph:
            return try await executeKnowledgeGraphZoom(call)
        case .focusKnowledgeNode:
            return try await executeKnowledgeNodeFocus(call)
        case .searchKnowledgeNodes:
            return try await executeKnowledgeNodeSearch(call)
        case .showClusterDetail:
            return try await executeShowClusterDetail(call)

        // MARK: - Sanctuary Panels
        case .toggleTimelineView:
            return try await executePanelToggle(.timeline, call: call)
        case .showCorrelationInsights:
            return try await executePanelToggle(.correlationInsights, call: call)
        case .showPredictionsPanel:
            return try await executePanelToggle(.predictions, call: call)
        case .expandMetricDetail:
            return try await executePanelToggle(.metricDetail, call: call)

        // MARK: - Sanctuary Quick Actions
        case .quickLogMood:
            return try await executeQuickLogMood(call)
        case .startMeditationSession:
            return try await executeStartMeditation(call)
        case .openJournalEntry:
            return try await executeOpenJournalEntry()
        }
    }

    // MARK: - Create

    private func executeCreate(_ call: FunctionCall, context: VoiceContext) async throws -> ExecutionResult {
        guard let atomRepo = atomRepository else {
            throw MicroBrainError.executionFailed("AtomRepository not configured")
        }

        guard let atomTypeStr = call.string("atom_type"),
              let atomType = AtomType(rawValue: atomTypeStr) else {
            throw MicroBrainError.invalidParameters("Invalid or missing atom_type")
        }

        let title = call.string("title") ?? "Untitled"
        let body = call.string("body")

        // Build metadata JSON
        var metadata: String?
        if let metadataObj = call.object("metadata") {
            let jsonDict = metadataObj.mapValues { $0.jsonValue }
            if let data = try? JSONSerialization.data(withJSONObject: jsonDict),
               let json = String(data: data, encoding: .utf8) {
                metadata = json
            }
        }

        // Resolve project links
        var links: [AtomLink] = []
        if let linksArray = call.array("links") {
            for linkParam in linksArray {
                if let linkObj = linkParam.objectValue,
                   let type = linkObj["type"]?.stringValue {
                    // If query provided, resolve via fuzzy search
                    if let query = linkObj["query"]?.stringValue {
                        if let project = try await atomRepo.fuzzyFindProject(query: query) {
                            links.append(AtomLink(type: type, uuid: project.uuid, entityType: "project"))
                        }
                    } else if let uuid = linkObj["uuid"]?.stringValue {
                        links.append(AtomLink(type: type, uuid: uuid, entityType: linkObj["entity_type"]?.stringValue))
                    }
                }
            }
        }

        // Create the atom
        let atom = try await atomRepo.create(
            type: atomType,
            title: title,
            body: body,
            metadata: metadata,
            links: links.isEmpty ? nil : links
        )

        logger.info("Created \(atomType.rawValue): \(atom.uuid)")
        return .created(atom)
    }

    // MARK: - Update

    private func executeUpdate(_ call: FunctionCall, context: VoiceContext) async throws -> ExecutionResult {
        guard let atomRepo = atomRepository else {
            throw MicroBrainError.executionFailed("AtomRepository not configured")
        }

        // Resolve target UUID
        let targetStr = call.string("target") ?? "context"
        let targetRef = ParsedAction.TargetReference(rawValue: targetStr) ?? .context

        let targetUuid: String
        switch targetRef {
        case .context:
            guard let uuid = context.editingAtomUuid else {
                throw MicroBrainError.executionFailed("No atom in context to update")
            }
            targetUuid = uuid

        case .lastCreated:
            guard let uuid = try await atomRepo.getLastCreatedUuid() else {
                throw MicroBrainError.executionFailed("No recently created atom found")
            }
            targetUuid = uuid

        case .firstResult:
            throw MicroBrainError.executionFailed("Search result target requires prior search")
        }

        // Build updates
        var updates: [String: Any] = [:]

        if let title = call.string("title") {
            updates["title"] = title
        }

        if let body = call.string("body") {
            updates["body"] = body
        }

        if let metadataObj = call.object("metadata") {
            let jsonDict = metadataObj.mapValues { $0.jsonValue }
            if let data = try? JSONSerialization.data(withJSONObject: jsonDict),
               let json = String(data: data, encoding: .utf8) {
                updates["metadata"] = json
            }
        }

        let atom = try await atomRepo.update(uuid: targetUuid, updates: updates)

        logger.info("Updated atom: \(targetUuid)")
        return .updated(atom)
    }

    // MARK: - Delete

    private func executeDelete(_ call: FunctionCall, context: VoiceContext) async throws -> ExecutionResult {
        guard let atomRepo = atomRepository else {
            throw MicroBrainError.executionFailed("AtomRepository not configured")
        }

        let targetStr = call.string("target") ?? "context"
        let targetRef = ParsedAction.TargetReference(rawValue: targetStr) ?? .context

        let targetUuid: String
        switch targetRef {
        case .context:
            guard let uuid = context.editingAtomUuid else {
                throw MicroBrainError.executionFailed("No atom in context to delete")
            }
            targetUuid = uuid

        case .lastCreated:
            guard let uuid = try await atomRepo.getLastCreatedUuid() else {
                throw MicroBrainError.executionFailed("No recently created atom found")
            }
            targetUuid = uuid

        case .firstResult:
            throw MicroBrainError.executionFailed("Search result target requires prior search")
        }

        try await atomRepo.delete(uuid: targetUuid)

        logger.info("Deleted atom: \(targetUuid)")
        return .deleted(targetUuid)
    }

    // MARK: - Search

    private func executeSearch(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let atomRepo = atomRepository else {
            throw MicroBrainError.executionFailed("AtomRepository not configured")
        }

        guard let query = call.string("query") else {
            throw MicroBrainError.invalidParameters("search_atoms requires query")
        }

        var types: [AtomType]?
        if let typesArray = call.array("types") {
            types = typesArray.compactMap { param -> AtomType? in
                guard let str = param.stringValue else { return nil }
                return AtomType(rawValue: str)
            }
        }

        let atoms = try await atomRepo.search(query: query, types: types)

        logger.info("Search found \(atoms.count) results for: \(query)")
        return .searched(atoms)
    }

    // MARK: - Batch Create

    private func executeBatch(_ call: FunctionCall, context: VoiceContext) async throws -> ExecutionResult {
        guard let atomRepo = atomRepository else {
            throw MicroBrainError.executionFailed("AtomRepository not configured")
        }

        guard let items = call.array("items") else {
            throw MicroBrainError.invalidParameters("batch_create requires items array")
        }

        var createdAtoms: [Atom] = []

        for itemParam in items {
            guard let itemObj = itemParam.objectValue,
                  let atomTypeStr = itemObj["atom_type"]?.stringValue,
                  let atomType = AtomType(rawValue: atomTypeStr) else {
                continue
            }

            let title = itemObj["title"]?.stringValue ?? "Untitled"
            let body = itemObj["body"]?.stringValue

            var metadata: String?
            if let metaObj = itemObj["metadata"]?.objectValue {
                let jsonDict = metaObj.mapValues { $0.jsonValue }
                if let data = try? JSONSerialization.data(withJSONObject: jsonDict),
                   let json = String(data: data, encoding: .utf8) {
                    metadata = json
                }
            }

            let atom = try await atomRepo.create(
                type: atomType,
                title: title,
                body: body,
                metadata: metadata,
                links: nil
            )

            createdAtoms.append(atom)
        }

        logger.info("Batch created \(createdAtoms.count) atoms")
        return .batched(createdAtoms)
    }

    // MARK: - Navigate

    private func executeNavigate(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let destination = call.string("destination") else {
            throw MicroBrainError.invalidParameters("navigate requires destination")
        }

        // Post navigation notification
        await MainActor.run {
            NotificationCenter.default.post(
                name: .voiceNavigationRequested,
                object: nil,
                userInfo: ["destination": destination]
            )
        }

        logger.info("Navigation requested: \(destination)")
        return .navigated(destination)
    }

    // MARK: - Query Level System

    private func executeQuery(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let handler = levelQueryHandler else {
            throw MicroBrainError.executionFailed("LevelSystemQueryHandler not configured")
        }

        guard let queryTypeStr = call.string("query_type") else {
            throw MicroBrainError.invalidParameters("query_level_system requires query_type")
        }

        let dimension = call.string("dimension")

        let response = try await handler.executeQuery(
            queryType: queryTypeStr,
            dimension: dimension
        )

        logger.info("Query executed: \(queryTypeStr)")
        return .queried(response)
    }

    // MARK: - Deep Work

    private func executeStartDeepWork(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let handler = deepWorkHandler else {
            throw MicroBrainError.executionFailed("DeepWorkSessionHandler not configured")
        }

        let durationMinutes = call.int("duration_minutes") ?? 60
        let pomodoroMode = call.bool("pomodoro_mode") ?? false

        let sessionId = try await handler.startSession(
            durationMinutes: durationMinutes,
            pomodoroMode: pomodoroMode
        )

        logger.info("Deep work started: \(sessionId) for \(durationMinutes) minutes")
        return .deepWorkStarted(sessionId)
    }

    private func executeStopDeepWork() async throws -> ExecutionResult {
        guard let handler = deepWorkHandler else {
            throw MicroBrainError.executionFailed("DeepWorkSessionHandler not configured")
        }

        let summary = try await handler.stopSession()

        logger.info("Deep work stopped: \(summary.durationMinutes) minutes, +\(summary.xpEarned) XP")
        return .deepWorkStopped(summary)
    }

    private func executeExtendDeepWork(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let handler = deepWorkHandler else {
            throw MicroBrainError.executionFailed("DeepWorkSessionHandler not configured")
        }

        guard let additionalMinutes = call.int("additional_minutes") else {
            throw MicroBrainError.invalidParameters("extend_deep_work requires additional_minutes")
        }

        let newDuration = try await handler.extendSession(additionalMinutes: additionalMinutes)

        logger.info("Deep work extended by \(additionalMinutes) minutes, new total: \(newDuration)")
        return .deepWorkExtended(newDuration)
    }

    // MARK: - Workout

    private func executeLogWorkout(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let atomRepo = atomRepository else {
            throw MicroBrainError.executionFailed("AtomRepository not configured")
        }

        guard let workoutType = call.string("workout_type") else {
            throw MicroBrainError.invalidParameters("log_workout requires workout_type")
        }

        var metadata: [String: Any] = [
            "workoutType": workoutType,
            "source": "voice",
            "completedAt": ISO8601DateFormatter().string(from: Date())
        ]

        if let duration = call.int("duration_minutes") {
            metadata["durationMinutes"] = duration
        }

        if let distance = call.double("distance_km") {
            metadata["distanceKm"] = distance
        }

        if let exercise = call.string("exercise") {
            metadata["exercise"] = exercise
        }

        if let reps = call.int("reps") {
            metadata["reps"] = reps
        }

        if let sets = call.int("sets") {
            metadata["sets"] = sets
        }

        let metadataJson: String?
        if let data = try? JSONSerialization.data(withJSONObject: metadata),
           let json = String(data: data, encoding: .utf8) {
            metadataJson = json
        } else {
            metadataJson = nil
        }

        let atom = try await atomRepo.create(
            type: .workout,
            title: "\(workoutType.capitalized) workout",
            body: nil,
            metadata: metadataJson,
            links: nil
        )

        logger.info("Workout logged: \(workoutType)")
        return .workoutLogged(atom)
    }

    // MARK: - Correlation (Big Brain Trigger)

    private func executeTriggerCorrelation(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let claude = claudeClient else {
            throw MicroBrainError.executionFailed("ClaudeAPIClient not configured")
        }

        guard let dimensionsArray = call.array("dimensions") else {
            throw MicroBrainError.invalidParameters("trigger_correlation_analysis requires dimensions")
        }

        let dimensions = dimensionsArray.compactMap { $0.stringValue }
        let triggerReason = call.string("trigger_reason") ?? "manual"

        let correlationId = try await claude.triggerCorrelationAnalysis(
            dimensions: dimensions,
            triggerReason: triggerReason
        )

        logger.info("Correlation analysis triggered: \(correlationId)")
        return .correlationTriggered(correlationId)
    }

    // MARK: - Sanctuary Dimension Navigation

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

    private func executeSanctuaryHomeNavigation() async throws -> ExecutionResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .sanctuaryHomeRequested,
                object: nil,
                userInfo: nil
            )
        }

        logger.info("Sanctuary home requested")
        return .sanctuaryHomeOpened
    }

    // MARK: - Sanctuary Satellite Navigation

    private func executePlannerumNavigation() async throws -> ExecutionResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .sanctuaryPlannerumRequested,
                object: nil,
                userInfo: nil
            )
        }

        logger.info("Plannerum opened")
        return .plannerumOpened
    }

    private func executeThinkspaceNavigation() async throws -> ExecutionResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .sanctuaryThinkspaceRequested,
                object: nil,
                userInfo: nil
            )
        }

        logger.info("Thinkspace opened")
        return .thinkspaceOpened
    }

    // MARK: - Sanctuary Knowledge Graph

    private func executeKnowledgeGraphZoom(_ call: FunctionCall) async throws -> ExecutionResult {
        let directionStr = call.string("direction") ?? "in"
        let direction: ZoomDirection = directionStr == "out" ? .out : .in
        let amount = call.double("amount") ?? 0.25

        await MainActor.run {
            NotificationCenter.default.post(
                name: .knowledgeGraphZoomRequested,
                object: nil,
                userInfo: ["direction": direction.rawValue, "amount": amount]
            )
        }

        logger.info("Knowledge graph zoom: \(direction.rawValue) by \(amount)")
        return .knowledgeGraphZoomed(direction: direction)
    }

    private func executeKnowledgeNodeFocus(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let nodeId = call.string("node_id") ?? call.string("query") else {
            throw MicroBrainError.invalidParameters("focus_knowledge_node requires node_id or query")
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .knowledgeNodeFocusRequested,
                object: nil,
                userInfo: ["nodeId": nodeId]
            )
        }

        logger.info("Knowledge node focus: \(nodeId)")
        return .knowledgeNodeFocused(nodeId: nodeId)
    }

    private func executeKnowledgeNodeSearch(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let query = call.string("query") else {
            throw MicroBrainError.invalidParameters("search_knowledge_nodes requires query")
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .knowledgeNodeSearchRequested,
                object: nil,
                userInfo: ["query": query]
            )
        }

        // Result count would be returned asynchronously by the view
        logger.info("Knowledge node search: \(query)")
        return .knowledgeNodesSearched(query: query, resultCount: 0)
    }

    private func executeShowClusterDetail(_ call: FunctionCall) async throws -> ExecutionResult {
        guard let clusterId = call.string("cluster_id") ?? call.string("cluster") else {
            throw MicroBrainError.invalidParameters("show_cluster_detail requires cluster_id")
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .knowledgeClusterDetailRequested,
                object: nil,
                userInfo: ["clusterId": clusterId]
            )
        }

        logger.info("Cluster detail shown: \(clusterId)")
        return .clusterDetailShown(clusterId: clusterId)
    }

    // MARK: - Sanctuary Panels

    private func executePanelToggle(_ panel: SanctuaryPanel, call: FunctionCall) async throws -> ExecutionResult {
        let show = call.bool("show") ?? true

        await MainActor.run {
            NotificationCenter.default.post(
                name: .sanctuaryPanelToggleRequested,
                object: nil,
                userInfo: ["panel": panel.rawValue, "show": show]
            )
        }

        logger.info("Panel toggled: \(panel.rawValue) -> \(show)")
        return .panelToggled(panel: panel, isVisible: show)
    }

    // MARK: - Sanctuary Quick Actions

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

        logger.info("Mood logged: \(emoji) (valence: \(valence), energy: \(energy))")
        return .moodLogged(emoji: emoji, valence: valence, energy: energy)
    }

    private func executeStartMeditation(_ call: FunctionCall) async throws -> ExecutionResult {
        let duration = call.int("duration_minutes") ?? 10
        let sessionId = UUID().uuidString

        await MainActor.run {
            NotificationCenter.default.post(
                name: .meditationSessionRequested,
                object: nil,
                userInfo: [
                    "sessionId": sessionId,
                    "durationMinutes": duration
                ]
            )
        }

        logger.info("Meditation session started: \(sessionId) for \(duration) minutes")
        return .meditationSessionStarted(sessionId: sessionId)
    }

    private func executeOpenJournalEntry() async throws -> ExecutionResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .journalEntryRequested,
                object: nil,
                userInfo: nil
            )
        }

        logger.info("Journal entry opened")
        return .journalEntryOpened
    }

    // MARK: - Mood Helpers

    /// Estimate valence from emoji (higher = more positive)
    private func moodValence(for emoji: String) -> Double {
        switch emoji {
        case "😊", "😄", "🥰", "😍", "🤩", "😁": return 0.8
        case "🙂", "😌", "😇": return 0.5
        case "😐", "🤔": return 0.0
        case "😔", "😢", "😞": return -0.4
        case "😠", "😡", "😤": return -0.6
        case "😭", "💔": return -0.8
        default: return 0.0
        }
    }

    /// Estimate energy from emoji (higher = more energetic)
    private func moodEnergy(for emoji: String) -> Double {
        switch emoji {
        case "🤩", "🥳", "😤", "😡": return 0.8
        case "😊", "😁", "😄": return 0.5
        case "🙂", "😐": return 0.0
        case "😌", "😔", "😢": return -0.4
        case "😴", "😪": return -0.8
        default: return 0.0
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let voiceNavigationRequested = Notification.Name("voiceNavigationRequested")

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

// MARK: - Protocols for Dependencies

/// Protocol for AtomRepository (for testability)
public protocol AtomRepositoryProtocol: Sendable {
    func create(type: AtomType, title: String?, body: String?, metadata: String?, links: [AtomLink]?) async throws -> Atom
    func update(uuid: String, updates: [String: Any]) async throws -> Atom
    func delete(uuid: String) async throws
    func search(query: String, types: [AtomType]?) async throws -> [Atom]
    func fuzzyFindProject(query: String) async throws -> Atom?
    func getLastCreatedUuid() async throws -> String?
}

/// Protocol for LevelSystemQueryHandler
public protocol LevelSystemQueryHandlerProtocol: Sendable {
    func executeQuery(queryType: String, dimension: String?) async throws -> QueryResponse
}

/// Protocol for DeepWorkSessionHandler
public protocol DeepWorkSessionHandlerProtocol: Sendable {
    func startSession(durationMinutes: Int, pomodoroMode: Bool) async throws -> String
    func stopSession() async throws -> DeepWorkSummary
    func extendSession(additionalMinutes: Int) async throws -> Int
}

/// Protocol for ClaudeAPIClient
public protocol ClaudeAPIClientProtocol: Sendable {
    func triggerCorrelationAnalysis(dimensions: [String], triggerReason: String) async throws -> String
}
