// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeState.swift
// Persistent session state for Idea Focus Mode - keyed by atom UUID
// February 2026

import Foundation

// MARK: - Idea Focus Mode State

/// Session state for Idea Focus Mode, persisted to UserDefaults keyed by atom UUID.
/// Tracks UI preferences and analysis timestamps so the workspace restores exactly
/// where the user left off.
@MainActor
class IdeaFocusModeState: ObservableObject {
    // MARK: - Published State

    /// The currently selected framework (SwipeFrameworkType rawValue), if any
    @Published var selectedFramework: String?

    /// Whether the right-hand intelligence panel is collapsed
    @Published var intelligencePanelCollapsed: Bool = false

    /// ISO 8601 timestamp of the last analysis run
    @Published var lastAnalyzedAt: String?

    /// Index of the currently selected hook suggestion (nil = none selected)
    @Published var selectedHookIndex: Int?

    /// Scroll offset within the intelligence panel (for restoring position)
    @Published var intelligencePanelScrollOffset: CGFloat = 0

    // MARK: - Private

    private let atomUUID: String

    private var prefix: String { "ideaFocus_\(atomUUID)_" }

    // MARK: - Initialization

    init(atomUUID: String) {
        self.atomUUID = atomUUID
        load()
    }

    // MARK: - Persistence

    /// Load state from UserDefaults
    private func load() {
        let defaults = UserDefaults.standard
        selectedFramework = defaults.string(forKey: prefix + "selectedFramework")
        intelligencePanelCollapsed = defaults.bool(forKey: prefix + "intelligencePanelCollapsed")
        lastAnalyzedAt = defaults.string(forKey: prefix + "lastAnalyzedAt")

        let hookIndex = defaults.integer(forKey: prefix + "selectedHookIndex")
        selectedHookIndex = defaults.object(forKey: prefix + "selectedHookIndex") != nil ? hookIndex : nil

        intelligencePanelScrollOffset = CGFloat(defaults.double(forKey: prefix + "intelligencePanelScrollOffset"))
    }

    /// Save state to UserDefaults
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(selectedFramework, forKey: prefix + "selectedFramework")
        defaults.set(intelligencePanelCollapsed, forKey: prefix + "intelligencePanelCollapsed")
        defaults.set(lastAnalyzedAt, forKey: prefix + "lastAnalyzedAt")

        if let hookIndex = selectedHookIndex {
            defaults.set(hookIndex, forKey: prefix + "selectedHookIndex")
        } else {
            defaults.removeObject(forKey: prefix + "selectedHookIndex")
        }

        defaults.set(Double(intelligencePanelScrollOffset), forKey: prefix + "intelligencePanelScrollOffset")
    }

    /// Clear all persisted state for this atom
    func clear() {
        let defaults = UserDefaults.standard
        let keys = [
            "selectedFramework",
            "intelligencePanelCollapsed",
            "lastAnalyzedAt",
            "selectedHookIndex",
            "intelligencePanelScrollOffset"
        ]
        for key in keys {
            defaults.removeObject(forKey: prefix + key)
        }
    }

    /// Generate the persistence key prefix for a given atom UUID
    static func persistenceKeyPrefix(atomUUID: String) -> String {
        "ideaFocus_\(atomUUID)_"
    }
}
