// CosmoOS/UI/CommandK/CortexIdeasBrowser.swift
// Idea ledger logic (sections, layout, capture) — the CortexIdeasBrowser view
// itself was deleted July 2026 (dead since the master-detail refactor); the
// remaining enums are exercised by the idea-lifecycle tests and shared logic.
// Greenhouse-native ideas ledger for Command-K with per-column expansion.

import SwiftUI

// MARK: - Section Model

struct IdeasLedgerSection: Identifiable {
    let id: String
    let clientName: String
    let clientUUID: String?
    let color: Color
    let items: [IdeaGalleryItem]

    var countText: String {
        "\(items.count) idea\(items.count == 1 ? "" : "s")"
    }
}

enum CortexIdeasSectionBuilder {
    static func sections(
        visibleIdeas: [IdeaGalleryItem],
        clientProfiles: [Atom],
        unassignedKey: String = "__unassigned__"
    ) -> [IdeasLedgerSection] {
        var grouped: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []

        for item in visibleIdeas.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if let uuid = item.clientUUID {
                grouped[uuid, default: []].append(item)
            } else {
                unassigned.append(item)
            }
        }

        let clientSections = clientProfiles
            .sorted { ($0.title ?? "") < ($1.title ?? "") }
            .map { client in
                IdeasLedgerSection(
                    id: client.uuid,
                    clientName: client.title ?? "Client",
                    clientUUID: client.uuid,
                    color: DS.clientColor(for: client.uuid),
                    items: grouped[client.uuid] ?? []
                )
            }

        guard !unassigned.isEmpty else { return clientSections }

        return clientSections + [
            IdeasLedgerSection(
                id: unassignedKey,
                clientName: "Unassigned",
                clientUUID: nil,
                color: DS.entityIdea,
                items: unassigned
            )
        ]
    }
}







enum CortexIdeasLedgerLayout {
    static let clientLedgerOuterScrollAxes: Axis.Set = .vertical
    static let clientLedgerInnerScrollAxes: Axis.Set = .horizontal

    static func visibleItems(from items: [IdeaGalleryItem], isExpanded: Bool, previewLimit: Int) -> [IdeaGalleryItem] {
        guard !isExpanded else { return items }
        return Array(items.prefix(previewLimit))
    }
}

enum CortexIdeasCapture {
    static func normalizedTitle(from draft: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// IdeaSortMode and IdeaStatus.sortOrder live in IdeasTab.swift (still used elsewhere).
