// CosmoOS/UI/Codex/CodexElementDetailView.swift
// Full element entry detail — definition, rules, anti-patterns, examples, linked walkthroughs.
// April 2026 — WP3 Codex Navigation

import SwiftUI

struct CodexElementDetailView: View {
    let atom: Atom
    let element: CodexElement

    @State private var linkedWalkthroughs: [CodexWalkthroughEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                headerSection
                if hasDeepData {
                    definitionSection
                    applicationRulesSection
                    antiPatternsSection
                    readerEffectSection
                    whereActiveSection
                    whyItWorksSection
                    examplesSection
                    patternsSection
                    variantsSection
                } else {
                    noDeepDataSection
                    variantsSection
                }
                linkedWalkthroughsSection
            }
            .padding(DS.space32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(DS.bg)
        .task { await loadLinkedWalkthroughs() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(element.canonicalName)
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)

            HStack(spacing: DS.space8) {
                categoryBadge
                frequencyBadge
            }
        }
    }

    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: element.category.icon)
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(element.category.displayName)
                .font(DS.caption)
        }
        .foregroundStyle(element.category.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(element.category.color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var frequencyBadge: some View {
        if let freq = element.frequency {
            Text(freq)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DS.surface, in: Capsule())
        }
    }

    // MARK: - Definition

    private var definitionSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("DEFINITION")
                .dsSectionLabel()
            Text(element.definition)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Application Rules

    @ViewBuilder
    private var applicationRulesSection: some View {
        if !element.applicationRules.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("APPLICATION RULES")
                    .dsSectionLabel()

                ForEach(Array(element.applicationRules.enumerated()), id: \.offset) { idx, rule in
                    applicationRuleRow(index: idx, rule: rule)
                }
            }
        }
    }

    private func applicationRuleRow(index: Int, rule: String) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Text("\(index + 1).")
                .font(DS.callout)
                .fontWeight(.semibold)
                .foregroundStyle(DS.green)
                .frame(width: 20, alignment: .trailing)
            Text(rule)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
        }
    }

    // MARK: - Anti-Patterns

    @ViewBuilder
    private var antiPatternsSection: some View {
        if !element.antiPatterns.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("ANTI-PATTERNS")
                    .dsSectionLabel()

                ForEach(Array(element.antiPatterns.enumerated()), id: \.offset) { idx, ap in
                    antiPatternRow(index: idx, pattern: ap)
                }
            }
        }
    }

    private func antiPatternRow(index: Int, pattern: String) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(DS.red)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(pattern)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
        }
    }

    // MARK: - Reader Effect

    @ViewBuilder
    private var readerEffectSection: some View {
        if let effect = element.readerEffect, !effect.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("READER EFFECT")
                    .dsSectionLabel()
                calloutCard(text: effect, accentColor: DS.accent)
            }
        }
    }

    // MARK: - Where Active

    @ViewBuilder
    private var whereActiveSection: some View {
        if !element.whereActive.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("WHERE ACTIVE")
                    .dsSectionLabel()
                calloutCard(text: element.whereActive.joined(separator: ", "), accentColor: DS.green)
            }
        }
    }

    // MARK: - Why It Works

    @ViewBuilder
    private var whyItWorksSection: some View {
        if let why = element.whyItWorks, !why.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("WHY IT WORKS")
                    .dsSectionLabel()
                calloutCard(text: why, accentColor: DS.accent)
            }
        }
    }

    // MARK: - Examples

    @ViewBuilder
    private var examplesSection: some View {
        if !element.examples.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                Text("EXAMPLES")
                    .dsSectionLabel()

                ForEach(Array(element.examples.prefix(15).enumerated()), id: \.offset) { _, example in
                    CodexExampleCard(example: example)
                }
            }
        }
    }

    // MARK: - Patterns

    @ViewBuilder
    private var patternsSection: some View {
        if !element.patterns.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("PATTERNS")
                    .dsSectionLabel()

                ForEach(element.patterns, id: \.self) { pattern in
                    HStack(alignment: .top, spacing: DS.space8) {
                        Circle()
                            .fill(DS.textMuted)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(pattern)
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                            .lineSpacing(3)
                    }
                }
            }
        }
    }

    // MARK: - Variants

    @ViewBuilder
    private var variantsSection: some View {
        if !element.variants.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text("VARIANTS")
                    .dsSectionLabel()

                FlowLayout(spacing: 6) {
                    ForEach(element.variants, id: \.self) { variant in
                        Text(variant)
                            .font(DS.caption)
                            .foregroundStyle(element.category.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                element.category.color.opacity(0.1),
                                in: Capsule()
                            )
                    }
                }
            }
        }
    }

    // MARK: - Linked Walkthroughs

    @ViewBuilder
    private var linkedWalkthroughsSection: some View {
        if !linkedWalkthroughs.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                Text("LINKED WALKTHROUGHS")
                    .dsSectionLabel()

                ForEach(linkedWalkthroughs) { entry in
                    NavigationLink(value: CodexRoute.walkthrough(entry)) {
                        linkedWalkthroughRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func linkedWalkthroughRow(_ entry: CodexWalkthroughEntry) -> some View {
        HStack(spacing: DS.space12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 14))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.walkthrough.postTitle)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                if let creator = entry.walkthrough.creatorName {
                    Text(creator)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
        }
        .padding(DS.space12)
        .dsCard()
    }

    // MARK: - No Deep Data Fallback

    private var hasDeepData: Bool {
        !element.examples.isEmpty || !element.applicationRules.isEmpty || !element.antiPatterns.isEmpty
    }

    @ViewBuilder
    private var noDeepDataSection: some View {
        if !hasDeepData {
            VStack(alignment: .leading, spacing: DS.space8) {
                Text(element.definition)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineSpacing(5)
                    .padding(DS.space16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))

                Text("This element is defined in the Periodic Table. Detailed analysis with examples is available for elements that appear in the Deep Entries section of the Codex.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .italic()
                    .padding(.top, DS.space8)
            }
        }
    }

    // MARK: - Callout Card

    private func calloutCard(text: String, accentColor: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .padding(DS.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
    }

    // MARK: - Data

    private func loadLinkedWalkthroughs() async {
        let links = atom.links(ofType: .codexElementToWalkthrough)
        guard !links.isEmpty else { return }

        let repo = CodexRepository.shared
        var results: [CodexWalkthroughEntry] = []
        for link in links {
            if let atomResult = try? await AtomRepository.shared.fetch(uuid: link.uuid),
               let wt = atomResult.codexWalkthroughData {
                results.append(CodexWalkthroughEntry(atom: atomResult, walkthrough: wt))
            }
        }
        linkedWalkthroughs = results
    }
}

// MARK: - Example Card

struct CodexExampleCard: View {
    let example: CodexExample

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(example.slideText)
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(DS.text)
                .lineSpacing(4)

            if !example.postReference.isEmpty {
                Text(example.postReference)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            if let mechanism = example.mechanism, !mechanism.isEmpty {
                Text(mechanism)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 0.5)
        )
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

