// CosmoOS/UI/Codex/CodexWalkthroughDetailView.swift
// Full walkthrough detail — slide breakdown, transitions, composition lesson, antimatter.
// April 2026 — WP3 Codex Navigation

import SwiftUI

struct CodexWalkthroughDetailView: View {
    let atom: Atom
    let walkthrough: CodexWalkthrough

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                headerSection
                whySelectedSection
                slidesSection
                transitionsSection
                compositionLessonSection
                antimatterSection
                fabricSection
            }
            .padding(DS.space32)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(DS.bg)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(walkthrough.postTitle)
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)

            if let creator = walkthrough.creatorName {
                Text(creator)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
            }

            headerTags
        }
    }

    private var headerTags: some View {
        HStack(spacing: 6) {
            if let frame = walkthrough.dominantFrame {
                CodexConceptTag(name: frame, color: CodexElementCategory.dominantFrame.color)
            }
            if let arc = walkthrough.arcShape {
                CodexConceptTag(name: arc, color: CodexElementCategory.arcShape.color)
            }
        }
    }

    // MARK: - Why Selected

    @ViewBuilder
    private var whySelectedSection: some View {
        if let why = walkthrough.whySelected, !why.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("WHY SELECTED")
                    .dsSectionLabel()

                Text(why)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineSpacing(3)
                    .padding(DS.space16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .stroke(DS.accent.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Slides

    @ViewBuilder
    private var slidesSection: some View {
        if !walkthrough.slides.isEmpty {
            VStack(alignment: .leading, spacing: DS.space16) {
                Text("SLIDE BREAKDOWN")
                    .dsSectionLabel()

                ForEach(walkthrough.slides) { slide in
                    WalkthroughSlideCard(slide: slide)
                }
            }
        }
    }

    // MARK: - Transitions

    @ViewBuilder
    private var transitionsSection: some View {
        if !walkthrough.transitions.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                Text("TRANSITIONS")
                    .dsSectionLabel()

                ForEach(walkthrough.transitions) { transition in
                    transitionRow(transition)
                }
            }
        }
    }

    private func transitionRow(_ transition: WalkthroughTransition) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            transitionBadge(from: transition.fromSlide, to: transition.toSlide)

            VStack(alignment: .leading, spacing: 2) {
                CodexConceptTag(name: transition.transitionType, color: CodexElementCategory.transition.color)

                if let explanation = transition.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineSpacing(2)
                }
            }
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private func transitionBadge(from: Int, to: Int) -> some View {
        HStack(spacing: 4) {
            Text("Slide \(from)")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Slide \(to)")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Composition Lesson

    @ViewBuilder
    private var compositionLessonSection: some View {
        if let lesson = walkthrough.compositionLesson, !lesson.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("COMPOSITION LESSON")
                    .dsSectionLabel()

                HStack(alignment: .top, spacing: DS.space12) {
                    Rectangle()
                        .fill(DS.green)
                        .frame(width: 3)

                    Text(lesson)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineSpacing(4)
                }
                .padding(DS.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.green.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(DS.green.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Antimatter

    @ViewBuilder
    private var antimatterSection: some View {
        if let antimatter = walkthrough.antimatter, !antimatter.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("ANTIMATTER")
                    .dsSectionLabel()

                ForEach(antimatter, id: \.self) { item in
                    HStack(alignment: .top, spacing: DS.space8) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.red)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                            .lineSpacing(3)
                    }
                }
                .padding(DS.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.red.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(DS.red.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - The Fabric

    @ViewBuilder
    private var fabricSection: some View {
        if let fabric = walkthrough.theFabric, !fabric.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("THE FABRIC")
                    .dsSectionLabel()

                Text(fabric)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineSpacing(4)
                    .italic()
                    .padding(DS.space16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .stroke(DS.border, lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Slide Card

struct WalkthroughSlideCard: View {
    let slide: WalkthroughSlide

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            slideBadge
            slideText
            conceptTags
            secondaryTags
            whySection
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var slideBadge: some View {
        Text("Slide \(slide.slideNumber)")
            .font(DS.caption)
            .fontWeight(.semibold)
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.accent.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private var slideText: some View {
        if let text = slide.text, !text.isEmpty {
            Text(text)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .italic()
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var conceptTags: some View {
        FlowLayout(spacing: 6) {
            if let act = slide.speechAct {
                CodexConceptTag(name: act, color: CodexElementCategory.speechAct.color)
            }
            ForEach(slide.readerDeltas, id: \.self) { delta in
                CodexConceptTag(name: delta, color: CodexElementCategory.readerDelta.color)
            }
            if let frame = slide.frame {
                CodexConceptTag(name: frame, color: CodexElementCategory.frame.color)
            }
            if let distance = slide.distance {
                CodexConceptTag(name: distance, color: CodexElementCategory.distance.color)
            }
            ForEach(slide.techniques, id: \.canonicalName) { tech in
                CodexConceptTag(name: tech.canonicalName, color: CodexElementCategory.technique.color)
            }
        }
    }

    @ViewBuilder
    private var secondaryTags: some View {
        let hasSecondary = !slide.proofTypes.isEmpty
            || !slide.motivations.isEmpty
            || !slide.compressions.isEmpty

        if hasSecondary {
            FlowLayout(spacing: 4) {
                ForEach(slide.proofTypes, id: \.self) { proof in
                    smallTag(proof, color: CodexElementCategory.proofType.color)
                }
                ForEach(slide.motivations, id: \.self) { mot in
                    smallTag(mot, color: CodexElementCategory.motivation.color)
                }
                ForEach(slide.compressions, id: \.self) { comp in
                    smallTag(comp, color: CodexElementCategory.compression.color)
                }
            }
        }
    }

    private func smallTag(_ name: String, color: Color) -> some View {
        Text(name)
            .font(DS.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private var whySection: some View {
        if let why = slide.whyThisSlideWorks, !why.isEmpty {
            Text(why)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(2)
                .padding(.top, 4)
        }
    }
}

// MARK: - Flow Layout (file-private)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews)
        -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }
        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}
