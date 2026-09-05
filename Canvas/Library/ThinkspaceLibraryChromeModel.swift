// CosmoOS/Canvas/Library/ThinkspaceLibraryChromeModel.swift
// The library's chrome state, hoisted out of the lens view so the SPACE chrome
// row (owned by CanvasView) can render the lenses, sort menu and search field
// on the app's one island baseline while the lens content stays below. One
// model per CanvasView; `activate(thinkspaceId:)` is idempotent because the
// canvas refreshes the library twice per space switch.

import SwiftUI

@MainActor
@Observable
final class ThinkspaceLibraryChromeModel {
    private(set) var thinkspaceId: String = ""

    /// Per-space, persisted the moment they change — saved under THIS model's
    /// space id, never a stale one (a space switch mid-edit used to save A's
    /// prefs under B's key).
    var prefs = ThinkspaceLibraryPrefs() {
        didSet {
            guard !thinkspaceId.isEmpty, prefs != oldValue else { return }
            prefs.save(thinkspaceId: thinkspaceId)
        }
    }

    var inquirySourceIDs: [String] = []
    var searchText = ""
    /// Inside a folder, search can look through just the folder or everything.
    var searchEntireThinkspace = false
    var kindFilter: String?
    /// Mirrored from the row's search field FocusState.
    var isSearchFocused = false
    /// The row's field focuses when this ticks (⌘F).
    private(set) var searchFocusRequest = 0
    /// The lens refocuses its browser when this ticks (search dismissed).
    private(set) var browserFocusRequest = 0

    /// The lens view installs its own Esc ladder (rename → selection →
    /// folder) here; the model runs search-clearing first.
    @ObservationIgnored var escapeHandler: (() -> Bool)?

    /// Idempotent: loads prefs once per space and clears transient search state.
    func activate(thinkspaceId: String) {
        guard thinkspaceId != self.thinkspaceId else { return }
        self.thinkspaceId = thinkspaceId
        prefs = ThinkspaceLibraryPrefs.load(thinkspaceId: thinkspaceId)
        if prefs.viewMode == .gallery { prefs.viewMode = .icons }
        searchText = ""
        searchEntireThinkspace = false
        kindFilter = nil
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Lenses / sort

    func setViewMode(_ mode: ThinkspaceLibraryViewMode) {
        guard prefs.viewMode != mode else { return }
        withAnimation(ProMotionSprings.focusTransition) { prefs.viewMode = mode }
    }

    /// Re-picking the active field flips direction (Finder); a new field
    /// arrives in its natural direction (names A→Z, dates newest-first).
    func selectSort(_ field: ThinkspaceLibrarySortField) {
        withAnimation(ProMotionSprings.snappy) {
            if prefs.sortField == field {
                prefs.sortAscending.toggle()
            } else {
                prefs.sortField = field
                prefs.sortAscending = field.defaultAscending
            }
        }
    }

    func setGrouping(_ grouping: ThinkspaceLibraryGrouping) {
        withAnimation(ProMotionSprings.snappy) { prefs.grouping = grouping }
    }

    func setIconScale(_ scale: ThinkspaceLibraryIconScale) {
        withAnimation(ProMotionSprings.gentle) { prefs.iconScale = scale }
    }

    func stepIconScale(up: Bool) {
        let next = up ? prefs.iconScale.stepUp : prefs.iconScale.stepDown
        if let next { setIconScale(next) }
    }

    // MARK: Search + focus

    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    func clearSearch() {
        searchText = ""
        kindFilter = nil
        searchEntireThinkspace = false
    }

    /// Esc: clear a search first (the field is the row's), then hand the
    /// lens its own ladder. Returns whether anything was dismissed.
    func handleEscape() -> Bool {
        if isSearchFocused || isSearching {
            clearSearch()
            isSearchFocused = false
            browserFocusRequest += 1
            return true
        }
        return escapeHandler?() ?? false
    }

    func refocusBrowser() {
        browserFocusRequest += 1
    }
}
