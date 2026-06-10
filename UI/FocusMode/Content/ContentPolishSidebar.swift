// CosmoOS/UI/FocusMode/Content/ContentPolishSidebar.swift
// Right sidebar for polish mode — readability, scorecard, red team, AI suggestions
// Extracted from ContentPolishView's sidebar
// February 2026

import SwiftUI

// MARK: - Content Polish Sidebar

/// Right sidebar shown when polish mode is active in the unified content editor.
/// Contains readability dashboard, writing quality metrics, content scorecard, and red team analysis.
struct ContentPolishSidebar: View {
    @Binding var state: ContentFocusModeState
    let atom: Atom
    let analysis: WritingAnalysis?

    @StateObject private var scorecardEngine = ContentScorecardEngine()
    @StateObject private var redTeamEngine = RedTeamEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.green)

                Text("Polish")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(DS.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    readabilitySection
                    legendBar
                    writingQualitySection
                    scorecardSection
                    redTeamSection
                }
                .padding(16)
            }
        }
        .frame(width: 320)
        .background(DS.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.border)
                .frame(width: 1)
        }
        .onAppear {
            autoTriggerScorecard()
            autoTriggerRedTeam()
        }
    }

    // MARK: - Readability Section

    @ViewBuilder
    private var readabilitySection: some View {
        if let analysis = analysis {
            HStack(spacing: 16) {
                // Flesch-Kincaid circle
                readabilityCircle(analysis)

                // Stats
                VStack(alignment: .leading, spacing: 4) {
                    statRow(label: "Grade", value: String(format: "%.1f", analysis.gradeLevel))
                    statRow(label: "Sentences", value: "\(analysis.sentenceCount)")
                    statRow(label: "Avg Length", value: String(format: "%.0f", analysis.avgSentenceLength))
                    statRow(label: "Words", value: "\(analysis.wordCount)")
                }
            }
        }
    }

    private func readabilityCircle(_ analysis: WritingAnalysis) -> some View {
        let score = analysis.fleschKincaidScore
        let color = readabilityColor(analysis)

        return ZStack {
            Circle()
                .stroke(DS.glassBorder, lineWidth: 5)
                .frame(width: 56, height: 56)

            Circle()
                .trim(from: 0, to: CGFloat(score / 100.0))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(Int(score))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text)
                Text(analysis.readabilityRating.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .shadow(color: color.opacity(0.12), radius: 6)
    }

    private func readabilityColor(_ analysis: WritingAnalysis) -> Color {
        switch analysis.readabilityRating {
        case .good: return DS.green
        case .moderate: return DS.orange
        case .difficult: return DS.red
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.text)
        }
    }

    // MARK: - Legend Bar

    private var legendBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                legendItem(color: .yellow, label: "Complex")
                legendItem(color: .red, label: "Very Complex")
            }
            HStack(spacing: 12) {
                legendItem(color: .blue, label: "Passive Voice")
                legendItem(color: .purple, label: "Adverb")
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Writing Quality

    @ViewBuilder
    private var writingQualitySection: some View {
        if let analysis = analysis {
            sectionHeader(title: "WRITING QUALITY", icon: "text.magnifyingglass")

            VStack(spacing: 8) {
                qualityRow(label: "Complex Sentences", count: analysis.complexSentenceRanges.count, color: .yellow)
                qualityRow(label: "Very Complex", count: analysis.veryComplexSentenceRanges.count, color: .red)
                qualityRow(label: "Passive Voice", count: analysis.passiveVoiceRanges.count, color: .blue)
                qualityRow(label: "Adverbs", count: analysis.adverbRanges.count, color: .purple)
            }
            .padding(12)
            .dsGlassSection()
        }
    }

    private func qualityRow(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.text)

            Spacer()

            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? color : DS.textMuted)
        }
    }

    // MARK: - Scorecard

    @ViewBuilder
    private var scorecardSection: some View {
        sectionHeader(title: "CONTENT SCORECARD", icon: "chart.bar.fill")

        if scorecardEngine.isEvaluating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(scorecardEngine.evaluationProgress.isEmpty ? "Evaluating..." : scorecardEngine.evaluationProgress)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsGlassSection()
        } else if let scorecard = state.contentScorecard {
            scorecardResults(scorecard)
        } else {
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
    }

    @ViewBuilder
    private func scorecardResults(_ scorecard: ContentScorecard) -> some View {
        VStack(spacing: 8) {
            scoreRow(label: "Hook", score: scorecard.hookScore.score)
            scoreRow(label: "Copy", score: scorecard.copyScore.score)
            scoreRow(label: "CTA", score: scorecard.ctaScore.score)

            if scorecard.voiceMatch.percentage >= 0 {
                scoreRow(label: "Voice", score: scorecard.voiceMatch.percentage / 10.0)
            }

            scoreRow(label: "Structure", score: scorecard.structuralAlignment.alignmentScore / 10.0)

            if let originality = scorecard.originalityScore {
                scoreRow(label: "Originality", score: originality.score)
            }

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
                .background(DS.glassCardFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .dsGlassSection()
    }

    private func scoreRow(label: String, score: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text(String(format: "%.1f", score))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
                Text("/10")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.glassBorder)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(min(score / 10.0, 1.0)), height: 3)
                }
            }
            .frame(height: 3)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score > 7 { return DS.green }
        if score >= 5 { return DS.orange }
        return DS.red
    }

    // MARK: - Red Team

    @ViewBuilder
    private var redTeamSection: some View {
        sectionHeader(title: "RED TEAM", icon: "exclamationmark.shield.fill")

        if redTeamEngine.isEvaluating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Analyzing risks...")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsGlassSection()
        } else if let result = state.redTeamResult {
            redTeamResults(result)
        } else {
            Button {
                autoTriggerRedTeam()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 11))
                    Text("Run Red Team")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func redTeamResults(_ result: RedTeamResult) -> some View {
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
                ForEach(result.cards) { card in
                    VStack(alignment: .leading, spacing: 4) {
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
                        if !card.recommendation.isEmpty {
                            Text(card.recommendation)
                                .font(.system(size: 9))
                                .foregroundStyle(DS.textMuted)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .dsGlassSection(cornerRadius: 8)
                }
            }

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
                .background(DS.glassCardFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)
            Text(title)
                .dsSmallCapsLabel()
        }
    }

    // MARK: - Actions

    private func autoTriggerScorecard() {
        guard state.contentScorecard == nil,
              !state.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            do {
                let scorecard = try await scorecardEngine.evaluate(contentAtom: atom, state: state)
                state.contentScorecard = scorecard
            } catch {
                print("ContentPolishSidebar: scorecard failed: \(error)")
            }
        }
    }

    private func autoTriggerRedTeam() {
        guard state.redTeamResult == nil,
              !state.draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await redTeamEngine.evaluate(contentAtom: atom, state: state)
            state.redTeamResult = redTeamEngine.result
        }
    }
}
