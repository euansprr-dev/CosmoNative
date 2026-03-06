// Canvas/CommandCenter/SavedTimerPreset.swift
// Saved timer presets for quick-start recurring work sessions
// March 2026

import Foundation

struct SavedTimerPreset: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var intent: TaskIntent
    var plannedMinutes: Int
    var lastUsedAt: Date?

    init(id: String = UUID().uuidString, title: String, intent: TaskIntent = .general, plannedMinutes: Int = 30, lastUsedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.intent = intent
        self.plannedMinutes = plannedMinutes
        self.lastUsedAt = lastUsedAt
    }

    // MARK: - Persistence

    private static let storageKey = "commandCenter.savedTimerPresets"

    static func loadAll() -> [SavedTimerPreset] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let presets = try? JSONDecoder().decode([SavedTimerPreset].self, from: data) else {
            return []
        }
        return presets.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    static func saveAll(_ presets: [SavedTimerPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
