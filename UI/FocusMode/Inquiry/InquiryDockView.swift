// CosmoOS/UI/FocusMode/Inquiry/InquiryDockView.swift
// Shared dock components: prefix-command suggestion catalog + popover and
// ephemeral AI reply cards. The dock surface itself lives in Dock/InquiryAssistantDock.swift.

import SwiftUI

// Legacy dock retired: InquiryAssistantDock (Dock/InquiryAssistantDock.swift)
// is the permanent assistant-styled replacement. This file keeps the shared
// suggestion catalog, suggestions popover, and ephemeral AI reply cards.

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

    /// Slash-menu filtering: "/cl" matches "claim:", "/scout" matches both
    /// "scout:" and "/scout". An empty filter shows the full catalog.
    func matchesSlashFilter(_ filter: String) -> Bool {
        guard !filter.isEmpty else { return true }
        let needle = filter.lowercased()
        let bareToken = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/:"))
        return bareToken.hasPrefix(needle) || label.lowercased().hasPrefix(needle)
    }

    /// One-to-one with the Connection structure (goal, problems, claims,
    /// evidence, beliefs/objections, process, examples, benefits, open
    /// questions, concept, references) plus session commands.
    static let all: [InquiryDockSuggestion] = [
        InquiryDockSuggestion(token: "goal:", label: "Goal", detail: "What you're trying to achieve", icon: "target"),
        InquiryDockSuggestion(token: "problem:", label: "Problem", detail: "A pain point or obstacle", icon: "exclamationmark.octagon"),
        InquiryDockSuggestion(token: "claim:", label: "Claim", detail: "Save as a load-bearing claim", icon: "exclamationmark.bubble"),
        InquiryDockSuggestion(token: "maybe:", label: "Speculative claim", detail: "Save as a speculative claim", icon: "questionmark.bubble"),
        InquiryDockSuggestion(token: "evidence:", label: "Evidence", detail: "Save as evidence", icon: "checkmark.seal"),
        InquiryDockSuggestion(token: "counter:", label: "Counterevidence", detail: "Save as counterevidence", icon: "exclamationmark.triangle"),
        InquiryDockSuggestion(token: "objection:", label: "Objection", detail: "A pushback or counterargument", icon: "questionmark.diamond"),
        InquiryDockSuggestion(token: "assumption:", label: "Assumption", detail: "Something taken for granted", icon: "building.columns"),
        InquiryDockSuggestion(token: "principle:", label: "Principle", detail: "A distilled general rule", icon: "scope"),
        InquiryDockSuggestion(token: "mechanism:", label: "Mechanism", detail: "How or why something works", icon: "gearshape.2"),
        InquiryDockSuggestion(token: "example:", label: "Example", detail: "A concrete illustrating instance", icon: "lightbulb"),
        InquiryDockSuggestion(token: "benefit:", label: "Benefit", detail: "A positive outcome or payoff", icon: "gift"),
        InquiryDockSuggestion(token: "quote:", label: "Quote", detail: "Verbatim text worth keeping", icon: "quote.opening"),
        InquiryDockSuggestion(token: "reference:", label: "Reference", detail: "A pointer to a source", icon: "link"),
        InquiryDockSuggestion(token: "concept:", label: "Concept", detail: "Name a concept for the lexicon", icon: "character.book.closed"),
        InquiryDockSuggestion(token: "term:", label: "Term", detail: "Add to lexicon", icon: "character.book.closed"),
        InquiryDockSuggestion(token: "note:", label: "Note", detail: "Save a free note", icon: "note.text"),
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

// MARK: - Slash command menu

/// Command-K-style glass menu listing every dock command. Opened intentionally
/// with "/" only, and rendered above the dock by its host.
@MainActor
struct InquiryDockSuggestionsView: View {
    let suggestions: [InquiryDockSuggestion]
    let onSelect: (InquiryDockSuggestion) -> Void

    @State private var hoveredToken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("COMMANDS")
                .dsSmallCapsLabel()
                .padding(.horizontal, DS.space12)
                .padding(.top, DS.space8)
                .padding(.bottom, DS.space4)
            ForEach(suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .padding(.vertical, DS.space6)
        .frame(width: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(DS.surfaceElevated.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        .dsFloatingShadow()
    }

    private func suggestionRow(_ suggestion: InquiryDockSuggestion) -> some View {
        Button { onSelect(suggestion) } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .frame(width: 20, height: 20)
                    .background(DS.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)
                Text(suggestion.label)
                    .font(CosmoTypography.label)
                    .foregroundStyle(CosmoColors.textPrimary)
                Text(suggestion.detail)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: DS.space8)
                Text(suggestion.token)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 6)
            .background(
                hoveredToken == suggestion.token ? DS.surfaceHover.opacity(0.8) : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.space6)
        .onHover { hoveredToken = $0 ? suggestion.token : (hoveredToken == suggestion.token ? nil : hoveredToken) }
        .accessibilityLabel("\(suggestion.label). \(suggestion.detail)")
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
