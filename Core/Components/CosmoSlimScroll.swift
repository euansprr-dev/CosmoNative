// Core/Components/CosmoSlimScroll.swift
// The app's slim scrollbar, extracted from Content focus mode's margin
// rails: suppresses the native scroller at the NSScrollView level — so
// macOS's "Show scroll bars: Always" setting can't force a fat legacy bar
// through `.scrollIndicators(.hidden)` — and replaces it with the same
// 2.5pt capsule the manuscript uses, fading in only when content overflows.
// (ContentFocusModeView keeps a private copy for now — dedupe later.)
// July 2026

import SwiftUI
import AppKit

// MARK: - Metrics

struct CosmoSlimScrollMetrics: Equatable {
    var progress: CGFloat = 0
    var thumbFraction: CGFloat = 1
    var isScrollable: Bool = false
}

// MARK: - Wrapper

/// A vertical ScrollView wearing the app's slim capsule scrollbar.
struct CosmoSlimScroll<Content: View>: View {
    var tint: Color = DS.textMuted
    @ViewBuilder var content: () -> Content

    @State private var metrics = CosmoSlimScrollMetrics()

    var body: some View {
        ScrollView(.vertical) {
            content()
                .background(
                    CosmoSlimScrollIntrospector { newMetrics in
                        metrics = newMetrics
                    }
                )
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .trailing) {
            CosmoSlimScrollbar(metrics: metrics, tint: tint)
                .padding(.trailing, DS.space2)
                .padding(.vertical, DS.space8)
        }
    }
}

// MARK: - The Capsule

private struct CosmoSlimScrollbar: View {
    let metrics: CosmoSlimScrollMetrics
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = proxy.size.height
            let thumbHeight = max(32, trackHeight * metrics.thumbFraction)
            let travel = max(0, trackHeight - thumbHeight)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(tint.opacity(0.10))
                    .frame(width: 2)

                Capsule()
                    .fill(tint.opacity(0.62))
                    .frame(width: 2.5, height: thumbHeight)
                    .offset(y: travel * metrics.progress)
            }
            .frame(width: 8, height: trackHeight)
            .opacity(metrics.isScrollable ? 1 : 0)
            .animation(ProMotionSprings.gentle, value: metrics)
            .allowsHitTesting(false)
        }
        .frame(width: 8)
    }
}

// MARK: - Introspector

private struct CosmoSlimScrollIntrospector: NSViewRepresentable {
    var onMetricsChange: (CosmoSlimScrollMetrics) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                context.coordinator.attach(to: scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMetricsChange = onMetricsChange
        DispatchQueue.main.async {
            if let scrollView = nsView.enclosingScrollView {
                context.coordinator.attach(to: scrollView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMetricsChange: onMetricsChange)
    }

    final class Coordinator {
        var onMetricsChange: (CosmoSlimScrollMetrics) -> Void
        private weak var scrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []
        private var lastMetrics = CosmoSlimScrollMetrics()

        init(onMetricsChange: @escaping (CosmoSlimScrollMetrics) -> Void) {
            self.onMetricsChange = onMetricsChange
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to scrollView: NSScrollView) {
            if self.scrollView === scrollView {
                configure(scrollView)
                publishMetrics(for: scrollView)
                return
            }

            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            self.scrollView = scrollView
            configure(scrollView)

            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            scrollView.postsFrameChangedNotifications = true

            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let scrollView else { return }
                    self?.publishMetrics(for: scrollView)
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let scrollView else { return }
                    self?.publishMetrics(for: scrollView)
                }
            )

            publishMetrics(for: scrollView)
        }

        private func configure(_ scrollView: NSScrollView) {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.drawsBackground = false
        }

        private func publishMetrics(for scrollView: NSScrollView) {
            let visibleHeight = max(scrollView.documentVisibleRect.height, 1)
            let documentHeight = max(scrollView.documentView?.bounds.height ?? visibleHeight, visibleHeight)
            let scrollableDistance = max(documentHeight - visibleHeight, 0)
            let rawProgress = scrollableDistance > 0 ? scrollView.documentVisibleRect.minY / scrollableDistance : 0
            let metrics = CosmoSlimScrollMetrics(
                progress: min(max(rawProgress, 0), 1),
                thumbFraction: min(max(visibleHeight / documentHeight, 0.08), 1),
                isScrollable: scrollableDistance > 1
            )
            guard metrics != lastMetrics else { return }
            lastMetrics = metrics
            onMetricsChange(metrics)
        }
    }
}
