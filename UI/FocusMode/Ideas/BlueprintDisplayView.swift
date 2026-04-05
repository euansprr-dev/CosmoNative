// CosmoOS/UI/FocusMode/Ideas/BlueprintDisplayView.swift
// Displays a blueprint/swipe atom — slide text with physics breakdown.
// Premium redesign — April 2026

import SwiftUI

struct BlueprintDisplayView: View {
    let blueprintAtom: Atom
    @Binding var displayMode: BlueprintDisplayMode

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            blueprintTitle
            BlueprintPhysicsToggle(mode: $displayMode)
            slideContent
        }
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance) {
                appeared = true
            }
        }
    }

    // MARK: - Title

    @ViewBuilder
    private var blueprintTitle: some View {
        if let title = blueprintAtom.title, !title.isEmpty {
            Text(title)
                .font(DS.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DS.text)
                .lineLimit(2)
        }
    }

    // MARK: - Slide Content

    @ViewBuilder
    private var slideContent: some View {
        if let profile = blueprintAtom.bestPhysicsProfile,
           let quarks = profile.slideQuarks, !quarks.isEmpty {
            quarksSlideList(quarks)
        } else {
            fallbackTextContent
        }
    }

    // MARK: - Quarks-Based Slides (Primary)

    private func quarksSlideList(_ quarks: [SlideQuark]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(quarks.enumerated()), id: \.element.id) { index, quark in
                quarkSlideCard(quark, index: index)
            }
        }
    }

    private func quarkSlideCard(_ quark: SlideQuark, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            quarkSlideHeader(quark)
            quarkSlideText(quark)
            if displayMode == .physics {
                quarkPhysicsTags(quark)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(alignment: .leading) {
            slideAccentBar(quark)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(ProMotionSprings.staggered(index: index), value: appeared)
    }

    private func quarkSlideHeader(_ quark: SlideQuark) -> some View {
        HStack(spacing: 6) {
            slideNumberBadge(quark.slideNumber)
            if let speechAct = quark.speechAct.type, !speechAct.isEmpty {
                CodexConceptTag(name: speechAct, color: CodexElementCategory.speechAct.color)
            }
        }
    }

    @ViewBuilder
    private func quarkSlideText(_ quark: SlideQuark) -> some View {
        if let text = quark.text, !text.isEmpty {
            Text(cleanSlideText(text))
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Physics Tags (shown in physics mode)

    private func quarkPhysicsTags(_ quark: SlideQuark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            physicsTagsDivider
            readerDeltaTags(quark)
            frameTags(quark)
            techniqueTags(quark)
            proofMotivationTags(quark)
        }
    }

    private var physicsTagsDivider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 0.5)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func readerDeltaTags(_ quark: SlideQuark) -> some View {
        if let deltas = quark.readerDeltas, !deltas.isEmpty {
            CodexFlowLayout(spacing: 4) {
                ForEach(Array(deltas.enumerated()), id: \.offset) { _, delta in
                    if let type = delta.type, !type.isEmpty {
                        CodexConceptTag(name: type, color: CodexElementCategory.readerDelta.color)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func frameTags(_ quark: SlideQuark) -> some View {
        CodexFlowLayout(spacing: 4) {
            if let frame = quark.frame?.type, !frame.isEmpty {
                CodexConceptTag(name: frame, color: CodexElementCategory.frame.color)
            }
            if let distance = quark.experientialDistance?.type, !distance.isEmpty {
                CodexConceptTag(name: distance, color: CodexElementCategory.distance.color)
            }
        }
    }

    @ViewBuilder
    private func techniqueTags(_ quark: SlideQuark) -> some View {
        if let techniques = quark.techniques, !techniques.isEmpty {
            CodexFlowLayout(spacing: 4) {
                ForEach(Array(techniques.enumerated()), id: \.offset) { _, tech in
                    CodexConceptTag(name: tech.technique, color: CodexElementCategory.technique.color)
                }
            }
        }
    }

    @ViewBuilder
    private func proofMotivationTags(_ quark: SlideQuark) -> some View {
        let hasProof = quark.proofType?.type != nil
        let hasMotivation = quark.motivation?.type != nil
        if hasProof || hasMotivation {
            CodexFlowLayout(spacing: 4) {
                if let proof = quark.proofType?.type, !proof.isEmpty {
                    CodexConceptTag(name: proof, color: CodexElementCategory.proofType.color)
                }
                if let motivation = quark.motivation?.type, !motivation.isEmpty {
                    CodexConceptTag(name: motivation, color: CodexElementCategory.motivation.color)
                }
            }
        }
    }

    // MARK: - Accent Bar

    private func slideAccentBar(_ quark: SlideQuark) -> some View {
        let color = categoryColorForSpeechAct(quark.speechAct.type)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.4))
            .frame(width: 2)
            .padding(.vertical, 6)
            .padding(.leading, 1)
    }

    private func categoryColorForSpeechAct(_ type: String?) -> Color {
        guard let type = type, !type.isEmpty else { return DS.entityIdea }
        return CodexElementCategory.speechAct.color
    }

    // MARK: - Slide Number Badge

    private func slideNumberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(DS.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(DS.entityIdea, in: Circle())
    }

    // MARK: - Fallback (no physics profile)

    @ViewBuilder
    private var fallbackTextContent: some View {
        let walkthrough = blueprintAtom.blueprintWalkthrough
        let body = blueprintAtom.body

        if let text = walkthrough ?? body, !text.isEmpty {
            fallbackSlideList(from: text)
        } else {
            emptyState
        }
    }

    private func fallbackSlideList(from text: String) -> some View {
        let slides = parseSlidesFromWalkthrough(text)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                fallbackSlideRow(number: index + 1, text: slide, index: index)
            }
        }
    }

    private func fallbackSlideRow(number: Int, text: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            slideNumberBadge(number)
            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DS.entityIdea.opacity(0.3))
                .frame(width: 2)
                .padding(.vertical, 6)
                .padding(.leading, 1)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(ProMotionSprings.staggered(index: index), value: appeared)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(DS.title2)
                .foregroundStyle(DS.entityIdea.opacity(0.3))
                .accessibilityHidden(true)
            Text("No slide data available")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(DS.entityIdea.opacity(0.02), in: .rect(cornerRadius: 8))
    }

    // MARK: - Text Cleaning

    private func cleanSlideText(_ text: String) -> String {
        var cleaned = text
        // Remove markdown bold markers
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        // Replace literal \n with actual newlines
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")
        // Remove "Slide N:" prefix if present
        if let range = cleaned.range(of: #"^Slide\s+\d+:\s*"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Remove surrounding quotes
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Walkthrough Text Parser (fallback)

    private func parseSlidesFromWalkthrough(_ text: String) -> [String] {
        // Try to extract actual slide content blocks
        var slides: [String] = []
        let pattern = #"\*\*Slide\s+\d+:.*?\*\*"#
        let lines = text.components(separatedBy: "\n")
        var current = ""
        var inSlide = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Detect slide markers
            if trimmed.range(of: #"^\*?\*?Slide\s+\d+"#, options: .regularExpression) != nil {
                if !current.isEmpty && inSlide {
                    slides.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                current = trimmed
                inSlide = true
            } else if inSlide {
                // Stop collecting when we hit metadata sections
                if trimmed.hasPrefix("Speech act:") || trimmed.hasPrefix("Reader deltas:")
                    || trimmed.hasPrefix("Frame:") || trimmed.hasPrefix("Distance:")
                    || trimmed.hasPrefix("Techniques active:") || trimmed.hasPrefix("Why this slide works:")
                    || trimmed.hasPrefix("---") || trimmed.hasPrefix("##") {
                    if !current.isEmpty {
                        slides.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                        current = ""
                    }
                    inSlide = false
                } else if !trimmed.isEmpty {
                    current += "\n" + trimmed
                }
            }
        }
        if !current.isEmpty && inSlide {
            slides.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // If no slide markers found, fall back to paragraph splitting
        if slides.isEmpty {
            return simpleParagraphSplit(text)
        }

        return slides.map { cleanSlideText($0) }
    }

    private func simpleParagraphSplit(_ text: String) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 10 }
            .filter { !$0.hasPrefix("---") && !$0.hasPrefix("##") && !$0.hasPrefix("WALKTHROUGH") }
        return paragraphs.isEmpty ? [text] : paragraphs
    }
}
