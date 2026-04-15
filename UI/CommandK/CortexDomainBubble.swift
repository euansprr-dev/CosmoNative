// CosmoOS/UI/CommandK/CortexDomainBubble.swift
// Domain bubble for Cortex compact mode — tappable circle with icon, label, and count

import SwiftUI

struct CortexDomainBubble: View {
    let tab: CommandKTab
    let count: Int
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.space8) {
                bubbleCircle
                bubbleLabel
            }
            .opacity(count == 0 ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private var bubbleCircle: some View {
        ZStack {
            Circle()
                .fill(tab.accentColor.opacity(0.10))

            Circle()
                .stroke(isHovered ? tab.accentColor.opacity(0.3) : DS.border.opacity(0.25), lineWidth: 0.5)

            Image(systemName: tab.icon)
                .font(.system(size: 20))
                .foregroundStyle(tab.accentColor)
        }
        .frame(width: CommandKMetrics.domainBubbleSize, height: CommandKMetrics.domainBubbleSize)
        .matchedGeometryEffect(id: "cortexDomain-\(tab.rawValue)", in: namespace)
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .shadow(
            color: .black.opacity(isHovered ? 0.08 : 0.03),
            radius: isHovered ? 12 : 6,
            x: 0,
            y: isHovered ? 4 : 2
        )
    }

    private var bubbleLabel: some View {
        VStack(spacing: 2) {
            Text(tab.title)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)

            Text("\(count)")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }
}
