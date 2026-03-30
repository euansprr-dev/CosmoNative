// CosmoOS/UI/FocusMode/SwipeStudy/ContentPhysicsSection.swift
// Content Physics profile visualization — summary card + expandable detail sections

import SwiftUI

struct ContentPhysicsSection: View {
    let profile: ContentPhysicsProfile

    @State private var expandedSection: PhysicsDetailSection?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            summaryCard
            if let section = expandedSection {
                detailView(for: section)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expandedSection)
    }

    // MARK: - Summary Card

    @ViewBuilder
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            headerRow
            arcShapeSection
            physicsEventsSection
            antimatterSection
            fabricExcerptSection
            sectionToggles
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "atom")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.entitySwipe)

            Text("CONTENT PHYSICS")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.entitySwipe)

            Spacer()

            if profile.extractedAt != nil {
                Text("Extracted")
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, 3)
                    .background(DS.greenSoft, in: Capsule())
            }
        }
    }

    // MARK: - Arc Shape (readable text, not broken pills)

    @ViewBuilder
    private var arcShapeSection: some View {
        if let arc = profile.arcQuarks, let shape = arc.shape, !shape.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                    // Extract arc type (first word or phrase before colon/comma)
                    let arcType = extractArcType(from: shape)
                    Text(arcType)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.entitySwipe)
                        .padding(.horizontal, DS.space8)
                        .padding(.vertical, DS.space4)
                        .background(DS.entitySwipe.opacity(0.12), in: Capsule())

                    if let reversals = arc.winLossReversals, reversals > 0 {
                        Text("\(reversals) reversals")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.textSecondary)
                    }
                }

                // Full arc description as readable text
                Text(shape)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.entitySwipe.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.entitySwipe.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - Physics Events (wrapping rows, not truncating pills)

    @ViewBuilder
    private var physicsEventsSection: some View {
        if let events = profile.physicsEvents {
            VStack(alignment: .leading, spacing: DS.space8) {
                if let brk = events.symmetryBreak, let slide = brk.slideNumber, slide > 0 {
                    physicsEventRow(
                        icon: "⚡",
                        label: "Symmetry Break",
                        value: "@slide \(slide)",
                        detail: brk.whatBreaks,
                        color: DS.orange
                    )
                }
                if let pt = events.phaseTransition, let slide = pt.slideNumber, slide > 0 {
                    let shift = [pt.frameBefore, pt.frameAfter].compactMap { $0 }.joined(separator: " → ")
                    physicsEventRow(
                        icon: "🔮",
                        label: "Phase Transition",
                        value: "\(shift) @slide \(slide)",
                        detail: pt.recontextualization,
                        color: DS.info
                    )
                }
                if let pg = events.peakGravity, let loops = pg.activeLoops, loops > 0 {
                    physicsEventRow(
                        icon: "🌀",
                        label: "Peak Gravity",
                        value: "\(loops) loops @slide \(pg.slideNumber ?? 0)",
                        detail: nil,
                        color: DS.entitySwipe
                    )
                }
                if let er = events.energyResolution {
                    physicsEventRow(
                        icon: "⚖️",
                        label: "Energy",
                        value: er.proportional == true ? "Proportional" : "Disproportional",
                        detail: nil,
                        color: er.proportional == true ? DS.green : DS.red
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func physicsEventRow(icon: String, label: String, value: String, detail: String?, color: Color) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Text(icon)
                .font(.system(size: 12))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.space6) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.text)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)

                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Antimatter

    @ViewBuilder
    private var antimatterSection: some View {
        if let antimatter = profile.antimatter, !antimatter.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space4) {
                    Text("☢️")
                        .font(.system(size: 11))
                    Text("ANTIMATTER")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(DS.red)
                }
                ForEach(antimatter.prefix(4), id: \.self) { item in
                    Text("• \(item)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.text)

                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.red.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.red.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - Fabric Excerpt

    @ViewBuilder
    private var fabricExcerptSection: some View {
        if let fabric = profile.deepFabric, !fabric.isEmpty {
            let excerpt = String(fabric.prefix(250)) + (fabric.count > 250 ? "..." : "")
            Text(excerpt)
                .font(DS.callout)
                .foregroundStyle(DS.text.opacity(0.85))
                .lineSpacing(4)

                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, DS.space12)
                .padding(.vertical, DS.space10)
                .padding(.trailing, DS.space10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.entitySwipe)
                        .frame(width: 3)
                }
                .background(DS.entitySwipe.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
    }

    // MARK: - Section Toggles

    @ViewBuilder
    private var sectionToggles: some View {
        FlowLayout(spacing: DS.space6) {
            ForEach(PhysicsDetailSection.allCases) { section in
                if sectionHasData(section) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            expandedSection = expandedSection == section ? nil : section
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expandedSection == section ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                            Text(section.label)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(expandedSection == section ? .white : DS.textSecondary)
                        .padding(.horizontal, DS.space10)
                        .padding(.vertical, DS.space6)
                        .background(
                            expandedSection == section ? DS.entitySwipe : DS.surfaceHover,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(expandedSection == section ? DS.entitySwipe : DS.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Detail Views

    @ViewBuilder
    private func detailView(for section: PhysicsDetailSection) -> some View {
        switch section {
        case .slideQuarks:
            PhysicsSlideQuarksView(quarks: profile.slideQuarks ?? [])
        case .transitions:
            PhysicsTransitionFlowView(transitions: profile.transitions ?? [])
        case .readerJourney:
            PhysicsReaderJourneyView(
                simulation: profile.readerSimulation ?? [],
                rsvPoints: profile.rsv?.trajectoryPoints ?? [],
                physicsEvents: profile.physicsEvents
            )
        case .rhythm:
            PhysicsRhythmView(rhythm: profile.rhythm)
        case .bonds:
            PhysicsBondsView(interactions: profile.longRangeInteractions)
        case .fabric:
            PhysicsFabricView(text: profile.deepFabric ?? "")
        }
    }

    // MARK: - Helpers

    private func extractArcType(from shape: String) -> String {
        // Extract the arc type from the beginning (before first colon or comma)
        let separators: [Character] = [":", ","]
        if let firstSep = shape.firstIndex(where: { separators.contains($0) }) {
            let prefix = String(shape[shape.startIndex..<firstSep]).trimmingCharacters(in: .whitespaces)
            if prefix.count <= 40 { return prefix }
        }
        return String(shape.prefix(30))
    }

    private func sectionHasData(_ section: PhysicsDetailSection) -> Bool {
        switch section {
        case .slideQuarks: return !(profile.slideQuarks ?? []).isEmpty
        case .transitions: return !(profile.transitions ?? []).isEmpty
        case .readerJourney: return !(profile.readerSimulation ?? []).isEmpty || !(profile.rsv?.trajectoryPoints ?? []).isEmpty
        case .rhythm: return profile.rhythm != nil
        case .bonds: return profile.longRangeInteractions != nil
        case .fabric: return profile.deepFabric != nil && !(profile.deepFabric ?? "").isEmpty
        }
    }
}

// MARK: - Section Enum

enum PhysicsDetailSection: String, CaseIterable, Identifiable {
    case slideQuarks = "Slide Quarks"
    case transitions = "Transitions"
    case readerJourney = "Reader Journey"
    case rhythm = "Rhythm"
    case bonds = "Bonds"
    case fabric = "Fabric"

    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult { var size: CGSize; var positions: [CGPoint] }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return LayoutResult(size: CGSize(width: maxWidth, height: y + rowHeight), positions: positions)
    }
}
