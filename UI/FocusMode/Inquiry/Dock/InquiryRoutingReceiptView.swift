// CosmoOS/UI/FocusMode/Inquiry/Dock/InquiryRoutingReceiptView.swift
// Routing transparency: after a capture, a transient receipt shows exactly
// where each part went ("→ Claim · Pranayama"), with tap-to-correct menus.
// Replaces fire-and-forget toasts for routing events.

import SwiftUI

/// Transient UI model for one capture's routing outcome.
struct InquiryRoutingReceiptItem: Identifiable, Equatable {
    struct Destination: Identifiable, Equatable {
        var id: String { extractUUID }
        var extractUUID: String
        var kind: ExtractKind
        var questionUUID: String?
        var questionTitle: String
        var conceptNames: [String]
        var isNewBranch: Bool
        var isPending: Bool = false     // Awaiting LLM classification
    }
    var id: String                 // Original extract UUID
    var headline: String
    var destinations: [Destination]
    var isProvisional: Bool
}

@MainActor
struct InquiryRoutingReceiptStack: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            ForEach(viewModel.routingReceipts) { receipt in
                InquiryRoutingReceiptCard(viewModel: viewModel, receipt: receipt)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ProMotionSprings.gentle, value: viewModel.routingReceipts)
    }
}

@MainActor
struct InquiryRoutingReceiptCard: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let receipt: InquiryRoutingReceiptItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            headerRow
            ForEach(receipt.destinations) { destination in
                InquiryReceiptDestinationRow(viewModel: viewModel, destination: destination)
            }
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
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textSecondary)
            Spacer()
            Button {
                viewModel.dismissRoutingReceipt(receipt.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss routing receipt")
        }
    }
}

@MainActor
private struct InquiryReceiptDestinationRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let destination: InquiryRoutingReceiptItem.Destination

    var body: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            kindChip
            destinationMenu
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    /// The kind is its own one-click dropdown; while classification is in
    /// flight a shimmer chip holds its place (correcting early still works —
    /// the user-correction stamp outranks the eventual LLM result).
    @ViewBuilder
    private var kindChip: some View {
        if destination.isPending {
            InquiryClassifyingChip()
        } else {
            InquiryKindBadgeMenu(
                viewModel: viewModel,
                extractUUID: destination.extractUUID,
                kind: destination.kind
            )
        }
    }

    private var destinationMenu: some View {
        Menu {
            correctionMenu
        } label: {
            HStack(spacing: DS.space6) {
                Text(destinationLine)
                    .font(CosmoTypography.bodySmall)
                    .foregroundStyle(CosmoColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Correct routing for \(destinationLine)")
    }

    private var destinationLine: String {
        var line = destination.questionTitle
        if !destination.conceptNames.isEmpty {
            line += "  →  \(destination.conceptNames.prefix(2).joined(separator: ", "))"
        }
        return line
    }

    @ViewBuilder
    private var correctionMenu: some View {
        InquiryExtractCorrectionMenu(
            viewModel: viewModel,
            extractUUID: destination.extractUUID,
            currentKind: destination.kind
        )
    }
}

/// Shared "Change kind / Move to question / Make branch" correction actions for a
/// routed extract. Embed inside a `Menu` label or a `.contextMenu` — anywhere an
/// extract is shown after routing, so misroutes stay correctable beyond the
/// transient receipt.
@MainActor
struct InquiryExtractCorrectionMenu: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let extractUUID: String
    var currentKind: ExtractKind?

    var body: some View {
        Menu("Change kind") {
            ForEach(ExtractKind.correctionOptions, id: \.self) { kind in
                Button {
                    Task { await viewModel.rerouteExtract(extractUUID, toKind: kind) }
                } label: {
                    if kind == currentKind {
                        Label(kind.displayName, systemImage: "checkmark")
                    } else {
                        Text(kind.displayName)
                    }
                }
                .disabled(kind == currentKind)
            }
        }
        Menu("Move to question") {
            ForEach(viewModel.questions, id: \.uuid) { question in
                Button(question.title ?? "Untitled") {
                    Task { await viewModel.rerouteExtract(extractUUID, toQuestionUUID: question.uuid) }
                }
            }
        }
        Button("Make a branch question") {
            Task { await viewModel.promoteExtractToBranch(extractUUID) }
        }
    }
}
