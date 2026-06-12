// CosmoOS/Automation/AutomationDispatcher.swift
// Singleton event listener that bridges CosmoNotifications to the automation pipeline
// Follows QuestEngine pattern: @MainActor + Timer + Notification subscriptions

import Foundation
import Combine
import GRDB

@MainActor
class AutomationDispatcher: ObservableObject {
    static let shared = AutomationDispatcher()

    // MARK: - State

    /// All rules grouped by trigger type for O(1) lookup
    @Published private(set) var ruleCache: [AutomationTriggerType: [AutomationRule]] = [:]

    /// Total count of active rules
    @Published private(set) var activeRuleCount: Int = 0

    /// Whether the dispatcher is running
    @Published private(set) var isRunning = false

    // MARK: - Engine Components

    private let evaluator = AutomationRuleEvaluator()
    private let executor = AutomationActionExecutor()

    // MARK: - Cascade Prevention

    /// Execution depth counter for cascade prevention (max 5)
    private var currentExecutionDepth = 0
    private static let maxExecutionDepth = 5

    /// Deduplication set: "ruleUUID:atomUUID:secondTimestamp"
    private var recentDispatches = Set<String>()
    private var lastDeduplicationCleanup = Date()

    // MARK: - Status Cache (for detecting status changes)

    /// Previous status values: atomUUID → last known status
    private var statusCache: [String: String] = [:]

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()
    private var scheduledTimers: [String: Timer] = [:] // ruleUUID → timer

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        Task {
            await loadRuleCache()
        }

        subscribeToAtomLifecycle()
        subscribeToCanvasEvents()
        subscribeToSyncEvents()

        print("⚡ [AutomationDispatcher] Started with \(activeRuleCount) active rules")
    }

    func stop() {
        isRunning = false
        cancellables.removeAll()
        scheduledTimers.values.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
        print("⚡ [AutomationDispatcher] Stopped")
    }

    // MARK: - Rule Cache

    func loadRuleCache() async {
        do {
            guard let db = CosmoDatabase.shared.dbQueue else { return }

            let rules = try await db.read { db in
                try AutomationRule
                    .filter(AutomationRule.Columns.isEnabled == true)
                    .fetchAll(db)
            }

            var cache: [AutomationTriggerType: [AutomationRule]] = [:]
            for rule in rules {
                cache[rule.triggerType, default: []].append(rule)
            }

            // Sort each group by priority
            for (key, value) in cache {
                cache[key] = value.sorted { $0.priority < $1.priority }
            }

            ruleCache = cache
            activeRuleCount = rules.count

            // Set up scheduled timers for cron-based rules
            setupScheduledRules(rules.filter { $0.triggerType == .schedule })

        } catch {
            print("⚡ [AutomationDispatcher] Failed to load rules: \(error.localizedDescription)")
        }
    }

    /// Invalidate and reload the rule cache (called when rules are created/updated/deleted)
    func invalidateCache() {
        Task { await loadRuleCache() }
    }

    // MARK: - Event Subscriptions

    private func subscribeToAtomLifecycle() {
        // Entity created
        NotificationCenter.default.publisher(for: CosmoNotification.Entity.created)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleEntityCreated(notification)
                }
            }
            .store(in: &cancellables)

        // Entity updated
        NotificationCenter.default.publisher(for: CosmoNotification.Entity.updated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleEntityUpdated(notification)
                }
            }
            .store(in: &cancellables)

        // Entity deleted
        NotificationCenter.default.publisher(for: CosmoNotification.Entity.deleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleEntityDeleted(notification)
                }
            }
            .store(in: &cancellables)

        // Link created
        NotificationCenter.default.publisher(for: CosmoNotification.Entity.linkEntities)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleLinkCreated(notification)
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToCanvasEvents() {
        // Block placed on canvas
        NotificationCenter.default.publisher(for: CosmoNotification.Canvas.placeEntityOnCanvas)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleBlockPlacedOnCanvas(notification)
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToSyncEvents() {
        // Cloud atoms pulled (sync catch-up)
        NotificationCenter.default.publisher(for: CosmoNotification.Sync.atomsPulled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleAtomsPulled(notification)
                }
            }
            .store(in: &cancellables)

        // Rule CRUD notifications — invalidate cache
        for name in [CosmoNotification.Automation.ruleCreated,
                     CosmoNotification.Automation.ruleUpdated,
                     CosmoNotification.Automation.ruleDeleted] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.invalidateCache()
                }
                .store(in: &cancellables)
        }
    }

    // MARK: - Scheduled Rules

    private func setupScheduledRules(_ rules: [AutomationRule]) {
        // Clear existing timers
        scheduledTimers.values.forEach { $0.invalidate() }
        scheduledTimers.removeAll()

        for rule in rules {
            guard rule.canFire else { continue }

            // Simple interval-based scheduling (parse from config)
            let config = rule.parsedTriggerConfig
            let intervalSeconds: TimeInterval

            if let cronExpr = config["cron"] {
                // Simple cron parsing — extract hour for daily schedules
                intervalSeconds = parseCronInterval(cronExpr)
            } else if let seconds = config["intervalSeconds"], let interval = Double(seconds) {
                intervalSeconds = interval
            } else {
                intervalSeconds = 86400 // Default: daily
            }

            let timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.fireScheduledRule(rule)
                }
            }
            scheduledTimers[rule.uuid] = timer
        }
    }

    private func parseCronInterval(_ cron: String) -> TimeInterval {
        // Simple cron parsing for common patterns
        // "0 9 * * *" = daily at 9am → 86400
        // "*/5 * * * *" = every 5 min → 300
        let parts = cron.split(separator: " ")
        if parts.count >= 5 {
            if let first = parts.first, first.hasPrefix("*/"), let minutes = Int(first.dropFirst(2)) {
                return TimeInterval(minutes * 60)
            }
        }
        return 86400 // Default daily
    }

    private func fireScheduledRule(_ rule: AutomationRule) async {
        // Scheduled rules evaluate against all atoms matching their conditions
        // For now, create a synthetic event and dispatch
        let event = AutomationEvent(
            triggerType: .schedule,
            atomUUID: "schedule-\(rule.uuid)",
            isFromSync: false
        )
        await dispatchEvent(event, depth: 0)
    }

    // MARK: - Notification Handlers

    private func handleEntityCreated(_ notification: Notification) {
        guard let uuid = notification.userInfo?["uuid"] as? String
                ?? notification.userInfo?["atomUUID"] as? String else { return }

        let atomType = notification.userInfo?["type"] as? String
            ?? (notification.userInfo?["type"] as? AtomType)?.rawValue

        let event = AutomationEvent(
            triggerType: .atomCreated,
            atomUUID: uuid,
            atomType: atomType
        )

        Task { await dispatchEvent(event, depth: 0) }

        // Also check for atomTypeCreated trigger
        if let type = atomType {
            let typeEvent = AutomationEvent(
                triggerType: .atomTypeCreated,
                atomUUID: uuid,
                atomType: type
            )
            Task { await dispatchEvent(typeEvent, depth: 0) }
        }
    }

    private func handleEntityUpdated(_ notification: Notification) {
        guard let uuid = notification.userInfo?["uuid"] as? String
                ?? notification.userInfo?["atomUUID"] as? String else { return }

        // General update event
        let event = AutomationEvent(
            triggerType: .atomUpdated,
            atomUUID: uuid
        )
        Task { await dispatchEvent(event, depth: 0) }

        // Check for status change
        Task {
            await detectStatusChange(atomUUID: uuid)
        }
    }

    private func handleEntityDeleted(_ notification: Notification) {
        guard let uuid = notification.userInfo?["uuid"] as? String
                ?? notification.userInfo?["atomUUID"] as? String else { return }

        let event = AutomationEvent(
            triggerType: .atomDeleted,
            atomUUID: uuid
        )
        Task { await dispatchEvent(event, depth: 0) }
    }

    private func handleLinkCreated(_ notification: Notification) {
        guard let sourceUUID = notification.userInfo?["sourceUUID"] as? String else { return }
        let linkType = notification.userInfo?["linkType"] as? String

        let event = AutomationEvent(
            triggerType: .linkCreated,
            atomUUID: sourceUUID,
            newValue: linkType
        )
        Task { await dispatchEvent(event, depth: 0) }
    }

    private func handleBlockPlacedOnCanvas(_ notification: Notification) {
        guard let atomUUID = notification.userInfo?["atomUUID"] as? String else { return }
        let thinkspaceId = notification.userInfo?["thinkspaceId"] as? String

        let event = AutomationEvent(
            triggerType: .addedToThinkspace,
            atomUUID: atomUUID,
            thinkspaceId: thinkspaceId
        )
        Task { await dispatchEvent(event, depth: 0) }
    }

    private func handleAtomsPulled(_ notification: Notification) {
        guard let atomUUIDs = notification.userInfo?["atomUUIDs"] as? [String] else { return }

        Task {
            // Process each pulled atom with a small delay to avoid UI stutter
            for uuid in atomUUIDs {
                let event = AutomationEvent(
                    triggerType: .atomCreated,
                    atomUUID: uuid,
                    isFromSync: true
                )
                await dispatchEvent(event, depth: 0)

                // 50ms delay between evaluations for bulk sync
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    // MARK: - Cluster Membership Events (called by CanvasClusterEngine)

    func handleBlockMovedToCluster(blockUUID: String, clusterId: String) {
        let event = AutomationEvent(
            triggerType: .movedToCluster,
            atomUUID: blockUUID,
            newValue: clusterId
        )
        Task { await dispatchEvent(event, depth: 0) }
    }

    func handleBlockRemovedFromCluster(blockUUID: String, clusterId: String) {
        let event = AutomationEvent(
            triggerType: .removedFromCluster,
            atomUUID: blockUUID,
            previousValue: clusterId
        )
        Task { await dispatchEvent(event, depth: 0) }
    }

    // MARK: - Status Change Detection

    private func detectStatusChange(atomUUID: String) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else { return }

        let currentStatus = await AutomationContextBuilder.build(
            event: AutomationEvent(triggerType: .atomUpdated, atomUUID: atomUUID),
            atom: atom,
            thinkspaceId: nil
        ).atom.status

        let previousStatus = statusCache[atomUUID]

        if let current = currentStatus, current != previousStatus {
            statusCache[atomUUID] = current

            let event = AutomationEvent(
                triggerType: .statusChanged,
                atomUUID: atomUUID,
                atomType: atom.type.rawValue,
                previousValue: previousStatus,
                newValue: current
            )
            await dispatchEvent(event, depth: 0)

            // Check for phase advancement (content pipeline)
            if atom.type == .content, let prev = previousStatus {
                if isPhaseAdvancement(from: prev, to: current) {
                    let phaseEvent = AutomationEvent(
                        triggerType: .phaseAdvanced,
                        atomUUID: atomUUID,
                        atomType: atom.type.rawValue,
                        previousValue: prev,
                        newValue: current
                    )
                    await dispatchEvent(phaseEvent, depth: 0)
                }
            }
        } else if currentStatus != nil {
            statusCache[atomUUID] = currentStatus
        }
    }

    private func isPhaseAdvancement(from: String, to: String) -> Bool {
        let phases = ["ideation", "brainstorm", "draft", "polish", "scheduled", "published", "analyzing", "archived"]
        guard let fromIdx = phases.firstIndex(of: from),
              let toIdx = phases.firstIndex(of: to) else { return false }
        return toIdx > fromIdx
    }

    // MARK: - Core Dispatch

    /// Main dispatch loop — matches events to rules, evaluates conditions, executes actions
    private func dispatchEvent(_ event: AutomationEvent, depth: Int) async {
        // Cascade prevention: depth check
        guard depth < Self.maxExecutionDepth else {
            print("⚡ [AutomationDispatcher] Max cascade depth (\(Self.maxExecutionDepth)) reached, halting")
            return
        }

        // Get rules for this trigger type
        guard let rules = ruleCache[event.triggerType], !rules.isEmpty else { return }

        // Skip automation atoms themselves to prevent infinite loops
        if event.atomType == AtomType.automation.rawValue { return }

        // Fetch the atom for context building
        guard let atom = try? await AtomRepository.shared.fetch(uuid: event.atomUUID) else { return }

        // Skip if recently automated and user hasn't overridden
        if executor.isRecentlyAutomated(event.atomUUID) { return }

        // Build context (spatial info would come from canvas engines)
        let context = await AutomationContextBuilder.build(
            event: event,
            atom: atom,
            thinkspaceId: event.thinkspaceId,
            executionDepth: depth
        )

        // Evaluate and execute matching rules
        var executedFields = Set<String>() // Track which fields were modified (conflict resolution)

        for rule in rules {
            guard rule.canFire else { continue }

            // Deduplication
            let dedupeKey = "\(rule.uuid):\(event.atomUUID):\(Int(event.timestamp.timeIntervalSince1970))"
            guard !recentDispatches.contains(dedupeKey) else { continue }

            // Scope check
            guard evaluator.scopeMatches(rule: rule, context: context) else { continue }

            // Trigger config check
            guard evaluator.triggerMatches(rule: rule, event: event) else { continue }

            // Condition evaluation
            guard evaluator.evaluate(rule: rule, context: context) else { continue }

            // Conflict resolution: check if another rule already modified the same fields
            let actions = rule.parsedActions
            let actionFields = Set(actions.map { $0.type.rawValue })
            let conflicts = actionFields.intersection(executedFields)
            guard conflicts.isEmpty else {
                print("⚡ [AutomationDispatcher] Skipping rule '\(rule.name)' — conflicts with higher-priority rule on: \(conflicts)")
                continue
            }

            // Execute!
            recentDispatches.insert(dedupeKey)
            executedFields.formUnion(actionFields)

            await executor.execute(actions: actions, context: context, ruleName: rule.name)

            // Update rule stats in database
            await updateRuleStats(rule)

            // Post fire notification for UI feedback
            NotificationCenter.default.post(
                name: CosmoNotification.Automation.ruleFired,
                object: nil,
                userInfo: [
                    "ruleName": rule.name,
                    "ruleUUID": rule.uuid,
                    "atomUUID": event.atomUUID,
                    "action": "fired"
                ]
            )

            print("⚡ [AutomationDispatcher] Rule '\(rule.name)' fired for atom \(event.atomUUID)")
        }

        // Periodic cleanup of deduplication set
        cleanupDeduplicationSetIfNeeded()
    }

    // MARK: - Stats & Cleanup

    private func updateRuleStats(_ rule: AutomationRule) async {
        do {
            guard let db = CosmoDatabase.shared.dbQueue else { return }
            let now = ISO8601.string(from: Date())

            try await db.write { db in
                try db.execute(
                    sql: """
                        UPDATE automation_rules
                        SET fireCount = fireCount + 1,
                            lastFiredAt = ?,
                            updatedAt = ?
                        WHERE uuid = ?
                    """,
                    arguments: [now, now, rule.uuid]
                )
            }
        } catch {
            print("⚡ [AutomationDispatcher] Failed to update rule stats: \(error.localizedDescription)")
        }
    }

    private func cleanupDeduplicationSetIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastDeduplicationCleanup) > 60 else { return } // Every 60s
        lastDeduplicationCleanup = now

        // Remove entries older than 5 seconds
        let cutoff = Int(now.timeIntervalSince1970) - 5
        recentDispatches = recentDispatches.filter { key in
            guard let timestampStr = key.split(separator: ":").last,
                  let timestamp = Int(timestampStr) else { return false }
            return timestamp > cutoff
        }
    }

    // MARK: - Public API

    /// Look up a cached rule by uuid (used for confirmation descriptions).
    func ruleCacheLookup(uuid: String) -> AutomationRule? {
        ruleCache.values.flatMap { $0 }.first { $0.uuid == uuid }
    }

    /// Get rules scoped to a specific cluster
    func rules(for clusterId: String) -> [AutomationRule] {
        let allRules = ruleCache.values.flatMap { $0 }
        return allRules.filter { $0.scope == .cluster && $0.scopeId == clusterId }
    }

    /// Get rules scoped to a specific thinkspace
    func rules(for thinkspaceId: String, includeGlobal: Bool = true) -> [AutomationRule] {
        let allRules = ruleCache.values.flatMap { $0 }
        return allRules.filter { rule in
            if includeGlobal && rule.scope == .global { return true }
            return rule.scope == .thinkspace && rule.scopeId == thinkspaceId
        }
    }

    /// Get active rule count for a cluster (for UI indicator)
    func activeRuleCount(for clusterId: String) -> Int {
        rules(for: clusterId).count
    }

    /// Access the executor's deferred actions
    var pendingDeferredActions: [(action: AutomationAction, atomUUID: String, thinkspaceId: String)] {
        executor.deferredActions
    }

    /// Execute deferred actions for a thinkspace
    func executeDeferredActions(for thinkspaceId: String) async -> Int {
        await executor.executeDeferredActions(for: thinkspaceId)
    }
}

// MARK: - Rule CRUD Helpers

extension AutomationDispatcher {

    /// Create a new automation rule and persist it
    @discardableResult
    func createRule(_ rule: AutomationRule) async throws -> AutomationRule {
        guard let db = CosmoDatabase.shared.dbQueue else {
            throw AutomationError.databaseNotReady
        }

        let savedRule = rule
        try await db.write { db in
            var mutable = savedRule
            try mutable.insert(db)
        }

        // Also create companion Atom for sync
        let _ = try await AtomRepository.shared.create(
            type: .automation,
            title: rule.name,
            body: nil,
            structured: nil,
            metadata: rule.actions,
            links: rule.scopeId.map { [AtomLink(type: AtomLinkType.automationScope.rawValue, uuid: $0)] }
        )

        NotificationCenter.default.post(name: CosmoNotification.Automation.ruleCreated, object: nil)

        return savedRule
    }

    /// Update an existing rule
    func updateRule(_ rule: AutomationRule) async throws {
        guard let db = CosmoDatabase.shared.dbQueue else {
            throw AutomationError.databaseNotReady
        }

        try await db.write { db in
            try rule.update(db)
        }

        NotificationCenter.default.post(name: CosmoNotification.Automation.ruleUpdated, object: nil)
    }

    /// Toggle a rule's enabled state
    func toggleRule(uuid: String) async throws {
        guard let db = CosmoDatabase.shared.dbQueue else {
            throw AutomationError.databaseNotReady
        }

        try await db.write { db in
            if var rule = try AutomationRule.filter(AutomationRule.Columns.uuid == uuid).fetchOne(db) {
                rule.isEnabled.toggle()
                rule.updatedAt = ISO8601.string(from: Date())
                try rule.update(db)
            }
        }

        NotificationCenter.default.post(name: CosmoNotification.Automation.ruleUpdated, object: nil)
    }

    /// Delete a rule
    func deleteRule(uuid: String) async throws {
        guard let db = CosmoDatabase.shared.dbQueue else {
            throw AutomationError.databaseNotReady
        }

        try await db.write { db in
            try AutomationRule.filter(AutomationRule.Columns.uuid == uuid).deleteAll(db)
        }

        NotificationCenter.default.post(name: CosmoNotification.Automation.ruleDeleted, object: nil)
    }

    /// Fetch all rules
    func fetchAllRules() async throws -> [AutomationRule] {
        guard let db = CosmoDatabase.shared.dbQueue else {
            throw AutomationError.databaseNotReady
        }

        return try await db.read { db in
            try AutomationRule.order(AutomationRule.Columns.priority).fetchAll(db)
        }
    }
}

// MARK: - Errors

enum AutomationError: Error, LocalizedError {
    case databaseNotReady
    case ruleNotFound
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotReady: return "Database is not ready"
        case .ruleNotFound: return "Automation rule not found"
        case .invalidConfiguration(let msg): return "Invalid configuration: \(msg)"
        }
    }
}
