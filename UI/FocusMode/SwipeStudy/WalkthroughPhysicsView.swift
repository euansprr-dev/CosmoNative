// CosmoOS/UI/FocusMode/SwipeStudy/WalkthroughPhysicsView.swift
// Renders Content Physics data with interactive codex tags on every element.
// Used in BlueprintDisplayView (physics mode) and outline composer.

import SwiftUI

// MARK: - Data Source

enum PhysicsDataSource {
    case profile(ContentPhysicsProfile)
    case walkthrough(CodexWalkthrough)
}

// MARK: - View

struct WalkthroughPhysicsView: View {
    let source: PhysicsDataSource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space20) {
                if slideData.isEmpty && arcShape == nil && dominantFrame == nil {
                    emptyState
                } else {
                    arcHeader
                    slidesSection
                    transitionsSection
                }
            }
            .padding(DS.space16)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Arc Header

extension WalkthroughPhysicsView {
    private var arcHeader: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("ARC & FRAME").dsSectionLabel()
            HStack(spacing: DS.space8) {
                if let arc = arcShape {
                    CodexConceptTag(name: arc, color: CodexElementCategory.arcShape.color)
                }
                if let frame = dominantFrame {
                    CodexConceptTag(name: frame, color: CodexElementCategory.dominantFrame.color)
                }
            }
        }
    }
}

// MARK: - Slides Section

extension WalkthroughPhysicsView {
    private var slidesSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if !slideData.isEmpty {
                Text("SLIDES").dsSectionLabel()
                ForEach(slideData) { slide in
                    slideCard(slide)
                }
            }
        }
    }

    private func slideCard(_ slide: SlideDisplayData) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            slideBadge(slide.slideNumber)
            slideTextPreview(slide.text)
            slideTagsFlow(slide)
        }
        .padding(DS.space12)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 0.5)
        )
    }

    private func slideBadge(_ number: Int) -> some View {
        Text("Slide \(number)")
            .font(DS.caption)
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.accent, in: Capsule())
    }

    @ViewBuilder
    private func slideTextPreview(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
                .italic()
        }
    }

    private func slideTagsFlow(_ slide: SlideDisplayData) -> some View {
        FlowLayout(spacing: 4) {
            if let act = slide.speechAct {
                CodexConceptTag(name: act, color: CodexElementCategory.speechAct.color)
            }
            ForEach(slide.readerDeltas, id: \.self) { delta in
                CodexConceptTag(name: delta, color: CodexElementCategory.readerDelta.color)
            }
            if let frame = slide.frame {
                CodexConceptTag(name: frame, color: CodexElementCategory.frame.color)
            }
            if let dist = slide.distance {
                CodexConceptTag(name: dist, color: CodexElementCategory.distance.color)
            }
            ForEach(slide.techniques, id: \.self) { tech in
                CodexConceptTag(name: tech, color: CodexElementCategory.technique.color)
            }
            ForEach(slide.proofTypes, id: \.self) { proof in
                CodexConceptTag(name: proof, color: CodexElementCategory.proofType.color)
            }
            ForEach(slide.motivations, id: \.self) { motive in
                CodexConceptTag(name: motive, color: CodexElementCategory.motivation.color)
            }
            ForEach(slide.compressions, id: \.self) { comp in
                CodexConceptTag(name: comp, color: CodexElementCategory.compression.color)
            }
        }
    }
}

// MARK: - Transitions Section

extension WalkthroughPhysicsView {
    @ViewBuilder
    private var transitionsSection: some View {
        if !transitionData.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                Text("TRANSITIONS").dsSectionLabel()
                ForEach(transitionData) { t in
                    transitionRow(t)
                }
            }
        }
    }

    private func transitionRow(_ t: TransitionDisplayData) -> some View {
        HStack(spacing: DS.space8) {
            Text("Slide \(t.from) \u{2192} \(t.to)")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            CodexConceptTag(name: t.type, color: CodexElementCategory.transition.color)
            if let mech = t.mechanism, !mech.isEmpty {
                Text(mech)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Empty State

extension WalkthroughPhysicsView {
    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "atom")
                .font(.system(size: 28))
                .foregroundStyle(DS.textMuted)
            Text("No physics data available")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Normalized Data Helpers

extension WalkthroughPhysicsView {
    private var arcShape: String? {
        switch source {
        case .profile(let p): p.arcQuarks?.shape
        case .walkthrough(let w): w.arcShape
        }
    }

    private var dominantFrame: String? {
        switch source {
        case .profile(let p): p.arcQuarks?.dominantFrame?.type
        case .walkthrough(let w): w.dominantFrame
        }
    }

    private var slideData: [SlideDisplayData] {
        switch source {
        case .profile(let p):
            return (p.slideQuarks ?? []).map { sq in
                SlideDisplayData(
                    slideNumber: sq.slideNumber,
                    text: sq.text,
                    speechAct: sq.speechAct.type,
                    readerDeltas: (sq.readerDeltas ?? []).compactMap(\.type),
                    frame: sq.frame?.type,
                    distance: sq.experientialDistance?.type,
                    techniques: (sq.techniques ?? []).map(\.technique),
                    proofTypes: [sq.proofType?.type].compactMap { $0 },
                    motivations: [sq.motivation?.type].compactMap { $0 },
                    compressions: [sq.compression?.type].compactMap { $0 }.filter { !$0.isEmpty }
                )
            }
        case .walkthrough(let w):
            return w.slides.map { slide in
                SlideDisplayData(
                    slideNumber: slide.slideNumber,
                    text: slide.text,
                    speechAct: slide.speechAct,
                    readerDeltas: slide.readerDeltas,
                    frame: slide.frame,
                    distance: slide.distance,
                    techniques: slide.techniques.map(\.canonicalName),
                    proofTypes: slide.proofTypes,
                    motivations: slide.motivations,
                    compressions: slide.compressions
                )
            }
        }
    }

    private var transitionData: [TransitionDisplayData] {
        switch source {
        case .profile(let p):
            return (p.transitions ?? []).map { t in
                TransitionDisplayData(from: t.from, to: t.to, type: t.type, mechanism: t.mechanism)
            }
        case .walkthrough(let w):
            return w.transitions.map { t in
                TransitionDisplayData(from: t.fromSlide, to: t.toSlide, type: t.transitionType, mechanism: t.explanation)
            }
        }
    }
}

// MARK: - Display Data

private struct SlideDisplayData: Identifiable {
    var id: Int { slideNumber }
    let slideNumber: Int
    let text: String?
    let speechAct: String?
    let readerDeltas: [String]
    let frame: String?
    let distance: String?
    let techniques: [String]
    let proofTypes: [String]
    let motivations: [String]
    let compressions: [String]
}

private struct TransitionDisplayData: Identifiable {
    var id: String { "\(from)-\(to)" }
    let from: Int
    let to: Int
    let type: String
    let mechanism: String?
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

// MARK: - Preview

#Preview("Profile Source") {
    WalkthroughPhysicsView(source: .profile(ContentPhysicsProfile(
        version: 1,
        extractedAt: nil,
        extractedBy: nil,
        slideQuarks: [
            SlideQuark(
                slideNumber: 1,
                text: "2020: \"Babe, I'm worried about our future...\"",
                speechAct: QuarkMechanism(type: "REVEAL", mechanism: "Opens with vulnerability"),
                readerDeltas: [QuarkMechanism(type: "CURIOSITY+", mechanism: nil), QuarkMechanism(type: "TRUST+", mechanism: nil)],
                proofType: QuarkMechanism(type: "LIVED", mechanism: nil),
                motivation: QuarkMechanism(type: "FEAR_ESCAPE", mechanism: nil),
                compression: nil,
                resonanceFrequency: nil,
                frame: QuarkMechanism(type: "DIALOGUE", mechanism: nil),
                experientialDistance: QuarkMechanism(type: "ZERO", mechanism: nil),
                techniques: [TechniqueEntry(technique: "TIMELINE_ANCHOR", usage: nil)]
            ),
        ],
        transitions: [
            QuarkTransition(from: 1, to: 2, type: "ESCALATION", mechanism: "Stakes increase", swapTestPasses: nil, doubleHelix: nil, doubleHelixDetail: nil),
        ],
        arcQuarks: ArcQuarks(shape: "J-CURVE", winLossReversals: 2, sparseDensePattern: nil, internalExternalTension: nil, dominantFrame: QuarkMechanism(type: "TRANSFORMATION_ARC", mechanism: nil), tensionPeaks: nil),
        rsv: nil,
        physicsEvents: nil,
        novelDiscoveries: nil,
        longRangeInteractions: nil,
        antimatter: nil,
        rhythm: nil,
        readerSimulation: nil,
        deepFabric: nil
    )))
    .frame(width: 460, height: 600)
}

#Preview("Empty") {
    WalkthroughPhysicsView(source: .profile(ContentPhysicsProfile(
        version: nil, extractedAt: nil, extractedBy: nil,
        slideQuarks: nil, transitions: nil, arcQuarks: nil,
        rsv: nil, physicsEvents: nil, novelDiscoveries: nil,
        longRangeInteractions: nil, antimatter: nil, rhythm: nil,
        readerSimulation: nil, deepFabric: nil
    )))
    .frame(width: 460, height: 300)
}
