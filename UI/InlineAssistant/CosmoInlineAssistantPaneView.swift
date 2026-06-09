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

struct CosmoInlineAssistantPaneView: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CosmoInlineAssistantPaneHeader(onClose: onClose)
            Divider().overlay(DS.borderSubtle)
            CosmoInlineAssistantPaneMessages(store: store)
            CosmoInlineAssistantPaneComposer(store: store)
        }
        .background(DS.bg)
    }
}

private struct CosmoInlineAssistantPaneHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)

            Text("Cosmo Assistant")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.text)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close assistant pane")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

private struct CosmoInlineAssistantPaneMessages: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        ScrollView {
            if store.paneMessages.isEmpty,
               !CosmoInlineAssistantPaneProgressPolicy.shouldShow(
                    isProcessing: store.isProcessing,
                    statusText: store.statusText
               ) {
                CosmoInlineAssistantPaneEmptyState()
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .padding(16)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.paneMessages) { message in
                        if let proposalID = message.proposalID,
                           let proposal = store.proposal(id: proposalID) {
                            CosmoInlineAssistantPaneProposalCard(store: store, proposal: proposal)
                        } else {
                            CosmoInlineAssistantPaneMessageRow(message: message)
                        }
                    }

                    if CosmoInlineAssistantPaneProgressPolicy.shouldShow(
                        isProcessing: store.isProcessing,
                        statusText: store.statusText
                    ) {
                        CosmoInlineAssistantPaneProgressRow(
                            statusText: CosmoInlineAssistantPaneProgressPolicy.statusLabel(
                                isProcessing: store.isProcessing,
                                statusText: store.statusText
                            )
                        )
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct CosmoInlineAssistantPaneEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(DS.textMuted)

            Text("Ask about the active workspace")
                .font(.headline)
                .foregroundStyle(DS.text)

            Text("Questions open here; edit requests stay reviewable on the canvas or document.")
                .font(.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 260)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CosmoInlineAssistantPaneProgressRow: View {
    let statusText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 32, height: 32)
                .background(DS.accentSoft, in: Circle())
                .symbolEffect(.pulse, options: .repeating, value: statusText)

            VStack(alignment: .leading, spacing: 3) {
                Text("Working...")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceCard, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cosmo is working. \(statusText)")
    }
}

private struct CosmoInlineAssistantPaneMessageRow: View {
    let message: CosmoInlineAssistantPaneMessage

    var body: some View {
        Text(message.content)
            .font(.system(size: 14))
            .foregroundStyle(textColor)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundFill, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }

    private var textColor: Color {
        switch message.role {
        case .user:
            return DS.text
        case .assistant:
            return DS.textSecondary
        case .system:
            return DS.textMuted
        }
    }

    private var backgroundFill: Color {
        switch message.role {
        case .user:
            return DS.accentSoft
        case .assistant:
            return DS.surfaceCard
        case .system:
            return DS.surface
        }
    }

    private var borderColor: Color {
        message.role == .user ? DS.accent.opacity(0.16) : DS.borderSubtle
    }
}

private struct CosmoInlineAssistantPaneProposalCard: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let proposal: CosmoAssistantProposal
    @State private var isReviewExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.borderSubtle)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(proposal.operations) { operation in
                    CosmoInlineAssistantPaneOperationRow(store: store, operation: operation)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if isReviewExpanded {
                Divider().overlay(DS.borderSubtle)
                expandedDiff
            }
        }
        .background(DS.surfaceCard, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "rectangle.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 34, height: 34)
                .background(DS.surface, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Edited \(proposal.operations.count) \(proposal.operations.count == 1 ? "item" : "items")")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("+\(proposal.addedHunkCount)")
                        .foregroundStyle(DS.green)
                    Text("-\(proposal.removedHunkCount)")
                        .foregroundStyle(DS.red)
                    Text(proposal.operationStatusSummary)
                        .foregroundStyle(DS.textMuted)
                }
                .font(.system(size: 12, weight: .medium))
            }

            Spacer()

            if proposal.hasRevertableOperations {
                Button {
                    Task { await store.revertAll(proposalID: proposal.id) }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.text)
                .help("Revert applied changes")
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isReviewExpanded.toggle()
                }
            } label: {
                Text(isReviewExpanded ? "Hide" : "Review")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(DS.surface, in: .rect(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.text)
        }
        .padding(14)
    }

    private var expandedDiff: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(proposal.summary)
                .font(.system(size: 13))
                .foregroundStyle(DS.textSecondary)

            ForEach(proposal.operations) { operation in
                VStack(alignment: .leading, spacing: 6) {
                    Text(operation.rationale)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textSecondary)

                    ForEach(operation.hunks) { hunk in
                        CosmoInlineAssistantPaneDiffHunkView(hunk: hunk)
                    }
                }
            }
        }
        .padding(14)
        .background(DS.surface.opacity(0.55))
    }
}

private struct CosmoInlineAssistantPaneOperationRow: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let operation: CosmoAssistantProposalOperation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(operation.rationale)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            Text(statusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)

            if operation.isRevertable {
                Button {
                    Task { await store.revert(operationID: operation.id) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .help("Revert this change")
                .accessibilityLabel("Revert this change")
            }
        }
    }

    private var statusLabel: String {
        switch operation.status {
        case .pending:
            return "pending"
        case .accepted, .applied:
            return "accepted"
        case .rejected:
            return "rejected"
        case .conflicted:
            return "conflicted"
        case .reverted:
            return "reverted"
        }
    }

    private var statusColor: Color {
        switch operation.status {
        case .pending:
            return DS.textMuted
        case .accepted, .applied:
            return DS.green
        case .rejected, .reverted:
            return DS.textSecondary
        case .conflicted:
            return DS.orange
        }
    }
}

private struct CosmoInlineAssistantPaneDiffHunkView: View {
    let hunk: CosmoProposalHunk

    var body: some View {
        Text(prefix + hunk.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(foreground)
            .lineLimit(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: .rect(cornerRadius: 8))
            .strikethrough(hunk.kind == .removed, color: foreground)
    }

    private var prefix: String {
        switch hunk.kind {
        case .added:
            return "+ "
        case .removed:
            return "- "
        case .context:
            return "  "
        }
    }

    private var foreground: Color {
        switch hunk.kind {
        case .added:
            return DS.green
        case .removed:
            return DS.red
        case .context:
            return DS.textSecondary
        }
    }

    private var background: Color {
        switch hunk.kind {
        case .added:
            return DS.greenSoft
        case .removed:
            return DS.redSoft
        case .context:
            return DS.surfaceHover.opacity(0.55)
        }
    }
}

private struct CosmoInlineAssistantPaneComposer: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask Cosmo", text: $store.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)

            Button {
                Task { await store.submit() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(sendFill, in: Circle())
                    .foregroundStyle(sendText)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Send")
        }
        .padding(12)
        .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.borderSubtle, lineWidth: 1)
        }
        .padding(16)
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
