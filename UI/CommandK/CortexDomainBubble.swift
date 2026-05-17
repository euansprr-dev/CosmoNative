// CosmoOS/UI/CommandK/CortexDomainBubble.swift
// Domain launcher plate for the Command-K compact surface.
// Atelier / Akashic Codex language: vellum surface, sepia hairline,
// one gilt corner bracket, one accent chip. Quiet by default.

import SwiftUI

struct CortexDomainBubble: View {
    let tab: CommandKTab
    let count: Int
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            plate
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tab.title), \(formattedCount) items")
        .accessibilityHint("Open \(tab.title)")
    }

    private var plate: some View {
        textBlock
            .padding(.horizontal, DS.space20)
            .padding(.bottom, DS.space20)
            .frame(
                width: CommandKMetrics.domainCardWidth,
                height: CommandKMetrics.domainCardHeight,
                alignment: .bottomLeading
            )
            .background(plateSurface)
            .overlay(plateBorder)
            .overlay(alignment: .topLeading) { giltBracket }
            .overlay(alignment: .topTrailing) { accentChip }
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
            .matchedGeometryEffect(id: "domain-card-\(tab.rawValue)", in: namespace)
            .modifier(PlateShadow(isHovered: isHovered))
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(tab.title.uppercased())
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.giltMuted)

            Text(tab.compactSubtitle)
                .font(DS.spaceTitleSerif)
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(width: 64, height: 0.5)
                .padding(.vertical, DS.space4)

            Text("\(formattedCount) items")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.inkFaded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plateSurface: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .fill(DS.vellum)
    }

    private var plateBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(DS.sepiaBorder, lineWidth: isHovered ? 1 : 0.5)
    }

    private var giltBracket: some View {
        GiltCornerBracket()
            .stroke(DS.gilt, lineWidth: 0.8)
            .frame(width: 12, height: 12)
            .padding(DS.space10)
            .opacity(isHovered ? 0.85 : 0.55)
            .allowsHitTesting(false)
    }

    private var accentChip: some View {
        Capsule(style: .continuous)
            .fill(tab.accentColor.opacity(isHovered ? 0.70 : 0.40))
            .frame(width: 28, height: 3)
            .padding(DS.space10)
            .allowsHitTesting(false)
    }

    private var formattedCount: String {
        count.formatted(.number)
    }
}

private struct PlateShadow: ViewModifier {
    let isHovered: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isHovered {
            content.dsHoverShadow()
        } else {
            content.dsRestingShadow()
        }
    }
}
