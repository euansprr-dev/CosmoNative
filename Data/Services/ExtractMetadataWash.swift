// CosmoOS/Data/Services/ExtractMetadataWash.swift
// One-shot repair (July 2026): before ExtractPeekView existed, opening an
// extract/question atom fell through entity routing into the Idea WORKBENCH,
// which stamped idea-session keys (codexOutline, ideaStatus) onto capture
// atoms. The routing is fixed; this washes the leaked keys off the affected
// rows so captures stop carrying idea scaffolding. Flag-guarded, runs once,
// writes through the versioned sync path.

import Foundation
import GRDB

enum ExtractMetadataWash {
    static let flagKey = "extractIdeaMetadataWash.v1"
    /// Keys the Idea workbench owns — they have no business on a capture.
    static let leakedKeys: Set<String> = ["codexOutline", "ideaStatus", "ideaActivated"]

    static func runIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        do {
            let polluted = try await CosmoDatabase.shared.asyncRead { db in
                try Atom
                    .filter([AtomType.extract.rawValue, AtomType.question.rawValue].contains(Column("type")))
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db)
                    .filter { atom in
                        guard let metadata = atom.metadata else { return false }
                        return leakedKeys.contains { metadata.contains("\"\($0)\"") }
                    }
            }

            var washedCount = 0
            for var atom in polluted {
                guard let cleaned = washedMetadata(atom.metadata) else { continue }
                atom.metadata = cleaned
                _ = try? await MainActor.run { try AtomRepository.shared.updateSync(atom) }
                washedCount += 1
            }

            UserDefaults.standard.set(true, forKey: flagKey)
            if washedCount > 0 {
                print("🧽 [ExtractMetadataWash] stripped idea keys from \(washedCount) capture atom(s)")
            }
        } catch {
            // Flag stays unset — retried on next launch.
            print("⚠️ [ExtractMetadataWash] failed: \(error)")
        }
    }

    /// Pure: removes the leaked keys at the TOP level only (merge-at-key-level
    /// discipline — sibling keys survive byte-for-byte re-encode). Returns nil
    /// when nothing needed washing.
    static func washedMetadata(_ metadata: String?) -> String? {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let present = leakedKeys.filter { dict[$0] != nil }
        guard !present.isEmpty else { return nil }
        for key in present { dict.removeValue(forKey: key) }

        guard let cleaned = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let out = String(data: cleaned, encoding: .utf8)
        else { return nil }
        return out
    }
}
