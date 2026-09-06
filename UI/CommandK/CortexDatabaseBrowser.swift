// CosmoOS/UI/CommandK/CortexDatabaseBrowser.swift
// Shared ⌘K preview infrastructure. The CortexDatabaseBrowser view itself was
// deleted July 2026 (dead since the master-detail refactor); what remains —
// the rail data source, thumbnails, preview excerpts, and the Spotlight
// preview family — is live in CortexMasterDetailView / CortexResultRail /
// CortexDetailPane.
// Spotlight-style document thumbnail grid with full content previews

import SwiftUI

struct CommandKLibraryThumbnail: View {
    let item: LibraryItem
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(thumbnailSurface)
            thumbnailContent
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.64), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailURL = item.thumbnailURL, !thumbnailURL.isEmpty {
            SpotlightImageContent(urlString: thumbnailURL)
        } else if let preview = item.preview, !preview.isEmpty,
                  item.atomType != .project, item.atomType != .thinkspace {
            SpotlightPageContent(text: preview, accentColor: item.color)
        } else if item.atomType == .project || item.atomType == .thinkspace {
            SpotlightFolderContent(item: item)
        } else {
            SpotlightFauxPage(accentColor: item.color)
        }
    }

    private var thumbnailSurface: Color {
        isDocumentPreview ? CommandKPreviewPaper.fill : DS.glassCardFill.opacity(0.50)
    }

    // Connections never reach this thumbnail — CortexPreviewBlock intercepts
    // them with the manuscript preview before the .library dispatch.
    private var isDocumentPreview: Bool {
        item.thumbnailURL?.isEmpty != false
    }
}

enum CommandKDatabaseBrowserDataSource {
    static func visibleItems(
        allItems: [LibraryItem],
        displayItems: [LibraryItem],
        recentlyDeletedItems: [LibraryItem],
        isAtHome: Bool,
        showingRecentlyDeleted: Bool
    ) -> [LibraryItem] {
        if showingRecentlyDeleted {
            return recentlyDeletedItems
        }

        return isAtHome ? allItems : displayItems
    }
}



// MARK: - Mini Document Page (full text at thumbnail scale)

/// ⌘K preview surfaces must never typeset unbounded text: SwiftUI `Text`
/// runs a full CoreText metrics pass over the entire string on the main
/// thread, so one transcript-sized atom body freezes the whole app.
/// Clamp inside the shared leaf views (so no caller can regress) AND at
/// the display-model choke points (so giant strings never ride view state).
enum CommandKPreviewExcerpt {
    /// Fills a 4pt-font thumbnail page with room to spare.
    static let thumbnailLimit = 500
    /// Serif reading excerpt in the detail pane's fixed-height preview card.
    static let readingLimit = 3000

    static func clamp(_ text: String, limit: Int) -> String {
        let excerpt = text.prefix(limit)
        guard excerpt.endIndex < text.endIndex else { return text }
        return String(excerpt) + "…"
    }

    static func clampOptional(_ text: String?, limit: Int) -> String? {
        text.map { clamp($0, limit: limit) }
    }
}

struct SpotlightPageContent: View {
    let text: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Colored header accent bar
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(accentColor.opacity(0.4))
                .frame(height: 2)

            // Excerpt rendered tiny — creates document texture
            Text(CommandKPreviewExcerpt.clamp(text, limit: CommandKPreviewExcerpt.thumbnailLimit))
                .font(.system(size: 4, weight: .regular))
                .foregroundStyle(CommandKPreviewPaper.text.opacity(0.85))
                .multilineTextAlignment(.leading)
                .lineSpacing(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(CommandKPreviewPaper.fill)
        )
        .padding(4)
    }
}

// MARK: - Faux Page (empty atoms — simulates blank document)

struct SpotlightFauxPage: View {
    let accentColor: Color

    private let lineWidths: [CGFloat] = [1.0, 0.85, 0.92, 0.7, 0.95, 0.6, 0.88, 0.45]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(accentColor.opacity(0.3))
                .frame(height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lineWidths.enumerated()), id: \.offset) { _, fraction in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(CommandKPreviewPaper.text.opacity(0.15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 2)
                        .scaleEffect(x: fraction, anchor: .leading)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(CommandKPreviewPaper.fill)
        )
        .padding(4)
    }
}

// MARK: - Image Thumbnail

struct SpotlightImageContent: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { geo in
            Group {
                if urlString.hasPrefix("http") {
                    asyncThumbnail
                } else {
                    localThumbnail
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .clipShape(.rect(cornerRadius: 4))
        .padding(4)
    }

    private var asyncThumbnail: some View {
        CachedAsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .empty:
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(DS.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                unavailableImage
            }
        }
    }

    private var localThumbnail: some View {
        // Async + downsampled: the old sync NSImage(contentsOfFile:) decoded
        // full-resolution files on the main thread while the grid scrolled.
        LocalFileThumbnail(path: urlString) { image in
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .accessibilityLabel(contentMode == .fit ? "Full image preview" : "Image thumbnail")
        } placeholder: {
            unavailableImage
        }
    }

    @ViewBuilder
    private var unavailableImage: some View {
        if contentMode == .fit {
            Label("Image preview unavailable", systemImage: "photo")
                .font(DS.caption).foregroundStyle(DS.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SpotlightFauxPage(accentColor: DS.textMuted)
        }
    }
}

// MARK: - Folder / Thinkspace Preview

private struct SpotlightFolderContent: View {
    let item: LibraryItem

    var body: some View {
        VStack(spacing: DS.space4) {
            Image(systemName: item.atomType == .thinkspace ? "rectangle.3.group" : "folder.fill")
                .font(.system(size: 24))
                .foregroundStyle(item.color.opacity(0.7))
                .accessibilityHidden(true)

            Text(countLabel)
                .font(DS.caption2)
                .foregroundStyle(CommandKPreviewPaper.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(CommandKPreviewPaper.fill)
                .padding(4)
        )
    }

    private var countLabel: String {
        if item.atomType == .thinkspace {
            return "\(item.blockCount) block\(item.blockCount == 1 ? "" : "s")"
        }
        return "\(item.childCount) item\(item.childCount == 1 ? "" : "s")"
    }
}

