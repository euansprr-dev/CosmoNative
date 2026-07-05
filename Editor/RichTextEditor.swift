// CosmoOS/Editor/RichTextEditor.swift
// Apple Notes-quality rich text editor with TextKit 2
// Slash commands, @mentions, markdown, inline embeds
// Premium overlay behavior: dismiss on outside click, scroll, focus loss

import SwiftUI
import AppKit

/// Lets an editor's open slash / mention / selection menu claim Escape before
/// MainView's global key monitor falls through to closing the whole focus mode
/// or page. The handler dismisses just the menu (leaving the typed `/` or `@`
/// in place) and reports whether it consumed the press.
@MainActor
final class EditorOverlayEscapeCoordinator {

    static let shared = EditorOverlayEscapeCoordinator()

    private var handlers: [(id: UUID, handle: () -> Bool)] = []

    func register(id: UUID, handler: @escaping () -> Bool) {
        unregister(id: id)
        handlers.append((id, handler))
    }

    func unregister(id: UUID) {
        handlers.removeAll { $0.id == id }
    }

    /// Ask handlers (most recent first) to dismiss their open menu. Returns
    /// true as soon as one consumes the Escape press.
    func dismissTopOverlay() -> Bool {
        for entry in handlers.reversed() where entry.handle() {
            return true
        }
        return false
    }
}

enum EditorHeightUpdatePolicy {
    static let defaultEpsilon: CGFloat = 1.0

    static func normalizedHeight(_ height: CGFloat) -> CGFloat? {
        guard height.isFinite, height > 1 else {
            return nil
        }
        return ceil(height)
    }

    static func shouldPublish(
        current: CGFloat,
        next: CGFloat,
        epsilon: CGFloat = defaultEpsilon
    ) -> Bool {
        guard let nextHeight = normalizedHeight(next) else {
            return false
        }
        guard let currentHeight = normalizedHeight(current) else {
            return true
        }
        return abs(nextHeight - currentHeight) > epsilon
    }
}

struct EditorTextPadding: Equatable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    static let zero = EditorTextPadding(top: 0, leading: 0, bottom: 0, trailing: 0)

    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    var vertical: CGFloat {
        top + bottom
    }
}

enum EditorTextInsetPolicy {
    static func usesExternalTextPadding(
        scrollsInternally: Bool,
        singleLine: Bool,
        isTitleMode: Bool
    ) -> Bool {
        !scrollsInternally && !singleLine && !isTitleMode
    }

    static func textContainerInset(
        scrollsInternally: Bool,
        singleLine: Bool,
        isTitleMode: Bool,
        compact: Bool,
        fontSize: CGFloat
    ) -> NSSize {
        if usesExternalTextPadding(
            scrollsInternally: scrollsInternally,
            singleLine: singleLine,
            isTitleMode: isTitleMode
        ) {
            return .zero
        }

        let padding = visualPadding(
            singleLine: singleLine,
            isTitleMode: isTitleMode,
            compact: compact,
            fontSize: fontSize
        )
        return NSSize(width: padding.leading, height: padding.top)
    }

    static func externalTextPadding(
        scrollsInternally: Bool,
        singleLine: Bool,
        isTitleMode: Bool,
        compact: Bool,
        fontSize: CGFloat
    ) -> EditorTextPadding {
        guard usesExternalTextPadding(
            scrollsInternally: scrollsInternally,
            singleLine: singleLine,
            isTitleMode: isTitleMode
        ) else {
            return .zero
        }

        return visualPadding(
            singleLine: singleLine,
            isTitleMode: isTitleMode,
            compact: compact,
            fontSize: fontSize
        )
    }

    static func visualPadding(
        singleLine: Bool,
        isTitleMode: Bool,
        compact: Bool,
        fontSize: CGFloat
    ) -> EditorTextPadding {
        if singleLine {
            let verticalInset = EditorLayoutMetrics.singleLineVerticalInset(fontSize: fontSize, compact: compact)
            return EditorTextPadding(
                top: verticalInset,
                leading: compact ? 0 : 2,
                bottom: verticalInset,
                trailing: 2
            )
        }

        if isTitleMode {
            let verticalInset = EditorLayoutMetrics.titleVerticalInset(fontSize: fontSize, compact: compact)
            return EditorTextPadding(
                top: verticalInset,
                leading: compact ? 0 : 2,
                bottom: verticalInset,
                trailing: 2
            )
        }

        if compact {
            return EditorTextPadding(top: 8, leading: 10, bottom: 8, trailing: 10)
        }

        return EditorTextPadding(top: 16, leading: 16, bottom: 16, trailing: 16)
    }
}

/// Hoists a block-row editor's slash menu to the top of the enclosing block
/// list. Each row is a separate AppKit text view; a menu rendered inside a
/// row's own ZStack draws and hit-tests underneath the NSTextViews of the
/// rows below it, and gets clamped to the row's ~1-line-tall container. Rows
/// publish a session here instead; the block list renders the single menu in
/// an overlay above every row.
@MainActor
@Observable
final class EditorOverlayPresenter {
    /// The coordinate space the owning block list declares; rows convert
    /// their caret anchors into it.
    static let coordinateSpaceName = "cosmoBlockEditorOverlaySpace"

    struct SlashMenuSession {
        /// Caret-anchored menu origin in the block list's coordinate space.
        var anchorInList: CGPoint
        var query: String
        /// Already filtered against the query, in display order.
        var commands: [SlashCommand]
        var elementSubmenuCommands: [SlashCommand]
        var selectedIndex: Int
        var darkMode: Bool
        var onHighlight: (Int) -> Void
        var onSelect: (SlashCommand) -> Void
        var onDismiss: () -> Void
    }

    struct ElementCreationSession {
        var anchorInList: CGPoint
        var darkMode: Bool
        var onCreate: (String, String) -> Void
        var onDismiss: () -> Void
    }

    /// Selection formatting bar for block rows — hoisted for the same reason
    /// as the slash menu: inside a one-line row it draws under the rows below
    /// it and clamps to nonsense positions.
    struct SelectionMenuSession {
        /// Selection rect in the block list's coordinate space.
        var anchorInList: CGRect
        var traits: SelectionFormattingTraits
        var compact: Bool
        var darkMode: Bool
        /// Identifies the publishing row so a stale row can't clear a newer session.
        var ownerID: UUID
        var onAIAction: ((AIWritingAction) -> Void)?
        var onCustomPrompt: ((String) -> Void)?
        var onWritingAIRequest: (() -> Void)?
        var onDismiss: () -> Void
    }

    var slashSession: SlashMenuSession?
    var elementCreationSession: ElementCreationSession?
    var selectionSession: SelectionMenuSession?

    func clearSelectionSession(ownedBy ownerID: UUID) {
        if selectionSession?.ownerID == ownerID {
            selectionSession = nil
        }
    }
}

private struct BlockEditorOverlayPresenterKey: EnvironmentKey {
    static let defaultValue: EditorOverlayPresenter? = nil
}

extension EnvironmentValues {
    /// Set by the top-level BlockListView; block-row editors publish their
    /// slash menu sessions into it instead of presenting inline.
    var blockEditorOverlayPresenter: EditorOverlayPresenter? {
        get { self[BlockEditorOverlayPresenterKey.self] }
        set { self[BlockEditorOverlayPresenterKey.self] = newValue }
    }
}

struct RichTextEditor: View {
    @Binding var text: NSAttributedString
    @Binding var plainText: String

    @State private var showSlashMenu = false
    @State private var showMentionMenu = false
    @State private var showSelectionMenu = false
    @State private var showElementCreationMenu = false
    @State private var slashMenuPosition: CGPoint = .zero
    /// Live query typed after the "/" — the text view keeps focus, the menu
    /// filters reactively (type-through model).
    @State private var slashQuery = ""
    @State private var slashSelectedIndex = 0
    /// Unclamped caret-anchored menu origin in this editor's local space —
    /// the hoisted overlay clamps against the block list's size instead.
    @State private var slashMenuLocalAnchor: CGPoint = .zero
    /// This editor's frame in the block list's overlay coordinate space —
    /// converts local caret anchors into list space for the hoisted menu.
    @State private var frameInOverlaySpace: CGRect = .zero
    @Environment(\.blockEditorOverlayPresenter) private var overlayPresenter
    @Environment(\.blockDragSelectionController) private var dragSelectionController
    @State private var mentionMenuPosition: CGPoint = .zero
    @State private var selectionAnchor: CGRect = .zero
    @State private var selectionTraits: SelectionFormattingTraits = .none
    @State private var elementCreationMenuPosition: CGPoint = .zero
    @State private var mentionSearchQuery = ""
    @State private var cursorPosition: Int = 0
    @State private var shouldRefocusEditor = false
    @State private var overlayEscapeOwnerID = UUID()
    @StateObject private var elementStore = DocumentElementStore()

    // Configuration
    var fontSize: CGFloat = 16
    var fontDesign: NSFontDescriptor.SystemDesign = .default
    var compact: Bool = false  // Compact mode for notes
    var lineSpacingAdjustment: CGFloat = 0  // Aa menu Compact/Standard/Airy delta
    var darkMode: Bool = false  // Dark mode for Thinkspace blocks
    var overrideTextColor: NSColor? = nil
    var overrideFont: NSFont? = nil
    var headingDisclosureColor: NSColor? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
    var rendersElementChrome: Bool = true
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
    var onBoundaryCommand: ((EditorBoundaryCommand) -> Bool)? = nil
    var onSlashCommandSelected: ((SlashCommand, String) -> Bool)? = nil
    var splitsOnReturn: Bool = false
    var rowBlockID: UUID? = nil
    var rowBlockKind: RichBlockKind? = nil
    var caretRequest: EditorCaretRequest? = nil
    var externalContentToken: Int = 0
    var onPlainTextDidChange: ((String) -> Void)? = nil
    var onStructuredDocumentChange: ((RichDocument, String) -> Void)? = nil
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

    /// The slash menu's rows, filtered by the live type-through query.
    private var slashFilteredCommands: [SlashCommand] {
        let isSearching = !slashQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return SlashCommandCatalog.filteredCommands(
            matching: slashQuery,
            commands: isSearching ? slashSearchCommands : slashCommands
        )
    }

    init(
        text: Binding<NSAttributedString>,
        plainText: Binding<String>,
        fontSize: CGFloat = 16,
        fontDesign: NSFontDescriptor.SystemDesign = .default,
        compact: Bool = false,
        lineSpacingAdjustment: CGFloat = 0,
        placeholder: String = "Start typing...",
        darkMode: Bool = false,
        overrideTextColor: NSColor? = nil,
        overrideFont: NSFont? = nil,
        headingDisclosureColor: NSColor? = nil,
        allowSlashCommands: Bool = true,
        allowMentions: Bool = true,
        allowSelectionMenu: Bool = true,
        allowImages: Bool = true,
        rendersElementChrome: Bool = true,
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
        onBoundaryCommand: ((EditorBoundaryCommand) -> Bool)? = nil,
        onSlashCommandSelected: ((SlashCommand, String) -> Bool)? = nil,
        splitsOnReturn: Bool = false,
        rowBlockID: UUID? = nil,
        rowBlockKind: RichBlockKind? = nil,
        caretRequest: EditorCaretRequest? = nil,
        externalContentToken: Int = 0,
        onPlainTextDidChange: ((String) -> Void)? = nil,
        onStructuredDocumentChange: ((RichDocument, String) -> Void)? = nil,
        autoFocus: Bool = false,
        onSave: ((NSAttributedString) -> Void)? = nil
    ) {
        self._text = text
        self._plainText = plainText
        self.fontSize = fontSize
        self.fontDesign = fontDesign
        self.compact = compact
        self.lineSpacingAdjustment = lineSpacingAdjustment
        self.placeholder = placeholder
        self.darkMode = darkMode
        self.overrideTextColor = overrideTextColor
        self.overrideFont = overrideFont
        self.headingDisclosureColor = headingDisclosureColor
        self.allowSlashCommands = allowSlashCommands
        self.allowMentions = allowMentions
        self.allowSelectionMenu = allowSelectionMenu
        self.allowImages = allowImages
        self.rendersElementChrome = rendersElementChrome
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
        self.onBoundaryCommand = onBoundaryCommand
        self.onSlashCommandSelected = onSlashCommandSelected
        self.splitsOnReturn = splitsOnReturn
        self.rowBlockID = rowBlockID
        self.rowBlockKind = rowBlockKind
        self.caretRequest = caretRequest
        self.externalContentToken = externalContentToken
        self.onPlainTextDidChange = onPlainTextDidChange
        self.onStructuredDocumentChange = onStructuredDocumentChange
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
                fontDesign: fontDesign,
                compact: compact,
                lineSpacingAdjustment: lineSpacingAdjustment,
                darkMode: darkMode,
                overrideTextColor: overrideTextColor,
                overrideFont: overrideFont,
                headingDisclosureColor: headingDisclosureColor,
                allowSlashCommands: allowSlashCommands,
                allowMentions: allowMentions,
                allowImages: allowImages,
                allowSelectionMenu: allowSelectionMenu,
                rendersElementChrome: rendersElementChrome,
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
                onSlashCommand: { position, query in
                    handleSlashTrigger(position: position, query: query)
                },
                onSlashMenuKey: { event in
                    handleSlashMenuKey(event)
                },
                onMention: { position, query in
                    guard allowMentions else { return }
                    let adjustedPosition = positionFromTextKit(position)
                    mentionMenuPosition = clampMenuPosition(adjustedPosition, menuSize: CGSize(width: 360, height: 320), in: containerSize)
                    mentionSearchQuery = query
                    showMentionMenu = true
                },
                onSelectionChange: { snapshot in
                    let adjustedSnapshot = snapshotFromTextKit(snapshot)
                    onSelectionChanged?(adjustedSnapshot)
                    if adjustedSnapshot.range.length > 0 {
                        if allowSelectionMenu && !showSlashMenu && !showMentionMenu {
                            selectionAnchor = adjustedSnapshot.rectInEditor
                            selectionTraits = adjustedSnapshot.traits
                            // showSelectionMenu also drives Esc handling and the
                            // click-away dismiss layer, so it's set even when the
                            // bar itself renders hoisted in the block list.
                            showSelectionMenu = true
                            if overlayPresenter != nil {
                                publishSelectionSessionIfHoisted()
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            showSelectionMenu = false
                            overlayPresenter?.clearSelectionSession(ownedBy: overlayEscapeOwnerID)
                        }
                    }
                },
                onDismissMenus: {
                    dismissAllOverlays()
                },
                menusVisible: { isOverlayVisible },
                onContentHeightChange: { height in
                    scheduleMeasuredContentHeightUpdate(height)
                },
                onActivate: onActivate,
                onDeactivate: {
                    // Type-through menus never take focus themselves, so a
                    // deactivation while one is open means the user genuinely
                    // clicked away — close it.
                    if showSlashMenu {
                        dismissAllOverlays(includeSelection: false)
                    }
                    onDeactivate?()
                },
                onCommit: onCommit,
                onBoundaryCommand: onBoundaryCommand,
                onSlashCommandSelected: onSlashCommandSelected,
                onPlainTextDidChange: onPlainTextDidChange,
                onStructuredDocumentChange: onStructuredDocumentChange,
                splitsOnReturn: splitsOnReturn,
                caretRequest: caretRequest,
                externalContentToken: externalContentToken,
                dragSelectionController: dragSelectionController,
                rowBlockID: rowBlockID,
                rowBlockKind: rowBlockKind,
                editorInstanceID: overlayEscapeOwnerID
            )
            // Non-scrolling editors report their live height through
            // CosmoScrollView.intrinsicContentSize. Do not also pin this view to
            // measuredContentHeight: that SwiftUI @State update lands one layout
            // pass later than TextKit's own frame growth, producing a one-frame
            // mismatch on Return.
            .fixedSize(horizontal: false, vertical: !scrollsInternally)
            .padding(externalTextPadding.edgeInsets)
            .frame(maxWidth: .infinity)
            // Prevent overlay show/hide animations from spring-animating the editor frame
            .transaction { $0.animation = nil }
            // Ensure the entire editor area is clickable, even when empty
            .contentShape(Rectangle())

            // Placeholder - aligned with textContainerInset (16x16)
            if plainText.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize, weight: swiftUIFontWeight, design: EditorFontPolicy.swiftUIDesign(fontDesign)))
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

            // Slash command menu — inline presentation only when no block-list
            // presenter is hoisting it (continuous editors: Content, Idea,
            // canvas blocks). Block rows publish a session to the presenter
            // instead, so the menu renders above every row's text view.
            if showSlashMenu, overlayPresenter == nil {
                SlashCommandMenu(
                    position: slashMenuPosition,
                    query: slashQuery,
                    commands: slashFilteredCommands,
                    elementSubmenuCommands: elementSubmenuCommands,
                    selectedIndex: slashSelectedIndex,
                    onHighlight: { slashSelectedIndex = $0 },
                    onSelect: { handleSlashMenuSelection($0) },
                    onDismiss: { dismissAllOverlays() },
                    darkMode: darkMode
                )
                .background(ScrollEventBlocker())
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }

            if showElementCreationMenu, overlayPresenter == nil {
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

            // Selection formatting menu — inline only when no block-list
            // presenter is hoisting it (block rows publish a session so the
            // bar renders above every row's text view, never caged by a row).
            if showSelectionMenu && !showSlashMenu && !showMentionMenu, overlayPresenter == nil {
                SelectionFormattingMenu(
                    anchor: selectionAnchor,
                    container: containerSize,
                    traits: selectionTraits,
                    compact: compact,
                    darkMode: darkMode,
                    onDismiss: { showSelectionMenu = false },
                    onAIAction: onAIAction,
                    onCustomPrompt: onCustomPrompt,
                    onWritingAIRequest: onWritingAIRequest.map { request in
                        {
                            dismissAllOverlays()
                            request()
                        }
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
        .onGeometryChange(for: CGRect.self) { proxy in
            overlayPresenter == nil
                ? .zero
                : proxy.frame(in: .named(EditorOverlayPresenter.coordinateSpaceName))
        } action: { newValue in
            frameInOverlaySpace = newValue
        }
        .onAppear {
            if autoFocus {
                shouldRefocusEditor = true
            }
            EditorOverlayEscapeCoordinator.shared.register(id: overlayEscapeOwnerID) {
                dismissOverlaysForEscape()
            }
        }
        .onDisappear {
            EditorOverlayEscapeCoordinator.shared.unregister(id: overlayEscapeOwnerID)
            if showSlashMenu {
                overlayPresenter?.slashSession = nil
            }
            overlayPresenter?.clearSelectionSession(ownedBy: overlayEscapeOwnerID)
        }
        .onChange(of: autoFocus) { _, shouldFocus in
            if shouldFocus {
                shouldRefocusEditor = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoDismissEditorOverlays)) { _ in
            dismissAllOverlays()
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showSlashMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showMentionMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showSelectionMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showElementCreationMenu)
    }

    // MARK: - Overlay Helpers

    private func scheduleMeasuredContentHeightUpdate(_ height: CGFloat) {
        guard let nextHeight = EditorHeightUpdatePolicy.normalizedHeight(height),
              EditorHeightUpdatePolicy.shouldPublish(current: measuredContentHeight, next: nextHeight) else {
            return
        }

        DispatchQueue.main.async {
            guard EditorHeightUpdatePolicy.shouldPublish(current: measuredContentHeight, next: nextHeight) else {
                return
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                measuredContentHeight = nextHeight
            }
            onContentHeightChange?(visualHeight(forTextKitHeight: nextHeight))
        }
    }

    private var externalTextPadding: EditorTextPadding {
        EditorTextInsetPolicy.externalTextPadding(
            scrollsInternally: scrollsInternally,
            singleLine: singleLine,
            isTitleMode: titleConfiguration != nil,
            compact: compact,
            fontSize: fontSize
        )
    }

    private func visualHeight(forTextKitHeight height: CGFloat) -> CGFloat {
        height + externalTextPadding.vertical
    }

    private func positionFromTextKit(_ position: CGPoint) -> CGPoint {
        let padding = externalTextPadding
        return CGPoint(
            x: position.x + padding.leading,
            y: position.y + padding.top
        )
    }

    private func snapshotFromTextKit(_ snapshot: EditorSelectionSnapshot) -> EditorSelectionSnapshot {
        let padding = externalTextPadding
        return EditorSelectionSnapshot(
            range: snapshot.range,
            text: snapshot.text,
            rectInEditor: snapshot.rectInEditor.offsetBy(dx: padding.leading, dy: padding.top),
            traits: snapshot.traits,
            nearestHeadingBlockID: snapshot.nearestHeadingBlockID
        )
    }

    /// Publishes/updates the hoisted selection bar session for block rows.
    private func publishSelectionSessionIfHoisted() {
        guard let overlayPresenter else { return }
        overlayPresenter.selectionSession = EditorOverlayPresenter.SelectionMenuSession(
            anchorInList: selectionAnchor.offsetBy(
                dx: frameInOverlaySpace.minX,
                dy: frameInOverlaySpace.minY
            ),
            traits: selectionTraits,
            compact: compact,
            darkMode: darkMode,
            ownerID: overlayEscapeOwnerID,
            onAIAction: onAIAction,
            onCustomPrompt: onCustomPrompt,
            onWritingAIRequest: onWritingAIRequest.map { request in
                {
                    dismissAllOverlays()
                    request()
                }
            },
            onDismiss: {
                overlayPresenter.clearSelectionSession(ownedBy: overlayEscapeOwnerID)
            }
        )
    }

    private func dismissAllOverlays(includeSelection: Bool = true) {
        showSlashMenu = false
        showMentionMenu = false
        showElementCreationMenu = false
        if includeSelection {
            showSelectionMenu = false
            overlayPresenter?.clearSelectionSession(ownedBy: overlayEscapeOwnerID)
        }
        slashQuery = ""
        slashSelectedIndex = 0
        overlayPresenter?.slashSession = nil
        overlayPresenter?.elementCreationSession = nil
    }

    // MARK: - Slash Menu (type-through)

    /// Trigger/update from the coordinator: the "/" was typed (or the query
    /// after it changed). The text view keeps focus the whole time.
    private func handleSlashTrigger(position: CGPoint, query: String) {
        guard allowSlashCommands else { return }
        if !showSlashMenu {
            slashSelectedIndex = 0
        }
        slashQuery = query
        let filtered = slashFilteredCommands
        guard !filtered.isEmpty else {
            // Nothing matches — retire the menu. Deleting back to a matching
            // query reopens it on the next keystroke.
            showSlashMenu = false
            overlayPresenter?.slashSession = nil
            return
        }
        if slashSelectedIndex >= filtered.count {
            slashSelectedIndex = 0
        }
        let localAnchor = positionFromTextKit(position)
        slashMenuLocalAnchor = localAnchor
        slashMenuPosition = clampMenuPosition(
            localAnchor,
            menuSize: CGSize(width: 528, height: 340),
            in: containerSize
        )
        showSlashMenu = true
        publishSlashSessionIfHoisted()
    }

    /// ↑/↓/Return/Esc routed from the coordinator while the menu is open.
    private func handleSlashMenuKey(_ event: SlashMenuKeyEvent) -> Bool {
        guard showSlashMenu else { return false }
        let filtered = slashFilteredCommands
        switch event {
        case .up:
            slashSelectedIndex = max(0, slashSelectedIndex - 1)
            publishSlashSessionIfHoisted()
            return true
        case .down:
            slashSelectedIndex = min(max(0, filtered.count - 1), slashSelectedIndex + 1)
            publishSlashSessionIfHoisted()
            return true
        case .commit:
            guard let command = filtered[safe: slashSelectedIndex],
                  command.type != .elements else { return false }
            handleSlashMenuSelection(command)
            return true
        case .dismiss:
            dismissAllOverlays()
            return true
        }
    }

    /// Menu selection — synchronous. No dismiss-refocus-insert delay chain:
    /// the text view never lost focus, so the command can execute immediately.
    private func handleSlashMenuSelection(_ command: SlashCommand) {
        CosmicHaptics.shared.play(.selection)
        if command.type == .newElement {
            showSlashMenu = false
            overlayPresenter?.slashSession = nil
            elementCreationMenuPosition = clampMenuPosition(
                slashMenuPosition,
                menuSize: CGSize(width: 330, height: 364),
                in: containerSize
            )
            showElementCreationMenu = true
            publishElementCreationSessionIfHoisted()
            return
        }
        guard command.type != .elements else { return }
        dismissAllOverlays()
        postSlashCommand(command)
    }

    /// Publishes the New Element form for block rows — same hoisting as the
    /// slash menu (a form inside a one-line row clamps and hit-tests badly).
    private func publishElementCreationSessionIfHoisted() {
        guard let overlayPresenter, showElementCreationMenu else { return }
        overlayPresenter.elementCreationSession = EditorOverlayPresenter.ElementCreationSession(
            anchorInList: CGPoint(
                x: frameInOverlaySpace.minX + slashMenuLocalAnchor.x,
                y: frameInOverlaySpace.minY + slashMenuLocalAnchor.y
            ),
            darkMode: darkMode,
            onCreate: { title, icon in
                createElementAndInsert(title: title, icon: icon)
            },
            onDismiss: {
                dismissAllOverlays()
                refocusAfterDismiss()
            }
        )
    }

    /// Publishes/updates the hoisted menu session for block rows.
    private func publishSlashSessionIfHoisted() {
        guard let overlayPresenter, showSlashMenu else { return }
        overlayPresenter.slashSession = EditorOverlayPresenter.SlashMenuSession(
            anchorInList: CGPoint(
                x: frameInOverlaySpace.minX + slashMenuLocalAnchor.x,
                y: frameInOverlaySpace.minY + slashMenuLocalAnchor.y
            ),
            query: slashQuery,
            commands: slashFilteredCommands,
            elementSubmenuCommands: elementSubmenuCommands,
            selectedIndex: slashSelectedIndex,
            darkMode: darkMode,
            onHighlight: { index in
                slashSelectedIndex = index
                publishSlashSessionIfHoisted()
            },
            onSelect: { command in
                handleSlashMenuSelection(command)
            },
            onDismiss: {
                dismissAllOverlays()
            }
        )
    }

    /// Escape handler for EditorOverlayEscapeCoordinator: if a menu is open,
    /// dismiss it (leaving the typed `/` or `@` in the text) and report that we
    /// consumed the press so the global monitor doesn't also close the page.
    private func dismissOverlaysForEscape() -> Bool {
        guard isOverlayVisible else { return false }
        dismissAllOverlays()
        return true
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

    /// Clamp menu position so it stays within visible bounds. The horizontal
    /// clamp reserves shadow clearance: the editor column is a clipped
    /// container, and a body-only clamp slices the menu's drop shadow into a
    /// hard line at the column edge.
    private func clampMenuPosition(_ raw: CGPoint, menuSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let hPadding: CGFloat = min(
            CosmoMenuChrome.shadowClearance,
            max(8, (containerSize.width - menuSize.width) / 2)
        )
        let vPadding: CGFloat = 8
        var x = raw.x
        var y = raw.y

        // Clamp horizontally
        if x + menuSize.width > containerSize.width - hPadding {
            x = containerSize.width - menuSize.width - hPadding
        }
        if x < hPadding { x = hPadding }

        // Clamp vertically (prefer showing below cursor; flip above if needed)
        if y + menuSize.height > containerSize.height - vPadding {
            y = max(vPadding, raw.y - menuSize.height - 24)
        }
        if y < vPadding { y = vPadding }

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
        EditorTextInsetPolicy.visualPadding(
            singleLine: singleLine,
            isTitleMode: titleConfiguration != nil,
            compact: compact,
            fontSize: fontSize
        ).edgeInsets
    }

    // MARK: - Slash Command Insertion

    /// All slash execution routes through the coordinator notification: it
    /// owns the text storage, consumes the tracked "/" trigger, and — for
    /// block rows — hands the command to the block pipeline synchronously.
    private func insertSlashCommand(_ command: SlashCommand) {
        postSlashCommand(command)
    }

    private func postSlashCommand(_ command: SlashCommand) {
        var userInfo: [String: Any] = ["command": command]
        if let editorTargetID, !editorTargetID.isEmpty {
            userInfo["targetEditorID"] = editorTargetID
        }
        // Pin the command to THIS editor instance. Target IDs are not unique
        // (the canvas note block behind a focus mode shares the note-body
        // target), and a second editor executing the same command runs the
        // legacy TextKit path, steals first responder, and writes stale
        // content back over the note.
        userInfo["sourceEditorInstanceID"] = overlayEscapeOwnerID
        NotificationCenter.default.post(
            name: .performSlashCommand,
            object: nil,
            userInfo: userInfo
        )
    }

    // MARK: - Mention Insertion
    private func performMentionSelection(_ entity: MentionEntity) {
        var userInfo: [String: Any] = [
            "entityType": entity.type.rawValue,
            "entityId": entity.entityID as Any,
            "entityUUID": entity.uuid,
            "title": entity.title
        ]
        if let editorTargetID, !editorTargetID.isEmpty {
            userInfo["targetEditorID"] = editorTargetID
        }
        NotificationCenter.default.post(
            name: .performMentionSelection,
            object: nil,
            userInfo: userInfo
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
    case content
    case research
    case heading1, heading2, heading3
    case bulletList, numberedList, checkbox
    case quote, divider

    var requiresTextKitMutationBeforeSemanticHandling: Bool {
        switch self {
        case .content, .research:
            return true
        default:
            return false
        }
    }

    var stableID: String {
        switch self {
        case .writingAI: return "writing-ai"
        case .image: return "image"
        case .elements: return "elements"
        case .element: return "element"
        case .newElement: return "new-element"
        case .content: return "content"
        case .research: return "research"
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
        SlashCommand(type: .content, title: "Content Block", subtitle: "Draft with the content workflow", icon: "doc.text", shortcut: nil, searchAliases: ["content", "draft", "post"]),
        SlashCommand(type: .research, title: "Research Block", subtitle: "Collect sources and notes", icon: "magnifyingglass.circle", shortcut: nil, searchAliases: ["research", "source", "citation"]),
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
