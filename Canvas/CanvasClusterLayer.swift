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
    var onRenameCluster: ((UUID, String) -> Void)?
    var onRemoveCluster: ((UUID) -> Void)?

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
        .allowsHitTesting(true)
    }

    // MARK: - Cluster Zone

    @ViewBuilder
    private func clusterZone(_ cluster: CanvasCluster) -> some View {
        let rect = clusterScreenRect(cluster)
        let isHovered = hoveredClusterID == cluster.id
        let isEditing = editingClusterID == cluster.id
        let showLabel = cluster.isUserCreated || isHovered || effectiveScale < 0.8

        ZStack(alignment: .topLeading) {
            // Background fill
            RoundedRectangle(cornerRadius: 16)
                .fill(cluster.color.opacity(cluster.isUserCreated ? 0.06 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            cluster.color.opacity(cluster.isUserCreated ? 0.2 : (isHovered ? 0.25 : 0.0)),
                            lineWidth: cluster.isUserCreated ? 1.5 : 1.5
                        )
                )
                .frame(width: rect.width, height: rect.height)

            // Label (top-left) — always visible for user clusters
            if showLabel {
                clusterLabel(cluster, isEditing: isEditing)
                    .padding(.top, 8)
                    .padding(.leading, 10)
                    .transition(.opacity)
            }

            // Controls (top-right) — only for user clusters on hover
            if cluster.isUserCreated && isHovered {
                clusterControls(cluster)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .transition(.opacity)
            }

            // Synthesis tooltip on hover
            if isHovered, let synthesis = cluster.synthesis, !synthesis.isEmpty {
                synthesisTooltip(synthesis)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, 8)
                    .padding(.leading, 10)
                    .transition(.opacity)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredClusterID = hovered ? cluster.id : nil
            }
        }
    }

    // MARK: - Label

    @ViewBuilder
    private func clusterLabel(_ cluster: CanvasCluster, isEditing: Bool) -> some View {
        if isEditing {
            // Inline rename field
            HStack(spacing: 4) {
                Circle()
                    .fill(cluster.color)
                    .frame(width: 6, height: 6)

                TextField("Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(cluster.color)
                    .frame(width: 120)
                    .onSubmit {
                        commitRename(cluster)
                    }
                    .onExitCommand {
                        editingClusterID = nil
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
            .overlay(
                Capsule()
                    .stroke(cluster.color.opacity(0.4), lineWidth: 1)
            )
        } else {
            HStack(spacing: 4) {
                Circle()
                    .fill(cluster.color)
                    .frame(width: 6, height: 6)

                Text(cluster.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(cluster.color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.5))
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
            // Regenerate synthesis
            Button {
                // Post notification for engine to re-synthesize
                NotificationCenter.default.post(
                    name: CosmoNotification.Canvas.clusterResynthesizeRequested,
                    object: nil,
                    userInfo: ["clusterId": cluster.id.uuidString]
                )
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(cluster.color.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)

            // Remove cluster
            Button {
                onRemoveCluster?(cluster.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CosmoColors.softRed.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Synthesis Tooltip

    private func synthesisTooltip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(CosmoColors.textSecondary)
            .lineLimit(3)
            .frame(maxWidth: 240, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.7))
            )
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
    static let clusterResynthesizeRequested = Notification.Name("com.cosmo.canvas.clusterResynthesizeRequested")
    static let createClusterFromSelection = Notification.Name("com.cosmo.canvas.createClusterFromSelection")
}
