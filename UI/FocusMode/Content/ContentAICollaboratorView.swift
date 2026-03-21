// CosmoOS/UI/FocusMode/Content/ContentAICollaboratorView.swift
// Floating AI Collaborator popover for Content Focus Mode
// February 2026

import SwiftUI

// MARK: - ContentAICollaboratorView

/// Floating popover chat UI for the AI Collaborator.
/// Anchored to the bottom-right of the Content Focus Mode view.
/// Triggered by AI button in bottom bar or Cmd+J.
struct ContentAICollaboratorView: View {
    @ObservedObject var engine: UnifiedWritingEngine
    @Binding var isVisible: Bool
    let contentAtom: Atom
    @Binding var state: ContentFocusModeState

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showCompletedSteps = false
    @StateObject private var scorecardEngine = ContentScorecardEngine()
    @StateObject private var redTeamEngine = RedTeamEngine()
    @State private var showStructuralAlignment = false
    @State private var showSlideAnalysis = false

    private let popoverWidth: CGFloat = 380
    private let popoverMaxHeight: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(DS.border)
            quickActionPills
            Divider().background(DS.border)

            messageList
            Divider().background(DS.border)
            inputBar

            // Undo toast
            if state.showUndoToast {
                undoToast
            }
        }
        .frame(width: popoverWidth)
        .frame(maxHeight: popoverMaxHeight)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
        .onAppear {
            isInputFocused = true
        }
        .onChange(of: state.showUndoToast) { _, newValue in
            if newValue {
                // Auto-dismiss after 5 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.3)) {
                            state.showUndoToast = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.accent)

            Text("AI COLLABORATOR")
                .dsSectionLabel()

            Spacer()

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Quick Action Pills

    private var isPolishPhase: Bool {
        state.currentStep == .polish
    }

    private var quickActionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isPolishPhase {
                    polishPills
                } else {
                    defaultPills
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var defaultPills: some View {
        quickActionButton("Write draft", icon: "doc.text") {
            Task { await engine.generateDraft() }
        }
        quickActionButton("Suggest outline", icon: "list.bullet") {
            Task { await engine.suggestOutline() }
        }
        quickActionPill("Improve hook", icon: "text.quote")
        quickActionPill("Research topic", icon: "magnifyingglass")
    }

    @ViewBuilder
    private var polishPills: some View {
        quickActionPill("Improve Hook", icon: "text.quote")
        quickActionPill("Fix Voice Drift", icon: "waveform")
        quickActionPill("Strengthen CTA", icon: "megaphone")
        runScorecardPill
        runRedTeamPill
    }

    private var runScorecardPill: some View {
        Button {
            Task { await engine.runScorecard() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 10))
                Text("Run Full Scorecard")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 10)
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
        .disabled(scorecardEngine.isEvaluating || engine.isProcessing)
    }

    private func quickActionPill(_ label: String, icon: String) -> some View {
        Button {
            sendMessage(label)
        } label: {
            quickActionPillLabel(label, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(engine.isProcessing)
    }

    private func quickActionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            quickActionPillLabel(label, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(engine.isProcessing)
    }

    private func quickActionPillLabel(_ label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 10)
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

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    // Scorecard card at top when in polish phase
                    if isPolishPhase {
                        scorecardSection
                        redTeamSection
                    }

                    if engine.messages.isEmpty && !isPolishPhase {
                        emptyStateView
                    }

                    // Cap displayed messages to last 30 to bound render cost.
                    // With 48+ messages, ForEach over all of them causes O(N) diffing
                    // on every @Published change, leading to 100% CPU.
                    ForEach(engine.messages.suffix(30)) { message in
                        WritingMessageBubble(message: message)
                            .id(message.id)
                    }

                    if engine.isProcessing {
                        inlineToolProgress
                            .id("inlineToolProgress")
                    }

                    if let error = engine.error {
                        errorBanner(error)
                    }
                }
                .padding(14)
            }
            .onChange(of: engine.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: engine.isProcessing) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: engine.toolChainSteps.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(DS.accent.opacity(0.3))

            Text("Ask me anything about your content")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.orange.opacity(0.9))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.3)) {
            if engine.isProcessing {
                proxy.scrollTo("inlineToolProgress", anchor: .bottom)
            } else if let lastId = engine.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - Inline Tool Progress (replaces old top-level toolChainView)

    /// Inline progress view shown at the bottom of the message list where the AI is about to reply.
    /// Groups completed steps in a collapsible dropdown, shows active step prominently in gray.
    private var inlineToolProgress: some View {
        let completedSteps = engine.toolChainSteps.filter { $0.status == .completed }
        let activeStep = engine.toolChainSteps.last(where: { $0.status == .executing })

        return VStack(alignment: .leading, spacing: 6) {
            // Completed steps — collapsible dropdown
            if !completedSteps.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCompletedSteps.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showCompletedSteps ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(completedSteps.count) action\(completedSteps.count == 1 ? "" : "s") completed")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)

                if showCompletedSteps {
                    completedStepsList(completedSteps)
                }
            }

            // Currently active step
            if let active = activeStep {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(DS.textSecondary)
                    Text(active.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
                .transition(.opacity)
            } else {
                // No active tool call — show typing dots
                CollaboratorTypingIndicator()
            }

            // Cancel button
            Button {
                engine.cancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.surfaceElevated)
                    .clipShape(.rect(cornerRadius: DS.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func completedStepsList(_ steps: [WritingToolChainStep]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(steps) { step in
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                    Text(step.label)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(.leading, 4)
        .transition(.opacity)
    }

    // MARK: - Undo Toast

    private var undoToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.accent)

            Text(state.undoToastMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.text)

            Spacer()

            Button(action: {
                undoLastAIEdit()
            }) {
                Text("Undo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(DS.accentSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.easeOut(duration: 0.3)) {
                    state.showUndoToast = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DS.surfaceElevated)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func undoLastAIEdit() {
        if let edit = state.popAIUndo() {
            state.draftContent = edit.previousContent
            state.save()
            withAnimation(.easeOut(duration: 0.3)) {
                state.showUndoToast = false
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your content...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.command) {
                        sendCurrentMessage()
                    }
                }

            if engine.isProcessing {
                Button {
                    engine.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Cancel request")
            } else {
                Button {
                    sendCurrentMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? DS.textMuted
                                : DS.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(DS.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Scorecard Section

    @ViewBuilder
    private var scorecardSection: some View {
        if scorecardEngine.isEvaluating {
            scorecardLoadingView
        } else if let scorecard = state.contentScorecard {
            scorecardCard(scorecard)
        }
    }

    private var scorecardLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(DS.accent)

            Text(scorecardEngine.evaluationProgress.isEmpty ? "Evaluating draft..." : scorecardEngine.evaluationProgress)
                .font(.system(size: 12))
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func scorecardCard(_ scorecard: ContentScorecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.accent)
                Text("Content Scorecard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                Spacer()
                Text("Confidence: \(scorecard.overallConfidence)%")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
            }

            // Score circles row
            HStack(spacing: 16) {
                scoreCircle(score: scorecard.hookScore.score, label: "Hook", category: scorecard.hookScore.colorCategory)
                scoreCircle(score: scorecard.copyScore.score, label: "Copy", category: scorecard.copyScore.colorCategory)
                scoreCircle(score: scorecard.ctaScore.score, label: "CTA", category: scorecard.ctaScore.colorCategory)
            }
            .frame(maxWidth: .infinity)

            // Voice match bar
            if scorecard.voiceMatch.percentage >= 0 {
                voiceMatchBar(percentage: scorecard.voiceMatch.percentage)
            }

            // Fix buttons for low-scoring areas
            lowScoreFixButtons(scorecard)

            // Voice drifts
            if !scorecard.voiceMatch.drifts.isEmpty {
                voiceDriftSection(scorecard.voiceMatch.drifts)
            }

            // Expandable structural alignment
            structuralAlignmentSection(scorecard.structuralAlignment)

            // Expandable slide analysis
            if !scorecard.slideAnalysis.isEmpty {
                slideAnalysisSection(scorecard.slideAnalysis)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    private func scoreCircle(score: Double, label: String, category: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(DS.border, lineWidth: 4)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(score / 10.0))
                    .stroke(
                        scoreColor(category),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.1f", score))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text)
            }
            .shadow(color: scoreColor(category).opacity(0.15), radius: 8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textSecondary)
        }
    }

    private func scoreColor(_ category: String) -> Color {
        switch category {
        case "green": return Color(hex: "10B981")
        case "yellow": return Color(hex: "F59E0B")
        case "red": return Color(hex: "EF4444")
        default: return Color.gray
        }
    }

    private func voiceMatchBar(percentage: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Voice Match")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.borderSubtle)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.accent)
                        .frame(width: geo.size.width * CGFloat(percentage / 100.0), height: 6)
                        .shadow(color: DS.accentGlow, radius: 4)
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private func lowScoreFixButtons(_ scorecard: ContentScorecard) -> some View {
        let lowAreas: [(String, String)] = {
            var areas: [(String, String)] = []
            if scorecard.hookScore.score < 7 {
                let suggestion = scorecard.hookScore.suggestions.first ?? "Improve hook strength"
                areas.append(("Hook", "Fix the hook: \(suggestion)"))
            }
            if scorecard.copyScore.score < 7 {
                let suggestion = scorecard.copyScore.suggestions.first ?? "Improve copy quality"
                areas.append(("Copy", "Fix the copy: \(suggestion)"))
            }
            if scorecard.ctaScore.score < 7 {
                let suggestion = scorecard.ctaScore.suggestions.first ?? "Strengthen the CTA"
                areas.append(("CTA", "Fix the CTA: \(suggestion)"))
            }
            return areas
        }()

        if !lowAreas.isEmpty {
            HStack(spacing: 6) {
                ForEach(lowAreas, id: \.0) { area, message in
                    fixButton(label: "Fix \(area)", message: message)
                }
            }
        }
    }

    private func fixButton(label: String, message: String) -> some View {
        Button {
            sendMessage(message)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(engine.isProcessing)
    }

    private func voiceDriftSection(_ drifts: [VoiceDrift]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice Drifts (\(drifts.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textSecondary)

            ForEach(drifts.prefix(3)) { drift in
                voiceDriftRow(drift)
            }
        }
    }

    private func voiceDriftRow(_ drift: VoiceDrift) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Line \(drift.lineNumber): \(drift.issue)")
                .font(.system(size: 10))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\"\(drift.draftText.prefix(40))...\"")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                Spacer()
                Button {
                    sendMessage("Fix voice drift on line \(drift.lineNumber): \(drift.suggestion)")
                } label: {
                    Text("Fix")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(DS.accentSoft)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(engine.isProcessing)
            }
        }
        .padding(6)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private func structuralAlignmentSection(_ alignment: StructuralAlignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showStructuralAlignment.toggle()
                }
            } label: {
                structuralAlignmentHeader(alignment)
            }
            .buttonStyle(.plain)

            if showStructuralAlignment {
                structuralAlignmentContent(alignment)
            }
        }
    }

    @ViewBuilder
    private func structuralAlignmentHeader(_ alignment: StructuralAlignment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: showStructuralAlignment ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
            Text("Structural Alignment")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text("\(Int(alignment.alignmentScore))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(DS.textSecondary)
    }

    @ViewBuilder
    private func structuralAlignmentContent(_ alignment: StructuralAlignment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DRAFT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.textMuted)
                    ForEach(alignment.draftBeats, id: \.self) { beat in
                        Text(beat)
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("RECOMMENDED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.textMuted)
                    ForEach(alignment.recommendedBeats, id: \.self) { beat in
                        Text(beat)
                            .font(.system(size: 10))
                            .foregroundStyle(DS.accent.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !alignment.suggestions.isEmpty {
                ForEach(alignment.suggestions, id: \.self) { suggestion in
                    Text("- \(suggestion)")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
        .padding(8)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
    }

    private func slideAnalysisSection(_ slides: [SlideAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSlideAnalysis.toggle()
                }
            } label: {
                slideAnalysisHeader(slides)
            }
            .buttonStyle(.plain)

            if showSlideAnalysis {
                slideAnalysisContent(slides)
            }
        }
    }

    @ViewBuilder
    private func slideAnalysisHeader(_ slides: [SlideAnalysis]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: showSlideAnalysis ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
            Text("Slide-by-Slide Analysis")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text("\(slides.count) sections")
                .font(.system(size: 10))
        }
        .foregroundStyle(DS.textSecondary)
    }

    @ViewBuilder
    private func slideAnalysisContent(_ slides: [SlideAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(slides) { slide in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Section \(slide.sectionIndex + 1)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                        Text("[\(slide.beatLabel)]")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DS.accent.opacity(0.7))
                    }
                    Text(slide.swipeComparison)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(3)
                    Text(slide.suggestion)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "F59E0B").opacity(0.8))
                        .lineLimit(2)
                }
                .padding(6)
                .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Scorecard Actions
    // Scorecard is now run through the UnifiedWritingEngine.
    // Results arrive via .unifiedEngineScorecardResult notification.

    // MARK: - Red Team

    private var runRedTeamPill: some View {
        Button {
            runRedTeam()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 10))
                Text("Run Red Team")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.red.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(redTeamEngine.isEvaluating || engine.isProcessing)
    }

    @ViewBuilder
    private var redTeamSection: some View {
        if redTeamEngine.isEvaluating {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.red.opacity(0.7))
                Text(redTeamEngine.evaluationProgress.isEmpty ? "Running adversarial analysis..." : redTeamEngine.evaluationProgress)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if let result = state.redTeamResult, !result.cards.isEmpty {
            redTeamCard(result)
        }
    }

    private func redTeamCard(_ result: RedTeamResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
                Text("Red Team Analysis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                Spacer()
                if result.highRiskCount > 0 {
                    Text("\(result.highRiskCount) HIGH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                }
                if result.mediumRiskCount > 0 {
                    Text("\(result.mediumRiskCount) MED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.orange))
                }
            }

            // Risk cards
            ForEach(result.cards) { card in
                riskCardRow(card)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(Color.red.opacity(0.15), lineWidth: 1)
        )
    }

    private func riskCardRow(_ card: RiskCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + severity + type
            HStack(spacing: 6) {
                Circle()
                    .fill(card.severity.color)
                    .frame(width: 6, height: 6)
                Text(card.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.text)
                Spacer()
                Text(card.riskType.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(DS.surface)
                    )
            }

            // Evidence quote
            if !card.evidence.isEmpty {
                Text("\"" + card.evidence.prefix(120) + (card.evidence.count > 120 ? "..." : "") + "\"")
                    .font(.system(size: 11).italic())
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }

            // Metric comparison
            if !card.metric.isEmpty {
                Text(card.metric)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(card.severity.color.opacity(0.9))
            }

            // Recommendation + Fix button
            HStack(alignment: .top, spacing: 8) {
                Text(card.recommendation)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !card.fixPrompt.isEmpty {
                    Button {
                        sendMessage(card.fixPrompt)
                    } label: {
                        Text("Fix")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(card.severity.color.opacity(0.8))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(card.severity.color.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(card.severity.color.opacity(0.1), lineWidth: 1)
        )
    }

    private func runRedTeam() {
        Task {
            await redTeamEngine.evaluate(contentAtom: contentAtom, state: state)
            state.redTeamResult = redTeamEngine.result
        }
    }

    // MARK: - Actions

    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        sendMessage(text)
    }

    private func sendMessage(_ text: String) {
        Task {
            _ = await engine.sendMessage(text, phase: state.currentStep)
        }
    }

}

// MARK: - Writing Message Bubble

private struct WritingMessageBubble: View {
    let message: WritingMessage

    private var isUser: Bool { message.role == .user }
    private var isAssistant: Bool { message.role == .assistant }
    private var isSystem: Bool { message.role == .system }
    private var isToolResult: Bool { message.role == .toolResult }

    /// Whether this message should be hidden (tool results, empty assistant messages).
    private var isHidden: Bool {
        if isToolResult { return true }
        if isAssistant && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.toolCalls == nil {
            return true
        }
        return false
    }

    var body: some View {
        // Use @ViewBuilder control flow instead of AnyView to preserve SwiftUI's
        // diffing cache. AnyView forces full view recreation on every re-render.
        if isHidden {
            EmptyView()
        } else {
            messageContent
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            // Timestamp + role indicator
            HStack(spacing: 4) {
                if isAssistant {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.accent)
                }
                if isSystem {
                    Image(systemName: "arrow.right.arrow.left")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                }
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            // Tool call badges (inline)
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                toolCallBadges(toolCalls)
            }

            // Message content
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(isSystem ? DS.textSecondary : DS.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .fill(isUser ? DS.accentSoft :
                                  isSystem ? DS.border.opacity(0.3) :
                                  DS.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.border, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }

            // Copy button for assistant messages
            if isAssistant && !message.content.isEmpty {
                assistantMessageActions
            }
        }
    }

    @ViewBuilder
    private func toolCallBadges(_ toolCalls: [WritingToolCall]) -> some View {
        HStack(spacing: 4) {
            ForEach(toolCalls) { call in
                HStack(spacing: 3) {
                    Image(systemName: iconForTool(call.toolName))
                        .font(.system(size: 9))
                    Text(labelForTool(call.toolName))
                        .font(.system(size: 10, weight: .medium))
                    statusIcon(call.status)
                }
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(DS.accent.opacity(0.1))
                )
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: WritingToolCall.ToolCallStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
        case .executing:
            ProgressView()
                .scaleEffect(0.4)
                .tint(DS.accent)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.red)
        case .pending:
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
        }
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "think": return "brain"
        case "update_outline": return "list.bullet"
        case "add_hooks": return "sparkles"
        case "set_description": return "doc.text"
        case "write_draft": return "pencil.and.outline"
        case "edit_section": return "scissors"
        case "search_swipes": return "magnifyingglass"
        case "get_client_profile": return "person.crop.circle"
        case "run_scorecard": return "checkmark.seal"
        default: return "gear"
        }
    }

    private func labelForTool(_ name: String) -> String {
        switch name {
        case "think": return "Reasoning"
        case "update_outline": return "Outline"
        case "add_hooks": return "Hooks"
        case "set_description": return "Description"
        case "write_draft": return "Draft"
        case "edit_section": return "Edit"
        case "search_swipes": return "Search"
        case "get_client_profile": return "Profile"
        case "run_scorecard": return "Scorecard"
        default: return name
        }
    }

    private var assistantMessageActions: some View {
        HStack(spacing: 10) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                    Text("Copy")
                        .font(.system(size: 10))
                }
                .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Typing Indicator

private struct CollaboratorTypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(DS.accent.opacity(0.5))

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(DS.accent)
                        .frame(width: 5, height: 5)
                        .opacity(animating ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: DS.radiusSmall).fill(DS.surfaceElevated))

            Spacer()
        }
        .onAppear { animating = true }
    }
}

