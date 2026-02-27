// CosmoOS/Canvas/DistillationLayerSelector.swift
// Maps canvas zoom level to the appropriate distillation layer
// February 2026 - Thinking Lab WP3

import SwiftUI

struct DistillationLayerSelector {
    static func layer(for scale: CGFloat) -> DistillationLayer {
        if scale > 0.6 { return .full }
        if scale > 0.35 { return .summary }
        if scale > 0.2 { return .essence }
        return .glyph
    }
}

// MARK: - Environment Key

private struct DistillationLayerKey: EnvironmentKey {
    static let defaultValue: DistillationLayer = .full
}

extension EnvironmentValues {
    var distillationLayer: DistillationLayer {
        get { self[DistillationLayerKey.self] }
        set { self[DistillationLayerKey.self] = newValue }
    }
}
