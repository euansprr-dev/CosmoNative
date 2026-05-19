import Foundation

struct CommandKUserCommandRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let action: CommandKAction
}

struct CommandKUserCommandSearchComposer {
    func rows(for quicklinks: [CommandKQuicklink]) -> [CommandKUserCommandRow] {
        quicklinks.compactMap(row(for:))
    }

    private func row(for quicklink: CommandKQuicklink) -> CommandKUserCommandRow? {
        guard let action = action(for: quicklink) else { return nil }
        return CommandKUserCommandRow(
            id: "quicklink-\(quicklink.id)",
            title: quicklink.title,
            subtitle: "Quicklink · \(quicklink.alias)",
            icon: action.icon,
            action: action
        )
    }

    private func action(for quicklink: CommandKQuicklink) -> CommandKAction? {
        switch quicklink.route {
        case .commandCenter:
            return CommandKAction(
                kind: .navigateCommandCenter,
                title: quicklink.title,
                subtitle: "Open Command Center",
                icon: "command.circle.fill",
                payload: CommandKActionPayload(quicklinkID: quicklink.id, rawText: quicklink.alias)
            )
        case .commandKDomain(let domain):
            return CommandKAction(
                kind: .openDomain,
                title: quicklink.title,
                subtitle: "Open \(quicklink.title)",
                icon: icon(forDomain: domain),
                payload: CommandKActionPayload(
                    domain: domain,
                    quicklinkID: quicklink.id,
                    rawText: quicklink.alias
                )
            )
        case .atom(let uuid):
            return CommandKAction(
                kind: .openAtom,
                title: quicklink.title,
                subtitle: "Open object",
                icon: "arrow.up.left.and.arrow.down.right",
                payload: CommandKActionPayload(atomUUID: uuid, quicklinkID: quicklink.id, rawText: quicklink.alias)
            )
        case .thinkspace(let id):
            return CommandKAction(
                kind: .openThinkspace,
                title: quicklink.title,
                subtitle: "Open Thinkspace",
                icon: "rectangle.3.group.fill",
                payload: CommandKActionPayload(thinkspaceID: id, quicklinkID: quicklink.id, rawText: quicklink.alias)
            )
        case .savedSearch(let query):
            return CommandKAction(
                kind: .savedSearch,
                title: quicklink.title,
                subtitle: "Search \(query)",
                icon: "magnifyingglass.circle.fill",
                payload: CommandKActionPayload(queryText: query, quicklinkID: quicklink.id, rawText: quicklink.alias)
            )
        }
    }

    private func icon(forDomain domain: String) -> String {
        switch domain {
        case "swipeGallery": return "bolt.fill"
        case "ideas": return "lightbulb.fill"
        case "readwise": return "books.vertical.fill"
        case "database": return "tray.full.fill"
        default: return "rectangle.grid.2x2.fill"
        }
    }
}

struct CommandKSystemCommandComposer {
    func rows(for query: String) -> [CommandKUserCommandRow] {
        guard matchesCosmoQuery(query) else { return [] }
        return [
            row(
                id: "system-cosmo-pane",
                title: "Open Cosmo as Pane",
                subtitle: "Dock the AI assistant beside your workspace",
                kind: .openCosmoPane
            ),
            row(
                id: "system-cosmo-window",
                title: "Open Cosmo Floating Window",
                subtitle: "Open the AI assistant as a floating window",
                kind: .openCosmoWindow
            )
        ]
    }

    private func row(
        id: String,
        title: String,
        subtitle: String,
        kind: CommandKActionKind
    ) -> CommandKUserCommandRow {
        let action = CommandKAction(
            kind: kind,
            title: title,
            subtitle: subtitle,
            icon: "sparkles",
            payload: CommandKActionPayload(rawText: "cosmo")
        )
        return CommandKUserCommandRow(
            id: id,
            title: title,
            subtitle: "System · Cosmo",
            icon: action.icon,
            action: action
        )
    }

    private func matchesCosmoQuery(_ query: String) -> Bool {
        let normalized = Self.normalized(query)
        guard normalized.count >= 2 else { return false }

        if normalized == "ai" {
            return true
        }

        let prefixable = [
            "cosmo",
            "assistant",
            "agent",
            "open cosmo",
            "open ai",
            "cosmo pane",
            "cosmo window",
            "ai pane",
            "ai window"
        ]
        return prefixable.contains { candidate in
            candidate.hasPrefix(normalized) || normalized.hasPrefix(candidate)
        }
    }

    private static func normalized(_ raw: String) -> String {
        raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
