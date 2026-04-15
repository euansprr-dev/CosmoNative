// CosmoOS/UI/FocusMode/Content/IntelligenceModelView.swift
// Reusable view for displaying and editing the Client Intelligence Model
// Uses concrete fingerprint types from ContentPipelineMetadata.swift
// February 2026

import SwiftUI

// MARK: - Display Metric (local adapter)

/// Lightweight adapter to display concrete fingerprint fields as editable rows
private struct DisplayMetric: Identifiable {
    let id: String // stable key path string for override tracking
    let label: String
    var value: String

    init(_ label: String, value: String, key: String) {
        self.id = key
        self.label = label
        self.value = value
    }
}

struct IntelligenceModelView: View {
    @Binding var model: ClientIntelligenceModel
    @Binding var overrides: [IntelligenceOverride]
    @Binding var editingMetricId: UUID?
    @Binding var editingMetricKey: String
    @Binding var editingMetricValue: String
    var showUpdateButton: Bool = true
    var onUpdateRequested: (() -> Void)? = nil

    @State private var expandedSections: Set<String> = ["voice", "performance", "failure", "audience", "niche"]
    @State private var selectedFormat: IntelligenceFormatView = .overall

    /// Whether format-specific data exists in the model
    private var hasFormatData: Bool {
        model.reelVoiceFingerprint != nil || model.threadVoiceFingerprint != nil ||
        model.reelFailureFingerprint != nil || model.threadFailureFingerprint != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBar

            if hasFormatData {
                formatPicker
            }

            switch selectedFormat {
            case .overall:
                overallSections
            case .reels:
                reelSections
            case .threads:
                threadSections
            }

            sectionView(
                key: "audience",
                title: "AUDIENCE MODEL",
                icon: "person.3.fill",
                color: DS.green,
                metrics: audienceMetrics()
            )

            sectionView(
                key: "niche",
                title: "NICHE & POSITIONING",
                icon: "target",
                color: DS.orange,
                metrics: nicheMetrics()
            )

            if showUpdateButton {
                updateButton
            }
        }
    }

    // MARK: - Format Picker

    private var formatPicker: some View {
        HStack(spacing: 2) {
            ForEach(IntelligenceFormatView.allCases, id: \.self) { format in
                formatPickerButton(format)
            }
        }
        .padding(2)
        .background(DS.borderSubtle, in: Capsule())
    }

    @ViewBuilder
    private func formatPickerButton(_ format: IntelligenceFormatView) -> some View {
        let isSelected = selectedFormat == format
        let isDisabled: Bool = {
            switch format {
            case .overall: return false
            case .reels: return model.reelVoiceFingerprint == nil && model.reelFailureFingerprint == nil
            case .threads: return model.threadVoiceFingerprint == nil && model.threadFailureFingerprint == nil
            }
        }()

        Button(action: { if !isDisabled { selectedFormat = format } }) {
            Text(format.rawValue)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundColor(isDisabled ? DS.textMuted : isSelected ? .white : DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected ? DS.borderActive : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Format-Conditional Sections

    @ViewBuilder
    private var overallSections: some View {
        sectionView(
            key: "voice",
            title: "VOICE FINGERPRINT",
            icon: "waveform",
            color: DS.accent,
            metrics: voiceMetrics()
        )

        sectionView(
            key: "performance",
            title: "PERFORMANCE FINGERPRINT",
            icon: "chart.line.uptrend.xyaxis",
            color: .blue,
            metrics: performanceMetrics()
        )

        if let fp = model.failureFingerprint, !fp.rules.isEmpty {
            failureFingerprintSection(
                key: "failure",
                title: "FAILURE FINGERPRINT",
                fingerprint: fp
            )
        }
    }

    @ViewBuilder
    private var reelSections: some View {
        if model.reelVoiceFingerprint != nil {
            sectionView(
                key: "reelVoice",
                title: "REEL VOICE FINGERPRINT",
                icon: "waveform",
                color: DS.accent,
                metrics: reelVoiceMetrics()
            )

            sectionView(
                key: "reelPerf",
                title: "REEL PERFORMANCE FINGERPRINT",
                icon: "chart.line.uptrend.xyaxis",
                color: .blue,
                metrics: reelPerformanceMetrics()
            )

            if let fp = model.reelFailureFingerprint, !fp.rules.isEmpty {
                failureFingerprintSection(
                    key: "reelFailure",
                    title: "REEL FAILURE FINGERPRINT",
                    fingerprint: fp
                )
            }
        } else {
            formatEmptyState("reel")
        }
    }

    @ViewBuilder
    private var threadSections: some View {
        if model.threadVoiceFingerprint != nil {
            sectionView(
                key: "threadVoice",
                title: "THREAD VOICE FINGERPRINT",
                icon: "waveform",
                color: DS.accent,
                metrics: threadVoiceMetrics()
            )

            sectionView(
                key: "threadPerf",
                title: "THREAD PERFORMANCE FINGERPRINT",
                icon: "chart.line.uptrend.xyaxis",
                color: .blue,
                metrics: threadPerformanceMetrics()
            )

            if let fp = model.threadFailureFingerprint, !fp.rules.isEmpty {
                failureFingerprintSection(
                    key: "threadFailure",
                    title: "THREAD FAILURE FINGERPRINT",
                    fingerprint: fp
                )
            }
        } else {
            formatEmptyState("thread")
        }
    }

    @ViewBuilder
    private func formatEmptyState(_ format: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(DS.textMuted)
            Text("No \(format) analysis — add \(format) documents and regenerate.")
                .font(DS.cardMeta)
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14))
                .foregroundColor(DS.accent)

            Text("Intelligence Model")
                .font(DS.navTitle)
                .foregroundColor(DS.text)

            Spacer()

            Text("Generated \(model.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)
        }
    }

    // MARK: - Section View

    @ViewBuilder
    private func sectionView(
        key: String,
        title: String,
        icon: String,
        color: Color,
        metrics: [DisplayMetric]
    ) -> some View {
        let isExpanded = expandedSections.contains(key)

        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.25)) {
                    if isExpanded {
                        expandedSections.remove(key)
                    } else {
                        expandedSections.insert(key)
                    }
                }
            }) {
                sectionHeaderLabel(title: title, icon: icon, color: color, isExpanded: isExpanded, metricCount: metrics.count)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(metrics) { metric in
                        metricRow(metric: metric, sectionKey: key)
                    }
                }
                .padding(.top, 2)
            }
        }
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionHeaderLabel(title: String, icon: String, color: Color, isExpanded: Bool, metricCount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)

            Text(title)
                .dsSmallCapsLabel()

            Spacer()

            Text("\(metricCount) metrics")
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Metric Row

    @ViewBuilder
    private func metricRow(metric: DisplayMetric, sectionKey: String) -> some View {
        let isEditing = editingMetricKey == metric.id
        let override = overrides.first(where: { $0.metricPath == metric.id })
        let confidence = model.confidenceScores.first(where: { $0.metricPath == metric.id })?.confidence

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(metric.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 120, alignment: .leading)

                if isEditing {
                    TextField("Value", text: $editingMetricValue)
                        .textFieldStyle(.plain)
                        .font(DS.cardMeta)
                        .foregroundColor(DS.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DS.border, in: RoundedRectangle(cornerRadius: 4))
                        .onSubmit { saveEdit(metricKey: metric.id, oldValue: metric.value, sectionKey: sectionKey) }
                } else {
                    Text(metric.value)
                        .font(DS.cardMeta)
                        .foregroundColor(DS.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let confidence = confidence {
                    confidenceBadge(confidence)
                }

                if isEditing {
                    editingButtons(metricKey: metric.id, oldValue: metric.value, sectionKey: sectionKey)
                } else {
                    Button(action: {
                        editingMetricKey = metric.id
                        editingMetricValue = metric.value
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let override = override {
                overrideIndicator(override: override)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func editingButtons(metricKey: String, oldValue: String, sectionKey: String) -> some View {
        HStack(spacing: 4) {
            Button(action: { saveEdit(metricKey: metricKey, oldValue: oldValue, sectionKey: sectionKey) }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.green)
            }
            .buttonStyle(.plain)

            Button(action: { editingMetricKey = "" }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: ConfidenceLevel) -> some View {
        Text(confidence.displayName)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(confidence.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(confidence.color.opacity(0.12))
            )
    }

    @ViewBuilder
    private func overrideIndicator(override: IntelligenceOverride) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 8))
                .foregroundColor(DS.orange.opacity(0.6))

            Text("User override")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.orange.opacity(0.6))

            Text("- AI suggested: \(override.generatedValue)")
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)
                .lineLimit(1)
        }
        .padding(.leading, 128)
    }

    // MARK: - Update Button

    private var updateButton: some View {
        Button(action: { onUpdateRequested?() }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                Text("Update Intelligence Model")
                    .font(DS.buttonText)
            }
            .foregroundColor(DS.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.accentSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    // MARK: - Failure Fingerprint Section

    @ViewBuilder
    private func failureFingerprintSection(
        key: String,
        title: String,
        fingerprint: FailureFingerprint
    ) -> some View {
        let isExpanded = expandedSections.contains(key)
        let highCount = fingerprint.rules.filter { $0.severity == .high }.count
        let medCount = fingerprint.rules.filter { $0.severity == .medium }.count

        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.25)) {
                    if isExpanded {
                        expandedSections.remove(key)
                    } else {
                        expandedSections.insert(key)
                    }
                }
            }) {
                failureSectionHeader(
                    title: title,
                    isExpanded: isExpanded,
                    ruleCount: fingerprint.rules.count,
                    highCount: highCount,
                    medCount: medCount
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Source summary
                failureSourceSummary(fingerprint: fingerprint)

                // Rule cards
                VStack(spacing: 1) {
                    ForEach(fingerprint.rules) { rule in
                        failureRuleRow(rule)
                    }
                }
                .padding(.top, 2)
            }
        }
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func failureSectionHeader(
        title: String,
        isExpanded: Bool,
        ruleCount: Int,
        highCount: Int,
        medCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11))
                .foregroundColor(.red)

            Text(title)
                .dsSmallCapsLabel()

            Spacer()

            if highCount > 0 {
                severityCountBadge(count: highCount, severity: .high)
            }
            if medCount > 0 {
                severityCountBadge(count: medCount, severity: .medium)
            }

            Text("\(ruleCount) rules")
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func severityCountBadge(count: Int, severity: FailureRuleSeverity) -> some View {
        Text("\(count) \(severity.displayName)")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(severity.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(severity.color.opacity(0.12))
            )
    }

    @ViewBuilder
    private func failureSourceSummary(fingerprint: FailureFingerprint) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(DS.green)
                Text("\(fingerprint.topPerformerCount) top performers")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textSecondary)
            }

            Text("vs")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.textMuted)

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text("\(fingerprint.underperformerCount) underperformers")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.03))
    }

    @ViewBuilder
    private func failureRuleRow(_ rule: FailureRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top: dimension + severity
            HStack(spacing: 8) {
                Text(rule.dimension)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                Text(rule.severity.displayName.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(rule.severity.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(rule.severity.color.opacity(0.12))
                    )

                Text(rule.delta)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }

            // Comparison: best vs worst
            HStack(spacing: 0) {
                comparisonMetric(label: "Top", value: rule.bestMetric, color: DS.green)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(DS.textMuted)
                    .padding(.horizontal, 6)

                comparisonMetric(label: "Worst", value: rule.worstMetric, color: .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Rule statement
            Text(rule.rule)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(rule.severity == .high ? Color.red.opacity(0.9) : DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func comparisonMetric(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 5, height: 5)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.textMuted)

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Metric Extraction

    private func voiceMetrics() -> [DisplayMetric] {
        let v = model.voiceFingerprint
        return [
            DisplayMetric("Avg Sentence Len", value: String(format: "%.1f words", v.avgSentenceLength), key: "voice.avgSentenceLength"),
            DisplayMetric("Max Sentence Len", value: "\(v.maxSentenceLength) words", key: "voice.maxSentenceLength"),
            DisplayMetric("Reading Level", value: v.readingLevel, key: "voice.readingLevel"),
            DisplayMetric("Punctuation Style", value: v.punctuationStyle, key: "voice.punctuationStyle"),
            DisplayMetric("CTA Pattern", value: v.ctaPattern, key: "voice.ctaPattern"),
            DisplayMetric("Paragraph Length", value: v.paragraphLength, key: "voice.paragraphLength"),
            DisplayMetric("Power Words", value: v.powerWords.joined(separator: ", "), key: "voice.powerWords"),
            DisplayMetric("Signature Phrases", value: v.signaturePhrases.joined(separator: ", "), key: "voice.signaturePhrases"),
            DisplayMetric("Blacklisted", value: v.blacklistedPhrases.joined(separator: ", "), key: "voice.blacklistedPhrases"),
            DisplayMetric("Formatting Quirks", value: v.formattingQuirks.joined(separator: ", "), key: "voice.formattingQuirks"),
            DisplayMetric("Emotional Tones", value: formatDict(v.emotionalToneDistribution), key: "voice.emotionalToneDistribution"),
            DisplayMetric("Sentence Starters", value: formatDict(v.sentenceStarterDistribution), key: "voice.sentenceStarterDistribution"),
        ]
    }

    private func performanceMetrics() -> [DisplayMetric] {
        let p = model.performanceFingerprint
        return [
            DisplayMetric("Optimal Length", value: p.optimalLength, key: "perf.optimalLength"),
            DisplayMetric("Best Topics", value: p.bestTopics.joined(separator: ", "), key: "perf.bestTopics"),
            DisplayMetric("Best Beat Patterns", value: p.bestBeatPatterns.joined(separator: ", "), key: "perf.bestBeatPatterns"),
            DisplayMetric("Engagement Triggers", value: p.engagementTriggers.joined(separator: ", "), key: "perf.engagementTriggers"),
            DisplayMetric("Hook Performance", value: formatDict(p.hookTypePerformance), key: "perf.hookTypePerformance"),
            DisplayMetric("Format Comparison", value: formatDict(p.formatComparison), key: "perf.formatComparison"),
        ]
    }

    private func audienceMetrics() -> [DisplayMetric] {
        let a = model.audienceModel
        return [
            DisplayMetric("Primary Audience", value: a.primaryAudience, key: "audience.primaryAudience"),
            DisplayMetric("Top Pain Points", value: a.topPainPoints.joined(separator: ", "), key: "audience.topPainPoints"),
            DisplayMetric("Aspirations", value: a.aspirationalOutcomes.joined(separator: ", "), key: "audience.aspirationalOutcomes"),
            DisplayMetric("Objections", value: a.commonObjections.joined(separator: ", "), key: "audience.commonObjections"),
            DisplayMetric("Audience Language", value: a.audienceLanguage.joined(separator: ", "), key: "audience.audienceLanguage"),
        ]
    }

    private func nicheMetrics() -> [DisplayMetric] {
        let n = model.nicheAndPositioning
        return [
            DisplayMetric("Specific Niche", value: n.specificNiche, key: "niche.specificNiche"),
            DisplayMetric("Unique Angle", value: n.uniqueAngle, key: "niche.uniqueAngle"),
            DisplayMetric("Core Beliefs", value: n.coreBeliefs.joined(separator: ", "), key: "niche.coreBeliefs"),
            DisplayMetric("Enemies", value: n.enemies.joined(separator: ", "), key: "niche.enemies"),
            DisplayMetric("Unique Mechanism", value: n.uniqueMechanism, key: "niche.uniqueMechanism"),
        ]
    }

    // MARK: - Format-Specific Metric Extractors

    private func reelVoiceMetrics() -> [DisplayMetric] {
        guard let v = model.reelVoiceFingerprint else { return [] }
        return [
            DisplayMetric("Avg Sentence Len", value: String(format: "%.1f words", v.avgSentenceLength), key: "reelVoice.avgSentenceLength"),
            DisplayMetric("Max Sentence Len", value: "\(v.maxSentenceLength) words", key: "reelVoice.maxSentenceLength"),
            DisplayMetric("Reading Level", value: v.readingLevel, key: "reelVoice.readingLevel"),
            DisplayMetric("Punctuation Style", value: v.punctuationStyle, key: "reelVoice.punctuationStyle"),
            DisplayMetric("CTA Pattern", value: v.ctaPattern, key: "reelVoice.ctaPattern"),
            DisplayMetric("Paragraph Length", value: v.paragraphLength, key: "reelVoice.paragraphLength"),
            DisplayMetric("Power Words", value: v.powerWords.joined(separator: ", "), key: "reelVoice.powerWords"),
            DisplayMetric("Signature Phrases", value: v.signaturePhrases.joined(separator: ", "), key: "reelVoice.signaturePhrases"),
            DisplayMetric("Blacklisted", value: v.blacklistedPhrases.joined(separator: ", "), key: "reelVoice.blacklistedPhrases"),
            DisplayMetric("Formatting Quirks", value: v.formattingQuirks.joined(separator: ", "), key: "reelVoice.formattingQuirks"),
            DisplayMetric("Emotional Tones", value: formatDict(v.emotionalToneDistribution), key: "reelVoice.emotionalToneDistribution"),
            DisplayMetric("Sentence Starters", value: formatDict(v.sentenceStarterDistribution), key: "reelVoice.sentenceStarterDistribution"),
        ]
    }

    private func reelPerformanceMetrics() -> [DisplayMetric] {
        guard let p = model.reelPerformanceFingerprint else { return [] }
        return [
            DisplayMetric("Optimal Length", value: p.optimalLength, key: "reelPerf.optimalLength"),
            DisplayMetric("Best Topics", value: p.bestTopics.joined(separator: ", "), key: "reelPerf.bestTopics"),
            DisplayMetric("Best Beat Patterns", value: p.bestBeatPatterns.joined(separator: ", "), key: "reelPerf.bestBeatPatterns"),
            DisplayMetric("Engagement Triggers", value: p.engagementTriggers.joined(separator: ", "), key: "reelPerf.engagementTriggers"),
            DisplayMetric("Hook Performance", value: formatDict(p.hookTypePerformance), key: "reelPerf.hookTypePerformance"),
            DisplayMetric("Format Comparison", value: formatDict(p.formatComparison), key: "reelPerf.formatComparison"),
        ]
    }

    private func threadVoiceMetrics() -> [DisplayMetric] {
        guard let v = model.threadVoiceFingerprint else { return [] }
        return [
            DisplayMetric("Avg Sentence Len", value: String(format: "%.1f words", v.avgSentenceLength), key: "threadVoice.avgSentenceLength"),
            DisplayMetric("Max Sentence Len", value: "\(v.maxSentenceLength) words", key: "threadVoice.maxSentenceLength"),
            DisplayMetric("Reading Level", value: v.readingLevel, key: "threadVoice.readingLevel"),
            DisplayMetric("Punctuation Style", value: v.punctuationStyle, key: "threadVoice.punctuationStyle"),
            DisplayMetric("CTA Pattern", value: v.ctaPattern, key: "threadVoice.ctaPattern"),
            DisplayMetric("Paragraph Length", value: v.paragraphLength, key: "threadVoice.paragraphLength"),
            DisplayMetric("Power Words", value: v.powerWords.joined(separator: ", "), key: "threadVoice.powerWords"),
            DisplayMetric("Signature Phrases", value: v.signaturePhrases.joined(separator: ", "), key: "threadVoice.signaturePhrases"),
            DisplayMetric("Blacklisted", value: v.blacklistedPhrases.joined(separator: ", "), key: "threadVoice.blacklistedPhrases"),
            DisplayMetric("Formatting Quirks", value: v.formattingQuirks.joined(separator: ", "), key: "threadVoice.formattingQuirks"),
            DisplayMetric("Emotional Tones", value: formatDict(v.emotionalToneDistribution), key: "threadVoice.emotionalToneDistribution"),
            DisplayMetric("Sentence Starters", value: formatDict(v.sentenceStarterDistribution), key: "threadVoice.sentenceStarterDistribution"),
        ]
    }

    private func threadPerformanceMetrics() -> [DisplayMetric] {
        guard let p = model.threadPerformanceFingerprint else { return [] }
        return [
            DisplayMetric("Optimal Length", value: p.optimalLength, key: "threadPerf.optimalLength"),
            DisplayMetric("Best Topics", value: p.bestTopics.joined(separator: ", "), key: "threadPerf.bestTopics"),
            DisplayMetric("Best Beat Patterns", value: p.bestBeatPatterns.joined(separator: ", "), key: "threadPerf.bestBeatPatterns"),
            DisplayMetric("Engagement Triggers", value: p.engagementTriggers.joined(separator: ", "), key: "threadPerf.engagementTriggers"),
            DisplayMetric("Hook Performance", value: formatDict(p.hookTypePerformance), key: "threadPerf.hookTypePerformance"),
            DisplayMetric("Format Comparison", value: formatDict(p.formatComparison), key: "threadPerf.formatComparison"),
        ]
    }

    private func formatDict(_ dict: [String: Double]) -> String {
        guard !dict.isEmpty else { return "—" }
        return dict.sorted(by: { $0.value > $1.value })
            .prefix(5)
            .map { "\($0.key): \(Int($0.value * 100))%" }
            .joined(separator: ", ")
    }

    // MARK: - Save Edit

    private func saveEdit(metricKey: String, oldValue: String, sectionKey: String) {
        let newValue = editingMetricValue.trimmingCharacters(in: .whitespaces)
        guard !newValue.isEmpty, newValue != oldValue else {
            editingMetricKey = ""
            return
        }

        // Record override
        let override = IntelligenceOverride(
            metricPath: metricKey,
            userValue: newValue,
            generatedValue: oldValue,
            overrideDate: Date()
        )
        overrides.removeAll { $0.metricPath == metricKey }
        overrides.append(override)

        // Write back to the concrete model field
        applyEdit(key: metricKey, value: newValue)

        editingMetricKey = ""
    }

    private func applyEdit(key: String, value: String) {
        switch key {
        // Voice (overall)
        case "voice.readingLevel": model.voiceFingerprint.readingLevel = value
        case "voice.punctuationStyle": model.voiceFingerprint.punctuationStyle = value
        case "voice.ctaPattern": model.voiceFingerprint.ctaPattern = value
        case "voice.paragraphLength": model.voiceFingerprint.paragraphLength = value
        case "voice.powerWords": model.voiceFingerprint.powerWords = value.components(separatedBy: ", ")
        case "voice.signaturePhrases": model.voiceFingerprint.signaturePhrases = value.components(separatedBy: ", ")
        case "voice.blacklistedPhrases": model.voiceFingerprint.blacklistedPhrases = value.components(separatedBy: ", ")
        case "voice.formattingQuirks": model.voiceFingerprint.formattingQuirks = value.components(separatedBy: ", ")
        case "voice.avgSentenceLength":
            if let d = Double(value.replacingOccurrences(of: " words", with: "")) {
                model.voiceFingerprint.avgSentenceLength = d
            }
        case "voice.maxSentenceLength":
            if let i = Int(value.replacingOccurrences(of: " words", with: "")) {
                model.voiceFingerprint.maxSentenceLength = i
            }
        // Reel voice
        case "reelVoice.readingLevel": model.reelVoiceFingerprint?.readingLevel = value
        case "reelVoice.punctuationStyle": model.reelVoiceFingerprint?.punctuationStyle = value
        case "reelVoice.ctaPattern": model.reelVoiceFingerprint?.ctaPattern = value
        case "reelVoice.paragraphLength": model.reelVoiceFingerprint?.paragraphLength = value
        case "reelVoice.powerWords": model.reelVoiceFingerprint?.powerWords = value.components(separatedBy: ", ")
        case "reelVoice.signaturePhrases": model.reelVoiceFingerprint?.signaturePhrases = value.components(separatedBy: ", ")
        case "reelVoice.blacklistedPhrases": model.reelVoiceFingerprint?.blacklistedPhrases = value.components(separatedBy: ", ")
        case "reelVoice.formattingQuirks": model.reelVoiceFingerprint?.formattingQuirks = value.components(separatedBy: ", ")
        case "reelVoice.avgSentenceLength":
            if let d = Double(value.replacingOccurrences(of: " words", with: "")) {
                model.reelVoiceFingerprint?.avgSentenceLength = d
            }
        case "reelVoice.maxSentenceLength":
            if let i = Int(value.replacingOccurrences(of: " words", with: "")) {
                model.reelVoiceFingerprint?.maxSentenceLength = i
            }
        // Thread voice
        case "threadVoice.readingLevel": model.threadVoiceFingerprint?.readingLevel = value
        case "threadVoice.punctuationStyle": model.threadVoiceFingerprint?.punctuationStyle = value
        case "threadVoice.ctaPattern": model.threadVoiceFingerprint?.ctaPattern = value
        case "threadVoice.paragraphLength": model.threadVoiceFingerprint?.paragraphLength = value
        case "threadVoice.powerWords": model.threadVoiceFingerprint?.powerWords = value.components(separatedBy: ", ")
        case "threadVoice.signaturePhrases": model.threadVoiceFingerprint?.signaturePhrases = value.components(separatedBy: ", ")
        case "threadVoice.blacklistedPhrases": model.threadVoiceFingerprint?.blacklistedPhrases = value.components(separatedBy: ", ")
        case "threadVoice.formattingQuirks": model.threadVoiceFingerprint?.formattingQuirks = value.components(separatedBy: ", ")
        case "threadVoice.avgSentenceLength":
            if let d = Double(value.replacingOccurrences(of: " words", with: "")) {
                model.threadVoiceFingerprint?.avgSentenceLength = d
            }
        case "threadVoice.maxSentenceLength":
            if let i = Int(value.replacingOccurrences(of: " words", with: "")) {
                model.threadVoiceFingerprint?.maxSentenceLength = i
            }
        // Performance (overall)
        case "perf.optimalLength": model.performanceFingerprint.optimalLength = value
        case "perf.bestTopics": model.performanceFingerprint.bestTopics = value.components(separatedBy: ", ")
        case "perf.bestBeatPatterns": model.performanceFingerprint.bestBeatPatterns = value.components(separatedBy: ", ")
        case "perf.engagementTriggers": model.performanceFingerprint.engagementTriggers = value.components(separatedBy: ", ")
        // Reel performance
        case "reelPerf.optimalLength": model.reelPerformanceFingerprint?.optimalLength = value
        case "reelPerf.bestTopics": model.reelPerformanceFingerprint?.bestTopics = value.components(separatedBy: ", ")
        case "reelPerf.bestBeatPatterns": model.reelPerformanceFingerprint?.bestBeatPatterns = value.components(separatedBy: ", ")
        case "reelPerf.engagementTriggers": model.reelPerformanceFingerprint?.engagementTriggers = value.components(separatedBy: ", ")
        // Thread performance
        case "threadPerf.optimalLength": model.threadPerformanceFingerprint?.optimalLength = value
        case "threadPerf.bestTopics": model.threadPerformanceFingerprint?.bestTopics = value.components(separatedBy: ", ")
        case "threadPerf.bestBeatPatterns": model.threadPerformanceFingerprint?.bestBeatPatterns = value.components(separatedBy: ", ")
        case "threadPerf.engagementTriggers": model.threadPerformanceFingerprint?.engagementTriggers = value.components(separatedBy: ", ")
        // Audience
        case "audience.primaryAudience": model.audienceModel.primaryAudience = value
        case "audience.topPainPoints": model.audienceModel.topPainPoints = value.components(separatedBy: ", ")
        case "audience.aspirationalOutcomes": model.audienceModel.aspirationalOutcomes = value.components(separatedBy: ", ")
        case "audience.commonObjections": model.audienceModel.commonObjections = value.components(separatedBy: ", ")
        case "audience.audienceLanguage": model.audienceModel.audienceLanguage = value.components(separatedBy: ", ")
        // Niche
        case "niche.specificNiche": model.nicheAndPositioning.specificNiche = value
        case "niche.uniqueAngle": model.nicheAndPositioning.uniqueAngle = value
        case "niche.coreBeliefs": model.nicheAndPositioning.coreBeliefs = value.components(separatedBy: ", ")
        case "niche.enemies": model.nicheAndPositioning.enemies = value.components(separatedBy: ", ")
        case "niche.uniqueMechanism": model.nicheAndPositioning.uniqueMechanism = value
        default: break
        }
    }
}

// MARK: - Preview

#Preview("Intelligence Model View") {
    IntelligenceModelView(
        model: .constant(ClientIntelligenceModel()),
        overrides: .constant([]),
        editingMetricId: .constant(nil),
        editingMetricKey: .constant(""),
        editingMetricValue: .constant(""),
        showUpdateButton: true,
        onUpdateRequested: {}
    )
    .frame(width: 500, height: 700)
    .padding()
}
