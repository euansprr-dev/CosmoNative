// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyInsightRail.swift
// The analysis rail: INSIGHT (the one serif reading moment) → STRUCTURE
// (slide-anchored beats) → PATTERNS → DETAILS (taxonomy). Everything reads
// from one analysis produced by the insight pass.
// July 2026

import SwiftUI

/// The rail's building blocks — adaptive layouts (panes, medium windows) show
/// subsets in different places, so each tier composes exactly what fits.
enum SwipeStudyRailSection: Hashable {
    case insight, structure, patterns, details
}

struct SwipeStudyInsightRail: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom
    /// Which sections this instance renders (adaptive tiers split the rail).
    var visibleSections: Set<SwipeStudyRailSection> = [.insight, .structure, .patterns, .details]
    /// Provided by the shell (owns the ScrollViewReader proxy): scrolls the
    /// manuscript / seeks the video to a structure beat.
    var onBeatTap: (SwipeSection) -> Void

    private func shows(_ section: SwipeStudyRailSection) -> Bool {
        visibleSections.contains(section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            if model.isAnalyzing {
                if shows(.insight) || shows(.structure) {
                    analysisSkeleton
                }
            } else if let analysis = model.analysis, analysis.isFullyAnalyzed {
                if shows(.insight) {
                    insightSection(analysis)
                }
                if shows(.structure) {
                    structureSection(analysis)
                }
                if shows(.patterns) {
                    patternsSection
                }
                if shows(.details) {
                    detailsSection
                }
            } else {
                if shows(.insight) || shows(.structure) {
                    analysisTeachingRow
                }
                if shows(.details) {
                    detailsSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Insight

    @ViewBuilder
    private func insightSection(_ analysis: SwipeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            SwipeStudyRailHeader(label: "INSIGHT")

            if let insight = analysis.keyInsight, !insight.isEmpty {
                Text(insight)
                    .font(DS.dateSerif)
                    .foregroundStyle(DS.text)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let mechanism = analysis.hookMechanism, !mechanism.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Why the hook works")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                    Text(mechanism)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DS.space2)
            }
        }
    }

    // MARK: - Structure

    @ViewBuilder
    private func structureSection(_ analysis: SwipeAnalysis) -> some View {
        if let sections = analysis.sections, !sections.isEmpty {
            VStack(alignment: .leading, spacing: DS.space10) {
                SwipeStudyRailHeader(label: "STRUCTURE", count: sections.count)

                proportionTrack(sections)

                VStack(alignment: .leading, spacing: DS.space4) {
                    ForEach(sections) { section in
                        SwipeStudyBeatRow(section: section) {
                            onBeatTap(section)
                        }
                    }
                }

                if let framework = analysis.frameworkType {
                    Text("\(framework.displayName) — \(framework.description)")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .padding(.top, DS.space2)
                }

                if let recipe = analysis.structuralRecipe, !recipe.isEmpty {
                    DisclosureGroup {
                        Text(recipe)
                            .font(DS.footnote)
                            .foregroundStyle(DS.textSecondary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(.top, DS.space6)
                    } label: {
                        Text("Replication recipe")
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(DS.textSecondary)
                    }
                    .disclosureGroupStyle(.automatic)
                    .tint(DS.textMuted)
                    .padding(.top, DS.space2)
                }
            }
        }
    }

    /// Thin proportional bar — one tint per beat, widths from sizePercent.
    private func proportionTrack(_ sections: [SwipeSection]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    Capsule()
                        .fill(beatTint(index))
                        .frame(width: max(8, geo.size.width * trackFraction(section, in: sections)))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func trackFraction(_ section: SwipeSection, in sections: [SwipeSection]) -> CGFloat {
        let total = sections.compactMap(\.sizePercent).reduce(0, +)
        guard total > 0, let size = section.sizePercent else {
            return 1 / CGFloat(max(sections.count, 1))
        }
        return CGFloat(size / total) * 0.96
    }

    private func beatTint(_ index: Int) -> Color {
        let tints: [Color] = [
            DS.accent.opacity(0.55),
            DS.entitySwipe.opacity(0.5),
            DS.accent.opacity(0.32),
            DS.entitySwipe.opacity(0.3),
            DS.accent.opacity(0.2),
            DS.entitySwipe.opacity(0.2),
            DS.accent.opacity(0.14),
            DS.entitySwipe.opacity(0.14)
        ]
        return tints[index % tints.count]
    }

    // MARK: - Patterns (filled by the PatternWeaver — Phase 3)

    private var patternsSection: some View {
        SwipeStudyPatternsSection(model: model, atom: atom)
    }

    // MARK: - Details (taxonomy)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            SwipeStudyRailHeader(label: "DETAILS")
            TaxonomySection(
                analysis: $model.analysis,
                currentAtom: $model.currentAtom,
                isReclassifying: $model.isReclassifying,
                reclassifySuggestion: $model.reclassifySuggestion,
                onReclassify: { model.reclassifySwipe() },
                onAcceptReclassification: { model.acceptReclassification() },
                onRejectReclassification: { model.rejectReclassification() },
                onSaveTaxonomyChange: { model.saveTaxonomyOverride() },
                onOpenCreatorProfile: { creatorUUID in
                    NotificationCenter.default.post(
                        name: Notification.Name("openCreatorProfile"),
                        object: nil,
                        userInfo: ["creatorUUID": creatorUUID]
                    )
                },
                onLinkCreator: { _, _ in
                    model.saveTaxonomyOverride()
                }
            )
        }
    }

    // MARK: - States

    /// Same-grammar teaching row: analysis is missing, hand the user the fix.
    private var analysisTeachingRow: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            SwipeStudyRailHeader(label: "INSIGHT")
            HStack(spacing: DS.space8) {
                Image(systemName: "sparkles")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text(hasAnyTranscript
                     ? "Run the analysis to see why this one works."
                     : "Add a transcript first — the analysis reads it.")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
                if hasAnyTranscript {
                    Button("Analyze") { model.reanalyze() }
                        .buttonStyle(.plain)
                        .font(DS.subheadline.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .help("Analyze this swipe")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var hasAnyTranscript: Bool {
        !model.slidesTranscriptText.isEmpty || !model.transcriptText.isEmpty
    }

    private var analysisSkeleton: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            SwipeStudyRailHeader(label: "INSIGHT")
            VStack(alignment: .leading, spacing: DS.space8) {
                skeletonBar(fraction: 0.95)
                skeletonBar(fraction: 0.8)
                skeletonBar(fraction: 0.6)
            }
            .padding(.top, DS.space2)
            HStack(spacing: DS.space6) {
                ProgressView().controlSize(.small)
                Text("Reading the structure…")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.top, DS.space4)
        }
    }

    private func skeletonBar(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.glassSectionFill)
                .frame(width: geo.size.width * fraction)
        }
        .frame(height: 12)
    }
}

// MARK: - Rail header (the one header voice, count optional)

struct SwipeStudyRailHeader: View {
    let label: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
            if let count {
                Text("\(count)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Beat row

struct SwipeStudyBeatRow: View {
    let section: SwipeSection
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                Text(displayLabel)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .frame(width: 108, alignment: .leading)
                Text(section.purpose)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if section.slideStart != nil {
                    Image(systemName: "arrow.down.right")
                        .font(DS.caption2.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .opacity(isHovered ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DS.glassSectionFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .help(anchorHelp)
        .accessibilityLabel("\(displayLabel). \(section.purpose)")
    }

    private var displayLabel: String {
        section.label.replacingOccurrences(of: "Uncategorized: ", with: "")
    }

    private var anchorHelp: String {
        if let start = section.slideStart {
            let end = section.slideEnd ?? start
            return start == end ? "Jump to slide \(start)" : "Jump to slides \(start)–\(end)"
        }
        return "Jump to this beat"
    }
}
