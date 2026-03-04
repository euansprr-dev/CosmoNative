// CosmoOS/Canvas/CanvasClusterLayer.swift
// Visual layer rendering cluster zones on the canvas
// Supports both auto-chunked and user-created clusters

import SwiftUI

@MainActor
struct CanvasClusterLayer: View {

    // MARK: - Parameters

    let clusters: [CanvasCluster]
    let blocks: [CanvasBlock]
    let canvasOffset: CGSize
    let scaledPanOffset: CGSize
    let effectiveScale: CGFloat
    var dropTargetClusterId: UUID?
    var selectedClusterId: UUID?
    var clusterDragOffset: CGSize?
    var onRenameCluster: ((UUID, String) -> Void)?
    var onRemoveCluster: ((UUID) -> Void)?
    var onSelectCluster: ((UUID?) -> Void)?
    var onDragCluster: ((UUID, CGSize) -> Void)?
    var onDragEndCluster: ((UUID, CGSize) -> Void)?
    var onResizeCluster: ((UUID, CGSize, ClusterResizeEdge) -> Void)?
    var onResizeEndCluster: ((UUID) -> Void)?
    var onChangeViewMode: ((UUID, ClusterViewMode) -> Void)?
    var onChangeColor: ((UUID, Int) -> Void)?
    var onChangeSortOrder: ((UUID, ClusterSortOrder) -> Void)?
    var onToggleListExpand: ((UUID, String) -> Void)?
    var onBoardColumnDrop: ((String, String, UUID) -> Void)?   // blockUUID, newColumnValue, clusterId
    var onOpenFocusMode: ((String) -> Void)?
    var expandedBlockUUIDs: [UUID: String] = [:]

    // MARK: - State

    @State private var hoveredClusterID: UUID?
    @State private var editingClusterID: UUID?
    @State private var editingName: String = ""

    // MARK: - Body

    var body: some View {
        ZStack {
            // Cluster zones
            ForEach(clusters) { cluster in
                clusterZone(cluster)
            }

            // Inspector panel — floats to the right of the selected cluster,
            // rendered OUTSIDE the cluster zone so it never overlaps cluster content
            inspectorPanelOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let rect = clusterScreenRect(cluster)
        let scale = labelCounterScale
        let panelHalfWidth: CGFloat = 120 * scale
        let panelHalfHeight: CGFloat = 110 * scale
        let posX = rect.maxX + 12 + panelHalfWidth
        let posY = rect.minY + panelHalfHeight

        ClusterInspectorPanel(
            cluster: cluster,
            onChangeColor: { colorIndex in
                onChangeColor?(cluster.id, colorIndex)
            },
            onChangeViewMode: { mode in
                onChangeViewMode?(cluster.id, mode)
            },
            onDismiss: {
                onSelectCluster?(nil)
            }
        )
        .scaleEffect(scale, anchor: .topLeading)
        .position(x: posX, y: posY)
        .allowsHitTesting(true)
        .zIndex(9999)
        .transition(.opacity)
        .animation(ProMotionSprings.snappy, value: selectedClusterId)
    }

    /// The currently selected user cluster (inspector only shows for user clusters)
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
        let showLabel = cluster.isUserCreated || isHovered || effectiveScale < 0.8
        let hasAltContent = cluster.isUserCreated && cluster.viewMode != .canvas

        ZStack {
            // Background fill
            RoundedRectangle(cornerRadius: 16)
                .fill(cluster.color.opacity(isDropTarget ? 0.12 : (cluster.isUserCreated ? 0.06 : 0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected
                                ? cluster.color.opacity(0.6)
                                : cluster.color.opacity(isDropTarget ? 0.5 : (cluster.isUserCreated ? 0.2 : (isHovered ? 0.25 : 0.0))),
                            lineWidth: isSelected ? 2.5 : (isDropTarget ? 2.5 : 1.5)
                        )
                )
                .shadow(color: isDropTarget ? cluster.color.opacity(0.3) : .clear, radius: isDropTarget ? 12 : 0)

            // Content overlay: title label + list/board content
            // Uses a VStack so content sits properly below the title, never overlapping
            if showLabel || hasAltContent {
                VStack(spacing: 0) {
                    // Title bar
                    if showLabel {
                        clusterTitleBar(cluster, isEditing: isEditing, isHovered: isHovered, isSelected: isSelected)
                            .scaleEffect(labelCounterScale)
                            .frame(height: 44 * labelCounterScale)
                    }

                    // List/Board content fills remaining space
                    if hasAltContent {
                        clusterAlternativeContent(cluster, clusterWidth: rect.width)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }

            // Resize handles — only for selected user clusters
            if cluster.isUserCreated && isSelected {
                resizeHandlesOverlay(cluster: cluster, rect: rect)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .position(x: rect.midX, y: rect.midY)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTarget)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(cluster.isUserCreated)
        .onTapGesture(count: 1) {
            if cluster.isUserCreated {
                onSelectCluster?(isSelected ? nil : cluster.id)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { gesture in
                    guard cluster.isUserCreated else { return }
                    if selectedClusterId != cluster.id {
                        onSelectCluster?(cluster.id)
                    }
                    onDragCluster?(cluster.id, gesture.translation)
                }
                .onEnded { gesture in
                    guard cluster.isUserCreated else { return }
                    onDragEndCluster?(cluster.id, gesture.translation)
                }
        )
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredClusterID = hovered ? cluster.id : nil
            }
        }
    }

    /// Counter-scale for labels: stays readable when zoomed out, capped at 3x
    private var labelCounterScale: CGFloat {
        min(3.0, max(1.0, 1.0 / effectiveScale))
    }

    // MARK: - Title Bar (label + controls in one row)

    @ViewBuilder
    private func clusterTitleBar(_ cluster: CanvasCluster, isEditing: Bool, isHovered: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            clusterLabel(cluster, isEditing: isEditing)

            Spacer(minLength: 0)

            // Delete button — visible on hover/select for user clusters
            if cluster.isUserCreated && (isHovered || isSelected) {
                Button {
                    onRemoveCluster?(cluster.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.red)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DS.surfaceElevated)
                                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Alternative Content (List / Board)

    @ViewBuilder
    private func clusterAlternativeContent(_ cluster: CanvasCluster, clusterWidth: CGFloat) -> some View {
        let scale = labelCounterScale
        // Content is rendered at 1:1 (readable) size, then scaled to fit the cluster.
        // Width in content-space = cluster pixel width / scale factor.
        let contentWidth = max((clusterWidth / scale) - 24, 100)

        Group {
            switch cluster.viewMode {
            case .canvas:
                EmptyView()
            case .list:
                ClusterListContent(
                    cluster: cluster,
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
                    blocks: blocks,
                    onBoardColumnDrop: { blockUUID, newValue in
                        onBoardColumnDrop?(blockUUID, newValue, cluster.id)
                    },
                    onOpenFocusMode: { uuid in
                        onOpenFocusMode?(uuid)
                    }
                )
            }
        }
        .frame(width: contentWidth)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(scale, anchor: .top)
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
            .overlay(
                Circle().stroke(cluster.color.opacity(0.8), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            .frame(width: isCorner ? handleSize : handleSize * 0.8,
                   height: isCorner ? handleSize : handleSize * 0.8)
            .scaleEffect(labelCounterScale)
            .contentShape(Rectangle().size(width: hitSize, height: hitSize))
            .frame(width: hitSize, height: hitSize)
            .allowsHitTesting(true)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        let delta = CGSize(
                            width: gesture.translation.width / effectiveScale,
                            height: gesture.translation.height / effectiveScale
                        )
                        onResizeCluster?(cluster.id, delta, edge)
                    }
                    .onEnded { _ in
                        onResizeEndCluster?(cluster.id)
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
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cluster.color.opacity(0.4), lineWidth: 1.5)
                )
                .onSubmit {
                    commitRename(cluster)
                }
                .onExitCommand {
                    editingClusterID = nil
                }
        } else {
            Text(cluster.name.uppercased())
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DS.text)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DS.surfaceElevated)
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
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
        let drag = (selectedClusterId == cluster.id) ? (clusterDragOffset ?? .zero) : .zero

        let screenX = origin.x + canvasOffset.width + scaledPanOffset.width + drag.width
        let screenY = origin.y + canvasOffset.height + scaledPanOffset.height + drag.height

        return CGRect(x: screenX, y: screenY, width: size.width, height: size.height)
    }
}

// MARK: - Resize Cursor Helper

extension NSCursor {
    static func resizeCursor(for edge: ClusterResizeEdge) -> NSCursor {
        switch edge {
        case .left, .right:     return .resizeLeftRight
        case .top, .bottom:     return .resizeUpDown
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        }
    }
}

// MARK: - Notification Extension

extension CosmoNotification.Canvas {
    static let createClusterFromSelection = Notification.Name("com.cosmo.canvas.createClusterFromSelection")
}
