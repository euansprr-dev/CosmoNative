// CosmoOS/UI/FocusMode/Connection/ConnectionStructuredWorkspaceView.swift
// April 2026 — governed connection workspace

import SwiftUI

struct ConnectionStructuredWorkspaceView: View {

    @Binding var title: String
    @Binding var conceptType: ConceptFrameworkType
    @Binding var state: ConnectionFocusModeState
    @Binding var collaboratorMessages: [CollaboratorMessage]
    @Binding var activeDraftProposal: ConnectionDraftProposal?
    @ObservedObject var previewStore: ConnectionCollaboratorPreviewStore

    let frameworkTitle: String
    let isCollaboratorThinking: Bool
    let insights: [LiveInsight]
    let isRefreshingInsights: Bool
    let sourceCount: Int
    let linkedSourceCount: Int
    let maturityLabel: String

    let sources: [Atom]
    let suggestedSources: [Atom]
    let whispersBySource: [String: [GhostSuggestion]]
    let contributionsBySource: [String: Set<ConnectionSectionType>]
    let isShowingSuggestions: Bool
    let isLoadingSuggestions: Bool

    let onAddItem: (RichDocument, String, ConnectionSectionType) -> Void
    let onEditItem: (ConnectionItem, ConnectionSectionType) -> Void
    let onDeleteItem: (UUID, ConnectionSectionType) -> Void
    let onSourceTap: (String) -> Void
    let onAcceptGhost: (GhostSuggestion, ConnectionSectionType) -> Void
    let onDismissGhost: (UUID, ConnectionSectionType) -> Void
    let onEnterStationMode: (ConnectionSectionType) -> Void
    let onTitleCommit: (String) -> Void
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
    let onAddSource: () -> Void
    let onRequestSuggestions: () -> Void
    let onLinkSuggestedSource: (Atom) -> Void
    let onRefreshWhispers: (String) -> Void
    let onAcceptWhisper: (GhostSuggestion) -> Void
    let onDismissWhisper: (UUID) -> Void
    let onHoverSource: (String?) -> Void

    var body: some View {
        GeometryReader { geo in
            let metrics = ConnectionWorkspaceMetrics(width: geo.size.width)

            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                workspace(metrics: metrics, availableWidth: geo.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 96)
            .padding(.horizontal, metrics.outerPadding)
            .padding(.bottom, 140)
        }
    }

    @ViewBuilder
    private func workspace(metrics: ConnectionWorkspaceMetrics, availableWidth: CGFloat) -> some View {
        switch metrics.breakpoint {
        case .wide:
            HStack(alignment: .top, spacing: metrics.columnSpacing) {
                wellColumn
                    .frame(width: metrics.wellWidth)
                forgeColumn(metrics: metrics)
                atelierColumn(metrics: metrics)
                    .frame(width: metrics.atelierWidth)
            }

        case .medium:
            HStack(alignment: .top, spacing: metrics.columnSpacing) {
                wellColumn
                    .frame(width: metrics.wellWidth)
                forgeColumn(metrics: metrics)
                atelierColumn(metrics: metrics)
                    .frame(width: metrics.atelierWidth)
            }

        case .narrow:
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                forgeColumn(metrics: metrics)
                wellColumn
                atelierColumn(metrics: metrics)
            }
        }
    }

    private var wellColumn: some View {
        WellSourcesBlock(
            sources: sources,
            suggestedSources: suggestedSources,
            whispersBySource: whispersBySource,
            contributionsBySource: contributionsBySource,
            isShowingSuggestions: isShowingSuggestions,
            isLoadingSuggestions: isLoadingSuggestions,
            onAddSource: onAddSource,
            onRequestSuggestions: onRequestSuggestions,
            onLinkSuggestedSource: onLinkSuggestedSource,
            onSourceTap: onSourceTap,
            onRefreshWhispers: onRefreshWhispers,
            onAcceptWhisper: onAcceptWhisper,
            onDismissWhisper: onDismissWhisper,
            onHoverSource: onHoverSource
        )
    }

    private func forgeColumn(metrics: ConnectionWorkspaceMetrics) -> some View {
        TheForgeView(
            title: $title,
            conceptType: $conceptType,
            state: $state,
            activeDraftProposal: $activeDraftProposal,
            previewStore: previewStore,
            onAddItem: onAddItem,
            onEditItem: onEditItem,
            onDeleteItem: onDeleteItem,
            onSourceTap: onSourceTap,
            onAcceptGhost: onAcceptGhost,
            onDismissGhost: onDismissGhost,
            onEnterStationMode: onEnterStationMode,
            onTitleCommit: onTitleCommit,
            sourceCount: sourceCount,
            insightCount: state.collaboratorObservationCount,
            maturityLabel: maturityLabel,
            stationWidth: metrics.stationWidth,
            stationColumns: metrics.stationColumns,
            columnSpacing: metrics.stationSpacing,
            rowSpacing: metrics.stationSpacing
        )
    }

    private func atelierColumn(metrics: ConnectionWorkspaceMetrics) -> some View {
        ConnectionAtelierDockView(
            collaboratorMessages: $collaboratorMessages,
            activeDraftProposal: $activeDraftProposal,
            previewStore: previewStore,
            frameworkTitle: frameworkTitle,
            conceptType: conceptType,
            isCollaboratorThinking: isCollaboratorThinking,
            linkedSourceCount: linkedSourceCount,
            insights: insights,
            isRefreshingInsights: isRefreshingInsights,
            onSendMessage: onSendMessage,
            onCrystallizeMessage: onCrystallizeMessage,
            onInsertDraft: onInsertDraft,
            onReviseDraft: onReviseDraft,
            onMoveDraft: onMoveDraft,
            onDismissDraft: onDismissDraft,
            onResumeDraft: onResumeDraft,
            onUseLinkedSources: onUseLinkedSources,
            onRefreshInsights: onRefreshInsights,
            onDismissInsight: onDismissInsight,
            collaboratorHeight: metrics.atelierHeight
        )
    }
}

private struct ConnectionWorkspaceMetrics {
    enum Breakpoint {
        case wide
        case medium
        case narrow
    }

    let breakpoint: Breakpoint
    let outerPadding: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let stationSpacing: CGFloat
    let wellWidth: CGFloat
    let atelierWidth: CGFloat
    let atelierHeight: CGFloat
    let stationWidth: CGFloat
    let stationColumns: Int

    init(width: CGFloat) {
        let stationTargetWidth: CGFloat = 372
        let compactStationMaxWidth: CGFloat = 360
        let atelierTargetWidth: CGFloat = 340
        let atelierTargetHeight: CGFloat = 500
        let wideOuterPadding: CGFloat = 40
        let wideColumnSpacing: CGFloat = 24
        let wideStationSpacing: CGFloat = 16
        let wideWellWidth: CGFloat = 272
        let wideAtelierWidth: CGFloat = atelierTargetWidth
        let wideAvailableStationWidth = floor(
            (width
             - wideOuterPadding * 2
             - wideWellWidth
             - wideAtelierWidth
             - wideColumnSpacing * 2
             - wideStationSpacing * 3) / 4
        )

        let mediumOuterPadding: CGFloat = 32
        let mediumColumnSpacing: CGFloat = 24
        let mediumStationSpacing: CGFloat = 16
        let mediumWellWidth: CGFloat = 272
        let mediumAtelierWidth: CGFloat = atelierTargetWidth
        let mediumAvailableStationWidth = floor(
            (width
             - mediumOuterPadding * 2
             - mediumAtelierWidth
             - mediumColumnSpacing
             - mediumStationSpacing * 3) / 4
        )

        if wideAvailableStationWidth >= 188 {
            breakpoint = .wide
            outerPadding = wideOuterPadding
            columnSpacing = wideColumnSpacing
            rowSpacing = 24
            stationSpacing = wideStationSpacing
            wellWidth = wideWellWidth
            atelierWidth = wideAtelierWidth
            atelierHeight = atelierTargetHeight
            stationWidth = stationTargetWidth
            stationColumns = 4
        } else if mediumAvailableStationWidth >= 192 {
            breakpoint = .medium
            outerPadding = mediumOuterPadding
            columnSpacing = mediumColumnSpacing
            rowSpacing = 24
            stationSpacing = mediumStationSpacing
            wellWidth = mediumWellWidth
            atelierWidth = mediumAtelierWidth
            atelierHeight = atelierTargetHeight
            stationWidth = stationTargetWidth
            stationColumns = 4
        } else {
            breakpoint = .narrow
            outerPadding = 24
            columnSpacing = 20
            rowSpacing = 20
            stationSpacing = 16
            wellWidth = width
            atelierWidth = width
            atelierHeight = atelierTargetHeight
            stationColumns = width >= 860 ? 2 : 1
            let availableWidth = width
                - outerPadding * 2
                - stationSpacing * CGFloat(max(stationColumns - 1, 0))
            stationWidth = max(260, min(compactStationMaxWidth, floor(availableWidth / CGFloat(stationColumns))))
        }
    }
}
