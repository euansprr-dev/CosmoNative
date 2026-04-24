import SwiftUI
import Combine

enum HabitAssignmentSource: String, Codable, Sendable {
    case manual
    case intentDerived
    case keywordDerived
}

enum HabitCompletionSource: String, Codable, Sendable {
    case task
    case manual
}

struct IntentDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var icon: String
    var accentColor: String
    var sortOrder: Int
    var isArchived: Bool
    var isBuiltInSeed: Bool
    var behaviorTemplate: IntentBehaviorTemplate?

    var accent: Color {
        Color(hex: accentColor)
    }
}

struct ResolvedIntentPresentation: Identifiable, Equatable {
    let id: String
    let definitionID: String?
    let title: String
    let icon: String
    let accentColorHex: String
    let behaviorTemplate: IntentBehaviorTemplate?
    let isUnassigned: Bool

    var accent: Color {
        Color(hex: accentColorHex)
    }
}

struct IntentSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let accentColorHex: String
    var minutes: Int

    var accent: Color {
        Color(hex: accentColorHex)
    }
}

struct HabitDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var icon: String
    var accentColor: String
    var dailyTargetCount: Int
    var keywordTriggers: [String]
    var mappedIntents: [String]
    var defaultIntentUUID: String?
    var allowManualCompletion: Bool
    var sortOrder: Int
    var isBuiltIn: Bool
    var isArchived: Bool

    var accent: Color {
        Color(hex: accentColor)
    }

    var taskIntents: [TaskIntent] {
        mappedIntents.compactMap(TaskIntent.init(rawValue:))
    }

    var normalizedKeywordTriggers: [String] {
        keywordTriggers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

struct HabitVisibilityConfig: Codable, Equatable, Sendable {
    var disabledBuiltInHabitIDs: Set<String> = []
}

struct HabitCompletionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var habitUUID: String
    var date: String
    var source: HabitCompletionSource
    var taskUUID: String?
    var countDelta: Int
    var trackedMinutesSnapshot: Int
}

struct HabitSourceBreakdown: Equatable, Sendable {
    var taskCount: Int = 0
    var manualCount: Int = 0
    var systemCount: Int = 0

    var summaryText: String? {
        var parts: [String] = []
        if taskCount > 0 { parts.append("\(taskCount) tasks") }
        if manualCount > 0 { parts.append("\(manualCount) manual") }
        if systemCount > 0 { parts.append("\(systemCount) system") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct HabitProgressState: Identifiable, Equatable, Sendable {
    let definition: HabitDefinition
    let todayCount: Int
    let targetCount: Int
    let trackedMinutesToday: Int
    let last7Days: [Bool]
    let sourceBreakdown: HabitSourceBreakdown
    let linkedIntentSummary: String?

    var id: String { definition.id }
    var todayProgress: Double {
        guard targetCount > 0 else { return 0 }
        return min(1, Double(todayCount) / Double(targetCount))
    }
    var isTodayComplete: Bool { todayCount >= targetCount }
    var consistencyCount: Int { last7Days.filter { $0 }.count }
    var isBuiltIn: Bool { definition.isBuiltIn }
    var isEditable: Bool { !definition.isBuiltIn }
}

struct HabitResolution: Equatable, Sendable {
    let definition: HabitDefinition
    let source: HabitAssignmentSource
}

@MainActor
final class CommandCenterIntentEngine: ObservableObject {
    static let shared = CommandCenterIntentEngine()

    @Published private(set) var definitions: [IntentDefinition] = []

    private let atomRepository: AtomRepository
    private let scope = "command_center.intent_definitions"

    init(atomRepository: AtomRepository = .shared) {
        self.atomRepository = atomRepository
        self.definitions = Self.seedDefinitions
    }

    var activeDefinitions: [IntentDefinition] {
        definitions
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    func refreshDefinitions() async {
        do {
            let prefs = try await atomRepository.fetchAll(type: .userPreference)
            let stored = prefs.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == scope
            }?.structuredData(as: [IntentDefinition].self) ?? []

            definitions = mergeWithSeeds(stored)
            if stored != definitions {
                await persistDefinitions()
            }
        } catch {
            print("❌ IntentEngine: Failed to refresh definitions: \(error)")
            definitions = Self.seedDefinitions
        }
    }

    func definition(for id: String?) -> IntentDefinition? {
        guard let id else { return nil }
        return activeDefinitions.first(where: { $0.id == id })
    }

    func resolvedDefinition(intentUUID: String?, legacyIntentRaw: String?) -> IntentDefinition? {
        if let direct = definition(for: intentUUID) {
            return direct
        }

        guard let legacyIntent = legacyIntentRaw.flatMap(TaskIntent.init(rawValue:)),
              let template = IntentBehaviorTemplate(legacyIntent) else {
            return nil
        }
        return activeDefinitions.first(where: { $0.behaviorTemplate == template })
    }

    func resolvedPresentation(intentUUID: String?, legacyIntentRaw: String?) -> ResolvedIntentPresentation {
        if let definition = resolvedDefinition(intentUUID: intentUUID, legacyIntentRaw: legacyIntentRaw) {
            return ResolvedIntentPresentation(
                id: definition.id,
                definitionID: definition.id,
                title: definition.title,
                icon: definition.icon,
                accentColorHex: definition.accentColor,
                behaviorTemplate: definition.behaviorTemplate,
                isUnassigned: false
            )
        }

        return ResolvedIntentPresentation(
            id: "unassigned",
            definitionID: nil,
            title: "Unassigned",
            icon: "questionmark.circle",
            accentColorHex: "94A3B8",
            behaviorTemplate: nil,
            isUnassigned: true
        )
    }

    func behaviorTemplate(intentUUID: String?, legacyIntentRaw: String?) -> IntentBehaviorTemplate? {
        resolvedDefinition(intentUUID: intentUUID, legacyIntentRaw: legacyIntentRaw)?.behaviorTemplate
    }

    func createIntent(
        title: String,
        icon: String,
        accentColor: String,
        behaviorTemplate: IntentBehaviorTemplate?
    ) async {
        let definition = IntentDefinition(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.isEmpty ? "tag.fill" : icon,
            accentColor: accentColor.replacingOccurrences(of: "#", with: ""),
            sortOrder: nextSortOrder(),
            isArchived: false,
            isBuiltInSeed: false,
            behaviorTemplate: behaviorTemplate
        )
        definitions = mergeWithSeeds(definitions + [definition])
        await persistDefinitions()
    }

    func updateIntent(_ definition: IntentDefinition) async {
        definitions = mergeWithSeeds(
            definitions.map { $0.id == definition.id ? normalized(definition) : $0 }
        )
        await persistDefinitions()
    }

    func archiveIntent(id: String) async {
        guard let definition = definitions.first(where: { $0.id == id }) else { return }
        var updated = definition
        updated.isArchived = true
        await updateIntent(updated)
    }

    func moveIntent(id: String, direction: Int) async {
        let intents = activeDefinitions
        guard let index = intents.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard intents.indices.contains(targetIndex) else { return }

        var reordered = intents
        reordered.swapAt(index, targetIndex)
        for (offset, intent) in reordered.enumerated() {
            var updated = intent
            updated.sortOrder = offset
            definitions = definitions.map { $0.id == updated.id ? updated : $0 }
        }
        definitions = mergeWithSeeds(definitions)
        await persistDefinitions()
    }

    func seedID(for behavior: TaskIntent?) -> String? {
        guard let behavior, let template = IntentBehaviorTemplate(behavior) else { return nil }
        return activeDefinitions.first(where: { $0.behaviorTemplate == template })?.id
    }

    private func nextSortOrder() -> Int {
        (definitions.map(\.sortOrder).max() ?? -1) + 1
    }

    private func normalized(_ definition: IntentDefinition) -> IntentDefinition {
        IntentDefinition(
            id: definition.id,
            title: definition.title.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: definition.icon.isEmpty ? "tag.fill" : definition.icon,
            accentColor: definition.accentColor.isEmpty ? "2D6A4F" : definition.accentColor.replacingOccurrences(of: "#", with: ""),
            sortOrder: definition.sortOrder,
            isArchived: definition.isArchived,
            isBuiltInSeed: definition.isBuiltInSeed,
            behaviorTemplate: definition.behaviorTemplate
        )
    }

    private func mergeWithSeeds(_ stored: [IntentDefinition]) -> [IntentDefinition] {
        var merged: [IntentDefinition] = stored.map(normalized)
        for seed in Self.seedDefinitions {
            guard !merged.contains(where: { $0.id == seed.id }) else { continue }
            merged.append(seed)
        }
        return merged
    }

    private func persistDefinitions() async {
        do {
            let prefs = try await atomRepository.fetchAll(type: .userPreference)
            let existing = prefs.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == scope
            }

            if var atom = existing {
                atom = atom.withStructured(definitions)
                try await atomRepository.update(atom)
            } else {
                let metadataJSON = "{\"scope\":\"\(scope)\"}"
                var newAtom = Atom.new(type: .userPreference, title: "Intent Definitions", metadata: metadataJSON)
                newAtom = newAtom.withStructured(definitions)
                try await atomRepository.create(newAtom)
            }
        } catch {
            print("❌ IntentEngine: Failed to persist definitions: \(error)")
        }
    }

    static let seedDefinitions: [IntentDefinition] = [
        IntentDefinition(id: "intent-writing", title: "Writing", icon: "pencil.line", accentColor: "818CF8", sortOrder: 0, isArchived: false, isBuiltInSeed: true, behaviorTemplate: .writeContent),
        IntentDefinition(id: "intent-research", title: "Research", icon: "magnifyingglass", accentColor: "38BDF8", sortOrder: 1, isArchived: false, isBuiltInSeed: true, behaviorTemplate: .research),
        IntentDefinition(id: "intent-swipe-study", title: "Swipe Study", icon: "bolt.fill", accentColor: "FFD700", sortOrder: 2, isArchived: false, isBuiltInSeed: true, behaviorTemplate: .studySwipes),
        IntentDefinition(id: "intent-thinking", title: "Thinking", icon: "brain.head.profile", accentColor: "A855F7", sortOrder: 3, isArchived: false, isBuiltInSeed: true, behaviorTemplate: .deepThink),
        IntentDefinition(id: "intent-review", title: "Review", icon: "eye", accentColor: "4ADE80", sortOrder: 4, isArchived: false, isBuiltInSeed: true, behaviorTemplate: .review),
    ]
}

@MainActor
final class CommandCenterHabitEngine: ObservableObject {
    static let shared = CommandCenterHabitEngine()

    @Published private(set) var definitions: [HabitDefinition] = []
    @Published private(set) var visibilityConfig = HabitVisibilityConfig()

    private let atomRepository: AtomRepository
    private let visibilityScope = "habit_visibility_config"

    init(atomRepository: AtomRepository = .shared) {
        self.atomRepository = atomRepository
        self.definitions = Self.builtInDefinitions
    }

    var activeDefinitions: [HabitDefinition] {
        definitions.filter { def in
            if def.isArchived { return false }
            if def.isBuiltIn && visibilityConfig.disabledBuiltInHabitIDs.contains(def.id) {
                return false
            }
            return true
        }
    }

    var allBuiltInDefinitions: [HabitDefinition] {
        Self.builtInDefinitions
    }

    func isBuiltInHabitEnabled(_ id: String) -> Bool {
        !visibilityConfig.disabledBuiltInHabitIDs.contains(id)
    }

    func refreshDefinitions() async {
        await loadVisibilityConfig()
        do {
            let atoms = try await atomRepository.fetchAll(type: .routineDefinition)
            let custom = atoms.compactMap { atom -> HabitDefinition? in
                guard var habit = atom.structuredData(as: HabitDefinition.self) else { return nil }
                habit = normalized(habit, fallbackId: atom.uuid)
                return habit
            }

            definitions = (Self.builtInDefinitions + custom).sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
        } catch {
            print("❌ HabitEngine: Failed to refresh definitions: \(error)")
            definitions = Self.builtInDefinitions
        }
    }

    func definition(for id: String?) -> HabitDefinition? {
        guard let id else { return nil }
        return activeDefinitions.first(where: { $0.id == id })
    }

    func createHabit(
        title: String,
        icon: String,
        accentColor: String,
        dailyTargetCount: Int,
        keywordTriggers: [String],
        mappedIntents: [TaskIntent],
        defaultIntentUUID: String?,
        allowManualCompletion: Bool
    ) async {
        let atom = Atom.new(
            type: .routineDefinition,
            title: title,
            body: bodyText(
                keywordTriggers: keywordTriggers,
                mappedIntents: mappedIntents.map(\.displayName)
            )
        )
        let definition = HabitDefinition(
            id: atom.uuid,
            title: title,
            icon: icon,
            accentColor: accentColor,
            dailyTargetCount: max(1, dailyTargetCount),
            keywordTriggers: normalizedKeywords(keywordTriggers),
            mappedIntents: mappedIntents.map(\.rawValue),
            defaultIntentUUID: defaultIntentUUID,
            allowManualCompletion: allowManualCompletion,
            sortOrder: nextSortOrder(),
            isBuiltIn: false,
            isArchived: false
        )

        do {
            try await atomRepository.create(atom.withStructured(definition))
            await refreshDefinitions()
        } catch {
            print("❌ HabitEngine: Failed to create habit: \(error)")
        }
    }

    func updateHabit(_ definition: HabitDefinition) async {
        guard !definition.isBuiltIn else { return }

        do {
            _ = try await atomRepository.update(uuid: definition.id) { atom in
                let normalized = normalized(definition, fallbackId: atom.uuid)
                atom.title = normalized.title
                atom.body = bodyText(
                    keywordTriggers: normalized.keywordTriggers,
                    mappedIntents: normalized.taskIntents.map(\.displayName)
                )
                atom = atom.withStructured(normalized)
            }
            await refreshDefinitions()
        } catch {
            print("❌ HabitEngine: Failed to update habit: \(error)")
        }
    }

    func archiveHabit(uuid: String) async {
        guard var habit = definition(for: uuid), !habit.isBuiltIn else { return }
        habit.isArchived = true
        await updateHabit(habit)
    }

    func moveHabit(uuid: String, direction: Int) async {
        let customs = activeDefinitions.filter { !$0.isBuiltIn }.sorted { $0.sortOrder < $1.sortOrder }
        guard let index = customs.firstIndex(where: { $0.id == uuid }) else { return }
        let targetIndex = index + direction
        guard customs.indices.contains(targetIndex) else { return }

        var reordered = customs
        reordered.swapAt(index, targetIndex)
        for (offset, habit) in reordered.enumerated() {
            var updated = habit
            updated.sortOrder = 100 + offset
            await updateHabit(updated)
        }
    }

    func assignHabit(taskUUID: String, habitUUID: String?, source: HabitAssignmentSource?) async {
        do {
            _ = try await atomRepository.update(uuid: taskUUID) { atom in
                var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
                metadata.habitUUID = habitUUID
                metadata.habitAssignmentSource = source?.rawValue
                if metadata.intentUUID == nil,
                   let habit = definition(for: habitUUID),
                   let defaultIntentUUID = habit.defaultIntentUUID {
                    metadata.intentUUID = defaultIntentUUID
                    metadata.intent = CommandCenterIntentEngine.shared
                        .behaviorTemplate(intentUUID: defaultIntentUUID, legacyIntentRaw: metadata.intent)?
                        .taskIntent
                        .rawValue
                }
                atom = atom.withMetadata(metadata)
            }
        } catch {
            print("❌ HabitEngine: Failed to assign habit: \(error)")
        }
    }

    func resolveHabit(title: String, intent: TaskIntent?) -> HabitResolution? {
        let active = activeDefinitions

        if let intent,
           let mapped = active.first(where: { $0.taskIntents.contains(intent) }) {
            return HabitResolution(definition: mapped, source: .intentDerived)
        }

        let normalizedTitle = title.lowercased()
        for habit in active {
            if let match = habit.normalizedKeywordTriggers.first(where: { keyword in
                keyword.count > 1 && keywordMatch(keyword, in: normalizedTitle)
            }) {
                _ = match
                return HabitResolution(definition: habit, source: .keywordDerived)
            }
        }

        return nil
    }

    func resolvedHabit(for task: TaskViewModel) -> HabitResolution? {
        if task.habitAssignmentSource == HabitAssignmentSource.manual.rawValue, task.habitUUID == nil {
            return nil
        }
        if let habit = definition(for: task.habitUUID) {
            let source = HabitAssignmentSource(rawValue: task.habitAssignmentSource ?? "") ?? .manual
            return HabitResolution(definition: habit, source: source)
        }
        return resolveHabit(title: task.title, intent: task.intent)
    }

    func recordManualCompletion(habitUUID: String) async {
        guard let habit = definition(for: habitUUID),
              habit.allowManualCompletion else { return }
        await persistCompletion(
            HabitCompletionRecord(
                id: UUID().uuidString,
                habitUUID: habitUUID,
                date: PlannerumFormatters.iso8601.string(from: Date()),
                source: .manual,
                taskUUID: nil,
                countDelta: 1,
                trackedMinutesSnapshot: await trackedMinutesToday(for: habitUUID)
            )
        )
    }

    func recordTaskCompletion(taskUUID: String) async {
        guard let resolution = await resolveTaskHabit(taskUUID: taskUUID) else { return }
        let taskMinutes = await totalTrackedMinutes(forTaskUUID: taskUUID)
        await persistCompletion(
            HabitCompletionRecord(
                id: UUID().uuidString,
                habitUUID: resolution.definition.id,
                date: PlannerumFormatters.iso8601.string(from: Date()),
                source: .task,
                taskUUID: taskUUID,
                countDelta: 1,
                trackedMinutesSnapshot: taskMinutes
            )
        )
    }

    func reverseTaskCompletion(taskUUID: String) async {
        guard let resolution = await resolveTaskHabit(taskUUID: taskUUID) else { return }
        let taskMinutes = await totalTrackedMinutes(forTaskUUID: taskUUID)
        await persistCompletion(
            HabitCompletionRecord(
                id: UUID().uuidString,
                habitUUID: resolution.definition.id,
                date: PlannerumFormatters.iso8601.string(from: Date()),
                source: .task,
                taskUUID: taskUUID,
                countDelta: -1,
                trackedMinutesSnapshot: taskMinutes
            )
        )
    }

    func loadProgressStates() async -> [HabitProgressState] {
        if definitions.count <= Self.builtInDefinitions.count {
            await refreshDefinitions()
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let last7Days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -6 + $0, to: todayStart) }

        do {
            let sessionAtoms = try await atomRepository.fetchAll(type: .deepWorkBlock)
            let taskAtoms = try await atomRepository.fetchAll(type: .task)
            let journalAtoms = try await atomRepository.fetchAll(type: .journalEntry)
            let contentPhases = try await atomRepository.fetchAll(type: .contentPhase)
            let workouts = try await atomRepository.fetchAll(type: .workout)
            let workoutSessions = try await atomRepository.fetchAll(type: .workoutSession)
            let systemEvents = try await atomRepository.fetchAll(type: .systemEvent)

            let completionRecords = systemEvents.compactMap { $0.structuredData(as: HabitCompletionRecord.self) }

            let trackedMinutesByHabitToday = sessionAtoms.reduce(into: [String: Int]()) { partial, atom in
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let started = PlannerumFormatters.iso8601.date(from: metadata.startedAt),
                      started >= todayStart,
                      let habitUUID = metadata.habitUUID else { return }
                partial[habitUUID, default: 0] += metadata.actualMinutes ?? metadata.plannedMinutes
            }

            let totalTrackedMinutesToday = sessionAtoms.reduce(into: 0) { partial, atom in
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let started = PlannerumFormatters.iso8601.date(from: metadata.startedAt),
                      started >= todayStart else { return }
                partial += metadata.actualMinutes ?? metadata.plannedMinutes
            }

            let customCountsByHabitAndDay = completionRecords.reduce(into: [String: [Date: Int]]()) { partial, record in
                guard let date = PlannerumFormatters.iso8601.date(from: record.date) else { return }
                let day = calendar.startOfDay(for: date)
                partial[record.habitUUID, default: [:]][day, default: 0] += record.countDelta
            }

            let customTodayBreakdown = completionRecords.reduce(into: [String: HabitSourceBreakdown]()) { partial, record in
                guard let date = PlannerumFormatters.iso8601.date(from: record.date),
                      calendar.isDate(date, inSameDayAs: todayStart) else { return }
                switch record.source {
                case .task:
                    partial[record.habitUUID, default: HabitSourceBreakdown()].taskCount += max(record.countDelta, 0)
                case .manual:
                    partial[record.habitUUID, default: HabitSourceBreakdown()].manualCount += max(record.countDelta, 0)
                }
            }

            return activeDefinitions.map { definition in
                if definition.isBuiltIn {
                    return builtInProgress(
                        for: definition,
                        last7Days: last7Days,
                        sessionAtoms: sessionAtoms,
                        taskAtoms: taskAtoms,
                        journalAtoms: journalAtoms,
                        contentPhases: contentPhases,
                        workouts: workouts,
                        workoutSessions: workoutSessions,
                        completionRecords: completionRecords,
                        totalTrackedMinutesToday: totalTrackedMinutesToday
                    )
                }

                let dayCounts = customCountsByHabitAndDay[definition.id] ?? [:]
                let todayCount = max(0, dayCounts[todayStart] ?? 0)
                let breakdown = customTodayBreakdown[definition.id] ?? HabitSourceBreakdown()
                return HabitProgressState(
                    definition: definition,
                    todayCount: todayCount,
                    targetCount: max(1, definition.dailyTargetCount),
                    trackedMinutesToday: trackedMinutesByHabitToday[definition.id] ?? 0,
                    last7Days: last7Days.map { max(0, dayCounts[$0] ?? 0) >= max(1, definition.dailyTargetCount) },
                    sourceBreakdown: breakdown,
                    linkedIntentSummary: linkedIntentSummary(for: definition)
                )
            }
            .sorted { $0.definition.sortOrder < $1.definition.sortOrder }
        } catch {
            print("❌ HabitEngine: Failed to load progress states: \(error)")
            return []
        }
    }

    private func builtInProgress(
        for definition: HabitDefinition,
        last7Days: [Date],
        sessionAtoms: [Atom],
        taskAtoms: [Atom],
        journalAtoms: [Atom],
        contentPhases: [Atom],
        workouts: [Atom],
        workoutSessions: [Atom],
        completionRecords: [HabitCompletionRecord],
        totalTrackedMinutesToday: Int
    ) -> HabitProgressState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let manualByDay = completionRecords.reduce(into: [Date: Int]()) { partial, record in
            guard record.habitUUID == definition.id,
                  let date = PlannerumFormatters.iso8601.date(from: record.date) else { return }
            partial[calendar.startOfDay(for: date), default: 0] += record.countDelta
        }

        func createdOnDay(_ atom: Atom, day: Date) -> Bool {
            guard let date = ISO8601DateFormatter().date(from: atom.createdAt) else { return false }
            return calendar.isDate(date, inSameDayAs: day)
        }

        let dayCounts: [Date: Int]
        let trackedToday: Int
        var breakdown = HabitSourceBreakdown()

        switch definition.id {
        case "deepFocus":
            dayCounts = Dictionary(uniqueKeysWithValues: last7Days.map { day in
                let count = sessionAtoms.filter { atom in
                    guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                          let started = PlannerumFormatters.iso8601.date(from: metadata.startedAt),
                          calendar.isDate(started, inSameDayAs: day) else { return false }
                    let minutes = metadata.actualMinutes ?? metadata.plannedMinutes
                    return minutes >= 25 && (metadata.focusScore ?? 100) > 70
                }.count
                return (day, count)
            })
            breakdown.systemCount = dayCounts[today] ?? 0
            trackedToday = totalTrackedMinutesToday

        case "dailyReflection":
            dayCounts = Dictionary(uniqueKeysWithValues: last7Days.map { day in
                let count = journalAtoms.filter { atom in
                    guard createdOnDay(atom, day: day) else { return false }
                    let wordCount = (atom.body ?? "").split(separator: " ").count
                    return wordCount >= 50
                }.count
                return (day, count)
            })
            breakdown.systemCount = dayCounts[today] ?? 0
            trackedToday = 0

        case "taskCrusher":
            dayCounts = Dictionary(uniqueKeysWithValues: last7Days.map { day in
                let count = taskAtoms.filter { atom in
                    guard let metadata = atom.metadataValue(as: TaskMetadata.self),
                          metadata.isCompleted == true else { return false }
                    if let completedAtString = metadata.completedAt,
                       let completedAt = PlannerumFormatters.iso8601.date(from: completedAtString) {
                        return calendar.isDate(completedAt, inSameDayAs: day)
                    }
                    return false
                }.count
                return (day, count)
            })
            breakdown.systemCount = dayCounts[today] ?? 0
            trackedToday = 0

        case "creativeBurst":
            dayCounts = Dictionary(uniqueKeysWithValues: last7Days.map { day in
                (day, contentPhases.filter { createdOnDay($0, day: day) }.count)
            })
            breakdown.systemCount = dayCounts[today] ?? 0
            trackedToday = 0

        case "heartHealth":
            dayCounts = Dictionary(uniqueKeysWithValues: last7Days.map { day in
                let automatic = workouts.filter { createdOnDay($0, day: day) }.count
                    + workoutSessions.filter { createdOnDay($0, day: day) }.count
                let manual = max(0, manualByDay[day] ?? 0)
                return (day, automatic + manual)
            })
            breakdown.systemCount = workouts.filter { createdOnDay($0, day: today) }.count
                + workoutSessions.filter { createdOnDay($0, day: today) }.count
            breakdown.manualCount = max(0, manualByDay[today] ?? 0)
            trackedToday = 0

        default:
            dayCounts = [:]
            trackedToday = 0
        }

        return HabitProgressState(
            definition: definition,
            todayCount: max(0, dayCounts[today] ?? 0),
            targetCount: max(1, definition.dailyTargetCount),
            trackedMinutesToday: trackedToday,
            last7Days: last7Days.map { max(0, dayCounts[$0] ?? 0) >= max(1, definition.dailyTargetCount) },
            sourceBreakdown: breakdown,
            linkedIntentSummary: linkedIntentSummary(for: definition)
        )
    }

    private func resolveTaskHabit(taskUUID: String) async -> HabitResolution? {
        do {
            guard let atom = try await atomRepository.fetch(uuid: taskUUID) else { return nil }
            let metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()

            if metadata.habitAssignmentSource == HabitAssignmentSource.manual.rawValue,
               metadata.habitUUID == nil {
                return nil
            }

            if let habit = definition(for: metadata.habitUUID) {
                let source = HabitAssignmentSource(rawValue: metadata.habitAssignmentSource ?? "") ?? .manual
                return HabitResolution(definition: habit, source: source)
            }

            let intent = metadata.intent.flatMap(TaskIntent.init(rawValue:))
            guard let resolution = resolveHabit(title: atom.title ?? "", intent: intent) else {
                return nil
            }

            await assignHabit(taskUUID: taskUUID, habitUUID: resolution.definition.id, source: resolution.source)
            return resolution
        } catch {
            print("❌ HabitEngine: Failed to resolve task habit: \(error)")
            return nil
        }
    }

    private func totalTrackedMinutes(forTaskUUID taskUUID: String) async -> Int {
        do {
            guard let atom = try await atomRepository.fetch(uuid: taskUUID),
                  let metadata = atom.metadataValue(as: TaskMetadata.self) else { return 0 }
            return metadata.totalFocusMinutes ?? 0
        } catch {
            return 0
        }
    }

    private func trackedMinutesToday(for habitUUID: String) async -> Int {
        do {
            let atoms = try await atomRepository.fetchAll(type: .deepWorkBlock)
            let todayStart = Calendar.current.startOfDay(for: Date())
            return atoms.reduce(into: 0) { partial, atom in
                guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                      let started = PlannerumFormatters.iso8601.date(from: metadata.startedAt),
                      started >= todayStart,
                      metadata.habitUUID == habitUUID else { return }
                partial += metadata.actualMinutes ?? metadata.plannedMinutes
            }
        } catch {
            return 0
        }
    }

    private func persistCompletion(_ record: HabitCompletionRecord) async {
        let atom = Atom.new(
            type: .systemEvent,
            title: "Habit completion",
            body: record.source == .manual ? "Manual habit check-in" : "Task-linked habit completion"
        ).withStructured(record)

        do {
            try await atomRepository.create(atom)
        } catch {
            print("❌ HabitEngine: Failed to persist completion: \(error)")
        }
    }

    func linkedIntentSummary(for habit: HabitDefinition) -> String? {
        let names = habit.taskIntents.map(\.displayName)
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    private func normalized(_ definition: HabitDefinition, fallbackId: String) -> HabitDefinition {
        HabitDefinition(
            id: definition.id.isEmpty ? fallbackId : definition.id,
            title: definition.title.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: definition.icon.isEmpty ? "repeat" : definition.icon,
            accentColor: definition.accentColor.isEmpty ? "2D6A4F" : definition.accentColor.replacingOccurrences(of: "#", with: ""),
            dailyTargetCount: max(1, definition.dailyTargetCount),
            keywordTriggers: normalizedKeywords(definition.keywordTriggers),
            mappedIntents: definition.taskIntents.map(\.rawValue),
            defaultIntentUUID: definition.defaultIntentUUID,
            allowManualCompletion: definition.allowManualCompletion,
            sortOrder: definition.sortOrder,
            isBuiltIn: definition.isBuiltIn,
            isArchived: definition.isArchived
        )
    }

    private func normalizedKeywords(_ input: [String]) -> [String] {
        input
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func keywordMatch(_ keyword: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = "\\b\(escaped)\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            || text.contains(keyword)
    }

    private func nextSortOrder() -> Int {
        (definitions.map(\.sortOrder).max() ?? 99) + 1
    }

    private func bodyText(keywordTriggers: [String], mappedIntents: [String]) -> String? {
        let keywords = normalizedKeywords(keywordTriggers)
        var parts: [String] = []
        if !mappedIntents.isEmpty {
            parts.append("Intents: \(mappedIntents.joined(separator: ", "))")
        }
        if !keywords.isEmpty {
            parts.append("Keywords: \(keywords.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    // MARK: - Visibility Config Persistence

    func setBuiltInHabitEnabled(id: String, enabled: Bool) async {
        if enabled {
            visibilityConfig.disabledBuiltInHabitIDs.remove(id)
        } else {
            visibilityConfig.disabledBuiltInHabitIDs.insert(id)
        }
        await saveVisibilityConfig()
    }

    private func loadVisibilityConfig() async {
        do {
            let prefs = try await atomRepository.fetchAll(type: .userPreference)
            let configAtom = prefs.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == visibilityScope
            }
            if let atom = configAtom,
               let config = atom.structuredData(as: HabitVisibilityConfig.self) {
                visibilityConfig = config
            } else {
                visibilityConfig = HabitVisibilityConfig()
            }
        } catch {
            print("❌ HabitEngine: Failed to load visibility config: \(error)")
            visibilityConfig = HabitVisibilityConfig()
        }
    }

    private func saveVisibilityConfig() async {
        do {
            let prefs = try await atomRepository.fetchAll(type: .userPreference)
            let existing = prefs.first { atom in
                guard let dict = atom.metadataDict else { return false }
                return (dict["scope"] as? String) == visibilityScope
            }

            if var atom = existing {
                atom = atom.withStructured(visibilityConfig)
                try await atomRepository.update(atom)
            } else {
                let metadataJSON = "{\"scope\":\"\(visibilityScope)\"}"
                var newAtom = Atom.new(
                    type: .userPreference,
                    title: "Habit Visibility Config",
                    metadata: metadataJSON
                )
                newAtom = newAtom.withStructured(visibilityConfig)
                try await atomRepository.create(newAtom)
            }
        } catch {
            print("❌ HabitEngine: Failed to save visibility config: \(error)")
        }
    }

    // MARK: - Habit Report (Extended Date Ranges)

    func loadHabitReport(startDate: Date, endDate: Date) async -> [HabitReportEntry] {
        if definitions.count <= Self.builtInDefinitions.count {
            await refreshDefinitions()
        }

        let calendar = Calendar.current
        let dayCount = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let allDays = (0...dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
            .map { calendar.startOfDay(for: $0) }

        do {
            let sessionAtoms = try await atomRepository.fetchAll(type: .deepWorkBlock)
            let taskAtoms = try await atomRepository.fetchAll(type: .task)
            let journalAtoms = try await atomRepository.fetchAll(type: .journalEntry)
            let contentPhases = try await atomRepository.fetchAll(type: .contentPhase)
            let workouts = try await atomRepository.fetchAll(type: .workout)
            let workoutSessions = try await atomRepository.fetchAll(type: .workoutSession)
            let systemEvents = try await atomRepository.fetchAll(type: .systemEvent)

            let completionRecords = systemEvents.compactMap { $0.structuredData(as: HabitCompletionRecord.self) }

            return activeDefinitions.map { definition in
                let createdDate = habitCreationDate(for: definition)
                let applicableDays = allDays.filter { day in
                    if let created = createdDate, day < calendar.startOfDay(for: created) { return false }
                    return day <= calendar.startOfDay(for: Date())
                }

                let dayResults: [Date: Bool]
                if definition.isBuiltIn {
                    dayResults = builtInDayResults(
                        for: definition,
                        days: applicableDays,
                        sessionAtoms: sessionAtoms,
                        taskAtoms: taskAtoms,
                        journalAtoms: journalAtoms,
                        contentPhases: contentPhases,
                        workouts: workouts,
                        workoutSessions: workoutSessions,
                        completionRecords: completionRecords
                    )
                } else {
                    let recordsByDay = completionRecords
                        .filter { $0.habitUUID == definition.id }
                        .reduce(into: [Date: Int]()) { partial, record in
                            guard let date = PlannerumFormatters.iso8601.date(from: record.date) else { return }
                            partial[calendar.startOfDay(for: date), default: 0] += record.countDelta
                        }
                    dayResults = Dictionary(uniqueKeysWithValues: applicableDays.map { day in
                        (day, max(0, recordsByDay[day] ?? 0) >= max(1, definition.dailyTargetCount))
                    })
                }

                let completedDays = dayResults.values.filter { $0 }.count
                let totalDays = applicableDays.count
                let rate = totalDays > 0 ? Double(completedDays) / Double(totalDays) : 0

                let (current, best) = calculateStreaks(dayResults: dayResults, days: applicableDays)

                return HabitReportEntry(
                    habitDefinition: definition,
                    dayResults: dayResults,
                    completionRate: rate,
                    completedDays: completedDays,
                    totalDays: totalDays,
                    currentStreak: current,
                    bestStreak: best,
                    createdDate: createdDate
                )
            }
        } catch {
            print("❌ HabitEngine: Failed to load habit report: \(error)")
            return []
        }
    }

    private func builtInDayResults(
        for definition: HabitDefinition,
        days: [Date],
        sessionAtoms: [Atom],
        taskAtoms: [Atom],
        journalAtoms: [Atom],
        contentPhases: [Atom],
        workouts: [Atom],
        workoutSessions: [Atom],
        completionRecords: [HabitCompletionRecord]
    ) -> [Date: Bool] {
        let calendar = Calendar.current
        let target = max(1, definition.dailyTargetCount)

        let manualByDay = completionRecords
            .filter { $0.habitUUID == definition.id }
            .reduce(into: [Date: Int]()) { partial, record in
                guard let date = PlannerumFormatters.iso8601.date(from: record.date) else { return }
                partial[calendar.startOfDay(for: date), default: 0] += record.countDelta
            }

        func createdOnDay(_ atom: Atom, day: Date) -> Bool {
            guard let date = ISO8601DateFormatter().date(from: atom.createdAt) else { return false }
            return calendar.isDate(date, inSameDayAs: day)
        }

        return Dictionary(uniqueKeysWithValues: days.map { day in
            let count: Int
            switch definition.id {
            case "deepFocus":
                count = sessionAtoms.filter { atom in
                    guard let metadata = atom.metadataValue(as: DeepWorkSessionMetadata.self),
                          let started = PlannerumFormatters.iso8601.date(from: metadata.startedAt),
                          calendar.isDate(started, inSameDayAs: day) else { return false }
                    let minutes = metadata.actualMinutes ?? metadata.plannedMinutes
                    return minutes >= 25 && (metadata.focusScore ?? 100) > 70
                }.count

            case "dailyReflection":
                count = journalAtoms.filter { atom in
                    guard createdOnDay(atom, day: day) else { return false }
                    return (atom.body ?? "").split(separator: " ").count >= 50
                }.count

            case "taskCrusher":
                count = taskAtoms.filter { atom in
                    guard let metadata = atom.metadataValue(as: TaskMetadata.self),
                          metadata.isCompleted == true,
                          let completedAt = metadata.completedAt,
                          let date = PlannerumFormatters.iso8601.date(from: completedAt) else { return false }
                    return calendar.isDate(date, inSameDayAs: day)
                }.count

            case "creativeBurst":
                count = contentPhases.filter { createdOnDay($0, day: day) }.count

            case "heartHealth":
                let automatic = workouts.filter { createdOnDay($0, day: day) }.count
                    + workoutSessions.filter { createdOnDay($0, day: day) }.count
                let manual = max(0, manualByDay[day] ?? 0)
                count = automatic + manual

            default:
                count = 0
            }
            return (day, count >= target)
        })
    }

    private func habitCreationDate(for definition: HabitDefinition) -> Date? {
        if definition.isBuiltIn { return nil }
        // Custom habits have UUID as id, which is the atom UUID
        // We can't easily get creation date without fetching, so return nil
        // (the caller will treat nil as "always existed" — acceptable for built-ins,
        //  and custom habits will show from their first completion)
        return nil
    }

    private func calculateStreaks(dayResults: [Date: Bool], days: [Date]) -> (current: Int, best: Int) {
        let sorted = days.sorted()
        var current = 0
        var best = 0
        var streak = 0

        for day in sorted {
            if dayResults[day] == true {
                streak += 1
                best = max(best, streak)
            } else {
                streak = 0
            }
        }
        current = streak
        return (current, best)
    }

    static let builtInDefinitions: [HabitDefinition] = [
        HabitDefinition(
            id: "deepFocus",
            title: "Deep Focus",
            icon: "brain.head.profile",
            accentColor: "7B7EC0",
            dailyTargetCount: 1,
            keywordTriggers: [],
            mappedIntents: [],
            defaultIntentUUID: nil,
            allowManualCompletion: false,
            sortOrder: 0,
            isBuiltIn: true,
            isArchived: false
        ),
        HabitDefinition(
            id: "dailyReflection",
            title: "Journal",
            icon: "book.fill",
            accentColor: "5B84B0",
            dailyTargetCount: 1,
            keywordTriggers: [],
            mappedIntents: [],
            defaultIntentUUID: nil,
            allowManualCompletion: false,
            sortOrder: 1,
            isBuiltIn: true,
            isArchived: false
        ),
        HabitDefinition(
            id: "taskCrusher",
            title: "Tasks Done",
            icon: "checkmark.circle.fill",
            accentColor: "38B764",
            dailyTargetCount: 3,
            keywordTriggers: [],
            mappedIntents: [],
            defaultIntentUUID: nil,
            allowManualCompletion: false,
            sortOrder: 2,
            isBuiltIn: true,
            isArchived: false
        ),
        HabitDefinition(
            id: "creativeBurst",
            title: "Creative Burst",
            icon: "paintbrush.fill",
            accentColor: "C4A870",
            dailyTargetCount: 1,
            keywordTriggers: [],
            mappedIntents: [],
            defaultIntentUUID: nil,
            allowManualCompletion: false,
            sortOrder: 3,
            isBuiltIn: true,
            isArchived: false
        ),
        HabitDefinition(
            id: "heartHealth",
            title: "Exercise",
            icon: "heart.fill",
            accentColor: "DC3545",
            dailyTargetCount: 1,
            keywordTriggers: [],
            mappedIntents: [],
            defaultIntentUUID: nil,
            allowManualCompletion: true,
            sortOrder: 4,
            isBuiltIn: true,
            isArchived: false
        ),
    ]
}
