// CosmoOS/Agent/DeepDiveAliasRegistry.swift
// Global registry of Deep Dive aliases for fast Telegram capture routing.
// Hydrated from `.deepDive` atoms' metadata.aliases (and topicAliases) on demand.
// Resolution is case-insensitive, longest-match-wins.

import Foundation

@MainActor
final class DeepDiveAliasRegistry {
    static let shared = DeepDiveAliasRegistry()
    private init() {}

    /// Cache of normalized alias → Deep Dive UUID. Refreshed on demand.
    private var aliasMap: [String: String] = [:]
    private var lastRefresh: Date = .distantPast
    private let refreshInterval: TimeInterval = 60 // seconds

    /// Look up a Deep Dive UUID by alias term. Returns nil if no match.
    func deepDiveUUID(forAlias term: String) async -> String? {
        await refreshIfStale()
        return aliasMap[normalize(term)]
    }

    /// Force a refresh of the alias map.
    func refresh() async {
        do {
            let deepDives = try await AtomRepository.shared.fetchAll(type: .deepDive)
            var newMap: [String: String] = [:]
            for dd in deepDives {
                guard let meta = dd.deepDiveMetadata else {
                    // Auto-add the title as an implicit alias so `breathwork:` matches a Deep Dive titled "Breathwork"
                    if let title = dd.title { newMap[normalize(title)] = dd.uuid }
                    continue
                }
                if let title = dd.title {
                    newMap[normalize(title)] = dd.uuid
                }
                for alias in (meta.aliases ?? []) {
                    newMap[normalize(alias)] = dd.uuid
                }
                for topic in (meta.topicAliases ?? []) {
                    newMap[normalize(topic)] = dd.uuid
                }
            }
            self.aliasMap = newMap
            self.lastRefresh = Date()
        } catch {
            print("[DeepDiveAliasRegistry] refresh failed: \(error)")
        }
    }

    private func refreshIfStale() async {
        if Date().timeIntervalSince(lastRefresh) > refreshInterval {
            await refresh()
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns all known aliases (used for the closest-match suggestion in error replies).
    func allAliases() -> [String] {
        Array(aliasMap.keys).sorted()
    }
}
