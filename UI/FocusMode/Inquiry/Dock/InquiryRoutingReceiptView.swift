// CosmoOS/UI/FocusMode/Inquiry/Dock/InquiryRoutingReceiptView.swift
// Routing-receipt data model + the shared correction menu. The receipt
// surface itself renders as glass capsules in Study/StudyReceiptCapsule.swift.

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
