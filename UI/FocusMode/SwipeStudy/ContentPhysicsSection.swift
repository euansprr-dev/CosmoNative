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
    }

    // MARK: - Summary Card

    @ViewBuilder
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            headerRow
            arcShapeRow
            physicsEventBadges
            fabricExcerpt
            sectionToggles
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "atom")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.entitySwipe)

            Text("CONTENT PHYSICS")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)

            Spacer()

            if profile.extractedAt != nil {
                Text("Extracted")
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 2)
                    .background(DS.greenSoft, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var arcShapeRow: some View {
        if let arc = profile.arcQuarks, let shape = arc.shape, !shape.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                arcShapePills(shape: shape)
                if let reversals = arc.winLossReversals, reversals > 0 {
                    Text("\(reversals) reversals")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
            .padding(DS.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceHover, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
    }

    @ViewBuilder
    private func arcShapePills(shape: String) -> some View {
        let beats = shape.split(separator: "-").map(String.init)
        FlowLayout(spacing: DS.space4) {
            ForEach(Array(beats.enumerated()), id: \.offset) { _, beat in
                Text(beat)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(arcBeatColor(beat))
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 2)
                    .background(arcBeatColor(beat).opacity(DS.opacitySubtle), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var physicsEventBadges: some View {
        if let events = profile.physicsEvents {
            let badges = buildEventBadges(events)
            if !badges.isEmpty {
                FlowLayout(spacing: DS.space6) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        HStack(spacing: 3) {
                            Text(badge.icon)
                                .font(.system(size: 10))
                            Text(badge.text)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.text)
                        }
                        .padding(.horizontal, DS.space8)
                        .padding(.vertical, DS.space4)
                        .background(badge.color.opacity(DS.opacityHover), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fabricExcerpt: some View {
        if let fabric = profile.deepFabric, !fabric.isEmpty {
            let excerpt = String(fabric.prefix(200)) + (fabric.count > 200 ? "..." : "")
            Text(excerpt)
                .font(DS.callout)
                .italic()
                .foregroundStyle(DS.textSecondary)
                .lineLimit(4)
                .padding(DS.space10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(DS.entitySwipe)
                        .frame(width: 3)
                }
                .background(DS.entitySwipe.opacity(DS.opacityFaint), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
    }

    @ViewBuilder
    private var sectionToggles: some View {
        FlowLayout(spacing: DS.space6) {
            ForEach(PhysicsDetailSection.allCases) { section in
                if sectionHasData(section) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            expandedSection = expandedSection == section ? nil : section
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: expandedSection == section ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                            Text(section.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(expandedSection == section ? DS.accent : DS.textMuted)
                        .padding(.horizontal, DS.space8)
                        .padding(.vertical, DS.space4)
                        .background(
                            expandedSection == section ? DS.accentSoft : DS.surfaceHover,
                            in: Capsule()
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

    private func arcBeatColor(_ beat: String) -> Color {
        let b = beat.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if b.contains("win") || b.contains("success") || b.contains("peace") { return DS.green }
        if b.contains("fail") || b.contains("loss") || b.contains("crisis") { return DS.red }
        if b.contains("grind") || b.contains("struggle") { return DS.orange }
        if b.contains("empty") || b.contains("doubt") { return DS.textMuted }
        if b.contains("restart") || b.contains("rebuild") { return DS.info }
        return DS.textSecondary
    }

    private struct EventBadge {
        let icon: String
        let text: String
        let color: Color
    }

    private func buildEventBadges(_ events: PhysicsEvents) -> [EventBadge] {
        var badges: [EventBadge] = []
        if let brk = events.symmetryBreak, let slide = brk.slideNumber, slide > 0 {
            badges.append(EventBadge(icon: "⚡", text: "Break @\(slide)", color: DS.orange))
        }
        if let pt = events.phaseTransition, let slide = pt.slideNumber, slide > 0 {
            let shift = [pt.frameBefore, pt.frameAfter].compactMap { $0 }.joined(separator: " → ")
            badges.append(EventBadge(icon: "🔮", text: shift.isEmpty ? "@\(slide)" : "\(shift) @\(slide)", color: DS.info))
        }
        if let pg = events.peakGravity, let loops = pg.activeLoops, loops > 0 {
            badges.append(EventBadge(icon: "🌀", text: "\(loops) loops", color: DS.entitySwipe))
        }
        if let er = events.energyResolution {
            let label = er.proportional == true ? "Proportional" : "Disproportional"
            badges.append(EventBadge(icon: "⚖️", text: label, color: er.proportional == true ? DS.green : DS.red))
        }
        return badges
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

// MARK: - Flow Layout (for wrapping pills)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return LayoutResult(
            size: CGSize(width: maxWidth, height: y + rowHeight),
            positions: positions
        )
    }
}
