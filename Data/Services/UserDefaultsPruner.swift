// CosmoOS/Data/Services/UserDefaultsPruner.swift
// Launch-time sweep that removes stale per-atom UI-state keys from UserDefaults.
//
// The preferences plist is loaded fully into RAM at launch and rewritten to
// disk on every write, so per-atom keys (focus-mode UI state, inline-assistant
// sessions, cosmo-window archives) otherwise accumulate forever — the plist had
// grown past 4MB before this sweep existed. Every rule here only deletes state
// that is unreachable from the UI:
//   - per-atom keys whose atom no longer exists (tombstoned/deleted)

import Foundation
import GRDB

enum UserDefaultsPruner {

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

        if removedAtomState > 0 {
            print("[DefaultsPruner] Removed \(removedAtomState) stale UI-state keys")
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

        // Conversations are user content. Their owner being absent or outside
        // a recent-history limit is never permission to discard them.
        return nil
    }
}
