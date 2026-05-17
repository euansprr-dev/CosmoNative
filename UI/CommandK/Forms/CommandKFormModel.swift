import Foundation

enum CommandKInlineFormKind: String, Codable, Equatable {
    case captureSwipe
    case captureResearch
    case createTask
    case createIdea
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
        case .createTask:
            return "Create Task"
        case .createIdea:
            return "Create Idea"
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
        case .createTask, .createIdea, .createInquiry, .createQuicklink, .createSnippet, .createRecipe:
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

    private func compact(_ dictionary: [String: String]) -> [String: String] {
        dictionary.filter { !$0.value.isEmpty }
    }
}
