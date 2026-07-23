// CosmoOS/Data/Services/UserDefaultsPruner.swift
// Launch-time sweep that removes stale per-atom UI-state keys from UserDefaults.
//
// The preferences plist is loaded fully into RAM at launch and rewritten to
// disk on every write, so per-atom keys (focus-mode UI state, inline-assistant
// sessions, cosmo-window archives) otherwise accumulate forever — the plist had
// grown past 4MB before this sweep existed. Every rule here only deletes state
// that is unreachable from the UI:
//   - per-atom keys whose atom no longer exists (tombstoned/deleted)
//   - cosmo-window chat archives that the history sheet can no longer list

import Foundation
import GRDB

enum UserDefaultsPruner {

    private static let archivePrefix = "cosmoWindow.messageArchive."
    private static let collaboratorConversationPrefix = "cosmo-collaborator-"
    /// The history sheet lists 20 recent conversations; keep a 3x margin so a
    /// conversation briefly pushed off the list is never lost.
    private static let archiveKeepLimit = 60

    /// Run once per launch, off the startup hot path.
    static func pruneStaleState() async {
        let defaults = UserDefaults.standard

        // Live (non-tombstoned) atom UUIDs. An empty result means a fresh
        // install or a mid-migration database — never prune against that.
        let liveUUIDs: Set<String>
        do {
            let uuids: [String] = try await CosmoDatabase.shared.asyncRead { db in
                try String.fetchAll(db, sql: "SELECT uuid FROM atoms WHERE is_deleted = 0")
            }
            liveUUIDs = Set(uuids.map { $0.uppercased() })
        } catch {
            print("[DefaultsPruner] Skipped — atom fetch failed: \(error)")
            return
        }
        guard !liveUUIDs.isEmpty else {
            print("[DefaultsPruner] Skipped — no live atoms (fresh install or migration in flight)")
            return
        }

        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        var removedAtomState = 0

        for key in allKeys {
            guard let uuid = atomUUID(inKey: key) else { continue }
            if !liveUUIDs.contains(uuid.uppercased()) {
                defaults.removeObject(forKey: key)
                removedAtomState += 1
            }
        }

        let removedArchives = await pruneOrphanedWindowArchives(
            defaults: defaults,
            allKeys: allKeys,
            liveUUIDs: liveUUIDs
        )

        if removedAtomState > 0 || removedArchives > 0 {
            print("[DefaultsPruner] Removed \(removedAtomState) stale atom-state keys, \(removedArchives) orphaned chat archives")
        }
    }

    /// Extract the owning atom UUID from a per-atom state key, or nil when the
    /// key is not one of the swept families (or has a non-UUID suffix like the
    /// inline assistant's `global` session — those are never pruned).
    static func atomUUID(inKey key: String) -> String? {
        // connectionFocusMode_<UUID> / researchFocusMode_<UUID>
        for prefix in ["connectionFocusMode_", "researchFocusMode_"] where key.hasPrefix(prefix) {
            let rest = String(key.dropFirst(prefix.count))
            return UUID(uuidString: rest) != nil ? rest : nil
        }

        // ideaFocus_<UUID>_<stateSuffix>
        if key.hasPrefix("ideaFocus_") {
            let rest = key.dropFirst("ideaFocus_".count)
            guard let first = rest.split(separator: "_", maxSplits: 1).first else { return nil }
            let candidate = String(first)
            return UUID(uuidString: candidate) != nil ? candidate : nil
        }

        // cosmo.inlineAssistant.session.<surface>:<UUID>
        if key.hasPrefix("cosmo.inlineAssistant.session") {
            guard let colon = key.lastIndex(of: ":") else { return nil }
            let rest = String(key[key.index(after: colon)...])
            return UUID(uuidString: rest) != nil ? rest : nil
        }

        return nil
    }

    /// Cosmo-window chat archives live in defaults keyed by conversation id,
    /// while the history sheet lists conversations from ConversationMemoryService.
    /// An archive is unreachable — and prunable — when its conversation can no
    /// longer appear in that list:
    ///   - collaborator archives (`cosmo-collaborator-<preset>-<atomUUID>`):
    ///     reachable while their atom exists, pruned only when the atom is gone
    ///   - regular archives: pruned when absent from the recent-conversation
    ///     list (with margin) and not the active conversation
    private static func pruneOrphanedWindowArchives(
        defaults: UserDefaults,
        allKeys: [String],
        liveUUIDs: Set<String>
    ) async -> Int {
        let archiveKeys = allKeys.filter { $0.hasPrefix(archivePrefix) }
        guard !archiveKeys.isEmpty else { return 0 }

        let recent = await ConversationMemoryService.shared.getRecentConversations(limit: archiveKeepLimit)
        // Conversation memory unavailable/empty — can't tell what's reachable.
        guard !recent.isEmpty else { return 0 }

        var keep = Set(recent.map { archivePrefix + $0.id })
        if let current = defaults.string(forKey: "cosmoWindow.lastConversationId") {
            keep.insert(archivePrefix + current)
        }

        var removed = 0
        for key in archiveKeys {
            if keep.contains(key) { continue }

            let conversationId = String(key.dropFirst(archivePrefix.count))
            if conversationId.hasPrefix(collaboratorConversationPrefix) {
                // Atom-scoped: prune only when the owning atom is gone.
                guard let uuid = trailingUUID(of: conversationId),
                      !liveUUIDs.contains(uuid.uppercased()) else { continue }
            }

            defaults.removeObject(forKey: key)
            removed += 1
        }
        return removed
    }

    /// A UUID occupies the final 36 characters of collaborator conversation ids.
    static func trailingUUID(of string: String) -> String? {
        guard string.count >= 36 else { return nil }
        let candidate = String(string.suffix(36))
        return UUID(uuidString: candidate) != nil ? candidate : nil
    }
}
