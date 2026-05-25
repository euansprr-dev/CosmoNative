import AppKit
import SwiftUI

struct ElementBlockView: View {
    @Binding var block: RichBlock

    let focusCoordinator: BlockFocusCoordinator
    var fontSize: CGFloat = 17
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ElementBlockHeader(
                title: titleBinding,
                isCollapsed: isCollapsed,
                iconName: iconName,
                titleColor: titleColor,
                iconColor: iconColor,
                chevronColor: chevronColor,
                autoFocusTitle: focusCoordinator.focusedBlockID == block.id,
                onToggleCollapse: toggleCollapse,
                onSubmitTitle: focusBody,
                onTitleFocusChange: handleTitleFocusChange
            )

            if !isCollapsed {
                bodyContent
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay(cardBorder)
        .shadow(color: shadowColor, radius: 4, x: 0, y: 2)
        .animation(ProMotionSprings.snappy, value: isCollapsed)
        .onAppear { focusCoordinator.register(block.id) }
        .onDisappear { focusCoordinator.unregister(block.id) }
    }

    private var bodyContent: some View {
        BlockListView(
            document: childDocumentBinding,
            fontSize: fontSize,
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
            onSelectionChanged: onSelectionChanged,
            onExitFinalEmptyTextRegion: exitBody,
            onDocumentChange: { _, _ in onElementChange?() }
        )
        .padding(.horizontal, DS.space12)
        .padding(.top, DS.space8)
        .padding(.bottom, DS.space12)
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

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(DS.surfaceCard)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(DS.documentBorderSubtle, lineWidth: 1)
    }

    private var shadowColor: Color {
        Color.black.opacity(darkMode ? 0.30 : 0.04)
    }

    private var titleColor: Color {
        if let overrideTextColor {
            return Color(nsColor: overrideTextColor).opacity(0.92)
        }
        return darkMode ? DS.focusImmersiveText.opacity(0.92) : DS.documentText.opacity(0.92)
    }

    private var iconColor: Color {
        darkMode ? DS.focusImmersiveTextSecondary : DS.documentTextSecondary
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
