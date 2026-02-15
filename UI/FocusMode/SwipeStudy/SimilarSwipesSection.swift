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
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("SIMILAR IN COLLECTION")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)

            if !hasLoaded {
                ProgressView()
                    .tint(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if similarSwipes.isEmpty {
                placeholderView
            } else {
                // Pattern formula callout
                if let formula = patternFormula {
                    patternFormulaCard(formula)
                }

                scrollContent
            }
        }
        .padding(16)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onAppear { loadSimilarSwipes() }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(similarSwipes) { match in
                    similarCard(match)
                        .onTapGesture {
                            onSwipeTap(match.item.entityId)
                        }
                }
            }
        }
    }

    // MARK: - Similar Card

    private func similarCard(_ match: SimilarSwipeMatch) -> some View {
        let item = match.item
        return VStack(alignment: .leading, spacing: 6) {
            // Thumbnail area
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
            .frame(width: 140, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Title
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            // Hook type pill + similarity score
            HStack(spacing: 6) {
                if let hookType = item.hookType {
                    Text(hookType.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(hookType.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(hookType.color.opacity(0.15), in: Capsule())
                }

                Spacer()

                if let similarity = match.similarity {
                    Text("\(Int(similarity * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(similarityColor(similarity))
                } else if let score = item.hookScore {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(item.scoreColor)
                }
            }
            .frame(width: 140)
        }
        .padding(8)
        .frame(width: 156, height: 110)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var cardPlaceholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.04))
            .overlay(
                Image(systemName: "doc.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.15))
            )
    }

    private func similarityColor(_ similarity: Double) -> Color {
        if similarity >= 0.8 { return Color(hex: "#10B981") }  // Emerald
        if similarity >= 0.5 { return Color(hex: "#3B82F6") }  // Blue
        return Color(hex: "#64748B")                             // Slate
    }

    // MARK: - Pattern Formula Card

    private func patternFormulaCard(_ formula: PatternFormula) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#FFD700"))
                Text("YOUR WINNING FORMULA")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(Color(hex: "#FFD700"))
            }

            // Formula pills
            HStack(spacing: 6) {
                if let hookType = formula.hookType {
                    Text(hookType.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(hookType.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hookType.color.opacity(0.15), in: Capsule())
                }

                if formula.hookType != nil && formula.frameworkType != nil {
                    Text("+")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }

                if let frameworkType = formula.frameworkType {
                    Text(frameworkType.abbreviation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(frameworkType.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(frameworkType.color.opacity(0.15), in: Capsule())
                }

                if formula.topTechnique != nil && (formula.hookType != nil || formula.frameworkType != nil) {
                    Text("+")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }

                if let technique = formula.topTechnique {
                    Text(technique.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(technique.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(technique.color.opacity(0.15), in: Capsule())
                }
            }

            // Stats line
            HStack(spacing: 4) {
                Text("Found in \(formula.matchCount) swipes")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))

                if formula.avgScore > 0 {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))
                    Text("Avg score \(String(format: "%.1f", formula.avgScore))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#FFD700").opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "#FFD700").opacity(0.15), lineWidth: 1)
        )
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
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.15))
            Text("Save more swipes to see patterns")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
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
struct SimilarSwipesSection_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()
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
}
#endif
