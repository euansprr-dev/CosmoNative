// CosmoOS/UI/FocusMode/Inquiry/InquiryDockView.swift
// Bottom universal capture dock for the Stele shell. Raycast-style single input.
// Inline autocomplete for command prefixes; ephemeral AI replies floating above.

import SwiftUI

@MainActor
struct InquiryDockView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    @Binding var dockDraft: String
    @FocusState.Binding var dockFocused: Bool

    @State private var showSuggestions: Bool = false

    var body: some View {
        HStack(spacing: DS.space10) {
            leadingIcon

            if let activity = viewModel.sourceActivityLine, dockDraft.isEmpty {
                dockActivityLine(activity)
            } else if viewModel.aiBusy && dockDraft.isEmpty {
                dockActivityLine("Cosmo is thinking…")
            } else {
                dockField
            }

            sendButton
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space10)
        .background(DS.surface)
        .overlay(alignment: .topLeading) {
            if showSuggestions && !suggestions.isEmpty {
                InquiryDockSuggestionsView(
                    suggestions: suggestions,
                    onSelect: applySuggestion
                )
                .padding(.leading, suggestionsLeadingInset)
                // Keep the popover above the dock instead of letting it grow through the input row.
                .alignmentGuide(.top) { dimensions in
                    dimensions[.bottom] + DS.space8
                }
                .zIndex(1)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(ProMotionSprings.gentle, value: viewModel.sourceActivityLine)
        .animation(ProMotionSprings.gentle, value: viewModel.aiBusy)
        .animation(ProMotionSprings.gentle, value: showSuggestions)
    }

    private var leadingIcon: some View {
        Image(systemName: "sparkle.magnifyingglass")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DS.accent)
            .frame(width: 36, height: 36)
            .background(DS.accentSoft, in: Circle())
            .accessibilityHidden(true)
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

    private func dockActivityLine(_ activity: String) -> some View {
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
        .padding(.horizontal, DS.space10)
        .padding(.vertical, 6)
        .background(DS.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.accent.opacity(0.14), lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 36, height: 36)
                .background(isDraftEmpty ? DS.surfaceHover : DS.accent, in: Circle())
                .foregroundStyle(isDraftEmpty ? CosmoColors.textTertiary : DS.textOnAccent)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDraftEmpty)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityLabel("Send")
    }

    // MARK: - Helpers

    private var isDraftEmpty: Bool {
        dockDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var suggestionsLeadingInset: CGFloat {
        DS.space20 + 36 + DS.space10
    }

    private func submit() {
        let text = dockDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dockDraft = ""
        showSuggestions = false
        Task { await viewModel.submitDockText(text) }
    }

    private func shouldShowSuggestions(for draft: String) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("/") { return true }
        if trimmed.contains(":") { return false }
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return firstWord.count >= 1 && firstWord.count <= 12 && InquiryDockSuggestion.all.contains { $0.matches(prefix: firstWord) }
    }

    private var suggestions: [InquiryDockSuggestion] {
        let trimmed = dockDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let matching = InquiryDockSuggestion.all.filter { $0.matches(prefix: firstWord) }
        return Array(matching.prefix(6))
    }

    private func applySuggestion(_ suggestion: InquiryDockSuggestion) {
        let trimmed = dockDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let remainder = trimmed.dropFirst(firstWord.count).trimmingCharacters(in: .whitespaces)
        let needsSpace = suggestion.token.hasSuffix(":")
        let inserted = needsSpace ? "\(suggestion.token) \(remainder)" : suggestion.token
        dockDraft = inserted
        showSuggestions = false
        dockFocused = true
    }
}

// MARK: - Suggestion model

struct InquiryDockSuggestion: Identifiable, Equatable, Sendable {
    var id: String { token }
    var token: String         // "claim:", "/scout", "@branch"
    var label: String         // human-readable name
    var detail: String        // short description
    var icon: String          // SF Symbol

    func matches(prefix: String) -> Bool {
        let lower = token.lowercased()
        let prefixLower = prefix.lowercased()
        return lower.hasPrefix(prefixLower) || lower.contains(prefixLower)
    }

    static let all: [InquiryDockSuggestion] = [
        InquiryDockSuggestion(token: "claim:", label: "Claim", detail: "Save as a load-bearing claim", icon: "exclamationmark.bubble"),
        InquiryDockSuggestion(token: "maybe:", label: "Speculative claim", detail: "Save as a speculative claim", icon: "questionmark.bubble"),
        InquiryDockSuggestion(token: "evidence:", label: "Evidence", detail: "Save as evidence", icon: "checkmark.seal"),
        InquiryDockSuggestion(token: "counter:", label: "Counterevidence", detail: "Save as counterevidence", icon: "exclamationmark.triangle"),
        InquiryDockSuggestion(token: "note:", label: "Note", detail: "Save a free note", icon: "note.text"),
        InquiryDockSuggestion(token: "term:", label: "Term", detail: "Add to lexicon", icon: "character.book.closed"),
        InquiryDockSuggestion(token: "practice:", label: "Practice", detail: "Save a practice", icon: "figure.mind.and.body"),
        InquiryDockSuggestion(token: "output:", label: "Output idea", detail: "Capture an output angle", icon: "paperplane"),
        InquiryDockSuggestion(token: "source:", label: "Source", detail: "Open URL or search sources", icon: "globe"),
        InquiryDockSuggestion(token: "scout:", label: "Deep Scout", detail: "Run Deep Scout across providers", icon: "sparkle.magnifyingglass"),
        InquiryDockSuggestion(token: "branch:", label: "Branch", detail: "Create a child question", icon: "arrow.branch"),
        InquiryDockSuggestion(token: "q:", label: "Question", detail: "Auto-place a new question", icon: "questionmark.diamond"),
        InquiryDockSuggestion(token: "/sources", label: "Refresh sources", detail: "Re-run source radar", icon: "scope"),
        InquiryDockSuggestion(token: "/scout", label: "Deep Scout", detail: "Run Deep Scout", icon: "sparkle.magnifyingglass"),
        InquiryDockSuggestion(token: "/summarize", label: "Summarize", detail: "Summarize current context", icon: "text.book.closed"),
        InquiryDockSuggestion(token: "/challenge", label: "Challenge evidence", detail: "Create an evidence audit", icon: "exclamationmark.triangle"),
    ]
}

// MARK: - Suggestions popover

@MainActor
struct InquiryDockSuggestionsView: View {
    let suggestions: [InquiryDockSuggestion]
    let onSelect: (InquiryDockSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(suggestions) { suggestion in
                Button { onSelect(suggestion) } label: {
                    HStack(spacing: DS.space8) {
                        Image(systemName: suggestion.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.accent)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        Text(suggestion.token)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(CosmoColors.textPrimary)
                        Text(suggestion.detail)
                            .font(CosmoTypography.caption)
                            .foregroundStyle(CosmoColors.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DS.space6)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        .frame(maxWidth: 360, alignment: .leading)
    }
}

// MARK: - Ephemeral AI cards stack

@MainActor
struct InquiryEphemeralAICardsStack: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(viewModel.ephemeralAIReplies.suffix(3).reversed()) { card in
                EphemeralAIReplyCardView(card: card) {
                    viewModel.dismissEphemeralReply(card.id)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct EphemeralAIReplyCardView: View {
    let card: EphemeralAIReplyCard
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(DS.accent)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(card.text)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(CosmoColors.textPrimary)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
            Spacer(minLength: DS.space8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss AI reply")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(DS.vellum, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private var icon: String {
        switch card.kind {
        case .reply: return "sparkles"
        case .summary: return "text.book.closed"
        case .challenge: return "exclamationmark.triangle"
        case .routing: return "arrow.branch"
        }
    }
}
