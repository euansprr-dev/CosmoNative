import Foundation

struct BlockCommand: Identifiable, Equatable, Hashable {
    enum Action: Equatable, Hashable {
        case transform(RichBlockKind)
        /// Heading transform carrying the plain vs. collapsible choice —
        /// "Heading 1" and "Toggle Heading 1" are distinct menu entries.
        case transformHeading(RichBlockKind, collapsible: Bool)
        case replaceOrInsert(RichBlockKind)
        case insertElement(DocumentElementDefinition)
        case createElement
        case openElementsSubmenu
        case openWritingAI
    }

    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var aliases: [String]
    var action: Action

    var searchableText: String {
        ([title, subtitle] + aliases)
            .joined(separator: " ")
            .lowercased()
    }
}

extension BlockCommand.Action {
    var undoActionName: String {
        switch self {
        case .transform(let kind):
            return "Transform to \(kind.editorDisplayName)"
        case .transformHeading(let kind, let collapsible):
            return "Transform to \(collapsible ? "Toggle " : "")\(kind.editorDisplayName)"
        case .replaceOrInsert(let kind):
            return "Insert \(kind.editorDisplayName)"
        case .insertElement:
            return "Insert Element"
        case .createElement:
            return "Create Element"
        case .openElementsSubmenu:
            return "Open Elements"
        case .openWritingAI:
            return "Open Writing AI"
        }
    }
}

enum BlockCommandCatalog {
    static let baseCommands: [BlockCommand] = [
        BlockCommand(
            id: "writing-ai",
            title: "Writing AI",
            subtitle: "Draft, rewrite, or continue this block",
            systemImage: "sparkles",
            aliases: ["ai", "write", "assistant"],
            action: .openWritingAI
        ),
        BlockCommand(
            id: "heading-1",
            title: "Heading 1",
            subtitle: "Large section heading",
            systemImage: "textformat.size.larger",
            aliases: ["h1", "title"],
            action: .transformHeading(.heading1, collapsible: false)
        ),
        BlockCommand(
            id: "heading-2",
            title: "Heading 2",
            subtitle: "Medium section heading",
            systemImage: "textformat.size",
            aliases: ["h2", "subtitle"],
            action: .transformHeading(.heading2, collapsible: false)
        ),
        BlockCommand(
            id: "heading-3",
            title: "Heading 3",
            subtitle: "Small section heading",
            systemImage: "textformat",
            aliases: ["h3"],
            action: .transformHeading(.heading3, collapsible: false)
        ),
        BlockCommand(
            id: "checklist",
            title: "Checklist",
            subtitle: "Track tasks with checkboxes",
            systemImage: "checklist",
            aliases: ["todo", "task", "checkbox"],
            action: .transform(.checklist)
        ),
        BlockCommand(
            id: "bullet-list",
            title: "Bullet List",
            subtitle: "Create a bulleted list item",
            systemImage: "list.bullet",
            aliases: ["ul", "list"],
            action: .transform(.bulletList)
        ),
        BlockCommand(
            id: "numbered-list",
            title: "Numbered List",
            subtitle: "Create an ordered list item",
            systemImage: "list.number",
            aliases: ["ol", "ordered"],
            action: .transform(.numberedList)
        ),
        BlockCommand(
            id: "quote",
            title: "Quote",
            subtitle: "Emphasize a passage",
            systemImage: "quote.opening",
            aliases: ["blockquote"],
            action: .transform(.quote)
        ),
        BlockCommand(
            id: "callout",
            title: "Callout",
            subtitle: "Highlight with an icon and tint",
            systemImage: "exclamationmark.bubble",
            aliases: ["info", "note", "highlight", "aside", "warning"],
            action: .transform(.callout)
        ),
        BlockCommand(
            id: "toggle",
            title: "Toggle",
            subtitle: "Collapsible section of blocks",
            systemImage: "chevron.forward.square",
            aliases: ["collapse", "disclosure", "fold", "expand"],
            action: .transform(.toggle)
        ),
        BlockCommand(
            id: "toggle-heading-1",
            title: "Toggle Heading 1",
            subtitle: "Large collapsible section heading",
            systemImage: "chevron.forward.square",
            aliases: ["th1", "toggle h1", "collapsible heading", "fold heading"],
            action: .transformHeading(.heading1, collapsible: true)
        ),
        BlockCommand(
            id: "toggle-heading-2",
            title: "Toggle Heading 2",
            subtitle: "Medium collapsible section heading",
            systemImage: "chevron.forward.square",
            aliases: ["th2", "toggle h2", "collapsible heading", "fold heading"],
            action: .transformHeading(.heading2, collapsible: true)
        ),
        BlockCommand(
            id: "toggle-heading-3",
            title: "Toggle Heading 3",
            subtitle: "Small collapsible section heading",
            systemImage: "chevron.forward.square",
            aliases: ["th3", "toggle h3", "collapsible heading", "fold heading"],
            action: .transformHeading(.heading3, collapsible: true)
        ),
        BlockCommand(
            id: "code-block",
            title: "Code",
            subtitle: "Monospaced code block",
            systemImage: "curlybraces",
            aliases: ["snippet", "mono", "codeblock", "pre"],
            action: .transform(.code)
        ),
        BlockCommand(
            id: "divider",
            title: "Divider",
            subtitle: "Separate sections",
            systemImage: "minus",
            aliases: ["line", "separator", "rule"],
            action: .replaceOrInsert(.divider)
        ),
        BlockCommand(
            id: "image",
            title: "Image",
            subtitle: "Insert an image block",
            systemImage: "photo",
            aliases: ["picture", "media"],
            action: .replaceOrInsert(.image)
        ),
        BlockCommand(
            id: "sketch",
            title: "Sketch",
            subtitle: "Draw freehand on the page",
            systemImage: "scribble.variable",
            aliases: ["draw", "drawing", "doodle", "board"],
            action: .replaceOrInsert(.sketch)
        ),
        BlockCommand(
            id: "content",
            title: "Content Block",
            subtitle: "Create a structured writing block",
            systemImage: "doc.text",
            aliases: ["draft", "post", "article"],
            action: .replaceOrInsert(.content)
        ),
        BlockCommand(
            id: "research",
            title: "Research Block",
            subtitle: "Collect sources and findings",
            systemImage: "magnifyingglass",
            aliases: ["source", "sources", "inquiry"],
            action: .replaceOrInsert(.research)
        ),
        BlockCommand(
            id: "elements",
            title: "Elements",
            subtitle: "Insert a reusable custom block",
            systemImage: "square.stack.3d.up",
            aliases: ["custom"],
            action: .openElementsSubmenu
        )
    ]

    static func filteredCommands(query: String) -> [BlockCommand] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return baseCommands }

        return baseCommands
            .compactMap { command -> (BlockCommand, Int)? in
                if command.title.lowercased().hasPrefix(normalized) { return (command, 0) }
                if command.searchableText.contains(normalized) { return (command, 1) }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    static func action(for slashCommandType: SlashCommandType) -> BlockCommand.Action? {
        switch slashCommandType {
        case .heading1:
            return .transformHeading(.heading1, collapsible: false)
        case .heading2:
            return .transformHeading(.heading2, collapsible: false)
        case .heading3:
            return .transformHeading(.heading3, collapsible: false)
        case .toggleHeading1:
            return .transformHeading(.heading1, collapsible: true)
        case .toggleHeading2:
            return .transformHeading(.heading2, collapsible: true)
        case .toggleHeading3:
            return .transformHeading(.heading3, collapsible: true)
        case .quote:
            return .transform(.quote)
        case .bulletList:
            return .transform(.bulletList)
        case .numberedList:
            return .transform(.numberedList)
        case .checkbox:
            return .transform(.checklist)
        case .divider:
            return .replaceOrInsert(.divider)
        case .callout:
            return .transform(.callout)
        case .toggle:
            return .transform(.toggle)
        case .codeBlock:
            return .transform(.code)
        case .sketch:
            return .replaceOrInsert(.sketch)
        case .content:
            return .replaceOrInsert(.content)
        case .research:
            return .replaceOrInsert(.research)
        case .element:
            return nil
        case .newElement:
            return .createElement
        case .elements:
            return .openElementsSubmenu
        case .writingAI:
            return nil
        case .image:
            return nil
        }
    }

    static func action(for slashCommand: SlashCommand) -> BlockCommand.Action? {
        if slashCommand.type == .element, let definition = slashCommand.elementDefinition {
            return .insertElement(definition)
        }
        return action(for: slashCommand.type)
    }
}

private extension RichBlockKind {
    var editorDisplayName: String {
        switch self {
        case .paragraph: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .quote: return "Quote"
        case .divider: return "Divider"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered List"
        case .checklist: return "Checklist"
        case .image: return "Image"
        case .element: return "Element"
        case .content: return "Content Block"
        case .research: return "Research Block"
        case .callout: return "Callout"
        case .toggle: return "Toggle"
        case .code: return "Code Block"
        case .sketch: return "Sketch"
        }
    }
}
