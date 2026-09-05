import Foundation

enum CommandKInlineFormKind: String, Codable, Equatable {
    case captureSwipe
    case captureResearch
    case captureInbox
    case createTask
    case createIdea
    case createNote
    case createContent
    case createThinkspace
    case createInquiry
    case createQuicklink
    case createSnippet
    case createRecipe
}

enum CommandKFormFieldID: String, Codable, Hashable {
    case url
    case title
    case body
    case date
    case client
    case attachTo
    case template
    case notes
    case priority
    case intent
    case format
    case platform
    case lane
    case hook
    case thinkspace
}

struct CommandKFormValidation: Equatable {
    let isValid: Bool
    let message: String?
}

struct CommandKInlineFormModel: Equatable {
    let kind: CommandKInlineFormKind
    private(set) var values: [CommandKFormFieldID: String] = [:]

    var primaryTitle: String {
        switch kind {
        case .captureSwipe, .captureResearch:
            return "Capture"
        case .captureInbox:
            return "Capture to Inbox"
        case .createTask:
            return "Create Task"
        case .createIdea:
            return "Create Idea"
        case .createNote:
            return "Create Page"
        case .createContent:
            return "Create Content"
        case .createThinkspace:
            return "Create Space"
        case .createInquiry:
            return "Start Inquiry"
        case .createQuicklink:
            return "Save Quicklink"
        case .createSnippet:
            return "Save Snippet"
        case .createRecipe:
            return "Save Recipe"
        }
    }

    var validation: CommandKFormValidation {
        switch kind {
        case .captureSwipe:
            guard value(for: .url).hasPrefix("http") else {
                return .init(isValid: false, message: "Paste a swipe URL")
            }
            return .init(isValid: true, message: nil)
        case .captureResearch:
            guard value(for: .url).hasPrefix("http") else {
                return .init(isValid: false, message: "Paste a research URL")
            }
            return .init(isValid: true, message: nil)
        case .captureInbox:
            guard !value(for: .body).isEmpty else {
                return .init(isValid: false, message: "Type what to capture")
            }
            return .init(isValid: true, message: nil)
        case .createIdea:
            guard !value(for: .title).isEmpty || !value(for: .body).isEmpty else {
                return .init(isValid: false, message: "Add a title or the idea itself")
            }
            return .init(isValid: true, message: nil)
        case .createTask, .createNote, .createContent, .createThinkspace,
             .createInquiry, .createQuicklink, .createSnippet, .createRecipe:
            guard !value(for: .title).isEmpty else {
                return .init(isValid: false, message: "Add a title")
            }
            return .init(isValid: true, message: nil)
        }
    }

    var resolvedIntent: CommandKActionIntent? {
        guard validation.isValid else { return nil }
        switch kind {
        case .captureSwipe:
            return .executeTool(name: "capture_swipe", arguments: ["url": value(for: .url)])
        case .captureResearch:
            return .executeTool(
                name: "capture_research",
                arguments: compact(["url": value(for: .url), "title": value(for: .title), "body": value(for: .body)])
            )
        case .captureInbox:
            // Inbox captures route through the ingest choke point, not an
            // agent tool — the composer commit service owns that path.
            return nil
        case .createTask:
            return .executeTool(
                name: "create_task",
                arguments: compact(["title": value(for: .title), "date": value(for: .date)])
            )
        case .createIdea:
            return .executeTool(
                name: "create_idea",
                arguments: compact(["title": value(for: .title), "body": value(for: .body)])
            )
        case .createNote:
            return .executeTool(name: "create_note", arguments: compact(["title": value(for: .title)]))
        case .createContent:
            return .executeTool(name: "create_content", arguments: compact(["title": value(for: .title)]))
        case .createThinkspace:
            return .executeTool(name: "create_thinkspace", arguments: compact(["title": value(for: .title)]))
        case .createInquiry:
            return .startInquiry(anchorUUID: value(for: .title), anchorType: "Query")
        case .createQuicklink:
            return .userCommand(id: "quicklink-form")
        case .createSnippet:
            return .userCommand(id: "snippet-form")
        case .createRecipe:
            return .recipe(id: "recipe-form")
        }
    }

    mutating func setValue(_ value: String, for field: CommandKFormFieldID) {
        values[field] = value
    }

    func value(for field: CommandKFormFieldID) -> String {
        values[field]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Untrimmed value for live text-field bindings — trimming while the
    /// user types would eat their spaces.
    func rawValue(for field: CommandKFormFieldID) -> String {
        values[field] ?? ""
    }

    private func compact(_ dictionary: [String: String]) -> [String: String] {
        dictionary.filter { !$0.value.isEmpty }
    }
}
