// CosmoOS/Canvas/CanvasMinimapOverlay.swift
// Bird's-eye minimap overlay for navigating large thinkspaces with cluster zones

import SwiftUI

struct CanvasMinimapOverlay: View {
    let blocks: [CanvasBlock]
    let clusters: [CanvasCluster]
    let currentViewport: CGRect  // Current viewport in canvas coordinates
    let onNavigate: (CGPoint, Bool) -> Void
    let onDismiss: () -> Void
    var places: [CanvasPlace] = []
    var onJumpToPlace: ((CanvasPlace) -> Void)? = nil

    @State private var appeared = false
    @State private var hoveredCluster: UUID?
    @State private var enabledLayers: Set<MinimapSemanticLayer> = Set(MinimapSemanticLayer.allCases)

    private enum MinimapSemanticLayer: String, CaseIterable, Hashable, Identifiable {
        case questions = "Questions"
        case sources = "Sources"
        case claims = "Claims"
        case concepts = "Concepts"
        case outputs = "Outputs"
        case openLoops = "Open Loops"
        case links = "Links"

        var id: String { rawValue }
    }

    // Entity type colors for block dots — Greenhouse bespoke palette
    private static let typeColors: [EntityType: Color] = [
        .idea: DS.entityIdea,           // Muted indigo
        .content: DS.entityContent,     // Slate blue
        .research: DS.entityResearch,   // Forest teal
        .connection: DS.entityConnection, // Soft purple
        .note: DS.entityStickyNote,     // Yellow
        .stickyNote: DS.entityStickyNote, // Yellow
        .task: DS.entityTask,           // Dusty rose
        .cosmoAI: DS.accent,            // Forest green
    ]

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.3)
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
                        // Background — warm parchment canvas
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DS.canvas)

                        // Cluster zones
                        ForEach(clusters) { cluster in
                            clusterZoneView(cluster: cluster, layout: layout)
                        }

                        // Block dots
                        ForEach(blocks.filter(shouldShowBlock)) { block in
                            blockDot(block: block, layout: layout)
                        }

                        // Saved Places — accent diamonds, click to fly
                        ForEach(places) { place in
                            MinimapPlaceDiamond(
                                place: place,
                                position: canvasPointToMinimap(place.center, layout: layout),
                                onJump: { onJumpToPlace?(place) }
                            )
                        }

                        // Current viewport indicator
                        viewportRect(layout: layout)
                    }
                    .frame(width: overlaySize.width - 32, height: overlaySize.height - 80)
                    .clipped()
                    .padding(16)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let canvasPoint = screenToCanvas(location, layout: layout)
                        onNavigate(canvasPoint, true)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let canvasPoint = screenToCanvas(value.location, layout: layout)
                                onNavigate(canvasPoint, false)
                            }
                    )
                }
                .frame(width: overlaySize.width, height: overlaySize.height)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DS.vellum)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DS.sepiaBorder, lineWidth: 0.5)
                )
                .dsFloatingShadow()
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.gilt)
                Text("MINIMAP")
                    .dsSmallCapsLabel()
            }

            Spacer()

            // Legend
            HStack(spacing: 12) {
                legendItem(color: DS.accent.opacity(0.5), label: "Viewport")
                layerToggle(.questions, color: DS.entityIdea)
                layerToggle(.sources, color: DS.entityResearch)
                layerToggle(.claims, color: DS.orange)
                layerToggle(.concepts, color: DS.entityConnection)
                layerToggle(.outputs, color: DS.entityContent)
                layerToggle(.openLoops, color: DS.entityStickyNote)
            }

            Spacer()

            // Dismiss hint
            Text("TAB / ESC")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(DS.borderSubtle)
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
                .foregroundColor(DS.textMuted)
        }
    }

    private func layerToggle(_ layer: MinimapSemanticLayer, color: Color) -> some View {
        Button {
            if enabledLayers.contains(layer) {
                enabledLayers.remove(layer)
            } else {
                enabledLayers.insert(layer)
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(enabledLayers.contains(layer) ? color : DS.textMuted.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(layer.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(enabledLayers.contains(layer) ? DS.textMuted : DS.textMuted.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cluster Zone

    /// Zone accent colors keyed by zoneType identifier
    private static let zoneAccentColors: [String: Color] = [
        "welcomeHub": DS.accent,
        "planningDock": Color(hex: "3B82F6"),   // Blue
        "goalForge": Color(hex: "D97706"),      // Amber
        "questBoard": Color(hex: "8B5CF6"),     // Violet
    ]

    /// SF Symbol icon for each zone type
    private static let zoneIcons: [String: String] = [
        "welcomeHub": "house.fill",
        "planningDock": "calendar",
        "goalForge": "target",
        "questBoard": "gamecontroller.fill",
    ]

    @ViewBuilder
    private func clusterZoneView(cluster: CanvasCluster, layout: MinimapLayout) -> some View {
        let rect = canvasRectToMinimap(cluster.boundingRect, layout: layout)
        let isHovered = hoveredCluster == cluster.id
        let isZone = cluster.isZone && cluster.zoneType != nil
        let zoneColor = cluster.zoneType.flatMap { Self.zoneAccentColors[$0] } ?? cluster.color
        let borderWidth: CGFloat = isZone ? 1.5 : 1

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8)
                .fill(zoneColor.opacity(isZone ? 0.10 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(zoneColor.opacity(isHovered ? 0.5 : (isZone ? 0.3 : 0.2)), lineWidth: borderWidth)
                )

            // Zone/cluster name label with optional icon
            HStack(spacing: 3) {
                if let zt = cluster.zoneType, let icon = Self.zoneIcons[zt] {
                    Image(systemName: icon)
                        .font(.system(size: max(7, 9 * layout.scale), weight: .semibold))
                        .foregroundColor(zoneColor)
                }
                Text(cluster.name)
                    .font(.system(size: max(9, 11 * layout.scale), weight: .semibold))
                    .foregroundColor(zoneColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(DS.surfaceElevated)
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            )
            .padding(.top, 4)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .onHover { h in hoveredCluster = h ? cluster.id : nil }
        .onTapGesture {
            let center = CGPoint(x: cluster.boundingRect.midX, y: cluster.boundingRect.midY)
            onNavigate(center, true)
        }
    }

    // MARK: - Block Dot

    @ViewBuilder
    private func blockDot(block: CanvasBlock, layout: MinimapLayout) -> some View {
        let pos = canvasPointToMinimap(block.position, layout: layout)
        let color = semanticColor(for: block)
        let isInCluster = clusters.contains { $0.blockUUIDs.contains(block.entityUuid) }

        Circle()
            .fill(color)
            .frame(width: isInCluster ? 6 : 4, height: isInCluster ? 6 : 4)
            .opacity(isInCluster ? 0.9 : 0.4)
            .position(x: pos.x, y: pos.y)
            .onTapGesture {
                onNavigate(block.position, true)
            }
    }

    private func shouldShowBlock(_ block: CanvasBlock) -> Bool {
        switch semanticLayer(for: block) {
        case .some(let layer):
            return enabledLayers.contains(layer)
        case .none:
            return true
        }
    }

    private func semanticLayer(for block: CanvasBlock) -> MinimapSemanticLayer? {
        if block.entityType == .research { return .sources }
        if block.entityType == .connection { return .concepts }
        if block.entityType == .content { return .outputs }
        if block.entityType == .note || block.entityType == .stickyNote {
            let kind = block.metadata["kind"] ?? block.metadata["canvasObjectKind"] ?? block.metadata["visualMaturity"] ?? ""
            if kind.localizedCaseInsensitiveContains("claim") { return .claims }
            if kind.localizedCaseInsensitiveContains("open") { return .openLoops }
            return .openLoops
        }
        if block.entityType == .idea { return .questions }
        if block.entityType == .deepDive || block.entityType == .thinkspace { return .concepts }
        return nil
    }

    private func semanticColor(for block: CanvasBlock) -> Color {
        switch semanticLayer(for: block) {
        case .questions: return DS.entityIdea
        case .sources: return DS.entityResearch
        case .claims: return DS.orange
        case .concepts: return DS.entityConnection
        case .outputs: return DS.entityContent
        case .openLoops: return DS.entityStickyNote
        case .links: return DS.textMuted
        case .none: return Self.typeColors[block.entityType] ?? DS.textMuted
        }
    }

    // MARK: - Viewport Rect

    @ViewBuilder
    private func viewportRect(layout: MinimapLayout) -> some View {
        let rect = canvasRectToMinimap(currentViewport, layout: layout)

        RoundedRectangle(cornerRadius: 3)
            .stroke(DS.accent.opacity(0.6), lineWidth: 1.5)
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
        // Always include the current viewport so the minimap shows where you are
        guard !blocks.isEmpty else {
            return currentViewport.insetBy(dx: -100, dy: -100)
        }

        // Start from viewport bounds
        var minX = currentViewport.minX
        var minY = currentViewport.minY
        var maxX = currentViewport.maxX
        var maxY = currentViewport.maxY

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
