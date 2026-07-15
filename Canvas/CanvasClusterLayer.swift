// CosmoOS/Canvas/CanvasClusterLayer.swift
// Visual layer rendering cluster zones on the canvas
// Supports both auto-chunked and user-created clusters

import SwiftUI

@MainActor
struct CanvasClusterLayer: View, @preconcurrency Equatable {

    // MARK: - Parameters

    let clusters: [CanvasCluster]
    let blocks: [CanvasBlock]
    let effectiveScale: CGFloat
    var dropTargetClusterId: UUID?
    var selectedClusterId: UUID?
    var resizingClusterId: UUID?
    /// Live drag offsets are read per-cluster inside a tiny host view so a
    /// cluster-drag frame moves only the dragged zone — never re-evaluating
    /// this layer's body. Optional: pane canvases render without drags.
    var interaction: CanvasInteractionState?
    var onRenameCluster: ((UUID, String) -> Void)?
    var onRemoveCluster: ((UUID) -> Void)?
    var onSelectCluster: ((UUID?) -> Void)?
    var onDragCluster: ((UUID, CGSize) -> Void)?
    var onDragEndCluster: ((UUID, CGSize) -> Void)?
    var onResizeCluster: ((UUID, CGSize, ClusterResizeEdge) -> Void)?
    var onResizeEndCluster: ((UUID) -> Void)?
    var onChangeViewMode: ((UUID, ClusterViewMode) -> Void)?
    var onChangeBoardGrouping: ((UUID, ClusterBoardGrouping) -> Void)?
    var onChangeColor: ((UUID, Int) -> Void)?
    var onChangeSortOrder: ((UUID, ClusterSortOrder) -> Void)?
    var onToggleListExpand: ((UUID, String) -> Void)?
    var onBoardColumnDrop: ((BoardDropEvent) -> Void)?
    var onClusterViewDrop: ((ClusterTransferEvent) -> Void)?
    var onOpenFocusMode: ((String) -> Void)?
    var onMagnify: ((CGFloat) -> Void)?
    var onMagnifyEnd: ((CGFloat) -> Void)?
    var expandedBlockUUIDs: [UUID: String] = [:]

    // MARK: - Equatable boundary

    /// Used via `.equatable()` at the call site: the ~20 action closures are
    /// recreated on every parent body evaluation and would defeat SwiftUI's
    /// implicit diffing, so equality compares only the render inputs. When
    /// they match, the entire cluster subtree (glass materials, grid/list/
    /// board member content) is skipped.
    static func == (lhs: CanvasClusterLayer, rhs: CanvasClusterLayer) -> Bool {
        // interaction is a shared reference read via observation inside the
        // per-cluster drag host; it never participates in parent diffing.
        lhs.clusters == rhs.clusters &&
            lhs.blocks == rhs.blocks &&
            lhs.effectiveScale == rhs.effectiveScale &&
            lhs.dropTargetClusterId == rhs.dropTargetClusterId &&
            lhs.selectedClusterId == rhs.selectedClusterId &&
            lhs.resizingClusterId == rhs.resizingClusterId &&
            lhs.expandedBlockUUIDs == rhs.expandedBlockUUIDs
    }

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredClusterID: UUID?
    @State private var editingClusterID: UUID?
    @State private var editingName: String = ""
    @State private var localResizingClusterId: UUID?
    @State private var clusterViewDropPreview: ClusterViewDropPreview?
    @State private var showRecipePopoverForCluster: UUID?

    // MARK: - Body

    var body: some View {
        ZStack {
            ForEach(clusters) { cluster in
                // The drag host applies the live drag offset by reading the
                // interaction state in its own tiny body — drag frames move
                // the dragged zone without re-entering this layer's body.
                ClusterDragOffsetHost(interaction: interaction, clusterId: cluster.id) {
                    clusterZone(cluster)
                }
            }
            // Cluster inspector panel moved to CanvasView unified top-right slot
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "clusterLayer")
    }

    // MARK: - Cluster Zone

    @ViewBuilder
    private func clusterZone(_ cluster: CanvasCluster) -> some View {
        let rect = clusterScreenRect(cluster)
        let isHovered = hoveredClusterID == cluster.id
        let isEditing = editingClusterID == cluster.id
        let isSelected = selectedClusterId == cluster.id
        let showLabel = cluster.isUserCreated || isHovered || effectiveScale < 0.7
        let isZoneCluster = cluster.zoneType != nil
        let hasAltContent = cluster.isUserCreated && (cluster.viewMode != .canvas || isZoneCluster)
        let supportsClusterViewDrop = cluster.isUserCreated && !isZoneCluster
        let clusterViewPreview = clusterViewDropPreview?.clusterId == cluster.id ? clusterViewDropPreview : nil
        let isClusterViewDropTarget = clusterViewPreview != nil
        let isDropTarget = dropTargetClusterId == cluster.id || isClusterViewDropTarget
        let clusterIsResizing = resizingClusterId == cluster.id || localResizingClusterId == cluster.id

        ZStack {
            // Native glass base. Keep the cluster body neutral so blocks and grid
            // remain visible through large zones in both light and dark mode.
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 16)
                .fill(clusterSurfaceFill(cluster: cluster, isDropTarget: isDropTarget, isZone: isZoneCluster))

            // Accent color is only a light wash; the border carries identity.
            RoundedRectangle(cornerRadius: 16)
                .fill(cluster.color.opacity(accentWashOpacity(cluster: cluster, isDropTarget: isDropTarget, isZone: isZoneCluster)))

            if cluster.isUserCreated && (isSelected || isHovered || isDropTarget) {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        cluster.color.opacity(clusterGlowOpacity(isSelected: isSelected, isHovered: isHovered, isDropTarget: isDropTarget)),
                        lineWidth: isSelected || isDropTarget ? 5 : 3
                    )
                    .blur(radius: isSelected || isDropTarget ? 8 : 4)
                    .allowsHitTesting(false)
            }

            if cluster.isUserCreated && (isSelected || isHovered || isDropTarget) {
                clusterGiltCorners(rect: rect, color: cluster.color, isActive: isSelected || isHovered || isDropTarget)
            }

            // Drop-target accent glow
            if isDropTarget {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(cluster.color.opacity(0.28), lineWidth: 4)
                    .blur(radius: 5)
            }

            if showLabel || hasAltContent {
                VStack(spacing: 0) {
                    if showLabel {
                        clusterTitleBar(cluster, isEditing: isEditing, isZone: isZoneCluster, allowDrag: hasAltContent)
                            .frame(height: 42)
                            .padding(.top, 8)
                    } else {
                        Spacer(minLength: 8)
                    }

                    if hasAltContent {
                        clusterAlternativeContent(
                            cluster,
                            clusterWidth: rect.width,
                            clusterHeight: rect.height - 54,
                            isDropTargeted: isClusterViewDropTarget,
                            highlightedBoardColumnValue: clusterViewPreview?.boardColumnValue
                        )
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            clusterOutlineOverlay(
                cluster: cluster,
                isSelected: isSelected,
                isHovered: isHovered,
                isDropTarget: isDropTarget
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onDrop(
            of: [.text],
            delegate: ClusterViewSurfaceDropDelegate(
                enabled: supportsClusterViewDrop,
                cluster: cluster,
                blocks: blocks,
                clusterSize: CGSize(width: rect.width, height: rect.height),
                contentPaddingH: 8,
                preview: $clusterViewDropPreview,
                onBoardColumnDrop: onBoardColumnDrop,
                onClusterViewDrop: onClusterViewDrop
            )
        )
        // Resize handles rendered OUTSIDE the clip shape so edge/corner
        // handles aren't clipped and remain fully interactive in grid/list/board modes
        .overlay {
            if cluster.isUserCreated && isSelected {
                resizeHandlesOverlay(cluster: cluster, rect: rect)
            }
        }
        .allowsHitTesting(cluster.isUserCreated)
        .onTapGesture(count: 1) {
            if cluster.isUserCreated {
                onSelectCluster?(isSelected ? nil : cluster.id)
            }
        }
        .gesture(
            (isZoneCluster || hasAltContent || clusterIsResizing || resizingClusterId != nil || localResizingClusterId != nil)
            ? nil
            : DragGesture(minimumDistance: 10, coordinateSpace: .named("clusterLayer"))
                .onChanged { gesture in
                    guard cluster.isUserCreated else { return }
                    if selectedClusterId != cluster.id { onSelectCluster?(cluster.id) }
                    onDragCluster?(cluster.id, gesture.translation)
                }
                .onEnded { gesture in
                    guard cluster.isUserCreated else { return }
                    onDragEndCluster?(cluster.id, gesture.translation)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("clusterLayer"))
                .onChanged { gesture in
                    guard hasAltContent,
                          cluster.isUserCreated,
                          !isEditing,
                          resizingClusterId == nil,
                          localResizingClusterId == nil,
                          CanvasClusterMoveHitTesting.allowsDragStart(
                            at: gesture.startLocation,
                            in: rect,
                            hasAltContent: hasAltContent
                          ) else { return }
                    if selectedClusterId != cluster.id { onSelectCluster?(cluster.id) }
                    onDragCluster?(cluster.id, gesture.translation)
                }
                .onEnded { gesture in
                    guard hasAltContent,
                          cluster.isUserCreated,
                          !isEditing,
                          resizingClusterId == nil,
                          localResizingClusterId == nil,
                          CanvasClusterMoveHitTesting.allowsDragStart(
                            at: gesture.startLocation,
                            in: rect,
                            hasAltContent: hasAltContent
                          ) else { return }
                    onDragEndCluster?(cluster.id, gesture.translation)
                }
        )
        .onHover { hovered in
            hoveredClusterID = hovered ? cluster.id : nil
        }
        .position(x: rect.midX, y: rect.midY)
        .transaction { tx in
            if clusterIsResizing || draggingCluster(cluster.id) {
                tx.animation = nil
            }
        }
    }

    @ViewBuilder
    private func clusterOutlineOverlay(
        cluster: CanvasCluster,
        isSelected: Bool,
        isHovered: Bool,
        isDropTarget: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)

        ZStack {
            shape
                .strokeBorder(
                    DS.sidebarMaterialBorder.opacity(DS.palette.isDark ? 0.70 : 0.58),
                    lineWidth: 0.5
                )

            shape
                .strokeBorder(
                    cluster.color.opacity(
                        clusterStrokeOpacity(
                            isSelected: isSelected,
                            isHovered: isHovered,
                            isDropTarget: isDropTarget
                        )
                    ),
                    style: StrokeStyle(
                        lineWidth: clusterStrokeWidth(isSelected: isSelected, isDropTarget: isDropTarget),
                        dash: (isSelected || isDropTarget) ? [] : [5, 5]
                    )
                )
                .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isDropTarget)
        }
        .allowsHitTesting(false)
    }

    private func draggingCluster(_ clusterId: UUID) -> Bool {
        interaction?.draggingClusterId == clusterId
    }

    private func clusterSurfaceFill(cluster: CanvasCluster, isDropTarget: Bool, isZone: Bool) -> Color {
        DS.canvasClusterSurfaceFill(
            isDropTarget: isDropTarget,
            isUserCreated: cluster.isUserCreated,
            usesExpandedContent: cluster.viewMode != .canvas || isZone
        )
    }

    private func accentWashOpacity(cluster: CanvasCluster, isDropTarget: Bool, isZone: Bool) -> Double {
        DS.canvasClusterAccentWashOpacity(
            isDropTarget: isDropTarget,
            isUserCreated: cluster.isUserCreated,
            usesExpandedContent: cluster.viewMode != .canvas || isZone
        )
    }

    private func clusterStrokeOpacity(isSelected: Bool, isHovered: Bool, isDropTarget: Bool) -> Double {
        DS.canvasClusterStrokeOpacity(
            isSelected: isSelected,
            isHovered: isHovered,
            isDropTarget: isDropTarget
        )
    }

    private func clusterStrokeWidth(isSelected: Bool, isDropTarget: Bool) -> CGFloat {
        if isDropTarget { return 2.75 }
        if isSelected { return 2.1 }
        return 1.15
    }

    private func clusterGlowOpacity(isSelected: Bool, isHovered: Bool, isDropTarget: Bool) -> Double {
        if isDropTarget { return 0.20 }
        if isSelected { return 0.12 }
        if isHovered { return 0.06 }
        return 0
    }

    // MARK: - Gilt Corner Brackets

    /// Four subtle accent L-brackets shown only while a cluster is active.
    @ViewBuilder
    private func clusterGiltCorners(rect: CGRect, color: Color, isActive: Bool) -> some View {
        let opacity = isActive ? (DS.palette.isDark ? 0.48 : 0.34) : 0
        let size: CGFloat = 14
        let inset: CGFloat = 10
        let stroke = color.opacity(opacity)

        ZStack {
            // Top-left
            GiltCornerBracket()
                .stroke(stroke, lineWidth: isActive ? 1.15 : 0.95)
                .frame(width: size, height: size)
                .position(x: inset + size / 2, y: inset + size / 2)

            // Top-right (rotated 90°)
            GiltCornerBracket()
                .stroke(stroke, lineWidth: isActive ? 1.15 : 0.95)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(90))
                .position(x: rect.width - inset - size / 2, y: inset + size / 2)

            // Bottom-right (rotated 180°)
            GiltCornerBracket()
                .stroke(stroke, lineWidth: isActive ? 1.15 : 0.95)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(180))
                .position(x: rect.width - inset - size / 2, y: rect.height - inset - size / 2)

            // Bottom-left (rotated 270°)
            GiltCornerBracket()
                .stroke(stroke, lineWidth: isActive ? 1.15 : 0.95)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(270))
                .position(x: inset + size / 2, y: rect.height - inset - size / 2)
        }
        .frame(width: rect.width, height: rect.height)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Title Bar

    @ViewBuilder
    private func clusterTitleBar(_ cluster: CanvasCluster, isEditing: Bool, isZone: Bool, allowDrag: Bool = false) -> some View {
        HStack(spacing: 6) {
            if allowDrag {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textMuted)
            }
            if isZone, let zt = CommandCenterZoneType(rawValue: cluster.zoneType ?? "") {
                Image(systemName: zt.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(cluster.color)
            }
            clusterLabel(cluster, isEditing: isEditing)

            // Automation rule indicator
            if cluster.isUserCreated {
                ClusterRuleIndicator(
                    clusterId: cluster.id,
                    clusterColor: cluster.color,
                    ruleCount: AutomationDispatcher.shared.activeRuleCount(for: cluster.id.uuidString),
                    onAddRule: {
                        showRecipePopoverForCluster = cluster.id
                    }
                )
                .popover(isPresented: Binding(
                    get: { showRecipePopoverForCluster == cluster.id },
                    set: { if !$0 { showRecipePopoverForCluster = nil } }
                )) {
                    AutomationRecipePopover(
                        clusterId: cluster.id.uuidString,
                        clusterName: cluster.name,
                        clusterColor: cluster.color,
                        onDismiss: {
                            showRecipePopoverForCluster = nil
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Alternative Content (List / Board)

    @ViewBuilder
    private func clusterAlternativeContent(
        _ cluster: CanvasCluster,
        clusterWidth: CGFloat,
        clusterHeight: CGFloat,
        isDropTargeted: Bool,
        highlightedBoardColumnValue: String?
    ) -> some View {
        if let zoneType = cluster.zoneType {
            let zoneWidth = max(clusterWidth - 4, 100)
            let zoneHeight = max(clusterHeight - 8, 100)

            ZoneContentView(
                zoneType: zoneType,
                contentSize: CGSize(width: zoneWidth, height: zoneHeight),
                effectiveScale: effectiveScale
            )
            .frame(width: zoneWidth, height: zoneHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            let contentWidth = max(clusterWidth - 4, 120)
            let contentHeight = max(clusterHeight - 8, 120)
            // Member-scoped: each content view receives only its own members
            // so an edit to any other block on the canvas no longer re-diffs
            // every cluster's grid/list/board subtree.
            let memberBlocks = memberBlocks(for: cluster)

            Group {
                switch cluster.viewMode {
                case .canvas:
                    EmptyView()
                case .list:
                    ClusterListContent(
                        cluster: cluster,
                        clusterColor: cluster.color,
                        blocks: memberBlocks,
                        isDropTargeted: isDropTargeted,
                        sortOrder: cluster.sortOrder,
                        expandedBlockUUID: expandedBlockUUIDs[cluster.id],
                        onChangeSortOrder: { order in
                            onChangeSortOrder?(cluster.id, order)
                        },
                        onToggleExpand: { blockUUID in
                            onToggleListExpand?(cluster.id, blockUUID)
                        },
                        onOpenFocusMode: { uuid in
                            onOpenFocusMode?(uuid)
                        }
                    )
                case .board:
                    ClusterBoardContent(
                        cluster: cluster,
                        clusterColor: cluster.color,
                        blocks: memberBlocks,
                        highlightedColumnValue: highlightedBoardColumnValue,
                        onOpenFocusMode: { uuid in
                            onOpenFocusMode?(uuid)
                        }
                    )
                case .grid:
                    ClusterGridContent(
                        cluster: cluster,
                        clusterColor: cluster.color,
                        blocks: memberBlocks,
                        isDropTargeted: isDropTargeted,
                        onOpenFocusMode: { uuid in
                            onOpenFocusMode?(uuid)
                        }
                    )
                }
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // Allow pinch-to-zoom to pass through cluster ScrollViews to the canvas
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        onMagnify?(value.magnification)
                    }
                    .onEnded { value in
                        onMagnifyEnd?(value.magnification)
                    }
            )
        }
    }

    // MARK: - Resize Handles

    @ViewBuilder
    private func resizeHandlesOverlay(cluster: CanvasCluster, rect: CGRect) -> some View {
        let handleSize: CGFloat = 10
        let hitSize: CGFloat = 28

        ZStack {
            resizeHandle(cluster: cluster, edge: .topLeft, handleSize: handleSize, hitSize: hitSize)
                .position(x: 0, y: 0)
            resizeHandle(cluster: cluster, edge: .topRight, handleSize: handleSize, hitSize: hitSize)
                .position(x: rect.width, y: 0)
            resizeHandle(cluster: cluster, edge: .bottomLeft, handleSize: handleSize, hitSize: hitSize)
                .position(x: 0, y: rect.height)
            resizeHandle(cluster: cluster, edge: .bottomRight, handleSize: handleSize, hitSize: hitSize)
                .position(x: rect.width, y: rect.height)
            resizeHandle(cluster: cluster, edge: .top, handleSize: handleSize, hitSize: hitSize)
                .position(x: rect.width / 2, y: 0)
            resizeHandle(cluster: cluster, edge: .bottom, handleSize: handleSize, hitSize: hitSize)
                .position(x: rect.width / 2, y: rect.height)
            resizeHandle(cluster: cluster, edge: .left, handleSize: handleSize, hitSize: hitSize)
                .position(x: 0, y: rect.height / 2)
            resizeHandle(cluster: cluster, edge: .right, handleSize: handleSize, hitSize: hitSize)
                .position(x: rect.width, y: rect.height / 2)
        }
        .frame(width: rect.width, height: rect.height)
    }

    @ViewBuilder
    private func resizeHandle(cluster: CanvasCluster, edge: ClusterResizeEdge, handleSize: CGFloat, hitSize: CGFloat) -> some View {
        let isCorner: Bool = {
            switch edge {
            case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
            default: return false
            }
        }()

        Circle()
            .fill(DS.surfaceElevated)
            .overlay(Circle().stroke(cluster.color.opacity(0.8), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            .frame(width: isCorner ? handleSize : handleSize * 0.8, height: isCorner ? handleSize : handleSize * 0.8)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("clusterLayer"))
                    .onChanged { gesture in
                        if localResizingClusterId != cluster.id {
                            localResizingClusterId = cluster.id
                        }
                        onResizeCluster?(cluster.id, gesture.translation, edge)
                    }
                    .onEnded { _ in
                        onResizeEndCluster?(cluster.id)
                        if localResizingClusterId == cluster.id {
                            localResizingClusterId = nil
                        }
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeCursor(for: edge).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }

    // MARK: - Label

    @ViewBuilder
    private func clusterLabel(_ cluster: CanvasCluster, isEditing: Bool) -> some View {
        if isEditing {
            TextField("Name", text: $editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DS.text)
                .multilineTextAlignment(.leading)
                .frame(minWidth: 100, maxWidth: 200)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.surfaceElevated)
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cluster.color.opacity(0.35), lineWidth: 1)
                )
                .onSubmit { commitRename(cluster) }
                .onExitCommand { editingClusterID = nil }
        } else {
            Text(cluster.name)
                .dsSmallCapsLabel()
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.vellum)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.sepiaBorder, lineWidth: 0.5)
                )
                .onTapGesture(count: 2) {
                    if cluster.isUserCreated {
                        editingName = cluster.name
                        editingClusterID = cluster.id
                    }
                }
        }
    }

    // MARK: - Rename

    private func commitRename(_ cluster: CanvasCluster) {
        let newName = editingName.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty {
            onRenameCluster?(cluster.id, newName)
        }
        editingClusterID = nil
    }

    /// The cluster's own member blocks, in canvas order.
    private func memberBlocks(for cluster: CanvasCluster) -> [CanvasBlock] {
        let uuids = Set(cluster.blockUUIDs)
        return blocks.filter { uuids.contains($0.entityUuid) }
    }

    // MARK: - Coordinate Conversion

    private func clusterScreenRect(_ cluster: CanvasCluster) -> CGRect {
        let origin = cluster.boundingRect.origin
        let size = cluster.boundingRect.size
        return CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}

enum CanvasClusterMoveHitTesting {
    private static let altContentHeaderHeight: CGFloat = 58
    private static let altContentChromeGutter: CGFloat = 18

    static func allowsDragStart(at point: CGPoint, in rect: CGRect, hasAltContent: Bool) -> Bool {
        guard hasAltContent else { return rect.contains(point) }
        guard rect.contains(point) else { return false }

        if point.y <= rect.minY + altContentHeaderHeight {
            return true
        }

        return point.x <= rect.minX + altContentChromeGutter ||
            point.x >= rect.maxX - altContentChromeGutter ||
            point.y >= rect.maxY - altContentChromeGutter
    }
}

private struct ClusterViewDropPreview: Equatable {
    let clusterId: UUID
    let boardColumnValue: String?
}

@MainActor
enum ClusterViewDragSession {
    static var sourceClusterId: UUID?
}

private struct ClusterViewSurfaceDropDelegate: DropDelegate {
    let enabled: Bool
    let cluster: CanvasCluster
    let blocks: [CanvasBlock]
    let clusterSize: CGSize
    /// Horizontal padding between the cluster edge and the content area (for board column calculation)
    let contentPaddingH: CGFloat
    @Binding var preview: ClusterViewDropPreview?
    let onBoardColumnDrop: ((BoardDropEvent) -> Void)?
    let onClusterViewDrop: ((ClusterTransferEvent) -> Void)?

    /// A cluster surface accepts intra-canvas block transfers (a block dragged
    /// from one cluster/the canvas into this one). A Command-K "retrieve" drag
    /// is a different verb: it must place a NEW block on the canvas at the drop
    /// point, so the cluster surface declines and lets the drop fall through to
    /// the canvas drop delegate behind it. Its `.text` payload is otherwise
    /// indistinguishable, and the cluster's drop rect bleeds into the white
    /// space around its content, so without this guard a Command-K card
    /// released near a cluster is swallowed (no matching existing block →
    /// silent no-op) instead of being placed.
    private var isCommandKRetrieveDrag: Bool {
        CommandKDragSession.shared.isActive
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard !isCommandKRetrieveDrag else { return false }
        return enabled && info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        guard !isCommandKRetrieveDrag else { return }
        updatePreview(for: info, animated: true)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !isCommandKRetrieveDrag else { return nil }
        updatePreview(for: info, animated: false)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearPreview(animated: true)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Command-K retrieve drags are the canvas's to place; never consume them.
        guard !isCommandKRetrieveDrag else { return false }
        guard previewTarget(for: info) != nil else {
            clearPreview(animated: true)
            ClusterViewDragSession.sourceClusterId = nil
            return false
        }

        let target = previewTarget(for: info)
        clearPreview(animated: true)

        let providers = info.itemProviders(for: [.text])
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
                guard let blockUUID = blockUUID(from: item) else { return }
                DispatchQueue.main.async {
                    switch cluster.viewMode {
                    case .board:
                        guard let block = blocks.first(where: { $0.entityUuid == blockUUID }) else { return }
                        let targetColumnValue = target?.boardColumnValue ?? cluster.defaultBoardDropColumnValue(for: block, among: blocks)
                        onBoardColumnDrop?(
                            BoardDropEvent(
                                blockUUID: blockUUID,
                                targetClusterId: cluster.id,
                                targetColumnValue: targetColumnValue
                            )
                        )
                    case .list, .grid, .canvas:
                        onClusterViewDrop?(
                            ClusterTransferEvent(
                                blockUUID: blockUUID,
                                targetClusterId: cluster.id
                            )
                        )
                    }
                }
            }
        }

        ClusterViewDragSession.sourceClusterId = nil
        return true
    }

    private func updatePreview(for info: DropInfo, animated: Bool) {
        setPreview(previewTarget(for: info), animated: animated)
    }

    private func clearPreview(animated: Bool) {
        guard preview?.clusterId == cluster.id else { return }
        setPreview(nil, animated: animated)
    }

    private func setPreview(_ newValue: ClusterViewDropPreview?, animated: Bool) {
        guard preview != newValue else { return }
        if animated {
            withAnimation(ProMotionSprings.snappy) {
                preview = newValue
            }
        } else {
            preview = newValue
        }
    }

    private func previewTarget(for info: DropInfo) -> ClusterViewDropPreview? {
        guard validateDrop(info: info) else { return nil }
        guard ClusterViewDragSession.sourceClusterId != cluster.id else { return nil }

        switch cluster.viewMode {
        case .board:
            let adjustedX = info.location.x - contentPaddingH
            let contentWidth = max(clusterSize.width - contentPaddingH * 2, 1)
            return ClusterViewDropPreview(
                clusterId: cluster.id,
                boardColumnValue: cluster.boardDropColumnValue(
                    for: adjustedX,
                    clusterWidth: contentWidth,
                    blocks: blocks
                )
            )
        case .list, .grid, .canvas:
            return ClusterViewDropPreview(clusterId: cluster.id, boardColumnValue: nil)
        }
    }

    private func blockUUID(from item: NSSecureCoding?) -> String? {
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        if let text = item as? String {
            return text
        }
        if let text = item as? NSString {
            return text as String
        }
        return nil
    }
}

// MARK: - Resize Cursor Helper

extension NSCursor {
    static func resizeCursor(for edge: ClusterResizeEdge) -> NSCursor {
        switch edge {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        }
    }
}

// MARK: - Notification Extension

extension CosmoNotification.Canvas {
    static let createClusterFromSelection = Notification.Name("com.cosmo.canvas.createClusterFromSelection")
}

// MARK: - Cluster Drag Offset Host

/// Applies the live cluster-drag offset by reading the interaction state in
/// its own body: drag frames invalidate only the dragged cluster's host (a
/// compositor translation), while every other cluster reads just the stable
/// dragged-id field and stays untouched.
private struct ClusterDragOffsetHost<Content: View>: View {
    let interaction: CanvasInteractionState?
    let clusterId: UUID
    @ViewBuilder var content: Content

    var body: some View {
        let offset = interaction?.clusterDragOffset(for: clusterId) ?? .zero
        content
            .offset(x: offset.width, y: offset.height)
    }
}
