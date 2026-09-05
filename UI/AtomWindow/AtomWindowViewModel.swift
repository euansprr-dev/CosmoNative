// CosmoOS/UI/AtomWindow/AtomWindowViewModel.swift
// State management for the floating atom viewer panel

import SwiftUI

@Observable @MainActor
final class AtomWindowViewModel {
    private let database = CosmoDatabase.shared

    // MARK: - Current Atom

    var currentAtom: Atom?
    var isLoading = false
    var isPresented = false

    // MARK: - Navigation History

    private(set) var backStack: [String] = []
    private(set) var forwardStack: [String] = []
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    // MARK: - Search

    var isSearchVisible = false
    var searchQuery = ""
    var searchResults: [AtomSearchResult] = []
    var selectedSearchIndex = 0
    var selectedTypeFilter: AtomType?

    // MARK: - Bookmarks

    var bookmarkedUUIDs: Set<String> = []

    // MARK: - Recent Atoms (empty state)

    var recentAtoms: [Atom] = []

    // MARK: - Private

    private let maxHistorySize = 50
    private var searchTask: Task<Void, Never>?
    private let searchEngine = AtomSearchEngine()

    private let bookmarksKey = "atomWindowBookmarks"
    private let lastAtomKey = "atomWindowLastAtomUUID"

    // User-facing types for search results
    private let searchableTypes: [AtomType] = [
        .idea, .content, .research, .connection, .note,
        .task, .project, .journalEntry, .objective, .stickyNote,
        .clientProfile, .blockTemplate
    ]

    // MARK: - Init

    init() {
        loadBookmarks()
    }

    // MARK: - Navigation

    func navigate(to uuid: String) async {
        guard uuid != currentAtom?.uuid else { return }

        isLoading = true
        defer { isLoading = false }

        // Release lock on current atom
        if let currentUUID = currentAtom?.uuid {
            AtomRepository.shared.releaseEditingLock(uuid: currentUUID)
            backStack.append(currentUUID)
            if backStack.count > maxHistorySize {
                backStack.removeFirst()
            }
        }

        forwardStack.removeAll()

        do {
            if let atom = try await AtomRepository.shared.fetch(uuid: uuid) {
                guard !Task.isCancelled else { return }
                currentAtom = atom
                AtomRepository.shared.acquireEditingLock(uuid: uuid)
                saveSession()
            }
        } catch {
            print("[AtomWindow] Failed to fetch atom \(uuid): \(error)")
        }
    }

    func goBack() async {
        guard let previousUUID = backStack.popLast() else { return }

        // Push current to forward stack
        if let currentUUID = currentAtom?.uuid {
            AtomRepository.shared.releaseEditingLock(uuid: currentUUID)
            forwardStack.append(currentUUID)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if let atom = try await AtomRepository.shared.fetch(uuid: previousUUID) {
                currentAtom = atom
                AtomRepository.shared.acquireEditingLock(uuid: previousUUID)
                saveSession()
            }
        } catch {
            print("[AtomWindow] Failed to go back to \(previousUUID): \(error)")
        }
    }

    func goForward() async {
        guard let nextUUID = forwardStack.popLast() else { return }

        // Push current to back stack
        if let currentUUID = currentAtom?.uuid {
            AtomRepository.shared.releaseEditingLock(uuid: currentUUID)
            backStack.append(currentUUID)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if let atom = try await AtomRepository.shared.fetch(uuid: nextUUID) {
                currentAtom = atom
                AtomRepository.shared.acquireEditingLock(uuid: nextUUID)
                saveSession()
            }
        } catch {
            print("[AtomWindow] Failed to go forward to \(nextUUID): \(error)")
        }
    }

    // MARK: - Search

    func performSearch() {
        searchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            selectedSearchIndex = 0
            return
        }

        searchTask = Task {
            // Debounce 200ms
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            do {
                var options = AtomSearchOptions.default
                options.limit = 20
                if let typeFilter = selectedTypeFilter {
                    options.types = [typeFilter]
                } else {
                    options.types = searchableTypes
                }

                let results = try await searchEngine.search(query: query, options: options)
                guard !Task.isCancelled else { return }

                searchResults = results
                selectedSearchIndex = 0
            } catch {
                guard !Task.isCancelled else { return }
                print("[AtomWindow] Search failed: \(error)")
                searchResults = []
            }
        }
    }

    func openSearchResult(at index: Int) async {
        guard index >= 0, index < searchResults.count else { return }
        let result = searchResults[index]
        isSearchVisible = false
        searchQuery = ""
        searchResults = []
        await navigate(to: result.atom.uuid)
    }

    func moveSearchSelection(by offset: Int) {
        guard !searchResults.isEmpty else { return }
        let newIndex = selectedSearchIndex + offset
        selectedSearchIndex = max(0, min(newIndex, searchResults.count - 1))
    }

    // MARK: - Bookmarks

    func toggleBookmark() {
        guard let uuid = currentAtom?.uuid else { return }
        if bookmarkedUUIDs.contains(uuid) {
            bookmarkedUUIDs.remove(uuid)
        } else {
            bookmarkedUUIDs.insert(uuid)
        }
        saveBookmarks()
    }

    var isCurrentBookmarked: Bool {
        guard let uuid = currentAtom?.uuid else { return false }
        return bookmarkedUUIDs.contains(uuid)
    }

    // MARK: - Create

    func createNewAtom(type: AtomType) async {
        if !database.isReady {
            print("[AtomWindow] createNewAtom requested before database reported ready — type=\(type.rawValue)")
        }

        let atom = Atom.new(type: type, title: "New \(type.displayName)")

        do {
            let created = try await AtomRepository.shared.create(atom)
            guard let persisted = try await AtomRepository.shared.fetch(uuid: created.uuid) else {
                print("[AtomWindow] Created atom missing on immediate fetch — uuid=\(created.uuid) type=\(created.type.rawValue)")
                currentAtom = created
                saveSession()
                await refreshRecentAtoms()
                return
            }

            await navigate(to: persisted.uuid)
            await refreshRecentAtoms()
        } catch {
            print("[AtomWindow] Failed to create atom — type=\(type.rawValue) error=\(error)")
        }
    }

    // MARK: - Session Persistence

    func restoreLastSession() async {
        if !database.isReady {
            print("[AtomWindow] restoreLastSession started before database reported ready")
        }

        if let uuid = currentAtom?.uuid {
            // Keep the mounted editor, but don't keep a deleted item alive or
            // leave its window title stale after another device changes it.
            do {
                let latest = try await AtomRepository.shared.fetch(uuid: uuid)
                guard !Task.isCancelled, currentAtom?.uuid == uuid else { return }
                if let latest, !latest.isDeleted {
                    currentAtom = latest
                } else {
                    unloadCurrentSession()
                    await refreshRecentAtoms()
                }
            } catch {
                print("[AtomWindow] Could not refresh retained item: \(error)")
            }
            return
        }

        // Restore last open atom
        if let uuid = UserDefaults.standard.string(forKey: lastAtomKey) {
            guard !Task.isCancelled else { return }
            print("[AtomWindow] Restoring last session atom uuid=\(uuid)")
            await navigate(to: uuid)
        }
        // Recents only serve the empty state; don't put an unused query on
        // the critical path to opening the last document.
        if currentAtom == nil, !Task.isCancelled {
            await refreshRecentAtoms()
        }
    }

    func saveSession() {
        UserDefaults.standard.set(currentAtom?.uuid, forKey: lastAtomKey)
    }

    func releaseCurrentLock() {
        if let uuid = currentAtom?.uuid {
            AtomRepository.shared.releaseEditingLock(uuid: uuid)
        }
    }

    func unloadCurrentSession() {
        releaseCurrentLock()
        currentAtom = nil
        isLoading = false
        isSearchVisible = false
        searchQuery = ""
        searchResults = []
        selectedSearchIndex = 0
        selectedTypeFilter = nil
        backStack.removeAll()
        forwardStack.removeAll()
        searchTask?.cancel()
        searchTask = nil
    }

    // MARK: - Recent Atoms Refresh

    func refreshRecentAtoms() async {
        do {
            recentAtoms = try await AtomRepository.shared.fetchRecent(limit: 8)
        } catch {
            print("[AtomWindow] Failed to refresh recent atoms: \(error)")
        }
    }

    // MARK: - Persistence Helpers

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let uuids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            bookmarkedUUIDs = uuids
        }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarkedUUIDs) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }
}

// MARK: - Atom Type Helpers

extension AtomWindowViewModel {

    /// Maps AtomType to EntityType for focus view routing
    static func entityType(for atomType: AtomType) -> EntityType {
        switch atomType {
        case .idea: return .idea
        case .task, .scheduleBlock: return .task
        case .content, .contentDraft: return .content
        case .research: return .research
        case .connection, .clientProfile: return .connection
        case .project: return .project
        case .note: return .note
        case .extract, .question: return .extract
        // Study surfaces route to their own focus modes — falling through to
        // `.idea` opened a Deep Dive as an Idea from ⌘K.
        case .deepDive: return .deepDive
        case .inquirySession: return .inquirySession
        default: return .idea
        }
    }

    /// Returns the DS entity color for an atom type
    nonisolated static func entityColor(for atomType: AtomType) -> Color {
        switch atomType {
        case .idea: return DS.entityIdea
        case .content, .contentDraft: return DS.entityContent
        case .research: return DS.entityResearch
        case .connection, .clientProfile: return DS.entityConnection
        case .note: return DS.entityNote
        case .task, .scheduleBlock: return DS.entityTask
        case .stickyNote: return DS.entityStickyNote
        case .image: return DS.entityImage
        default: return DS.textSecondary
        }
    }
}
