// CosmoOS/Canvas/CanvasMinimapOverlay.swift
// Bird's-eye minimap overlay for navigating large thinkspaces with cluster zones

import SwiftUI

struct CanvasMinimapOverlay: View {
    let blocks: [CanvasBlock]
    let clusters: [CanvasCluster]
    let currentViewport: CGRect  // Current viewport in canvas coordinates
    let onNavigate: (CGPoint) -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var hoveredCluster: UUID?

    // Entity type colors for block dots
    private static let typeColors: [EntityType: Color] = [
        .idea: Color(hex: "#818CF8"),       // Indigo
        .content: Color(hex: "#34D399"),    // Emerald
        .research: Color(hex: "#60A5FA"),   // Blue
        .connection: Color(hex: "#F472B6"), // Pink
        .note: Color(hex: "#A78BFA"),       // Violet
        .task: Color(hex: "#FBBF24"),       // Amber
        .cosmoAI: Color(hex: "#C084FC"),    // Purple
    ]

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Minimap container
            GeometryReader { geo in
                let overlaySize = CGSize(
                    width: geo.size.width * 0.7,
                    height: geo.size.height * 0.7
                )
                let layout = computeLayout(overlaySize: overlaySize)

                VStack(spacing: 0) {
                    // Header
                    minimapHeader

                    // Minimap canvas
                    ZStack {
                        // Background
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#0A0A0F"))

                        // Cluster zones
                        ForEach(clusters) { cluster in
                            clusterZoneView(cluster: cluster, layout: layout)
                        }

                        // Block dots
                        ForEach(blocks) { block in
                            blockDot(block: block, layout: layout)
                        }

                        // Current viewport indicator
                        viewportRect(layout: layout)
                    }
                    .frame(width: overlaySize.width - 32, height: overlaySize.height - 80)
                    .padding(16)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let canvasPoint = screenToCanvas(location, layout: layout)
                        onNavigate(canvasPoint)
                        dismiss()
                    }
                }
                .frame(width: overlaySize.width, height: overlaySize.height)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DS.borderActive.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: CosmoColors.thinkspacePurple.opacity(0.15), radius: 40, y: 10)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1.0 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private var minimapHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CosmoColors.thinkspacePurple)
                Text("Minimap")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.text)
            }

            Spacer()

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .white.opacity(0.5), label: "Viewport")
                legendItem(color: Color(hex: "#818CF8"), label: "Ideas")
                legendItem(color: Color(hex: "#60A5FA"), label: "Research")
                legendItem(color: Color(hex: "#34D399"), label: "Content")
            }

            Spacer()

            // Dismiss hint
            Text("TAB / ESC")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(CosmoColors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(CosmoColors.textTertiary)
        }
    }

    // MARK: - Cluster Zone

    @ViewBuilder
    private func clusterZoneView(cluster: CanvasCluster, layout: MinimapLayout) -> some View {
        let rect = canvasRectToMinimap(cluster.boundingRect, layout: layout)
        let isHovered = hoveredCluster == cluster.id

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8)
                .fill(cluster.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cluster.color.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
                )

            // Cluster name label
            Text(cluster.name)
                .font(.system(size: max(9, 11 * layout.scale), weight: .semibold))
                .foregroundColor(cluster.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.6))
                )
                .padding(.top, 4)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .onHover { h in hoveredCluster = h ? cluster.id : nil }
        .onTapGesture {
            let center = CGPoint(x: cluster.boundingRect.midX, y: cluster.boundingRect.midY)
            onNavigate(center)
            dismiss()
        }
    }

    // MARK: - Block Dot

    @ViewBuilder
    private func blockDot(block: CanvasBlock, layout: MinimapLayout) -> some View {
        let pos = canvasPointToMinimap(block.position, layout: layout)
        let color = Self.typeColors[block.entityType] ?? Color.white.opacity(0.4)
        let isInCluster = clusters.contains { $0.blockUUIDs.contains(block.entityUuid) }

        Circle()
            .fill(color)
            .frame(width: isInCluster ? 6 : 4, height: isInCluster ? 6 : 4)
            .opacity(isInCluster ? 0.9 : 0.4)
            .position(x: pos.x, y: pos.y)
            .onTapGesture {
                onNavigate(block.position)
                dismiss()
            }
    }

    // MARK: - Viewport Rect

    @ViewBuilder
    private func viewportRect(layout: MinimapLayout) -> some View {
        let rect = canvasRectToMinimap(currentViewport, layout: layout)

        RoundedRectangle(cornerRadius: 3)
            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
            .frame(width: max(rect.width, 20), height: max(rect.height, 14))
            .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Layout Math

    private struct MinimapLayout {
        let canvasBounds: CGRect   // Bounding rect of all blocks + padding
        let minimapRect: CGRect    // Available drawing area in the overlay
        let scale: CGFloat         // canvas → minimap scale factor
        let offset: CGPoint        // Translation to center in minimap
    }

    private func computeLayout(overlaySize: CGSize) -> MinimapLayout {
        let drawableSize = CGSize(
            width: overlaySize.width - 64,
            height: overlaySize.height - 112
        )

        let canvasBounds = computeCanvasBounds()
        guard canvasBounds.width > 0, canvasBounds.height > 0 else {
            return MinimapLayout(
                canvasBounds: .zero,
                minimapRect: CGRect(origin: .zero, size: drawableSize),
                scale: 1.0,
                offset: .zero
            )
        }

        let scaleX = drawableSize.width / canvasBounds.width
        let scaleY = drawableSize.height / canvasBounds.height
        let scale = min(scaleX, scaleY) * 0.9  // 90% fill for margins

        let offsetX = (drawableSize.width - canvasBounds.width * scale) / 2
        let offsetY = (drawableSize.height - canvasBounds.height * scale) / 2

        return MinimapLayout(
            canvasBounds: canvasBounds,
            minimapRect: CGRect(origin: .zero, size: drawableSize),
            scale: scale,
            offset: CGPoint(x: offsetX, y: offsetY)
        )
    }

    private func computeCanvasBounds() -> CGRect {
        guard !blocks.isEmpty else { return .zero }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for block in blocks {
            let halfW = block.size.width / 2
            let halfH = block.size.height / 2
            minX = min(minX, block.position.x - halfW)
            minY = min(minY, block.position.y - halfH)
            maxX = max(maxX, block.position.x + halfW)
            maxY = max(maxY, block.position.y + halfH)
        }

        // Add padding
        let padding: CGFloat = 100
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding * 2
        )
    }

    private func canvasPointToMinimap(_ point: CGPoint, layout: MinimapLayout) -> CGPoint {
        CGPoint(
            x: (point.x - layout.canvasBounds.origin.x) * layout.scale + layout.offset.x,
            y: (point.y - layout.canvasBounds.origin.y) * layout.scale + layout.offset.y
        )
    }

    private func canvasRectToMinimap(_ rect: CGRect, layout: MinimapLayout) -> CGRect {
        let origin = canvasPointToMinimap(rect.origin, layout: layout)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * layout.scale,
            height: rect.height * layout.scale
        )
    }

    private func screenToCanvas(_ point: CGPoint, layout: MinimapLayout) -> CGPoint {
        guard layout.scale > 0 else { return .zero }
        return CGPoint(
            x: (point.x - layout.offset.x) / layout.scale + layout.canvasBounds.origin.x,
            y: (point.y - layout.offset.y) / layout.scale + layout.canvasBounds.origin.y
        )
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}
