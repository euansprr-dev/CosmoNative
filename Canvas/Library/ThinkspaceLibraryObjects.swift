// CosmoOS/Canvas/Library/ThinkspaceLibraryObjects.swift
// The library's object language: quiet macOS folders with identity badges,
// documents as honest objects at icon scale (recognizable, not readable),
// and drag previews that carry the real thing. Shared by every lens so the
// same object never renders two ways.

import SwiftUI
import AppKit

// MARK: - Folder Icon (quiet, machined)

/// The macOS folder silhouette, drawn in the app's material voice: one hue
/// family per folder (chroma pulled toward the page so five folders read as
/// a set, not a crayon box), zero outline strokes, a single contact shadow,
/// and the cluster's emoji identity as a Finder-style badge.
struct LibraryFolderIconV2: View {
    let folder: ThinkspaceLibraryFolder
    var showsBadge = true

    private var baseColor: Color { folder.color.mix(with: DS.bg, by: 0.12) }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let radius = height * 0.11
            ZStack(alignment: .bottom) {
                backPanel
                if !folder.items.isEmpty { paper(size: geo.size, radius: radius) }
                frontFace(height: height * 0.78, radius: radius)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }

    private var backPanel: some View {
        LibraryFolderBackShape()
            .fill(baseColor.mix(with: .black, by: 0.16))
    }

    private func paper(size: CGSize, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius * 0.45, style: .continuous)
            .fill(DS.surfaceCard)
            .frame(width: size.width * 0.82, height: size.height * 0.76)
            .offset(y: -size.height * 0.07)
    }

    private func frontFace(height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(baseColor)
            .overlay(
                // One breath of top light — the only modelling the face gets.
                LinearGradient(
                    colors: [.white.opacity(0.12), .white.opacity(0)],
                    startPoint: .top, endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay { badge(height: height) }
            .frame(height: height)
    }

    @ViewBuilder
    private func badge(height: CGFloat) -> some View {
        if showsBadge, let emoji = folder.identityEmoji {
            Text(emoji)
                .font(.system(size: height * 0.38))
                .opacity(0.92)
        }
    }
}

/// Back panel of a macOS folder: full body with a rounded tab on the top-left
/// that slopes down into the body's top edge.
struct LibraryFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tabWidth = rect.width * 0.40
        let tabHeight = rect.height * 0.14
        let slope = rect.width * 0.10
        let radius = rect.height * 0.11
        let tabRadius = radius * 0.6

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tabRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tabRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + tabWidth - tabRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tabWidth + slope, y: rect.minY + tabHeight),
            control: CGPoint(x: rect.minX + tabWidth + slope * 0.35, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY + tabHeight))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tabHeight + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY + tabHeight)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Document Object (uniform-well renderer)

/// A document rendered as an honest object inside a fixed-height well, so a
/// strict grid stays strict: pages stand portrait, media keeps its true
/// aspect letterboxed within the well, and nothing ever stretches a row.
/// At small/medium scale a page is a *fingerprint* (faux text bars derived
/// from its actual content) — recognizable, not readable, exactly like a
/// Finder thumbnail. Real prose appears only at large scale and in Gallery.
struct LibraryDocumentObject: View {
    let model: ThinkspaceLibraryCardModel
    let wellWidth: CGFloat
    let wellHeight: CGFloat
    var cornerRadius: CGFloat = 8
    /// True below large scale — pages render as miniatures.
    var miniature: Bool = true
    /// Finder's selection grammar: a soft grey rounded backing hugging the
    /// object (never a hard ring). The inset is constant so selecting never
    /// re-layouts the object (structural-identity law).
    var isSelected: Bool = false

    private static let selectionInset: CGFloat = 6

    var body: some View {
        objectBody
            .frame(width: objectSize.width, height: objectSize.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(objectEdge)
            .overlay(alignment: .bottomLeading) { playBadge }
            .padding(Self.selectionInset)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                    .fill(DS.text.opacity(isSelected ? 0.09 : 0))
            )
            .frame(width: wellWidth, height: wellHeight, alignment: .bottom)
    }

    /// Honest aspect, fitted inside the well (minus the selection inset);
    /// pages pin to the well height so every page in a row shares a baseline
    /// (objects stand on a shelf).
    private var objectSize: CGSize {
        let aspect = model.previewAspect
        let maxWidth = wellWidth - Self.selectionInset * 2
        let maxHeight = wellHeight - Self.selectionInset * 2
        let fittedWidth = min(maxWidth, maxHeight * aspect)
        return CGSize(width: fittedWidth, height: fittedWidth / aspect)
    }

    @ViewBuilder
    private var objectBody: some View {
        switch model.previewKind {
        case .media(let source):
            LibraryMediaThumbnail(source: source, accent: model.item.entityType.color)
        case .page(let text):
            // Real content at every scale (the Finder law): the page is
            // typeset once at design size and scaled down, so each document
            // shows its actual words — unreadable at small sizes but
            // instantly distinguishable, never an abstract stand-in.
            if miniature {
                LibraryPageThumbnail(
                    title: model.item.title,
                    text: text,
                    pageStyle: notePageStyle,
                    size: objectSize
                )
            } else {
                LibraryPagePreview(title: model.item.title, text: text, pageStyle: notePageStyle)
            }
        case .connection(let sections, let conceptTypeName):
            // Same law as pages: the concept's actual manuscript, typeset once
            // at design size for miniatures and readable at gallery scale.
            if miniature {
                LibraryManuscriptThumbnail(
                    title: model.item.title,
                    conceptTypeName: conceptTypeName,
                    sections: sections,
                    size: objectSize
                )
            } else {
                LibraryManuscriptPreview(
                    title: model.item.title,
                    conceptTypeName: conceptTypeName,
                    sections: sections
                )
            }
        case .objectMotif(let icon, let tint):
            LibraryObjectMotifWell(icon: icon, tint: tint)
        }
    }

    private var notePageStyle: NoteDocumentStyle? {
        model.item.entityType == .note
            ? NotePageStyleCache.shared.style(for: model.item.entityUuid)
            : nil
    }

    private var objectEdge: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(edgeColor, lineWidth: isPage ? 1 : 0.5)
            .frame(width: objectSize.width, height: objectSize.height)
    }

    private var isPage: Bool {
        switch model.previewKind {
        case .page, .connection: return true
        case .media, .objectMotif: return false
        }
    }

    private var edgeColor: Color {
        isPage ? model.item.entityType.color.opacity(0.35) : DS.glassBorder
    }

    @ViewBuilder
    private var playBadge: some View {
        if model.isVideoMedia, case .media = model.previewKind {
            Image(systemName: "play.fill")
                .font(DS.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(DS.space6)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Page Thumbnail (the real page, scaled — the Finder law)

/// The document's actual first page rendered as a thumbnail: the page is
/// typeset ONCE at a fixed design size (where the type scale is honest), then
/// scaled to the object's size. Real title, real prose, real note styling —
/// so every document is instantly distinguishable at a glance, exactly like a
/// Finder document thumbnail. Never bars, never a stand-in.
struct LibraryPageThumbnail: View {
    let title: String
    let text: String?
    var pageStyle: NoteDocumentStyle? = nil
    let size: CGSize

    /// The page's honest typesetting size (matches the page aspect 90:116) —
    /// one text layout here, GPU-scaled everywhere else.
    private static let designSize = CGSize(width: 200, height: 258)

    var body: some View {
        LibraryPagePreview(title: title, text: text, pageStyle: pageStyle)
            .frame(width: Self.designSize.width, height: Self.designSize.height)
            .scaleEffect(size.width / Self.designSize.width, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Page Preview (readable — large scale & Gallery)

/// The document's actual first page at file-object scale — real title and
/// prose, the way Files renders a page. Never an icon.
struct LibraryPagePreview: View {
    let title: String
    let text: String?
    /// A personalized note's page style — paper tone, icon, cover — so the
    /// object is a faithful miniature. nil for every other page kind.
    var pageStyle: NoteDocumentStyle? = nil

    /// Text typesets its ENTIRE string even when clipped (the ⌘K freeze
    /// lesson) — a page this size can display at most a few hundred
    /// characters, so the excerpt is bounded before layout.
    private var excerpt: String {
        guard let text, !text.isEmpty else { return " " }
        return String(text.prefix(700))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            if let icon = pageStyle?.pageIcon {
                NotePageIconView(
                    icon: icon,
                    style: pageStyle ?? .default,
                    darkMode: DS.palette.isDark,
                    size: 16
                )
            }
            Text(title)
                .font(DS.compactTitleSerif)
                .foregroundStyle(CommandKPreviewPaper.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(excerpt)
                .font(DS.caption)
                .foregroundStyle(CommandKPreviewPaper.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(paperFill)
        .background(alignment: .top) { coverBand }
        .accessibilityHidden(true)
    }

    private var paperFill: Color {
        pageStyle?.paperTone.pageColor(darkMode: DS.palette.isDark) ?? CommandKPreviewPaper.fill
    }

    private var coverHeight: CGFloat {
        (pageStyle?.cover ?? NoteDocumentStyle.Cover.none) == NoteDocumentStyle.Cover.none ? 0 : 56
    }

    @ViewBuilder
    private var coverBand: some View {
        if let pageStyle, pageStyle.cover != .none {
            NotePageCoverBand(
                style: pageStyle,
                darkMode: DS.palette.isDark,
                height: coverHeight
            )
        }
    }
}

// MARK: - Manuscript Preview (connections — the concept as its printed page)

/// The concept's manuscript face: the serif document from the Connection
/// workspace's manuscript mode, miniaturized as the library object. Vellum
/// paper, filigree masthead, chapters with accent dots — the real sections
/// from `atom.structured`, never a stand-in mock. An empty concept renders
/// as a blank vellum page carrying only its masthead, which is the honest
/// state of an unwritten manuscript.
struct LibraryManuscriptPreview: View {
    let title: String
    let conceptTypeName: String?
    let sections: [ConnectionSection]

    /// Bounded before layout (the ⌘K freeze lesson — Text typesets its whole
    /// string even when clipped): a page this size shows a handful of
    /// chapters, so sections, items, and characters are capped up front.
    private static let maxChapters = 7
    private static let maxItemsPerChapter = 3
    private static let maxItemCharacters = 160

    private var chapters: [ConnectionSection] {
        Array(
            sections
                .filter { !$0.items.isEmpty }
                .sorted { $0.type.sortOrder < $1.type.sortOrder }
                .prefix(Self.maxChapters)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            masthead
            ForEach(chapters) { chapter(for: $0) }
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.vellum)
        .accessibilityHidden(true)
    }

    private var masthead: some View {
        VStack(spacing: DS.space8) {
            filigree
            Text(title.isEmpty ? "Untitled Framework" : title)
                .font(DS.compactTitleSerif)
                .foregroundStyle(DS.inkWash)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let conceptTypeName {
                Text(conceptTypeName.uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.8)
                    .foregroundStyle(DS.giltMuted)
            }
            filigree
        }
        .frame(maxWidth: .infinity)
    }

    private var filigree: some View {
        HStack(spacing: DS.space6) {
            Rectangle().fill(DS.gilt.opacity(0.6)).frame(height: 0.5)
            Rectangle()
                .fill(DS.gilt.opacity(0.75))
                .frame(width: 3.5, height: 3.5)
                .rotationEffect(.degrees(45))
            Rectangle().fill(DS.gilt.opacity(0.6)).frame(height: 0.5)
        }
        .frame(maxWidth: 120)
    }

    private func chapter(for section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            chapterHeader(section)
            ForEach(Array(section.items.prefix(Self.maxItemsPerChapter))) { item in
                HStack(alignment: .top, spacing: DS.space6) {
                    Circle()
                        .fill(section.type.accentColor.opacity(0.65))
                        .frame(width: 2.5, height: 2.5)
                        .padding(.top, 5)
                    Text(String(item.resolvedPlainText.prefix(Self.maxItemCharacters)))
                        .font(DS.excerptSerif)
                        .foregroundStyle(DS.inkWash.opacity(0.9))
                        .lineSpacing(2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    private func chapterHeader(_ section: ConnectionSection) -> some View {
        HStack(spacing: DS.space6) {
            Circle()
                .fill(section.type.accentColor)
                .frame(width: 4, height: 4)
            Text(section.type.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(section.type.accentColor)
                .lineLimit(1)
            Rectangle().fill(section.type.accentColor.opacity(0.3)).frame(height: 0.5)
        }
    }
}

/// The manuscript scaled to object size, exactly the page-thumbnail trick:
/// typeset ONCE at design size (where the type scale is honest), then
/// GPU-scaled — so icon cells and filmstrip tiles show the real document.
struct LibraryManuscriptThumbnail: View {
    let title: String
    let conceptTypeName: String?
    let sections: [ConnectionSection]
    let size: CGSize

    /// Matches the page aspect 90:116, same as LibraryPageThumbnail.
    private static let designSize = CGSize(width: 200, height: 258)

    var body: some View {
        LibraryManuscriptPreview(title: title, conceptTypeName: conceptTypeName, sections: sections)
            .frame(width: Self.designSize.width, height: Self.designSize.height)
            .scaleEffect(size.width / Self.designSize.width, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Motif & Fallback Wells

/// The object motif well: a tinted mark centered on a quiet wash — the honest
/// face of a non-document object (portal, live Cosmo block).
struct LibraryObjectMotifWell: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            Rectangle().fill(tint.opacity(0.07))
            Image(systemName: icon)
                .font(DS.title2.weight(.medium))
                .foregroundStyle(tint.opacity(0.75))
        }
        .accessibilityHidden(true)
    }
}

/// Quiet stand-in when a thumbnail can't load — a skeleton-toned well, not chrome.
struct LibraryMediaFallback: View {
    let accent: Color

    var body: some View {
        ZStack {
            Rectangle().fill(DS.glassSectionFill)
            Image(systemName: "photo")
                .font(DS.title2)
                .foregroundStyle(accent.opacity(0.35))
        }
        .accessibilityHidden(true)
    }
}

struct LibraryMediaThumbnail: View {
    let source: String
    let accent: Color

    var body: some View {
        Group {
            if source.hasPrefix("http") {
                remote
            } else {
                local
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    private var remote: some View {
        CachedAsyncImage(url: URL(string: source)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                Rectangle().fill(DS.glassSectionFill)
            case .failure:
                LibraryMediaFallback(accent: accent)
            }
        }
    }

    private var local: some View {
        // Async + downsampled: a sync NSImage(contentsOfFile:) would decode
        // full-resolution files on the main thread during grid scrolling.
        LocalFileThumbnail(path: source) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            LibraryMediaFallback(accent: accent)
        }
    }
}

// MARK: - List-row mark (icon territory)

/// The 26pt mark for list rows. Lists are icon territory (the Raycast law):
/// media keeps its honest thumbnail, everything else wears its kind glyph in
/// the entity tint — never a 26pt micro-page.
struct LibraryListObjectMark: View {
    let model: ThinkspaceLibraryCardModel
    var size: CGFloat = 26

    var body: some View {
        Group {
            if case .media(let source) = model.previewKind {
                LibraryMediaThumbnail(source: source, accent: model.item.entityType.color)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(DS.glassBorder, lineWidth: 0.5)
                    )
            } else {
                CosmoIdentityChip(
                    icon: model.cosmoIcon,
                    tint: model.item.entityType.color,
                    size: size
                )
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Drag Previews

/// The object itself at grid scale — you drag the actual thumbnail with its
/// name beneath, exactly what Finder does when you pick up a file.
struct ThinkspaceLibraryDragPreview: View {
    let model: ThinkspaceLibraryCardModel

    var body: some View {
        VStack(spacing: DS.space8) {
            LibraryDocumentObject(model: model, wellWidth: 128, wellHeight: 96, miniature: true)
                .cardShadow(isHovered: true)
            Text(model.item.title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, 3)
                .background(DS.canvas.opacity(0.88), in: Capsule())
        }
        .frame(width: 180)
        // Slack so the object's shadow survives the drag snapshot's bounds.
        .padding(DS.space16)
    }
}

/// A multi-selection drag: the lead object with two ghosted followers fanned
/// behind it and a count badge — the flock reads as "you are carrying N".
struct ThinkspaceLibraryFlockDragPreview: View {
    let lead: ThinkspaceLibraryCardModel
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                follower(rotation: -6, offset: CGSize(width: -10, height: 6), opacity: 0.45)
                follower(rotation: 5, offset: CGSize(width: 10, height: 3), opacity: 0.65)
                LibraryDocumentObject(model: lead, wellWidth: 116, wellHeight: 88, miniature: true)
                    .cardShadow(isHovered: true)
            }
            countBadge
                .offset(x: 10, y: -10)
        }
        .padding(DS.space20)
    }

    private func follower(rotation: Double, offset: CGSize, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(DS.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .frame(width: 72, height: 88)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .opacity(opacity)
    }

    private var countBadge: some View {
        Text("\(count)")
            .font(DS.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, DS.space8)
            .frame(height: 22)
            .background(DS.accent, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}
