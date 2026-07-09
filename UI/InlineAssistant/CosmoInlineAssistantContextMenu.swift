// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantContextMenu.swift
// The @-mention context picker in the assistant menu grammar: dense ink rows,
// recents while browsing, flat ranked results while searching, kind-scope
// grammar ("@idea hook"), full keyboard control. Shared verbatim by the bar
// and the pane composer.
// July 2026 rebuild (was the card-chassis picker, June 2026)

import SwiftUI

// MARK: - Kind-scope grammar

/// The kinds a leading token can scope an @-search to: "@idea hook" searches
/// ideas only. Keyboard-first — this is what replaced the filter-chip strip.
enum CosmoInlineContextScope: String, CaseIterable, Equatable {
    case content
    case profile
    case swipe
    case idea
    case research
    case note

    var displayName: String {
        switch self {
        case .content: return "Content"
        case .profile: return "Profiles"
        case .swipe: return "Swipes"
        case .idea: return "Ideas"
        case .research: return "Research"
        case .note: return "Notes"
        }
    }

    var entityType: EntityType {
        switch self {
        case .content: return .content
        case .profile: return .connection
        case .swipe: return .swipeFile
        case .idea: return .idea
        case .research: return .research
        case .note: return .note
        }
    }

    static func match(_ token: String) -> CosmoInlineContextScope? {
        let normalized = token.lowercased()
        for scope in allCases {
            if normalized == scope.rawValue || normalized == scope.rawValue + "s" {
                return scope
            }
        }
        return nil
    }
}

struct CosmoInlineContextScopeParse: Equatable {
    let scope: CosmoInlineContextScope?
    /// The remainder after the scope token (the whole input when unscoped).
    let query: String
    /// UTF-16 length of the scope token as typed (for the composer wash).
    let scopeTokenLength: Int
}

enum CosmoInlineContextScopeParser {
    static func parse(_ raw: String) -> CosmoInlineContextScopeParse {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CosmoInlineContextScopeParse(scope: nil, query: "", scopeTokenLength: 0)
        }

        // The scope token must lead the raw input — "@ idea" is a search for
        // "idea", not a scope.
        guard !raw.hasPrefix(" "), !raw.hasPrefix("\t") else {
            return CosmoInlineContextScopeParse(scope: nil, query: trimmed, scopeTokenLength: 0)
        }

        let firstToken = trimmed.split(
            separator: " ",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )[0]

        guard let scope = CosmoInlineContextScope.match(String(firstToken)) else {
            return CosmoInlineContextScopeParse(scope: nil, query: trimmed, scopeTokenLength: 0)
        }

        let remainder = trimmed
            .dropFirst(firstToken.count)
            .trimmingCharacters(in: .whitespaces)

        return CosmoInlineContextScopeParse(
            scope: scope,
            query: remainder,
            scopeTokenLength: (String(firstToken) as NSString).length
        )
    }
}

// MARK: - Model

/// Owns the picker's rows and highlight so the host (bar / pane composer) can
/// drive it from the keyboard while the view stays purely presentational.
@MainActor
@Observable
final class CosmoInlineContextMenuModel {
    enum Entry: Identifiable {
        /// The document the user is looking at — one Enter attaches it.
        case attachCurrent(Atom)
        case atom(Atom, isSelected: Bool)

        var id: String {
            switch self {
            case .attachCurrent(let atom): return "current:\(atom.uuid)"
            case .atom(let atom, _): return atom.uuid
            }
        }

        var atom: Atom {
            switch self {
            case .attachCurrent(let atom), .atom(let atom, _): return atom
            }
        }

        var isSelected: Bool {
            if case .atom(_, let selected) = self { return selected }
            return false
        }
    }

    struct Section: Identifiable {
        let title: String?
        /// Index of the section's first entry in the flattened list.
        let startIndex: Int
        let entries: [Entry]
        var id: String { title ?? "results" }
    }

    private(set) var sections: [Section] = []
    private(set) var flattened: [Entry] = []
    private(set) var highlightedIndex = 0
    private(set) var scope: CosmoInlineContextScope?
    private(set) var isBrowsing = true

    private var searchTask: Task<Void, Never>?
    private var generation = 0

    var highlightedEntry: Entry? {
        flattened.indices.contains(highlightedIndex) ? flattened[highlightedIndex] : nil
    }

    func moveHighlight(_ delta: Int) {
        highlightedIndex = CosmoAssistantMenuHighlightPolicy.moved(
            highlightedIndex, by: delta, count: flattened.count
        )
    }

    func setHighlight(_ index: Int) {
        highlightedIndex = CosmoAssistantMenuHighlightPolicy.clamped(index, count: flattened.count)
    }

    func update(query rawQuery: String, selectedAtoms: [Atom]) {
        let parse = CosmoInlineContextScopeParser.parse(rawQuery)
        scope = parse.scope
        generation += 1
        let requestGeneration = generation
        searchTask?.cancel()

        if parse.query.isEmpty {
            isBrowsing = true
            searchTask = Task { [weak self] in
                guard let self else { return }
                let current = await Self.activeSurfaceAtom()
                let recents = await Self.recents(scope: parse.scope, excluding: selectedAtoms, current: current)
                guard !Task.isCancelled, self.generation == requestGeneration else { return }
                self.rebuildBrowsing(selectedAtoms: selectedAtoms, current: current, recents: recents)
            }
        } else {
            isBrowsing = false
            searchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                let results = await Self.search(query: parse.query, scope: parse.scope)
                guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
                self.rebuildResults(results, selectedAtoms: selectedAtoms)
            }
        }
    }

    func teardown() {
        searchTask?.cancel()
        searchTask = nil
    }

    // MARK: Row assembly

    private func rebuildBrowsing(selectedAtoms: [Atom], current: Atom?, recents: [Atom]) {
        var built: [Section] = []
        var flat: [Entry] = []

        if !selectedAtoms.isEmpty {
            let entries = selectedAtoms.map { Entry.atom($0, isSelected: true) }
            built.append(Section(title: "ATTACHED", startIndex: flat.count, entries: entries))
            flat.append(contentsOf: entries)
        }

        var recentEntries: [Entry] = []
        if let current, !selectedAtoms.contains(where: { $0.uuid == current.uuid }) {
            recentEntries.append(.attachCurrent(current))
        }
        recentEntries.append(contentsOf: recents.map { Entry.atom($0, isSelected: false) })
        if !recentEntries.isEmpty {
            built.append(Section(title: "RECENT", startIndex: flat.count, entries: recentEntries))
            flat.append(contentsOf: recentEntries)
        }

        apply(sections: built, flattened: flat)
    }

    private func rebuildResults(_ results: [Atom], selectedAtoms: [Atom]) {
        let selectedUUIDs = Set(selectedAtoms.map(\.uuid))
        let entries = results.map { Entry.atom($0, isSelected: selectedUUIDs.contains($0.uuid)) }
        apply(
            sections: [Section(title: nil, startIndex: 0, entries: entries)],
            flattened: entries
        )
    }

    private func apply(sections: [Section], flattened flat: [Entry]) {
        self.sections = sections
        flattened = flat
        highlightedIndex = CosmoAssistantMenuHighlightPolicy.clamped(highlightedIndex, count: flat.count)
    }

    // MARK: Data

    private static func activeSurfaceAtom() async -> Atom? {
        guard let surfaceID = CosmoEditableSurfaceRegistry.shared.activeSurface?.surfaceID,
              let separator = surfaceID.firstIndex(of: ":") else { return nil }
        let uuid = String(surfaceID[surfaceID.index(after: separator)...])
        guard !uuid.isEmpty else { return nil }
        return try? await AtomRepository.shared.fetch(uuid: uuid)
    }

    private static func recents(
        scope: CosmoInlineContextScope?,
        excluding selectedAtoms: [Atom],
        current: Atom?
    ) async -> [Atom] {
        let raw = (try? await AtomRepository.shared.fetchRecent(limit: 40)) ?? []
        let selectedUUIDs = Set(selectedAtoms.map(\.uuid))
        return raw
            .filter { matchesContextKinds($0, scope: scope) }
            .filter { !selectedUUIDs.contains($0.uuid) && $0.uuid != current?.uuid }
            .prefix(8)
            .map { $0 }
    }

    private static func matchesContextKinds(_ atom: Atom, scope: CosmoInlineContextScope?) -> Bool {
        guard let scope else {
            let contextTypes: Set<AtomType> = [.content, .clientProfile, .idea, .research, .note]
            return contextTypes.contains(atom.type)
        }
        switch scope {
        case .content: return atom.type == .content
        case .profile: return atom.type == .clientProfile
        case .swipe: return atom.isSwipeFileAtom
        case .research: return atom.type == .research && !atom.isSwipeFileAtom
        case .idea: return atom.type == .idea
        case .note: return atom.type == .note
        }
    }

    private static func search(query: String, scope: CosmoInlineContextScope?) async -> [Atom] {
        let raw: [Atom]
        switch scope {
        case .swipe:
            raw = ((try? await AtomRepository.shared.search(query: query, types: [.research])) ?? [])
                .filter(\.isSwipeFileAtom)
        case .research:
            raw = ((try? await AtomRepository.shared.search(query: query, types: [.research])) ?? [])
                .filter { !$0.isSwipeFileAtom }
        case .content:
            raw = (try? await AtomRepository.shared.search(query: query, types: [.content])) ?? []
        case .profile:
            raw = (try? await AtomRepository.shared.search(query: query, types: [.clientProfile])) ?? []
        case .idea:
            raw = (try? await AtomRepository.shared.search(query: query, types: [.idea])) ?? []
        case .note:
            raw = (try? await AtomRepository.shared.search(query: query, types: [.note])) ?? []
        case nil:
            raw = (try? await AtomRepository.shared.search(query: query, limit: 18)) ?? []
        }
        return Array(raw.prefix(18))
    }
}

// MARK: - View

struct CosmoInlineAssistantContextMenu: View {
    let model: CosmoInlineContextMenuModel
    let searchText: String
    let selectedAtoms: [Atom]
    let onCommit: (CosmoInlineContextMenuModel.Entry) -> Void
    let onClear: () -> Void

    private let menuWidth: CGFloat = 340
    private let listMaxHeight: CGFloat = 296

    var body: some View {
        VStack(spacing: 0) {
            header
            CosmoGradientDivider()
            content
            CosmoKeyboardFooter(selectLabel: "Add")
        }
        .frame(width: menuWidth)
        .cosmoMenuChrome(cornerRadius: 14)
        .onAppear {
            model.setHighlight(0)
            model.update(query: searchText, selectedAtoms: selectedAtoms)
        }
        .onDisappear {
            model.teardown()
        }
        .onChange(of: searchText) { _, value in
            model.update(query: value, selectedAtoms: selectedAtoms)
        }
        .onChange(of: selectedAtoms.map(\.uuid)) { _, _ in
            model.update(query: searchText, selectedAtoms: selectedAtoms)
        }
    }

    private var header: some View {
        HStack(spacing: DS.space10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 26, height: 26)
                Image(systemName: "at")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
            .accessibilityHidden(true)

            Text("Context")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)

            if let scope = model.scope {
                Text(scope.displayName)
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(scopeTint(scope))
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, 2)
                    .background(scopeTint(scope).opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 0)

            if !selectedAtoms.isEmpty {
                Text("\(selectedAtoms.count)")
                    .font(DS.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, DS.space8)
                    .padding(.vertical, 3)
                    .background(DS.accentSoft, in: Capsule())
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(selectedAtoms.count) attached")

                Button("Clear", action: onClear)
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.medium))
                    .foregroundStyle(DS.textMuted)
                    .cosmoClickCursor()
                    .help("Remove all attached context")
            }
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    @ViewBuilder
    private var content: some View {
        if model.flattened.isEmpty {
            emptyState
        } else {
            listView
        }
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.sections) { section in
                        if let title = section.title {
                            CosmoAssistantMenuSectionHeader(title: title)
                        }
                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { offset, entry in
                            entryRow(entry, index: section.startIndex + offset)
                        }
                    }
                }
                .padding(.vertical, DS.space6)
            }
            .frame(maxHeight: listMaxHeight)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: model.highlightedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newIndex)
                }
            }
        }
    }

    private func entryRow(_ entry: CosmoInlineContextMenuModel.Entry, index: Int) -> some View {
        CosmoAssistantMenuRow(
            icon: icon(for: entry),
            iconTint: tint(for: entry),
            title: entry.atom.title ?? "Untitled",
            trailingHint: hint(for: entry),
            showsCheckmark: entry.isSelected,
            isHighlighted: index == model.highlightedIndex
        )
        .id(index)
        .onTapGesture {
            CosmicHaptics.shared.play(.selection)
            onCommit(entry)
        }
        .onHover { hovering in
            if hovering, model.highlightedIndex != index {
                model.setHighlight(index)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(model.isBrowsing ? "Nothing recent to attach" : "No matching context")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
            Text(model.isBrowsing
                 ? "Keep typing after @ to search everything you've made."
                 : "Try a shorter phrase, or scope with @idea, @swipe, @note.")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space12)
    }

    // MARK: Row presentation

    private func icon(for entry: CosmoInlineContextMenuModel.Entry) -> String {
        if case .attachCurrent = entry { return "doc.badge.plus" }
        let atom = entry.atom
        return atom.isSwipeFileAtom ? "bookmark.fill" : atom.type.iconName
    }

    private func tint(for entry: CosmoInlineContextMenuModel.Entry) -> Color? {
        if case .attachCurrent = entry { return DS.accent }
        let atom = entry.atom
        let entity: EntityType
        if atom.isSwipeFileAtom {
            entity = .swipeFile
        } else if atom.type == .clientProfile {
            entity = .connection
        } else {
            entity = EntityType(rawValue: atom.type.rawValue) ?? .note
        }
        return CosmoMentionColors.color(for: entity)
    }

    private func hint(for entry: CosmoInlineContextMenuModel.Entry) -> String? {
        if case .attachCurrent = entry { return "current" }
        return CosmoInlineAssistantContextMentionFormatter.typeLabel(for: entry.atom)
    }

    private func scopeTint(_ scope: CosmoInlineContextScope) -> Color {
        CosmoMentionColors.color(for: scope.entityType)
    }
}
