import AppKit
import SwiftUI

enum AssistantPresentationIntent: Equatable {
    case ensureVisible
    case pane
}

enum AssistantPresentationHost: Equatable {
    case resting, compact, pane
}

/// Presentation belongs to the window; the session, stream and editor belong to
/// the store. A destination must accept a transfer before the old host disappears.
@Observable @MainActor
final class CompanionAssistantCoordinator {
    static let shared = CompanionAssistantCoordinator()
    private(set) var host: AssistantPresentationHost = .resting
    private(set) var message: String?
    private(set) var ownerWindowNumber: Int?
    @ObservationIgnored private var windows: [ObjectIdentifier: WeakAssistantWindow] = [:]
    private var dismissedDuringRun = false

    var showsCharacter: Bool {
        get { UserDefaults.standard.object(forKey: "companion.assistant.character") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "companion.assistant.character"); appearanceRevision += 1 }
    }
    var quietMotion: Bool {
        get { UserDefaults.standard.bool(forKey: "companion.assistant.quietMotion") }
        set { UserDefaults.standard.set(newValue, forKey: "companion.assistant.quietMotion"); appearanceRevision += 1 }
    }
    var prefersPane: Bool {
        get { UserDefaults.standard.bool(forKey: "companion.assistant.opensAsPane") }
        set { UserDefaults.standard.set(newValue, forKey: "companion.assistant.opensAsPane"); appearanceRevision += 1 }
    }
    var showsEntrance: Bool {
        get { UserDefaults.standard.object(forKey: "companion.assistant.entrance") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "companion.assistant.entrance"); appearanceRevision += 1 }
    }
    private(set) var appearanceRevision = 0

    func register(window: NSWindow?, panes: PaneManager) {
        windows[ObjectIdentifier(panes)] = WeakAssistantWindow(window)
    }

    func isOwner(windowNumber: Int?) -> Bool {
        ownerWindowNumber == nil || ownerWindowNumber == windowNumber
    }

    func focusOwner() {
        NSApp?.windows.first { $0.windowNumber == ownerWindowNumber }?.makeKeyAndOrderFront(nil)
    }

    func openCompact(panes: PaneManager? = nil, store: CosmoInlineAssistantStore = .shared) {
        if let panes, let window = windows[ObjectIdentifier(panes)]?.value {
            // Accessibility activation can press a background window's button
            // directly. The explicit gesture still owns the destination.
            window.makeKeyAndOrderFront(nil)
            ownerWindowNumber = window.windowNumber
        } else {
            ownerWindowNumber = NSApp?.keyWindow?.windowNumber ?? ownerWindowNumber
        }
        dismissedDuringRun = false
        message = nil
        // Capture the source before the chat takes keyboard focus.
        if host == .resting { store.activateSessionIfIdle(surfaceID: CosmoEditableSurfaceRegistry.shared.activeSurface?.surfaceID) }
        store.retainsPresentedSession = true
        store.composerStorage.wantsFocus = true
        host = .compact
    }

    @discardableResult
    func openPane(using panes: PaneManager, store: CosmoInlineAssistantStore = .shared, userInitiated: Bool = false) -> Bool {
        if let window = windows[ObjectIdentifier(panes)]?.value, !window.isKeyWindow {
            guard userInitiated else { return false }
            window.makeKeyAndOrderFront(nil)
            ownerWindowNumber = window.windowNumber
        }
        guard !store.composerStorage.hasMarkedText else {
            message = "Finish composing this word, then open the pane."
            return false
        }
        ownerWindowNumber = NSApp?.keyWindow?.windowNumber ?? ownerWindowNumber
        guard panes.openOrActivateInlineAssistant() else {
            openCompact(store: store)
            message = "All six panes are open. Close one to make room, or keep chatting here."
            return false
        }
        store.retainsPresentedSession = true
        store.composerStorage.wantsFocus = true
        store.savePresentationDraft()
        dismissedDuringRun = false
        message = nil
        host = .pane
        return true
    }

    func returnToCompact(closePane: () -> Void, store: CosmoInlineAssistantStore = .shared) {
        guard !store.composerStorage.hasMarkedText else {
            message = "Finish composing this word, then return to the corner."
            return
        }
        store.savePresentationDraft()
        openCompact(store: store)
        closePane()
    }

    func dismiss(store: CosmoInlineAssistantStore = .shared) {
        store.savePresentationDraft()
        dismissedDuringRun = store.isProcessing
        store.retainsPresentedSession = false
        host = .resting
        message = nil
    }

    func reconcilePane(isOpen: Bool, windowNumber: Int? = nil, store: CosmoInlineAssistantStore = .shared) {
        if ownerWindowNumber == nil, let windowNumber {
            guard NSApp?.keyWindow?.windowNumber == windowNumber else { return }
            ownerWindowNumber = windowNumber
        }
        guard isOwner(windowNumber: windowNumber) else { return }
        if isOpen, host != .compact { host = .pane; store.retainsPresentedSession = true }
        if !isOpen, host == .pane { dismiss(store: store) }
    }

    func receive(_ intent: AssistantPresentationIntent, panes: PaneManager, store: CosmoInlineAssistantStore = .shared) {
        if let window = windows[ObjectIdentifier(panes)]?.value, !window.isKeyWindow { return }
        if intent == .pane { openPane(using: panes, store: store); return }
        guard !dismissedDuringRun else { return }
        if host == .resting { openCompact(store: store) }
    }

    func runBegan() { dismissedDuringRun = false }
    func clearMessage() { message = nil }
}

private final class WeakAssistantWindow {
    weak var value: NSWindow?
    init(_ value: NSWindow?) { self.value = value }
}

struct AssistantWindowReader: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> WindowView { let view = WindowView(); view.onWindow = onWindow; return view }
    func updateNSView(_ view: WindowView, context: Context) { view.onWindow = onWindow }
    final class WindowView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let current = window
            DispatchQueue.main.async { [weak self] in self?.onWindow?(current) }
        }
    }
}

/// The editor stays alive across SwiftUI hosts, preserving the native undo stack
/// and attachment storage. Only one visible composer may own it at a time.
@MainActor final class MentionComposerViewStorage {
    var scrollView: NSScrollView?
    var wantsFocus = false
    var hasMarkedText: Bool { (scrollView?.documentView as? NSTextView)?.hasMarkedText() == true }
    func reset() {
        (scrollView?.documentView as? NSTextView)?.undoManager?.removeAllActions()
    }
}

@Observable @MainActor final class AssistantConversationViewport {
    var followsLatest = true
    var firstVisibleRunID: UUID?
}

enum CompanionAssistantPlacement {
    static func compactSize(in size: CGSize) -> CGSize {
        CGSize(width: max(0, min(420, size.width - 32)), height: max(0, min(620, size.height - 80)))
    }
}
