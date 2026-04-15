// CosmoOS/UI/FocusMode/Content/ContentPolishView.swift
// Step 3 of content workflow: Hemingway-style readability analysis + AI polish
// 3-section layout: readability dashboard, annotated text, AI suggestions sidebar
// February 2026

import SwiftUI
import AppKit

// MARK: - Content Polish View

/// Step 3 of the content focus mode workflow.
/// Displays readability analysis with Hemingway-style highlights and AI-powered suggestions.
struct ContentPolishView: View {
    @Binding var state: ContentFocusModeState
    let atom: Atom
    let onBack: () -> Void

    @State private var analysis: WritingAnalysis?
    @StateObject private var scorecardEngine = ContentScorecardEngine()
    @StateObject private var redTeamEngine = RedTeamEngine()

    var body: some View {
        HStack(spacing: 0) {
            // Left: Editor area (readability dashboard + annotated text)
            VStack(spacing: 0) {
                // Top: Readability dashboard
                readabilityDashboard
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Divider()
                    .background(DS.border)

                // Annotated text with legend
                VStack(spacing: 0) {
                    legendBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ScrollView {
                        if let analysis = analysis {
                            PolishAnnotatedTextView(
                                text: state.draftContent,
                                analysis: analysis
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        } else {
                            Text("Analyzing...")
                                .foregroundStyle(DS.textSecondary)
                                .padding(40)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            // Right: Analysis sidebar
            polishSidebar
        }
        .background(DS.bg)
        .onAppear {
            runAnalysis()
            autoTriggerScorecard()
            autoTriggerRedTeam()
        }
        .onChange(of: state.draftContent) { _, _ in
            runAnalysis()
        }
    }

    // MARK: - Readability Dashboard

    private var readabilityDashboard: some View {
        HStack(spacing: 24) {
            // Flesch-Kincaid circle
            readabilityCircle

            // Stats row
            if let analysis = analysis {
                statsRow(analysis: analysis)
            }

            Spacer()

            // Back button
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back to Draft")
                }
                .font(DS.buttonText)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 80)
    }

    private var readabilityCircle: some View {
        ZStack {
            Circle()
                .stroke(DS.border, lineWidth: 6)
                .frame(width: 64, height: 64)

            Circle()
                .trim(from: 0, to: CGFloat((analysis?.fleschKincaidScore ?? 0) / 100.0))
                .stroke(
                    readabilityColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(Int(analysis?.fleschKincaidScore ?? 0))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text)
                Text(analysis?.readabilityRating.label ?? "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(readabilityColor)
            }
        }
        .shadow(color: readabilityColor.opacity(0.12), radius: 8)
    }

    private var readabilityColor: Color {
        guard let analysis = analysis else { return .gray }
        switch analysis.readabilityRating {
        case .good: return DS.green
        case .moderate: return DS.orange
        case .difficult: return DS.red
        }
    }

    private func statsRow(analysis: WritingAnalysis) -> some View {
        HStack(spacing: 20) {
            statItem(value: String(format: "%.1f", analysis.gradeLevel), label: "Grade Level")
            statItem(value: "\(analysis.sentenceCount)", label: "Sentences")
            statItem(value: String(format: "%.0f", analysis.avgSentenceLength), label: "Avg Length")
            statItem(value: String(format: "%.0f%%", analysis.passiveVoicePercent), label: "Passive")
            statItem(value: String(format: "%.1f%%", analysis.adverbDensity), label: "Adverbs")
            statItem(value: "\(analysis.wordCount)", label: "Words")
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.text)
            Text(label)
                .dsSmallCapsLabel()
        }
    }

    // MARK: - Legend Bar

    private var legendBar: some View {
        HStack(spacing: 16) {
            legendItem(color: .yellow, label: "Complex (15-25 words)")
            legendItem(color: .red, label: "Very Complex (>25 words)")
            legendItem(color: .blue, label: "Passive Voice")
            legendItem(color: .purple, label: "Adverb")
            Spacer()
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Analysis Sidebar

    private let sidebarWidth: CGFloat = 320

    private var polishSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.accent)
                Text("Analysis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(DS.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    writingQualitySection
                    scorecardSection
                    redTeamSection
                }
                .padding(16)
            }
        }
        .frame(width: sidebarWidth)
        .background(DS.surface.opacity(0.5))
    }

    // MARK: - Writing Quality Section

    @ViewBuilder
    private var writingQualitySection: some View {
        if let analysis = analysis {
            sidebarSectionHeader(title: "WRITING QUALITY", icon: "text.magnifyingglass")

            VStack(spacing: 8) {
                qualityMetricRow(
                    label: "Complex Sentences",
                    count: analysis.complexSentenceRanges.count,
                    color: .yellow,
                    description: "15-25 words — consider splitting"
                )
                qualityMetricRow(
                    label: "Very Complex",
                    count: analysis.veryComplexSentenceRanges.count,
                    color: .red,
                    description: ">25 words — hard to read"
                )
                qualityMetricRow(
                    label: "Passive Voice",
                    count: analysis.passiveVoiceRanges.count,
                    color: .blue,
                    description: "Use active voice for clarity"
                )
                qualityMetricRow(
                    label: "Adverbs",
                    count: analysis.adverbRanges.count,
                    color: .purple,
                    description: "Use stronger verbs instead"
                )
            }
            .padding(12)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func qualityMetricRow(label: String, count: Int, color: Color, description: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.text)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(count > 0 ? color : DS.textMuted)
                }
                if count > 0 {
                    Text(description)
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
    }

    // MARK: - Scorecard Section

    @ViewBuilder
    private var scorecardSection: some View {
        sidebarSectionHeader(title: "CONTENT SCORECARD", icon: "chart.bar.fill")

        if scorecardEngine.isEvaluating {
            scorecardLoadingView
        } else if let scorecard = state.contentScorecard {
            scorecardResultsView(scorecard)
        } else {
            scorecardEmptyView
        }
    }

    private var scorecardLoadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(scorecardEngine.evaluationProgress.isEmpty ? "Evaluating..." : scorecardEngine.evaluationProgress)
                .font(.system(size: 10))
                .foregroundStyle(DS.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private var scorecardEmptyView: some View {
        Button {
            autoTriggerScorecard()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                Text("Run Scorecard")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(DS.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scorecardResultsView(_ scorecard: ContentScorecard) -> some View {
        VStack(spacing: 8) {
            scoreRow(label: "Hook", score: scorecard.hookScore.score, suggestions: scorecard.hookScore.suggestions)
            scoreRow(label: "Copy", score: scorecard.copyScore.score, suggestions: scorecard.copyScore.suggestions)
            scoreRow(label: "CTA", score: scorecard.ctaScore.score, suggestions: scorecard.ctaScore.suggestions)

            if scorecard.voiceMatch.percentage >= 0 {
                voiceMatchRow(scorecard.voiceMatch)
            }

            structuralAlignmentRow(scorecard.structuralAlignment)

            if let originality = scorecard.originalityScore {
                scoreRow(label: "Originality", score: originality.score, suggestions: originality.suggestions)
            }

            // Overall confidence
            HStack {
                Text("Confidence")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Text("\(scorecard.overallConfidence)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.top, 4)

            // Re-evaluate button
            Button {
                state.contentScorecard = nil
                autoTriggerScorecard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("Re-evaluate")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.border, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func scoreRow(label: String, score: Double, suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text(String(format: "%.1f", score))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
                Text("/10")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.border)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(min(score / 10.0, 1.0)), height: 3)
                }
            }
            .frame(height: 3)

            // Top suggestion
            if let suggestion = suggestions.first {
                Text(suggestion)
                    .font(.system(size: 9))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }

    private func voiceMatchRow(_ voiceMatch: VoiceMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Voice Match")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text(String(format: "%.0f%%", voiceMatch.percentage))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(voiceMatch.percentage / 10.0))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.border)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(voiceMatch.percentage / 10.0))
                        .frame(width: geo.size.width * CGFloat(min(voiceMatch.percentage / 100.0, 1.0)), height: 3)
                }
            }
            .frame(height: 3)

            if let drift = voiceMatch.drifts.first {
                Text(drift.issue)
                    .font(.system(size: 9))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }

    private func structuralAlignmentRow(_ alignment: StructuralAlignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Structure")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text(String(format: "%.0f%%", alignment.alignmentScore))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(alignment.alignmentScore / 10.0))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.border)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(alignment.alignmentScore / 10.0))
                        .frame(width: geo.size.width * CGFloat(min(alignment.alignmentScore / 100.0, 1.0)), height: 3)
                }
            }
            .frame(height: 3)

            if let suggestion = alignment.suggestions.first {
                Text(suggestion)
                    .font(.system(size: 9))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score > 7 { return DS.green }
        if score >= 5 { return DS.orange }
        return DS.red
    }

    // MARK: - Red Team Section

    @ViewBuilder
    private var redTeamSection: some View {
        sidebarSectionHeader(title: "RED TEAM", icon: "exclamationmark.shield.fill")

        if redTeamEngine.isEvaluating {
            redTeamLoadingView
        } else if let result = state.redTeamResult {
            redTeamResultsView(result)
        } else {
            redTeamEmptyView
        }
    }

    private var redTeamLoadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(redTeamEngine.evaluationProgress.isEmpty ? "Analyzing risks..." : redTeamEngine.evaluationProgress)
                .font(.system(size: 10))
                .foregroundStyle(DS.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private var redTeamEmptyView: some View {
        Button {
            autoTriggerRedTeam()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 11))
                Text("Run Red Team")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DS.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func redTeamResultsView(_ result: RedTeamResult) -> some View {
        VStack(spacing: 8) {
            if result.cards.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.green)
                    Text("No significant risks found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.green)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else {
                // Summary counts
                riskSummaryBar(result)

                // Risk cards
                ForEach(result.cards) { card in
                    riskCardView(card)
                }
            }

            // Re-evaluate button
            Button {
                state.redTeamResult = nil
                autoTriggerRedTeam()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("Re-evaluate")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.border, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func riskSummaryBar(_ result: RedTeamResult) -> some View {
        HStack(spacing: 12) {
            if result.highRiskCount > 0 {
                riskCountBadge(count: result.highRiskCount, severity: .high)
            }
            if result.mediumRiskCount > 0 {
                riskCountBadge(count: result.mediumRiskCount, severity: .medium)
            }
            Spacer()
            Text("\(result.cards.count) issue\(result.cards.count == 1 ? "" : "s")")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
    }

    private func riskCountBadge(count: Int, severity: RiskSeverity) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(severity.color)
                .frame(width: 6, height: 6)
            Text("\(count) \(severity.displayName)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(severity.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(severity.color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func riskCardView(_ card: RiskCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: card.riskType.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(card.severity.color)

                Text(card.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer()

                Text(card.severity.displayName.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(card.severity.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(card.severity.color.opacity(0.15), in: Capsule())
            }

            if !card.metric.isEmpty {
                Text(card.metric)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }

            if !card.recommendation.isEmpty {
                Text(card.recommendation)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(card.severity.color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Sidebar Helpers

    private func sidebarSectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)
            Text(title)
                .dsSmallCapsLabel()
        }
    }

    // MARK: - Actions

    private func runAnalysis() {
        let text = state.draftContent
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            analysis = nil
            return
        }
        analysis = WritingAnalyzer.shared.analyze(text: text)
    }

    /// Auto-trigger scorecard evaluation when entering Polish phase
    private func autoTriggerScorecard() {
        guard state.contentScorecard == nil,
              !state.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        Task {
            do {
                let scorecard = try await scorecardEngine.evaluate(contentAtom: atom, state: state)
                state.contentScorecard = scorecard
            } catch {
                print("ContentPolishView: scorecard auto-trigger failed: \(error)")
            }
        }
    }

    /// Auto-trigger Red Team analysis when entering Polish phase
    private func autoTriggerRedTeam() {
        guard state.redTeamResult == nil,
              !state.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        Task {
            await redTeamEngine.evaluate(contentAtom: atom, state: state)
            state.redTeamResult = redTeamEngine.result
        }
    }
}

// MARK: - Annotated Text View (NSViewRepresentable)

/// NSTextView wrapper that displays text with Hemingway-style colored highlights
/// for complex sentences, passive voice, and adverbs.
struct PolishAnnotatedTextView: NSViewRepresentable {
    let text: String
    let analysis: WritingAnalysis

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        let attributed = buildAttributedString()
        textView.textStorage?.setAttributedString(attributed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 600
        nsView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        nsView.layoutManager?.ensureLayout(for: nsView.textContainer!)
        if let layoutManager = nsView.layoutManager, let textContainer = nsView.textContainer {
            let usedRect = layoutManager.usedRect(for: textContainer)
            return CGSize(width: width, height: ceil(usedRect.height) + 4)
        }
        return CGSize(width: width, height: 100)
    }

    private func buildAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .font: NSFont.systemFont(ofSize: 15),
            .paragraphStyle: paragraphStyle
        ])

        let nsLength = (text as NSString).length

        // Apply highlights in order: sentences first, then word-level overlays
        // Complex sentences: yellow background
        for range in analysis.complexSentenceRanges {
            guard range.location + range.length <= nsLength else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: PolishHighlightColors.complex,
                range: range
            )
        }

        // Very complex sentences: red background
        for range in analysis.veryComplexSentenceRanges {
            guard range.location + range.length <= nsLength else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: PolishHighlightColors.veryComplex,
                range: range
            )
        }

        // Passive voice: blue background
        for range in analysis.passiveVoiceRanges {
            guard range.location + range.length <= nsLength else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: PolishHighlightColors.passive,
                range: range
            )
        }

        // Adverbs: purple background
        for range in analysis.adverbRanges {
            guard range.location + range.length <= nsLength else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: PolishHighlightColors.adverb,
                range: range
            )
        }

        return attributed
    }
}

