import SwiftUI
import UniformTypeIdentifiers

struct BlockRowView<Content: View>: View {
    let block: RichBlock
    let path: BlockPath
    var darkMode: Bool = false
    var onMove: (BlockDragPayload, BlockDropTarget) -> Void
    @ViewBuilder var content: Content

    @State private var isHovered = false
    @State private var highlightedDropPosition: BlockDropPosition?

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            dragHandle
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .top) {
            dropZone(.above)
        }
        .overlay(alignment: .bottom) {
            dropZone(.below)
        }
        .overlay(alignment: .top) {
            dropIndicator(for: .above)
        }
        .overlay(alignment: .bottom) {
            dropIndicator(for: .below)
        }
        .onHover { isHovered = $0 }
    }

    private var dragHandle: some View {
        let metrics = BlockInteractionPolicy.handleMetrics(for: block.kind)
        let chrome = BlockInteractionPolicy.chrome(
            isHovered: isHovered,
            isDropTarget: highlightedDropPosition != nil,
            darkMode: darkMode
        )

        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(handleColor)
            .frame(width: metrics.hitSize.width, height: metrics.hitSize.height)
            .padding(.top, metrics.topPadding)
            .contentShape(Rectangle())
            .opacity(chrome.handleOpacity)
            .accessibilityLabel("Move block")
            .accessibilityHint("Drag to reorder this block")
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
            .animation(.spring(response: BlockMotionPolicy.chromeResponse, dampingFraction: BlockMotionPolicy.chromeDampingFraction), value: isHovered)
            .animation(.spring(response: BlockMotionPolicy.dropResponse, dampingFraction: BlockMotionPolicy.dropDampingFraction), value: highlightedDropPosition)
    }

    private var handleColor: Color {
        darkMode ? Color.white.opacity(0.45) : DS.documentTextMuted.opacity(0.8)
    }

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
