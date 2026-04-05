// CosmoOS/UI/Codex/CodexWalkthroughDetailView.swift
// Full walkthrough detail — slide breakdown, transitions, composition lesson, antimatter.
// April 2026 — WP3 Codex Navigation + Premium Redesign

import SwiftUI

struct CodexWalkthroughDetailView: View {
    let atom: Atom
    let walkthrough: CodexWalkthrough
    @State private var appeared = false

    private var frameColor: Color {
        CodexElementCategory.dominantFrame.color
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                walkthroughHero
                CodexCategorySectionDivider(color: frameColor)
                detailSections
            }
        }
        .scrollIndicators(.hidden)
        .background(DS.bg)
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance.delay(0.15)) {
                appeared = true
            }
        }
    }

    // MARK: - Hero

    private var walkthroughHero: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
            heroContent
        }
        .frame(maxWidth: .infinity)
    }

    private var heroBackground: some View {
        LinearGradient(
            colors: [frameColor.opacity(0.05), frameColor.opacity(0.02), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .filmGrain(opacity: 0.015)
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(walkthrough.postTitle)
                .font(DS.display)
                .foregroundStyle(DS.text)
            creatorRow
            headerTags
        }
        .padding(.horizontal, DS.space32)
        .padding(.vertical, DS.space24)
    }

    @ViewBuilder
    private var creatorRow: some View {
        if let creator = walkthrough.creatorName {
            Text(creator)
                .font(DS.title3)
                .foregroundStyle(DS.textSecondary)
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
            Text("\(walkthrough.slides.count) slides")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.surface, in: Capsule())
        }
    }

    // MARK: - Detail Sections

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
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
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: - Why Selected

    @ViewBuilder
    private var whySelectedSection: some View {
        if let why = walkthrough.whySelected, !why.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("WHY SELECTED")
                    .dsSectionLabel()
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(frameColor)
                        .frame(width: 3)
                    Text(why)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineSpacing(3)
                        .padding(DS.space16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(frameColor.opacity(0.04), in: .rect(cornerRadius: DS.radiusMedium))
            }
        }
    }

    // MARK: - Slides

    @ViewBuilder
    private var slidesSection: some View {
        if !walkthrough.slides.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("SLIDE BREAKDOWN")
                    .dsSectionLabel()
                    .padding(.bottom, DS.space12)

                ForEach(Array(walkthrough.slides.enumerated()), id: \.element.id) { idx, slide in
                    WalkthroughSlideCard(slide: slide, index: idx)
                    if idx < walkthrough.slides.count - 1 {
                        slideConnector(fromIndex: idx)
                    }
                }
            }
        }
    }

    private func slideConnector(fromIndex: Int) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 14)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(CodexElementCategory.transition.color.opacity(0.2))
                    .frame(width: 2, height: 16)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CodexElementCategory.transition.color.opacity(0.3))
                Rectangle()
                    .fill(CodexElementCategory.transition.color.opacity(0.2))
                    .frame(width: 2, height: 8)
            }
            Spacer()
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
                transitionExplanation(transition)
            }
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CodexElementCategory.transition.color.opacity(0.3))
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.leading, 1)
        }
    }

    private func transitionBadge(from: Int, to: Int) -> some View {
        HStack(spacing: 4) {
            Text("S\(from)")
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.textMuted)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(CodexElementCategory.transition.color.opacity(0.5))
                .accessibilityHidden(true)
            Text("S\(to)")
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private func transitionExplanation(_ transition: WalkthroughTransition) -> some View {
        if let explanation = transition.explanation, !explanation.isEmpty {
            Text(explanation)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(2)
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
                .background(DS.green.opacity(0.04), in: .rect(cornerRadius: DS.radiusMedium))
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
                antimatterContent(antimatter)
            }
        }
    }

    private func antimatterContent(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(items, id: \.self) { item in
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
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.red.opacity(0.04), in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DS.red.opacity(0.3))
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.leading, 1)
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
                    .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(frameColor.opacity(0.3))
                            .frame(width: 3)
                            .padding(.vertical, 6)
                            .padding(.leading, 1)
                    }
            }
        }
    }
}

// MARK: - Slide Card

struct WalkthroughSlideCard: View {
    let slide: WalkthroughSlide
    let index: Int
    @State private var appeared = false

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
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border.opacity(0.5), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(ProMotionSprings.staggered(index: index)) {
                appeared = true
            }
        }
    }

    private var slideBadge: some View {
        Text("Slide \(slide.slideNumber)")
            .font(DS.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(DS.accent, in: Capsule())
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
        CodexFlowLayout(spacing: 6) {
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
            CodexFlowLayout(spacing: 4) {
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
