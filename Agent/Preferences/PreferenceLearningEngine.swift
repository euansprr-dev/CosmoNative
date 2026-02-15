// CosmoOS/Agent/Preferences/PreferenceLearningEngine.swift
// Learns and stores user preferences for the agent

import Foundation

@MainActor
class PreferenceLearningEngine {
    static let shared = PreferenceLearningEngine()

    private let atomRepo = AtomRepository.shared

    private init() {}

    // MARK: - Learn Preference

    func learnPreference(key: String, value: String, scope: PreferenceScope, source: String = "explicit", confidence: Double = 0.8, scopeQualifier: String? = nil) async {
        if let existing = await getPreferenceAtom(key: key, scope: scope, scopeQualifier: scopeQualifier) {
            var updated = existing
            updated.body = value
            let metadata = buildMetadata(key: key, scope: scope, confidence: confidence, source: source, scopeQualifier: scopeQualifier)
            updated.metadata = metadata
            try? await atomRepo.update(updated)
        } else {
            let metadata = buildMetadata(key: key, scope: scope, confidence: confidence, source: source, scopeQualifier: scopeQualifier)
            let atom = Atom.new(
                type: .userPreference,
                title: "Agent Pref: \(key)",
                body: value,
                metadata: metadata
            )
            _ = try? await atomRepo.create(atom)
        }
    }

    // MARK: - Get Preference (with scope resolution)

    func getPreference(key: String, scope: PreferenceScope, scopeQualifier: String? = nil) async -> AgentPreference? {
        // Try specific scope first, fall back to global
        if scope != .global {
            if let pref = await getPreferenceAtom(key: key, scope: scope, scopeQualifier: scopeQualifier) {
                return atomToPreference(pref)
            }
        }
        // Fall back to global
        if let pref = await getPreferenceAtom(key: key, scope: .global, scopeQualifier: nil) {
            return atomToPreference(pref)
        }
        return nil
    }

    // MARK: - Get All Preferences

    func getAllPreferences(scope: PreferenceScope? = nil) async -> [AgentPreference] {
        let allPrefs = (try? await atomRepo.fetchAll(type: .userPreference)) ?? []
        let agentPrefs = allPrefs.filter { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let metaScope = dict["scope"] as? String,
                  metaScope.hasPrefix("agent_") else { return false }

            if let scope = scope {
                return metaScope == scope.metadataPrefix
            }
            return true
        }

        return agentPrefs.compactMap { atomToPreference($0) }
    }

    // MARK: - Build Preference Collection

    /// Builds a PreferenceCollection for efficient multi-key resolution
    func buildCollection(scope: PreferenceScope? = nil) async -> PreferenceCollection {
        let prefs = await getAllPreferences(scope: scope)
        return PreferenceCollection(preferences: prefs)
    }

    // MARK: - Delete Preference

    func deletePreference(key: String, scope: PreferenceScope, scopeQualifier: String? = nil) async {
        if let atom = await getPreferenceAtom(key: key, scope: scope, scopeQualifier: scopeQualifier) {
            try? await atomRepo.delete(atom)
        }
    }

    // MARK: - Infer Preference from Patterns

    /// Record an observed pattern with lower confidence (called by agent after detecting repeated behavior)
    func inferPreference(key: String, value: String, scope: PreferenceScope, scopeQualifier: String? = nil) async {
        // Check if an explicit preference already exists — don't overwrite it
        if let existing = await getPreference(key: key, scope: scope, scopeQualifier: scopeQualifier),
           existing.isExplicit {
            return
        }
        await learnPreference(key: key, value: value, scope: scope, source: "inferred", confidence: 0.5, scopeQualifier: scopeQualifier)
    }

    // MARK: - Private Helpers

    private func getPreferenceAtom(key: String, scope: PreferenceScope, scopeQualifier: String?) async -> Atom? {
        let allPrefs = (try? await atomRepo.fetchAll(type: .userPreference)) ?? []
        return allPrefs.first { atom in
            guard let meta = atom.metadata,
                  let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
                  let metaKey = dict["key"] as? String,
                  let metaScope = dict["scope"] as? String else { return false }

            let matchesKey = metaKey == key
            let matchesScope = metaScope == scope.metadataPrefix

            if let qualifier = scopeQualifier {
                let matchesQualifier = (dict["scopeQualifier"] as? String) == qualifier
                return matchesKey && matchesScope && matchesQualifier
            }

            return matchesKey && matchesScope
        }
    }

    private func atomToPreference(_ atom: Atom) -> AgentPreference? {
        guard let meta = atom.metadata,
              let dict = try? JSONSerialization.jsonObject(with: Data(meta.utf8)) as? [String: Any],
              let key = dict["key"] as? String,
              let scopeStr = dict["scope"] as? String else { return nil }

        let scope: PreferenceScope
        switch scopeStr {
        case "agent_global": scope = .global
        case "agent_client": scope = .client
        case "agent_taskType": scope = .taskType
        default: scope = .global
        }

        return AgentPreference(
            id: atom.uuid,
            key: key,
            value: atom.body ?? "",
            scope: scope,
            confidence: dict["confidence"] as? Double ?? 0.5,
            source: dict["source"] as? String ?? "unknown",
            learnedAt: ISO8601DateFormatter().date(from: atom.createdAt) ?? Date(),
            scopeQualifier: dict["scopeQualifier"] as? String
        )
    }

    private func buildMetadata(key: String, scope: PreferenceScope, confidence: Double, source: String, scopeQualifier: String?) -> String? {
        var dict: [String: Any] = [
            "key": key,
            "scope": scope.metadataPrefix,
            "confidence": confidence,
            "source": source
        ]
        if let qualifier = scopeQualifier {
            dict["scopeQualifier"] = qualifier
        }
        return (try? JSONSerialization.data(withJSONObject: dict)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
