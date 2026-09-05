// CosmoOS/Core/ClientColorResolver.swift
// The one answer to "what colour is this client". A dossier may pin a
// swatch (`ClientProfileMetadata.colorHex`); everything else keeps the
// deterministic hash `DS.clientColor(for:)` has always used. The resolver
// holds the pinned overrides in a lock so `DS.clientColor` stays
// nonisolated — it is read inside view bodies and nonisolated computed
// properties across the app, and a colour lookup must never await.
//
// Refresh points: every loader that reads client profiles calls
// `refresh(with:)` off the rows it already fetched; the Profile Studio and
// `setColor` call `refresh()` after a write.
// September 2026

import Foundation
import Synchronization

final class ClientColorResolver: Sendable {
    static let shared = ClientColorResolver()

    /// client uuid → normalised 6-digit hex (no "#", uppercase).
    private let overrides = Mutex<[String: String]>([:])

    init() {}

    // MARK: - Read

    /// The pinned hex for a client, or nil when the hash fallback applies.
    func hex(for uuid: String) -> String? {
        overrides.withLock { $0[uuid] }
    }

    // MARK: - Refresh

    /// One pass over every live client profile.
    func refresh() async {
        let atoms = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
        refresh(with: atoms.map { atom in
            (uuid: atom.uuid, colorHex: atom.metadataValue(as: ColorLens.self)?.colorHex)
        })
    }

    /// Replace the override map from rows a loader already holds. A nil or
    /// malformed hex clears that client back to the hash.
    func refresh(with entries: [(uuid: String, colorHex: String?)]) {
        var next: [String: String] = [:]
        next.reserveCapacity(entries.count)
        for entry in entries {
            guard let hex = Self.normalizedHex(entry.colorHex) else { continue }
            next[entry.uuid] = hex
        }
        overrides.withLock { $0 = next }
    }

    // MARK: - Write

    /// Pin (or clear, with nil) a client's colour. Fetch-fresh, key-merge
    /// only `colorHex` (or remove the key), update, refresh. One ⌘Z.
    @MainActor
    func setColor(hex: String?, for uuid: String, registerUndo: Bool = true) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
              atom.type == .clientProfile else { return }
        let normalized = Self.normalizedHex(hex)
        // A non-nil request that fails to normalise is garbage, not a clear.
        if hex != nil, normalized == nil { return }

        let previous = atom.metadataValue(as: ColorLens.self)?.colorHex
        let updated: Atom
        if let normalized {
            updated = atom.mergingMetadataKeys(ColorOverlay(colorHex: normalized))
        } else {
            updated = atom.removingMetadataKeys(["colorHex"])
        }
        guard (try? await AtomRepository.shared.update(updated)) != nil else { return }

        overrides.withLock { map in
            if let normalized {
                map[uuid] = normalized
            } else {
                _ = map.removeValue(forKey: uuid)
            }
        }
        await refresh()

        guard registerUndo else { return }
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: normalized == nil ? "Reset Client Color" : "Change Client Color",
            undo: { [self] in await setColor(hex: previous, for: uuid, registerUndo: false) },
            redo: { [self] in await setColor(hex: normalized, for: uuid, registerUndo: false) }
        ))
    }

    // MARK: - Hex grammar

    /// "#2e86ab" / "2E86AB" → "2E86AB"; anything that is not six hex digits → nil.
    static func normalizedHex(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit) else { return nil }
        return text.uppercased()
    }

    // MARK: - Lenses

    private struct ColorLens: Decodable {
        var colorHex: String?
    }

    private struct ColorOverlay: Encodable {
        var colorHex: String
    }
}
