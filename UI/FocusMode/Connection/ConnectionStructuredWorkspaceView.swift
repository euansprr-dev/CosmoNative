// CosmoOS/UI/FocusMode/Connection/ConnectionStructuredWorkspaceView.swift
// April 2026 — governed connection workspace

import SwiftUI

struct ConnectionStructuredWorkspaceView: View {

    @Binding var title: String
    @Binding var conceptType: ConceptFrameworkType
    @Binding var state: ConnectionFocusModeState
    @Binding var collaboratorMessages: [CollaboratorMessage]

    let frameworkTitle: String
    let isCollaboratorThinking: Bool
    let insights: [LiveInsight]
    let isRefreshingInsights: Bool
    let sourceCount: Int
    let usageCount: Int
    let referenceCount: Int
    let profileCount: Int
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
                atelierColumn
                    .frame(width: metrics.atelierWidth)
            }

        case .medium:
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                HStack(alignment: .top, spacing: metrics.columnSpacing) {
                    wellColumn
                        .frame(width: metrics.wellWidth)
                    forgeColumn(metrics: metrics)
                }

                atelierColumn
                    .frame(width: min(metrics.atelierWidth, availableWidth - metrics.outerPadding * 2))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, metrics.wellWidth + metrics.columnSpacing)
            }

        case .narrow:
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                forgeColumn(metrics: metrics)
                wellColumn
                atelierColumn
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
            onAddItem: onAddItem,
            onEditItem: onEditItem,
            onDeleteItem: onDeleteItem,
            onSourceTap: onSourceTap,
            onAcceptGhost: onAcceptGhost,
            onDismissGhost: onDismissGhost,
            onEnterStationMode: onEnterStationMode,
            onTitleCommit: onTitleCommit,
            sourceCount: sourceCount,
            insightCount: insights.count,
            usageCount: usageCount,
            referenceCount: referenceCount,
            profileCount: profileCount,
            maturityLabel: maturityLabel,
            stationWidth: metrics.stationWidth,
            stationColumns: metrics.stationColumns,
            columnSpacing: metrics.stationSpacing,
            rowSpacing: metrics.stationSpacing
        )
    }

    private var atelierColumn: some View {
        ConnectionAtelierDockView(
            collaboratorMessages: $collaboratorMessages,
            frameworkTitle: frameworkTitle,
            conceptType: conceptType,
            isCollaboratorThinking: isCollaboratorThinking,
            insights: insights,
            isRefreshingInsights: isRefreshingInsights,
            onSendMessage: onSendMessage,
            onCrystallizeMessage: onCrystallizeMessage,
            onRefreshInsights: onRefreshInsights,
            onDismissInsight: onDismissInsight
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
    let stationWidth: CGFloat
    let stationColumns: Int

    init(width: CGFloat) {
        let wideOuterPadding: CGFloat = 48
        let wideColumnSpacing: CGFloat = 28
        let wideStationSpacing: CGFloat = 18
        let wideWellWidth: CGFloat = 296
        let wideAtelierWidth: CGFloat = 332
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
        let mediumStationSpacing: CGFloat = 18
        let mediumWellWidth: CGFloat = 280
        let mediumAvailableStationWidth = floor(
            (width
             - mediumOuterPadding * 2
             - mediumWellWidth
             - mediumColumnSpacing
             - mediumStationSpacing * 3) / 4
        )

        if wideAvailableStationWidth >= 208 {
            breakpoint = .wide
            outerPadding = wideOuterPadding
            columnSpacing = wideColumnSpacing
            rowSpacing = 28
            stationSpacing = wideStationSpacing
            wellWidth = wideWellWidth
            atelierWidth = wideAtelierWidth
            stationWidth = min(256, wideAvailableStationWidth)
            stationColumns = 4
        } else if mediumAvailableStationWidth >= 196 {
            breakpoint = .medium
            outerPadding = mediumOuterPadding
            columnSpacing = mediumColumnSpacing
            rowSpacing = 24
            stationSpacing = mediumStationSpacing
            wellWidth = mediumWellWidth
            atelierWidth = 332
            stationWidth = min(236, mediumAvailableStationWidth)
            stationColumns = 4
        } else {
            breakpoint = .narrow
            outerPadding = 24
            columnSpacing = 20
            rowSpacing = 20
            stationSpacing = 16
            wellWidth = width
            atelierWidth = width
            stationColumns = width >= 860 ? 2 : 1
            let availableWidth = width
                - outerPadding * 2
                - stationSpacing * CGFloat(max(stationColumns - 1, 0))
            stationWidth = max(220, min(320, floor(availableWidth / CGFloat(stationColumns))))
        }
    }
}
