// CosmoOS/Navigation/PaneEnvironment.swift
// Environment keys for pane context — used by focus mode views to guard singleton writes

import SwiftUI

// MARK: - Is Pane Context

/// Whether the view is rendered inside a split pane (vs. the main content area).
/// When true, focus mode views should guard CosmoWindowViewModel and NSEvent monitor registration.
private struct IsPaneContextKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Is Pane Active

/// Whether this pane is the currently active (most recently tapped) pane.
/// Only the active pane should push its context to CosmoWindowViewModel and VoiceContextStore.
private struct IsPaneActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Is Pane Context Owner

/// Whether this pane's entity currently owns global context even if another pane
/// (such as a collaborator surface) is focused.
private struct IsPaneContextOwnerKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Is Pane Expanded

/// Whether this pane is currently EXPANDED (focused or pinned) rather than
/// collapsed into the tab rail. Collapsed panes stay mounted by design (state
/// survives the switch), but continuous work — media playback, per-token
/// transcript scrolls, 1Hz timelines — must quiet down while off-slot.
/// Defaults TRUE: outside the deck (main destinations, peek, atom windows)
/// a surface is always "expanded".
private struct IsPaneExpandedKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

// MARK: - Is Pane Width Streaming

/// True while a continuous width stream (main-split divider drag or window
/// live resize) is feeding the deck. Canvas panes consult it to bucket their
/// viewport-size snapshot instead of re-culling once per pointer frame.
private struct IsPaneWidthStreamingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Is Peek Context

/// Whether the view is rendered inside the Peek overlay. The peek header owns
/// the close affordance, so focus modes suppress their own close buttons.
private struct IsPeekContextKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Canvas Escape Coordinator

/// Lets deep canvas overlays (place capture, flow pickers, portal picker)
/// claim Escape before MainView's global key monitor falls through to
/// pane-closing or thinkspace-exit behavior.
@MainActor
final class CanvasEscapeCoordinator {

    static let shared = CanvasEscapeCoordinator()

    private var handlers: [(id: String, handle: () -> Bool)] = []

    /// Register a dismiss handler. Returns true from the handler if it
    /// consumed the Escape press.
    func register(id: String, handler: @escaping () -> Bool) {
        unregister(id: id)
        handlers.append((id, handler))
    }

    func unregister(id: String) {
        handlers.removeAll { $0.id == id }
    }

    /// Ask handlers (most recent first) to dismiss their top overlay.
    func dismissTopOverlay() -> Bool {
        for entry in handlers.reversed() where entry.handle() {
            return true
        }
        return false
    }
}

extension EnvironmentValues {

    /// True when the view is rendered inside a split pane.
    var isPaneContext: Bool {
        get { self[IsPaneContextKey.self] }
        set { self[IsPaneContextKey.self] = newValue }
    }

    /// True when this is the currently active pane (user last interacted with).
    var isPaneActive: Bool {
        get { self[IsPaneActiveKey.self] }
        set { self[IsPaneActiveKey.self] = newValue }
    }

    /// True when this pane's entity is the source of global context updates.
    var isPaneContextOwner: Bool {
        get { self[IsPaneContextOwnerKey.self] }
        set { self[IsPaneContextOwnerKey.self] = newValue }
    }

    /// True when this pane is expanded (focused or pinned) — false while
    /// collapsed into the tab rail. Defaults true outside the deck.
    var isPaneExpanded: Bool {
        get { self[IsPaneExpandedKey.self] }
        set { self[IsPaneExpandedKey.self] = newValue }
    }

    /// True while the deck is inside a continuous width stream.
    var isPaneWidthStreaming: Bool {
        get { self[IsPaneWidthStreamingKey.self] }
        set { self[IsPaneWidthStreamingKey.self] = newValue }
    }

    /// True when the view is rendered inside the Peek overlay.
    var isPeekContext: Bool {
        get { self[IsPeekContextKey.self] }
        set { self[IsPeekContextKey.self] = newValue }
    }
}
