// CosmoOS/UI/FocusMode/Connection/TheForgeView.swift
// April 2026 — governed Forge workspace
//
// The connection's own structure no longer free-floats. The masthead and
// metadata stay anchored, and stations live in a controlled 2×4 grid where one
// active station can expand and push the next row downward.

import SwiftUI

struct TheForgeView: View {

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

    var sourceCount: Int = 0
    var insightCount: Int = 0
    var maturityLabel: String = "Seed"
    var stationWidth: CGFloat = 260
    var stationColumns: Int = 4
    var columnSpacing: CGFloat = 20
    var rowSpacing: CGFloat = 20

    @State private var expandedStation: ConnectionSectionType?

    private let orderedStations: [ConnectionSectionType] = [
        [.goal, .conceptName, .problems, .benefits],
        [.process, .examples, .beliefsObjections, .references]
    ].flatMap { $0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerDeck
            MarginaliaLabel("THE FORGE")
            stationRows
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var headerDeck: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                Color.clear
                    .frame(width: 184, height: 1)
                masthead
                    .frame(maxWidth: .infinity, alignment: .top)
                maturityCard
                    .frame(width: 184, alignment: .trailing)
            }

            VStack(alignment: .center, spacing: 16) {
                masthead
                maturityCard
            }
        }
    }

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

    private var maturityCard: some View {
        ConnectionMaturityCard(
            maturityLabel: maturityLabel,
            filledCount: state.completedSectionCount
        )
    }

    private var stationRows: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(row, id: \.self) { type in
                        if let binding = stationBinding(for: type) {
                            stationCard(type: type, binding: binding)
                        }
                    }
                }
            }
        }
    }

    private var rows: [[ConnectionSectionType]] {
        stride(from: 0, to: orderedStations.count, by: stationColumns).map { start in
            let end = min(start + stationColumns, orderedStations.count)
            return Array(orderedStations[start..<end])
        }
    }

    private func stationCard(
        type: ConnectionSectionType,
        binding: Binding<ConnectionSection>
    ) -> some View {
        let isExpanded = expandedStation == type
        return StationCardView(
            section: binding,
            onAddItem: { doc, text in onAddItem(doc, text, type) },
            onEditItem: { item in onEditItem(item, type) },
            onDeleteItem: { id in onDeleteItem(id, type) },
            onSourceTap: onSourceTap,
            onAcceptGhost: { ghost in onAcceptGhost(ghost, type) },
            onDismissGhost: { id in onDismissGhost(id, type) },
            displayMode: isExpanded ? .expanded : .collapsed,
            isSelected: isExpanded,
            onSelect: {
                withAnimation(ProMotionSprings.focusTransition) {
                    expandedStation = isExpanded ? nil : type
                }
            },
            onEnterStationMode: { onEnterStationMode(type) },
            cardWidth: stationWidth
        )
        .animation(ProMotionSprings.focusTransition, value: expandedStation)
    }

    private func stationBinding(for type: ConnectionSectionType) -> Binding<ConnectionSection>? {
        guard let idx = state.sections.firstIndex(where: { $0.type == type }) else { return nil }
        return Binding(
            get: { state.sections[idx] },
            set: { state.sections[idx] = $0 }
        )
    }
}

private struct ConnectionMaturityCard: View {
    let maturityLabel: String
    let filledCount: Int

    var body: some View {
        HStack(spacing: 12) {
            MaturityCrystalView(
                filledCount: filledCount,
                diameter: 56
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(maturityLabel.uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.8)
                    .foregroundStyle(DS.giltMuted)
                Text("\(filledCount)/8 STATIONS")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.inkWash)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DS.vellumDeep.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.sepiaBorder.opacity(0.8), lineWidth: 0.5)
        )
    }
}
