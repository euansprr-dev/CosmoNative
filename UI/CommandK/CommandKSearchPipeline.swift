import Foundation
import os

enum CommandKActionKind: String, Equatable {
    case captureSwipe
    case captureSwipeWithIdea
    case captureLane
    case createCaptureLane
    case createIdea
    case createTask
    case captureResearch
    case createContent
    case createThinkspace
    case navigateCommandCenter
    case navigateLastThinkspace
    case openDomain
    case openAtom
    case openThinkspace
    case savedSearch
    case openApp
    case askCosmo
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
}

struct CommandKAction: Identifiable, Equatable {
    let kind: CommandKActionKind
    let title: String
    let subtitle: String?
    let icon: String
    let payload: CommandKActionPayload

    var id: String {
        [
            kind.rawValue,
            payload.url,
            payload.title,
            payload.destinationName,
            payload.subroute?.rawValue,
            payload.domain,
            payload.atomUUID,
            payload.thinkspaceID,
            payload.queryText,
            payload.quicklinkID,
            payload.body
        ]
        .compactMap { $0 }
        .joined(separator: "|")
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
        case .createIdea, .createTask, .captureResearch, .createContent, .createThinkspace:
            return payload.title?.isEmpty == false || payload.body?.isEmpty == false || payload.url != nil
        case .navigateCommandCenter, .navigateLastThinkspace, .openDomain:
            return true
        case .openAtom:
            return payload.atomUUID?.isEmpty == false
        case .openThinkspace:
            return payload.thinkspaceID?.isEmpty == false
        case .savedSearch:
            return payload.queryText?.isEmpty == false
        case .openApp:
            return payload.title?.isEmpty == false
        case .askCosmo:
            return payload.body?.isEmpty == false
        }
    }
}

enum CommandKActionExecutionError: LocalizedError {
    case appNotFound(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let appName):
            return "Couldn't find an app named \(appName)."
        }
    }
}

enum CommandKActionParser {
    private static let creationPrefixes: [(prefix: String, kind: CommandKActionKind, title: String, icon: String)] = [
        ("!task:", .createTask, "Create task", "checkmark.circle.fill"),
        ("task:", .createTask, "Create task", "checkmark.circle.fill"),
        ("!idea:", .createIdea, "Create idea", "lightbulb.fill"),
        ("idea:", .createIdea, "Create idea", "lightbulb.fill"),
        ("research:", .captureResearch, "Capture research", "doc.text.magnifyingglass"),
        ("content:", .createContent, "Create content", "paperplane.fill"),
        ("thinkspace:", .createThinkspace, "Create Thinkspace", "rectangle.3.group")
    ]

    private static let reservedLanePrefixes: Set<String> = [
        "inbox",
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

        if let navigation = parseNavigation(trimmed) {
            return navigation
        }

        if let domain = parseDomain(trimmed) {
            return domain
        }

        if let app = parseAppOpen(trimmed) {
            return app
        }

        if let creation = parseCreation(trimmed) {
            return creation
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

    private static func parseDomain(_ text: String) -> CommandKAction? {
        let normalized = normalizedAlias(text)
        let domain: (String, String, String)?
        switch normalized {
        case "library", "database":
            domain = ("database", "Open Library", "tray.full.fill")
        case "swipe gallery", "swipes", "swipe library":
            domain = ("swipeGallery", "Open Swipe Gallery", "bolt.fill")
        case "ideas":
            domain = ("ideas", "Open Ideas", "lightbulb.fill")
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
        case .output: return "paperplane.fill"
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

struct CommandKSearchIndex {
    struct Entry: Identifiable, Equatable {
        let id: String
        let atomUUID: String
        let atomType: AtomType
        let title: String
        let snippet: String?
        let updatedAt: String
        let searchableText: String

        init(
            id: String,
            atomUUID: String,
            atomType: AtomType,
            title: String,
            snippet: String?,
            updatedAt: String
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
                atomType.rawValue
            ])
        }
    }

    private(set) var entries: [Entry] = []

    mutating func replace(_ entries: [Entry]) {
        self.entries = entries
    }

    mutating func replace(atoms: [Atom]) {
        entries = atoms.map { atom in
            Entry(
                id: atom.uuid,
                atomUUID: atom.uuid,
                atomType: atom.type,
                title: atom.title ?? "Untitled",
                snippet: atom.body,
                updatedAt: atom.updatedAt
            )
        }
    }

    func search(_ query: String, limit: Int) -> [RankedResult] {
        let normalizedQuery = CommandKSearchMatcher.normalizeQuery(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return entries
            .compactMap { entry -> RankedResult? in
                guard entry.searchableText.contains(normalizedQuery) else { return nil }
                let normalizedTitle = CommandKSearchMatcher.normalize(entry.title)
                let structural: Double
                if normalizedTitle == normalizedQuery {
                    structural = 1.0
                } else if normalizedTitle.hasPrefix(normalizedQuery) {
                    structural = 0.86
                } else if normalizedTitle.contains(normalizedQuery) {
                    structural = 0.68
                } else {
                    structural = 0.42
                }

                return RankedResult(
                    atomUUID: entry.atomUUID,
                    atomType: entry.atomType,
                    title: entry.title,
                    snippet: entry.snippet?.prefix(160).description,
                    semanticWeight: 0.0,
                    structuralWeight: structural,
                    recencyWeight: 0.5,
                    usageWeight: 0.5,
                    updatedAt: entry.updatedAt
                )
            }
            .sorted()
            .prefix(limit)
            .map { $0 }
    }
}

enum CommandKPerformanceInstrumentation {
    static let logger = Logger(subsystem: "com.cosmo.os", category: "CommandKPerformance")
    static let signposter = OSSignposter(subsystem: "com.cosmo.os", category: "CommandKPerformance")
}
