// CosmoOS/Core/Components/CosmoLiveScrollMonitor.swift
// AppKit knows when a scroll gesture is actually in flight; SwiftUI does not.
// Hover work that is trivial when the *pointer* moves becomes a per-frame storm
// when the *content* moves underneath a still pointer — every row the content
// drags past reports a hover change, and each one that animates spawns a spring
// that keeps the view graph dirty long enough to collide with the next.
// July 2026

import AppKit
import SwiftUI

/// Tracks whether any `NSScrollView` in the app is mid live-scroll.
///
/// Deliberately NOT `@Observable`. Callers read this from inside event handlers
/// (`onHover`), never from a `body`. Making it observable would invalidate every
/// view that reads it twice per scroll gesture — reintroducing, in a new shape,
/// exactly the churn it exists to prevent.
@MainActor
final class CosmoLiveScrollMonitor {
    static let shared = CosmoLiveScrollMonitor()

    /// A live scroll that never reported its end (window torn down mid-gesture,
    /// a scroll view deallocated under momentum) must not disable hover
    /// animation forever, so the flag also expires on its own.
    private static let staleAfter: TimeInterval = 5

    private var isScrolling = false
    private var startedAt = Date.distantPast

    var isLiveScrolling: Bool {
        isScrolling && Date().timeIntervalSince(startedAt) < Self.staleAfter
    }

    private init() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                CosmoLiveScrollMonitor.shared.isScrolling = true
                CosmoLiveScrollMonitor.shared.startedAt = Date()
            }
        }

        center.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                CosmoLiveScrollMonitor.shared.isScrolling = false
            }
        }
    }
}

/// Applies a hover state change with its usual animation — unless a scroll is
/// live, in which case it lands immediately instead.
///
/// The state still updates either way. Nothing is dropped, so nothing is left
/// stale once the scroll stops; only the 150ms ease is skipped. AppKit's own
/// controls settle hover the same way mid-scroll, and at scrolling speed the
/// ease is not perceivable — but a spring per row per scroll frame is very
/// much perceivable, because it keeps the view graph dirty long enough for the
/// next one to pile onto it.
@MainActor
func withCosmoHoverAnimation(
    _ animation: Animation? = ProMotionSprings.hover,
    _ body: () -> Void
) {
    if CosmoLiveScrollMonitor.shared.isLiveScrolling {
        body()
    } else {
        withAnimation(animation, body)
    }
}

extension View {
    /// Hover that keeps its state exactly correct while the content is moving,
    /// without paying for a spring per row per scroll frame.
    func cosmoHover(
        _ animation: Animation? = ProMotionSprings.hover,
        perform apply: @escaping (Bool) -> Void
    ) -> some View {
        onHover { hovering in
            withCosmoHoverAnimation(animation) { apply(hovering) }
        }
    }
}
