// CosmoOS/UI/FocusMode/Connection/ManuscriptModeView.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// Manuscript mode flattens the spatial workshop into a single serif-typeset
// reading flow — the framework as a printed document. Each populated station
// becomes a chapter: gilt dropcap-like header, body lines as serif bullets, no
// chrome. This is the "read it as if it were a book" moment — a final
// check before the framework leaves the crucible.

import SwiftUI

struct ManuscriptModeView: View {

    let title: String
    let conceptType: ConceptFrameworkType
    let sections: [ConnectionSection]
    /// Media refs render as plates: anchored ones under their chapter,
    /// the rest gathered in a closing Plates block before the colophon.
    var media: [ConnectionMediaItem] = []
    var mediaAtoms: [String: Atom] = [:]
    var onOpenMedia: (UUID) -> Void = { _ in }
    let onDismiss: () -> Void

    private var populatedSections: [ConnectionSection] {
        sections
            .filter { !$0.items.isEmpty }
            .sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    // Dark themes read the manuscript in a dark room; light themes keep vellum.
    private var paper: Color {
        DS.usesImmersiveFocusAppearance ? DS.bg : DS.vellum
    }

    private var ink: Color {
        DS.usesImmersiveFocusAppearance ? DS.text : DS.inkWash
    }

    private var inkSecondary: Color {
        DS.usesImmersiveFocusAppearance ? DS.textMuted : DS.inkFaded
    }

    private var hairline: Color {
        DS.usesImmersiveFocusAppearance ? DS.border : DS.sepiaBorder
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            paper.ignoresSafeArea()
            scrollBody
            dismissButton
        }
    }

    // MARK: - Scroll body

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                masthead
                ForEach(populatedSections) { section in
                    chapter(for: section)
                }
                if !unanchoredMedia.isEmpty {
                    platesBlock
                }
                colophon
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 48)
            .padding(.top, 80)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .center, spacing: 14) {
            filigree
            Text(title.isEmpty ? "Untitled Framework" : title)
                .font(DS.displaySerif)
                .tracking(0.4)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(conceptType.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(2.4)
                .foregroundStyle(DS.giltMuted)
            filigree
        }
        .frame(maxWidth: .infinity)
    }

    private var filigree: some View {
        HStack(spacing: 10) {
            Rectangle().fill(DS.gilt.opacity(0.6)).frame(height: 0.5)
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(DS.gilt.opacity(0.75))
            Rectangle().fill(DS.gilt.opacity(0.6)).frame(height: 0.5)
        }
        .frame(maxWidth: 280)
    }

    // MARK: - Chapter

    private var unanchoredMedia: [ConnectionMediaItem] {
        media.filter { $0.anchorSection == nil }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    private func anchoredMedia(for type: ConnectionSectionType) -> [ConnectionMediaItem] {
        media.filter { $0.anchorSection == type }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    private func chapter(for section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            chapterHeader(section)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(section.type.accentColor.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .padding(.top, 9)
                        if let linkedUUID = item.linkedConnectionUUID {
                            ConnectionLinkPill(title: item.resolvedPlainText) {
                                ConnectionLinkOpener.open(uuid: linkedUUID)
                            }
                        } else {
                            ConnectionLinkedText(
                                text: item.resolvedPlainText,
                                font: .system(size: 16, weight: .regular, design: .serif),
                                color: ink,
                                mentions: item.explicitMentions
                            )
                            .lineSpacing(4)
                        }
                    }
                }
            }
            let plates = anchoredMedia(for: section.type)
            if !plates.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(plates) { item in
                        plate(item)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Plates (media figures)

    /// A media ref as a book plate: hairline-framed image, small-caps
    /// caption underneath. Click opens the Stage lightbox.
    private func plate(_ item: ConnectionMediaItem) -> some View {
        let atom = item.atomUUID.flatMap { mediaAtoms[$0] }
        return Button {
            onOpenMedia(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                plateImage(item, atom: atom)
                    .aspectRatio(16 / 10, contentMode: .fill)
                    .frame(maxWidth: 420)
                    .clipShape(Rectangle())
                    .overlay(Rectangle().stroke(hairline, lineWidth: 0.5))
                    .overlay(alignment: .center) {
                        if item.kind == .video {
                            Image(systemName: "play.circle")
                                .font(DS.title1.weight(.thin))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.4), radius: 6)
                                .accessibilityHidden(true)
                        }
                    }
                Text(plateCaption(item, atom: atom).uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.6)
                    .foregroundStyle(inkSecondary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in the Stage")
        .accessibilityLabel("Plate: \(plateCaption(item, atom: atom))")
    }

    private func plateCaption(_ item: ConnectionMediaItem, atom: Atom?) -> String {
        if let caption = item.caption, !caption.isEmpty { return caption }
        if let title = atom?.title, !title.isEmpty { return title }
        return item.assetTitle ?? "Untitled plate"
    }

    @ViewBuilder
    private func plateImage(_ item: ConnectionMediaItem, atom: Atom?) -> some View {
        if let poster = item.thumbnailAssetPath {
            ConceptLocalThumbnail(path: poster, maxPixel: 840)
        } else if let path = item.assetPath, !MediaAssetStore.isVideoPath(path) {
            ConceptLocalThumbnail(path: path, maxPixel: 840)
        } else if let atom, let url = ConceptMediaThumbnailResolver.thumbnailURL(for: atom) {
            CachedAsyncImage(url: url, stableKey: "manuscript-\(ConceptMediaThumbnailResolver.stableKey(for: item))") { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle().fill(hairline.opacity(0.2))
                @unknown default:
                    Rectangle().fill(hairline.opacity(0.2))
                }
            }
        } else {
            Rectangle().fill(hairline.opacity(0.2))
        }
    }

    private var platesBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle().fill(DS.gilt).frame(width: 6, height: 6)
                Text("PLATES")
                    .font(DS.smallCaps)
                    .tracking(2.0)
                    .foregroundStyle(DS.giltMuted)
                Rectangle().fill(DS.gilt.opacity(0.3)).frame(height: 0.5)
            }
            ForEach(unanchoredMedia) { item in
                plate(item)
            }
        }
    }

    private func chapterHeader(_ section: ConnectionSection) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(section.type.accentColor)
                .frame(width: 6, height: 6)
            Text(section.type.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(2.0)
                .foregroundStyle(section.type.accentColor)
            Rectangle().fill(section.type.accentColor.opacity(0.3)).frame(height: 0.5)
        }
    }

    private var colophon: some View {
        VStack(spacing: 10) {
            filigree
            Text("— FIN —")
                .font(DS.smallCaps)
                .tracking(3.0)
                .foregroundStyle(DS.giltMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(inkSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().stroke(hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(24)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Dismiss manuscript mode")
    }
}
