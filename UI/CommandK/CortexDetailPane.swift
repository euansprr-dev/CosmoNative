// CosmoOS/UI/CommandK/CortexDetailPane.swift
// Raycast-style right preview pane. Phase 2: per-type rendering (media /
// connection / reading excerpt) + the INFORMATION metadata table, hydrated
// from a lazy AtomRepository fetch keyed to the current selection.

import SwiftUI

/// Maps the current Command-K selection to a uniform preview subject so the
/// detail pane never needs to know whether it came from Recents or search.
enum CortexDetailSubject {
    case empty
    case recent(RecentDisplayItem)
    case result(UnifiedSearchResult)
    case library(LibraryItem)
    case swipe(SwipeGalleryItem)
    case idea(IdeaGalleryItem)
    case readwise(ReadwiseLibraryBook)

    var title: String {
        switch self {
        case .empty: return ""
        case .recent(let i): return i.title
        case .result(let r): return r.title
        case .library(let item): return item.title
        case .swipe(let item): return item.title
        case .idea(let item): return item.title
        case .readwise(let book): return book.title
        }
    }

    var typeLabel: String {
        switch self {
        case .empty: return ""
        case .recent(let i): return i.type.displayName
        case .result(let r): return r.source.displayName
        case .library(let item): return item.typeName
        case .swipe: return "Swipe File"
        case .idea: return "Idea"
        case .readwise(let book): return book.category.displayName
        }
    }

    var metaLine: String? {
        switch self {
        case .empty: return nil
        case .recent(let i): return i.relativeDate
        case .result(let r): return r.subtitle
        case .library(let item): return item.relativeDate
        case .swipe(let item): return [item.creatorName ?? item.author, item.platformName].compactMap { $0 }.joined(separator: " · ")
        case .idea(let item): return [item.status.displayName, item.clientName].compactMap { $0 }.joined(separator: " · ")
        case .readwise(let book): return [book.author, "\(book.numHighlights) highlights"].compactMap { $0 }.joined(separator: " · ")
        }
    }

    var accentColor: Color {
        switch self {
        case .empty: return DS.textSecondary
        case .recent(let i): return cortexEntityAccent(i.type)
        case .result(let r): return r.accentColor
        case .library(let item): return item.color
        case .swipe: return DS.entitySwipe
        case .idea: return DS.entityIdea
        case .readwise: return DS.entityReadwise
        }
    }

    var thumbnailURL: String? {
        if case .recent(let i) = self { return i.thumbnailURL }
        if case .library(let item) = self { return item.thumbnailURL }
        if case .swipe(let item) = self { return item.thumbnailUrl }
        if case .readwise(let book) = self { return book.coverImageUrl }
        return nil
    }

    var previewText: String? {
        switch self {
        case .recent(let i): return i.preview
        case .result(let r): return r.snippet ?? r.subtitle
        case .library(let item): return item.preview
        case .swipe(let item): return item.hookText
        case .idea(let item): return item.context ?? item.body ?? item.hooks.first
        case .readwise(let book): return book.highlights.first?.text ?? "\(book.numHighlights) saved highlights"
        default: return nil
        }
    }

    var atomUUID: String? {
        switch self {
        case .recent(let i): return i.id
        case .result(let r): return r.atomUUID
        case .library(let item): return item.kind == .thinkspace ? nil : item.uuid
        case .swipe(let item): return item.atomUUID
        case .idea(let item): return item.atomUUID
        default: return nil
        }
    }

    var isConnection: Bool {
        if case .recent(let i) = self { return i.type == .connection }
        if case .result(let r) = self { return r.atomType == .connection }
        if case .library(let item) = self { return item.atomType == .connection }
        return false
    }

    var createdText: String? {
        switch self {
        case .library(let item): return cortexFormatDate(item.createdAt)
        case .swipe(let item): return cortexFormatISO(item.createdAt)
        case .idea(let item): return cortexFormatISO(item.createdAt)
        default: return nil
        }
    }

    var updatedText: String? {
        switch self {
        case .library(let item): return cortexFormatDate(item.updatedAt)
        case .idea(let item): return cortexFormatISO(item.updatedAt)
        default: return nil
        }
    }

    var linksCount: Int? {
        switch self {
        case .library(let item): return max(item.childCount, item.blockCount)
        default: return nil
        }
    }
}

/// Shared entity-accent mapping (mirrors the recents card palette).
func cortexEntityAccent(_ type: AtomType) -> Color {
    switch type {
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

struct CortexDetailPane: View {
    let subject: CortexDetailSubject

    @State private var atom: Atom?

    var body: some View {
        Group {
            if case .empty = subject { emptyState } else { loaded }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.space24)
        .task(id: subject.atomUUID) { await loadAtom() }
    }

    private func loadAtom() async {
        atom = nil
        guard let id = subject.atomUUID else { return }
        atom = try? await AtomRepository.shared.fetch(uuid: id)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.giltMuted)
            Text("Select something to preview")
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkFaded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                CortexPreviewBlock(subject: subject, bodyText: atom?.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: DS.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                            .strokeBorder(DS.sepiaSubtle, lineWidth: 0.5)
                    )

                Text(subject.title)
                    .font(DS.spaceTitleSerif)
                    .foregroundStyle(DS.text)
                    .lineLimit(3)

                CortexInformationTable(
                    typeLabel: subject.typeLabel,
                    created: subject.createdText ?? cortexFormatISO(atom?.createdAt),
                    updated: subject.updatedText ?? cortexFormatISO(atom?.updatedAt),
                    links: subject.linksCount ?? atom?.linksList.count,
                    fallbackMeta: subject.metaLine
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

/// Per-type preview: media → image, connection → section map, text → a
/// serif reading excerpt, otherwise a faux page.
private struct CortexPreviewBlock: View {
    let subject: CortexDetailSubject
    let bodyText: String?

    var body: some View {
        switch subject {
        case .library(let item):
            CommandKLibraryThumbnail(item: item, cornerRadius: DS.radiusMedium)
                .background(DS.vellum)
        case .swipe(let item):
            CortexSwipeDomainPreview(item: item)
        case .idea(let item):
            CortexIdeaDomainPreview(item: item)
        case .readwise(let book):
            CortexReadwiseDomainPreview(book: book)
        default:
            genericPreview
        }
    }

    @ViewBuilder
    private var genericPreview: some View {
        if let url = subject.thumbnailURL, !url.isEmpty {
            SpotlightImageContent(urlString: url)
        } else if subject.isConnection {
            SpotlightConnectionPreview(preview: subject.previewText, accentColor: subject.accentColor)
        } else if let text = readingText, !text.isEmpty {
            readingCard(text)
        } else {
            SpotlightFauxPage(accentColor: subject.accentColor)
        }
    }

    private var readingText: String? {
        let t = bodyText ?? subject.previewText
        guard let t, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return t
    }

    private func readingCard(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(DS.dateSerif)
                .foregroundStyle(DS.text)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.space16)
        }
        .scrollIndicators(.hidden)
        .background(DS.vellum)
    }
}

private struct CortexSwipeDomainPreview: View {
    let item: SwipeGalleryItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            imageLayer
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.62)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: DS.space8) {
                if let hookType = item.hookType {
                    Text(hookType.displayName)
                        .font(DS.caption2)
                        .foregroundStyle(hookType.color)
                        .padding(.horizontal, DS.space8)
                        .frame(height: 24)
                        .background(hookType.color.opacity(0.18), in: Capsule())
                }
                Text(item.hookText ?? item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                Text([item.creatorName ?? item.author, item.platformName].compactMap { $0 }.joined(separator: " · "))
                    .font(DS.caption)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(DS.space16)
        }
    }

    @ViewBuilder
    private var imageLayer: some View {
        if let rawURL = item.thumbnailUrl, let url = URL(string: rawURL) {
            CachedAsyncImage(url: url, stableKey: item.instagramId) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    ProgressView().scaleEffect(0.65).tint(.white.opacity(0.70))
                case .failure:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        LinearGradient(
            colors: [DS.entitySwipe.opacity(0.34), DS.vellumDeep.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: item.platformIcon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
                .accessibilityHidden(true)
        }
    }
}

private struct CortexIdeaDomainPreview: View {
    let item: IdeaGalleryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space12) {
                if let contextText {
                    previewSection("CONTEXT", text: contextText)
                }
                if !item.hooks.isEmpty {
                    previewList("HOOKS", values: Array(item.hooks.prefix(3)))
                }
                if !item.outline.isEmpty {
                    previewList("OUTLINE", values: Array(item.outline.prefix(4)))
                }
                if contextText == nil, item.hooks.isEmpty, item.outline.isEmpty {
                    Text(item.body ?? "No idea context captured yet.")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.inkFaded)
                }
            }
            .padding(DS.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(DS.vellum)
    }

    private var contextText: String? {
        item.context ?? item.body
    }

    private func previewSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title)
                .font(DS.smallCaps)
                .foregroundStyle(DS.entityIdea)
            Text(text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(3)
                .lineLimit(6)
        }
    }

    private func previewList(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Text(title)
                .font(DS.smallCaps)
                .foregroundStyle(DS.entityIdea)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(alignment: .top, spacing: DS.space8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.entityIdea)
                        .frame(width: 18, height: 18)
                        .background(DS.entityIdea.opacity(0.10), in: Circle())
                    Text(value)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct CortexReadwiseDomainPreview: View {
    let book: ReadwiseLibraryBook

    var body: some View {
        HStack(alignment: .top, spacing: DS.space18) {
            cover
                .frame(width: 96, height: 144)
            VStack(alignment: .leading, spacing: DS.space12) {
                Text(book.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(3)
                if let author = book.author {
                    Text(author)
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                }
                Text(book.highlights.first?.text ?? "\(book.numHighlights) saved highlights.")
                    .font(DS.dateSerif)
                    .foregroundStyle(DS.text)
                    .lineSpacing(4)
                    .lineLimit(5)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.space18)
        .background(DS.vellum)
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.vellumDeep)
            if let coverURL = book.coverImageUrl, let url = URL(string: coverURL) {
                CachedAsyncImage(url: url, stableKey: "\(book.id)") { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().scaleEffect(0.6).tint(DS.textMuted)
                    case .failure:
                        fallbackCover
                    }
                }
            } else {
                fallbackCover
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(DS.sepiaBorder, lineWidth: 0.5)
        )
    }

    private var fallbackCover: some View {
        Text(book.title.prefix(28).description)
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .foregroundStyle(DS.entityReadwise)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding(DS.space10)
    }
}
