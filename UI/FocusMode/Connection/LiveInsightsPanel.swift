// CosmoOS/UI/FocusMode/Connection/LiveInsightsPanel.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// Rolling AI observations. The second surface in The Atelier. Each insight is a
// vellum chip with a kind glyph, a one-sentence observation, and (optionally) the
// display-name chips of the sections it names. New insights slide in from the
// right with a staggered spring. Empty state is quiet — the room breathes.

import SwiftUI

struct LiveInsightsPanel: View {

    // MARK: - Inputs

    let insights: [LiveInsight]
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onDismiss: (UUID) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(DS.surfaceElevated)
        .overlay(alignment: .bottom) { hairline }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(DS.gilt.opacity(0.7))
                .accessibilityHidden(true)
            Text("LIVE INSIGHTS")
                .font(DS.smallCaps)
                .tracking(1.8)
                .foregroundStyle(DS.giltMuted)
            Spacer()
            if isRefreshing {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            } else {
                refreshButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10))
                .foregroundStyle(DS.giltMuted)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh live insights")
    }

    private var hairline: some View {
        Rectangle().fill(DS.borderSubtle).frame(height: 0.5)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if insights.isEmpty {
            emptyState
        } else {
            insightsList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 16)
            Text("The room is quiet.")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.textMuted)
            Text("Populate two stations to invite observations.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var insightsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                    InsightChip(
                        insight: insight,
                        onDismiss: { onDismiss(insight.id) }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: 12, y: 0).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .animation(
                        ProMotionSprings.bouncy.delay(Double(index) * 0.05),
                        value: insight.id
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Insight Chip

private struct InsightChip: View {

    let insight: LiveInsight
    let onDismiss: () -> Void

    @State private var isHovering: Bool = false

    private var kindColor: Color {
        switch insight.kind {
        case .tension: return Color(hex: "#D97757")        // warm ochre
        case .gap: return DS.giltMuted
        case .echo: return Color(hex: "#8B6BAB")           // entity-connection purple
        case .strength: return Color(hex: "#4A7C59")       // sage green
        case .contradiction: return Color(hex: "#C05040")  // oxidized red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            messageText
            if !insight.relatedSections.isEmpty {
                sectionChips
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.bg.opacity(0.55), in: .rect(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(kindColor.opacity(0.25), lineWidth: 0.5)
        )
        .overlay(alignment: .leading) { leadingAccent }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.kind.label): \(insight.message)")
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: insight.kind.glyph)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(kindColor)
                .accessibilityHidden(true)
            Text(insight.kind.label.uppercased())
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(kindColor.opacity(0.85))
            Spacer(minLength: 4)
            if isHovering {
                dismissButton
            }
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss insight")
    }

    private var messageText: some View {
        Text(insight.message)
            .font(.system(size: 12, weight: .regular, design: .serif))
            .foregroundStyle(DS.text)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(1.5)
    }

    private var sectionChips: some View {
        HStack(spacing: 4) {
            ForEach(insight.relatedSections, id: \.self) { section in
                Text(section.displayName)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(section.accentColor.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().stroke(section.accentColor.opacity(0.35), lineWidth: 0.5)
                    )
            }
        }
    }

    private var leadingAccent: some View {
        Rectangle()
            .fill(kindColor.opacity(0.55))
            .frame(width: 2)
            .clipShape(.rect(cornerRadius: 1))
            .padding(.vertical, 6)
            .padding(.leading, 1)
    }
}
