// CosmoOS/UI/FocusMode/Ideas/OutlineComposer/OutlineComposerView.swift
// 5-step sheet flow for composing codex-tagged outlines.

import SwiftUI

// MARK: - Step Enum

enum OutlineComposerStep: Int, CaseIterable {
    case pickArc = 0
    case template = 1
    case browse = 2
    case compose = 3
    case review = 4

    var title: String {
        switch self {
        case .pickArc: "Pick Arc Shape"
        case .template: "Template"
        case .browse: "Browse Blueprint"
        case .compose: "Compose Outline"
        case .review: "Review"
        }
    }
}

// MARK: - Drag Item

struct CodexDragItem: Codable, Transferable {
    let canonicalName: String
    let category: CodexElementCategory

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: CodexDragItem.self, contentType: .json)
    }
}

// MARK: - Outline Composer View

struct OutlineComposerView: View {
    let arcRecommendations: [ArcRecommendation]
    let onComplete: (CodexOutlineModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: OutlineComposerStep = .pickArc
    @State private var outline = CodexOutlineModel(arcShape: nil, slides: [])
    @State private var arcShapes: [(Atom, CodexElement)] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            composerHeader
            Divider().background(DS.border)
            stepContent
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 750)
        .background(DS.bg)
        .task { await loadArcShapes() }
    }

    // MARK: - Step Router

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .pickArc: arcSelectionStep
        case .template: templateStep
        case .browse: browseStep
        case .compose: composeStep
        case .review: reviewStep
        }
    }

    // MARK: - Data Loading

    private func loadArcShapes() async {
        do {
            arcShapes = try await CodexRepository.shared.arcShapes()
        } catch {}
        isLoading = false
    }
}

// MARK: - Header

extension OutlineComposerView {
    private var composerHeader: some View {
        HStack {
            backButton
            Spacer()
            stepIndicator
            Spacer()
            nextButton
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
        .background(DS.surface)
    }

    @ViewBuilder
    private var backButton: some View {
        if currentStep.rawValue > 0 {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    currentStep = OutlineComposerStep(rawValue: currentStep.rawValue - 1) ?? .pickArc
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Back")
                        .font(DS.callout)
                }
                .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 80, alignment: .leading)
        } else {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 80, alignment: .leading)
        }
    }

    private var stepIndicator: some View {
        VStack(spacing: DS.space4) {
            HStack(spacing: DS.space8) {
                ForEach(OutlineComposerStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == currentStep ? DS.accent : DS.borderSubtle)
                        .frame(width: 8, height: 8)
                }
            }
            Text(currentStep.title)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if currentStep == .review {
            Button {
                onComplete(outline)
                dismiss()
            } label: {
                Text("Done")
                    .font(DS.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space6)
                    .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(width: 80, alignment: .trailing)
        } else {
            Color.clear.frame(width: 80)
        }
    }
}

// MARK: - Step 1: Pick Arc

extension OutlineComposerView {
    private var arcSelectionStep: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                arcGrid
                skipButton
            }
        }
    }

    private var arcGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: DS.space12)], spacing: DS.space12) {
                ForEach(arcShapes, id: \.0.uuid) { atom, element in
                    arcCard(element)
                }
            }
            .padding(DS.space20)
        }
        .scrollIndicators(.hidden)
    }

    private func arcCard(_ element: CodexElement) -> some View {
        let isRecommended = arcRecommendations.contains { $0.arcName.lowercased() == element.canonicalName.lowercased() }
        let recommendation = arcRecommendations.first { $0.arcName.lowercased() == element.canonicalName.lowercased() }

        return Button {
            withAnimation(ProMotionSprings.snappy) {
                outline = CodexOutlineModel(arcShape: element.canonicalName, slides: generateTemplate(for: element))
                currentStep = .template
            }
        } label: {
            arcCardLabel(element: element, isRecommended: isRecommended, recommendation: recommendation)
        }
        .buttonStyle(.plain)
    }

    private func arcCardLabel(element: CodexElement, isRecommended: Bool, recommendation: ArcRecommendation?) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack {
                Text(element.canonicalName)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                Spacer()
                if isRecommended {
                    Text("Recommended")
                        .font(DS.caption2)
                        .foregroundStyle(DS.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.green.opacity(DS.opacitySubtle), in: Capsule())
                }
            }
            Text(element.definition)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
            if let freq = element.frequency, !freq.isEmpty {
                Text(freq)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            if let rec = recommendation {
                Text(rec.explanation)
                    .font(DS.caption2)
                    .foregroundStyle(CodexElementCategory.arcShape.color)
                    .lineLimit(2)
            }
        }
        .padding(DS.space12)
        .dsCard()
    }

    private var skipButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                outline = CodexOutlineModel(arcShape: nil, slides: generateDefaultTemplate())
                currentStep = .template
            }
        } label: {
            Text("Skip -- Auto-generate")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space8)
                .background(DS.borderSubtle.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, DS.space16)
    }
}

// MARK: - Step 2: Template

extension OutlineComposerView {
    private var templateStep: some View {
        VStack(spacing: DS.space16) {
            templateHeader
            templatePreview
            templateActions
        }
        .padding(DS.space20)
    }

    private var templateHeader: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if let arc = outline.arcShape {
                Text("Arc: \(arc)")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
            } else {
                Text("Auto-generated Template")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
            }
            Text("\(outline.slides.count) slides generated")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var templatePreview: some View {
        ScrollView {
            LazyVStack(spacing: DS.space8) {
                ForEach(outline.slides) { slide in
                    templateSlideRow(slide)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func templateSlideRow(_ slide: CodexOutlineSlide) -> some View {
        HStack(spacing: DS.space8) {
            Text("\(slide.position)")
                .font(DS.caption)
                .foregroundStyle(DS.textOnAccent)
                .frame(width: 24, height: 24)
                .background(DS.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                if let act = slide.speechAct {
                    CodexConceptTag(name: act, color: CodexElementCategory.speechAct.color)
                }
                if let note = slide.note, !note.isEmpty {
                    Text(note)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
            Spacer()
        }
        .padding(DS.space8)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private var templateActions: some View {
        HStack(spacing: DS.space12) {
            Button {
                withAnimation(ProMotionSprings.snappy) { currentStep = .browse }
            } label: {
                Text("Customize")
                    .font(DS.callout)
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space8)
                    .background(DS.accent.opacity(DS.opacitySubtle), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(ProMotionSprings.snappy) { currentStep = .compose }
            } label: {
                Text("Accept & Compose")
                    .font(DS.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space8)
                    .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Step 3: Browse

extension OutlineComposerView {
    private var browseStep: some View {
        HStack(spacing: 0) {
            browseOutlinePreview
            Divider().background(DS.border)
            browseBlueprintPlaceholder
        }
    }

    private var browseOutlinePreview: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Outline Preview")
                .font(DS.title3)
                .foregroundStyle(DS.text)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space6) {
                    ForEach(outline.slides) { slide in
                        browseSlideRow(slide)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity)
    }

    private func browseSlideRow(_ slide: CodexOutlineSlide) -> some View {
        HStack(spacing: DS.space6) {
            Text("S\(slide.position)")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, alignment: .trailing)
            if let act = slide.speechAct {
                CodexConceptTag(name: act, color: CodexElementCategory.speechAct.color)
            }
            if let note = slide.note, !note.isEmpty {
                Text(note)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var browseBlueprintPlaceholder: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(DS.textMuted)
            Text("Blueprint reference will appear here")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Button {
                withAnimation(ProMotionSprings.snappy) { currentStep = .compose }
            } label: {
                Text("Start Composing")
                    .font(DS.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space8)
                    .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, DS.space20)
        }
        .frame(maxWidth: .infinity)
        .background(DS.surface)
    }
}

// MARK: - Step 4: Compose

extension OutlineComposerView {
    private var composeStep: some View {
        HStack(spacing: 0) {
            composeSlideList
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            Divider().background(DS.border)
            CodexElementBrowser()
                .frame(width: 340)
        }
    }

    private var composeSlideList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: DS.space12) {
                    ForEach($outline.slides) { $slide in
                        OutlineSlideEditor(slide: $slide) {
                            withAnimation(ProMotionSprings.snappy) {
                                outline.slides.removeAll { $0.id == slide.id }
                                reindexSlides()
                            }
                        }
                    }
                }
                .padding(DS.space16)
            }
            .scrollIndicators(.hidden)
            composeBottomBar
        }
    }

    private var composeBottomBar: some View {
        HStack {
            Button {
                withAnimation(ProMotionSprings.bouncy) {
                    let newSlide = CodexOutlineSlide(
                        id: UUID(),
                        position: outline.slides.count + 1,
                        speechAct: nil,
                        readerDeltas: [],
                        frame: nil,
                        distance: nil,
                        techniques: [],
                        transition: nil,
                        note: nil
                    )
                    outline.slides.append(newSlide)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add Slide")
                        .font(DS.callout)
                }
                .foregroundStyle(DS.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(ProMotionSprings.snappy) { currentStep = .review }
            } label: {
                Text("Review")
                    .font(DS.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space6)
                    .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .background(DS.surface)
    }
}

// MARK: - Step 5: Review

extension OutlineComposerView {
    private var reviewStep: some View {
        ScrollView {
            LazyVStack(spacing: DS.space12) {
                ForEach(outline.slides) { slide in
                    reviewSlideCard(slide)
                }
            }
            .padding(DS.space20)
        }
        .scrollIndicators(.hidden)
    }

    private func reviewSlideCard(_ slide: CodexOutlineSlide) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            reviewSlideHeader(slide)
            reviewSlideElements(slide)
            if let note = slide.note, !note.isEmpty {
                Text(note)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .italic()
            }
        }
        .padding(DS.space12)
        .dsCard()
    }

    private func reviewSlideHeader(_ slide: CodexOutlineSlide) -> some View {
        HStack {
            Text("Slide \(slide.position)")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            if let act = slide.speechAct {
                CodexConceptTag(name: act, color: CodexElementCategory.speechAct.color)
            }
            Spacer()
        }
    }

    private func reviewSlideElements(_ slide: CodexOutlineSlide) -> some View {
        FlowLayout(spacing: DS.space4) {
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
            if let trans = slide.transition {
                CodexConceptTag(name: trans, color: CodexElementCategory.transition.color)
            }
        }
    }
}

// MARK: - Template Generation

extension OutlineComposerView {
    private func generateTemplate(for arc: CodexElement) -> [CodexOutlineSlide] {
        generateDefaultTemplate()
    }

    private func generateDefaultTemplate() -> [CodexOutlineSlide] {
        let roles: [(Int, String?, String?)] = [
            (1, nil, "Hook / pattern interrupt"),
            (2, nil, "Setup / context"),
            (3, nil, "Development"),
            (4, nil, "Development"),
            (5, nil, "Detail / proof"),
            (6, nil, "Detail / proof"),
            (7, nil, "Detail / proof"),
            (8, nil, "Detail / proof"),
            (9, nil, "Pivot / payoff"),
            (10, nil, "Pivot / payoff"),
            (11, nil, "Resolution"),
            (12, nil, "Resolution / CTA"),
            (13, nil, "CTA"),
        ]
        return roles.map { pos, act, note in
            CodexOutlineSlide(
                id: UUID(),
                position: pos,
                speechAct: act,
                readerDeltas: [],
                frame: nil,
                distance: nil,
                techniques: [],
                transition: nil,
                note: note
            )
        }
    }

    private func reindexSlides() {
        for i in outline.slides.indices {
            outline.slides[i].position = i + 1
        }
    }
}

// MARK: - Flow Layout Helper

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
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
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }
        return (offsets, CGSize(width: maxX, height: currentY + lineHeight))
    }
}
