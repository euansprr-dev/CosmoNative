// CosmoOS/UI/FocusMode/Inquiry/Study/StudyReceiptCapsule.swift
// One transient voice for everything the Study says back: routing receipts
// and ephemeral AI replies render as small floating glass capsules above the
// thinking bar — they materialize, live briefly, and fade. Tap-to-correct
// menus are preserved from the receipt system they replace.

import SwiftUI

// MARK: - Stack

@MainActor
struct StudyReceiptStack: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .center, spacing: DS.space6) {
            if let nudge = viewModel.ripeningNudge {
                StudyRipeningCapsule(viewModel: viewModel, nudge: nudge)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            ForEach(viewModel.ephemeralAIReplies) { reply in
                StudyAIReplyCapsule(viewModel: viewModel, reply: reply)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            ForEach(viewModel.routingReceipts) { receipt in
                StudyReceiptCapsule(viewModel: viewModel, receipt: receipt)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(ProMotionSprings.gentle, value: viewModel.routingReceipts)
        .animation(ProMotionSprings.gentle, value: viewModel.ephemeralAIReplies)
        .animation(ProMotionSprings.gentle, value: viewModel.ripeningNudge)
    }
}

// MARK: - Ripening nudge

/// A seedling crossed the ripeness line mid-session: one quiet invitation in
/// the receipt voice. Tap develops now; ✕ lets it wait (the seedling strip
/// and overview keep showing it — nothing is lost by ignoring this).
@MainActor
struct StudyRipeningCapsule: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let nudge: InquiryWorkspaceViewModel.RipeningNudge

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "leaf")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Text("\(nudge.name) is ripening")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.text)
            Text(nudge.reason)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Spacer(minLength: DS.space12)
            Button {
                Task { await viewModel.developFromNudge() }
            } label: {
                Text("Develop now")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, 3)
                    .background(DS.accentSoft, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Pivot to the Concept Desk")
            .accessibilityLabel("Develop \(nudge.name) now")
            Button {
                viewModel.dismissRipeningNudge()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Not now — it keeps ripening")
            .accessibilityLabel("Dismiss ripening nudge")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .frame(maxWidth: 560, alignment: .leading)
        .background(DS.surfaceCard.opacity(0.98), in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.accent.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Routing receipt

@MainActor
struct StudyReceiptCapsule: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let receipt: InquiryRoutingReceiptItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            headerRow
            ForEach(receipt.destinations) { destination in
                destinationRow(destination)
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .frame(maxWidth: 560, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(DS.surfaceCard.opacity(0.98), in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
    }

    private var headerRow: some View {
        HStack(spacing: DS.space6) {
            if receipt.isProvisional {
                ProvisionalPulseDot()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.green)
                    .accessibilityHidden(true)
            }
            Text(receipt.headline)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: DS.space12)
            Button {
                viewModel.dismissRoutingReceipt(receipt.id)
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss routing receipt")
        }
    }

    /// One destination line: kind badge + question, both tap-to-correct.
    private func destinationRow(_ destination: InquiryRoutingReceiptItem.Destination) -> some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "arrow.turn.down.right")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            if destination.isPending {
                InquiryClassifyingChip()
            } else {
                // No kind label while writing — the capture-time kind is only a hint
                // now (the real typing + organizing happens at crystallization), so a
                // premature "Principle/Practice" chip here just mismatches the result.
                // Kind is still correctable via the destination menu below.
                capturedChip
            }
            destinationMenu(destination)
        }
    }

    /// Neutral "filed" indicator shown in place of the old kind badge.
    private var capturedChip: some View {
        HStack(spacing: DS.space4) {
            Image(systemName: "checkmark.circle.fill")
                .font(DS.caption2)
                .foregroundStyle(DS.accent.opacity(0.7))
            Text("Captured")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .accessibilityLabel("Captured")
    }

    private func destinationMenu(_ destination: InquiryRoutingReceiptItem.Destination) -> some View {
        Menu {
            InquiryExtractCorrectionMenu(
                viewModel: viewModel,
                extractUUID: destination.extractUUID,
                currentKind: destination.kind
            )
        } label: {
            HStack(spacing: DS.space4) {
                Text(destinationLine(destination))
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Correct routing for \(destinationLine(destination))")
    }

    private func destinationLine(_ destination: InquiryRoutingReceiptItem.Destination) -> String {
        var line = destination.questionTitle
        if !destination.conceptNames.isEmpty {
            line += "  →  \(destination.conceptNames.prefix(2).joined(separator: ", "))"
        }
        return line
    }
}

// MARK: - Ephemeral AI reply

@MainActor
struct StudyAIReplyCapsule: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let reply: EphemeralAIReplyCard

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "sparkles")
                .font(DS.caption)
                .foregroundStyle(DS.accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.space4) {
                Text(reply.text)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(DS.text.opacity(0.9))
                    .lineSpacing(3)
                    .lineLimit(isExpanded ? nil : 3)
                    .textSelection(.enabled)
                if needsExpansion && !isExpanded {
                    Button("Show more") {
                        withAnimation(ProMotionSprings.gentle) { isExpanded = true }
                    }
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityLabel("Show the full reply")
                }
            }
            Spacer(minLength: DS.space8)
            Button {
                viewModel.dismissEphemeralReply(reply.id)
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss reply")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .frame(maxWidth: 560, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(DS.surfaceCard.opacity(0.98), in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
    }

    private var needsExpansion: Bool {
        reply.text.count > 220
    }
}
