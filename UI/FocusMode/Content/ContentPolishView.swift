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
    @State private var suggestions: [AISuggestion] = []
    @State private var isGeneratingSuggestions = false
    @State private var showPolishSettings = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top: Readability dashboard
            readabilityDashboard
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()
                .background(Color.white.opacity(0.08))

            // Center + Right: Annotated text + AI suggestions
            HStack(spacing: 0) {
                // Center: Annotated text with legend
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
                                .foregroundColor(.white.opacity(0.5))
                                .padding(40)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .background(Color.white.opacity(0.08))

                // Right: AI suggestions sidebar
                suggestionsSidebar
                    .frame(width: 320)
            }
        }
        .background(CosmoColors.thinkspaceVoid)
        .onAppear {
            runAnalysis()
        }
        .onChange(of: state.draftContent) { _, _ in
            runAnalysis()
        }
        .sheet(isPresented: $showPolishSettings) {
            polishSettingsSheet
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 80)
    }

    private var readabilityCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
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
                    .foregroundColor(.white)
                Text(analysis?.readabilityRating.label ?? "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(readabilityColor)
            }
        }
    }

    private var readabilityColor: Color {
        guard let analysis = analysis else { return .gray }
        switch analysis.readabilityRating {
        case .good: return Color(hex: "10B981")     // Green
        case .moderate: return Color(hex: "F59E0B")  // Yellow
        case .difficult: return Color(hex: "EF4444") // Red
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
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
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
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Suggestions Sidebar

    private var suggestionsSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Suggestions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: { showPolishSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Generate button
            Button(action: {
                Task { await generateSuggestions() }
            }) {
                HStack(spacing: 8) {
                    if isGeneratingSuggestions {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isGeneratingSuggestions ? "Generating..." : "Generate Suggestions")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(CosmoColors.blockContent)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingSuggestions)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "EF4444"))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Suggestion cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        suggestionCard(suggestion)
                    }

                    if suggestions.isEmpty && !isGeneratingSuggestions {
                        VStack(spacing: 8) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.2))
                            Text("No suggestions yet")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.4))
                            Text("Click Generate to get AI writing feedback")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(CosmoColors.thinkspaceSecondary)
    }

    private func suggestionCard(_ suggestion: AISuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Original text (strikethrough)
            Text(suggestion.originalText)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .strikethrough(true, color: .white.opacity(0.3))
                .lineLimit(3)

            // Arrow
            Image(systemName: "arrow.down")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .center)

            // Suggested replacement
            Text(suggestion.suggestedText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(3)

            // Reason
            Text(suggestion.reason)
                .font(.system(size: 11).italic())
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(2)

            // Accept / Dismiss buttons
            HStack(spacing: 8) {
                Button(action: { acceptSuggestion(suggestion) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Accept")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "10B981"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "10B981").opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: { dismissSuggestion(suggestion) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Dismiss")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "EF4444"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "EF4444").opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(CosmoColors.thinkspaceTertiary)
        .cornerRadius(10)
    }

    // MARK: - Polish Settings Sheet

    private var polishSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Polish Settings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { showPolishSettings = false }
                    .foregroundColor(CosmoColors.blockContent)
            }
            .padding(.bottom, 4)

            Text("Custom system prompt for AI suggestions. This guides the AI's writing style and focus areas.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))

            TextEditor(text: $state.polishSystemPrompt)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(8)
                .background(CosmoColors.thinkspaceTertiary)
                .cornerRadius(8)

            Button(action: {
                state.polishSystemPrompt = PolishEngine.defaultSystemPrompt
                state.save()
            }) {
                Text("Reset to Default")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(24)
        .frame(width: 500, height: 400)
        .background(CosmoColors.thinkspaceSecondary)
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

    private func generateSuggestions() async {
        guard let analysis = analysis else { return }
        isGeneratingSuggestions = true
        errorMessage = nil

        do {
            let prompt = state.polishSystemPrompt.isEmpty ? nil : state.polishSystemPrompt
            suggestions = try await PolishEngine.shared.generateSuggestions(
                text: state.draftContent,
                analysis: analysis,
                systemPrompt: prompt
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isGeneratingSuggestions = false
    }

    private func acceptSuggestion(_ suggestion: AISuggestion) {
        // Replace original text with suggested text in the draft
        if let range = state.draftContent.range(of: suggestion.originalText) {
            state.draftContent.replaceSubrange(range, with: suggestion.suggestedText)
        }
        suggestions.removeAll { $0.id == suggestion.id }
        // Persist the change
        state.lastModified = Date()
        state.save()
        // Re-analyze after accepting a change
        runAnalysis()
    }

    private func dismissSuggestion(_ suggestion: AISuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
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
                value: NSColor.systemYellow.withAlphaComponent(0.15),
                range: range
            )
        }

        // Very complex sentences: red background
        for range in analysis.veryComplexSentenceRanges {
            guard range.location + range.length <= nsLength else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: NSColor.systemRed.withAlphaComponent(0.15),
                range: range
            )
        }

        // Passive voice: blue background
        for range in analysis.passiveVoiceRanges {
            guard range.location + range.length <= nsLength else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: NSColor.systemBlue.withAlphaComponent(0.15),
                range: range
            )
        }

        // Adverbs: purple background
        for range in analysis.adverbRanges {
            guard range.location + range.length <= nsLength else { continue }
            attributed.addAttribute(
                .backgroundColor,
                value: NSColor.systemPurple.withAlphaComponent(0.15),
                range: range
            )
        }

        return attributed
    }
}
