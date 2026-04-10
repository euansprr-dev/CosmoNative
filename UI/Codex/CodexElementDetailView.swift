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
                operationalRecipeSection
                generationRecipeSection
                formatConstraintsSection
                applicationRulesSection
                antiPatternsSection
                antiExampleFixSection
                readerEffectSection
                whereActiveSection
                whyItWorksSection
                reelExamplesSection
                carouselExamplesSection
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
            AkashicSectionHeader(title: "DEFINITION")
            AkashicCallout(text: element.definition, tintColor: categoryColor)
        }
    }

    private var definitionCallout: some View {
        AkashicCallout(text: element.definition, tintColor: categoryColor)
    }

    // MARK: - Application Rules

    @ViewBuilder
    private var applicationRulesSection: some View {
        if !element.applicationRules.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                AkashicSectionHeader(title: "APPLICATION RULES")
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
            .foregroundStyle(DS.gilt)
            .frame(width: 22, height: 22)
            .background(DS.giltSoft, in: Circle())
    }

    // MARK: - Anti-Patterns

    @ViewBuilder
    private var antiPatternsSection: some View {
        if !element.antiPatterns.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                AkashicSectionHeader(title: "ANTI-PATTERNS")
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
                AkashicSectionHeader(title: "READER EFFECT")
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
                AkashicSectionHeader(title: "WHERE ACTIVE")
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
                AkashicSectionHeader(title: "WHY IT WORKS")
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
                    AkashicSectionHeader(title: "EXAMPLES")
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
                AkashicSectionHeader(title: "PATTERNS")
                ForEach(element.patterns, id: \.self) { pattern in
                    HStack(alignment: .top, spacing: DS.space8) {
                        Rectangle()
                            .fill(DS.gilt.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .rotationEffect(.degrees(45))
                            .padding(.top, 7)
                        Text(pattern)
                            .font(DS.callout)
                            .foregroundStyle(DS.inkWash)
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
                AkashicSectionHeader(title: "VARIANTS")
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
            .foregroundStyle(DS.inkFaded)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(DS.vellumDeep, in: .rect(cornerRadius: DS.radiusXSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusXSmall)
                    .stroke(DS.sepiaSubtle, lineWidth: 0.5)
            )
    }

    // MARK: - Linked Walkthroughs

    @ViewBuilder
    private var linkedWalkthroughsSection: some View {
        if !linkedWalkthroughs.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                sectionDivider
                AkashicSectionHeader(title: "LINKED WALKTHROUGHS")
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
            giltDiamondOrnament
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.walkthrough.postTitle)
                    .font(DS.callout)
                    .fontDesign(.serif)
                    .foregroundStyle(DS.inkWash)
                walkthroughSubtitle(entry)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(DS.giltMuted)
                .accessibilityHidden(true)
        }
        .padding(DS.space12)
        .dsVellumCard(cornerRadius: DS.radiusMedium)
        .codexHover(accent: categoryColor)
    }

    private var giltDiamondOrnament: some View {
        Rectangle()
            .fill(DS.gilt)
            .frame(width: 6, height: 6)
            .rotationEffect(.degrees(45))
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

    // MARK: - Operational Recipe

    @ViewBuilder
    private var operationalRecipeSection: some View {
        if let recipe = element.operationalRecipe, !recipe.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                AkashicSectionHeader(title: "OPERATIONAL RECIPE")
                AkashicCallout(text: recipe, tintColor: DS.gilt)
            }
        }
    }

    // MARK: - Generation Recipe

    @ViewBuilder
    private var generationRecipeSection: some View {
        if let recipe = element.generationRecipe {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                AkashicSectionHeader(title: "GENERATION RECIPE")
                generationSteps(recipe.steps)
                generationMistakes(recipe.commonMistakes)
            }
        }
    }

    @ViewBuilder
    private func generationSteps(_ steps: [String]) -> some View {
        if !steps.isEmpty {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                applicationRuleRow(index: idx, rule: step)
            }
        }
    }

    @ViewBuilder
    private func generationMistakes(_ mistakes: [String]) -> some View {
        if !mistakes.isEmpty {
            VStack(alignment: .leading, spacing: DS.space4) {
                Text("COMMON MISTAKES")
                    .font(DS.caption)
                    .tracking(0.8)
                    .foregroundStyle(DS.red.opacity(0.7))
                    .padding(.top, DS.space4)
                ForEach(mistakes, id: \.self) { mistake in
                    antiPatternRow(pattern: mistake)
                }
            }
        }
    }

    // MARK: - Format Constraints

    @ViewBuilder
    private var formatConstraintsSection: some View {
        if let constraints = element.formatConstraints {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                AkashicSectionHeader(title: "FORMAT CONSTRAINTS")
                formatConstraintCard(
                    icon: "play.rectangle.fill",
                    label: "REEL",
                    text: constraints.reel
                )
                formatConstraintCard(
                    icon: "rectangle.stack.fill",
                    label: "CAROUSEL",
                    text: constraints.carousel
                )
            }
        }
    }

    private func formatConstraintCard(icon: String, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(categoryColor)
                .frame(width: 22, height: 22)
                .background(categoryColor.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.caption)
                    .tracking(0.8)
                    .foregroundStyle(categoryColor)
                Text(text)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineSpacing(3)
            }
        }
        .padding(DS.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsVellumCard(cornerRadius: DS.radiusSmall)
    }

    // MARK: - Anti-Example with Fix

    @ViewBuilder
    private var antiExampleFixSection: some View {
        if let fix = element.antiExampleFix {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionDivider
                AkashicSectionHeader(title: "ANTI-EXAMPLE")
                antiExampleComparison(fix)
            }
        }
    }

    private func antiExampleComparison(_ fix: CodexAntiExampleFix) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            antiExampleHalf(
                icon: "xmark.circle",
                label: "BAD",
                text: fix.bad,
                explanation: fix.whyItFails,
                explanationLabel: "WHY IT FAILS",
                tint: DS.red
            )
            GiltHairline()
                .padding(.horizontal, DS.space16)
            antiExampleHalf(
                icon: "checkmark.circle",
                label: "FIXED",
                text: fix.fixed,
                explanation: fix.whyTheFixWorks,
                explanationLabel: "WHY THE FIX WORKS",
                tint: DS.green
            )
        }
        .dsVellumCard(cornerRadius: DS.radiusMedium)
    }

    private func antiExampleHalf(
        icon: String,
        label: String,
        text: String,
        explanation: String,
        explanationLabel: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(label)
                    .font(DS.caption)
                    .tracking(0.8)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkWash)
                .lineSpacing(4)
            Text(explanationLabel)
                .font(DS.caption2)
                .tracking(0.6)
                .foregroundStyle(DS.giltMuted)
            Text(explanation)
                .font(DS.caption)
                .foregroundStyle(DS.inkFaded)
                .lineSpacing(2)
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.03))
    }

    // MARK: - Format-Stratified Examples

    @ViewBuilder
    private var reelExamplesSection: some View {
        if let reelExamples = element.reelExamples, !reelExamples.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                sectionDivider
                HStack {
                    AkashicSectionHeader(title: "REEL EXAMPLES")
                    Spacer()
                    Text("\(reelExamples.count)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                ForEach(Array(reelExamples.prefix(15).enumerated()), id: \.offset) { idx, example in
                    CodexExampleCardView(example: example, categoryColor: categoryColor, index: idx)
                }
            }
        }
    }

    @ViewBuilder
    private var carouselExamplesSection: some View {
        if let carouselExamples = element.carouselExamples, !carouselExamples.isEmpty {
            VStack(alignment: .leading, spacing: DS.space12) {
                sectionDivider
                HStack {
                    AkashicSectionHeader(title: "CAROUSEL EXAMPLES")
                    Spacer()
                    Text("\(carouselExamples.count)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                ForEach(Array(carouselExamples.prefix(15).enumerated()), id: \.offset) { idx, example in
                    CodexExampleCardView(example: example, categoryColor: categoryColor, index: idx)
                }
            }
        }
    }

    // MARK: - No Deep Data Fallback

    private var hasDeepData: Bool {
        !element.examples.isEmpty || !element.applicationRules.isEmpty || !element.antiPatterns.isEmpty
        || element.operationalRecipe != nil || element.generationRecipe != nil
        || !(element.reelExamples ?? []).isEmpty || !(element.carouselExamples ?? []).isEmpty
    }

    @ViewBuilder
    private var noDeepDataSection: some View {
        if !hasDeepData {
            VStack(alignment: .leading, spacing: DS.space8) {
                definitionCallout
                Text("This element is defined in the Periodic Table. Detailed analysis with examples is available for elements that appear in the Deep Entries section of the Codex.")
                    .font(DS.caption)
                    .foregroundStyle(DS.inkFaded)
                    .italic()
                    .padding(.top, DS.space8)
            }
        }
    }

    // MARK: - Reusable Components

    private func accentCallout(text: String, color: Color) -> some View {
        AkashicCallout(text: text, tintColor: color, font: DS.callout)
    }

    private var sectionDivider: some View {
        AkashicSectionDivider()
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
