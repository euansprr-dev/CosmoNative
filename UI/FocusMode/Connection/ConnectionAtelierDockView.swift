// CosmoOS/UI/FocusMode/Connection/ConnectionAtelierDockView.swift
// April 2026 — docked Atelier rail for collaborator + live insights

import SwiftUI

struct ConnectionAtelierDockView: View {

    @Binding var collaboratorMessages: [CollaboratorMessage]

    let frameworkTitle: String
    let conceptType: ConceptFrameworkType
    let isCollaboratorThinking: Bool
    let insights: [LiveInsight]
    let isRefreshingInsights: Bool
    let onSendMessage: (String) -> Void
    let onCrystallizeMessage: (CollaboratorMessage) -> Void
    let onRefreshInsights: () -> Void
    let onDismissInsight: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MarginaliaLabel("THE ATELIER")
            ConceptCollaboratorPanel(
                messages: $collaboratorMessages,
                frameworkTitle: frameworkTitle,
                conceptType: conceptType,
                isThinking: isCollaboratorThinking,
                onSend: onSendMessage,
                onCrystallize: onCrystallizeMessage
            )
            .frame(minHeight: 340)

            if isRefreshingInsights || !insights.isEmpty {
                LiveInsightsPanel(
                    insights: insights,
                    isRefreshing: isRefreshingInsights,
                    onRefresh: onRefreshInsights,
                    onDismiss: onDismissInsight
                )
                .frame(minHeight: insights.isEmpty ? 104 : 180)
            } else {
                quietInsightsPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quietInsightsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE INSIGHTS")
                .font(DS.smallCaps)
                .tracking(1.8)
                .foregroundStyle(DS.giltMuted)
            Text("The room stays quiet until the framework has enough tension to say something useful.")
                .font(.system(size: 11, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkFaded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DS.vellumDeep.opacity(0.35), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.sepiaBorder.opacity(0.75), lineWidth: 0.5)
        )
    }
}
