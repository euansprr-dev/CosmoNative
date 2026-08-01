import SwiftUI
import os

enum CanvasPerformanceInstrumentation {
    static let logger = Logger(subsystem: "com.cosmo.os", category: "CanvasPerformance")
    static let signposter = OSSignposter(subsystem: "com.cosmo.os", category: "CanvasPerformance")
}

#if DEBUG

// MARK: - Frame Time Stats

/// Rolling main-thread frame health, published at ~4Hz so the HUD itself
/// never becomes a per-frame invalidation source.
@MainActor
@Observable
final class CanvasFrameStats {
    private(set) var fps: Double = 0
    /// Worst gap between delivered frames inside the last publish window, ms.
    private(set) var worstFrameMs: Double = 0

    func publish(fps: Double, worstFrameMs: Double) {
        self.fps = fps
        self.worstFrameMs = worstFrameMs
    }
}

/// Hosts a CADisplayLink and measures the gaps between delivered callbacks.
/// When the main thread stalls, the link fires late — the gap IS the frame
/// time the user experienced.
private final class CanvasFrameMeterNSView: NSView {
    var stats: CanvasFrameStats?

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frameCount = 0
    private var worstDelta: CFTimeInterval = 0
    private let publishInterval: CFTimeInterval = 0.25

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let newLink = displayLink(target: self, selector: #selector(tick(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
        lastTimestamp = 0
        windowStart = 0
        frameCount = 0
        worstDelta = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else {
            windowStart = now
            return
        }

        let delta = now - lastTimestamp
        frameCount += 1
        worstDelta = max(worstDelta, delta)

        let elapsed = now - windowStart
        guard elapsed >= publishInterval else { return }
        let fps = Double(frameCount) / elapsed
        let worstMs = worstDelta * 1000
        stats?.publish(fps: fps, worstFrameMs: worstMs)
        windowStart = now
        frameCount = 0
        worstDelta = 0
    }
}

private struct CanvasFrameMeter: NSViewRepresentable {
    let stats: CanvasFrameStats

    func makeNSView(context: Context) -> CanvasFrameMeterNSView {
        let view = CanvasFrameMeterNSView(frame: .zero)
        view.stats = stats
        return view
    }

    func updateNSView(_ nsView: CanvasFrameMeterNSView, context: Context) {
        nsView.stats = stats
    }
}

// MARK: - Overlay

struct CanvasPerformanceOverlay: View {
    let transform: CanvasViewportTransform
    let blockCount: Int
    let visibleBlockCount: Int
    let activeDragLabel: String?
    var pipeline: CanvasRenderPipeline?

    @State private var frameStats = CanvasFrameStats()

    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["COSMO_CANVAS_PERF_OVERLAY"] == "1"
    }

    var body: some View {
        if isEnabled {
            VStack(alignment: .leading, spacing: 4) {
                Text("Canvas Perf")
                    .fontWeight(.semibold)
                Text(String(format: "%.0f fps · worst %.1f ms", frameStats.fps, frameStats.worstFrameMs))
                    .foregroundStyle(frameStats.worstFrameMs > 17 ? DS.red : DS.textSecondary)
                Text("scale \(String(format: "%.2f", transform.effectiveScale))")
                Text("blocks \(visibleBlockCount)/\(blockCount)")
                if let pipeline {
                    Text("body evals \(pipeline.debugSnapshotRequestCount) · swaps \(pipeline.debugViewportSnapshotBuildCount)")
                    Text("mounts +\(pipeline.debugTotalMounts) −\(pipeline.debugTotalUnmounts) (last +\(pipeline.debugLastSwapMounts) −\(pipeline.debugLastSwapUnmounts))")
                }
                Text("drag \(activeDragLabel ?? "-")")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(DS.textSecondary)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.border, lineWidth: 1)
            )
            .padding(16)
            .background(
                CanvasFrameMeter(stats: frameStats)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            )
        }
    }
}
#else
struct CanvasPerformanceOverlay: View {
    let transform: CanvasViewportTransform
    let blockCount: Int
    let visibleBlockCount: Int
    let activeDragLabel: String?
    var pipeline: CanvasRenderPipeline?

    var body: some View {
        EmptyView()
    }
}
#endif
