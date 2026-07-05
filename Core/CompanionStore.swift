// Core/CompanionStore.swift
// Which companion represents the user — read instantly from UserDefaults at
// launch, persisted as a synced user_preference atom (scope "cosmo.companion",
// the daily-focus-goal pattern). Field-for-field twin of the iPhone's
// CompanionStore: a pick made on either device moves both.

import SwiftUI

@Observable
@MainActor
final class CompanionStore {

    static let shared = CompanionStore()

    /// Metadata scope on the user_preference atom — shared with the iPhone.
    static let scope = "cosmo.companion"

    private static let defaultsKey = "companion.id"

    private(set) var companion: Companion

    private struct Payload: Codable {
        var id: String
        var updatedAt: String
    }

    private init() {
        companion = UserDefaults.standard.string(forKey: Self.defaultsKey)
            .flatMap(Companion.init(rawValue:)) ?? .sprout
    }

    /// The user picked a companion — local truth immediately, atom follows.
    func select(_ next: Companion, repository: AtomRepository = .shared) {
        guard next != companion else { return }
        companion = next
        UserDefaults.standard.set(next.rawValue, forKey: Self.defaultsKey)
        Task { try? await Self.write(next, repository: repository) }
    }

    /// Pull the synced choice (a pick made on the iPhone wins). Cheap and
    /// idempotent — run on surface load / sync pulses.
    func hydrate(repository: AtomRepository = .shared) async {
        guard let atom = try? await Self.atom(in: repository),
              let payload = atom.structuredData(as: Payload.self),
              let synced = Companion(rawValue: payload.id),
              synced != companion else { return }
        withAnimation(ProMotionSprings.gentle) { companion = synced }
        UserDefaults.standard.set(synced.rawValue, forKey: Self.defaultsKey)
    }

    private static func write(_ companion: Companion, repository: AtomRepository) async throws {
        let payload = Payload(id: companion.rawValue, updatedAt: ISO8601.string(from: Date()))
        let structured = String(data: try JSONEncoder().encode(payload), encoding: .utf8)
        if let existing = try await atom(in: repository) {
            _ = try await repository.update(uuid: existing.uuid) { atom in
                atom.structured = structured
            }
        } else {
            _ = try await repository.create(Atom.new(
                type: .userPreference,
                title: "Companion",
                structured: structured,
                metadata: #"{"scope":"\#(scope)"}"#
            ))
        }
    }

    private static func atom(in repository: AtomRepository) async throws -> Atom? {
        let prefs = try await repository.fetchAll(type: .userPreference)
        return prefs.first { atom in
            guard let dict = atom.metadataDict else { return false }
            return (dict["scope"] as? String) == scope
        }
    }
}

extension CompanionVitality {
    /// The mark's live state — the same rules as the iPhone masthead:
    /// a 30-day streak wears the star, 7 days turns the ring gilt, and
    /// meeting today's goal turns it green. Never punitive.
    static func current(repository: AtomRepository = .shared) async -> CompanionVitality {
        let engine = FocusStreakEngine(repository: repository)
        let goal = ((try? await engine.dailyFocusGoalMinutes()) ?? nil)
            ?? FocusStreakEngine.defaultGoalMinutes
        guard let streaks = try? await engine.focusStreaks(goal: goal),
              let byDay = try? await engine.focusSecondsByDay() else { return .resting }
        let today = Calendar.current.startOfDay(for: .now)
        let todayMet = (byDay[today] ?? 0) >= goal * 60
        if streaks.current >= 30 { return .luminous }
        if streaks.current >= 7 { return .radiant }
        return todayMet ? .thriving : .resting
    }
}
