import SwiftUI

struct CosmoInlineAssistantReviewOverlay: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        if !reviewableProposals.isEmpty {
            VStack(spacing: 12) {
                ForEach(reviewableProposals) { proposal in
                    CosmoInlineAssistantProposalCard(store: store, proposal: proposal)
                }
            }
            .frame(maxWidth: 840)
            .padding(.horizontal, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var reviewableProposals: [CosmoAssistantProposal] {
        store.proposals.filter { proposal in
            proposal.operations.contains { operation in
                operation.status == .pending || operation.status == .conflicted
            }
        }
    }
}

private struct CosmoInlineAssistantProposalCard: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let proposal: CosmoAssistantProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    Text(proposal.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    Task { await store.rejectAll(proposalID: proposal.id) }
                } label: {
                    Label("Reject all", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await store.acceptAll(proposalID: proposal.id) }
                } label: {
                    Label("Accept all", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DS.accent)
            }

            VStack(spacing: 8) {
                ForEach(proposal.operations) { operation in
                    if operation.status == .pending || operation.status == .conflicted {
                        CosmoInlineAssistantOperationReviewRow(store: store, operation: operation)
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.surfaceCard.opacity(0.97))
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.borderSubtle, lineWidth: 1)
        }
    }
}

private struct CosmoInlineAssistantOperationReviewRow: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let operation: CosmoAssistantProposalOperation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if operation.status == .conflicted {
                    Label("Source changed", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.orange)
                }

                Text(operation.rationale)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(operation.hunks) { hunk in
                        CosmoInlineAssistantDiffHunkView(hunk: hunk)
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    Task { await store.accept(operationID: operation.id) }
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
                .help("Accept change")
                .accessibilityLabel("Accept change")
                .disabled(operation.status == .conflicted)

                Button {
                    Task { await store.reject(operationID: operation.id) }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .help("Reject change")
                .accessibilityLabel("Reject change")
            }
            .padding(4)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            }
        }
        .padding(12)
        .background(DS.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CosmoInlineAssistantDiffHunkView: View {
    let hunk: CosmoProposalHunk

    var body: some View {
        Text(prefix + hunk.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(foreground)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
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
