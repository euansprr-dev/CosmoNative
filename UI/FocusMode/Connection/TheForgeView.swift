// CosmoOS/UI/FocusMode/Connection/TheForgeView.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// The Forge is the center zone. It contains the Masthead (the concept as a
// ritual object) and the spatial Stations grid. Stations default to a 2×4 grid
// arranged by semantic purpose:
//
//   Row 1 — Purpose & Tension:  [GOAL] [CONCEPT NAME] [PROBLEMS] [BENEFITS]
//   Row 2 — Execution & Evidence: [PROCESS] [EXAMPLES] [BELIEFS & OBJ.] [REFERENCES]
//
// Users can drag stations to rearrange — any drag "lifts" the grid into free
// placement mode (all stations get absolute positions) and subsequent drags
// update those positions. "Restore default arrangement" clears positions.

import SwiftUI

struct TheForgeView: View {

    // MARK: - Inputs

    @Binding var title: String
    @Binding var conceptType: ConceptFrameworkType
    @Binding var state: ConnectionFocusModeState

    let onAddItem: (RichDocument, String, ConnectionSectionType) -> Void
    let onEditItem: (ConnectionItem, ConnectionSectionType) -> Void
    let onDeleteItem: (UUID, ConnectionSectionType) -> Void
    let onSourceTap: (String) -> Void
    let onAcceptGhost: (GhostSuggestion, ConnectionSectionType) -> Void
    let onDismissGhost: (UUID, ConnectionSectionType) -> Void
    let onEnterStationMode: (ConnectionSectionType) -> Void
    let onTitleCommit: (String) -> Void

    /// Sources count — feeds masthead stats.
    var sourceCount: Int = 0
    /// Insights count — feeds masthead stats.
    var insightCount: Int = 0

    // MARK: - Layout constants

    private let stationWidth: CGFloat = 260
    private let stationMinHeight: CGFloat = 140
    private let gridColumns: Int = 4
    private let columnSpacing: CGFloat = 20
    private let rowSpacing: CGFloat = 20

    // Default semantic ordering (row-major, 4 per row).
    private let defaultOrder: [ConnectionSectionType] = [
        .goal, .conceptName, .problems, .benefits,
        .process, .examples, .beliefs, .references
    ]

    // MARK: - Local state

    @State private var hoveredStation: ConnectionSectionType?
    @State private var draggedStation: ConnectionSectionType?
    @State private var dragTranslation: CGSize = .zero

    private var coordinateSpaceName: String { "forge-space" }

    private var isFreePlacement: Bool { !state.stationPositions.isEmpty }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                masthead
                stationArea
                Spacer(minLength: 40)
            }
            .padding(.top, 40)
            .padding(.bottom, 80)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
        .background(Color.clear)
        .coordinateSpace(name: coordinateSpaceName)
    }

    // MARK: - Masthead

    private var masthead: some View {
        ConnectionMastheadView(
            title: $title,
            conceptType: $conceptType,
            filledCount: state.completedSectionCount,
            sourceCount: sourceCount,
            insightCount: insightCount,
            onTitleCommit: onTitleCommit
        )
    }

    // MARK: - Stations

    @ViewBuilder
    private var stationArea: some View {
        if isFreePlacement {
            freePlacementCanvas
        } else {
            defaultGrid
        }
    }

    private var defaultGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(stationWidth), spacing: columnSpacing), count: gridColumns)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: rowSpacing) {
            ForEach(defaultOrder, id: \.self) { type in
                stationBinding(for: type).map { binding in
                    stationCard(binding: binding)
                }
            }
        }
        .frame(maxWidth: CGFloat(gridColumns) * stationWidth + CGFloat(gridColumns - 1) * columnSpacing)
    }

    private var freePlacementCanvas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(defaultOrder, id: \.self) { type in
                if let binding = stationBinding(for: type) {
                    stationCard(binding: binding)
                        .position(stationPosition(for: type))
                }
            }
        }
        .frame(minHeight: 640)
    }

    @ViewBuilder
    private func stationCard(binding: Binding<ConnectionSection>) -> some View {
        let type = binding.wrappedValue.type
        StationCardView(
            section: binding,
            onAddItem: { doc, text in onAddItem(doc, text, type) },
            onEditItem: { item in onEditItem(item, type) },
            onDeleteItem: { id in onDeleteItem(id, type) },
            onSourceTap: onSourceTap,
            onAcceptGhost: { ghost in onAcceptGhost(ghost, type) },
            onDismissGhost: { id in onDismissGhost(id, type) },
            onEnterStationMode: { onEnterStationMode(type) },
            onHoverChange: { hovering in
                hoveredStation = hovering ? type : (hoveredStation == type ? nil : hoveredStation)
            },
            cardWidth: stationWidth
        )
        .scaleEffect(draggedStation == type ? 1.02 : 1.0)
        .shadow(
            color: DS.inkWash.opacity(draggedStation == type ? 0.18 : 0.05),
            radius: draggedStation == type ? 14 : 4,
            x: 0,
            y: draggedStation == type ? 8 : 2
        )
        .animation(ProMotionSprings.snappy, value: draggedStation == type)
        .reportLeyEndpoint(type.rawValue, in: coordinateSpaceName)
        .gesture(dragGesture(for: type))
    }

    // MARK: - Drag

    private func dragGesture(for type: ConnectionSectionType) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if draggedStation != type {
                    // First drag: lock in positions for every station so free-
                    // placement has a consistent starting layout.
                    liftIntoFreePlacementIfNeeded()
                    draggedStation = type
                }
                dragTranslation = value.translation
                let anchor = anchorPosition(for: type)
                let newPoint = CGPoint(
                    x: anchor.x + value.translation.width,
                    y: anchor.y + value.translation.height
                )
                state.setStationPosition(type, point: newPoint)
            }
            .onEnded { _ in
                withAnimation(ProMotionSprings.bouncy) {
                    draggedStation = nil
                    dragTranslation = .zero
                }
            }
    }

    private func anchorPosition(for type: ConnectionSectionType) -> CGPoint {
        if let existing = state.stationPositions[type] {
            return existing
        }
        return defaultGridPosition(for: type)
    }

    private func stationPosition(for type: ConnectionSectionType) -> CGPoint {
        if let point = state.stationPositions[type] {
            return point
        }
        return defaultGridPosition(for: type)
    }

    private func defaultGridPosition(for type: ConnectionSectionType) -> CGPoint {
        guard let index = defaultOrder.firstIndex(of: type) else {
            return CGPoint(x: stationWidth / 2, y: stationMinHeight / 2)
        }
        let col = index % gridColumns
        let row = index / gridColumns
        let x = CGFloat(col) * (stationWidth + columnSpacing) + stationWidth / 2
        let y = CGFloat(row) * (stationMinHeight + rowSpacing * 2) + stationMinHeight / 2 + 24
        return CGPoint(x: x, y: y)
    }

    private func liftIntoFreePlacementIfNeeded() {
        guard !isFreePlacement else { return }
        for type in defaultOrder {
            state.setStationPosition(type, point: defaultGridPosition(for: type))
        }
    }

    // MARK: - Section binding lookup

    private func stationBinding(for type: ConnectionSectionType) -> Binding<ConnectionSection>? {
        guard let idx = state.sections.firstIndex(where: { $0.type == type }) else { return nil }
        return Binding(
            get: { state.sections[idx] },
            set: { state.sections[idx] = $0 }
        )
    }
}
