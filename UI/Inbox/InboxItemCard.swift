// CosmoOS/UI/Inbox/InboxItemCard.swift
// Individual inbox item card with classification badge and action buttons
// March 2026

import SwiftUI

struct InboxItemCard: View {
    let item: InboxItem
    let isProcessing: Bool
    let onAccept: () -> Void
    let onOverride: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: badge + source icon + timestamp
            HStack(spacing: 8) {
                classificationBadge
                sourceIcon
                Spacer()
                timestampLabel
            }

            // Title
            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(1)
            }

            // Raw text preview
            Text(item.rawText)
                .font(.system(size: 13))
                .foregroundColor(DS.textSecondary)
                .lineLimit(3)

            // Suggestion line
            suggestionLine

            // Action buttons
            if isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textMuted)
                }
                .padding(.top, 4)
            } else {
                actionButtons
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? DS.accent.opacity(0.2) : DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .onHover { isHovered = $0 }
    }

    // MARK: - Classification Badge

    @ViewBuilder
    private var classificationBadge: some View {
        let (label, bg, fg) = badgeStyle

        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
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
            return ("New", Color(hex: "818CF8").opacity(0.12), Color(hex: "818CF8"))
        case .none:
            return ("Classifying...", DS.surface, DS.textMuted)
        }
    }

    // MARK: - Source Icon

    @ViewBuilder
    private var sourceIcon: some View {
        let icon: String = {
            switch item.source {
            case .telegramVoice: return "mic.fill"
            case .telegramText: return "message.fill"
            case .quickCapture: return "bolt.fill"
            }
        }()

        Image(systemName: icon)
            .font(.system(size: 10))
            .foregroundColor(DS.textMuted)
    }

    // MARK: - Timestamp

    private var timestampLabel: some View {
        Text(relativeTime)
            .font(.system(size: 11))
            .foregroundColor(DS.textMuted)
    }

    private var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: item.createdAt) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    // MARK: - Suggestion Line

    @ViewBuilder
    private var suggestionLine: some View {
        switch item.classification {
        case .merge:
            if let targetTitle = item.mergeTargetTitle {
                let pct = Int(item.confidence * 100)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 10))
                    Text("Merge with:")
                        .font(.system(size: 12))
                    Text(targetTitle)
                        .font(.system(size: 12, weight: .medium))
                    Text("(\(pct)%)")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textMuted)
                }
                .foregroundColor(DS.orange)
            }

        case .place:
            if let tsName = item.placeThinkspaceName {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 10))
                    Text("Place in:")
                        .font(.system(size: 12))
                    Text(tsName)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(DS.accent)
            }

        case .new:
            let typeName = item.placeAtomType?.capitalized ?? "Note"
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 10))
                Text("Create as:")
                    .font(.system(size: 12))
                Text(typeName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Color(hex: "818CF8"))

        case .none:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Analyzing...")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Accept button
            Button(action: onAccept) {
                acceptButtonLabel
            }
            .buttonStyle(.plain)

            // Override button
            Button(action: onOverride) {
                Text("Change")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DS.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var acceptButtonLabel: some View {
        let label: String = {
            switch item.classification {
            case .merge: return "Merge"
            case .place: return "Place"
            case .new: return "Create"
            case .none: return "Create"
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(DS.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
