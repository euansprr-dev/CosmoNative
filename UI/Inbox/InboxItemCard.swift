// CosmoOS/UI/Inbox/InboxItemCard.swift
// Rich inbox item card with entity bar, confidence meter, expandable content,
// hover actions, selection state, stale nudge, and classification progress
// March 2026

import SwiftUI

struct InboxItemCard: View {
    let item: InboxItem
    let isProcessing: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let isFocused: Bool
    let insight: String?
    let onAccept: () -> Void
    let onOverride: () -> Void
    let onDismiss: () -> Void
    let onToggleExpand: () -> Void
    let onToggleSelect: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            cardContent
        }
        .background { styledBackground }
        .overlay(cardBorder)
        .dsRestingShadow()
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            topRow
            titleRow
            textPreview
            confidenceMeter
            suggestionLine
            rationaleLine
            alternativesLine
            insightLine
            staleNudge
            actionRow
        }
        .padding(DS.space16)
    }

    // MARK: - Top Row: Badge + Source + Timestamp

    private var topRow: some View {
        HStack(spacing: DS.space6) {
            if isSelected {
                selectionCheckbox
            }
            classificationBadge
            if !item.isRead {
                unreadDot
            }
            sourceIcon
            Spacer()
            timestampLabel
        }
    }

    private var selectionCheckbox: some View {
        Button(action: onToggleSelect) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
        }
        .buttonStyle(.plain)
    }

    private var classificationBadge: some View {
        let (label, bg, fg) = badgeStyle
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }

    private var badgeStyle: (String, Color, Color) {
        switch item.classification {
        case .merge:
            return ("Merge", DS.orange.opacity(0.12), DS.orange)
        case .place:
            return ("Place", DS.accentSoft, DS.accent)
        case .new:
            return ("New", DS.classNew.opacity(0.12), DS.classNew)
        case .none:
            return ("Classifying...", DS.surface, DS.textMuted)
        }
    }

    private var unreadDot: some View {
        Circle()
            .fill(DS.accent)
            .frame(width: 6, height: 6)
    }

    private var sourceIcon: some View {
        let (icon, label): (String, String) = {
            switch item.source {
            case .telegramVoice: return ("mic.fill", "Voice message")
            case .telegramText: return ("paperplane.fill", "Telegram")
            case .quickCapture: return ("bolt.fill", "Quick capture")
            }
        }()

        return Image(systemName: icon)
            .font(.system(size: 10))
            .foregroundStyle(DS.textMuted)
            .help(label)
    }

    private var timestampLabel: some View {
        Text(relativeTime)
            .font(DS.footnote)
            .foregroundStyle(DS.textMuted)
    }

    // MARK: - Title

    @ViewBuilder
    private var titleRow: some View {
        if let title = item.title, !title.isEmpty {
            Text(title)
                .font(DS.title3)
                .foregroundStyle(DS.text)
                .lineLimit(1)
        }
    }

    // MARK: - Text Preview (Expandable)

    private var textPreview: some View {
        Button(action: onToggleExpand) {
            Text(item.rawText)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(isExpanded ? nil : 3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : BlockAnimations.expand, value: isExpanded)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confidence Meter

    @ViewBuilder
    private var confidenceMeter: some View {
        if item.classification == .merge || item.classification == .place {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.border)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(confidenceColor)
                        .frame(width: geo.size.width * item.confidence, height: 3)
                        .animation(reduceMotion ? nil : ProMotionSprings.gentle, value: item.confidence)
                }
            }
            .frame(height: 3)
        }
    }

    private var confidenceColor: Color {
        if item.confidence > 0.75 { return DS.accent }
        if item.confidence > 0.5 { return DS.orange }
        return DS.textMuted
    }

    // MARK: - Suggestion Line

    @ViewBuilder
    private var suggestionLine: some View {
        switch item.classification {
        case .merge:
            mergeSuggestion
        case .place:
            placeSuggestion
        case .new:
            newSuggestion
        case .none:
            classificationProgress
        }
    }

    @ViewBuilder
    private var mergeSuggestion: some View {
        if let targetTitle = item.mergeTargetTitle {
            let pct = Int(item.confidence * 100)
            HStack(spacing: DS.space4) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 10))
                Text("Merge with:")
                    .font(.system(size: 12))
                Text(targetTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("(\(pct)%)")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
            }
            .foregroundStyle(DS.orange)
        }
    }

    @ViewBuilder
    private var placeSuggestion: some View {
        if let destinationPath = item.destinationPath ?? item.placeThinkspaceName {
            HStack(spacing: DS.space4) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 10))
                Text("Route to:")
                    .font(.system(size: 12))
                Text(destinationPath)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(DS.accent)
        }
    }

    private var newSuggestion: some View {
        let label = item.destinationPath ?? item.placeAtomType?.capitalized ?? "Note"
        return HStack(spacing: DS.space4) {
            Image(systemName: "plus.circle")
                .font(.system(size: 10))
            Text("Create:")
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(DS.classNew)
    }

    private var classificationProgress: some View {
        HStack(spacing: DS.space6) {
            progressDot(label: "Searching", filled: true)
            progressDot(label: "Matching", filled: false)
            progressDot(label: "Ready", filled: false)
        }
    }

    @ViewBuilder
    private var rationaleLine: some View {
        if let rationale = item.rationale,
           !rationale.isEmpty,
           item.classification != nil {
            Text(rationale)
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .lineLimit(isExpanded ? 3 : 2)
        }
    }

    @ViewBuilder
    private var alternativesLine: some View {
        let alternatives = alternativeDestinationPaths
        if !alternatives.isEmpty {
            Text("Also considered: " + alternatives.prefix(2).joined(separator: " • "))
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted.opacity(0.9))
                .lineLimit(1)
        }
    }

    private var alternativeDestinationPaths: [String] {
        guard let json = item.recommendations,
              let data = json.data(using: .utf8),
              let bundle = try? JSONDecoder().decode(InboxRecommendationBundlePayload.self, from: data) else {
            return []
        }
        return Array(bundle.recommendations.dropFirst())
            .map(\.destinationPath)
            .filter { !$0.isEmpty }
    }

    private func progressDot(label: String, filled: Bool) -> some View {
        HStack(spacing: DS.space2) {
            Circle()
                .fill(filled ? DS.accent : DS.border)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(filled ? DS.textSecondary : DS.textMuted)
        }
    }

    // MARK: - Insight Line

    @ViewBuilder
    private var insightLine: some View {
        if let insight {
            Text(insight)
                .font(.system(size: 12).italic())
                .foregroundStyle(DS.textMuted)
                .lineLimit(2)
                .transition(.opacity)
        }
    }

    // MARK: - Stale Nudge

    @ViewBuilder
    private var staleNudge: some View {
        if item.isStale {
            HStack(spacing: DS.space6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 11))
                Text("Captured \(item.ageInDays) days ago — still relevant?")
                    .font(.system(size: 11))
                Spacer()
                Button("Dismiss") {
                    onDismiss()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
            }
            .foregroundStyle(DS.orange)
            .padding(DS.space8)
            .background(DS.orangeSoft, in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
        }
    }

    // MARK: - Action Row

    @ViewBuilder
    private var actionRow: some View {
        if isProcessing {
            processingIndicator
        } else {
            actionButtons
        }
    }

    private var processingIndicator: some View {
        HStack(spacing: DS.space6) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Processing...")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.top, DS.space4)
    }

    private var actionButtons: some View {
        HStack(spacing: DS.space8) {
            acceptButton
            overrideButton
            Spacer()
            dismissButton
        }
        .padding(.top, DS.space4)
        .opacity(isHovered ? 1.0 : 0.85)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private var acceptButton: some View {
        Button(action: onAccept) {
            acceptButtonLabel
        }
        .buttonStyle(.plain)
        .help("Accept suggestion (\u{21A9})")
    }

    @ViewBuilder
    private var acceptButtonLabel: some View {
        let label: String = {
            "Confirm"
        }()

        HStack(spacing: DS.space4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(DS.accent, in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
    }

    private var overrideButton: some View {
        Button(action: onOverride) {
            Text("Change")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 7)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .stroke(DS.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, height: 28)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Dismiss (Delete)")
    }

    // MARK: - Card Chrome

    private var cardBackground: some Shape {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
    }

    @ViewBuilder
    private func cardBackgroundFill() -> some View {
        if isSelected {
            cardBackground.fill(DS.accentSoft.opacity(0.3))
        } else {
            cardBackground.fill(DS.surfaceCard)
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .stroke(borderColor, lineWidth: borderWidth)
    }

    private var borderColor: Color {
        if isFocused { return DS.accent.opacity(0.5) }
        if isSelected { return DS.accent.opacity(0.35) }
        if isHovered { return DS.accent.opacity(0.2) }
        return DS.border
    }

    private var borderWidth: CGFloat {
        (isFocused || isSelected) ? 2 : 1
    }

    // MARK: - Helpers

    private var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: item.createdAt) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    private var accessibilityDescription: String {
        let type = item.classification?.rawValue ?? "pending"
        let title = item.title ?? String(item.rawText.prefix(50))
        return "\(type) inbox item: \(title)"
    }
}

// MARK: - Background Shape Conformance

extension InboxItemCard {
    private struct InboxRecommendationBundlePayload: Decodable {
        let recommendations: [InboxRecommendationPayload]
    }

    private struct InboxRecommendationPayload: Decodable {
        let destinationPath: String
    }

    @ViewBuilder
    var styledBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(DS.accentSoft.opacity(0.3))
        } else {
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(DS.surfaceCard)
        }
    }
}
