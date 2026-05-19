// CosmoOS/UI/CommandK/CortexRecentCard.swift
// Compact card for recent items — Atelier language, real document thumbnails.

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
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .fill(DS.vellum)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .strokeBorder(isHovered ? DS.sepiaBorder : DS.sepiaSubtle, lineWidth: isHovered ? 1 : 0.5)
            )
            .overlay(alignment: .topLeading) { hoverBracket }
            .clipShape(.rect(cornerRadius: DS.radiusMedium))
            .modifier(RecentCardShadow(isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: DS.radiusMedium))
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
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
            accentChip
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                .strokeBorder(DS.sepiaSubtle, lineWidth: 0.5)
        )
    }

    private var thumbnailBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                .fill(thumbnailSurface)
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

    private var accentChip: some View {
        Capsule(style: .continuous)
            .fill(accentColor.opacity(isHovered ? 0.85 : 0.55))
            .frame(width: 16, height: 3)
            .padding(5)
            .accessibilityHidden(true)
    }

    private var hoverBracket: some View {
        GiltCornerBracket()
            .stroke(DS.gilt, lineWidth: 0.8)
            .frame(width: 10, height: 10)
            .padding(DS.space6)
            .opacity(isHovered ? 0.55 : 0)
            .allowsHitTesting(false)
    }

    // MARK: - Label

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(item.title)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: DS.space4) {
                Text(item.type.displayName)
                Text("·")
                Text(item.relativeDate)
            }
            .font(DS.caption2)
            .foregroundStyle(DS.inkFaded)
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

    private var thumbnailSurface: Color {
        isDocumentPreview ? CommandKPreviewPaper.fill : DS.vellumDeep
    }

    private var isDocumentPreview: Bool {
        let hasImage = item.thumbnailURL?.isEmpty == false
        return !hasImage && item.type != .connection
    }
}

private struct RecentCardShadow: ViewModifier {
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
