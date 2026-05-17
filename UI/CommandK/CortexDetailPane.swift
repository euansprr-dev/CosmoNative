// CosmoOS/UI/CommandK/CortexDetailPane.swift
// Raycast-style right-hand preview pane. Phase 1: one generic adaptive
// renderer (thumbnail / page / faux) + title + a minimal info line.
// Per-type renderers and the full Information table arrive in Phase 2.

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
        switch self {
        case .recent(let i): return i.thumbnailURL
        default: return nil
        }
    }

    var previewText: String? {
        switch self {
        case .recent(let i): return i.preview
        case .result(let r): return r.snippet ?? r.subtitle
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

    var body: some View {
        Group {
            if case .empty = subject {
                emptyState
            } else {
                loaded
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.space24)
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
                previewBlock
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

                AtelierOrnamentalSectionLabel(label: "INFORMATION")

                infoRow("Type", subject.typeLabel)
                if let meta = subject.metaLine, !meta.isEmpty {
                    infoRow("Captured", meta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var previewBlock: some View {
        if let url = subject.thumbnailURL, !url.isEmpty {
            SpotlightImageContent(urlString: url)
        } else if subject.isConnection {
            SpotlightConnectionPreview(preview: subject.previewText, accentColor: subject.accentColor)
        } else if let text = subject.previewText, !text.isEmpty {
            SpotlightPageContent(text: text, accentColor: subject.accentColor)
        } else {
            SpotlightFauxPage(accentColor: subject.accentColor)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.inkFaded)
            Spacer(minLength: DS.space12)
            Text(value)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }
}
