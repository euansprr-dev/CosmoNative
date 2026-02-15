// CosmoOS/Agent/Models/AgentPreference.swift
// Preference storage types for agent learning

import Foundation

// MARK: - Preference Scope

/// Defines the context in which a preference applies
enum PreferenceScope: String, Codable, Sendable {
    case global      // Applies everywhere
    case client      // Specific to a client profile (clientUUID in metadata)
    case taskType    // Specific to a task type (e.g., "write", "research")

    var metadataPrefix: String {
        "agent_\(rawValue)"
    }
}

// MARK: - Agent Preference

/// A learned or explicit preference stored as an atom
struct AgentPreference: Codable, Identifiable, Sendable {
    let id: String       // Atom UUID
    let key: String      // e.g., "preferred_hook_style", "default_content_format"
    let value: String    // The preference value
    let scope: PreferenceScope
    let confidence: Double  // 0.0-1.0 (1.0 = user explicitly stated, lower = inferred)
    let source: String     // "explicit" (user told us) or "inferred" (observed pattern)
    let learnedAt: Date
    var scopeQualifier: String? // clientUUID or taskType value for scoped preferences

    init(
        id: String = UUID().uuidString,
        key: String,
        value: String,
        scope: PreferenceScope = .global,
        confidence: Double = 1.0,
        source: String = "explicit",
        learnedAt: Date = Date(),
        scopeQualifier: String? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.scope = scope
        self.confidence = min(max(confidence, 0.0), 1.0) // Clamp to [0, 1]
        self.source = source
        self.learnedAt = learnedAt
        self.scopeQualifier = scopeQualifier
    }

    /// Whether this preference was explicitly stated by the user
    var isExplicit: Bool {
        source == "explicit"
    }

    /// Whether this preference is high-confidence (threshold: 0.7)
    var isHighConfidence: Bool {
        confidence >= 0.7
    }

    /// Encode to JSON for storage in atom structured field
    func toJSON() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Decode from JSON stored in atom structured field
    static func fromJSON(_ json: String) -> AgentPreference? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AgentPreference.self, from: data)
    }
}

// MARK: - Preference Collection

/// Helper for working with multiple preferences, applying scope priority
struct PreferenceCollection: Sendable {
    let preferences: [AgentPreference]

    /// Get the best preference for a key, considering scope priority:
    /// client > taskType > global. Within same scope, higher confidence wins.
    func resolve(key: String, clientUUID: String? = nil, taskType: String? = nil) -> AgentPreference? {
        let matching = preferences.filter { $0.key == key }

        // Try client scope first
        if let clientUUID = clientUUID {
            let clientPref = matching
                .filter { $0.scope == .client && $0.scopeQualifier == clientUUID }
                .max(by: { $0.confidence < $1.confidence })
            if let pref = clientPref { return pref }
        }

        // Try taskType scope
        if let taskType = taskType {
            let taskPref = matching
                .filter { $0.scope == .taskType && $0.scopeQualifier == taskType }
                .max(by: { $0.confidence < $1.confidence })
            if let pref = taskPref { return pref }
        }

        // Fall back to global
        return matching
            .filter { $0.scope == .global }
            .max(by: { $0.confidence < $1.confidence })
    }

    /// All unique preference keys in this collection
    var keys: Set<String> {
        Set(preferences.map(\.key))
    }
}
