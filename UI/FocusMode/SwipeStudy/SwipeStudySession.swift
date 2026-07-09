// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudySession.swift
// The study queue: whichever swipe-file surface opens Study records the
// library order it was showing, so ⌘[ / ⌘] (and the top-bar chevrons) walk
// the same sequence the user was browsing — the Up Next feel.
// July 2026

import Foundation
import Observation

@MainActor
@Observable
final class SwipeStudySession {
    static let shared = SwipeStudySession()

    /// Entity ids (Atom row ids) in the order the launching surface showed them.
    private(set) var order: [Int64] = []
    private(set) var currentIndex: Int?

    private init() {}

    /// Called by the surface that opens Study (library/home). A missing
    /// `current` in `order` clears the queue — navigation hides.
    func begin(order: [Int64], current: Int64) {
        guard let index = order.firstIndex(of: current) else {
            clear()
            return
        }
        self.order = order
        self.currentIndex = index
    }

    func clear() {
        order = []
        currentIndex = nil
    }

    var hasPrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    var hasNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex < order.count - 1
    }

    var positionLabel: String? {
        guard let currentIndex, !order.isEmpty else { return nil }
        return "\(currentIndex + 1) of \(order.count)"
    }

    /// Advance and return the new entity id, or nil at the edge.
    func stepPrevious() -> Int64? {
        guard hasPrevious, let currentIndex else { return nil }
        self.currentIndex = currentIndex - 1
        return order[currentIndex - 1]
    }

    func stepNext() -> Int64? {
        guard hasNext, let currentIndex else { return nil }
        self.currentIndex = currentIndex + 1
        return order[currentIndex + 1]
    }

    /// Keep the pointer honest when Study navigates by other means
    /// (e.g. a pattern-sibling jump).
    func syncPointer(to entityId: Int64) {
        currentIndex = order.firstIndex(of: entityId)
        if currentIndex == nil { order = [] }
    }
}
