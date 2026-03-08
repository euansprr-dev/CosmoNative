import SwiftUI
import os

enum CanvasPerformanceInstrumentation {
    static let logger = Logger(subsystem: "com.cosmo.os", category: "CanvasPerformance")
    static let signposter = OSSignposter(subsystem: "com.cosmo.os", category: "CanvasPerformance")
}

#if DEBUG
struct CanvasPerformanceOverlay: View {
    let transform: CanvasViewportTransform
    let blockCount: Int
    let visibleBlockCount: Int
    let activeDragLabel: String?

    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["COSMO_CANVAS_PERF_OVERLAY"] == "1"
    }

    var body: some View {
        if isEnabled {
            VStack(alignment: .leading, spacing: 4) {
                Text("Canvas Perf")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("scale \(String(format: "%.2f", transform.effectiveScale))")
                Text("blocks \(visibleBlockCount)/\(blockCount)")
                Text("drag \(activeDragLabel ?? "-")")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(DS.textSecondary)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.border, lineWidth: 1)
            )
            .padding(16)
        }
    }
}
#else
struct CanvasPerformanceOverlay: View {
    let transform: CanvasViewportTransform
    let blockCount: Int
    let visibleBlockCount: Int
    let activeDragLabel: String?

    var body: some View {
        EmptyView()
    }
}
#endif
