// CosmoOS/UI/FocusMode/SwipeStudy/ContentPhysicsSection.swift
// Content Physics dashboard — hero header, event timeline, arc viz, section grid

import SwiftUI

struct ContentPhysicsSection: View {
    let profile: ContentPhysicsProfile

    @State private var expandedSections: Set<PhysicsDetailSection> = []
    @State private var selectedSlide: Int?
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            PhysicsHeroHeaderView(profile: profile)
            eventTimelineSection
            arcVisualizationSection
            sectionGrid
            expandedDetailViews
            antimatterFooter
        }
        .onAppear { withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true } }
    }

    // MARK: - Event Timeline

    @ViewBuilder
    private var eventTimelineSection: some View {
        if let events = profile.physicsEvents, hasAnyEvent(events) {
            PhysicsEventTimelineView(
                events: events,
                totalSlides: totalSlideCount,
                selectedSlide: $selectedSlide
            )
        }
    }

    // MARK: - Arc Visualization

    @ViewBuilder
    private var arcVisualizationSection: some View {
        if profile.arcQuarks?.shape != nil || profile.rhythm?.energyCurve != nil {
            PhysicsArcVisualizationView(
                arcQuarks: profile.arcQuarks,
                energyCurve: profile.rhythm?.energyCurve,
                selectedSlide: $selectedSlide
            )
        }
    }

    // MARK: - Section Grid

    @ViewBuilder
    private var sectionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.space12) {
            ForEach(PhysicsDetailSection.allCases) { section in
                if sectionHasData(section) {
                    sectionCard(for: section)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 12)
                        .animation(ProMotionSprings.staggered(index: section.sortIndex), value: hasAppeared)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard(for section: PhysicsDetailSection) -> some View {
        let isExpanded = expandedSections.contains(section)
        PhysicsSectionCardView(
            title: section.label,
            icon: section.icon,
            iconColor: section.color,
            summary: section.summaryText(from: profile),
            isExpanded: isExpanded,
            onTap: {
                withAnimation(ProMotionSprings.gentle) {
                    if isExpanded { expandedSections.remove(section) }
                    else { expandedSections.insert(section) }
                }
            },
            preview: { sectionPreview(for: section) },
            detail: { EmptyView() }
        )
    }

    @ViewBuilder
    private func sectionPreview(for section: PhysicsDetailSection) -> some View {
        switch section {
        case .slideQuarks:
            quarkPreviewDots
        case .rhythm:
            rhythmPreviewBars
        case .readerJourney:
            journeyPreviewSparkline
        default:
            EmptyView()
        }
    }

    // MARK: - Mini Previews

    @ViewBuilder
    private var quarkPreviewDots: some View {
        if let quarks = profile.slideQuarks {
            HStack(spacing: 3) {
                ForEach(quarks.prefix(16)) { quark in
                    Circle()
                        .fill(quarkDotColor(quark))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    @ViewBuilder
    private var rhythmPreviewBars: some View {
        if let density = profile.rhythm?.densityWaveform, !density.isEmpty {
            let maxVal = max(density.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(density.prefix(20).enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(DS.green.opacity(0.5))
                        .frame(width: 3, height: max(CGFloat(value / maxVal) * 18, 2))
                }
            }
            .frame(height: 20)
        }
    }

    @ViewBuilder
    private var journeyPreviewSparkline: some View {
        if let sim = profile.readerSimulation, !sim.isEmpty {
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(sim.prefix(16)) { state in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(investmentPreviewColor(state.investmentLevel ?? "low"))
                        .frame(width: 4, height: investmentPreviewHeight(state.investmentLevel ?? "low"))
                }
            }
            .frame(height: 20)
        }
    }

    // MARK: - Expanded Detail Views

    @ViewBuilder
    private var expandedDetailViews: some View {
        ForEach(PhysicsDetailSection.allCases) { section in
            if expandedSections.contains(section) && sectionHasData(section) {
                detailView(for: section)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: PhysicsDetailSection) -> some View {
        switch section {
        case .slideQuarks:
            PhysicsSlideQuarksView(quarks: profile.slideQuarks ?? [], selectedSlide: $selectedSlide)
        case .transitions:
            PhysicsTransitionFlowView(transitions: profile.transitions ?? [])
        case .readerJourney:
            PhysicsReaderJourneyView(
                simulation: profile.readerSimulation ?? [],
                rsvPoints: profile.rsv?.trajectoryPoints ?? [],
                physicsEvents: profile.physicsEvents,
                selectedSlide: $selectedSlide
            )
        case .rhythm:
            PhysicsRhythmView(rhythm: profile.rhythm, selectedSlide: $selectedSlide)
        case .bonds:
            PhysicsBondsView(interactions: profile.longRangeInteractions, totalSlides: totalSlideCount, selectedSlide: $selectedSlide)
        case .fabric:
            PhysicsFabricView(text: profile.deepFabric ?? "")
        }
    }

    // MARK: - Antimatter Footer

    @ViewBuilder
    private var antimatterFooter: some View {
        if let antimatter = profile.antimatter, !antimatter.isEmpty {
            AntimatterFooterView(items: antimatter)
        }
    }

    // MARK: - Helpers

    private var totalSlideCount: Int {
        max(
            profile.slideQuarks?.count ?? 0,
            profile.readerSimulation?.last?.afterSlide ?? 0,
            profile.transitions?.map(\.to).max() ?? 0,
            1
        )
    }

    private func hasAnyEvent(_ events: PhysicsEvents) -> Bool {
        (events.symmetryBreak?.slideNumber ?? 0) > 0 ||
        (events.phaseTransition?.slideNumber ?? 0) > 0 ||
        (events.peakGravity?.slideNumber ?? 0) > 0 ||
        events.energyResolution != nil
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

    private func quarkDotColor(_ quark: SlideQuark) -> Color {
        guard let delta = quark.readerDeltas?.first?.type?.lowercased() else { return DS.textMuted.opacity(0.3) }
        if delta.contains("tension") || delta.contains("empathy") { return DS.red.opacity(0.6) }
        if delta.contains("trust") || delta.contains("hope") || delta.contains("curiosity") { return DS.green.opacity(0.6) }
        if delta.contains("surprise") { return DS.orange.opacity(0.6) }
        if delta.contains("identification") { return DS.info.opacity(0.6) }
        return DS.textMuted.opacity(0.3)
    }

    private func investmentPreviewColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "locked-in", "locked in": return DS.red
        case "high": return DS.orange.opacity(0.7)
        case "medium", "building": return DS.info.opacity(0.5)
        default: return DS.textMuted.opacity(0.3)
        }
    }

    private func investmentPreviewHeight(_ level: String) -> CGFloat {
        switch level.lowercased() {
        case "locked-in", "locked in": return 20
        case "high": return 15
        case "medium", "building": return 10
        default: return 4
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

    var sortIndex: Int {
        switch self {
        case .slideQuarks: return 0
        case .transitions: return 1
        case .readerJourney: return 2
        case .rhythm: return 3
        case .bonds: return 4
        case .fabric: return 5
        }
    }

    var icon: String {
        switch self {
        case .slideQuarks: return "atom"
        case .transitions: return "arrow.right.arrow.left"
        case .readerJourney: return "chart.line.uptrend.xyaxis"
        case .rhythm: return "waveform"
        case .bonds: return "link"
        case .fabric: return "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .slideQuarks: return DS.entitySwipe
        case .transitions: return DS.info
        case .readerJourney: return DS.orange
        case .rhythm: return DS.green
        case .bonds: return DS.entityConnection
        case .fabric: return DS.entityNote
        }
    }

    func summaryText(from profile: ContentPhysicsProfile) -> String {
        switch self {
        case .slideQuarks:
            return "\(profile.slideQuarks?.count ?? 0) slides analyzed"
        case .transitions:
            return "\(profile.transitions?.count ?? 0) causal transitions"
        case .readerJourney:
            let peak = profile.readerSimulation?.last(where: { ($0.investmentLevel ?? "").lowercased().contains("locked") })
            if let slide = peak?.afterSlide { return "Locked in @slide \(slide)" }
            return "\(profile.readerSimulation?.count ?? 0) reader states"
        case .rhythm:
            return profile.rhythm?.pacingPattern ?? "Density & energy waveforms"
        case .bonds:
            let count = profile.longRangeInteractions?.setupPayoffBonds?.count ?? 0
            return "\(count) setup-payoff bonds"
        case .fabric:
            return "Deep synthesis"
        }
    }
}

// MARK: - Antimatter Footer

private struct AntimatterFooterView: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            headerRow
            itemsList
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.redSoft, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.red.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.callout)
                .foregroundStyle(DS.red)
                .accessibilityHidden(true)
            Text("ANTIMATTER")
                .font(DS.caption)
                .tracking(0.8)
                .foregroundStyle(DS.red)
        }
    }

    @ViewBuilder
    private var itemsList: some View {
        ForEach(items.prefix(6), id: \.self) { item in
            HStack(alignment: .top, spacing: DS.space6) {
                Circle()
                    .fill(DS.red.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                Text(item)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
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
