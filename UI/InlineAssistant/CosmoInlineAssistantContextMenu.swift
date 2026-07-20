// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantContextMenu.swift
// The @-mention context picker in the assistant menu grammar: dense ink rows,
// recents while browsing, flat ranked results while searching, kind-scope
// grammar ("@idea hook"), full keyboard control. Shared verbatim by the bar
// and the pane composer.
// July 2026 rebuild (was the card-chassis picker, June 2026)

import os
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

/// Temporary live-debug tap for the @ menu pipeline — prints every hop from
/// composer keystroke to applied results so a frozen list can be traced to
/// the exact link that broke. Flip `enabled` off once the pipeline is stable.
/// Streams via os_log too: `log stream --predicate 'category == "AtMenu"'`
/// traces a normally-launched app, no Xcode attach needed.
enum CosmoInlineContextMenuDebug {
    nonisolated(unsafe) static var enabled = false

    private static let logger = os.Logger(subsystem: "com.cosmo.os", category: "AtMenu")

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        print("🔍 [@menu] \(text)")
        logger.info("\(text, privacy: .public)")
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

    /// Fired on the main actor after every applied rebuild and highlight
    /// move. The menu view bumps an @State revision from this instead of
    /// relying on @Observable invalidation: in this overlay hierarchy the
    /// async applies were NOT repainting the view (Enter committed fresh
    /// results while the visible list stayed frozen one query behind).
    /// @State writes always repaint.
    var onApply: (() -> Void)?

    private var searchTask: Task<Void, Never>?
    private var snapshotTask: Task<SearchSnapshot, Never>?
    private var snapshotLoadedAt: Date?
    private var isUpgradingSnapshot = false
    private var lastRawQuery = ""
    private var lastSelectedAtoms: [Atom] = []
    private var generation = 0

    /// After this age a snapshot still answers instantly but a background
    /// rebuild starts (new atoms appear once it swaps in).
    private static let snapshotLifetime: TimeInterval = 180
    /// Stage-one snapshot: small enough to land in a few hundred ms so the
    /// first keystrokes have something real to search.
    private static let starterSnapshotLimit = 500
    /// Stage-two snapshot: ⌘K's own prewarm size.
    private static let fullSnapshotLimit = 10_000

    var highlightedEntry: Entry? {
        flattened.indices.contains(highlightedIndex) ? flattened[highlightedIndex] : nil
    }

    /// Build the search snapshot ahead of the menu opening (composer appear,
    /// bar hover) so the first "@" keystroke scans a warm index instead of
    /// waiting out the 10k-atom build.
    func prewarmSearchIndex() {
        loadSnapshotIfNeeded()
    }

    func moveHighlight(_ delta: Int) {
        let moved = CosmoAssistantMenuHighlightPolicy.moved(
            highlightedIndex, by: delta, count: flattened.count
        )
        guard moved != highlightedIndex else { return }
        highlightedIndex = moved
        onApply?()
    }

    func setHighlight(_ index: Int) {
        let clamped = CosmoAssistantMenuHighlightPolicy.clamped(index, count: flattened.count)
        guard clamped != highlightedIndex else { return }
        highlightedIndex = clamped
        onApply?()
    }

    func update(query rawQuery: String, selectedAtoms: [Atom]) {
        let parse = CosmoInlineContextScopeParser.parse(rawQuery)
        scope = parse.scope
        generation += 1
        let requestGeneration = generation
        searchTask?.cancel()
        lastRawQuery = rawQuery
        lastSelectedAtoms = selectedAtoms
        CosmoInlineContextMenuDebug.log("update raw=\"\(rawQuery)\" parsed=\"\(parse.query)\" scope=\(parse.scope.map(\.rawValue) ?? "nil") gen=\(requestGeneration)")

        if parse.query.isEmpty {
            isBrowsing = true
            // Warm the search snapshot while the user is still browsing so
            // the first typed character scans an already-built index.
            loadSnapshotIfNeeded()
            searchTask = Task { [weak self] in
                guard let self else { return }
                let current = await Self.activeSurfaceAtom()
                let recents = await Self.recents(scope: parse.scope, excluding: selectedAtoms, current: current)
                guard !Task.isCancelled, self.generation == requestGeneration else {
                    CosmoInlineContextMenuDebug.log("browsing gen=\(requestGeneration) DROPPED (cancelled=\(Task.isCancelled))")
                    return
                }
                CosmoInlineContextMenuDebug.log("browsing gen=\(requestGeneration) applied recents=\(recents.count)")
                self.rebuildBrowsing(selectedAtoms: selectedAtoms, current: current, recents: recents)
            }
        } else {
            isBrowsing = false
            let loader = loadSnapshotIfNeeded()
            searchTask = Task { [weak self] in
                // Just enough to coalesce burst typing — the scan is in-memory.
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard !Task.isCancelled else { return }
                let snapshot = await loader.value
                guard !Task.isCancelled else { return }
                // 10k-entry text scan — off the main actor, like ⌘K's.
                let results = await Task.detached(priority: .userInitiated) {
                    Self.scan(snapshot, query: parse.query, scope: parse.scope)
                }.value
                guard !Task.isCancelled, let self, self.generation == requestGeneration else {
                    CosmoInlineContextMenuDebug.log("search \"\(parse.query)\" gen=\(requestGeneration) DROPPED (cancelled=\(Task.isCancelled))")
                    return
                }
                CosmoInlineContextMenuDebug.log("search \"\(parse.query)\" gen=\(requestGeneration) applied results=\(results.count) snapshotEntries=\(snapshot.index.entries.count)")
                self.rebuildResults(results, selectedAtoms: selectedAtoms)
            }
        }
    }

    func teardown() {
        searchTask?.cancel()
        searchTask = nil
        onApply = nil
        lastRawQuery = ""
        lastSelectedAtoms = []
        // INVARIANT: never cancel or discard the snapshot here. Teardown runs
        // on every menu dismiss; discarding meant every reopen paid a
        // multi-second rebuild and typing raced a half-built index (the
        // "search never updates live" bug). Like ⌘K's prewarm, the snapshot
        // is retained for the app's lifetime and refreshed in the background.
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
        onApply?()
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

    /// ⌘K's instant search, for real this time. Two failed approaches taught
    /// the architecture:
    /// - `title/body LIKE %phrase%` ordered by updatedAt (the original) had
    ///   no relevance ranking at all.
    /// - Per-keystroke SQL (FTS prefix scan + LIKE table scan) starved on
    ///   the database connection (then one SERIAL DatabaseQueue shared by
    ///   the whole app; a concurrent-read DatabasePool since July 2026, but
    ///   per-keystroke table scans are wasteful on any connection). Every
    ///   keystroke queued multi-second scans behind the previous one, so the
    ///   visible list froze on the first query forever.
    /// The fix is ⌘K's own recipe: pay the database exactly once per menu
    /// session (fetchRecent 10k — the same prewarm ⌘K runs), normalize into
    /// a `CommandKSearchIndex` off the main actor, then answer every
    /// keystroke with a pure in-memory scan ranked by the shared lexical
    /// tier ladder. INVARIANT: never run per-keystroke SQL here.
    private struct SearchSnapshot: Sendable {
        let index: CommandKSearchIndex
        let atomsByUUID: [String: Atom]
    }

    /// Kicked off from prewarm (bar hover, pane appear) and every update.
    /// LAW: queries must NEVER await a rebuild when any snapshot exists — a
    /// full build on a transcript-heavy library takes seconds, and awaiting
    /// it is exactly the "list frozen while I type" bug. The first-ever call
    /// two-stages the warmup (a ~500-atom starter lands in a few hundred ms,
    /// the full ⌘K-sized build swaps in behind it); afterwards a stale
    /// snapshot keeps answering while its replacement builds in the
    /// background, and the live query re-runs when the swap lands.
    @discardableResult
    private func loadSnapshotIfNeeded() -> Task<SearchSnapshot, Never> {
        if let snapshotTask {
            let isStale = snapshotLoadedAt.map {
                Date().timeIntervalSince($0) >= Self.snapshotLifetime
            } ?? true
            if isStale {
                upgradeSnapshotInBackground(reason: "stale refresh")
            }
            return snapshotTask
        }

        let starter = buildSnapshot(limit: Self.starterSnapshotLimit, label: "starter")
        snapshotTask = starter
        snapshotLoadedAt = Date()
        upgradeSnapshotInBackground(reason: "initial full build")
        return starter
    }

    private func buildSnapshot(limit: Int, label: String) -> Task<SearchSnapshot, Never> {
        CosmoInlineContextMenuDebug.log("snapshot(\(label)) build started limit=\(limit)")
        return Task.detached(priority: .userInitiated) { () -> SearchSnapshot in
            let startedAt = Date()
            let atoms = (try? await AtomRepository.shared.fetchRecent(limit: limit)) ?? []
            // Entry construction normalizes every full body/metadata — that's
            // why this runs detached, exactly like the ⌘K prewarm.
            var index = CommandKSearchIndex()
            index.replace(CommandKSearchIndex.entries(for: atoms))
            let byUUID = Dictionary(atoms.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
            CosmoInlineContextMenuDebug.log("snapshot(\(label)) build finished atoms=\(atoms.count) in \(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s")
            return SearchSnapshot(index: index, atomsByUUID: byUUID)
        }
    }

    /// Builds the full snapshot without ever blocking queries, swaps it in on
    /// completion, and re-runs the query the user is currently looking at so
    /// the visible results upgrade in place.
    private func upgradeSnapshotInBackground(reason: String) {
        guard !isUpgradingSnapshot else { return }
        isUpgradingSnapshot = true
        let build = buildSnapshot(limit: Self.fullSnapshotLimit, label: "full — \(reason)")
        Task { [weak self] in
            _ = await build.value
            guard let self else { return }
            self.snapshotTask = build
            self.snapshotLoadedAt = Date()
            self.isUpgradingSnapshot = false
            if !self.lastRawQuery.isEmpty {
                CosmoInlineContextMenuDebug.log("snapshot swap → re-running \"\(self.lastRawQuery)\"")
                self.update(query: self.lastRawQuery, selectedAtoms: self.lastSelectedAtoms)
            }
        }
    }

    nonisolated private static func scan(
        _ snapshot: SearchSnapshot,
        query: String,
        scope: CosmoInlineContextScope?
    ) -> [Atom] {
        // Over-fetch when scoped: the index ranks across every kind and the
        // scope filter runs afterwards.
        let ranked = snapshot.index.search(query, limit: scope == nil ? 60 : 400)
        return ranked
            .compactMap { snapshot.atomsByUUID[$0.atomUUID] }
            .filter { matchesScope($0, scope: scope) }
            .prefix(18)
            .map { $0 }
    }

    nonisolated private static func matchesScope(_ atom: Atom, scope: CosmoInlineContextScope?) -> Bool {
        guard let scope else { return true }
        switch scope {
        case .swipe: return atom.isSwipeFileAtom
        case .research: return atom.type == .research && !atom.isSwipeFileAtom
        case .content: return atom.type == .content
        case .profile: return atom.type == .clientProfile
        case .idea: return atom.type == .idea
        case .note: return atom.type == .note
        }
    }
}

/// The @ menu wears ⌘K's identity marks: the same de-filled glyph vocabulary
/// (CommandKVisualIdentity) and the same entity accents (cortexEntityAccent),
/// so a note is the same object in both surfaces. Swipes get the swipe-file
/// bolt + tint since `research` masks their identity at the type level.
enum CosmoInlineContextIdentity {
    static func symbol(for atom: Atom) -> String {
        if atom.isSwipeFileAtom { return "bolt" }
        return CommandKVisualIdentity.atom(type: atom.type).symbolName
    }

    static func tint(for atom: Atom) -> Color {
        if atom.isSwipeFileAtom { return DS.entitySwipe }
        return cortexEntityAccent(atom.type)
    }
}

// MARK: - View

struct CosmoInlineAssistantContextMenu: View {
    let model: CosmoInlineContextMenuModel
    let searchText: String
    let selectedAtoms: [Atom]
    let onCommit: (CosmoInlineContextMenuModel.Entry) -> Void
    let onClear: () -> Void
    /// nil lets the host size the menu (inline hosts like the concept
    /// quick-add fields); the default matches the composer overlays.
    var menuWidth: CGFloat? = 340

    /// Bumped by the model's onApply after every async rebuild. A @State write
    /// always marks this view dirty, so applied results repaint even though
    /// @Observable invalidation doesn't fire in this overlay hierarchy.
    @State private var appliedRevision = 0

    private let listMaxHeight: CGFloat = 296

    var body: some View {
        // Unconditional @State read — the repaint dependency must not hide
        // behind the debug flag.
        let revision = appliedRevision
        let _ = CosmoInlineContextMenuDebug.log(
            "menu RENDER rev=\(revision) browsing=\(model.isBrowsing) rows=\(model.flattened.count) firstRow=\"\(model.flattened.first?.atom.title ?? "-")\""
        )
        VStack(spacing: 0) {
            header
            CosmoGradientDivider()
            content
            CosmoKeyboardFooter(selectLabel: "Add")
        }
        .frame(width: menuWidth)
        .cosmoMenuChrome(cornerRadius: 14)
        .onAppear {
            CosmoInlineContextMenuDebug.log("menu onAppear searchText=\"\(searchText)\"")
            model.onApply = { appliedRevision &+= 1 }
            model.setHighlight(0)
            model.update(query: searchText, selectedAtoms: selectedAtoms)
        }
        .onDisappear {
            CosmoInlineContextMenuDebug.log("menu onDisappear")
            model.teardown()
        }
        .onChange(of: searchText) { _, value in
            CosmoInlineContextMenuDebug.log("menu onChange searchText=\"\(value)\"")
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

    // Plain VStack, rows identified by their entry id: the list tops out at
    // 18 rows so laziness buys nothing, and `.id(index)` gave the NEW row at
    // a position the SAME explicit identity as the OLD row there — fighting
    // the ForEach's uuid identity when a fresh result set replaced the list.
    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
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
                guard model.flattened.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(model.flattened[newIndex].id)
                }
            }
        }
    }

    private func entryRow(_ entry: CosmoInlineContextMenuModel.Entry, index: Int) -> some View {
        let _ = CosmoInlineContextMenuDebug.log("row BUILD idx=\(index) \"\(entry.atom.title ?? "Untitled")\"")
        return CosmoAssistantMenuRow(
            icon: icon(for: entry),
            iconTint: tint(for: entry),
            title: entry.atom.title ?? "Untitled",
            trailingHint: hint(for: entry),
            showsCheckmark: entry.isSelected,
            isHighlighted: index == model.highlightedIndex
        )
        .id(entry.id)
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
        return CosmoInlineContextIdentity.symbol(for: entry.atom)
    }

    private func tint(for entry: CosmoInlineContextMenuModel.Entry) -> Color? {
        if case .attachCurrent = entry { return DS.accent }
        return CosmoInlineContextIdentity.tint(for: entry.atom)
    }

    private func hint(for entry: CosmoInlineContextMenuModel.Entry) -> String? {
        if case .attachCurrent = entry { return "current" }
        return CosmoInlineAssistantContextMentionFormatter.typeLabel(for: entry.atom)
    }

    private func scopeTint(_ scope: CosmoInlineContextScope) -> Color {
        CosmoMentionColors.color(for: scope.entityType)
    }
}
