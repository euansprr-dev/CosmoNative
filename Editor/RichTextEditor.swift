// CosmoOS/Editor/RichTextEditor.swift
// Apple Notes-quality rich text editor with TextKit 2
// Slash commands, @mentions, markdown, inline embeds
// Premium overlay behavior: dismiss on outside click, scroll, focus loss

import SwiftUI
import AppKit

struct RichTextEditor: View {
    @Binding var text: NSAttributedString
    @Binding var plainText: String

    @State private var showSlashMenu = false
    @State private var showMentionMenu = false
    @State private var showSelectionMenu = false
    @State private var showElementCreationMenu = false
    @State private var slashMenuPosition: CGPoint = .zero
    @State private var mentionMenuPosition: CGPoint = .zero
    @State private var selectionMenuPosition: CGPoint = .zero
    @State private var elementCreationMenuPosition: CGPoint = .zero
    @State private var mentionSearchQuery = ""
    @State private var cursorPosition: Int = 0
    @State private var shouldRefocusEditor = false
    @StateObject private var elementStore = DocumentElementStore()

    // Configuration
    var fontSize: CGFloat = 16
    var compact: Bool = false  // Compact mode for notes
    var darkMode: Bool = false  // Dark mode for Thinkspace blocks
    var overrideTextColor: NSColor? = nil
    var overrideFont: NSFont? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
    var singleLine: Bool = false
    var titleConfiguration: TitleEditorConfiguration? = nil
    var baseFontWeight: NSFont.Weight = .regular
    var typewriterMode: Bool = false
    var isEditable: Bool = true
    var scrollsInternally: Bool = false
    var polishHighlights: WritingAnalysis? = nil
    var textAlignment: NSTextAlignment = .natural
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    var onAIAction: ((AIWritingAction) -> Void)? = nil
    var onCustomPrompt: ((String) -> Void)? = nil
    var onWritingAIRequest: (() -> Void)? = nil
    var focusBandRange: NSRange? = nil
    var focusBandRangeProvider: ((String, NSRange) -> NSRange?)? = nil
    var editorTargetID: String? = nil
    var navigationTargetID: UUID? = nil
    var onActivate: (() -> Void)? = nil
    var onDeactivate: (() -> Void)? = nil
    var onCommit: (() -> Void)? = nil
    var onPlainTextDidChange: ((String) -> Void)? = nil
    var autoFocus: Bool = false

    // Geometry for menu clamping
    @State private var containerSize: CGSize = .zero
    // Tracks measured text content height so the representable can be explicitly sized
    // (needed for non-scrolling mode inside a parent ScrollView)
    @State private var measuredContentHeight: CGFloat = 0
    @EnvironmentObject var voiceEngine: VoiceEngine

    let placeholder: String
    let onSave: ((NSAttributedString) -> Void)?

    /// Whether any overlay menu is currently visible
    private var isOverlayVisible: Bool {
        showSlashMenu || showMentionMenu || showSelectionMenu || showElementCreationMenu
    }

    private var slashCommands: [SlashCommand] {
        SlashCommandCatalog.commands(elementDefinitions: elementStore.activeDefinitions)
    }

    private var slashSearchCommands: [SlashCommand] {
        SlashCommandCatalog.searchableCommands(elementDefinitions: elementStore.activeDefinitions)
    }

    private var elementSubmenuCommands: [SlashCommand] {
        SlashCommandCatalog.elementSubmenuCommands(elementDefinitions: elementStore.activeDefinitions)
    }

    init(
        text: Binding<NSAttributedString>,
        plainText: Binding<String>,
        fontSize: CGFloat = 16,
        compact: Bool = false,
        placeholder: String = "Start typing...",
        darkMode: Bool = false,
        overrideTextColor: NSColor? = nil,
        overrideFont: NSFont? = nil,
        allowSlashCommands: Bool = true,
        allowMentions: Bool = true,
        allowSelectionMenu: Bool = true,
        allowImages: Bool = true,
        singleLine: Bool = false,
        titleConfiguration: TitleEditorConfiguration? = nil,
        baseFontWeight: NSFont.Weight = .regular,
        typewriterMode: Bool = false,
        isEditable: Bool = true,
        scrollsInternally: Bool = false,
        polishHighlights: WritingAnalysis? = nil,
        textAlignment: NSTextAlignment = .natural,
        onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil,
        onContentHeightChange: ((CGFloat) -> Void)? = nil,
        onAIAction: ((AIWritingAction) -> Void)? = nil,
        onCustomPrompt: ((String) -> Void)? = nil,
        onWritingAIRequest: (() -> Void)? = nil,
        focusBandRange: NSRange? = nil,
        focusBandRangeProvider: ((String, NSRange) -> NSRange?)? = nil,
        editorTargetID: String? = nil,
        navigationTargetID: UUID? = nil,
        onActivate: (() -> Void)? = nil,
        onDeactivate: (() -> Void)? = nil,
        onCommit: (() -> Void)? = nil,
        onPlainTextDidChange: ((String) -> Void)? = nil,
        autoFocus: Bool = false,
        onSave: ((NSAttributedString) -> Void)? = nil
    ) {
        self._text = text
        self._plainText = plainText
        self.fontSize = fontSize
        self.compact = compact
        self.placeholder = placeholder
        self.darkMode = darkMode
        self.overrideTextColor = overrideTextColor
        self.overrideFont = overrideFont
        self.allowSlashCommands = allowSlashCommands
        self.allowMentions = allowMentions
        self.allowSelectionMenu = allowSelectionMenu
        self.allowImages = allowImages
        self.singleLine = singleLine
        self.titleConfiguration = titleConfiguration
        self.baseFontWeight = baseFontWeight
        self.typewriterMode = typewriterMode
        self.isEditable = isEditable
        self.scrollsInternally = scrollsInternally
        self.polishHighlights = polishHighlights
        self.textAlignment = textAlignment
        self.onSelectionChanged = onSelectionChanged
        self.onContentHeightChange = onContentHeightChange
        self.onAIAction = onAIAction
        self.onCustomPrompt = onCustomPrompt
        self.onWritingAIRequest = onWritingAIRequest
        self.focusBandRange = focusBandRange
        self.focusBandRangeProvider = focusBandRangeProvider
        self.editorTargetID = editorTargetID
        self.navigationTargetID = navigationTargetID
        self.onActivate = onActivate
        self.onDeactivate = onDeactivate
        self.onCommit = onCommit
        self.onPlainTextDidChange = onPlainTextDidChange
        self.autoFocus = autoFocus
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main editor
            TextKitEditorRepresentable(
                attributedText: $text,
                plainText: $plainText,
                cursorPosition: $cursorPosition,
                shouldRefocus: $shouldRefocusEditor,
                fontSize: fontSize,
                compact: compact,
                darkMode: darkMode,
                overrideTextColor: overrideTextColor,
                overrideFont: overrideFont,
                allowSlashCommands: allowSlashCommands,
                allowMentions: allowMentions,
                allowImages: allowImages,
                allowSelectionMenu: allowSelectionMenu,
                singleLine: singleLine,
                titleConfiguration: titleConfiguration,
                baseFontWeight: baseFontWeight,
                polishHighlights: polishHighlights,
                focusBandRange: focusBandRange,
                focusBandRangeProvider: focusBandRangeProvider,
                editorTargetID: editorTargetID,
                navigationTargetID: navigationTargetID,
                textAlignment: textAlignment,
                typewriterMode: typewriterMode,
                isEditable: isEditable,
                scrollsInternally: scrollsInternally,
                onSlashCommand: { position in
                    guard allowSlashCommands else { return }
                    slashMenuPosition = clampMenuPosition(position, menuSize: CGSize(width: 528, height: 340), in: containerSize)
                    showSlashMenu = true
                },
                onMention: { position, query in
                    guard allowMentions else { return }
                    mentionMenuPosition = clampMenuPosition(position, menuSize: CGSize(width: 360, height: 320), in: containerSize)
                    mentionSearchQuery = query
                    showMentionMenu = true
                },
                onSelectionChange: { snapshot in
                    onSelectionChanged?(snapshot)
                    if snapshot.range.length > 0 {
                        if allowSelectionMenu && !showSlashMenu && !showMentionMenu {
                            let menuHeight: CGFloat = 52
                            // Y: place menu center above selection top
                            let menuY = snapshot.rectInEditor.minY - (menuHeight / 2) - 8
                            // X: center on selection midpoint (no clamping — menu uses .fixedSize())
                            selectionMenuPosition = CGPoint(x: snapshot.rectInEditor.midX, y: menuY)
                            showSelectionMenu = true
                        }
                    } else {
                        DispatchQueue.main.async {
                            showSelectionMenu = false
                        }
                    }
                },
                onDismissMenus: {
                    dismissAllOverlays()
                },
                onContentHeightChange: { height in
                    measuredContentHeight = height
                    onContentHeightChange?(height)
                },
                onActivate: onActivate,
                onDeactivate: onDeactivate,
                onCommit: onCommit,
                onPlainTextDidChange: onPlainTextDidChange
            )
            .frame(maxWidth: .infinity)
            .frame(height: (!scrollsInternally && measuredContentHeight > 1) ? measuredContentHeight : nil)
            // Prevent overlay show/hide animations from spring-animating the editor frame
            .transaction { $0.animation = nil }
            // Ensure the entire editor area is clickable, even when empty
            .contentShape(Rectangle())

            // Placeholder - aligned with textContainerInset (16x16)
            if plainText.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize, weight: swiftUIFontWeight))
                    .foregroundStyle(darkMode ? Color.white.opacity(0.4) : DS.documentTextMuted)
                    .padding(.top, editorInsets.top)
                    .padding(.leading, editorInsets.leading)
                    .allowsHitTesting(false)

                // Clickable overlay to focus empty editor
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        shouldRefocusEditor = true
                    }
            }

            // MARK: - Invisible dismiss layer (captures outside clicks)
            if isOverlayVisible {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        dismissAllOverlays()
                    }
                    .allowsHitTesting(true)
            }

            // Slash command menu
            if showSlashMenu {
                SlashCommandMenu(
                    position: slashMenuPosition,
                    commands: slashCommands,
                    searchCommands: slashSearchCommands,
                    elementSubmenuCommands: elementSubmenuCommands,
                    onSelect: { command in
                        if command.type == .newElement {
                            showSlashMenu = false
                            elementCreationMenuPosition = clampMenuPosition(
                                slashMenuPosition,
                                menuSize: CGSize(width: 330, height: 364),
                                in: containerSize
                            )
                            showElementCreationMenu = true
                            return
                        }

                        // First dismiss overlays and refocus
                        dismissAllOverlays()

                        // Then after a short delay, insert the command
                        // This ensures the editor has focus when the notification is posted
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            shouldRefocusEditor = true

                            // Wait for refocus to complete, then insert
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                insertSlashCommand(command)
                            }
                        }
                    },
                    onDismiss: {
                        dismissAllOverlays()
                        refocusAfterDismiss()
                    },
                    darkMode: darkMode
                )
                .background(ScrollEventBlocker())
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }

            if showElementCreationMenu {
                ElementCreationMenu(
                    position: elementCreationMenuPosition,
                    onCreate: { title, icon in
                        createElementAndInsert(title: title, icon: icon)
                    },
                    onDismiss: {
                        dismissAllOverlays()
                        refocusAfterDismiss()
                    },
                    darkMode: darkMode
                )
                .background(ScrollEventBlocker())
                .zIndex(1001)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }

            // Mention menu
            if showMentionMenu {
                MentionMenu(
                    position: mentionMenuPosition,
                    searchQuery: mentionSearchQuery,
                    onSelect: { entity in
                        dismissAllOverlays()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            shouldRefocusEditor = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                performMentionSelection(entity)
                            }
                        }
                    },
                    onDismiss: {
                        dismissAllOverlays()
                        refocusAfterDismiss()
                    },
                    darkMode: darkMode
                )
                .background(ScrollEventBlocker())
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }

            // Selection formatting menu
            if showSelectionMenu && !showSlashMenu && !showMentionMenu {
                SelectionFormattingMenu(
                    position: selectionMenuPosition,
                    compact: compact,
                    onDismiss: { showSelectionMenu = false },
                    onAIAction: onAIAction,
                    onCustomPrompt: onCustomPrompt,
                    onWritingAIRequest: {
                        dismissAllOverlays()
                        onWritingAIRequest?()
                    }
                )
                .zIndex(900)
                .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            containerSize = newValue
        }
        .onAppear {
            if autoFocus {
                shouldRefocusEditor = true
            }
        }
        .onChange(of: autoFocus) { _, shouldFocus in
            if shouldFocus {
                shouldRefocusEditor = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoDismissEditorOverlays)) { _ in
            dismissAllOverlays(includeSelection: false)
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showSlashMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showMentionMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showSelectionMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showElementCreationMenu)
    }

    // MARK: - Overlay Helpers

    private func dismissAllOverlays(includeSelection: Bool = true) {
        showSlashMenu = false
        showMentionMenu = false
        showElementCreationMenu = false
        if includeSelection {
            showSelectionMenu = false
        }
    }

    private func createElementAndInsert(title: String, icon: String) {
        do {
            let definition = try elementStore.createDefinition(title: title, systemIcon: icon)
            dismissAllOverlays()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                shouldRefocusEditor = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    insertSlashCommand(SlashCommand(
                        type: .element,
                        title: definition.title,
                        subtitle: "Insert element",
                        icon: definition.systemIcon,
                        shortcut: nil,
                        searchAliases: ["element", definition.systemIcon],
                        elementDefinition: definition
                    ))
                }
            }
        } catch {
            NSSound.beep()
        }
    }

    private func refocusAfterDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldRefocusEditor = true
        }
    }

    /// Clamp menu position so it stays within visible bounds
    private func clampMenuPosition(_ raw: CGPoint, menuSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let padding: CGFloat = 8
        var x = raw.x
        var y = raw.y

        // Clamp horizontally
        if x + menuSize.width > containerSize.width - padding {
            x = containerSize.width - menuSize.width - padding
        }
        if x < padding { x = padding }

        // Clamp vertically (prefer showing below cursor; flip above if needed)
        if y + menuSize.height > containerSize.height - padding {
            y = max(padding, raw.y - menuSize.height - 24)
        }
        if y < padding { y = padding }

        return CGPoint(x: x, y: y)
    }

    private func clampCenteredMenuPosition(_ rawCenter: CGPoint, menuSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let padding: CGFloat = 10
        let halfWidth = menuSize.width / 2
        let halfHeight = menuSize.height / 2

        let minX = padding + halfWidth
        let maxX = max(minX, containerSize.width - padding - halfWidth)
        let minY = padding + halfHeight
        let maxY = max(minY, containerSize.height - padding - halfHeight)

        return CGPoint(
            x: min(max(rawCenter.x, minX), maxX),
            y: min(max(rawCenter.y, minY), maxY)
        )
    }

    /// Convert NSFont.Weight to SwiftUI Font.Weight for placeholder text
    private var swiftUIFontWeight: Font.Weight {
        switch baseFontWeight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    private var editorInsets: EdgeInsets {
        if singleLine {
            return EdgeInsets(top: compact ? 4 : max(4, floor(fontSize * 0.12)),
                              leading: compact ? 0 : 2,
                              bottom: compact ? 4 : max(4, floor(fontSize * 0.12)),
                              trailing: 2)
        }

        if titleConfiguration != nil {
            let verticalInset = EditorLayoutMetrics.titleVerticalInset(fontSize: fontSize, compact: compact)
            return EdgeInsets(
                top: verticalInset,
                leading: compact ? 0 : 2,
                bottom: verticalInset,
                trailing: 2
            )
        }

        if compact {
            return EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        }

        return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    // MARK: - Slash Command Insertion
    private func insertSlashCommand(_ command: SlashCommand) {
        // Delegate all text manipulation to TextKitCoordinator to ensure
        // atomic operations on the text storage and avoid binding desync.
        NotificationCenter.default.post(
            name: .performSlashCommand,
            object: nil,
            userInfo: ["command": command]
        )
    }

    // MARK: - Mention Insertion
    private func performMentionSelection(_ entity: MentionEntity) {
        NotificationCenter.default.post(
            name: .performMentionSelection,
            object: nil,
            userInfo: [
                "entityType": entity.type.rawValue,
                "entityId": entity.entityID as Any,
                "entityUUID": entity.uuid,
                "title": entity.title
            ]
        )
    }
}

extension Notification.Name {
    static let cosmoDismissEditorOverlays = Notification.Name("CosmoDismissEditorOverlays")
    static let setEditorTypingAttributes = Notification.Name("SetEditorTypingAttributes")
    static let performSlashCommand = Notification.Name("PerformSlashCommand")
    static let performMentionSelection = Notification.Name("PerformMentionSelection")
    static let openMentionAsFloatingBlock = Notification.Name("OpenMentionAsFloatingBlock")
}

// MARK: - Slash Commands
struct SlashCommand: Identifiable {
    let id: String
    let type: SlashCommandType
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String?
    var searchAliases: [String]
    var elementDefinition: DocumentElementDefinition?

    init(
        type: SlashCommandType,
        title: String,
        subtitle: String,
        icon: String,
        shortcut: String?,
        searchAliases: [String] = [],
        elementDefinition: DocumentElementDefinition? = nil
    ) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
        self.searchAliases = searchAliases
        self.elementDefinition = elementDefinition
        if let elementDefinition {
            id = "element:\(elementDefinition.id.uuidString)"
        } else {
            id = "command:\(type.stableID)"
        }
    }
}

enum SlashCommandType: Equatable {
    case writingAI
    case image
    case elements
    case element
    case newElement
    case heading1, heading2, heading3
    case bulletList, numberedList, checkbox
    case quote, divider

    var stableID: String {
        switch self {
        case .writingAI: return "writing-ai"
        case .image: return "image"
        case .elements: return "elements"
        case .element: return "element"
        case .newElement: return "new-element"
        case .heading1: return "heading-1"
        case .heading2: return "heading-2"
        case .heading3: return "heading-3"
        case .bulletList: return "bullet-list"
        case .numberedList: return "numbered-list"
        case .checkbox: return "checkbox"
        case .quote: return "quote"
        case .divider: return "divider"
        }
    }
}

enum SlashCommandCatalog {
    static let baseCommands: [SlashCommand] = [
        SlashCommand(type: .writingAI, title: "Writing AI", subtitle: "Ask, rewrite, search, or critique", icon: "sparkles", shortcut: "⌥A"),
        SlashCommand(type: .image, title: "Image", subtitle: "Insert an inline image", icon: "photo", shortcut: nil),
        SlashCommand(type: .heading1, title: "Heading 1", subtitle: "Large section heading", icon: "textformat.size.larger", shortcut: nil),
        SlashCommand(type: .heading2, title: "Heading 2", subtitle: "Medium section heading", icon: "textformat.size", shortcut: nil),
        SlashCommand(type: .heading3, title: "Heading 3", subtitle: "Small section heading", icon: "textformat.size.smaller", shortcut: nil),
        SlashCommand(type: .quote, title: "Quote", subtitle: "Add a block quote", icon: "text.quote", shortcut: nil),
        SlashCommand(type: .divider, title: "Divider", subtitle: "Visual separation between sections", icon: "minus", shortcut: nil),
        SlashCommand(type: .bulletList, title: "Bullet List", subtitle: "Create a bullet list", icon: "list.bullet", shortcut: nil),
        SlashCommand(type: .numberedList, title: "Numbered List", subtitle: "Create a numbered list", icon: "list.number", shortcut: nil),
        SlashCommand(type: .checkbox, title: "Checklist", subtitle: "Track tasks with checkboxes", icon: "checklist", shortcut: nil),
    ]

    static let newElementCommand = SlashCommand(
        type: .newElement,
        title: "New Element",
        subtitle: "Create a reusable organization block",
        icon: "plus.square",
        shortcut: nil,
        searchAliases: ["new elements", "create element", "elements"]
    )

    static let elementsCommand = SlashCommand(
        type: .elements,
        title: "Elements",
        subtitle: "Create or insert reusable blocks",
        icon: "square.stack.3d.up",
        shortcut: nil,
        searchAliases: ["element", "elements", "new element"]
    )

    static func commands(elementDefinitions: [DocumentElementDefinition]) -> [SlashCommand] {
        Array(baseCommands.prefix(2)) + [elementsCommand] + Array(baseCommands.dropFirst(2))
    }

    static func searchableCommands(elementDefinitions: [DocumentElementDefinition]) -> [SlashCommand] {
        Array(baseCommands.prefix(2))
            + [elementsCommand, newElementCommand]
            + elementCommands(from: elementDefinitions)
            + Array(baseCommands.dropFirst(2))
    }

    static func elementSubmenuCommands(elementDefinitions: [DocumentElementDefinition]) -> [SlashCommand] {
        [newElementCommand] + elementCommands(from: elementDefinitions)
    }

    private static func elementCommands(from elementDefinitions: [DocumentElementDefinition]) -> [SlashCommand] {
        let elementCommands = activeElementDefinitions(from: elementDefinitions).map { definition in
            SlashCommand(
                type: .element,
                title: definition.title,
                subtitle: "Insert element",
                icon: definition.systemIcon,
                shortcut: nil,
                searchAliases: ["element", definition.systemIcon],
                elementDefinition: definition
            )
        }
        return elementCommands
    }

    static func filteredCommands(
        matching query: String,
        elementDefinitions: [DocumentElementDefinition]
    ) -> [SlashCommand] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = normalizedQuery.isEmpty
            ? commands(elementDefinitions: elementDefinitions)
            : searchableCommands(elementDefinitions: elementDefinitions)
        return filteredCommands(matching: query, commands: source)
    }

    static func filteredCommands(matching query: String, commands: [SlashCommand]) -> [SlashCommand] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return commands }
        return commands.filter { command in
            command.title.localizedCaseInsensitiveContains(normalizedQuery)
                || command.subtitle.localizedCaseInsensitiveContains(normalizedQuery)
                || command.searchAliases.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
        }
        .sorted {
            matchRank(for: $0, query: normalizedQuery) < matchRank(for: $1, query: normalizedQuery)
        }
    }

    private static func matchRank(for command: SlashCommand, query: String) -> Int {
        if command.title.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return 0
        }
        if command.title.localizedCaseInsensitiveContains(query) {
            return 1
        }
        if command.subtitle.localizedCaseInsensitiveContains(query) {
            return 2
        }
        return 3
    }

    private static func activeElementDefinitions(from definitions: [DocumentElementDefinition]) -> [DocumentElementDefinition] {
        definitions
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }
}

// MARK: - Mention Entity
struct MentionEntity: Identifiable {
    let entityID: Int64?
    let uuid: String
    let type: EntityType
    let title: String
    let subtitle: String?
    let typeLabel: String
    let updatedAt: String

    var id: String { uuid }
}

// MARK: - Scroll Event Blocker

/// Prevents scroll events from propagating through overlay menus to the underlying page
private struct ScrollEventBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollBlockingNSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class ScrollBlockingNSView: NSView {
    override func scrollWheel(with event: NSEvent) {
        // Consume — do not forward to parent
    }
}

// MARK: - Preview

#Preview("Rich Text Editor") {
    @Previewable @State var text = NSAttributedString(string: "Sample text content...")
    @Previewable @State var plainText = "Sample text content..."

    RichTextEditor(
        text: $text,
        plainText: $plainText,
        placeholder: "Start typing..."
    )
    .frame(width: 600, height: 400)
    .padding()
}
