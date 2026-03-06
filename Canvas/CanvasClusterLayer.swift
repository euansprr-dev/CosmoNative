// CosmoOS/Canvas/CanvasClusterLayer.swift
// Visual layer rendering cluster zones on the canvas
// Supports both auto-chunked and user-created clusters

import SwiftUI

@MainActor
struct CanvasClusterLayer: View {

    // MARK: - Parameters

    let clusters: [CanvasCluster]
    let blocks: [CanvasBlock]
    let canvasSize: CGSize
    let canvasOffset: CGSize
    let scaledPanOffset: CGSize
    let effectiveScale: CGFloat
    var dropTargetClusterId: UUID?
    var selectedClusterId: UUID?
    var resizingClusterId: UUID?
    var clusterDragOffset: CGSize?
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
    var onOpenFocusMode: ((String) -> Void)?
    var expandedBlockUUIDs: [UUID: String] = [:]

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredClusterID: UUID?
    @State private var editingClusterID: UUID?
    @State private var editingName: String = ""
    @State private var localResizingClusterId: UUID?

    // MARK: - Body

    var body: some View {
        ZStack {
            ForEach(clusters) { cluster in
                clusterZone(cluster)
            }
            inspectorPanelOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "clusterLayer")
    }

    // MARK: - Inspector Panel Overlay

    @ViewBuilder
    private var inspectorPanelOverlay: some View {
        if let selected = selectedUserCluster {
            inspectorPanel(for: selected)
        }
    }

    @ViewBuilder
    private func inspectorPanel(for cluster: CanvasCluster) -> some View {
        let baseRect = clusterScreenRect(cluster)
        let drag = (selectedClusterId == cluster.id) ? (clusterDragOffset ?? .zero) : .zero
        let rect = baseRect.offsetBy(dx: drag.width, dy: drag.height)
        let panelSize = CGSize(width: 276, height: cluster.viewMode == .board ? 286 : 242)
        let margin: CGFloat = 16

        let desiredX = rect.maxX + 12
        let desiredY = rect.minY
        let maxX = max(margin, canvasSize.width - panelSize.width - margin)
        let maxY = max(margin, canvasSize.height - panelSize.height - margin)
        let clampedX = min(max(desiredX, margin), maxX)
        let clampedY = min(max(desiredY, margin), maxY)

        ClusterInspectorPanel(
            cluster: cluster,
            onChangeColor: { colorIndex in
                onChangeColor?(cluster.id, colorIndex)
            },
            onChangeViewMode: { mode in
                onChangeViewMode?(cluster.id, mode)
            },
            onChangeBoardGrouping: { grouping in
                onChangeBoardGrouping?(cluster.id, grouping)
            },
            onDelete: {
                onRemoveCluster?(cluster.id)
                onSelectCluster?(nil)
            },
            onDismiss: {
                onSelectCluster?(nil)
            }
        )
        .frame(width: panelSize.width)
        .position(
            x: clampedX + panelSize.width / 2,
            y: clampedY + panelSize.height / 2
        )
        .transition(.opacity)
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: selectedClusterId)
    }

    private var selectedUserCluster: CanvasCluster? {
        guard let id = selectedClusterId else { return nil }
        return clusters.first(where: { $0.id == id && $0.isUserCreated })
    }

    // MARK: - Cluster Zone

    @ViewBuilder
    private func clusterZone(_ cluster: CanvasCluster) -> some View {
        let rect = clusterScreenRect(cluster)
        let isHovered = hoveredClusterID == cluster.id
        let isEditing = editingClusterID == cluster.id
        let isDropTarget = dropTargetClusterId == cluster.id
        let isSelected = selectedClusterId == cluster.id
        let showLabel = cluster.isUserCreated || isHovered || effectiveScale < 0.7
        let isZoneCluster = cluster.zoneType != nil
        let hasAltContent = cluster.isUserCreated && (cluster.viewMode != .canvas || isZoneCluster)
        let clusterIsResizing = resizingClusterId == cluster.id || localResizingClusterId == cluster.id
        let dragOffset = draggingCluster(cluster.id) ? (clusterDragOffset ?? .zero) : .zero

        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(cluster.color.opacity(backgroundOpacity(cluster: cluster, isDropTarget: isDropTarget, isZone: isZoneCluster)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected ? cluster.color.opacity(0.55) : cluster.color.opacity(isDropTarget ? 0.5 : 0.2),
                            style: StrokeStyle(
                                lineWidth: isSelected || isDropTarget ? 2 : 1.5,
                                dash: (isSelected || isDropTarget) ? [] : [4, 4]
                            )
                        )
                )
                .shadow(color: isDropTarget ? cluster.color.opacity(0.22) : .clear, radius: isDropTarget ? 10 : 0)
                .animation(reduceMotion ? nil : ProMotionSprings.hover, value: isDropTarget)

            if showLabel || hasAltContent {
                VStack(spacing: 0) {
                    if showLabel {
                        clusterTitleBar(cluster, isEditing: isEditing, isZone: isZoneCluster)
                            .frame(height: 42)
                            .padding(.top, 8)
                    } else {
                        Spacer(minLength: 8)
                    }

                    if hasAltContent {
                        clusterAlternativeContent(
                            cluster,
                            clusterWidth: rect.width,
                            clusterHeight: rect.height - 54
                        )
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }

            if cluster.isUserCreated && isSelected {
                resizeHandlesOverlay(cluster: cluster, rect: rect)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(cluster.isUserCreated)
        .onTapGesture(count: 1) {
            if cluster.isUserCreated {
                onSelectCluster?(isSelected ? nil : cluster.id)
            }
        }
        .gesture(
            (isZoneCluster || clusterIsResizing || resizingClusterId != nil || localResizingClusterId != nil)
            ? nil
            : DragGesture(minimumDistance: 10)
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
        .onHover { hovered in
            hoveredClusterID = hovered ? cluster.id : nil
        }
        .position(x: rect.midX, y: rect.midY)
        .offset(x: dragOffset.width, y: dragOffset.height)
        .transaction { tx in
            if clusterIsResizing || draggingCluster(cluster.id) {
                tx.animation = nil
            }
        }
    }

    private func draggingCluster(_ clusterId: UUID) -> Bool {
        selectedClusterId == clusterId && clusterDragOffset != nil
    }

    private func backgroundOpacity(cluster: CanvasCluster, isDropTarget: Bool, isZone: Bool) -> Double {
        if isDropTarget { return 0.12 }
        if cluster.isUserCreated {
            return (cluster.viewMode != .canvas || isZone) ? 0.09 : 0.06
        }
        return 0.05
    }

    // MARK: - Title Bar

    @ViewBuilder
    private func clusterTitleBar(_ cluster: CanvasCluster, isEditing: Bool, isZone: Bool) -> some View {
        HStack(spacing: 6) {
            if isZone, let zt = CommandCenterZoneType(rawValue: cluster.zoneType ?? "") {
                Image(systemName: zt.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(cluster.color)
            }
            clusterLabel(cluster, isEditing: isEditing)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .gesture(
            (isZone && !isEditing && resizingClusterId == nil && localResizingClusterId == nil)
            ? DragGesture(minimumDistance: 10)
                .onChanged { gesture in
                    if selectedClusterId != cluster.id { onSelectCluster?(cluster.id) }
                    onDragCluster?(cluster.id, gesture.translation)
                }
                .onEnded { gesture in
                    onDragEndCluster?(cluster.id, gesture.translation)
                }
            : nil
        )
    }

    // MARK: - Alternative Content (List / Board)

    @ViewBuilder
    private func clusterAlternativeContent(_ cluster: CanvasCluster, clusterWidth: CGFloat, clusterHeight: CGFloat) -> some View {
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

            Group {
                switch cluster.viewMode {
                case .canvas:
                    EmptyView()
                case .list:
                    ClusterListContent(
                        cluster: cluster,
                        clusterColor: cluster.color,
                        blocks: blocks,
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
                        blocks: blocks,
                        onBoardColumnDrop: { event in
                            onBoardColumnDrop?(event)
                        },
                        onOpenFocusMode: { uuid in
                            onOpenFocusMode?(uuid)
                        }
                    )
                }
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            Text(cluster.name.uppercased())
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.text)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.border, lineWidth: 1)
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

    // MARK: - Coordinate Conversion

    private func clusterScreenRect(_ cluster: CanvasCluster) -> CGRect {
        let origin = cluster.boundingRect.origin
        let size = cluster.boundingRect.size

        let screenX = origin.x + canvasOffset.width + scaledPanOffset.width
        let screenY = origin.y + canvasOffset.height + scaledPanOffset.height

        return CGRect(x: screenX, y: screenY, width: size.width, height: size.height)
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
