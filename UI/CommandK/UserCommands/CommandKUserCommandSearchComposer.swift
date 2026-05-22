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
        let normalizedQuery = Self.normalized(query)
        guard normalizedQuery.count >= 2 || normalizedQuery == "ai" else { return [] }

        return Self.commands
            .compactMap { command -> (row: CommandKUserCommandRow, score: Int)? in
                guard let score = command.matchScore(for: normalizedQuery) else { return nil }
                return (row: row(for: command), score: score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.row.title.localizedCaseInsensitiveCompare($1.row.title) == .orderedAscending
            }
            .map(\.row)
    }

    private struct SystemCommand {
        let id: String
        let title: String
        let subtitle: String
        let category: String
        let kind: CommandKActionKind
        let icon: String
        let payload: CommandKActionPayload
        let aliases: [String]

        func matchScore(for normalizedQuery: String) -> Int? {
            let normalizedAliases = aliases.map(CommandKSystemCommandComposer.normalized)
            let normalizedTitle = CommandKSystemCommandComposer.normalized(title)
            let searchable = ([normalizedTitle] + normalizedAliases).joined(separator: " ")

            if normalizedAliases.contains(normalizedQuery) || normalizedTitle == normalizedQuery {
                return 400
            }

            if normalizedAliases.contains(where: { $0.hasPrefix(normalizedQuery) }) ||
                normalizedTitle.hasPrefix(normalizedQuery) {
                return 300
            }

            if normalizedTitle
                .split(separator: " ")
                .contains(where: { $0.hasPrefix(normalizedQuery) }) {
                return 250
            }

            if searchable.contains(normalizedQuery) {
                return 100
            }

            return nil
        }
    }

    private static let commands: [SystemCommand] = [
        SystemCommand(
            id: "system-open-browser",
            title: "Open Browser",
            subtitle: "Open a persistent research browser pane",
            category: "Browser",
            kind: .openBrowser,
            icon: "globe",
            payload: CommandKActionPayload(rawText: "browser"),
            aliases: ["browser", "open browser", "web", "open web", "research browser", "browser pane"]
        ),
        SystemCommand(
            id: "system-command-center",
            title: "Go to Command Center",
            subtitle: "Open the planning dashboard",
            category: "Navigation",
            kind: .navigateCommandCenter,
            icon: "command.circle.fill",
            payload: CommandKActionPayload(rawText: "command center"),
            aliases: ["command center", "home", "plannerum", "planning", "sanctuary"]
        ),
        SystemCommand(
            id: "system-last-thinkspace",
            title: "Go to Thinkspace",
            subtitle: "Open the last-used canvas",
            category: "Navigation",
            kind: .navigateLastThinkspace,
            icon: "rectangle.3.group.fill",
            payload: CommandKActionPayload(rawText: "thinkspace"),
            aliases: ["thinkspace", "canvas", "last thinkspace"]
        ),
        SystemCommand(
            id: "system-open-library",
            title: "Open Library",
            subtitle: "Switch Command-K domain",
            category: "Domain",
            kind: .openDomain,
            icon: "tray.full.fill",
            payload: CommandKActionPayload(domain: "database", rawText: "library"),
            aliases: ["library", "database", "objects", "all objects"]
        ),
        SystemCommand(
            id: "system-open-swipe-gallery",
            title: "Open Swipe Gallery",
            subtitle: "Switch Command-K domain",
            category: "Domain",
            kind: .openDomain,
            icon: "bolt.fill",
            payload: CommandKActionPayload(domain: "swipeGallery", rawText: "swipes"),
            aliases: ["swipe gallery", "swipes", "swipe file", "swipe library"]
        ),
        SystemCommand(
            id: "system-open-ideas",
            title: "Open Ideas",
            subtitle: "Switch Command-K domain",
            category: "Domain",
            kind: .openDomain,
            icon: "lightbulb.fill",
            payload: CommandKActionPayload(domain: "ideas", rawText: "ideas"),
            aliases: ["ideas", "idea", "idea gallery"]
        ),
        SystemCommand(
            id: "system-open-readwise",
            title: "Open Readwise",
            subtitle: "Switch Command-K domain",
            category: "Domain",
            kind: .openDomain,
            icon: "books.vertical.fill",
            payload: CommandKActionPayload(domain: "readwise", rawText: "readwise"),
            aliases: ["readwise", "books", "book library", "highlights"]
        ),
        SystemCommand(
            id: "system-cosmo-pane",
            title: "Open Cosmo as Pane",
            subtitle: "Dock the AI assistant beside your workspace",
            category: "Cosmo",
            kind: .openCosmoPane,
            icon: "sparkles",
            payload: CommandKActionPayload(rawText: "cosmo pane"),
            aliases: ["cosmo", "assistant", "agent", "open cosmo", "open ai", "cosmo pane", "ai pane"]
        ),
        SystemCommand(
            id: "system-cosmo-window",
            title: "Open Cosmo Floating Window",
            subtitle: "Open the AI assistant as a floating window",
            category: "Cosmo",
            kind: .openCosmoWindow,
            icon: "sparkles",
            payload: CommandKActionPayload(rawText: "cosmo window"),
            aliases: ["cosmo window", "cosmo floating", "ai window", "ai floating", "assistant window"]
        )
    ]

    private func row(for command: SystemCommand) -> CommandKUserCommandRow {
        let action = CommandKAction(
            kind: command.kind,
            title: command.title,
            subtitle: command.subtitle,
            icon: command.icon,
            payload: command.payload
        )
        return CommandKUserCommandRow(
            id: command.id,
            title: command.title,
            subtitle: "System · \(command.category)",
            icon: action.icon,
            action: action
        )
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
