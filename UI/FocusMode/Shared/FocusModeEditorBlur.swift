import AppKit
import SwiftUI

enum FocusModeEditorBlur {
    @discardableResult
    @MainActor
    static func clearFirstResponder() -> Bool {
        clearFirstResponder(in: NSApp.keyWindow)
    }

    @discardableResult
    @MainActor
    static func clearFirstResponder(in window: NSWindow?) -> Bool {
        guard let window, let currentResponder = window.firstResponder else {
            return false
        }

        let didClear = window.makeFirstResponder(nil)
        return didClear && window.firstResponder !== currentResponder
    }
}

struct FocusModeEditorBlurTapLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusModeEditorBlurTapView {
        FocusModeEditorBlurTapView()
    }

    func updateNSView(_ nsView: FocusModeEditorBlurTapView, context: Context) {}
}

final class FocusModeEditorBlurTapView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        FocusModeEditorBlur.clearFirstResponder(in: window)
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
