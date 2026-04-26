import SwiftUI

private enum InboxSpatialCardMetrics {
    static let cornerRadius: CGFloat = 14
    static let minHeight: CGFloat = 132
    static let hoverLift: CGFloat = -1
}

struct InboxSpatialItemCard: View {
    let item: InboxItem
    let isSelected: Bool
    let isProcessing: Bool
    let onSelect: () -> Void
    let onAccept: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            topRow
            preview
            routeLine
            Spacer(minLength: 0)
            actionRow
        }
        .padding(DS.space12)
        .frame(minHeight: InboxSpatialCardMetrics.minHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(background)
        .overlay(border)
        .dsRestingShadow()
        .offset(y: isHovered ? InboxSpatialCardMetrics.hoverLift : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(item.spatialActionTitle) inbox item")
    }

    private var topRow: some View {
        HStack(spacing: DS.space6) {
            Text(item.spatialActionTitle.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(actionColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(actionColor.opacity(0.12), in: Capsule())

            Spacer()

            Text(item.confidenceLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.textMuted)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(item.rawText)
                .font(.system(size: 12))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private var routeLine: some View {
        HStack(spacing: 5) {
            Image(systemName: item.classification == .merge ? "arrow.triangle.merge" : "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
            Text(item.spatialDestinationTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(actionColor)
    }

    @ViewBuilder
    private var actionRow: some View {
        if isProcessing {
            HStack(spacing: DS.space6) {
                ProgressView().scaleEffect(0.6)
                Text("Processing")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        } else {
            HStack {
                Button(action: onAccept) {
                    Label(primaryActionLabel, systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(actionColor, in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }

    private var primaryActionLabel: String {
        switch item.classification {
        case .merge: return "Merge"
        case .place: return "Place"
        case .new: return "Create"
        case .none: return "Confirm"
        }
    }

    private var actionColor: Color {
        switch item.classification {
        case .merge: return DS.orange
        case .place: return DS.accent
        case .new: return DS.entityIdea
        case .none: return DS.textMuted
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: InboxSpatialCardMetrics.cornerRadius, style: .continuous)
            .fill(isSelected ? DS.accentSoft.opacity(0.18) : DS.glassCardFill)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: InboxSpatialCardMetrics.cornerRadius, style: .continuous)
            .strokeBorder(
                isSelected ? DS.accent.opacity(0.5) : DS.sepiaSubtle,
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}

struct InboxSpatialDatabaseCard: View {
    let item: InboxDatabaseCandidate
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            topRow
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(item.preview)
                .font(.system(size: 12))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Label("Needs thinkspace home", systemImage: "tray.full")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.accent)
                .lineLimit(1)
        }
        .padding(DS.space12)
        .frame(minHeight: InboxSpatialCardMetrics.minHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(background)
        .overlay(border)
        .dsRestingShadow()
        .offset(y: isHovered ? InboxSpatialCardMetrics.hoverLift : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Unplaced database item \(item.title)")
    }

    private var topRow: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: item.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.accent)
                .frame(width: 24, height: 24)
                .background(item.accent.opacity(0.12), in: Circle())

            Text(item.atomType.displayName.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(item.accent)

            Spacer()

            Text(item.relativeDate)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: InboxSpatialCardMetrics.cornerRadius, style: .continuous)
            .fill(isSelected ? DS.accentSoft.opacity(0.18) : DS.glassCardFill)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: InboxSpatialCardMetrics.cornerRadius, style: .continuous)
            .strokeBorder(
                isSelected ? DS.accent.opacity(0.5) : DS.sepiaSubtle,
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}
