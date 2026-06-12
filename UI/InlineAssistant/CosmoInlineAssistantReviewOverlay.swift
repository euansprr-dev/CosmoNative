import SwiftUI

// MARK: - Cursor

extension View {
    /// Shows the pointing-hand cursor on hover. SwiftUI buttons layered over an
    /// `NSTextView` otherwise inherit the editor's I-beam; `pointerStyle` installs a
    /// real cursor rect that wins over the text surface underneath.
    func cosmoClickCursor() -> some View {
        pointerStyle(.link)
    }
}

// MARK: - Inline document diff review

/// Renders a surface's text *in place* with the proposed changes woven inline:
/// untouched prose reads normally (dimmed), each change shows the removed lines in red
/// and the added lines in green with its own accept / reject controls. This replaces a
/// surface's editor while a proposal is being reviewed, so the user scrolls the real
/// document and reads every change in context — no floating menu.
struct CosmoInlineDiffReviewView: View {
    // Plain reference, not observed: the host surface re-feeds `proposal` and
    // `sourceText` whenever the store changes, so observing here would only add
    // redundant re-renders on every composer keystroke.
    let store: CosmoInlineAssistantStore
    let proposal: CosmoAssistantProposal
    let sourceText: String
    var bodyFont: Font = .system(size: 17)
    var textColor: Color = DS.text
    var unchangedOpacity: Double = 0.5
    var onAcceptOperation: ((UUID) -> Void)?
    var onRejectOperation: ((UUID) -> Void)?

    private var segments: [CosmoInlineDiffSegment] {
        CosmoInlineDiffReviewBuilder.segments(
            sourceText: sourceText,
            operations: proposal.operations
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(segments) { segment in
                switch segment {
                case let .unchanged(_, text):
                    Text(text)
                        .font(bodyFont)
                        .foregroundStyle(textColor.opacity(unchangedOpacity))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                case let .change(change):
                    CosmoInlineDiffChangeRow(
                        change: change,
                        onAccept: { accept(change.id) },
                        onReject: { reject(change.id) }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.97))
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ProMotionSprings.gentle, value: sourceText)
    }

    private func accept(_ operationID: UUID) {
        if let onAcceptOperation {
            onAcceptOperation(operationID)
        } else {
            Task { await store.accept(operationID: operationID) }
        }
    }

    private func reject(_ operationID: UUID) {
        if let onRejectOperation {
            onRejectOperation(operationID)
        } else {
            Task { await store.reject(operationID: operationID) }
        }
    }
}

private struct CosmoInlineDiffChangeRow: View {
    let change: CosmoInlineDiffChange
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill((change.isConflicted ? DS.orange : DS.green).opacity(0.45))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                if change.isConflicted {
                    Label("Nothing to apply on this document — dismiss to clear", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.orange)
                } else if !change.rationale.isEmpty {
                    Text(change.rationale)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }

                ForEach(Array(change.removedLines.enumerated()), id: \.offset) { _, line in
                    CosmoInlineDiffLineView(text: line, kind: .removed)
                }
                ForEach(Array(change.addedLines.enumerated()), id: \.offset) { _, line in
                    CosmoInlineDiffLineView(text: line, kind: .added)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controls
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(DS.surface.opacity(0.45), in: .rect(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if !change.isConflicted {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.textOnAccent)
                        .frame(width: 30, height: 30)
                        .background(DS.green, in: Circle())
                }
                .buttonStyle(.plain)
                .cosmoClickCursor()
                .help("Accept change")
                .accessibilityLabel("Accept change")
            }

            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(DS.surface, in: Circle())
                    .overlay { Circle().stroke(DS.borderSubtle, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .help(change.isConflicted ? "Dismiss" : "Reject change")
            .accessibilityLabel(change.isConflicted ? "Dismiss change" : "Reject change")
        }
    }
}

private struct CosmoInlineDiffLineView: View {
    enum Kind { case removed, added }

    let text: String
    let kind: Kind

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(kind == .removed ? "−" : "+")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 12, alignment: .center)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(accent)
                .strikethrough(kind == .removed, color: accent.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(fill, in: .rect(cornerRadius: 8))
    }

    private var accent: Color {
        kind == .removed ? DS.red : DS.green
    }

    private var fill: Color {
        kind == .removed ? DS.redSoft : DS.greenSoft
    }
}

// MARK: - Global review bar

/// Slim accept-all / reject-all bar that floats just above the composer when a proposal
/// has more than one change. Single-change proposals are handled entirely by the inline
/// controls, so this only appears when a batch decision is useful.
struct CosmoInlineAssistantReviewOverlay: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    var body: some View {
        Group {
            if let proposal = store.activePendingProposal,
               proposal.reviewableOperationCount > 1 {
                globalBar(proposal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(ProMotionSprings.gentle, value: store.activePendingProposal?.id)
    }

    private func globalBar(_ proposal: CosmoAssistantProposal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(proposal.reviewableOperationCount) changes to review")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                if !proposal.title.isEmpty {
                    Text(proposal.title)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Button {
                Task { await store.rejectAll(proposalID: proposal.id) }
            } label: {
                pillLabel("Reject all", systemImage: "xmark")
                    .foregroundStyle(DS.textSecondary)
                    .background(DS.surface, in: Capsule())
                    .overlay { Capsule().stroke(DS.borderSubtle, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .accessibilityLabel("Reject all changes")

            Button {
                Task { await store.acceptAll(proposalID: proposal.id) }
            } label: {
                pillLabel("Accept all", systemImage: "checkmark")
                    .foregroundStyle(DS.textOnAccent)
                    .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .cosmoClickCursor()
            .accessibilityLabel("Accept all changes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 640)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(DS.borderSubtle, lineWidth: 1) }
        .dsFloatingShadow()
        .padding(.horizontal, 28)
    }

    private func pillLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }
}
