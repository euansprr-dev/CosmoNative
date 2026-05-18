// CosmoOS/UI/FocusMode/Connection/ConnectionCanvasLayer.swift
// April 2026 — Connection Focus Mode V3 "The Crucible, Dissolved"
//
// Every intrinsic panel on the Connection canvas (masthead, 11 stations,
// collaborator, live insights, maturity + usage summary, Well sources)
// renders here as a first-class draggable block. No sidebars. No grid.
//
// Default positions laid out in a deterministic three-column "Crucible
// Arrangement":
//   left column  → the Well (single sources block, ex-Well sidebar)
//   center       → masthead + 11-section station grid (ex-Forge)
//   right column → collaborator / insights / atelier summary (ex-Atelier)
//
// Users can drag any block freely. `⌘⇧R` clears canvas positions, snapping
// everything back to the default arrangement.
//
// V3 Phase 4 additions (habitation polish):
//   - Single `.well` block replaces the per-source `.source(uuid)` blocks
//     that previously tiled the left column with 80% dead space.
//   - `.atelierSummary` block merges crystal + usage into one compact panel
//     to eliminate vertical overlap at 1440×900.
//   - `ConnectionCrucibleLayout` is now a deterministic column packer that
//     accounts for block sizes and falls back to compact mode when columns
//     would collide on small canvases.

import SwiftUI

// MARK: - Block Kind

enum ConnectionBlockKind: Hashable {
    case masthead
    case station(ConnectionSectionType)
    case collaborator
    case insights
    /// V3 Phase 4: single block housing all sources (replaces per-source blocks).
    case well
    /// V3 Phase 4: compact block merging Maturity Crystal + Usage chips.
    case atelierSummary

    var storageKey: String {
        switch self {
        case .masthead: return "masthead"
        case .station(let type): return "station:\(type.rawValue)"
        case .collaborator: return "collaborator"
        case .insights: return "insights"
        case .well: return "well"
        case .atelierSummary: return "atelierSummary"
        }
    }

    /// Only intrinsic panels other than the masthead/stations/well can be hidden
    /// via the context menu. The masthead + stations + well are load-bearing.
    var isHidable: Bool {
        switch self {
        case .collaborator, .insights, .atelierSummary:
            return true
        default:
            return false
        }
    }
}

// MARK: - Default Sizes

enum ConnectionBlockSize {
    static let masthead = CGSize(width: 560, height: 180)
    static let station = CGSize(width: 260, height: 200)
    static let collaborator = CGSize(width: 320, height: 380)
    static let insights = CGSize(width: 320, height: 260)
    static let atelierSummary = CGSize(width: 320, height: 260)
    static let well = CGSize(width: 300, height: 420)

    static let collaboratorMin = CGSize(width: 260, height: 260)
    static let collaboratorMax = CGSize(width: 560, height: 680)
    static let insightsMin = CGSize(width: 260, height: 180)
    static let insightsMax = CGSize(width: 560, height: 540)
    static let atelierSummaryMin = CGSize(width: 260, height: 200)
    static let atelierSummaryMax = CGSize(width: 560, height: 420)
    static let wellMin = CGSize(width: 260, height: 240)
    static let wellMax = CGSize(width: 360, height: 700)
}

// MARK: - Crucible Layout (deterministic column packer)

/// Default "Crucible Arrangement". Instances are constructed with the actual
/// canvas size so positions breathe with the window, AND accounts for block
/// sizes so no panel overlaps another at default position.
///
/// Three logical columns:
///   - wellColumn     (width 300, anchored to left edge)
///   - forgeColumn    (width = 4×260 + 3×20 = 1100, centered)
///   - atelierColumn  (width 320, anchored to right edge)
///
/// If the canvas is too narrow for three columns side-by-side, the layout
/// falls back to `.compact` mode: atelier panels stack below the forge grid
/// and the well narrows toward the left.
struct ConnectionCrucibleLayout {
    var canvasSize: CGSize

    // Canonical station order used by both default layout and ley line
    // source lookups.
    static let stationOrder: [ConnectionSectionType] = [
        .goal, .problems, .claims, .evidence,
        .benefits, .examples, .beliefsObjections, .process,
        .openQuestions, .conceptName, .references
    ]

    // Column widths.
    private static let wellWidth: CGFloat = ConnectionBlockSize.well.width
    private static let atelierWidth: CGFloat = 320
    private static let stationGridCols = 4
    private static let stationSpacing: CGFloat = 20
    private static let forgeGridWidth: CGFloat = CGFloat(stationGridCols) * ConnectionBlockSize.station.width
        + CGFloat(stationGridCols - 1) * stationSpacing
    private static let interColumnGutter: CGFloat = 32
    private static let edgeInset: CGFloat = 40
    private static let interBlockGap: CGFloat = 24

    // Full required width if we want all three columns non-overlapping.
    private static var fullWidth: CGFloat {
        edgeInset * 2 + wellWidth + interColumnGutter + forgeGridWidth + interColumnGutter + atelierWidth
    }

    var isCompact: Bool { max(canvasSize.width, 1) < Self.fullWidth }

    // MARK: - Left edges per column

    /// Well column left edge.
    var wellLeft: CGFloat {
        if isCompact {
            return Self.edgeInset
        }
        return max(Self.edgeInset, canvasSize.width * 0.04)
    }

    /// Forge column left edge.
    var forgeLeft: CGFloat {
        if isCompact {
            // Narrow canvases — forge still needs to sit centered.
            return max(0, (canvasSize.width - Self.forgeGridWidth) / 2)
        }
        return wellLeft + Self.wellWidth + Self.interColumnGutter
    }

    /// Atelier column left edge.
    var atelierLeft: CGFloat {
        if isCompact {
            return (canvasSize.width - Self.atelierWidth) / 2
        }
        return canvasSize.width - Self.edgeInset - Self.atelierWidth
    }

    private var wellCenterX: CGFloat { wellLeft + Self.wellWidth / 2 }
    private var forgeCenterX: CGFloat { forgeLeft + Self.forgeGridWidth / 2 }
    private var atelierCenterX: CGFloat { atelierLeft + Self.atelierWidth / 2 }

    // MARK: - Masthead

    /// Masthead sits at the top of the forge column, clamped so it never
    /// clips above the top edge.
    var mastheadCenter: CGPoint {
        let size = ConnectionBlockSize.masthead
        let minY = size.height / 2 + Self.edgeInset
        let naturalY = max(minY, canvasSize.height * 0.16)
        return CGPoint(x: forgeCenterX, y: naturalY)
    }

    private var mastheadBottom: CGFloat {
        mastheadCenter.y + ConnectionBlockSize.masthead.height / 2
    }

    // MARK: - Station grid under masthead

    private var stationGridTop: CGFloat {
        mastheadBottom + Self.interBlockGap
    }

    func stationPosition(for type: ConnectionSectionType) -> CGPoint {
        guard let index = Self.stationOrder.firstIndex(of: type) else {
            return CGPoint(x: forgeCenterX, y: stationGridTop)
        }
        let col = index % Self.stationGridCols
        let row = index / Self.stationGridCols
        let size = ConnectionBlockSize.station
        let xStart = forgeLeft + size.width / 2
        let x = xStart + CGFloat(col) * (size.width + Self.stationSpacing)
        let y = stationGridTop + size.height / 2 + CGFloat(row) * (size.height + Self.stationSpacing)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Well column (single block)

    var wellCenter: CGPoint {
        let size = ConnectionBlockSize.well
        let topY = max(Self.edgeInset + size.height / 2, canvasSize.height * 0.16)
        return CGPoint(x: wellCenterX, y: topY)
    }

    // MARK: - Atelier column (collaborator → insights → summary)

    /// In compact mode, atelier panels stack HORIZONTALLY below the station
    /// grid rather than VERTICALLY on the right. Returns each block's center.
    private struct AtelierAnchors {
        let collaborator: CGPoint
        let insights: CGPoint
        let summary: CGPoint
    }

    private var atelierAnchors: AtelierAnchors {
        if isCompact {
            // Below the forge grid, row of three.
            let rowCount = Int(ceil(Double(Self.stationOrder.count) / Double(Self.stationGridCols)))
            let gridBottom = stationGridTop
                + ConnectionBlockSize.station.height * CGFloat(rowCount)
                + Self.stationSpacing * CGFloat(max(rowCount - 1, 0))
            let y = gridBottom + Self.interBlockGap + ConnectionBlockSize.collaborator.height / 2
            let total = ConnectionBlockSize.collaborator.width
                + ConnectionBlockSize.insights.width
                + ConnectionBlockSize.atelierSummary.width
                + Self.stationSpacing * 2
            let startX = (canvasSize.width - total) / 2
            let c1 = startX + ConnectionBlockSize.collaborator.width / 2
            let c2 = c1 + ConnectionBlockSize.collaborator.width / 2
                + Self.stationSpacing
                + ConnectionBlockSize.insights.width / 2
            let c3 = c2 + ConnectionBlockSize.insights.width / 2
                + Self.stationSpacing
                + ConnectionBlockSize.atelierSummary.width / 2
            return AtelierAnchors(
                collaborator: CGPoint(x: c1, y: y),
                insights: CGPoint(x: c2, y: y),
                summary: CGPoint(x: c3, y: y)
            )
        }
        // Standard right column — vertical pack.
        let startY = max(Self.edgeInset + ConnectionBlockSize.collaborator.height / 2,
                         canvasSize.height * 0.16)
        let collaborator = CGPoint(x: atelierCenterX, y: startY)
        let insightsY = collaborator.y
            + ConnectionBlockSize.collaborator.height / 2
            + Self.interBlockGap
            + ConnectionBlockSize.insights.height / 2
        let insights = CGPoint(x: atelierCenterX, y: insightsY)
        let summaryY = insights.y
            + ConnectionBlockSize.insights.height / 2
            + Self.interBlockGap
            + ConnectionBlockSize.atelierSummary.height / 2
        let summary = CGPoint(x: atelierCenterX, y: summaryY)
        return AtelierAnchors(collaborator: collaborator, insights: insights, summary: summary)
    }

    var collaboratorCenter: CGPoint { atelierAnchors.collaborator }
    var insightsCenter: CGPoint { atelierAnchors.insights }
    var atelierSummaryCenter: CGPoint { atelierAnchors.summary }

    // MARK: - Territory labels (vestigial — used by TerritoryAnnotationsLayer)

    var wellLabel: CGPoint {
        CGPoint(x: wellCenterX, y: max(16, Self.edgeInset * 0.5))
    }
    var forgeLabel: CGPoint {
        CGPoint(x: forgeCenterX, y: max(16, Self.edgeInset * 0.5))
    }
    var atelierLabel: CGPoint {
        CGPoint(x: atelierCenterX, y: max(16, Self.edgeInset * 0.5))
    }
}

// MARK: - Coordinate Space Name

enum ConnectionCanvasCoordinate {
    static let name = "connection-canvas"
}

// MARK: - Canvas Layer

struct ConnectionCanvasLayer: View {

    // MARK: - State bindings

    @Binding var state: ConnectionFocusModeState
    let selectedBlockId: String?
    let onSelect: (String) -> Void
    let onPositionChange: (String, CGPoint) -> Void
    let onResize: (String, CGSize) -> Void
    let onHidePanel: (String) -> Void

    // MARK: - Masthead inputs

    let title: Binding<String>
    let conceptType: Binding<ConceptFrameworkType>
    let onTitleCommit: (String) -> Void
    let mastheadSourceCount: Int
    let mastheadInsightCount: Int

    // MARK: - Station inputs

    let onAddItem: (RichDocument, String, ConnectionSectionType) -> Void
    let onEditItem: (ConnectionItem, ConnectionSectionType) -> Void
    let onDeleteItem: (UUID, ConnectionSectionType) -> Void
    let onStationSourceTap: (String) -> Void
    let onAcceptGhost: (GhostSuggestion, ConnectionSectionType) -> Void
    let onDismissGhost: (UUID, ConnectionSectionType) -> Void
    let onEnterStationMode: (ConnectionSectionType) -> Void

    // MARK: - Collaborator

    let collaboratorMessages: Binding<[CollaboratorMessage]>
    let isCollaboratorThinking: Bool
    let onSendMessage: (String) -> Void
    let onCrystallizeMessage: (CollaboratorMessage) -> Void
    let frameworkTitle: String

    // MARK: - Insights

    let insights: [LiveInsight]
    let isRefreshingInsights: Bool
    let onRefreshInsights: () -> Void
    let onDismissInsight: (UUID) -> Void

    // MARK: - Atelier summary (crystal + usage merged)

    let filledSectionCount: Int
    let thresholdLabel: String
    let maturityDetail: String
    let contentUsages: [AtelierContentUsage]
    let profiles: [AtelierProfileChip]
    let onOpenContent: (String) -> Void
    let onAddProfile: () -> Void
    let onOpenProfile: (String) -> Void

    // MARK: - Well (sources)

    let sources: [Atom]
    let whispersBySource: [String: [GhostSuggestion]]
    let contributionsBySource: [String: Set<ConnectionSectionType>]
    let onAddSource: () -> Void
    let onSourceTap: (String) -> Void
    let onRefreshWhispers: (String) -> Void
    let onAcceptWhisper: (GhostSuggestion) -> Void
    let onDismissWhisper: (UUID) -> Void
    let onHoverSource: (String?) -> Void

    // MARK: - Ley lines

    let leyViewport: CGRect?

    // MARK: - Local state

    @State private var endpointPositions: [String: CGPoint] = [:]

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let layout = ConnectionCrucibleLayout(canvasSize: geo.size)

            ZStack {
                // Transparent spacer so .position() uses full parent coords.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                // Territory annotations — dashed sepia region labels behind everything.
                TerritoryAnnotationsLayer(layout: layout)

                // Ley lines beneath the blocks.
                LeyLineLayer(
                    lines: computedLeyLines,
                    isActive: !computedLeyLines.isEmpty,
                    viewport: leyViewport
                )

                mastheadBlock(layout: layout)
                stationBlocks(layout: layout)
                if !state.isPanelHidden(ConnectionBlockKind.collaborator.storageKey) {
                    collaboratorBlock(layout: layout)
                }
                if !state.isPanelHidden(ConnectionBlockKind.insights.storageKey) {
                    insightsBlock(layout: layout)
                }
                if !state.isPanelHidden(ConnectionBlockKind.atelierSummary.storageKey) {
                    atelierSummaryBlock(layout: layout)
                }
                wellBlock(layout: layout)
            }
            .coordinateSpace(name: ConnectionCanvasCoordinate.name)
            .onPreferenceChange(LeyEndpointPreferenceKey.self) { endpoints in
                endpointPositions = endpoints
            }
        }
    }

    // MARK: - Ley Line Assembly

    private var computedLeyLines: [LeyLine] {
        var lines: [LeyLine] = []
        for section in state.sections {
            // Count item sources per section → strength.
            var perSourceCount: [String: Int] = [:]
            for item in section.items {
                if let uuid = item.sourceAtomUUID {
                    perSourceCount[uuid, default: 0] += 1
                }
            }
            let stationKey = section.type.rawValue
            guard let stationPoint = endpointPositions[stationKey] else { continue }
            for (sourceUUID, count) in perSourceCount {
                let sourceKey = "well-source-\(sourceUUID)"
                guard let sourcePoint = endpointPositions[sourceKey] else { continue }
                let strength = min(1.0, 0.4 + Double(count) * 0.15)
                lines.append(LeyLine(from: sourcePoint, to: stationPoint, strength: strength))
            }
        }
        return lines
    }

    // MARK: - Masthead Block

    private func mastheadBlock(layout: ConnectionCrucibleLayout) -> some View {
        let kind = ConnectionBlockKind.masthead
        let pos = state.canvasPosition(kind.storageKey) ?? layout.mastheadCenter
        return ConnectionBlockFrame(
            blockId: kind.storageKey,
            position: pos,
            size: ConnectionBlockSize.masthead,
            chrome: .none,
            isSelected: selectedBlockId == kind.storageKey,
            onSelect: { onSelect(kind.storageKey) },
            onPositionChange: { onPositionChange(kind.storageKey, $0) }
        ) {
            ConnectionMastheadView(
                title: title,
                conceptType: conceptType,
                filledCount: filledSectionCount,
                sourceCount: mastheadSourceCount,
                insightCount: mastheadInsightCount,
                onTitleCommit: onTitleCommit
            )
            .reportLeyEndpoint(kind.storageKey, in: ConnectionCanvasCoordinate.name)
        }
    }

    // MARK: - Stations

    @ViewBuilder
    private func stationBlocks(layout: ConnectionCrucibleLayout) -> some View {
        ForEach(ConnectionCrucibleLayout.stationOrder, id: \.self) { type in
            if let binding = sectionBinding(for: type) {
                stationBlock(for: type, binding: binding, layout: layout)
            }
        }
    }

    private func stationBlock(
        for type: ConnectionSectionType,
        binding: Binding<ConnectionSection>,
        layout: ConnectionCrucibleLayout
    ) -> some View {
        let kind = ConnectionBlockKind.station(type)
        let pos = state.canvasPosition(kind.storageKey) ?? layout.stationPosition(for: type)
        return ConnectionBlockFrame(
            blockId: kind.storageKey,
            position: pos,
            size: nil,
            chrome: .none,
            isSelected: selectedBlockId == kind.storageKey,
            onSelect: { onSelect(kind.storageKey) },
            onPositionChange: { onPositionChange(kind.storageKey, $0) }
        ) {
            StationCardView(
                section: binding,
                onAddItem: { doc, text in onAddItem(doc, text, type) },
                onEditItem: { item in onEditItem(item, type) },
                onDeleteItem: { id in onDeleteItem(id, type) },
                onSourceTap: onStationSourceTap,
                onAcceptGhost: { ghost in onAcceptGhost(ghost, type) },
                onDismissGhost: { id in onDismissGhost(id, type) },
                onEnterStationMode: { onEnterStationMode(type) },
                onHoverChange: nil,
                cardWidth: ConnectionBlockSize.station.width
            )
            .reportLeyEndpoint(type.rawValue, in: ConnectionCanvasCoordinate.name)
        }
    }

    private func sectionBinding(for type: ConnectionSectionType) -> Binding<ConnectionSection>? {
        guard let idx = state.sections.firstIndex(where: { $0.type == type }) else { return nil }
        return Binding(
            get: { state.sections[idx] },
            set: { state.sections[idx] = $0 }
        )
    }

    // MARK: - Collaborator

    private func collaboratorBlock(layout: ConnectionCrucibleLayout) -> some View {
        let kind = ConnectionBlockKind.collaborator
        let pos = state.canvasPosition(kind.storageKey) ?? layout.collaboratorCenter
        let effectiveSize = state.canvasSize(kind.storageKey) ?? ConnectionBlockSize.collaborator
        return ConnectionBlockFrame(
            blockId: kind.storageKey,
            position: pos,
            size: effectiveSize,
            chrome: .hairline,
            isSelected: selectedBlockId == kind.storageKey,
            allowResize: true,
            minSize: ConnectionBlockSize.collaboratorMin,
            maxSize: ConnectionBlockSize.collaboratorMax,
            onSelect: { onSelect(kind.storageKey) },
            onPositionChange: { onPositionChange(kind.storageKey, $0) },
            onResize: { onResize(kind.storageKey, $0) }
        ) {
            ConceptCollaboratorPanel(
                messages: collaboratorMessages,
                frameworkTitle: frameworkTitle,
                conceptType: state.conceptType,
                isThinking: isCollaboratorThinking,
                onSend: onSendMessage,
                onCrystallize: onCrystallizeMessage
            )
            .contextMenu { hidePanelMenu(for: kind) }
        }
    }

    // MARK: - Insights

    private func insightsBlock(layout: ConnectionCrucibleLayout) -> some View {
        let kind = ConnectionBlockKind.insights
        let pos = state.canvasPosition(kind.storageKey) ?? layout.insightsCenter
        let effectiveSize = state.canvasSize(kind.storageKey) ?? ConnectionBlockSize.insights
        return ConnectionBlockFrame(
            blockId: kind.storageKey,
            position: pos,
            size: effectiveSize,
            chrome: .hairline,
            isSelected: selectedBlockId == kind.storageKey,
            allowResize: true,
            minSize: ConnectionBlockSize.insightsMin,
            maxSize: ConnectionBlockSize.insightsMax,
            onSelect: { onSelect(kind.storageKey) },
            onPositionChange: { onPositionChange(kind.storageKey, $0) },
            onResize: { onResize(kind.storageKey, $0) }
        ) {
            LiveInsightsPanel(
                insights: insights,
                isRefreshing: isRefreshingInsights,
                onRefresh: onRefreshInsights,
                onDismiss: onDismissInsight
            )
            .contextMenu { hidePanelMenu(for: kind) }
        }
    }

    // MARK: - Atelier summary (crystal + usage merged)

    private func atelierSummaryBlock(layout: ConnectionCrucibleLayout) -> some View {
        let kind = ConnectionBlockKind.atelierSummary
        let pos = state.canvasPosition(kind.storageKey) ?? layout.atelierSummaryCenter
        let effectiveSize = state.canvasSize(kind.storageKey) ?? ConnectionBlockSize.atelierSummary
        return ConnectionBlockFrame(
            blockId: kind.storageKey,
            position: pos,
            size: effectiveSize,
            chrome: .hairline,
            isSelected: selectedBlockId == kind.storageKey,
            allowResize: true,
            minSize: ConnectionBlockSize.atelierSummaryMin,
            maxSize: ConnectionBlockSize.atelierSummaryMax,
            onSelect: { onSelect(kind.storageKey) },
            onPositionChange: { onPositionChange(kind.storageKey, $0) },
            onResize: { onResize(kind.storageKey, $0) }
        ) {
            AtelierSummaryContent(
                filledSectionCount: filledSectionCount,
                thresholdLabel: thresholdLabel,
                maturityDetail: maturityDetail,
                contentUsages: contentUsages,
                profiles: profiles,
                onOpenContent: onOpenContent,
                onAddProfile: onAddProfile,
                onOpenProfile: onOpenProfile
            )
            .contextMenu { hidePanelMenu(for: kind) }
        }
    }

    // MARK: - Well (single sources block)

    private func wellBlock(layout: ConnectionCrucibleLayout) -> some View {
        let kind = ConnectionBlockKind.well
        let pos = state.canvasPosition(kind.storageKey) ?? layout.wellCenter
        let effectiveSize = state.canvasSize(kind.storageKey) ?? ConnectionBlockSize.well
        return ConnectionBlockFrame(
            blockId: kind.storageKey,
            position: pos,
            size: effectiveSize,
            chrome: .paper,
            isSelected: selectedBlockId == kind.storageKey,
            allowResize: true,
            minSize: ConnectionBlockSize.wellMin,
            maxSize: ConnectionBlockSize.wellMax,
            onSelect: { onSelect(kind.storageKey) },
            onPositionChange: { onPositionChange(kind.storageKey, $0) },
            onResize: { onResize(kind.storageKey, $0) }
        ) {
            WellSourcesBlock(
                sources: sources,
                suggestedSources: [],
                whispersBySource: whispersBySource,
                contributionsBySource: contributionsBySource,
                isShowingSuggestions: false,
                isLoadingSuggestions: false,
                onAddSource: onAddSource,
                onRequestSuggestions: {},
                onLinkSuggestedSource: { _ in },
                onSourceTap: onSourceTap,
                onRefreshWhispers: onRefreshWhispers,
                onAcceptWhisper: onAcceptWhisper,
                onDismissWhisper: onDismissWhisper,
                onHoverSource: onHoverSource
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func hidePanelMenu(for kind: ConnectionBlockKind) -> some View {
        if kind.isHidable {
            Button(role: .destructive) {
                onHidePanel(kind.storageKey)
            } label: {
                Label("Hide Panel", systemImage: "eye.slash")
            }
        }
    }
}

// MARK: - Atelier Summary Content

/// Compact merged panel: Maturity Crystal (small) + threshold label + usage
/// chips. Replaces the separate `.crystal` and `.usage` blocks from V3
/// Phase 1-3, which overlapped at 1440×900.
private struct AtelierSummaryContent: View {
    let filledSectionCount: Int
    let thresholdLabel: String
    let maturityDetail: String
    let contentUsages: [AtelierContentUsage]
    let profiles: [AtelierProfileChip]
    let onOpenContent: (String) -> Void
    let onAddProfile: () -> Void
    let onOpenProfile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            crystalRow
            hairline
            usageSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var crystalRow: some View {
        HStack(spacing: 12) {
            MaturityCrystalView(
                filledCount: filledSectionCount,
                diameter: 56,
                tintColor: DS.entityConnection
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(thresholdLabel.uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.8)
                    .foregroundStyle(DS.inkWash)
                Text(maturityDetail)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
            }
            Spacer()
        }
    }

    private var hairline: some View {
        Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
    }

    private var usageSection: some View {
        AtelierUsageSection(
            usages: contentUsages,
            profiles: profiles,
            onOpenContent: onOpenContent,
            onOpenProfile: onOpenProfile,
            onAddProfile: onAddProfile
        )
        .padding(.horizontal, -14)
        .padding(.vertical, -2)
    }
}

// MARK: - Territory Annotations

/// Dashed sepia region labels behind the blocks. Pure scaffolding — no
/// hit-testing, no animation. Purely to evoke "THE WELL / FORGE / ATELIER"
/// as distinct zones without caging the user inside panels.
struct TerritoryAnnotationsLayer: View {
    let layout: ConnectionCrucibleLayout

    var body: some View {
        ZStack {
            TerritoryLabel(text: "THE WELL", position: layout.wellLabel)
            TerritoryLabel(text: "THE FORGE", position: layout.forgeLabel)
            TerritoryLabel(text: "THE ATELIER", position: layout.atelierLabel)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TerritoryLabel: View {
    let text: String
    let position: CGPoint

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .serif))
            .tracking(3.5)
            .foregroundStyle(DS.giltMuted.opacity(0.45))
            .italic()
            .position(position)
    }
}
