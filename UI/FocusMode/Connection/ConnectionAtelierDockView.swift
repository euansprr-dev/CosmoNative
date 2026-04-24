// CosmoOS/UI/FocusMode/Connection/ConnectionAtelierDockView.swift
// April 2026 — docked Atelier rail for the connection-native collaborator

import SwiftUI

struct ConnectionAtelierDockView: View {

    @Binding var collaboratorMessages: [CollaboratorMessage]
    @Binding var activeDraftProposal: ConnectionDraftProposal?
    @ObservedObject var previewStore: ConnectionCollaboratorPreviewStore

    let frameworkTitle: String
    let conceptType: ConceptFrameworkType
    let isCollaboratorThinking: Bool
    let linkedSourceCount: Int
    let insights: [LiveInsight]
    let isRefreshingInsights: Bool
    let onSendMessage: (String) -> Void
    let onCrystallizeMessage: (CollaboratorMessage) -> Void
    let onInsertDraft: (ConnectionDraftProposal) -> Void
    let onReviseDraft: (ConnectionDraftProposal) -> Void
    let onMoveDraft: (ConnectionDraftProposal, ConnectionSectionType) -> Void
    let onDismissDraft: (ConnectionDraftProposal) -> Void
    let onResumeDraft: (ConnectionDraftProposal) -> Void
    let onUseLinkedSources: () -> Void
    let onRefreshInsights: () -> Void
    let onDismissInsight: (UUID) -> Void

    private var displayDraft: ConnectionDraftProposal? {
        previewStore.streamingDraft ?? activeDraftProposal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarginaliaLabel("THE ATELIER")
            ConceptCollaboratorPanel(
                messages: $collaboratorMessages,
                frameworkTitle: frameworkTitle,
                conceptType: conceptType,
                isThinking: isCollaboratorThinking,
                activeDraft: displayDraft,
                previewSourceMessageID: previewStore.sourceMessageID,
                isPreviewPaused: previewStore.isPaused,
                linkedSourceCount: linkedSourceCount,
                onSend: onSendMessage,
                onCrystallize: onCrystallizeMessage,
                onInsertDraft: onInsertDraft,
                onReviseDraft: onReviseDraft,
                onMoveDraft: onMoveDraft,
                onDismissDraft: onDismissDraft,
                onResumeDraft: onResumeDraft,
                onUseLinkedSources: onUseLinkedSources
            )
            .frame(height: 420)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
