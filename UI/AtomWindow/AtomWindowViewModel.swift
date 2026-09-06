// CosmoOS/UI/AtomWindow/AtomWindowViewModel.swift
// State management for the floating atom viewer panel

import AppKit
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

    // MARK: - Switcher

    /// The search/browse surface. It is the window's home when nothing is
    /// open, and the layer "Back" lifts over an open item.
    let switcher = AtomSwitcherModel()
    private(set) var switcherRequested = false

    var isSwitcherVisible: Bool {
        switcherRequested || (currentAtom == nil && !isLoading)
    }

    // MARK: - Bookmarks

    var bookmarkedUUIDs: Set<String> = []

    // MARK: - Private

    private let maxHistorySize = 50

    private let bookmarksKey = "atomWindowBookmarks"
    private let lastAtomKey = "atomWindowLastAtomUUID"

    // MARK: - Init

    init() {
        loadBookmarks()
    }

    // MARK: - Navigation

    func navigate(to uuid: String) async {
        guard uuid != currentAtom?.uuid else {
            dismissSwitcher()
            return
        }

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
                dismissSwitcher()
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
                dismissSwitcher()
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
                dismissSwitcher()
            }
        } catch {
            print("[AtomWindow] Failed to go forward to \(nextUUID): \(error)")
        }
    }

    // MARK: - Switcher

    /// Lift the switcher over the open item (Back, the title button, ⌘K).
    func showSwitcher() {
        switcher.present(openAtom: currentAtom, pinnedUUIDs: bookmarkedUUIDs)
        withAnimation(ProMotionSprings.modal) {
            switcherRequested = true
        }
    }

    /// Drop the switcher layer. With nothing open the switcher IS the
    /// window's home, so this only ever hides it over an item.
    func dismissSwitcher() {
        guard switcherRequested else { return }
        withAnimation(ProMotionSprings.modal) {
            switcherRequested = false
        }
        if currentAtom != nil {
            switcher.dismiss()
        }
    }

    func toggleSwitcher() {
        if switcherRequested {
            dismissSwitcher()
        } else {
            showSwitcher()
        }
    }

    /// The switcher is the home surface: make sure it is loaded whenever the
    /// window shows without an open item.
    func presentSwitcherHome() {
        switcher.present(openAtom: nil, pinnedUUIDs: bookmarkedUUIDs)
    }

    /// Esc inside the switcher: clear the query, then the layer, then the
    /// window — resolved by the model, executed here.
    func escapeSwitcher() {
        switch switcher.escapeAction {
        case .clearQuery:
            switcher.clearQuery()
        case .returnToOpenItem:
            dismissSwitcher()
        case .closeWindow:
            AtomWindowPanelController.shared.hide()
        }
    }

    func open(_ row: AtomSwitcherRow) {
        Task { await navigate(to: row.uuid) }
    }

    /// ⌘Return — hand the item to the main window and step aside.
    func openInMainWindow(_ row: AtomSwitcherRow) {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .init("com.cosmo.navigateToAtom"),
            object: nil,
            userInfo: ["uuid": row.uuid]
        )
        AtomWindowPanelController.shared.hide()
    }

    func togglePin(_ row: AtomSwitcherRow) {
        togglePin(uuid: row.uuid)
    }

    // MARK: - Bookmarks

    func toggleBookmark() {
        guard let uuid = currentAtom?.uuid else { return }
        togglePin(uuid: uuid)
    }

    private func togglePin(uuid: String) {
        if bookmarkedUUIDs.contains(uuid) {
            bookmarkedUUIDs.remove(uuid)
        } else {
            bookmarkedUUIDs.insert(uuid)
        }
        saveBookmarks()
        switcher.setPinned(bookmarkedUUIDs)
    }

    var isCurrentBookmarked: Bool {
        guard let uuid = currentAtom?.uuid else { return false }
        return bookmarkedUUIDs.contains(uuid)
    }

    // MARK: - Create

    func createNewAtom(type: AtomType, title: String? = nil) async {
        if !database.isReady {
            print("[AtomWindow] createNewAtom requested before database reported ready — type=\(type.rawValue)")
        }

        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let atom = Atom.new(
            type: type,
            title: resolvedTitle?.isEmpty == false ? resolvedTitle! : "New \(type.displayName)"
        )

        do {
            let created = try await AtomRepository.shared.create(atom)
            guard let persisted = try await AtomRepository.shared.fetch(uuid: created.uuid) else {
                print("[AtomWindow] Created atom missing on immediate fetch — uuid=\(created.uuid) type=\(created.type.rawValue)")
                currentAtom = created
                saveSession()
                dismissSwitcher()
                return
            }

            await navigate(to: persisted.uuid)
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
                    presentSwitcherHome()
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
        // Nothing to restore: the switcher is the home surface.
        if currentAtom == nil, !Task.isCancelled {
            presentSwitcherHome()
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
        switcherRequested = false
        switcher.reset()
        backStack.removeAll()
        forwardStack.removeAll()
    }

    /// The window is ordering out: the switcher layer never survives a hide
    /// (⌥E reopens onto the item, exactly as it was left).
    func prepareForHide() {
        switcherRequested = false
        switcher.dismiss()
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
