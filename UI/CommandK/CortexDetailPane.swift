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

    var title: String {
        switch self {
        case .empty: return ""
        case .recent(let i): return i.title
        case .result(let r): return r.title
        }
    }

    var typeLabel: String {
        switch self {
        case .empty: return ""
        case .recent(let i): return i.type.displayName
        case .result(let r): return r.source.displayName
        }
    }

    var metaLine: String? {
        switch self {
        case .empty: return nil
        case .recent(let i): return i.relativeDate
        case .result(let r): return r.subtitle
        }
    }

    var accentColor: Color {
        switch self {
        case .empty: return DS.textSecondary
        case .recent(let i): return cortexEntityAccent(i.type)
        case .result(let r): return r.accentColor
        }
    }

    var thumbnailURL: String? {
        if case .recent(let i) = self { return i.thumbnailURL }
        return nil
    }

    var previewText: String? {
        switch self {
        case .recent(let i): return i.preview
        case .result(let r): return r.snippet ?? r.subtitle
        default: return nil
        }
    }

    var atomUUID: String? {
        switch self {
        case .recent(let i): return i.id
        case .result(let r): return r.atomUUID
        default: return nil
        }
    }

    var isConnection: Bool {
        if case .recent(let i) = self { return i.type == .connection }
        if case .result(let r) = self { return r.atomType == .connection }
        return false
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
                    created: cortexFormatISO(atom?.createdAt),
                    updated: cortexFormatISO(atom?.updatedAt),
                    links: atom?.linksList.count,
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
