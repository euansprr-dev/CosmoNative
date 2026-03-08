import SwiftUI

struct ActiveCanvasDragState<ID: Hashable>: Equatable {
    var activeId: ID?
    var translation: CGSize = .zero

    var isDragging: Bool {
        activeId != nil
    }

    func translation(for id: ID) -> CGSize {
        activeId == id ? translation : .zero
    }

    mutating func begin(id: ID, translation: CGSize) {
        activeId = id
        self.translation = translation
    }

    mutating func update(translation: CGSize) {
        self.translation = translation
    }

    mutating func clear() {
        activeId = nil
        translation = .zero
    }
}
