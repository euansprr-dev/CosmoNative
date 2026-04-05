// CosmoOS/UI/FocusMode/Ideas/BlueprintDisplayView.swift
// Displays a blueprint/swipe atom in text or physics mode.

import SwiftUI

struct BlueprintDisplayView: View {
    let blueprintAtom: Atom
    @Binding var displayMode: BlueprintDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            BlueprintPhysicsToggle(mode: $displayMode)

            switch displayMode {
            case .text:
                textModeContent
            case .physics:
                physicsModeContent
            }
        }
    }

    // MARK: - Text Mode

    @ViewBuilder
    private var textModeContent: some View {
        let walkthrough = blueprintAtom.blueprintWalkthrough
        let body = blueprintAtom.body

        if let text = walkthrough ?? body, !text.isEmpty {
            slideList(from: text)
        } else {
            emptyTextState
        }
    }

    @ViewBuilder
    private func slideList(from text: String) -> some View {
        let slides = parseSlides(from: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                slideRow(number: index + 1, text: slide)
            }
        }
    }

    @ViewBuilder
    private func slideRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(DS.caption)
                .foregroundStyle(DS.accent)
                .frame(width: 22, height: 22)
                .background(DS.accent.opacity(0.12), in: Circle())

            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
    }

    private var emptyTextState: some View {
        Text("No walkthrough text available")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.glassSectionFill, in: .rect(cornerRadius: 8))
    }

    // MARK: - Physics Mode

    @ViewBuilder
    private var physicsModeContent: some View {
        if let profile = blueprintAtom.bestPhysicsProfile,
           let quarks = profile.slideQuarks, !quarks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(quarks) { quark in
                    slideQuarkCard(quark)
                }
            }
        } else {
            emptyPhysicsState
        }
    }

    @ViewBuilder
    private func slideQuarkCard(_ quark: SlideQuark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            slideQuarkHeader(quark)
            slideQuarkTags(quark)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
    }

    @ViewBuilder
    private func slideQuarkHeader(_ quark: SlideQuark) -> some View {
        HStack(spacing: 8) {
            Text("Slide \(quark.slideNumber)")
                .font(DS.caption)
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.accent.opacity(0.12), in: Capsule())

            if let speechAct = quark.speechAct.type, !speechAct.isEmpty {
                CodexConceptTag(name: speechAct, color: DS.green)
            }
        }
    }

    @ViewBuilder
    private func slideQuarkTags(_ quark: SlideQuark) -> some View {
        FlowLayout(spacing: 4) {
            // Reader deltas
            if let deltas = quark.readerDeltas {
                ForEach(Array(deltas.enumerated()), id: \.offset) { _, delta in
                    if let type = delta.type, !type.isEmpty {
                        CodexConceptTag(name: type, color: DS.orange)
                    }
                }
            }

            // Frame
            if let frame = quark.frame?.type, !frame.isEmpty {
                CodexConceptTag(name: frame, color: DS.accent)
            }

            // Experiential distance
            if let distance = quark.experientialDistance?.type, !distance.isEmpty {
                CodexConceptTag(name: distance, color: DS.accent)
            }

            // Techniques
            if let techniques = quark.techniques {
                ForEach(Array(techniques.enumerated()), id: \.offset) { _, tech in
                    CodexConceptTag(name: tech.technique, color: DS.textSecondary)
                }
            }
        }
    }

    private var emptyPhysicsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "atom")
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
            Text("Physics extraction not available")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(DS.glassSectionFill, in: .rect(cornerRadius: 8))
    }

    // MARK: - Flow Layout

    private struct FlowLayout: Layout {
        var spacing: CGFloat = 4

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let result = computeLayout(proposal: proposal, subviews: subviews)
            return result.size
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let result = computeLayout(proposal: proposal, subviews: subviews)
            for (index, position) in result.positions.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                    proposal: .unspecified
                )
            }
        }

        private struct LayoutResult {
            var size: CGSize
            var positions: [CGPoint]
        }

        private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
            let maxWidth = proposal.width ?? .infinity
            var positions: [CGPoint] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var totalHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                totalHeight = y + rowHeight
            }

            return LayoutResult(
                size: CGSize(width: maxWidth, height: totalHeight),
                positions: positions
            )
        }
    }

    // MARK: - Helpers

    /// Parse text into slides by splitting on common markers (numbered lines, "---", double newlines).
    private func parseSlides(from text: String) -> [String] {
        // Try splitting on slide markers like "Slide 1:", "[1]", or numbered lines "1."
        let lines = text.components(separatedBy: "\n")
        var slides: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    slides.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
                continue
            }
            // Check for slide marker patterns
            let isMarker = trimmed.hasPrefix("---")
                || trimmed.range(of: #"^(Slide\s+)?\d+[\.\):\]]"#, options: .regularExpression) != nil
            if isMarker && !current.isEmpty {
                slides.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = trimmed
            } else {
                if !current.isEmpty { current += "\n" }
                current += trimmed
            }
        }
        if !current.isEmpty {
            slides.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // If parsing produced only 1 slide, the text likely has no markers — return it as-is
        return slides.isEmpty ? [text] : slides
    }
}
