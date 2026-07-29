import Foundation
import SwiftUI

/// Live per-genre counts for the sidebar's adaptive space rows.
///
/// The sidebar shows one row per non-empty genre — a posts-only library shows
/// no extra rows at all, and the first newsletter capture makes the
/// Newsletters room appear. That adaptivity needs counts BEFORE any library
/// page has loaded, so this store mirrors `SwipeBoardStore`'s two paths: a
/// free tally from an already-loaded library, and a database tally for the
/// cold sidebar. Counts only — genre definitions are the closed `SwipeGenre`
/// vocabulary, so unlike boards there is nothing to create or persist here.
@MainActor
@Observable
final class SwipeSpaceStore {

    static let shared = SwipeSpaceStore()

    private(set) var counts: [SwipeGenre: Int] = [:]
    private(set) var isLoaded = false

    /// Genres that deserve a sidebar row, in vocabulary order. `.post` is
    /// excluded — the Posts room is the always-present landing, not an
    /// adaptive row.
    var visibleSpaces: [SwipeGenre] {
        SwipeGenre.allCases.filter { $0 != .post && (counts[$0] ?? 0) > 0 }
    }

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        await refreshCountsFromDatabase()
    }

    /// Tally from already-loaded gallery items (free when the library is open).
    /// The library view model pushes this on every reload, so a capture or a
    /// sync pull updates the sidebar within the same refresh.
    func refreshCounts(from items: [SwipeGalleryItem]) {
        var tally: [SwipeGenre: Int] = [:]
        for item in items {
            tally[item.genre, default: 0] += 1
        }
        isLoaded = true
        if counts != tally {
            counts = tally
        }
    }

    /// Tally straight from the database (sidebar before any library load).
    /// Derivation runs in Swift — SQL cannot run `Atom.swipeGenre`'s ladder
    /// over legacy rows, and the ~hundreds of swipe atoms make this cheap.
    func refreshCountsFromDatabase() async {
        do {
            let atoms = try await AtomRepository.shared.search(query: "", types: [.research])
            var tally: [SwipeGenre: Int] = [:]
            for atom in atoms where atom.isSwipeFileAtom {
                tally[atom.swipeGenre, default: 0] += 1
            }
            isLoaded = true
            if counts != tally {
                counts = tally
            }
        } catch {
            print("❌ Failed to refresh swipe space counts: \(error)")
        }
    }
}
