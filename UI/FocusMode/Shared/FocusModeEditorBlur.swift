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

    @discardableResult
    @MainActor
    static func clearEditableFirstResponderForClick(in window: NSWindow?, at locationInWindow: NSPoint) -> Bool {
        guard let window, let contentView = window.contentView else {
            return false
        }

        let locationInContent = contentView.convert(locationInWindow, from: nil)
        let hitView = contentView.hitTest(locationInContent)
        guard shouldClearEditableFirstResponder(currentResponder: window.firstResponder, hitView: hitView) else {
            return false
        }

        return clearFirstResponder(in: window)
    }

    @MainActor
    static func shouldClearEditableFirstResponder(currentResponder: NSResponder?, hitView: NSView?) -> Bool {
        guard let responderView = currentResponder as? NSView,
              responderView.isEditableTextInputOrDescendant else {
            return false
        }

        if let hitView, hitView.isEditableTextInputSurface {
            return false
        }

        return true
    }
}

enum FocusModeTextClipboardAction {
    case cut
    case copy
    case paste
    case selectAll
}

@MainActor
enum FocusModeTextClipboardTarget {
    private final class WeakTextView {
        weak var value: NSTextView?
    }

    private static let activeTextView = WeakTextView()

    static func activate(_ textView: NSTextView) {
        guard textView.isEditable || textView.isSelectable else { return }
        activeTextView.value = textView
    }

    static func performKeyEquivalent(_ event: NSEvent, fallback textView: NSTextView) -> Bool {
        guard let action = action(for: event) else { return false }
        if send(action, in: textView.window) {
            return true
        }
        perform(action, on: textView)
        return true
    }

    static func send(_ action: FocusModeTextClipboardAction, in window: NSWindow?) -> Bool {
        if let textView = currentTextView(in: window) {
            perform(action, on: textView)
            return true
        }

        guard let textView = activeTextView(in: window) else {
            return false
        }
        perform(action, on: textView)
        return true
    }

    private static func activeTextView(in window: NSWindow?) -> NSTextView? {
        guard let textView = activeTextView.value,
              textView.window === window,
              textView.isEditable || textView.isSelectable else {
            return nil
        }
        return textView
    }

    private static func currentTextView(in window: NSWindow?) -> NSTextView? {
        guard let textView = window?.firstResponder as? NSTextView,
              textView.isEditable || textView.isSelectable else {
            return nil
        }
        return textView
    }

    private static func action(for event: NSEvent) -> FocusModeTextClipboardAction? {
        guard event.type == .keyDown,
              let character = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandOnly = flags == .command
        let isControlOnly = flags == .control

        if character == "c", isCommandOnly || isControlOnly {
            return .copy
        }

        guard isCommandOnly else { return nil }

        switch character {
        case "x": return .cut
        case "v": return .paste
        case "a": return .selectAll
        default: return nil
        }
    }

    private static func perform(_ action: FocusModeTextClipboardAction, on textView: NSTextView) {
        switch action {
        case .cut:
            textView.cut(nil)
        case .copy:
            textView.copy(nil)
        case .paste:
            textView.paste(nil)
        case .selectAll:
            textView.selectAll(nil)
        }
    }
}

private extension NSView {
    var isEditableTextInputSurface: Bool {
        if isEditableTextInputOrDescendant {
            return true
        }

        if let scrollView = self as? NSScrollView,
           scrollView.documentView?.isEditableTextInputOrDescendant == true {
            return true
        }

        if let clipView = self as? NSClipView,
           clipView.documentView?.isEditableTextInputOrDescendant == true {
            return true
        }

        return false
    }

    var isEditableTextInputOrDescendant: Bool {
        var view: NSView? = self
        while let currentView = view {
            if let textView = currentView as? NSTextView, textView.isEditable {
                return true
            }
            if let textField = currentView as? NSTextField, textField.isEditable {
                return true
            }
            view = currentView.superview
        }
        return false
    }
}

struct FocusModeEditorBlurClickMonitor: NSViewRepresentable {
    let onBlur: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBlur: onBlur)
    }

    func makeNSView(context: Context) -> FocusModeEditorBlurMonitorView {
        let view = FocusModeEditorBlurMonitorView()
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: FocusModeEditorBlurMonitorView, context: Context) {
        context.coordinator.onBlur = onBlur
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        var onBlur: @MainActor () -> Void
        private weak var view: FocusModeEditorBlurMonitorView?
        private weak var monitoredWindow: NSWindow?
        private var monitor: Any?

        init(onBlur: @escaping @MainActor () -> Void) {
            self.onBlur = onBlur
        }

        deinit {
            removeMonitor()
        }

        func attach(to view: FocusModeEditorBlurMonitorView) {
            self.view = view
            updateMonitor(for: view.window)
        }

        func viewDidMoveToWindow(_ view: FocusModeEditorBlurMonitorView) {
            attach(to: view)
        }

        private func updateMonitor(for window: NSWindow?) {
            guard monitoredWindow !== window else { return }
            removeMonitor()
            monitoredWindow = window

            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                MainActor.assumeIsolated {
                    guard let window = self.view?.window,
                          event.window === window else {
                        return
                    }
                    if FocusModeEditorBlur.clearEditableFirstResponderForClick(in: window, at: event.locationInWindow) {
                        self.onBlur()
                    }
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            monitoredWindow = nil
        }
    }
}

final class FocusModeEditorBlurMonitorView: NSView {
    weak var coordinator: FocusModeEditorBlurClickMonitor.Coordinator?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.viewDidMoveToWindow(self)
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
