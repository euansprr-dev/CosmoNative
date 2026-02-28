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
}
