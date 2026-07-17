import Foundation
import os

enum CommandKActionKind: String, Equatable {
    case captureSwipe
    case captureSwipeWithIdea
    case captureLane
    case createCaptureLane
    case createIdea
    case createTask
    case createNote
    case captureResearch
    case createContent
    case createThinkspace
    case captureInbox
    case navigateCommandCenter
    case navigateLastThinkspace
    case openBrowser
    case openSwipeGallery
    case openDomain
    case openAtom
    case openThinkspace
    case savedSearch
    case openApp
    case openCosmoPane
    case openCosmoWindow
    case askCosmo
    case askCortex
    case calculator
}

struct CommandKActionPayload: Equatable {
    var url: String? = nil
    var title: String? = nil
    var body: String? = nil
    var destinationName: String? = nil
    var subroute: TelegramCaptureSubroute? = nil
    var clientName: String? = nil
    var ideaContext: String? = nil
    var hook: String? = nil
    var domain: String? = nil
    var atomUUID: String? = nil
    var thinkspaceID: String? = nil
    var queryText: String? = nil
    var quicklinkID: String? = nil
    var rawText: String? = nil
    /// Calculator: the formatted answer (what ⏎ copies) and the normalized
    /// expression it came from ("5 × 15,000").
    var resultText: String? = nil
    var expressionText: String? = nil
}

struct CommandKAction: Identifiable, Equatable {
    let kind: CommandKActionKind
    let title: String
    let subtitle: String?
    let icon: String
    let payload: CommandKActionPayload

    var scopedIdeaClientName: String? {
        guard kind == .createIdea else { return nil }
        let clientName = payload.clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clientName, !clientName.isEmpty else { return nil }
        return clientName
    }

    var scopedIdeaDraftText: String? {
        guard scopedIdeaClientName != nil else { return nil }
        let text = (payload.body ?? payload.title)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    var scopedIdeaPreviewText: String? {
        guard scopedIdeaClientName != nil else { return nil }
        return scopedIdeaDraftText ?? "Type the idea after :"
    }

    var scopedIdeaDestinationText: String? {
        guard let clientName = scopedIdeaClientName else { return nil }
        return "Save to \(clientName)'s ideas"
    }

    var id: String {
        let components: [String?]
        switch kind {
        case .captureSwipe, .captureSwipeWithIdea, .captureResearch:
            components = [kind.rawValue]
        case .captureLane:
            components = [kind.rawValue, payload.destinationName, payload.subroute?.rawValue]
        case .createCaptureLane:
            components = [kind.rawValue, payload.destinationName]
        case .createIdea:
            components = [kind.rawValue, payload.clientName]
        case .createTask, .createNote, .createContent, .createThinkspace, .captureInbox, .askCosmo, .askCortex:
            components = [kind.rawValue]
        case .calculator:
            // One stable id: the card keeps selection while the sum grows.
            components = [kind.rawValue]
        case .navigateCommandCenter, .navigateLastThinkspace, .openSwipeGallery, .openCosmoPane, .openCosmoWindow:
            components = [kind.rawValue]
        case .openBrowser:
            components = [kind.rawValue]
        case .openDomain:
            components = [kind.rawValue, payload.domain, payload.quicklinkID]
        case .openAtom:
            components = [kind.rawValue, payload.atomUUID, payload.quicklinkID]
        case .openThinkspace:
            components = [kind.rawValue, payload.thinkspaceID, payload.quicklinkID]
        case .savedSearch:
            components = [kind.rawValue, payload.queryText, payload.quicklinkID]
        case .openApp:
            components = [kind.rawValue, payload.title]
        }

        return components
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }

    /// Where this action lands, independent of how the row was authored.
    /// Quicklinks, system commands, and parsed primary actions that navigate
    /// to the same place share one key — the rail shows each destination once
    /// (unlike `id`, which keeps quicklink identity for selection/editing).
    /// nil = not a navigation (creation/capture actions never dedupe).
    var navigationTargetKey: String? {
        switch kind {
        case .openDomain:
            return payload.domain.map { "domain|\($0)" }
        case .openSwipeGallery:
            return "swipe-gallery-page"
        case .navigateCommandCenter:
            return "command-center"
        case .navigateLastThinkspace:
            return "last-thinkspace"
        case .openThinkspace:
            return payload.thinkspaceID.map { "thinkspace|\($0)" }
        case .openAtom:
            return payload.atomUUID.map { "atom|\($0)" }
        case .savedSearch:
            return payload.queryText.map {
                "search|\($0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        case .openBrowser:
            // Bare "open browser" is one destination; a URL/query search is
            // its own action every time.
            return (payload.url == nil && payload.queryText == nil) ? "browser" : nil
        case .openCosmoPane:
            return "cosmo-pane"
        case .openCosmoWindow:
            return "cosmo-window"
        case .openApp:
            return payload.title.map { "app|\($0.lowercased())" }
        default:
            return nil
        }
    }

    var isExecutable: Bool {
        switch kind {
        case .captureSwipe:
            return payload.url != nil
        case .captureSwipeWithIdea:
            return payload.url != nil
        case .captureLane:
            return payload.destinationName != nil && payload.body?.isEmpty == false
        case .createCaptureLane:
            return payload.destinationName != nil
        case .createIdea, .createTask, .createNote, .captureResearch, .createContent, .createThinkspace:
            return payload.title?.isEmpty == false || payload.body?.isEmpty == false || payload.url != nil
        case .captureInbox:
            return payload.body?.isEmpty == false
        case .navigateCommandCenter, .navigateLastThinkspace, .openBrowser, .openSwipeGallery, .openDomain:
            return true
        case .openAtom:
            return payload.atomUUID?.isEmpty == false
        case .openThinkspace:
            return payload.thinkspaceID?.isEmpty == false
        case .savedSearch:
            return payload.queryText?.isEmpty == false
        case .openApp:
            return payload.title?.isEmpty == false
        case .openCosmoPane, .openCosmoWindow:
            return true
        case .askCosmo, .askCortex:
            return payload.body?.isEmpty == false
        case .calculator:
            return payload.resultText?.isEmpty == false
        }
    }
}

enum CommandKVisualStyle: String, Equatable {
    case document
    case browser
    case swipeFile
    /// Browse Swipes — the shelf you flick through inside Command-K.
    case swipeShelf
    /// Open Swipe Gallery — the full-screen gallery page.
    case swipeGalleryPage
    case cosmo
    case commandCenter
    case thinkspace
    case domain
    case app
    case search
    case idea
    case task
    case research
    case content
    case connection
    case image
    case readwise
    case calculator
}

struct CommandKVisualIdentity: Equatable {
    let style: CommandKVisualStyle
    let symbolName: String
    let title: String
    let subtitle: String
    let badge: String

    static func action(_ action: CommandKAction) -> CommandKVisualIdentity {
        switch action.kind {
        case .captureSwipe, .captureSwipeWithIdea:
            return CommandKVisualIdentity(
                style: .swipeFile,
                symbolName: "bolt",
                title: "Swipe File",
                subtitle: "Hook capture",
                badge: "SWIPE"
            )
        case .captureLane, .createCaptureLane, .captureResearch:
            return CommandKVisualIdentity(
                style: .research,
                symbolName: action.icon,
                title: "Research",
                subtitle: "Capture route",
                badge: "SRC"
            )
        case .createIdea:
            return atom(type: .idea)
        case .createTask:
            return atom(type: .task)
        case .createNote:
            return atom(type: .note)
        case .createContent:
            return atom(type: .content)
        case .captureInbox:
            return CommandKVisualIdentity(
                style: .research,
                symbolName: "tray.and.arrow.down",
                title: "Inbox",
                subtitle: "Capture for triage",
                badge: "INBOX"
            )
        case .createThinkspace, .navigateLastThinkspace, .openThinkspace:
            return CommandKVisualIdentity(
                style: .thinkspace,
                symbolName: "rectangle.3.group",
                title: "Thinkspace",
                subtitle: "Canvas workspace",
                badge: "SPACE"
            )
        case .navigateCommandCenter:
            return CommandKVisualIdentity(
                style: .commandCenter,
                symbolName: "command",
                title: "Command Center",
                subtitle: "Planning dashboard",
                badge: "HOME"
            )
        case .openBrowser:
            return CommandKVisualIdentity(
                style: .browser,
                symbolName: "safari",
                title: "Browser",
                subtitle: "Research pane",
                badge: "WEB"
            )
        case .openSwipeGallery:
            return CommandKVisualIdentity(style: .swipeGalleryPage, symbolName: "rectangle.stack", title: "Swipe Gallery", subtitle: "All Swipes", badge: "OPEN")
        case .openDomain:
            return domain(action.payload.domain, title: action.title, symbolName: action.icon)
        case .openAtom:
            return CommandKVisualIdentity(
                style: .document,
                symbolName: "arrow.up.left.and.arrow.down.right",
                title: "Object",
                subtitle: "Focus surface",
                badge: "OPEN"
            )
        case .savedSearch:
            return CommandKVisualIdentity(
                style: .search,
                symbolName: "magnifyingglass",
                title: "Saved Search",
                subtitle: action.payload.queryText ?? "Search",
                badge: "FIND"
            )
        case .openApp:
            return CommandKVisualIdentity(
                style: .app,
                symbolName: "app",
                title: "App",
                subtitle: action.payload.title ?? "macOS app",
                badge: "APP"
            )
        case .askCortex:
            return CommandKVisualIdentity(
                style: .cosmo,
                symbolName: "circle.hexagongrid.circle",
                title: "Cortex",
                subtitle: "Answer from your knowledge",
                badge: "RECALL"
            )
        case .calculator:
            return CommandKVisualIdentity(
                style: .calculator,
                symbolName: "plus.forwardslash.minus",
                title: "Calculator",
                subtitle: action.payload.expressionText ?? "Instant math",
                badge: "CALC"
            )
        case .openCosmoPane, .openCosmoWindow, .askCosmo:
            return CommandKVisualIdentity(
                style: .cosmo,
                symbolName: "sparkles",
                title: "Cosmo",
                subtitle: "AI assistant",
                badge: "AI"
            )
        }
    }

    static func result(_ result: UnifiedSearchResult) -> CommandKVisualIdentity {
        switch result.resultKind {
        case .browserPin:
            return CommandKVisualIdentity(
                style: .browser,
                symbolName: result.icon,
                title: "Browser",
                subtitle: result.browserTitle ?? result.subtitle ?? "Browser Favorite",
                badge: "WEB"
            )
        case .thinkspace:
            return CommandKVisualIdentity(
                style: .thinkspace,
                symbolName: result.icon,
                title: "Thinkspace",
                subtitle: result.subtitle ?? "Canvas workspace",
                badge: "SPACE"
            )
        case .readwise:
            return CommandKVisualIdentity(
                style: .readwise,
                symbolName: result.icon,
                title: "Library",
                subtitle: result.subtitle ?? "Readwise",
                badge: "BOOK"
            )
        case .atom, .project:
            if result.source == .swipes {
                return CommandKVisualIdentity(
                    style: .swipeFile,
                    symbolName: "bolt",
                    title: "Swipe File",
                    subtitle: result.subtitle ?? "Hook capture",
                    badge: "SWIPE"
                )
            }
            if result.source == .ideas {
                return atom(type: .idea)
            }
            return result.atomType.map(atom(type:)) ?? CommandKVisualIdentity(
                style: .document,
                symbolName: result.icon,
                title: result.source.displayName,
                subtitle: result.subtitle ?? "Object",
                badge: "OPEN"
            )
        }
    }

    static func atom(type: AtomType) -> CommandKVisualIdentity {
        switch type {
        case .idea:
            return CommandKVisualIdentity(style: .idea, symbolName: "lightbulb", title: "Idea", subtitle: "Spark", badge: "IDEA")
        case .task:
            return CommandKVisualIdentity(style: .task, symbolName: "checkmark.circle", title: "Task", subtitle: "Next action", badge: "TASK")
        case .research:
            return CommandKVisualIdentity(style: .research, symbolName: "doc.text.magnifyingglass", title: "Research", subtitle: "Source", badge: "SRC")
        case .content:
            // The library's kind mark (doc.richtext) — one content identity
            // everywhere; the paper plane read as "send", not "writing".
            return CommandKVisualIdentity(style: .content, symbolName: "doc.richtext", title: "Content", subtitle: "Writing", badge: "POST")
        case .note:
            return CommandKVisualIdentity(style: .document, symbolName: "doc.text", title: "Note", subtitle: "Page", badge: "NOTE")
        case .connection:
            return CommandKVisualIdentity(style: .connection, symbolName: "point.3.connected.trianglepath.dotted", title: "Concept", subtitle: "Relationship", badge: "LINK")
        case .image:
            return CommandKVisualIdentity(style: .image, symbolName: "photo", title: "Image", subtitle: "Visual", badge: "IMG")
        case .thinkspace:
            return CommandKVisualIdentity(style: .thinkspace, symbolName: "rectangle.3.group", title: "Thinkspace", subtitle: "Canvas workspace", badge: "SPACE")
        default:
            return CommandKVisualIdentity(style: .document, symbolName: type.iconName, title: type.displayName, subtitle: "Object", badge: "OPEN")
        }
    }

    private static func domain(_ rawDomain: String?, title: String, symbolName: String) -> CommandKVisualIdentity {
        switch rawDomain {
        case "swipeGallery":
            return CommandKVisualIdentity(style: .swipeShelf, symbolName: "rectangle.stack", title: "Swipe File", subtitle: "Captures and hooks", badge: "BROWSE")
        case "ideas":
            return CommandKVisualIdentity(style: .idea, symbolName: "lightbulb", title: "Ideas", subtitle: "Sparks and notes", badge: "IDEA")
        case "readwise":
            return CommandKVisualIdentity(style: .readwise, symbolName: "books.vertical", title: "Library", subtitle: "Books and highlights", badge: "BOOK")
        case "database":
            return CommandKVisualIdentity(style: .domain, symbolName: "tray.full", title: "Database", subtitle: "All objects", badge: "DB")
        default:
            return CommandKVisualIdentity(style: .domain, symbolName: symbolName, title: title, subtitle: "Command-K domain", badge: "OPEN")
        }
    }
}

enum CommandKActionExecutionError: LocalizedError {
    case appNotFound(String)
    case clientNotFound(String)
    case missingIdeaText

    var errorDescription: String? {
        switch self {
        case .appNotFound(let appName):
            return "Couldn't find an app named \(appName)."
        case .clientNotFound(let clientName):
            return "Couldn't find a client named \(clientName)."
        case .missingIdeaText:
            return "Type the idea text first."
        }
    }
}

enum CommandKActionParser {
    private static let creationPrefixes: [(prefix: String, kind: CommandKActionKind, title: String, icon: String)] = [
        ("!task:", .createTask, "Create task", "checkmark.circle"),
        ("task:", .createTask, "Create task", "checkmark.circle"),
        ("!idea:", .createIdea, "Create idea", "lightbulb"),
        ("idea:", .createIdea, "Create idea", "lightbulb"),
        ("research:", .captureResearch, "Capture research", "doc.text.magnifyingglass"),
        ("content:", .createContent, "Create content", "doc.richtext"),
        ("thinkspace:", .createThinkspace, "Create Thinkspace", "rectangle.3.group")
    ]

    private static let reservedLanePrefixes: Set<String> = [
        "inbox",
        "note",
        "new",
        "create",
        "idea",
        "save idea",
        "new idea",
        "capture idea",
        "task",
        "todo",
        "to do",
        "swipe",
        "research",
        "content",
        "lesson",
        "rule",
        "current",
        "current inquiry",
        "inquiry",
        "thinkspace"
    ]

    private static let captureSignals = [
        "swipe",
        "capture",
        "save this",
        "save that",
        "grab this",
        "snag this",
        "file this",
        "add to swipes",
        "swipe this"
    ]

    static func parse(_ rawQuery: String) -> CommandKAction? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Math wins outright — the detector is strict (digits + operators
        // only), so nothing wordy ever lands here.
        if let calculator = parseCalculator(trimmed) {
            return calculator
        }

        if let cortex = parseAskCortex(trimmed) {
            return cortex
        }

        if let navigation = parseNavigation(trimmed) {
            return navigation
        }

        if let browser = parseBrowser(trimmed) {
            return browser
        }

        if let scopedIdea = parseScopedIdeaCapture(trimmed) {
            return scopedIdea
        }

        if let domain = parseDomain(trimmed) {
            return domain
        }

        if let app = parseAppOpen(trimmed) {
            return app
        }

        if let cosmoSurface = parseCosmoSurface(trimmed) {
            return cosmoSurface
        }

        if let creation = parseCreation(trimmed) {
            return creation
        }

        if let bareCreation = parseBareCreation(trimmed) {
            return bareCreation
        }

        if let swipeWithIdea = parseSwipeWithIdea(trimmed) {
            return swipeWithIdea
        }

        if let swipe = parseSwipe(trimmed) {
            return swipe
        }

        if let urlCapture = parseURLCapture(trimmed) {
            return urlCapture
        }

        if let lane = parseCaptureLane(trimmed) {
            return lane
        }

        if let ask = parseAskCosmo(trimmed) {
            return ask
        }

        return nil
    }

    /// "5 x 15,000" → the Raycast calculator card. The action's title is the
    /// verb (it labels the ⏎ button in the action bar); the card and detail
    /// pane draw from the payload's expression/result pair.
    private static func parseCalculator(_ text: String) -> CommandKAction? {
        guard let calculation = CommandKCalculator.evaluate(text) else { return nil }
        return CommandKAction(
            kind: .calculator,
            title: "Copy Result",
            subtitle: "\(calculation.expressionDisplay) = \(calculation.resultDisplay)",
            icon: "plus.forwardslash.minus",
            payload: CommandKActionPayload(
                rawText: text,
                resultText: calculation.resultDisplay,
                expressionText: calculation.expressionDisplay
            )
        )
    }

    private static func parseNavigation(_ text: String) -> CommandKAction? {
        switch normalizedAlias(text) {
        case "home", "command center", "plannerum", "planning", "sanctuary":
            return CommandKAction(
                kind: .navigateCommandCenter,
                title: "Go to Command Center",
                subtitle: "Open the planning dashboard",
                icon: "command.circle.fill",
                payload: CommandKActionPayload(rawText: text)
            )
        case "thinkspace", "canvas", "last thinkspace":
            return CommandKAction(
                kind: .navigateLastThinkspace,
                title: "Go to Thinkspace",
                subtitle: "Open the last-used canvas",
                icon: "rectangle.3.group.fill",
                payload: CommandKActionPayload(rawText: text)
            )
        default:
            return nil
        }
    }

    private static func parseBrowser(_ text: String) -> CommandKAction? {
        let normalized = normalizedAlias(text)
        let launchAliases: Set<String> = ["browser", "open browser", "web", "open web"]
        if launchAliases.contains(normalized) ||
            (normalized.count >= 3 && launchAliases.contains { $0.hasPrefix(normalized) }) {
            return CommandKAction(
                kind: .openBrowser,
                title: "Open Browser",
                subtitle: "Open a persistent research browser pane",
                icon: "globe",
                payload: CommandKActionPayload(rawText: text)
            )
        }

        let lower = text.lowercased()
        let prefixes = ["browser ", "open browser ", "web ", "search web "]
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        let remainder = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }

        if let url = firstURL(in: remainder), url == remainder {
            return CommandKAction(
                kind: .openBrowser,
                title: "Open Browser",
                subtitle: url,
                icon: "globe",
                payload: CommandKActionPayload(url: url, rawText: text)
            )
        }

        return CommandKAction(
            kind: .openBrowser,
            title: "Search Web",
            subtitle: remainder,
            icon: "magnifyingglass",
            payload: CommandKActionPayload(queryText: remainder, rawText: text)
        )
    }

    private static func parseDomain(_ text: String) -> CommandKAction? {
        let normalized = normalizedAlias(text)
        let domain: (String, String, String)?
        switch normalized {
        case "library", "database":
            domain = ("database", "Open Library", "tray.full.fill")
        case "swipe gallery", "swipes", "swipe library":
            domain = ("swipeGallery", "Browse Swipes", "bolt.fill")
        case "ideas":
            domain = ("ideas", "Open Ideas", "lightbulb")
        case "readwise", "books":
            domain = ("readwise", "Open Readwise", "books.vertical.fill")
        default:
            domain = nil
        }

        guard let domain else { return nil }
        return CommandKAction(
            kind: .openDomain,
            title: domain.1,
            subtitle: "Switch Command-K domain",
            icon: domain.2,
            payload: CommandKActionPayload(domain: domain.0, rawText: text)
        )
    }

    private static func parseScopedIdeaCapture(_ text: String) -> CommandKAction? {
        let lower = text.lowercased()
        let legacyPrefix = "idea for "
        if lower.hasPrefix(legacyPrefix) {
            let remainder = String(text.dropFirst(legacyPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let delimiterIndex = remainder.firstIndex(of: ":") else {
                return nil
            }

            return scopedIdeaCapture(from: remainder, delimiterIndex: delimiterIndex, rawText: text)
        }

        let shorthandPrefix = "idea "
        guard lower.hasPrefix(shorthandPrefix) else {
            return nil
        }

        let remainder = String(text.dropFirst(shorthandPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return nil }

        if let delimiterIndex = remainder.firstIndex(of: ":") {
            return scopedIdeaCapture(from: remainder, delimiterIndex: delimiterIndex, rawText: text)
        }

        return makeScopedIdeaCapture(clientName: remainder, content: "", rawText: text)
    }

    private static func scopedIdeaCapture(
        from remainder: String,
        delimiterIndex: String.Index,
        rawText: String
    ) -> CommandKAction? {
        let clientName = String(remainder[..<delimiterIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientName.isEmpty else { return nil }

        let contentStart = remainder.index(after: delimiterIndex)
        let content = String(remainder[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return makeScopedIdeaCapture(clientName: clientName, content: content, rawText: rawText)
    }

    private static func makeScopedIdeaCapture(
        clientName: String,
        content: String,
        rawText: String
    ) -> CommandKAction? {
        let trimmedClientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientName.isEmpty else { return nil }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        return CommandKAction(
            kind: .createIdea,
            title: "Create idea for \(trimmedClientName)",
            subtitle: trimmedContent.isEmpty ? "For \(trimmedClientName) · Type the idea after :" : "For \(trimmedClientName) · \(trimmedContent)",
            icon: "lightbulb",
            payload: CommandKActionPayload(
                title: trimmedContent.isEmpty ? nil : trimmedContent,
                body: trimmedContent.isEmpty ? nil : trimmedContent,
                clientName: trimmedClientName,
                rawText: rawText
            )
        )
    }

    /// One bare-keyword composer entry point ("task", "note", "new idea …").
    struct BareCreationShape {
        let kind: CommandKActionKind
        let keywords: [String]
        let title: String
        let icon: String
        /// Trailing text after the keyword prefills this payload slot.
        let prefillsBody: Bool

        static let all: [BareCreationShape] = [
            BareCreationShape(kind: .createTask, keywords: ["task", "todo"], title: "Create task", icon: "checkmark.circle", prefillsBody: false),
            BareCreationShape(kind: .createNote, keywords: ["note"], title: "Create note", icon: "doc.text", prefillsBody: false),
            // Bare "idea" only — "idea <text>" is the scoped client-capture
            // grammar (parseScopedIdeaCapture claims it first).
            BareCreationShape(kind: .createIdea, keywords: ["idea"], title: "Create idea", icon: "lightbulb", prefillsBody: false),
            BareCreationShape(kind: .captureInbox, keywords: ["capture", "inbox"], title: "Capture to Inbox", icon: "tray.and.arrow.down.fill", prefillsBody: true),
            BareCreationShape(kind: .createContent, keywords: ["content"], title: "Create content", icon: "doc.richtext", prefillsBody: false),
            BareCreationShape(kind: .captureSwipe, keywords: ["swipe"], title: "Capture swipe", icon: "bolt.fill", prefillsBody: false),
        ]
    }

    /// Bare creation keywords open the composer panel: "task" (and "task buy
    /// filters"), "note", "idea", "capture", "content", "swipe", plus the
    /// verb forms "new <shape> …" / "create <shape> …". URLs fall through to
    /// the capture parsers, and single-word "new"/"create" fall through to
    /// the system-command menu that lists every shape.
    private static func parseBareCreation(_ text: String) -> CommandKAction? {
        guard firstURL(in: text) == nil else { return nil }

        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = working.lowercased()
        var verbStripped = false
        for verb in ["new ", "create "] where lower.hasPrefix(verb) {
            working = String(working.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
            verbStripped = true
            break
        }
        guard !working.isEmpty else { return nil }

        let workingLower = working.lowercased()
        for shape in BareCreationShape.all {
            for keyword in shape.keywords {
                let trailing: String
                if workingLower == keyword {
                    trailing = ""
                } else if workingLower.hasPrefix(keyword + " ") {
                    trailing = String(working.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                } else {
                    continue
                }

                // The scoped-idea and swipe grammars own bare trailing text
                // for these shapes ("idea Euan: …", "swipe <url>"); an
                // explicit verb ("new idea morning hooks") is unambiguous.
                if !trailing.isEmpty, !verbStripped,
                   shape.kind == .createIdea || shape.kind == .captureSwipe {
                    return nil
                }

                return bareCreationAction(shape: shape, trailing: trailing, rawText: text)
            }
        }
        return nil
    }

    private static func bareCreationAction(
        shape: BareCreationShape,
        trailing: String,
        rawText: String
    ) -> CommandKAction {
        var payload = CommandKActionPayload(rawText: rawText)
        if !trailing.isEmpty {
            if shape.prefillsBody {
                payload.body = trailing
            } else {
                payload.title = trailing
            }
        }
        return CommandKAction(
            kind: shape.kind,
            title: shape.title,
            subtitle: trailing.isEmpty ? "Fill in the panel — Tab to start" : trailing,
            icon: shape.icon,
            payload: payload
        )
    }

    private static func parseAppOpen(_ text: String) -> CommandKAction? {
        let lower = text.lowercased()
        let prefixes = ["app:", "open app "]
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        let appName = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else {
            return CommandKAction(
                kind: .openApp,
                title: "Open app",
                subtitle: "Type an app name",
                icon: "app.fill",
                payload: CommandKActionPayload(rawText: text)
            )
        }

        return CommandKAction(
            kind: .openApp,
            title: "Open \(appName)",
            subtitle: "Launch macOS app",
            icon: "app.fill",
            payload: CommandKActionPayload(title: appName, rawText: text)
        )
    }

    private static func parseCosmoSurface(_ text: String) -> CommandKAction? {
        switch normalizedAlias(text) {
        case "cosmo pane", "open cosmo pane", "cosmo as pane", "open cosmo as pane",
             "ai pane", "open ai pane", "ai as pane", "open ai as pane":
            return CommandKAction(
                kind: .openCosmoPane,
                title: "Open Cosmo as Pane",
                subtitle: "Dock the AI assistant beside your workspace",
                icon: "sparkles",
                payload: CommandKActionPayload(rawText: text)
            )
        case "cosmo window", "open cosmo window", "cosmo floating", "open cosmo floating",
             "cosmo floating window", "open cosmo floating window",
             "ai window", "open ai window", "ai floating", "open ai floating",
             "ai floating window", "open ai floating window":
            return CommandKAction(
                kind: .openCosmoWindow,
                title: "Open Cosmo Floating Window",
                subtitle: "Open the AI assistant as a floating window",
                icon: "sparkles",
                payload: CommandKActionPayload(rawText: text)
            )
        default:
            return nil
        }
    }

    private static func parseCreation(_ text: String) -> CommandKAction? {
        let lower = text.lowercased()
        for entry in creationPrefixes where lower.hasPrefix(entry.prefix) {
            let content = String(text.dropFirst(entry.prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                return CommandKAction(
                    kind: entry.kind,
                    title: entry.title,
                    subtitle: "Type the text after \(entry.prefix)",
                    icon: entry.icon,
                    payload: CommandKActionPayload(rawText: text)
                )
            }

            let payload: CommandKActionPayload
            if entry.kind == .captureResearch, let url = firstURL(in: content) {
                payload = CommandKActionPayload(url: url, title: content, body: content, rawText: text)
            } else {
                payload = CommandKActionPayload(title: content, body: content, rawText: text)
            }

            return CommandKAction(
                kind: entry.kind,
                title: entry.title,
                subtitle: content,
                icon: entry.icon,
                payload: payload
            )
        }

        return nil
    }

    private static func parseSwipeWithIdea(_ text: String) -> CommandKAction? {
        guard let request = SwipeIdeaCaptureParser.parse(text) else { return nil }
        let title = request.title.map { "Swipe + idea: \($0)" } ?? "Swipe this and create an idea"
        let subtitle = [request.clientName, request.ideaContext, request.url]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")

        return CommandKAction(
            kind: .captureSwipeWithIdea,
            title: title,
            subtitle: subtitle.isEmpty ? request.url : subtitle,
            icon: "bolt.badge.plus.fill",
            payload: CommandKActionPayload(
                url: request.url,
                title: request.title,
                clientName: request.clientName,
                ideaContext: request.ideaContext,
                rawText: text
            )
        )
    }

    private static func parseSwipe(_ text: String) -> CommandKAction? {
        let lower = text.lowercased()
        if normalizedAlias(text) == "swipe" {
            return CommandKAction(
                kind: .captureSwipe,
                title: "Swipe a link",
                subtitle: "Paste a URL to save it to Swipe Gallery",
                icon: "bolt.fill",
                payload: CommandKActionPayload(rawText: text)
            )
        }

        let candidate: String
        if lower.hasPrefix("!swipe:") {
            candidate = String(text.dropFirst("!swipe:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            candidate = text
        }

        guard let url = firstURL(in: candidate) else { return nil }
        let hasCaptureSignal = lower.hasPrefix("!swipe:") || captureSignals.contains { lower.contains($0) }
        guard hasCaptureSignal else { return nil }

        return CommandKAction(
            kind: .captureSwipe,
            title: "Swipe this link",
            subtitle: url,
            icon: "bolt.fill",
            payload: CommandKActionPayload(url: url, rawText: text)
        )
    }

    private static func parseURLCapture(_ text: String) -> CommandKAction? {
        guard let url = firstURL(in: text) else { return nil }
        let classification = SwipeURLClassifier().classify(url)
        guard classification.isUrl else { return nil }

        if isSwipeSource(classification.sourceType) {
            return CommandKAction(
                kind: .captureSwipe,
                title: "Capture Swipe",
                subtitle: url,
                icon: "bolt.fill",
                payload: CommandKActionPayload(url: url, rawText: text)
            )
        }

        return CommandKAction(
            kind: .captureResearch,
            title: "Capture Research",
            subtitle: url,
            icon: "doc.text.magnifyingglass",
            payload: CommandKActionPayload(url: url, title: url, body: text, rawText: text)
        )
    }

    private static func isSwipeSource(_ sourceType: ResearchRichContent.SourceType) -> Bool {
        switch sourceType {
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel,
             .youtube, .youtubeShort, .xPost, .twitter, .threads, .tiktok, .loom:
            return true
        default:
            return false
        }
    }

    private static func parseCaptureLane(_ text: String) -> CommandKAction? {
        guard let command = TelegramCaptureCommandParser.parse(text, allowsEmptyBody: false) else { return nil }
        let normalizedDestination = normalizedAlias(command.destinationName)
        guard !reservedLanePrefixes.contains(normalizedDestination) else { return nil }

        switch command.kind {
        case .route:
            let subrouteSuffix = command.subroute == .general ? "" : " · \(command.subroute.rawValue)"
            return CommandKAction(
                kind: .captureLane,
                title: "Route to \(command.destinationName)",
                subtitle: "\(command.body)\(subrouteSuffix)",
                icon: command.subroute.iconName,
                payload: CommandKActionPayload(
                    body: command.body,
                    destinationName: command.destinationName,
                    subroute: command.subroute,
                    rawText: text
                )
            )
        case .createLane:
            return CommandKAction(
                kind: .createCaptureLane,
                title: "Create capture lane",
                subtitle: command.destinationName,
                icon: command.requestedLaneType?.defaultIcon ?? "tray.and.arrow.down.fill",
                payload: CommandKActionPayload(
                    body: command.body,
                    destinationName: command.destinationName,
                    subroute: command.subroute,
                    rawText: text
                )
            )
        }
    }

    /// `?<question>` (or `recall: <question>`) — answer from the user's own
    /// knowledge base with citations, honestly gated when the cortex is empty.
    private static func parseAskCortex(_ text: String) -> CommandKAction? {
        var body: String?
        if text.hasPrefix("?") {
            body = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.lowercased().hasPrefix("recall:") {
            body = String(text.dropFirst("recall:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let body, !body.isEmpty else { return nil }
        return CommandKAction(
            kind: .askCortex,
            title: "Ask your cortex",
            subtitle: body,
            icon: "circle.hexagongrid.circle",
            payload: CommandKActionPayload(body: body, rawText: text)
        )
    }

    private static func parseAskCosmo(_ text: String) -> CommandKAction? {
        let lower = text.lowercased()
        let prefixes = ["ask:", "cosmo:"]
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        let body = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return CommandKAction(
            kind: .askCosmo,
            title: "Ask Cosmo",
            subtitle: body,
            icon: "sparkles",
            payload: CommandKActionPayload(body: body, rawText: text)
        )
    }

    private static func firstURL(in text: String) -> String? {
        let pattern = try? NSRegularExpression(pattern: #"https?://[^\s]+"#)
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = pattern?.firstMatch(in: text, range: nsRange),
              let range = Range(match.range, in: text) else {
            return nil
        }

        return String(text[range])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,);]"))
    }

    private static func normalizedAlias(_ raw: String) -> String {
        raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[“”]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension TelegramCaptureSubroute {
    var iconName: String {
        switch self {
        case .general: return "tray.and.arrow.down.fill"
        case .source: return "doc.richtext"
        case .question: return "questionmark.circle.fill"
        case .evidence: return "checkmark.seal.fill"
        case .counterevidence: return "exclamationmark.triangle.fill"
        case .claim: return "quote.bubble.fill"
        case .practice: return "figure.mind.and.body"
        case .term: return "text.book.closed.fill"
        case .output: return "paperplane"
        case .image: return "photo.fill"
        case .file: return "doc.fill"
        case .note: return "note.text"
        case .task: return "checklist"
        }
    }
}

actor CommandKSearchPipeline {
    private var currentRequest = CommandKSearchRequestID()

    func nextRequestID() -> CommandKSearchRequestID {
        currentRequest = CommandKSearchRequestID()
        return currentRequest
    }

    func isCurrent(_ requestID: CommandKSearchRequestID) -> Bool {
        requestID == currentRequest
    }
}

struct CommandKSearchRequestID: Equatable, Sendable {
    private let rawValue = UUID()
}

/// One-edit typo tolerance (Damerau-Levenshtein distance ≤ 1: substitution,
/// insertion, deletion, or adjacent transposition) with an early-exit
/// single-pass check — no distance matrix, safe to run over the instant
/// index's titles.
enum CommandKTypoTolerance {
    static func isWithinOneEdit(_ a: Substring, _ b: Substring) -> Bool {
        if a == b { return true }
        let lengthDelta = a.count - b.count
        guard abs(lengthDelta) <= 1 else { return false }

        let aChars = Array(a)
        let bChars = Array(b)

        if lengthDelta == 0 {
            // Same length: one substitution, or one adjacent transposition.
            for index in aChars.indices where aChars[index] != bChars[index] {
                if index + 1 < aChars.count,
                   aChars[index] == bChars[index + 1],
                   aChars[index + 1] == bChars[index] {
                    // Transposition — everything after the swapped pair must
                    // match exactly.
                    return Array(aChars[(index + 2)...]) == Array(bChars[(index + 2)...])
                }
                // Substitution — everything after it must match exactly.
                return Array(aChars[(index + 1)...]) == Array(bChars[(index + 1)...])
            }
            return true
        }

        // Length differs by one: one insertion/deletion.
        let (longer, shorter) = aChars.count > bChars.count ? (aChars, bChars) : (bChars, aChars)
        var longIndex = 0
        var shortIndex = 0
        var skipped = false
        while longIndex < longer.count && shortIndex < shorter.count {
            if longer[longIndex] == shorter[shortIndex] {
                longIndex += 1
                shortIndex += 1
            } else if skipped {
                return false
            } else {
                skipped = true
                longIndex += 1
            }
        }
        return true
    }

    /// Query-token-vs-title-token match: exact-length tolerance, or the same
    /// tolerance against the title token's prefix so mid-typing typos
    /// ("retreiv" while writing "retrieval") still connect.
    static func fuzzyMatches(_ queryToken: Substring, titleToken: Substring) -> Bool {
        if isWithinOneEdit(queryToken, titleToken) { return true }
        if titleToken.count > queryToken.count {
            return isWithinOneEdit(queryToken, titleToken.prefix(queryToken.count))
        }
        return false
    }
}

struct CommandKSearchIndex: Sendable {
    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let atomUUID: String
        let atomType: AtomType
        let title: String
        let snippet: String?
        let updatedAt: String
        let searchableText: String
        let normalizedTitle: String
        let recencyWeight: Double

        init(
            id: String,
            atomUUID: String,
            atomType: AtomType,
            title: String,
            snippet: String?,
            updatedAt: String,
            metadata: String? = nil
        ) {
            self.id = id
            self.atomUUID = atomUUID
            self.atomType = atomType
            self.title = title
            self.snippet = snippet
            self.updatedAt = updatedAt
            self.searchableText = CommandKSearchMatcher.searchableText(from: [
                title,
                snippet,
                metadata,
                atomType.rawValue
            ])
            self.normalizedTitle = CommandKSearchMatcher.normalize(title)
            self.recencyWeight = WeightCalculator.recencyWeight(fromISO8601: updatedAt)
        }
    }

    private(set) var entries: [Entry] = []

    mutating func replace(_ entries: [Entry]) {
        self.entries = entries
    }

    mutating func replace(atoms: [Atom]) {
        entries = Self.entries(for: atoms)
    }

    /// Entry construction normalizes each atom's full title/body/metadata text
    /// — call this off the main actor for large batches.
    static func entries(for atoms: [Atom]) -> [Entry] {
        atoms.map { atom in
            Entry(
                id: atom.uuid,
                atomUUID: atom.uuid,
                atomType: atom.type,
                title: atom.title ?? "Untitled",
                snippet: atom.body,
                updatedAt: atom.updatedAt,
                metadata: atom.metadata
            )
        }
    }

    func search(_ query: String, limit: Int, shouldCancel: () -> Bool = { false }) -> [RankedResult] {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        guard !normalizedQuery.isEmpty else { return [] }

        // Explicitly-quoted segments are hard requirements: an entry that
        // doesn't contain every quoted phrase verbatim is not a match, no
        // matter how many loose tokens it carries.
        let requiredPhrases = CommandKSearchMatcher.quotedPhrases(in: query)

        var matches: [RankedResult] = []
        matches.reserveCapacity(min(limit * 2, entries.count))

        for entry in entries {
            if shouldCancel() { return [] }
            if !requiredPhrases.isEmpty,
               !requiredPhrases.allSatisfy({ entry.searchableText.contains($0) }) {
                continue
            }
            let (tier, structural) = CommandKSearchMatcher.lexicalMatch(
                normalizedQuery: normalizedQuery,
                normalizedTitle: entry.normalizedTitle,
                normalizedFullText: entry.searchableText
            )
            guard structural > 0 else { continue }

            matches.append(RankedResult(
                atomUUID: entry.atomUUID,
                atomType: entry.atomType,
                title: entry.title,
                snippet: entry.snippet?.prefix(160).description,
                // Extraction walks the raw body only for the few body-tier
                // matches, never the whole 10k-entry scan.
                matchedExcerpt: tier >= .phraseInBody
                    ? CommandKMatchExcerpt.excerpt(from: entry.snippet, query: query)
                    : nil,
                semanticWeight: 0.0,
                structuralWeight: structural,
                recencyWeight: entry.recencyWeight,
                usageWeight: 0.5,
                lexicalTier: tier,
                updatedAt: entry.updatedAt
            ))
        }

        // Typo net: when strict matching leaves the list nearly empty and
        // the query is name-shaped (1–3 tokens of 4+ chars, no quoted
        // phrases), retry titles with one-edit tolerance so "retreival"
        // still finds "Retrieval notes". Ranked below every real title
        // match by quality; never runs when strict results are plentiful.
        if matches.count < 3, requiredPhrases.isEmpty {
            appendFuzzyTitleMatches(
                to: &matches,
                normalizedQuery: normalizedQuery,
                shouldCancel: shouldCancel
            )
        }

        return matches.sorted().prefix(limit).map { $0 }
    }

    private func appendFuzzyTitleMatches(
        to matches: inout [RankedResult],
        normalizedQuery: String,
        shouldCancel: () -> Bool
    ) {
        let queryTokens = normalizedQuery.split(separator: " ")
        guard (1...3).contains(queryTokens.count),
              queryTokens.allSatisfy({ $0.count >= 4 }) else { return }

        let matchedIDs = Set(matches.map(\.atomUUID))
        for entry in entries {
            if shouldCancel() { return }
            guard !matchedIDs.contains(entry.atomUUID) else { continue }
            let titleTokens = entry.normalizedTitle.split(separator: " ")
            guard !titleTokens.isEmpty else { continue }
            let everyTokenFuzzyMatches = queryTokens.allSatisfy { queryToken in
                titleTokens.contains { CommandKTypoTolerance.fuzzyMatches(queryToken, titleToken: $0) }
            }
            guard everyTokenFuzzyMatches else { continue }

            matches.append(RankedResult(
                atomUUID: entry.atomUUID,
                atomType: entry.atomType,
                title: entry.title,
                snippet: entry.snippet?.prefix(160).description,
                semanticWeight: 0.0,
                // Below every exact title match (0.64+) within the tier.
                structuralWeight: 0.5,
                recencyWeight: entry.recencyWeight,
                usageWeight: 0.5,
                lexicalTier: .titleMatch,
                updatedAt: entry.updatedAt
            ))
        }
    }
}

enum CommandKPerformanceInstrumentation {
    static let logger = Logger(subsystem: "com.cosmo.os", category: "CommandKPerformance")
    static let signposter = OSSignposter(subsystem: "com.cosmo.os", category: "CommandKPerformance")
}
