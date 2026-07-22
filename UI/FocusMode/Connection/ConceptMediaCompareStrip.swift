// CosmoOS/UI/FocusMode/Connection/ConceptMediaCompareStrip.swift
// Side-by-side comparison of 2–4 ⌘-selected gallery media — the swipe-study
// pattern-comparison habit brought onto the concept board. Static stills
// only (the Stage owns playback); click a panel to open it there.
// July 2026

import SwiftUI

struct ConceptMediaCompareStrip: View {
    /// The compared refs, in gallery order.
    let items: [ConnectionMediaItem]
    let atoms: [String: Atom]
    let onOpen: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.space12) {
                header
                HStack(alignment: .top, spacing: DS.space12) {
                    ForEach(items) { item in
                        comparePanel(item)
                    }
                }
            }
            .padding(DS.space20)
            .frame(maxWidth: 1100)
            .background(DS.surfaceElevated)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DS.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
            .padding(DS.space48)
            .onTapGesture { /* absorb */ }
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "rectangle.split.2x1")
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.textSecondary)
                .accessibilityHidden(true)
            Text("Compare")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)
            Text("click a panel to open it in the Stage")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close comparison")
        }
    }

    private func comparePanel(_ item: ConnectionMediaItem) -> some View {
        let atom = item.atomUUID.flatMap { atoms[$0] }
        return Button {
            onOpen(item.id)
        } label: {
            VStack(alignment: .leading, spacing: DS.space6) {
                panelImage(item, atom: atom)
                    .aspectRatio(3 / 4, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
                    .overlay(alignment: .center) {
                        if item.kind == .video {
                            Image(systemName: "play.circle")
                                .font(DS.title2.weight(.thin))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.4), radius: 6)
                                .accessibilityHidden(true)
                        }
                    }
                Text(item.caption ?? atom?.title ?? item.assetTitle ?? "Media")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                if let hook = atom?.swipeAnalysis?.hookText, !hook.isEmpty {
                    Text(hook)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(item.caption ?? atom?.title ?? "media") in the Stage")
    }

    @ViewBuilder
    private func panelImage(_ item: ConnectionMediaItem, atom: Atom?) -> some View {
        if let poster = item.thumbnailAssetPath {
            ConceptLocalThumbnail(path: poster, maxPixel: 800)
        } else if let path = item.assetPath, !MediaAssetStore.isVideoPath(path) {
            ConceptLocalThumbnail(path: path, maxPixel: 800)
        } else if let atom, let url = ConceptMediaThumbnailResolver.thumbnailURL(for: atom) {
            CachedAsyncImage(url: url, stableKey: "compare-\(ConceptMediaThumbnailResolver.stableKey(for: item))") { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle().fill(DS.glassSectionFill)
                @unknown default:
                    Rectangle().fill(DS.glassSectionFill)
                }
            }
        } else {
            Rectangle().fill(DS.glassSectionFill)
        }
    }
}
