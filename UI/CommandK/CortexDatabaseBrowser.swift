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
        } else if item.atomType == .connection {
            SpotlightConnectionPreview(preview: item.preview, accentColor: item.color)
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

    private var isDocumentPreview: Bool {
        let hasImage = item.thumbnailURL?.isEmpty == false
        return !hasImage && item.atomType != .connection
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

// MARK: - Connection Preview (miniature section cards)

struct SpotlightConnectionPreview: View {
    let preview: String?
    let accentColor: Color

    // Section definitions matching the connection focus mode
    private static let sectionDefs: [(key: String, label: String, color: Color)] = [
        ("IDEA", "Idea", Color(hex: "#6B6EA8")),
        ("BELIEF", "Belief", Color(hex: "#5B84B0")),
        ("GOAL", "Goal", Color(hex: "#38B764")),
        ("PROBLEMS", "Problems", Color(hex: "#D97706")),
        ("BENEFIT", "Benefits", Color(hex: "#38B764").opacity(0.8)),
        ("OBJECTIONS", "Objections", Color(hex: "#8B6BAB")),
        ("EXAMPLE", "Examples", Color(hex: "#D17B4F")),
        ("PROCESS", "Process", Color(hex: "#5B84B0").opacity(0.8)),
        ("NOTES", "Notes", Color(hex: "#9B8A6E")),
    ]

    private var sections: [(label: String, color: Color, hasContent: Bool)] {
        guard let preview, !preview.isEmpty else {
            // No data — show all sections as empty
            return Self.sectionDefs.map { ($0.label, $0.color, false) }
        }
        // Section headers live at the top of the text; never scan an
        // unbounded body on the render path.
        let scanText = String(preview.prefix(4000))
        let blocks = Set(scanText.components(separatedBy: "\n\n").compactMap {
            $0.components(separatedBy: "\n").first
        })
        return Self.sectionDefs.map { def in
            (def.label, def.color, blocks.contains(def.key))
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionBar(section)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .padding(4)
    }

    private func sectionBar(_ section: (label: String, color: Color, hasContent: Bool)) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(section.color)
                .frame(width: 3, height: 3)
            Text(section.label)
                .font(.system(size: 3.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
            Spacer(minLength: 0)
            if section.hasContent {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(section.color.opacity(0.3))
                    .frame(width: 8, height: 3)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, section.hasContent ? 3 : 2)
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(section.hasContent ? 0.08 : 0.04))
        )
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
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(DS.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                SpotlightFauxPage(accentColor: DS.textMuted)
            }
        }
    }

    private var localThumbnail: some View {
        // Async + downsampled: the old sync NSImage(contentsOfFile:) decoded
        // full-resolution files on the main thread while the grid scrolled.
        LocalFileThumbnail(path: urlString) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel("Image thumbnail")
        } placeholder: {
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


