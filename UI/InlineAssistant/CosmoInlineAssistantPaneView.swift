import SwiftUI

enum CosmoInlineAssistantPaneProgressPolicy {
    static func shouldShow(isProcessing: Bool, statusText: String?) -> Bool {
        isProcessing
    }

    static func statusLabel(isProcessing: Bool, statusText: String?) -> String {
        guard isProcessing else { return "" }
        let trimmed = statusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Reading current context" : trimmed
    }
}

/// The assistant pane: a reading surface, not a chat app. Assistant answers are
/// the hero — plain prose on the page with no card chrome. User prompts and
/// staged proposals are quiet, warm-filled cards; the thinking row narrates the
/// phase in Cosmo's own voice; the composer stays out of the way until focused.
struct CosmoInlineAssistantPaneView: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CosmoInlineAssistantPaneHeader(store: store, onClose: onClose)
            Divider().overlay(DS.borderSubtle)
            CosmoInlineAssistantPaneMessages(store: store)
            CosmoInlineAssistantPaneComposer(store: store)
        }
        .background(DS.bg)
    }
}

// MARK: - Header

private struct CosmoInlineAssistantPaneHeader: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onClose: () -> Void

    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "sparkle")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(store.phase.isWorking ? DS.accent : DS.textSecondary)
                .symbolEffect(.pulse, options: .repeating, isActive: store.phase.isWorking)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            Text("Cosmo")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(isCloseHovered ? DS.text : DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(isCloseHovered ? AnyShapeStyle(DS.surfaceHover) : AnyShapeStyle(Color.clear), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .onHover { hovering in
                withAnimation(ProMotionSprings.snappy) { isCloseHovered = hovering }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close assistant pane (Esc)")
            .accessibilityLabel("Close assistant pane")
        }
        .padding(.horizontal, DS.space16)
        .frame(height: 48)
    }
}

// MARK: - Messages

private struct CosmoInlineAssistantPaneMessages: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    private static let bottomAnchorID = "pane-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
            }
            .onChange(of: store.paneMessages.count) {
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: store.paneMessages.last?.content) {
                // Streaming growth: follow without animating every token.
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
            .onChange(of: store.isProcessing) {
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.paneMessages.isEmpty,
           !CosmoInlineAssistantPaneProgressPolicy.shouldShow(
                isProcessing: store.isProcessing,
                statusText: store.statusText
           ) {
            CosmoInlineAssistantPaneEmptyState(store: store)
                .frame(maxWidth: .infinity, minHeight: 280)
                .padding(DS.space16)
        } else {
            conversation
        }
    }

    private var conversation: some View {
        LazyVStack(alignment: .leading, spacing: DS.space12) {
            ForEach(store.paneMessages) { message in
                messageRow(message)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if CosmoInlineAssistantPaneProgressPolicy.shouldShow(
                isProcessing: store.isProcessing,
                statusText: store.statusText
            ) {
                CosmoInlineAssistantPaneThinkingRow(store: store)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(DS.space16)
        .animation(ProMotionSprings.gentle, value: store.paneMessages.count)
        .animation(ProMotionSprings.gentle, value: store.isProcessing)
    }

    @ViewBuilder
    private func messageRow(_ message: CosmoInlineAssistantPaneMessage) -> some View {
        if let proposalID = message.proposalID,
           let proposal = store.proposal(id: proposalID) {
            CosmoInlineAssistantPaneProposalCard(store: store, proposal: proposal)
        } else {
            switch message.role {
            case .user:
                CosmoInlineAssistantPaneUserRow(message: message)
            case .assistant:
                CosmoInlineAssistantPaneAnswerRow(message: message)
            case .system:
                CosmoInlineAssistantPaneSectionLabel(text: message.content)
            }
        }
    }
}

// MARK: - Empty state

private struct CosmoInlineAssistantPaneEmptyState: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    private static let starters: [(label: String, prompt: String)] = [
        ("Review this draft", "Give me honest feedback on this draft — what's working, what's weak?"),
        ("Search my brain", "What have I saved about "),
        ("Synthesize", "/Synthesize ")
    ]

    var body: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(DS.pageTitle)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            Text("Ask about the active workspace")
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text("Answers open here with their sources. Edit requests stage as reviewable diffs right in the document.")
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            HStack(spacing: DS.space6) {
                ForEach(Self.starters, id: \.label) { starter in
                    CosmoInlineAssistantStarterChip(label: starter.label) {
                        store.composerText = starter.prompt
                    }
                }
            }
            .padding(.top, DS.space4)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CosmoInlineAssistantStarterChip: View {
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(isHovered ? DS.accent : DS.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space6)
                .background(isHovered ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(DS.surface), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isHovered ? DS.accent.opacity(0.3) : DS.borderSubtle, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isHovered = hovering }
        }
        .help("Start with this prompt")
        .accessibilityLabel("Use starter prompt: \(label)")
    }
}

// MARK: - Thinking row

/// The phase made visible: same symbol vocabulary as the orb, narrated with the
/// verb-first status grammar. One quiet row, no card weight.
private struct CosmoInlineAssistantPaneThinkingRow: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: phaseSymbol)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 26, height: 26)
                .background(DS.accentSoft, in: Circle())
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            Text(statusLabel)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .contentTransition(.opacity)
                .animation(ProMotionSprings.gentle, value: statusLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cosmo is working: \(statusLabel)")
    }

    private var statusLabel: String {
        CosmoInlineAssistantPaneProgressPolicy.statusLabel(
            isProcessing: store.isProcessing,
            statusText: store.statusText
        )
    }

    private var phaseSymbol: String {
        switch store.phase {
        case .idle, .planning: return "sparkles"
        case .gathering: return "magnifyingglass"
        case .drafting: return "pencil.and.outline"
        case .reviewing: return "checkmark.circle"
        }
    }
}

// MARK: - Message rows

/// User prompts: a compact, warm chip — quiet context, never the hero.
private struct CosmoInlineAssistantPaneUserRow: View {
    let message: CosmoInlineAssistantPaneMessage

    var body: some View {
        Text(message.content)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(DS.accentSoft, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DS.accent.opacity(0.14), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("You asked: \(message.content)")
    }
}

/// Assistant answers: the hero. Plain prose on the page — no card, no border —
/// with a reading measure and its source receipts underneath.
private struct CosmoInlineAssistantPaneAnswerRow: View {
    let message: CosmoInlineAssistantPaneMessage

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(message.content)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: 620, alignment: .leading)

            if let refs = message.sourceRefs, !refs.isEmpty {
                CosmoInlineAssistantSourceChips(refs: refs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// System titles ("What I changed", skill names): small-caps section labels.
private struct CosmoInlineAssistantPaneSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.caption.weight(.semibold))
            .foregroundStyle(DS.textMuted)
            .textCase(.uppercase)
            .kerning(0.4)
            .padding(.top, DS.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Source chips

/// Clickable chips for the sources Cosmo actually read — every answer carries
/// its receipts, and a click opens the atom for verification.
private struct CosmoInlineAssistantSourceChips: View {
    let refs: [CosmoAssistantSourceRef]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text("Sources")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
                .kerning(0.4)

            FlexibleChipRows(refs: refs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sources Cosmo read: \(refs.map(\.title).joined(separator: ", "))")
    }
}

private struct FlexibleChipRows: View {
    let refs: [CosmoAssistantSourceRef]

    var body: some View {
        // Simple wrapping via vertical stacking of pairs keeps the layout cheap;
        // chips are short and the pane is narrow.
        let rows = stride(from: 0, to: refs.count, by: 2).map { index in
            Array(refs[index..<min(index + 2, refs.count)])
        }
        VStack(alignment: .leading, spacing: DS.space4) {
            ForEach(rows, id: \.first?.uuid) { row in
                HStack(spacing: DS.space4) {
                    ForEach(row) { ref in
                        SourceChip(ref: ref)
                    }
                }
            }
        }
    }
}

private struct SourceChip: View {
    let ref: CosmoAssistantSourceRef

    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": ref.uuid, "asPane": true]
            )
        } label: {
            HStack(spacing: DS.space4) {
                Image(systemName: ref.icon)
                    .font(DS.caption2)
                    .accessibilityHidden(true)
                Text(ref.title.isEmpty ? "Untitled" : ref.title)
                    .font(DS.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isHovered ? DS.accent : DS.textSecondary)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(isHovered ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(DS.surface), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isHovered ? DS.accent.opacity(0.3) : DS.borderSubtle, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isHovered = hovering }
        }
        .help("Open \(ref.title)")
        .accessibilityLabel("Open source: \(ref.title)")
    }
}

// MARK: - Proposal card

private struct CosmoInlineAssistantPaneProposalCard: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let proposal: CosmoAssistantProposal
    @State private var isReviewExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)
            operationList
            if proposal.hasReviewableOperations {
                Divider().overlay(DS.borderSubtle)
                decisionBar
            }
            if isReviewExpanded {
                Divider().overlay(DS.borderSubtle)
                expandedDiff
            }
        }
        .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        }
        .animation(ProMotionSprings.gentle, value: isReviewExpanded)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.space12) {
            Image(systemName: "text.badge.checkmark")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 32, height: 32)
                .background(DS.accentSoft, in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title.isEmpty ? "Staged edits" : proposal.title)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                HStack(spacing: DS.space6) {
                    Text("+\(proposal.addedHunkCount)")
                        .foregroundStyle(DS.green)
                    Text("−\(proposal.removedHunkCount)")
                        .foregroundStyle(DS.red)
                    Text(proposal.operationStatusSummary)
                        .foregroundStyle(DS.textMuted)
                }
                .font(DS.caption.weight(.medium))
                .monospacedDigit()
            }

            Spacer()

            if proposal.hasRevertableOperations {
                CosmoPanePillButton(label: "Undo", icon: "arrow.uturn.backward", help: "Revert applied changes") {
                    Task { await store.revertAll(proposalID: proposal.id) }
                }
            }

            CosmoPanePillButton(
                label: isReviewExpanded ? "Hide" : "Review",
                icon: nil,
                help: isReviewExpanded ? "Collapse the diff" : "Show the full diff"
            ) {
                isReviewExpanded.toggle()
            }
        }
        .padding(DS.space12)
    }

    private var operationList: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(proposal.operations) { operation in
                CosmoInlineAssistantPaneOperationRow(store: store, operation: operation)
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    /// One decision, two verbs — the review itself happens in-document, but the
    /// pane offers the whole-proposal call without leaving the conversation.
    private var decisionBar: some View {
        HStack(spacing: DS.space8) {
            Text("Review the diff in the document, or decide here")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer()

            CosmoPanePillButton(label: "Reject all", icon: nil, help: "Reject every pending change") {
                Task { await store.rejectAll(proposalID: proposal.id) }
            }

            CosmoPanePillButton(
                label: "Accept all",
                icon: "checkmark",
                help: "Apply every pending change",
                isProminent: true
            ) {
                Task { await store.acceptAll(proposalID: proposal.id) }
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
    }

    private var expandedDiff: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text(proposal.summary)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)

            ForEach(proposal.operations) { operation in
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(operation.rationale)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textSecondary)

                    ForEach(operation.hunks) { hunk in
                        CosmoInlineAssistantPaneDiffHunkView(hunk: hunk)
                    }
                }
            }
        }
        .padding(DS.space12)
        .background(DS.surface.opacity(0.55))
    }
}

/// Quiet pill button for card actions: hover lift, press compress, optional
/// prominent (accent) variant for the primary verb.
private struct CosmoPanePillButton: View {
    let label: String
    let icon: String?
    let help: String
    var isProminent = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space4) {
                if let icon {
                    Image(systemName: icon)
                        .font(DS.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(DS.caption.weight(.medium))
            }
            .foregroundStyle(isProminent ? DS.textOnAccent : DS.text)
            .padding(.horizontal, DS.space12)
            .frame(height: 28)
            .background(fill, in: Capsule())
            .overlay {
                if !isProminent {
                    Capsule().strokeBorder(DS.borderSubtle, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .onHover { hovering in
            withAnimation(ProMotionSprings.snappy) { isHovered = hovering }
        }
        .help(help)
        .accessibilityLabel(label)
    }

    private var fill: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(DS.accent)
        }
        return isHovered ? AnyShapeStyle(DS.surfaceHover) : AnyShapeStyle(DS.surface)
    }
}

private struct CosmoInlineAssistantPaneOperationRow: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let operation: CosmoAssistantProposalOperation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
            Text(operation.rationale)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            Text(statusLabel)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(statusColor)

            if operation.isRevertable {
                Button {
                    Task { await store.revert(operationID: operation.id) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(DS.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cosmoClickCursor()
                .foregroundStyle(DS.textSecondary)
                .help("Revert this change")
                .accessibilityLabel("Revert this change")
            }
        }
    }

    private var statusLabel: String {
        switch operation.status {
        case .pending: return "pending"
        case .accepted, .applied: return "accepted"
        case .rejected: return "rejected"
        case .conflicted: return "conflicted"
        case .reverted: return "reverted"
        }
    }

    private var statusColor: Color {
        switch operation.status {
        case .pending: return DS.textMuted
        case .accepted, .applied: return DS.green
        case .rejected, .reverted: return DS.textSecondary
        case .conflicted: return DS.orange
        }
    }
}

private struct CosmoInlineAssistantPaneDiffHunkView: View {
    let hunk: CosmoProposalHunk

    var body: some View {
        Text(prefix + hunk.text)
            .font(DS.caption.monospaced())
            .foregroundStyle(foreground)
            .lineLimit(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(background, in: .rect(cornerRadius: 7))
            .strikethrough(hunk.kind == .removed, color: foreground)
    }

    private var prefix: String {
        switch hunk.kind {
        case .added: return "+ "
        case .removed: return "− "
        case .context: return "  "
        }
    }

    private var foreground: Color {
        switch hunk.kind {
        case .added: return DS.green
        case .removed: return DS.red
        case .context: return DS.textSecondary
        }
    }

    private var background: Color {
        switch hunk.kind {
        case .added: return DS.greenSoft
        case .removed: return DS.redSoft
        case .context: return DS.surfaceHover.opacity(0.55)
        }
    }
}

// MARK: - Composer

private struct CosmoInlineAssistantPaneComposer: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.space8) {
            TextField("Ask, or describe an edit", text: $store.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit { submit() }

            sendButton
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .dsGlassInput(isFocused: isFocused, cornerRadius: 14)
        .padding(DS.space16)
        .animation(ProMotionSprings.snappy, value: isFocused)
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: store.isProcessing ? "stop.fill" : "arrow.up")
                .font(DS.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .background(sendFill, in: Circle())
                .foregroundStyle(sendText)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .cosmoClickCursor()
        .disabled(!canSubmit)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Send (⏎)")
        .accessibilityLabel("Send")
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await store.submit() }
    }

    private var canSubmit: Bool {
        !store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isProcessing
    }

    private var sendFill: Color {
        canSubmit ? DS.accent : DS.borderSubtle
    }

    private var sendText: Color {
        canSubmit ? DS.textOnAccent : DS.textMuted
    }
}
