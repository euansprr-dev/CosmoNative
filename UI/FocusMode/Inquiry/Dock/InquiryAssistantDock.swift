// CosmoOS/UI/FocusMode/Inquiry/Dock/InquiryAssistantDock.swift
// Permanent assistant dock for the inquiry workspace, styled after the inline
// assistant system: floating card surface, context pills, streaming replies.
// Routing brain stays submitDockText + InquiryDockPrefixParser — every prefix
// command and the suggestions popover behave exactly as before.

import SwiftUI

@MainActor
struct InquiryAssistantDock: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    @Binding var dockDraft: String
    @FocusState.Binding var dockFocused: Bool

    @State private var showSuggestions: Bool = false
    @State private var suggestionsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            contextPillsRow
            composerRow
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .stroke(dockFocused ? DS.accent.opacity(0.35) : DS.sepiaBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .padding(.horizontal, DS.space20)
        .padding(.bottom, DS.space12)
        .overlay(alignment: .topLeading) { suggestionsOverlay }
        .animation(ProMotionSprings.gentle, value: showSuggestions)
        .animation(ProMotionSprings.gentle, value: dockFocused)
    }

    // MARK: - Context pills

    private var contextPillsRow: some View {
        HStack(spacing: DS.space6) {
            questionPill
            if let sourceTitle = viewModel.activeSourceTab?.title {
                contextPill(icon: "doc.text", label: sourceTitle, tint: DS.green)
            }
            Spacer(minLength: 0)
            if viewModel.aiBusy {
                thinkingIndicator
            }
        }
    }

    private var questionPill: some View {
        Menu {
            ForEach(viewModel.questions, id: \.uuid) { question in
                Button(question.title ?? "Untitled") {
                    viewModel.setActiveQuestion(question.uuid)
                }
            }
        } label: {
            contextPill(
                icon: "questionmark.bubble",
                label: viewModel.activeQuestionTitle,
                tint: DS.accent
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Active question: \(viewModel.activeQuestionTitle). Tap to switch.")
    }

    private func contextPill(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(label)
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 0.5))
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
            Text("Thinking…")
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textTertiary)
        }
    }

    // MARK: - Composer

    private var composerRow: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 30, height: 30)
                .background(DS.accentSoft, in: Circle())
                .accessibilityHidden(true)

            if let activity = viewModel.sourceActivityLine, dockDraft.isEmpty {
                activityLine(activity)
            } else {
                dockField
            }

            sendButton
        }
    }

    private var dockField: some View {
        TextField("Think out loud, paste a URL, or type / for commands", text: $dockDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(CosmoTypography.body)
            .focused($dockFocused)
            .lineLimit(1...4)
            .onSubmit(submit)
            .onChange(of: dockDraft) { _, newValue in
                showSuggestions = shouldShowSuggestions(for: newValue) && dockFocused
            }
            .onChange(of: dockFocused) { _, isFocused in
                if !isFocused { showSuggestions = false }
            }
    }

    private func activityLine(_ activity: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
            Text(activity)
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .background(isDraftEmpty ? DS.surfaceHover : DS.accent, in: Circle())
                .foregroundStyle(isDraftEmpty ? CosmoColors.textTertiary : DS.textOnAccent)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDraftEmpty)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityLabel("Send")
    }

    // MARK: - Slash command menu

    /// Floats fully above the dock card: anchored at the card's top, then
    /// shifted up by its own measured height. Hidden until measured to avoid
    /// a one-frame flash at the wrong position.
    @ViewBuilder
    private var suggestionsOverlay: some View {
        if showSuggestions && !suggestions.isEmpty {
            InquiryDockSuggestionsView(suggestions: suggestions, onSelect: applySuggestion)
                .padding(.leading, DS.space20)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    suggestionsHeight = height
                }
                .offset(y: -(suggestionsHeight + DS.space8))
                .opacity(suggestionsHeight > 0 ? 1 : 0)
                .zIndex(1)
                .transition(.opacity)
        }
    }

    // MARK: - Logic (prefix commands still parse exactly as before)

    private var isDraftEmpty: Bool {
        dockDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = dockDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dockDraft = ""
        showSuggestions = false
        Task { await viewModel.submitDockText(text) }
    }

    /// The menu is intentional-only: it opens with "/" and never while
    /// composing ordinary thoughts. Closes once a command is fully formed
    /// ("claim: …" or "/scout query") and real content follows.
    private func shouldShowSuggestions(for draft: String) -> Bool {
        guard draft.hasPrefix("/") else { return false }
        return !draft.contains(" ") || draft.trimmingCharacters(in: .whitespaces) == "/"
    }

    private var slashFilter: String {
        guard dockDraft.hasPrefix("/") else { return "" }
        return String(dockDraft.dropFirst())
            .split(separator: " ").first.map(String.init) ?? ""
    }

    private var suggestions: [InquiryDockSuggestion] {
        Array(InquiryDockSuggestion.all.filter { $0.matchesSlashFilter(slashFilter) }.prefix(12))
    }

    private func applySuggestion(_ suggestion: InquiryDockSuggestion) {
        // Kind prefixes ("claim: ") await the thought; slash commands
        // ("/scout ") await an optional query — Enter runs either.
        dockDraft = "\(suggestion.token) "
        showSuggestions = false
        dockFocused = true
    }
}
