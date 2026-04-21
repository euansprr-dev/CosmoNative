// CosmoOS/UI/FocusMode/Connection/WellSourcesBlock.swift
// April 2026 — governed Well column
//
// Linked sources appear by default. Semantic suggestions stay behind an explicit
// "find related" action so the Well never fabricates attachment state.

import SwiftUI

struct WellSourcesBlock: View {

    let sources: [Atom]
    let suggestedSources: [Atom]
    let whispersBySource: [String: [GhostSuggestion]]
    let contributionsBySource: [String: Set<ConnectionSectionType>]
    let isShowingSuggestions: Bool
    let isLoadingSuggestions: Bool

    let onAddSource: () -> Void
    let onRequestSuggestions: () -> Void
    let onLinkSuggestedSource: (Atom) -> Void
    let onSourceTap: (String) -> Void
    let onRefreshWhispers: (String) -> Void
    let onAcceptWhisper: (GhostSuggestion) -> Void
    let onDismissWhisper: (UUID) -> Void
    let onHoverSource: (String?) -> Void

    @State private var expandedSourceUUIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MarginaliaLabel("THE WELL", countText: "\(sources.count)")
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty && !isShowingSuggestions && !isLoadingSuggestions {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    linkedSourcesSection
                    if isLoadingSuggestions || isShowingSuggestions {
                        suggestionSection
                    }
                }
            }
        }
    }

    private var linkedSourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("LINKED SOURCES")

            if sources.isEmpty {
                Text("Nothing is attached yet.")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sources, id: \.uuid) { source in
                        WellSourceRow(
                            source: source,
                            whispers: whispersBySource[source.uuid] ?? [],
                            contributedStations: contributionsBySource[source.uuid] ?? [],
                            isExpanded: expandedSourceUUIDs.contains(source.uuid),
                            onToggleExpand: { toggleExpand(source.uuid) },
                            onTap: { onSourceTap(source.uuid) },
                            onRefresh: { onRefreshWhispers(source.uuid) },
                            onAcceptWhisper: onAcceptWhisper,
                            onDismissWhisper: onDismissWhisper,
                            onHover: { hovering in
                                onHoverSource(hovering ? source.uuid : nil)
                            }
                        )
                        if source.uuid != sources.last?.uuid {
                            divider
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(DS.vellumDeep.opacity(0.35), in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DS.sepiaBorder.opacity(0.8), lineWidth: 0.5)
                )
            }
        }
    }

    @ViewBuilder
    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("RELATED SUGGESTIONS")

            if isLoadingSuggestions {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Looking for nearby material…")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DS.inkFaded)
                }
                .padding(.vertical, 8)
            } else if suggestedSources.isEmpty {
                Text("No semantic suggestions right now.")
                    .font(.system(size: 11, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suggestedSources, id: \.uuid) { source in
                        SuggestedSourceRow(
                            source: source,
                            onTap: { onSourceTap(source.uuid) },
                            onLink: { onLinkSuggestedSource(source) }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(DS.inkFaded)
                .accessibilityHidden(true)

            Text("Link research, ideas, or swipes here.")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkWash)

            Text("Attached material belongs to the framework even before any station quotes it.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DS.inkFaded)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                actionButton(title: "Add Source", systemImage: "plus.circle", action: onAddSource)
                actionButton(title: "Find Related", systemImage: "sparkles", action: onRequestSuggestions)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.vellumDeep.opacity(0.35), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.sepiaBorder.opacity(0.8), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.sepiaSubtle.opacity(0.8))
            .frame(height: 0.5)
            .padding(.horizontal, 10)
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(DS.smallCaps)
            .tracking(1.6)
            .foregroundStyle(DS.giltMuted)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(title.uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.4)
            }
            .foregroundStyle(DS.giltMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.vellumDeep.opacity(0.45), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DS.sepiaBorder.opacity(0.8), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleExpand(_ uuid: String) {
        withAnimation(ProMotionSprings.snappy) {
            if expandedSourceUUIDs.contains(uuid) {
                expandedSourceUUIDs.remove(uuid)
            } else {
                expandedSourceUUIDs.insert(uuid)
            }
        }
    }
}

private struct WellSourceRow: View {

    let source: Atom
    let whispers: [GhostSuggestion]
    let contributedStations: Set<ConnectionSectionType>
    let isExpanded: Bool

    let onToggleExpand: () -> Void
    let onTap: () -> Void
    let onRefresh: () -> Void
    let onAcceptWhisper: (GhostSuggestion) -> Void
    let onDismissWhisper: (UUID) -> Void
    let onHover: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded && !whispers.isEmpty {
                whispersColumn
            }
        }
        .background(isHovering ? DS.vellumDeep.opacity(0.42) : Color.clear)
        .clipShape(.rect(cornerRadius: 8))
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.gilt.opacity(0.75))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)

            Button(action: onTap) {
                Text(source.title ?? "Untitled Source")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(DS.inkWash)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            contributionDots
            whisperBadge
            trailingControl
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
    }

    private var contributionDots: some View {
        HStack(spacing: 3) {
            ForEach(contributionPreview, id: \.self) { type in
                Circle()
                    .fill(type.accentColor.opacity(0.85))
                    .frame(width: 4, height: 4)
            }
            if contributedStations.count > contributionPreview.count {
                Text("+\(contributedStations.count - contributionPreview.count)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
            }
        }
        .frame(height: 10)
    }

    private var contributionPreview: [ConnectionSectionType] {
        ConnectionSectionType.allCases
            .filter { contributedStations.contains($0) }
            .prefix(3)
            .map { $0 }
    }

    @ViewBuilder
    private var whisperBadge: some View {
        if !whispers.isEmpty {
            Text("\(whispers.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.giltMuted)
                .frame(minWidth: 14)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule().stroke(DS.gilt.opacity(0.35), lineWidth: 0.5)
                )
                .accessibilityLabel("\(whispers.count) whispers")
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if !whispers.isEmpty {
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.giltMuted)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse whispers" : "Expand whispers")
        } else {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.giltMuted.opacity(isHovering ? 1 : 0.4))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh whispers")
        }
    }

    private var whispersColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(whispers) { whisper in
                WellWhisperRow(
                    whisper: whisper,
                    onAccept: { onAcceptWhisper(whisper) },
                    onDismiss: { onDismissWhisper(whisper.id) }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var glyph: String {
        switch source.type {
        case .research: return source.isSwipeFileAtom ? "bookmark" : "doc.text"
        case .idea: return "lightbulb"
        case .content: return "doc.richtext"
        case .connection: return "link"
        case .project: return "folder"
        case .clientProfile: return "person.crop.circle"
        case .note: return "note.text"
        case .task: return "checkmark.circle"
        default: return "circle"
        }
    }
}

private struct SuggestedSourceRow: View {
    let source: Atom
    let onTap: () -> Void
    let onLink: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.gilt.opacity(0.75))
                .frame(width: 14, height: 14)

            Button(action: onTap) {
                Text(source.title ?? "Untitled Source")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(DS.inkWash)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onLink) {
                Text("LINK")
                    .font(DS.smallCaps)
                    .tracking(1.2)
                    .foregroundStyle(DS.entityConnection)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DS.entityConnection.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.vellumDeep.opacity(0.25), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.sepiaBorder.opacity(0.55), lineWidth: 0.5)
        )
    }

    private var glyph: String {
        switch source.type {
        case .research: return source.isSwipeFileAtom ? "bookmark" : "doc.text"
        case .idea: return "lightbulb"
        case .content: return "doc.richtext"
        case .connection: return "link"
        case .note: return "note.text"
        default: return "circle"
        }
    }
}
