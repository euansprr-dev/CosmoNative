// Shared with iPhone. Identity and journey use separate synced preferences so older
// clients can change a companion without erasing growth or rituals.
import SwiftUI
#if os(iOS)
import CosmoCoreKit
#endif

@Observable
@MainActor
final class CompanionStore {
    static let shared = CompanionStore()
    static let scope = "cosmo.companion"
    static let journeyScope = "cosmo.companion.journey"
    private static let cacheKey = "companion.journey.v1"
    private static let dirtyKey = "companion.journey.pending"

    private(set) var companion: Companion
    private(set) var preferences: CompanionJourneyPreferences
    private(set) var snapshot = CompanionJourneySnapshot()
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var moment: CompanionResponse?
    private(set) var momentID = UUID()
    private var selectionStamp: String
    private var dirty: Bool
    private var revision = 0
    private var saveTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var momentTask: Task<Void, Never>?
    private var seenEvents = Set<String>()

    var growth: CompanionGrowth { .earned(days: preferences.earnedDays) }

    private init() {
        let defaults = UserDefaults.standard
        companion = defaults.string(forKey: "companion.id").flatMap(Companion.init(rawValue:)) ?? .sprout
        selectionStamp = defaults.string(forKey: "companion.updatedAt") ?? ""
        preferences = defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode(CompanionJourneyPreferences.self, from: $0) } ?? .init()
        dirty = defaults.bool(forKey: Self.dirtyKey)
    }

    func select(_ next: Companion, repository: AtomRepository? = nil) {
        let repository = repository ?? .shared
        guard companion != next else { return }
        companion = next
        selectionStamp = ISO8601.string(from: Date())
        changed(repository: repository)
    }

    func setRitual(_ ritual: CompanionRitual, finishTutorial: Bool = false, repository: AtomRepository? = nil) {
        let repository = repository ?? .shared
        var updated = ritual
        updated.updatedAt = Date()
        preferences.rituals.removeAll { $0.trigger == updated.trigger }
        preferences.rituals.append(updated)
        preferences.tutorialComplete = preferences.tutorialComplete || finishTutorial
        changed(repository: repository)
    }

    func dismissMoment() { momentTask?.cancel(); moment = nil }

    /// Called only after local writes succeed. Loading history or pulling sync never fires a ritual.
    func notice(_ trigger: CompanionTrigger, eventID: String, repository: AtomRepository? = nil) async {
        let repository = repository ?? .shared
        guard seenEvents.insert("\(trigger.rawValue):\(eventID)").inserted else { return }
        if seenEvents.count > 512 { seenEvents = ["\(trigger.rawValue):\(eventID)"] }
        await refresh(repository: repository)
        if let ritual = preferences.rituals.first(where: { $0.trigger == trigger && $0.isEnabled }) {
            moment = ritual.response
            momentID = UUID()
            let displayedID = momentID
            momentTask?.cancel()
            momentTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard self?.momentID == displayedID else { return }
                self?.moment = nil
            }
        }
    }

    func hydrate(repository: AtomRepository? = nil) async {
        let repository = repository ?? .shared
        await saveTask?.value
        do {
            let prefs = try await repository.fetchAll(type: .userPreference)
            if let identity = Self.preference(scope: Self.scope, in: prefs)?.structured,
               let fields = Self.dictionary(identity),
               let id = fields["id"] as? String, let synced = Companion(rawValue: id),
               let stamp = fields["updatedAt"] as? String, stamp > selectionStamp {
                companion = synced
                selectionStamp = stamp
            }
            preferences = Self.mergeJourneys(in: prefs, into: preferences)
            cache()
            if dirty { scheduleSave(repository: repository) }
            await refresh(repository: repository)
        } catch {
            errorMessage = "Your companion is saved here. Sync will retry when your library is available."
        }
    }

    func refresh(repository: AtomRepository? = nil) async {
        let repository = repository ?? .shared
        // A completion and its focus record may land together. Keep one read in flight.
        if let refreshTask { await refreshTask.value }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                async let focus = repository.fetchAll(type: .deepWorkBlock)
                async let tasks = repository.fetchAll(type: .task)
                let records = try await (focus, tasks)
                let convert: (Atom) -> CompanionActivityRecord = {
                    .init(id: $0.uuid, createdAt: $0.createdAt, metadata: $0.metadata)
                }
                snapshot = .make(focus: records.0.map(convert), tasks: records.1.map(convert))
                hasLoaded = true
                if !dirty { errorMessage = nil }
                if snapshot.activeDays > preferences.earnedDays {
                    preferences.earnedDays = snapshot.activeDays
                    changed(repository: repository)
                }
            } catch {
                errorMessage = "We couldn’t load your activity. Try again; your growth is safe."
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func changed(repository: AtomRepository) {
        revision += 1
        dirty = true
        cache()
        scheduleSave(repository: repository)
    }

    private func cache() {
        let defaults = UserDefaults.standard
        defaults.set(companion.rawValue, forKey: "companion.id")
        defaults.set(selectionStamp, forKey: "companion.updatedAt")
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.cacheKey) }
        defaults.set(dirty, forKey: Self.dirtyKey)
    }

    private func scheduleSave(repository: AtomRepository) {
        let prior = saveTask
        saveTask = Task { @MainActor [weak self] in
            await prior?.value
            guard let self, dirty else { return }
            let savingRevision = revision
            do {
                let prefs = try await repository.fetchAll(type: .userPreference)
                let merged = Self.mergeJourneys(in: prefs, into: preferences)
                let journeyData = try JSONEncoder().encode(merged)
                try await Self.write(scope: Self.journeyScope, title: "Companion journey", patch: String(decoding: journeyData, as: UTF8.self), existing: Self.preference(scope: Self.journeyScope, in: prefs), repository: repository)
                let identity = try JSONSerialization.data(withJSONObject: ["id": companion.rawValue, "updatedAt": selectionStamp])
                let existingIdentity = Self.preference(scope: Self.scope, in: prefs)
                let remoteStamp = existingIdentity?.structured.flatMap(Self.dictionary)?["updatedAt"] as? String ?? ""
                if selectionStamp >= remoteStamp {
                    try await Self.write(scope: Self.scope, title: "Companion", patch: String(decoding: identity, as: UTF8.self), existing: existingIdentity, repository: repository)
                }
                if savingRevision == revision {
                    preferences = merged
                    dirty = false
                    errorMessage = nil
                    cache()
                }
            } catch {
                errorMessage = "Saved on this device. We’ll retry syncing when you reopen your companion."
            }
        }
    }

    private static func mergeJourneys(in atoms: [Atom], into local: CompanionJourneyPreferences) -> CompanionJourneyPreferences {
        // Two offline first launches can create two scope rows. Fold both before saving.
        atoms.filter { $0.metadata.flatMap(dictionary)?["scope"] as? String == journeyScope }
            .compactMap { atom in
                atom.structured.flatMap { try? JSONDecoder().decode(CompanionJourneyPreferences.self, from: Data($0.utf8)) }
            }
            .reduce(local) { $0.merging($1) }
    }

    private static func preference(scope: String, in atoms: [Atom]) -> Atom? {
        atoms.filter { $0.metadata.flatMap(dictionary)?["scope"] as? String == scope }
            .max { $0.updatedAt < $1.updatedAt }
    }

    nonisolated private static func dictionary(_ string: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any]
    }

    private static func write(scope: String, title: String, patch: String, existing: Atom?, repository: AtomRepository) async throws {
        if let existing {
            _ = try await repository.update(uuid: existing.uuid) { atom in
                // Merge into the latest row; future preference keys survive this client.
                var fields = atom.structured.flatMap(dictionary) ?? [:]
                fields.merge(dictionary(patch) ?? [:]) { _, new in new }
                if let data = try? JSONSerialization.data(withJSONObject: fields) {
                    atom.structured = String(decoding: data, as: UTF8.self)
                }
            }
        } else {
            _ = try await repository.create(Atom.new(type: .userPreference, title: title, structured: patch,
                metadata: #"{"scope":"\#(scope)"}"#))
        }
    }
}

#if os(macOS)
extension CompanionVitality {
    @MainActor static func current(repository: AtomRepository? = nil) async -> CompanionVitality {
        let repository = repository ?? .shared
        let engine = FocusStreakEngine(repository: repository)
        let goal = ((try? await engine.dailyFocusGoalMinutes()) ?? nil) ?? FocusStreakEngine.defaultGoalMinutes
        guard let streaks = try? await engine.focusStreaks(goal: goal),
              let byDay = try? await engine.focusSecondsByDay() else { return .resting }
        if streaks.current >= 30 { return .luminous }
        if streaks.current >= 7 { return .radiant }
        return (byDay[Calendar.current.startOfDay(for: .now)] ?? 0) >= goal * 60 ? .thriving : .resting
    }
}
#endif
