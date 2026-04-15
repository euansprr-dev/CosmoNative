// CosmoOS/UI/Codex/CodexWalkthroughDetailView.swift
// Full walkthrough detail — slide breakdown, transitions, composition lesson, antimatter.
// April 2026 — Akashic Records Premium Redesign

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
                AkashicSectionDivider()
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
        ZStack {
            DS.vellum
            RadialGradient(
                colors: [frameColor.opacity(0.03), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 400
            )
        }
        .filmGrain(opacity: 0.02)
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(walkthrough.postTitle)
                .font(DS.displaySerif)
                .foregroundStyle(DS.inkWash)
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
                .font(DS.dateSerif)
                .foregroundStyle(DS.inkFaded)
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
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
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
                AkashicSectionHeader(title: "WHY SELECTED")
                AkashicCallout(text: why, tintColor: frameColor, font: DS.callout)
            }
        }
    }

    // MARK: - Slides

    @ViewBuilder
    private var slidesSection: some View {
        if !walkthrough.slides.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                AkashicSectionHeader(title: "SLIDE BREAKDOWN")
                    .padding(.bottom, DS.space12)

                ForEach(Array(walkthrough.slides.enumerated()), id: \.element.id) { idx, slide in
                    WalkthroughSlideCard(slide: slide, index: idx)
                    if idx < walkthrough.slides.count - 1 {
                        slideConnector
                    }
                }
            }
        }
    }

    private var slideConnector: some View {
        HStack {
            Spacer().frame(width: 14)
            GiltDotConnector()
            Spacer()
        }
    }

    // MARK: - Transitions

    @ViewBuilder
    private var transitionsSection: some View {
        if !walkthrough.transitions.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                AkashicSectionHeader(title: "TRANSITIONS")
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
        .dsVellumCard(cornerRadius: DS.radiusMedium)
    }

    private func transitionBadge(from: Int, to: Int) -> some View {
        HStack(spacing: 4) {
            Text("S\(from)")
                .font(DS.smallCaps)
                .foregroundStyle(DS.inkFaded)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(DS.giltMuted)
                .accessibilityHidden(true)
            Text("S\(to)")
                .font(DS.smallCaps)
                .foregroundStyle(DS.inkFaded)
        }
    }

    @ViewBuilder
    private func transitionExplanation(_ transition: WalkthroughTransition) -> some View {
        if let explanation = transition.explanation, !explanation.isEmpty {
            Text(explanation)
                .font(DS.caption)
                .foregroundStyle(DS.inkFaded)
                .lineSpacing(2)
        }
    }

    // MARK: - Composition Lesson

    @ViewBuilder
    private var compositionLessonSection: some View {
        if let lesson = walkthrough.compositionLesson, !lesson.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                AkashicSectionHeader(title: "COMPOSITION LESSON")
                AkashicCallout(text: lesson, tintColor: DS.green, font: DS.callout)
            }
        }
    }

    // MARK: - Antimatter

    @ViewBuilder
    private var antimatterSection: some View {
        if let antimatter = walkthrough.antimatter, !antimatter.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                AkashicSectionHeader(title: "ANTIMATTER")
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
                        .foregroundStyle(DS.inkWash)
                        .lineSpacing(3)
                }
            }
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DS.vellumDeep.opacity(0.8),
            in: .rect(cornerRadius: DS.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.red.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - The Fabric

    @ViewBuilder
    private var fabricSection: some View {
        if let fabric = walkthrough.theFabric, !fabric.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                AkashicSectionHeader(title: "THE FABRIC")
                fabricContent(fabric)
            }
        }
    }

    private func fabricContent(_ text: String) -> some View {
        VStack(spacing: 0) {
            OrnamentalRule(width: 60, color: DS.gilt)
                .padding(.bottom, DS.space12)
            Text(text)
                .font(DS.body)
                .fontDesign(.serif)
                .foregroundStyle(DS.inkWash)
                .lineSpacing(5)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
            OrnamentalRule(width: 60, color: DS.gilt)
                .padding(.top, DS.space12)
        }
        .padding(DS.space16)
        .background(DS.vellumDeep, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.giltMuted, lineWidth: 0.5)
        )
        .filmGrain(opacity: 0.025)
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
        .dsVellumCard(cornerRadius: DS.radiusMedium)
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
            .font(DS.smallCaps)
            .foregroundStyle(DS.gilt)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(DS.giltSoft, in: .rect(cornerRadius: DS.radiusXSmall))
    }

    @ViewBuilder
    private var slideText: some View {
        if let text = slide.text, !text.isEmpty {
            Text(text)
                .font(DS.body)
                .fontDesign(.serif)
                .foregroundStyle(DS.inkWash)
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
            .background(color.opacity(0.1), in: .rect(cornerRadius: DS.radiusXSmall))
    }

    @ViewBuilder
    private var whySection: some View {
        if let why = slide.whyThisSlideWorks, !why.isEmpty {
            Text(why)
                .font(DS.caption)
                .foregroundStyle(DS.inkFaded)
                .lineSpacing(2)
                .padding(.top, 4)
        }
    }
}
