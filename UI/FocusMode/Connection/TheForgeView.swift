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
    var usageCount: Int = 0
    var referenceCount: Int = 0
    var profileCount: Int = 0
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
                masthead
                    .frame(maxWidth: .infinity, alignment: .top)
                metadataRail
                    .frame(width: 292)
            }

            VStack(alignment: .center, spacing: 16) {
                masthead
                metadataRail
                    .frame(maxWidth: 540)
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

    private var metadataRail: some View {
        ConnectionMetadataRail(
            maturityLabel: maturityLabel,
            usageCount: usageCount,
            referenceCount: referenceCount,
            profileCount: profileCount
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

private struct ConnectionMetadataRail: View {
    let maturityLabel: String
    let usageCount: Int
    let referenceCount: Int
    let profileCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                maturityPill
                countPill(title: "USED IN", value: "\(usageCount)")
                countPill(title: "REFS", value: "\(referenceCount)")
                countPill(title: "PROF", value: "\(profileCount)")
            }

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    maturityPill
                    countPill(title: "USED IN", value: "\(usageCount)")
                }
                HStack(spacing: 10) {
                    countPill(title: "REFS", value: "\(referenceCount)")
                    countPill(title: "PROF", value: "\(profileCount)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var maturityPill: some View {
        metadataPill(title: "SEED", value: maturityLabel.uppercased())
    }

    private func countPill(title: String, value: String) -> some View {
        metadataPill(title: title, value: value)
    }

    private func metadataPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.smallCaps)
                .tracking(1.5)
                .foregroundStyle(DS.giltMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(DS.inkWash)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.vellumDeep.opacity(0.55), in: Capsule())
        .overlay(
            Capsule()
                .stroke(DS.sepiaBorder.opacity(0.85), lineWidth: 0.5)
        )
    }
}
