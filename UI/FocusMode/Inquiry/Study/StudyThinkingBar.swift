// CosmoOS/UI/FocusMode/Inquiry/Study/StudyThinkingBar.swift
// The Study's instrument — the inline assistant bar's language, tuned for
// inquiry: one near-opaque card that stretches from a quiet capsule into the
// composer on focus (the Dynamic Island move), with a footer of small
// hover-lit action chips that teach their shortcuts in place (Raycast's law).
// Content is CLIPPED to the same shape as the surface so nothing ever paints
// outside the card mid-stretch. Successor of InquiryAssistantDock; the
// routing brain (submitDockText, prefix parser, suggestions) is untouched.

import SwiftUI

@MainActor
struct StudyThinkingBar: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    @Binding var draft: String
    @FocusState.Binding var isFocused: Bool

    @State private var showSuggestions = false
    @State private var suggestionsHeight: CGFloat = 0

    private var isEngaged: Bool { isFocused || !draft.isEmpty }

    var body: some View {
        barBody
            // The clip is what makes the stretch read as one object: content
            // never paints past the surface, even mid-spring on a growing
            // multi-line draft (the assistant bar's move).
            .clipShape(barShape)
            .background {
                barShape
                    .fill(DS.surfaceCard.opacity(isEngaged ? 0.97 : 1.0))
                    .shadow(
                        color: .black.opacity(isEngaged ? 0.14 : 0.08),
                        radius: isEngaged ? 22 : 10,
                        y: isEngaged ? 10 : 4
                    )
            }
            .overlay { barShape.stroke(borderColor, lineWidth: 1) }
            .frame(maxWidth: isEngaged ? StudyMetrics.barMaxWidthFocused : StudyMetrics.barMaxWidthRest)
            .overlay(alignment: .topLeading) { suggestionsOverlay }
            // ONE spring drives the whole stretch — width, height, radius,
            // fill, shadow, and border together.
            .animation(ProMotionSprings.focusTransition, value: isEngaged)
            .animation(ProMotionSprings.gentle, value: showSuggestions)
            .onChange(of: viewModel.dockFocusTick) {
                isFocused = true
            }
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isEngaged ? 22 : 26, style: .continuous)
    }

    private var borderColor: Color {
        isFocused ? DS.accent.opacity(0.36) : DS.borderSubtle
    }

    // MARK: - Bar anatomy

    private var barBody: some View {
        VStack(spacing: 0) {
            composerRow
            if isEngaged {
                actionsFooter
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private var composerRow: some View {
        HStack(alignment: .center, spacing: DS.space10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)

            if let activity = viewModel.sourceActivityLine, draft.isEmpty, !isFocused {
                activityLine(activity)
            } else {
                field
            }

            if !isEngaged {
                scopeChip
            }
            sendButton
        }
        .frame(minHeight: 32)
    }

    private var field: some View {
        TextField("Think out loud, paste a URL, or type / for commands", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.body)
            .foregroundStyle(DS.text)
            .focused($isFocused)
            .lineLimit(1...4)
            .onSubmit(submit)
            .onChange(of: draft) { _, newValue in
                showSuggestions = shouldShowSuggestions(for: newValue) && isFocused
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { showSuggestions = false }
            }
    }

    private func activityLine(_ activity: String) -> some View {
        HStack(spacing: DS.space8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
            Text(activity)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    /// Where this thought lands — scope lives inside the instrument.
    private var scopeChip: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: "arrow.turn.down.right")
                .font(DS.caption2.weight(.semibold))
                .accessibilityHidden(true)
            Text(scopeTitle)
                .font(DS.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 4)
        .background(DS.accentSoft, in: Capsule())
        .fixedSize()
        .help("Captures save to: \(viewModel.activeQuestionTitle)")
        .accessibilityLabel("Saving to \(viewModel.activeQuestionTitle)")
    }

    private var scopeTitle: String {
        let title = viewModel.activeQuestionTitle
        return title.count > 26 ? "\(title.prefix(24))…" : title
    }

    private var sendButton: some View {
        Button(action: submit) {
            Group {
                if viewModel.aiBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up")
                        .font(DS.caption.weight(.bold))
                }
            }
            .frame(width: 28, height: 28)
            .background(isDraftEmpty ? AnyShapeStyle(DS.glassInputFill) : AnyShapeStyle(DS.accent), in: Circle())
            .foregroundStyle(isDraftEmpty ? DS.textMuted : DS.textOnAccent)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDraftEmpty || viewModel.aiBusy)
        .keyboardShortcut(.return, modifiers: [])
        .help("Send")
        .accessibilityLabel(viewModel.aiBusy ? "Thinking" : "Send")
    }

    // MARK: - Action chips footer

    /// Small hover-lit chips along the bar's foot; the scope chip anchors the
    /// trailing end. Everything is sized so the row never crowds the surface.
    private var actionsFooter: some View {
        HStack(spacing: DS.space6) {
            StudyFooterActionChip(label: "Summarize", shortcut: "⌘⇧1") {
                Task { await viewModel.runAIPrompt("Summarize the current state of inquiry on \(viewModel.activeQuestionTitle) into 4–5 sentences with hedges.") }
            }
            StudyFooterActionChip(label: "Challenge", shortcut: "⌘⇧2") {
                Task { await viewModel.submitDockText("/challenge") }
            }
            StudyFooterActionChip(label: "Branch", shortcut: "⌘⇧3") {
                Task { await viewModel.runAIPrompt("Propose 3 child branch questions that would advance the inquiry on \(viewModel.activeQuestionTitle).") }
            }
            StudyFooterActionChip(label: "Scout", shortcut: "⌘⇧4") {
                Task { await viewModel.refreshSourceRecommendations(query: nil, mode: .deepScout) }
            }
            Spacer(minLength: DS.space8)
            scopeChip
        }
        .padding(.top, DS.space8)
    }

    // MARK: - Slash suggestions (floats above the bar)

    @ViewBuilder
    private var suggestionsOverlay: some View {
        if showSuggestions && !suggestions.isEmpty {
            InquiryDockSuggestionsView(suggestions: suggestions, onSelect: applySuggestion)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    suggestionsHeight = height
                }
                .offset(y: -(suggestionsHeight + DS.space8))
                .opacity(suggestionsHeight > 0 ? 1 : 0)
                .zIndex(1)
                .transition(.opacity)
        }
    }

    // MARK: - Logic (identical to the dock it replaces)

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        showSuggestions = false
        Task { await viewModel.submitDockText(text) }
    }

    private func shouldShowSuggestions(for draft: String) -> Bool {
        guard draft.hasPrefix("/") else { return false }
        return !draft.contains(" ") || draft.trimmingCharacters(in: .whitespaces) == "/"
    }

    private var slashFilter: String {
        guard draft.hasPrefix("/") else { return "" }
        return String(draft.dropFirst())
            .split(separator: " ").first.map(String.init) ?? ""
    }

    private var suggestions: [InquiryDockSuggestion] {
        Array(InquiryDockSuggestion.all.filter { $0.matchesSlashFilter(slashFilter) }.prefix(12))
    }

    private func applySuggestion(_ suggestion: InquiryDockSuggestion) {
        draft = "\(suggestion.token) "
        showSuggestions = false
        isFocused = true
    }
}

/// One small taught action: a quiet chip that lights on hover (wash + ink)
/// and whispers its shortcut beside the label.
@MainActor
private struct StudyFooterActionChip: View {
    let label: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                Text(label)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(isHovered ? DS.text : DS.textSecondary)
                Text(shortcut)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .background(isHovered ? DS.glassInputFill : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("\(label) (\(shortcut))")
        .accessibilityLabel("\(label), shortcut \(shortcut)")
    }
}
