// CosmoOS/UI/Inbox/InboxGroupSuggestionCard.swift
// Suggested batch action card for auto-grouped inbox items
// March 2026

import SwiftUI

struct InboxGroupSuggestionCard: View {
    let group: InboxItemGroup
    let onExecute: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space12) {
            iconBadge

            VStack(alignment: .leading, spacing: DS.space2) {
                Text(group.theme)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)

                if let action = group.suggestedAction {
                    Text(action)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textMuted)
                }
            }

            Spacer()

            actionButtons
        }
        .padding(DS.space12)
        .background(DS.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(DS.accent.opacity(0.2), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }

    private var iconBadge: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 14))
            .foregroundStyle(DS.accent)
            .frame(width: 28, height: 28)
            .background(DS.accentSoft, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private var actionButtons: some View {
        HStack(spacing: DS.space6) {
            Button(action: onExecute) {
                Text(group.mergeTargetUuid != nil ? "Merge All" : "Place All")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.textOnAccent)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, DS.space4)
                    .background(DS.accent, in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }
}
