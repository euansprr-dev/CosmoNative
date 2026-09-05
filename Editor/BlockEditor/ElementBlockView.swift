import AppKit
import SwiftUI

struct ElementBlockView: View {
    @Binding var block: RichBlock

    let focusCoordinator: BlockFocusCoordinator
    var fontSize: CGFloat = 17
    var fontDesign: NSFontDescriptor.SystemDesign = .default
    var lineSpacingAdjustment: CGFloat = 0
    var blockGap: CGFloat = DS.space6
    var darkMode: Bool = false
    var overrideTextColor: NSColor? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowSelectionMenu: Bool = true
    var allowImages: Bool = true
    var typewriterMode: Bool = false
    var editorTargetID: String? = nil
    var navigationTargetID: UUID? = nil
    var onSelectionChanged: ((EditorSelectionSnapshot) -> Void)? = nil
    var onExitBody: (() -> Void)? = nil
    var onElementChange: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        // One container grammar: the Element card and the Section box draw
        // through the same surface (ContainerBlockChrome) — an Element is
        // simply a container backed by a reusable definition.
        ContainerBlockSurface(chrome: chrome, isCollapsed: isCollapsed) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !isCollapsed {
                    bodyContent
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                }
            }
        }
        .onHover { isHovered = $0 }
        .onAppear { focusCoordinator.register(block.id) }
        .onDisappear { focusCoordinator.unregister(block.id) }
    }

    private var header: some View {
        ElementBlockHeader(
            title: titleBinding,
            isCollapsed: isCollapsed,
            iconName: iconName,
            tone: tone,
            darkMode: darkMode,
            collapsedChildCount: block.children.count,
            titleColor: titleColor,
            chevronColor: chevronColor,
            // Per-row focus read — the whole-coordinator focusedBlockID
            // would re-render this element on every focus change anywhere.
            autoFocusTitle: focusCoordinator.rowState(for: block.id).isFocused,
            onToggleCollapse: toggleCollapse,
            onSubmitTitle: focusBody,
            onTitleFocusChange: handleTitleFocusChange
        )
    }

    private var bodyContent: some View {
        BlockListView(
            document: childDocumentBinding,
            fontSize: fontSize,
            fontDesign: fontDesign,
            lineSpacingAdjustment: lineSpacingAdjustment,
            blockGap: blockGap,
            placeholder: "Add details...",
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            allowSlashCommands: allowSlashCommands,
            allowMentions: allowMentions,
            allowSelectionMenu: allowSelectionMenu,
            allowImages: allowImages,
            typewriterMode: typewriterMode,
            editorTargetID: editorTargetID,
            navigationTargetID: navigationTargetID,
            focusCoordinator: focusCoordinator,
            providesNavigationOrder: false,
            onSelectionChanged: onSelectionChanged,
            onExitFinalEmptyTextRegion: exitBody,
            onDocumentChange: { _, _ in onElementChange?() }
        )
        .padding(.horizontal, DS.space10)
        .padding(.top, DS.space4)
        .padding(.bottom, DS.space10)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { block.element?.instanceTitleSnapshot ?? "" },
            set: { newValue in
                block.element?.instanceTitleSnapshot = newValue
                onElementChange?()
            }
        )
    }

    private var childDocumentBinding: Binding<RichDocument> {
        Binding(
            get: { RichDocument(blocks: block.children) },
            set: { nextDocument in
                block.children = nextDocument.blocks
                onElementChange?()
            }
        )
    }

    private var isCollapsed: Bool {
        block.element?.isCollapsed ?? false
    }

    private var iconName: String {
        block.element?.systemIconSnapshot ?? DocumentElementSymbol.fallback
    }

    private var tone: NoteInkTone {
        DocumentElementRendering.tone(for: block)
    }

    /// At rest the card is a whisper of its tone; hover firms the hairline.
    /// No drop shadow — the wash and hairline are all the depth it needs.
    /// Elements always wear the `.wash` appearance.
    private var chrome: ContainerBlockChrome {
        ContainerBlockChrome(appearance: .wash, tone: tone, darkMode: darkMode, isHovered: isHovered)
    }

    private var titleColor: Color {
        // Full ink — the card's title must not whisper under its own body.
        if let overrideTextColor {
            return Color(nsColor: overrideTextColor)
        }
        return darkMode ? DS.focusImmersiveText : DS.documentText
    }

    private var chevronColor: Color {
        darkMode ? DS.focusImmersiveTextMuted : DS.documentTextMuted
    }

    private func toggleCollapse() {
        block.element?.isCollapsed.toggle()
        onElementChange?()
    }

    private func focusBody() {
        if block.element?.isCollapsed == true {
            block.element?.isCollapsed = false
        }
        if block.children.isEmpty {
            block.children = [.paragraph("")]
        }
        let firstChildID = block.children.first?.id
        onElementChange?()
        focusCoordinator.focus(firstChildID)
    }

    private func handleTitleFocusChange(_ isFocused: Bool) {
        if isFocused {
            focusCoordinator.focus(block.id)
        }
    }

    private func exitBody() -> Bool {
        if let lastChild = block.children.last, lastChild.isEmptyParagraph {
            block.children.removeLast()
            onElementChange?()
        }
        onExitBody?()
        return true
    }
}

private extension RichBlock {
    var isEmptyParagraph: Bool {
        guard kind == .paragraph, children.isEmpty else { return false }
        return inlines.allSatisfy { inline in
            switch inline.kind {
            case .text:
                return inline.text?.isEmpty ?? true
            case .mention, .imageRef:
                return false
            }
        }
    }
}

private struct ElementBlockPreviewGrid: View {
    @State private var expanded = RichBlock.element(
        DocumentElementDefinition(title: "Benefits", systemIcon: "person.2"),
        children: [.paragraph("Example where text goes"), .paragraph("More body content...")],
        instanceTitle: "Benefits"
    )
    @State private var collapsed = RichBlock.element(
        DocumentElementDefinition(title: "Benefits", systemIcon: "sparkles"),
        children: [.paragraph("Example where text goes")],
        isCollapsed: true,
        instanceTitle: "Benefits"
    )
    @State private var coordinator = BlockFocusCoordinator()

    var body: some View {
        VStack(spacing: DS.space20) {
            ElementBlockView(block: $expanded, focusCoordinator: coordinator)
            ElementBlockView(block: $collapsed, focusCoordinator: coordinator)
        }
        .padding(DS.space24)
        .frame(width: 460)
    }
}

#Preview("Element Cards - Light") {
    ElementBlockPreviewGrid()
        .background(DS.documentBackground)
}

#Preview("Element Cards - Dark") {
    ElementBlockPreviewGrid()
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}
