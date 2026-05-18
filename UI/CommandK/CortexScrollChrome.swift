// CosmoOS/UI/CommandK/CortexScrollChrome.swift
// Thin overlay scroll chrome for the Command-K master/detail panes.

import AppKit
import SwiftUI

struct CortexScrollMetrics: Equatable {
    var progress: CGFloat = 0
    var thumbFraction: CGFloat = 1
    var isScrollable: Bool = false
}

struct CortexThinScrollbar: View {
    let metrics: CortexScrollMetrics

    private static let trackWidth: CGFloat = 2
    private static let thumbWidth: CGFloat = 2.5
    private static let touchWidth: CGFloat = 8
    private static let minimumThumbHeight: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = proxy.size.height
            let thumbHeight = max(Self.minimumThumbHeight, trackHeight * metrics.thumbFraction)
            let travel = max(0, trackHeight - thumbHeight)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(DS.inkFaded.opacity(0.10))
                    .frame(width: Self.trackWidth)

                Capsule()
                    .fill(DS.inkFaded.opacity(0.62))
                    .frame(width: Self.thumbWidth, height: thumbHeight)
                    .offset(y: travel * metrics.progress)
            }
            .frame(width: Self.touchWidth, height: trackHeight)
            .opacity(metrics.isScrollable ? 1 : 0)
            .animation(ProMotionSprings.gentle, value: metrics)
            .allowsHitTesting(false)
        }
        .frame(width: Self.touchWidth)
    }
}

struct CortexScrollViewIntrospector: NSViewRepresentable {
    var onMetricsChange: (CortexScrollMetrics) -> Void

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
        var onMetricsChange: (CortexScrollMetrics) -> Void
        private weak var scrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []
        private var lastMetrics = CortexScrollMetrics()

        init(onMetricsChange: @escaping (CortexScrollMetrics) -> Void) {
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
            let metrics = CortexScrollMetrics(
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

extension View {
    func cortexThinScrollbar(metrics: CortexScrollMetrics) -> some View {
        overlay(alignment: .trailing) {
            CortexThinScrollbar(metrics: metrics)
                .padding(.trailing, DS.space4)
                .padding(.vertical, DS.space8)
        }
    }
}
