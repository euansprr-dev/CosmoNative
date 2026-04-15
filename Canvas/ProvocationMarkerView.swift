// CosmoOS/Canvas/ProvocationMarkerView.swift
// Diamond-shaped provocation badge on block edges with expandable detail card.
// February 2026 — WP7 Provocation Layer

import SwiftUI

struct ProvocationMarkerView: View {
    let provocation: Provocation
    let onDismiss: () -> Void
    let onResolve: () -> Void
    let onAcceptAsTask: () -> Void

    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Diamond badge
            diamondBadge
                .onTapGesture {
                    withAnimation(ProMotionSprings.snappy) {
                        isExpanded.toggle()
                    }
                }
                .onHover { isHovering = $0 }

            // Expanded card
            if isExpanded {
                expandedCard
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
    }

    // MARK: - Diamond Badge

    private var diamondBadge: some View {
        Image(systemName: provocation.type.icon)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(DS.textOnAccent)
            .frame(width: 16, height: 16)
            .background(
                provocation.type.color
                    .opacity(isHovering ? 1.0 : 0.85)
            )
            .clipShape(DiamondShape())
            .shadow(
                color: provocation.type.color.opacity(0.4),
                radius: isHovering ? 4 : 2,
                y: 1
            )
    }

    // MARK: - Expanded Card

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            cardHeader

            // Description
            Text(provocation.description)
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            // Evidence quotes
            if !provocation.evidenceQuotes.isEmpty {
                evidenceSection
            }

            // Suggested resolution
            if let resolution = provocation.suggestedResolution {
                Text(resolution)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .italic()
            }

            // Actions
            HStack(spacing: 8) {
                actionButton("Dismiss", icon: "xmark", action: onDismiss)
                actionButton("Resolve", icon: "checkmark", action: onResolve)
                actionButton("Task", icon: "plus.circle", action: onAcceptAsTask)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(DS.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(provocation.type.color.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: provocation.type.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(provocation.type.color)

            Text(provocation.type.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(provocation.type.color)

            Spacer()

            Text("\(Int(provocation.confidence * 100))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(provocation.evidenceQuotes, id: \.self) { quote in
                Text(quote)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(3)
            }
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.border.opacity(0.3))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Diamond Shape

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let hw = rect.width / 2
        let hh = rect.height / 2
        path.move(to: CGPoint(x: cx, y: cy - hh))
        path.addLine(to: CGPoint(x: cx + hw, y: cy))
        path.addLine(to: CGPoint(x: cx, y: cy + hh))
        path.addLine(to: CGPoint(x: cx - hw, y: cy))
        path.closeSubpath()
        return path
    }
}
