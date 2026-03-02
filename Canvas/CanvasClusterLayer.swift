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

    // MARK: - State

    @State private var hoveredClusterID: UUID?
    @State private var editingClusterID: UUID?
    @State private var editingName: String = ""

    // MARK: - Body

    var body: some View {
        ZStack {
            ForEach(clusters) { cluster in
                clusterZone(cluster)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
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

        ZStack(alignment: .top) {
            // Background fill — brighter when accepting a drop or selected
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
                .frame(width: rect.width, height: rect.height)

            // Title — centered at top, counter-scaled to stay readable when zoomed out
            if showLabel {
                clusterLabel(cluster, isEditing: isEditing)
                    .scaleEffect(labelCounterScale)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            // Controls (top-right) — only for user clusters on hover
            if cluster.isUserCreated && (isHovered || isSelected) {
                clusterControls(cluster)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .transition(.opacity)
            }
        }
        .frame(width: rect.width, height: rect.height)
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
                    // Select on drag start
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

    /// Counter-scale for label: stays readable when zoomed out, capped at 3x
    private var labelCounterScale: CGFloat {
        min(3.0, max(1.0, 1.0 / effectiveScale))
    }

    // MARK: - Label

    @ViewBuilder
    private func clusterLabel(_ cluster: CanvasCluster, isEditing: Bool) -> some View {
        if isEditing {
            // Inline rename field — centered, bold
            TextField("Name", text: $editingName)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(DS.text)
                .multilineTextAlignment(.center)
                .frame(minWidth: 120, maxWidth: 240)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
            // Display label — centered heading style
            Text(cluster.name.uppercased())
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(DS.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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

    // MARK: - Controls

    private func clusterControls(_ cluster: CanvasCluster) -> some View {
        HStack(spacing: 4) {
            // Remove cluster
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

        // Apply live drag offset if this cluster is being dragged
        let drag = (selectedClusterId == cluster.id) ? (clusterDragOffset ?? .zero) : .zero

        let screenX = origin.x + canvasOffset.width + scaledPanOffset.width + drag.width
        let screenY = origin.y + canvasOffset.height + scaledPanOffset.height + drag.height

        return CGRect(
            x: screenX,
            y: screenY,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Notification Extension

extension CosmoNotification.Canvas {
    static let createClusterFromSelection = Notification.Name("com.cosmo.canvas.createClusterFromSelection")
}
