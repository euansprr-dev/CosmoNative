// CosmoOS/UI/CommandK/CortexRecentCard.swift
// Compact card for recent items in Cortex compact mode — document-style thumbnails

import SwiftUI

struct CortexRecentCard: View {
    let item: RecentDisplayItem
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.space12) {
                thumbnailView
                    .frame(width: 64, height: 74)
                cardLabel
                Spacer(minLength: 0)
            }
            .padding(DS.space10)
            .frame(height: 92)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isHovered ? DS.glassInputFillFocused.opacity(0.72) : DS.glassCardFill.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isHovered ? accentColor.opacity(0.30) : DS.glassBorder.opacity(0.62), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 5 : 2)
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: 13))
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(item.title)
        .accessibilityHint("Open \(item.type.displayName)")
        .commandKCardContextMenu(
            atomUUID: item.id,
            entityId: item.entityId,
            atomType: item.type,
            onDelete: onDelete
        )
    }

    // MARK: - Thumbnail

    private var thumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailBackground
            typeBadge
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isHovered ? accentColor.opacity(0.4) : DS.border.opacity(0.15),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: .black.opacity(isHovered ? 0.12 : 0.04),
            radius: isHovered ? 8 : 3, x: 0,
            y: isHovered ? 3 : 1
        )
    }

    private var thumbnailBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.glassCardFill.opacity(isHovered ? 0.8 : 0.5))
            thumbnailContent
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailURL = item.thumbnailURL, !thumbnailURL.isEmpty {
            SpotlightImageContent(urlString: thumbnailURL)
        } else if item.type == .connection {
            SpotlightConnectionPreview(preview: item.preview, accentColor: accentColor)
        } else if let preview = item.preview, !preview.isEmpty {
            SpotlightPageContent(text: preview, accentColor: accentColor)
        } else {
            SpotlightFauxPage(accentColor: accentColor)
        }
    }

    private var typeBadge: some View {
        Image(systemName: iconForType)
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(accentColor, in: Circle())
            .padding(4)
            .accessibilityHidden(true)
    }

    // MARK: - Label

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: DS.space4) {
                Text(item.type.displayName)
                Text("·")
                Text(item.relativeDate)
            }
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var accentColor: Color {
        switch item.type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .research: return DS.entityResearch
        case .content: return DS.entityContent
        case .connection: return DS.entityConnection
        case .project: return DS.entityIdea
        case .image: return DS.entityImage
        default: return DS.textSecondary
        }
    }

    private var iconForType: String {
        switch item.type {
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .research: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "link.circle.fill"
        case .project: return "folder.fill"
        case .note: return "note.text"
        case .stickyNote: return "note"
        case .image: return "photo.fill"
        default: return "circle.fill"
        }
    }
}
