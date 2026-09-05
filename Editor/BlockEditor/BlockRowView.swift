import SwiftUI
import UniformTypeIdentifiers

/// Row-scoped hover signal. The hover REGION is the whole row, but the only
/// thing that changes on hover is the gutter chrome — routing the flag
/// through an observable box means a pointer crossing re-renders just the
/// small gutter subview instead of the row's full overlay/drop-zone tree.
@MainActor
@Observable
final class BlockRowHoverBox {
    var isHovered = false
}

struct BlockRowView<Content: View>: View {
    let block: RichBlock
    let path: BlockPath
    var darkMode: Bool = false
    var isSelected: Bool = false
    /// Drop commit: payload + the drop position relative to THIS row's block.
    /// Positions are resolved by block ID at commit time — the payload's
    /// sourcePath and this row's captured path may both be stale by then.
    var onMove: (BlockDragPayload, BlockDropPosition, UUID) -> Void
    var onInsertBelow: (() -> Void)? = nil
    /// Plain click on the six-dot handle — the list selects the block before
    /// the menu opens. Shift+click extends the selection instead.
    var onHandleClick: (() -> Void)? = nil
    var onHandleShiftClick: (() -> Void)? = nil
    var handleMenu: (() -> BlockHandleMenuView)? = nil
    @ViewBuilder var content: Content

    @State private var hoverBox = BlockRowHoverBox()
    @State private var highlightedDropPosition: BlockDropPosition?
    @State private var rowHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            BlockRowGutter(
                block: block,
                path: path,
                darkMode: darkMode,
                isSelected: isSelected,
                highlightedDropPosition: highlightedDropPosition,
                hoverBox: hoverBox,
                onInsertBelow: onInsertBelow,
                onHandleClick: onHandleClick,
                onHandleShiftClick: onHandleShiftClick,
                handleMenu: handleMenu
            )
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(selectionWash)
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        // A drop destination on the row does not put a transparent view on
        // top of the text or handle. One region resolves above/below by y.
        .onDrop(of: [UTType.json.identifier], delegate: BlockRowDropDelegate(
            targetBlockID: block.id,
            rowHeight: rowHeight,
            highlightedDropPosition: $highlightedDropPosition,
            onMove: onMove
        ))
        .overlay(alignment: .top) { dropIndicator(for: .above) }
        .overlay(alignment: .bottom) { dropIndicator(for: .below) }
        .onHover { hovering in
            if hoverBox.isHovered != hovering {
                hoverBox.isHovered = hovering
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

    @ViewBuilder
    private func dropIndicator(for position: BlockDropPosition) -> some View {
        if highlightedDropPosition == position {
            // Reading the hover box here is safe: this branch only exists
            // while a drag highlight is active, so the row body tracks hover
            // only during drags, never in the steady state.
            let chrome = BlockInteractionPolicy.chrome(
                isHovered: hoverBox.isHovered,
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
                .allowsHitTesting(false)
        }
    }
}

/// The ＋ / ⋮⋮ gutter. Owns the hover read and the menu-presented state so a
/// pointer crossing (or menu toggle) re-renders only this small subtree.
private struct BlockRowGutter: View {
    let block: RichBlock
    let path: BlockPath
    let darkMode: Bool
    let isSelected: Bool
    let highlightedDropPosition: BlockDropPosition?
    let hoverBox: BlockRowHoverBox
    let onInsertBelow: (() -> Void)?
    let onHandleClick: (() -> Void)?
    let onHandleShiftClick: (() -> Void)?
    let handleMenu: (() -> BlockHandleMenuView)?

    @State private var isMenuPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = BlockInteractionPolicy.handleMetrics(for: block.kind)
        HStack(alignment: .top, spacing: 2) {
            insertButton(metrics: metrics)
            dragHandle(metrics: metrics)
        }
        .contentShape(Rectangle())
        .opacity(gutterOpacity)
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: gutterOpacity)
    }

    private var gutterOpacity: Double {
        let chrome = BlockInteractionPolicy.chrome(
            isHovered: BlockInteractionPolicy.revealsHandleChrome(
                isHovered: hoverBox.isHovered,
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
}

private struct BlockRowDropDelegate: DropDelegate {
    /// The block this drop zone belongs to — the drop TARGET is resolved from
    /// this ID at commit time, never from a captured path (rows can skip
    /// re-renders across structural shifts, so captured paths go stale).
    let targetBlockID: UUID
    let rowHeight: CGFloat
    @Binding var highlightedDropPosition: BlockDropPosition?
    var onMove: (BlockDragPayload, BlockDropPosition, UUID) -> Void

    func dropEntered(info: DropInfo) {
        highlightedDropPosition = position(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        highlightedDropPosition = position(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        highlightedDropPosition = nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.json.identifier])
    }

    func performDrop(info: DropInfo) -> Bool {
        let position = position(for: info)
        highlightedDropPosition = nil
        guard let provider = info.itemProviders(for: [UTType.json.identifier]).first else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
            guard let data,
                  let payload = BlockDropController.decodedPayload(data) else {
                return
            }
            DispatchQueue.main.async {
                onMove(payload, position, targetBlockID)
            }
        }
        return true
    }

    private func position(for info: DropInfo) -> BlockDropPosition {
        info.location.y < rowHeight / 2 ? .above : .below
    }
}
