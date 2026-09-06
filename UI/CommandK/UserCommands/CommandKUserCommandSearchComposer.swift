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
                subtitle: "Open Space",
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
        case "swipeGallery": return "rectangle.stack.fill"
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
            .compactMap { command -> (row: CommandKUserCommandRow, score: Int, priority: Int)? in
                guard let score = command.matchScore(for: normalizedQuery) else { return nil }
                return (row: row(for: command), score: score, priority: command.priority)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
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
        var priority: Int = 0

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

    /// The creation shapes behind the bare "new" menu — the Mac's orb fan.
    /// Every entry answers "new"/"create", so typing either lists them all;
    /// priorities hold the orb-fan order (task first, nearest reach).
    private static let creationCommands: [SystemCommand] = [
        SystemCommand(
            id: "system-new-task",
            title: "New Task",
            subtitle: "Schedule, priority, and intent in the panel",
            category: "Create",
            kind: .createTask,
            icon: "checkmark.circle.fill",
            payload: CommandKActionPayload(rawText: "new task"),
            aliases: ["new", "create", "new task", "create task", "task"],
            priority: 106
        ),
        SystemCommand(
            id: "system-new-note",
            title: "New Page",
            subtitle: "Write freely, from a thought to a chapter",
            category: "Create",
            kind: .createNote,
            icon: "doc.text",
            payload: CommandKActionPayload(rawText: "new note"),
            aliases: ["new", "create", "new page", "create page", "page", "new note", "create note", "note"],
            priority: 105
        ),
        SystemCommand(
            id: "system-new-idea",
            title: "New Idea",
            subtitle: "Brand, format, hooks, and outline in the panel",
            category: "Create",
            kind: .createIdea,
            icon: "lightbulb.fill",
            payload: CommandKActionPayload(rawText: "new idea"),
            aliases: ["new", "create", "new idea", "create idea", "idea"],
            priority: 104
        ),
        SystemCommand(
            id: "system-new-capture",
            title: "New Capture",
            subtitle: "Lands in your Inbox for triage",
            category: "Create",
            kind: .captureInbox,
            icon: "tray.and.arrow.down.fill",
            payload: CommandKActionPayload(rawText: "new capture"),
            aliases: ["new", "create", "new capture", "capture", "inbox capture"],
            priority: 103
        ),
        SystemCommand(
            id: "system-new-content",
            title: "New Content",
            subtitle: "Start a draft in your content pipeline",
            category: "Create",
            kind: .createContent,
            icon: "paperplane.fill",
            payload: CommandKActionPayload(rawText: "new content"),
            aliases: ["new", "create", "new content", "create content", "content"],
            priority: 102
        ),
        SystemCommand(
            id: "system-new-swipe",
            title: "New Swipe",
            subtitle: "Capture a reel, post, or page by URL",
            category: "Create",
            kind: .captureSwipe,
            icon: "bolt.fill",
            payload: CommandKActionPayload(rawText: "new swipe"),
            aliases: ["new", "create", "new swipe", "capture swipe", "swipe"],
            priority: 101
        ),
        SystemCommand(
            id: "system-new-thinkspace",
            title: "New Space",
            subtitle: "Bring a subject, collection, or project together",
            category: "Create",
            kind: .createThinkspace,
            icon: "rectangle.3.group",
            payload: CommandKActionPayload(rawText: "new thinkspace"),
            aliases: ["new", "create", "new space", "create space", "new thinkspace", "create thinkspace"],
            priority: 100
        ),
    ]

    private static let compositionCommands: [SystemCommand] = [
        SystemCommand(id: "system-new-group", title: "New Group", subtitle: "Collect originals in a Space",
            category: "Create", kind: .createGroup, icon: "square.stack.3d.up",
            payload: CommandKActionPayload(rawText: "new group"), aliases: ["new", "create", "group", "new group", "create group"], priority: 99),
        SystemCommand(id: "system-new-book", title: "New Book", subtitle: "Start with editable Pages and chapters",
            category: "Create", kind: .createBook, icon: "book.closed",
            payload: CommandKActionPayload(rawText: "new book"), aliases: ["new", "create", "book", "new book", "create book"], priority: 98),
        SystemCommand(id: "system-new-course", title: "New Course", subtitle: "Start with editable modules and lessons",
            category: "Create", kind: .createCourse, icon: "play.rectangle.on.rectangle",
            payload: CommandKActionPayload(rawText: "new course"), aliases: ["new", "create", "course", "new course", "create course"], priority: 97),
        SystemCommand(id: "system-space-map", title: "Open Space map", subtitle: "Explore concepts and their connections",
            category: "Navigation", kind: .openSpaceMap, icon: "point.3.connected.trianglepath.dotted",
            payload: CommandKActionPayload(rawText: "space map"), aliases: ["map", "space map", "open map", "open space map"], priority: 22)
    ]

    private static let commands: [SystemCommand] = creationCommands + compositionCommands + [
        SystemCommand(
            id: "system-open-browser",
            title: "Open Browser",
            subtitle: "Open a persistent research browser pane",
            category: "Browser",
            kind: .openBrowser,
            icon: "globe",
            payload: CommandKActionPayload(rawText: "browser"),
            aliases: ["browser", "open browser", "web", "open web", "research browser", "browser pane"],
            priority: 20
        ),
        SystemCommand(
            id: "system-command-center",
            title: "Go to Command Center",
            subtitle: "Open the planning dashboard",
            category: "Navigation",
            kind: .navigateCommandCenter,
            icon: "command.circle.fill",
            payload: CommandKActionPayload(rawText: "command center"),
            // "today" rode a retired built-in quicklink to the same place.
            aliases: ["command center", "home", "today", "plannerum", "planning", "sanctuary"]
        ),
        SystemCommand(
            id: "system-last-thinkspace",
            title: "Open Space",
            subtitle: "Open this Space or choose a destination",
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
            subtitle: "Open All Swipes full screen",
            category: "Domain",
            kind: .openSwipeGallery,
            icon: "rectangle.stack.fill",
            payload: CommandKActionPayload(rawText: "open swipe gallery"),
            aliases: ["open swipe gallery", "swipe gallery", "all swipes", "full screen swipes"],
            priority: 10
        ),
        SystemCommand(
            id: "system-browse-swipes",
            title: "Browse Swipes",
            subtitle: "Browse swipes inside Command-K",
            category: "Domain",
            kind: .openDomain,
            icon: "rectangle.stack.fill",
            payload: CommandKActionPayload(domain: "swipeGallery", rawText: "swipes"),
            aliases: ["browse swipes", "swipes", "swipe file", "swipe library"],
            priority: 5
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
