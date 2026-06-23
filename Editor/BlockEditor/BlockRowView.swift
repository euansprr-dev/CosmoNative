import SwiftUI
import UniformTypeIdentifiers

struct BlockRowView<Content: View>: View {
    let block: RichBlock
    let path: BlockPath
    var darkMode: Bool = false
    var isSelected: Bool = false
    var onMove: (BlockDragPayload, BlockDropTarget) -> Void
    var onInsertBelow: (() -> Void)? = nil
    /// Plain click on the six-dot handle — the list selects the block before
    /// the menu opens. Shift+click extends the selection instead.
    var onHandleClick: (() -> Void)? = nil
    var onHandleShiftClick: (() -> Void)? = nil
    var handleMenu: (() -> BlockHandleMenuView)? = nil
    @ViewBuilder var content: Content

    @State private var isHovered = false
    @State private var isMenuPresented = false
    @State private var highlightedDropPosition: BlockDropPosition?

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            gutter
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(selectionWash)
        }
        .overlay(alignment: .top) { dropZone(.above) }
        .overlay(alignment: .bottom) { dropZone(.below) }
        .overlay(alignment: .top) { dropIndicator(for: .above) }
        .overlay(alignment: .bottom) { dropIndicator(for: .below) }
        .onHover { isHovered = $0 }
    }

    // MARK: - Gutter (＋ and ⋮⋮)

    private var gutter: some View {
        let metrics = BlockInteractionPolicy.handleMetrics(for: block.kind)
        return HStack(alignment: .top, spacing: 2) {
            insertButton(metrics: metrics)
            dragHandle(metrics: metrics)
        }
        .opacity(gutterOpacity)
        .animation(.spring(response: BlockMotionPolicy.chromeResponse, dampingFraction: BlockMotionPolicy.chromeDampingFraction), value: isHovered)
        .animation(.spring(response: BlockMotionPolicy.dropResponse, dampingFraction: BlockMotionPolicy.dropDampingFraction), value: highlightedDropPosition)
    }

    private var gutterOpacity: Double {
        let chrome = BlockInteractionPolicy.chrome(
            isHovered: BlockInteractionPolicy.revealsHandleChrome(
                isHovered: isHovered,
                isSelected: isSelected,
                isMenuPresented: isMenuPresented,
                isDropTarget: highlightedDropPosition != nil
            ),
            isDropTarget: highlightedDropPosition != nil,
            darkMode: darkMode
        )
        return chrome.handleOpacity
    }

    private func insertButton(metrics: BlockInteractionPolicy.HandleMetrics) -> some View {
        Button {
            onInsertBelow?()
        } label: {
            Image(systemName: "plus")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(handleColor)
                .frame(width: 22, height: metrics.hitSize.height)
                .padding(.top, metrics.topPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add block below")
        .accessibilityLabel("Add block below")
    }

    private func dragHandle(metrics: BlockInteractionPolicy.HandleMetrics) -> some View {
        Button {
            if NSEvent.modifierFlags.contains(.shift) {
                onHandleShiftClick?()
            } else {
                onHandleClick?()
                if handleMenu != nil {
                    isMenuPresented = true
                }
            }
        } label: {
            sixDotGlyph(color: isMenuPresented ? DS.accent : handleColor)
                .frame(width: 24, height: metrics.hitSize.height)
                .padding(.top, metrics.topPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open block menu — drag to move")
        .accessibilityLabel("Block menu")
        .accessibilityHint("Click for block actions, drag to reorder")
        .onDrag {
            let data = BlockDropController.encodedPayload(BlockDragPayload(blockID: block.id, sourcePath: path))
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.json.identifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }
        .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
            handleMenu?()
        }
    }

    private var handleColor: Color {
        darkMode ? Color.white.opacity(0.45) : DS.documentTextMuted.opacity(0.8)
    }

    /// The Notion-style six-dot grip, drawn directly — there is no macOS SF
    /// Symbol for a 2×3 dot grid.
    private func sixDotGlyph(color: Color) -> some View {
        HStack(spacing: 2.5) {
            sixDotColumn(color: color)
            sixDotColumn(color: color)
        }
        .accessibilityHidden(true)
    }

    private func sixDotColumn(color: Color) -> some View {
        VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(color)
                    .frame(width: 2.5, height: 2.5)
            }
        }
    }

    // MARK: - Selection

    @ViewBuilder
    private var selectionWash: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.accentSoft.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DS.accent.opacity(0.22), lineWidth: 1)
                )
                .padding(.vertical, -2)
                .padding(.horizontal, -4)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Drop Targets

    private func dropZone(_ position: BlockDropPosition) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 14)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.json.identifier],
                delegate: BlockRowDropDelegate(
                    path: path,
                    position: position,
                    highlightedDropPosition: $highlightedDropPosition,
                    onMove: onMove
                )
            )
    }

    @ViewBuilder
    private func dropIndicator(for position: BlockDropPosition) -> some View {
        if highlightedDropPosition == position {
            let chrome = BlockInteractionPolicy.chrome(
                isHovered: isHovered,
                isDropTarget: true,
                darkMode: darkMode
            )
            Rectangle()
                .fill(DS.accent.opacity(darkMode ? 0.86 : 0.72))
                .frame(height: chrome.dropIndicatorHeight)
                .padding(.leading, chrome.reservedLeadingWidth)
                .opacity(chrome.dropIndicatorOpacity)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}

private struct BlockRowDropDelegate: DropDelegate {
    let path: BlockPath
    let position: BlockDropPosition
    @Binding var highlightedDropPosition: BlockDropPosition?
    var onMove: (BlockDragPayload, BlockDropTarget) -> Void

    func dropEntered(info: DropInfo) {
        highlightedDropPosition = position
    }

    func dropExited(info: DropInfo) {
        if highlightedDropPosition == position {
            highlightedDropPosition = nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.json.identifier])
    }

    func performDrop(info: DropInfo) -> Bool {
        highlightedDropPosition = nil
        guard let provider = info.itemProviders(for: [UTType.json.identifier]).first else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
            guard let data,
                  let payload = BlockDropController.decodedPayload(data) else {
                return
            }
            let target = BlockDropController.target(for: position, path: path)
            guard BlockDropController.canMove(from: payload.sourcePath, to: target) else {
                return
            }
            DispatchQueue.main.async {
                onMove(payload, target)
            }
        }
        return true
    }
}
