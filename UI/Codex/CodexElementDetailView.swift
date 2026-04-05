// CosmoOS/UI/Codex/CodexElementDetailView.swift
// Full element entry detail — definition, rules, anti-patterns, examples, linked walkthroughs.
// April 2026 — WP3 Codex Navigation + Premium Redesign

import SwiftUI

struct CodexElementDetailView: View {
    let atom: Atom
    let element: CodexElement

    @State private var linkedWalkthroughs: [CodexWalkthroughEntry] = []
    @State private var appeared = false

    private var categoryColor: Color { element.category.color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CodexElementHeroSection(element: element)
                CodexCategorySectionDivider(color: categoryColor)
                detailContent
            }
        }
        .scrollIndicators(.hidden)
        .background(DS.bg)
        .task { await loadLinkedWalkthroughs() }
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance.delay(0.15)) {
                appeared = true
            }
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
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
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    // MARK: - Definition

    private var definitionSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("DEFINITION")
                .dsSectionLabel()
            definitionCallout
        }
    }

    private var definitionCallout: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(categoryColor)
                .frame(width: 3)
            Text(element.definition)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(5)
                .padding(DS.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
    }

    // MARK: - Application Rules

    @ViewBuilder
    private var applicationRulesSection: some View {
        if !element.applicationRules.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
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
            ruleNumberBadge(index + 1)
            Text(rule)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
        }
    }

    private func ruleNumberBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(DS.caption)
            .fontWeight(.semibold)
            .foregroundStyle(DS.green)
            .frame(width: 22, height: 22)
            .background(DS.green.opacity(0.1), in: Circle())
    }

    // MARK: - Anti-Patterns

    @ViewBuilder
    private var antiPatternsSection: some View {
        if !element.antiPatterns.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                Text("ANTI-PATTERNS")
                    .dsSectionLabel()
                ForEach(Array(element.antiPatterns.enumerated()), id: \.offset) { _, ap in
                    antiPatternRow(pattern: ap)
                }
            }
        }
    }

    private func antiPatternRow(pattern: String) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(DS.red)
                .frame(width: 22, height: 22)
                .background(DS.red.opacity(0.08), in: Circle())
                .padding(.top, 1)
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
                sectionDivider
                Text("READER EFFECT")
                    .dsSectionLabel()
                accentCallout(text: effect, color: categoryColor)
            }
        }
    }

    // MARK: - Where Active

    @ViewBuilder
    private var whereActiveSection: some View {
        if !element.whereActive.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                sectionDivider
                Text("WHERE ACTIVE")
                    .dsSectionLabel()
                accentCallout(text: element.whereActive.joined(separator: ", "), color: DS.green)
            }
        }
    }

    // MARK: - Why It Works

    @ViewBuilder
    private var whyItWorksSection: some View {
        if let why = element.whyItWorks, !why.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                sectionDivider
                Text("WHY IT WORKS")
                    .dsSectionLabel()
                accentCallout(text: why, color: categoryColor)
            }
        }
    }

    // MARK: - Examples

    @ViewBuilder
    private var examplesSection: some View {
        if !element.examples.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                sectionDivider
                HStack {
                    Text("EXAMPLES")
                        .dsSectionLabel()
                    Spacer()
                    Text("\(element.examples.count) from viral posts")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                ForEach(Array(element.examples.prefix(15).enumerated()), id: \.offset) { idx, example in
                    CodexExampleCardView(example: example, categoryColor: categoryColor, index: idx)
                }
            }
        }
    }

    // MARK: - Patterns

    @ViewBuilder
    private var patternsSection: some View {
        if !element.patterns.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                Text("PATTERNS")
                    .dsSectionLabel()
                ForEach(element.patterns, id: \.self) { pattern in
                    HStack(alignment: .top, spacing: DS.space8) {
                        Circle()
                            .fill(categoryColor.opacity(0.5))
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
                sectionDivider
                Text("VARIANTS")
                    .dsSectionLabel()
                CodexFlowLayout(spacing: 6) {
                    ForEach(Array(element.variants.enumerated()), id: \.element) { idx, variant in
                        variantPill(variant, index: idx)
                    }
                }
            }
        }
    }

    private func variantPill(_ variant: String, index: Int) -> some View {
        Text(variant)
            .font(DS.caption)
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(categoryColor.opacity(0.1), in: Capsule())
    }

    // MARK: - Linked Walkthroughs

    @ViewBuilder
    private var linkedWalkthroughsSection: some View {
        if !linkedWalkthroughs.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                sectionDivider
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
                .foregroundStyle(categoryColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.walkthrough.postTitle)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                walkthroughSubtitle(entry)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
        }
        .padding(DS.space12)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor.opacity(0.3))
                .frame(width: 3)
                .padding(.vertical, 6)
                .padding(.leading, 1)
        }
        .codexHover(accent: categoryColor)
    }

    @ViewBuilder
    private func walkthroughSubtitle(_ entry: CodexWalkthroughEntry) -> some View {
        HStack(spacing: 6) {
            if let creator = entry.walkthrough.creatorName {
                Text(creator)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Text("\(entry.walkthrough.slides.count) slides")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - No Deep Data Fallback

    private var hasDeepData: Bool {
        !element.examples.isEmpty || !element.applicationRules.isEmpty || !element.antiPatterns.isEmpty
    }

    @ViewBuilder
    private var noDeepDataSection: some View {
        if !hasDeepData {
            VStack(alignment: .leading, spacing: DS.space8) {
                definitionCallout
                Text("This element is defined in the Periodic Table. Detailed analysis with examples is available for elements that appear in the Deep Entries section of the Codex.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .italic()
                    .padding(.top, DS.space8)
            }
        }
    }

    // MARK: - Reusable Components

    private func accentCallout(text: String, color: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .padding(DS.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(color.opacity(0.04), in: .rect(cornerRadius: DS.radiusSmall))
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(categoryColor.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, DS.space4)
    }

    // MARK: - Data

    private func loadLinkedWalkthroughs() async {
        let links = atom.links(ofType: .codexElementToWalkthrough)
        guard !links.isEmpty else { return }

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
