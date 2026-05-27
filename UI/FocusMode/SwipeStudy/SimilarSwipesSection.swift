// CosmoOS/UI/FocusMode/SwipeStudy/SimilarSwipesSection.swift
// Similar swipes section for Swipe Study Focus Mode
// February 2026

import SwiftUI

// MARK: - Similar Swipes Section

struct SimilarSwipesSection: View {
    let currentHookType: SwipeHookType?
    let currentFingerprint: StructuralFingerprint?
    let currentEntityId: Int64
    let onSwipeTap: (Int64) -> Void

    @State private var similarSwipes: [SimilarSwipeMatch] = []
    @State private var hasLoaded = false
    @State private var patternFormula: PatternFormula?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            FocusModeInspectorSection("PATTERNS") {
                patternsContent
            }

            FocusModeInspectorSection("RELATED") {
                relatedContent
            }
        }
        .onAppear { loadSimilarSwipes() }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var patternsContent: some View {
        if !hasLoaded {
            loadingLines
        } else if let formula = patternFormula {
            patternFormulaCard(formula)
        } else {
            subtleEmptyState(
                icon: "sparkles.rectangle.stack",
                text: "No repeatable formula yet"
            )
        }
    }

    @ViewBuilder
    private var relatedContent: some View {
        if !hasLoaded {
            loadingLines
        } else if similarSwipes.isEmpty {
            placeholderView
        } else {
            scrollContent
        }
    }

    private var loadingLines: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.sepiaSubtle)
                .frame(width: 180, height: 12)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.sepiaSubtle.opacity(0.7))
                .frame(width: 124, height: 12)
        }
        .padding(.vertical, DS.space6)
        .redacted(reason: .placeholder)
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space10) {
                ForEach(similarSwipes) { match in
                    Button {
                        onSwipeTap(match.item.entityId)
                    } label: {
                        similarCard(match)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Similar Card

    private func similarCard(_ match: SimilarSwipeMatch) -> some View {
        let item = match.item
        return VStack(alignment: .leading, spacing: DS.space8) {
            thumbnailWell(item: item)

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .frame(width: 148, height: 32, alignment: .topLeading)

            HStack(spacing: 6) {
                if let hookType = item.hookType {
                    miniPill(hookType.displayName, color: hookType.color)
                }

                Spacer()

                if let similarity = match.similarity {
                    scoreChip("\(Int(similarity * 100))%", color: similarityColor(similarity))
                } else if let score = item.hookScore {
                    scoreChip(String(format: "%.1f", score), color: item.scoreColor)
                }
            }
            .frame(width: 148)
        }
        .frame(width: 164, height: 136)
        .contentShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func thumbnailWell(item: SwipeGalleryItem) -> some View {
        ZStack {
            if let thumbUrl = item.thumbnailUrl, let url = URL(string: thumbUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        cardPlaceholder
                    }
                }
            } else {
                cardPlaceholder
            }
        }
        .frame(width: 148, height: 58)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.55), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 6, x: 0, y: 3)
    }

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(DS.glassCardFill.opacity(0.48))
            .overlay(
                Image(systemName: "doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.inkFaded)
            )
    }

    private func miniPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func scoreChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DS.glassCardFill.opacity(0.5), in: Capsule())
    }

    private func similarityColor(_ similarity: Double) -> Color {
        if similarity >= 0.8 { return DS.green }
        if similarity >= 0.5 { return DS.info }
        return DS.textMuted
    }

    // MARK: - Pattern Formula Card

    private func patternFormulaCard(_ formula: PatternFormula) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.entitySwipe)
                Text("Your Winning Formula")
                    .font(DS.smallCaps)
                    .foregroundStyle(DS.entitySwipe)
            }

            HStack(spacing: 6) {
                if let hookType = formula.hookType {
                    formulaPill(hookType.displayName, color: hookType.color)
                }

                if formula.hookType != nil && formula.frameworkType != nil {
                    formulaPlus
                }

                if let frameworkType = formula.frameworkType {
                    formulaPill(frameworkType.abbreviation, color: frameworkType.color)
                }

                if formula.topTechnique != nil && (formula.hookType != nil || formula.frameworkType != nil) {
                    formulaPlus
                }

                if let technique = formula.topTechnique {
                    formulaPill(technique.displayName, color: technique.color)
                }
            }

            HStack(spacing: 4) {
                Text("Found in \(formula.matchCount) swipes")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textSecondary)

                if formula.avgScore > 0 {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                    Text("Avg score \(String(format: "%.1f", formula.avgScore))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
        .padding(.vertical, DS.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formulaPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.16), lineWidth: 0.5))
    }

    private var formulaPlus: some View {
        Text("+")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(DS.inkFaded)
    }

    // MARK: - Data Loading

    private func loadSimilarSwipes() {
        guard !hasLoaded else { return }
        Task {
            defer { hasLoaded = true }

            do {
                let allResearch = try await AtomRepository.shared.fetch(
                    type: .research,
                    where: { atom in
                        atom.isSwipeFileAtom && (atom.id ?? -1) != currentEntityId
                    }
                )

                let allItems = allResearch.compactMap { atom -> (SwipeGalleryItem, StructuralFingerprint?)? in
                    guard let item = atom.toSwipeGalleryItem() else { return nil }
                    let fp = atom.swipeAnalysis?.fingerprint
                    return (item, fp)
                }

                // If we have a fingerprint, use cosine similarity
                if let fp = currentFingerprint {
                    let scored = allItems.compactMap { (item, otherFP) -> SimilarSwipeMatch? in
                        guard let otherFP = otherFP else {
                            // Fallback: if no fingerprint, check hookType match
                            if item.hookType == currentHookType {
                                return SimilarSwipeMatch(item: item, similarity: nil)
                            }
                            return nil
                        }
                        let sim = fp.similarity(to: otherFP)
                        // Only show if similarity is meaningful (> 0.3)
                        guard sim > 0.3 else { return nil }
                        return SimilarSwipeMatch(item: item, similarity: sim)
                    }
                    .sorted { ($0.similarity ?? 0) > ($1.similarity ?? 0) }
                    .prefix(6)

                    similarSwipes = Array(scored)

                    // Detect pattern formula: 3+ swipes above 0.8 similarity
                    let highMatches = similarSwipes.filter { ($0.similarity ?? 0) >= 0.8 }
                    if highMatches.count >= 3 {
                        // Find the most common hook type among high matches
                        let hookTypes = highMatches.compactMap(\.item.hookType)
                        let hookCounts = Dictionary(hookTypes.map { ($0, 1) }, uniquingKeysWith: +)
                        let topHook = hookCounts.max(by: { $0.value < $1.value })?.key

                        // Find the most common framework among high matches
                        let frameworks = highMatches.compactMap(\.item.frameworkType)
                        let frameworkCounts = Dictionary(frameworks.map { ($0, 1) }, uniquingKeysWith: +)
                        let topFramework = frameworkCounts.max(by: { $0.value < $1.value })?.key

                        // Compute average hook score from high matches
                        let scores = highMatches.compactMap(\.item.hookScore)
                        let avgScore = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)

                        // Only create formula if at least one component was found
                        if topHook != nil || topFramework != nil {
                            patternFormula = PatternFormula(
                                hookType: topHook,
                                frameworkType: topFramework,
                                topTechnique: nil,
                                matchCount: highMatches.count,
                                avgScore: avgScore
                            )
                        }
                    }
                } else {
                    // Fallback: hookType-only matching (no fingerprint available)
                    guard let hookType = currentHookType else { return }
                    let matching = allItems
                        .filter { $0.0.hookType == hookType }
                        .prefix(4)
                        .map { SimilarSwipeMatch(item: $0.0, similarity: nil) }

                    similarSwipes = Array(matching)
                }
            } catch {
                similarSwipes = []
            }
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        subtleEmptyState(
            icon: "square.stack.3d.up",
            text: "Save more swipes to see related posts"
        )
    }

    private func subtleEmptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(DS.inkFaded)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(DS.inkFaded)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Pattern Formula

private struct PatternFormula {
    let hookType: SwipeHookType?
    let frameworkType: SwipeFrameworkType?
    let topTechnique: PersuasionType?
    let matchCount: Int
    let avgScore: Double

    var displayComponents: [String] {
        var parts: [String] = []
        if let h = hookType { parts.append(h.displayName) }
        if let f = frameworkType { parts.append(f.abbreviation) }
        if let t = topTechnique { parts.append(t.displayName) }
        return parts
    }
}

// MARK: - Similar Swipe Match

struct SimilarSwipeMatch: Identifiable {
    let item: SwipeGalleryItem
    let similarity: Double?

    var id: String { item.id }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack {
        DS.bg.ignoresSafeArea()
        SimilarSwipesSection(
            currentHookType: .curiosityGap,
            currentFingerprint: nil,
            currentEntityId: 1,
            onSwipeTap: { id in print("Tap swipe: \(id)") }
        )
        .frame(width: 400)
        .padding()
    }
}
#endif
