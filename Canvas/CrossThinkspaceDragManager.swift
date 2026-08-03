// CosmoOS/Canvas/CrossThinkspaceDragManager.swift
// Coordinates dragging blocks between thinkspaces via the sidebar
// macOS-style spring-loaded folder behavior

import SwiftUI
import AppKit

// MARK: - Preference Key for Thinkspace Row Frames

struct ThinkspaceRowFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Spring-Load Pulse Host

/// The 60Hz spring-load pulse behind @Observable so per-tick writes invalidate
/// ONLY the row chrome that reads it, never the whole sidebar section body
/// (CortexScrollMetricsStore isolation pattern). Keeping it @Published on the
/// ObservableObject manager re-evaluated every observer per timer tick.
@MainActor
@Observable
final class SpringLoadPulseHost {
    var pulse: CGFloat = 0
}

// MARK: - Cross-Thinkspace Drag Manager

@MainActor
class CrossThinkspaceDragManager: ObservableObject {
    // Drag state
    @Published var isDragging = false
    @Published var isOverSidebar = false
    @Published var draggedBlock: CanvasBlock?
    @Published var sourceThinkspaceId: String?

    // Sidebar hover state
    @Published var hoveredThinkspaceId: String?
    let springLoadPulseHost = SpringLoadPulseHost()
    @Published var hasThinkspaceSwitched = false
    @Published var targetThinkspaceId: String?

    // Floating preview
    @Published var floatingPosition: CGPoint = .zero

    // Sidebar row frames (window coordinates) — set via preference key
    var thinkspaceRowFrames: [String: CGRect] = [:]

    // Sidebar width for hit testing — published so page-like canvas modes
    // (the thinkspace Library) can yield to the floating sidebar reactively.
    @Published var sidebarWidth: CGFloat = UnifiedSidebarMetrics.defaultExpandedWidth

    /// Total sidebar footprint including floating margins
    var sidebarTotalWidth: CGFloat {
        guard sidebarWidth > 0 else { return 0 }
        return sidebarWidth + UnifiedSidebarMetrics.floatingMargin * 2
    }

    // Timing
    private let hoverDelay: TimeInterval = 0.30
    private let blinkDuration: TimeInterval = 0.27
    private let blinkCount: Double = 3
    private var hoverTimer: Timer?
    private var blinkStartTime: Date?

    // NSEvent monitors for post-switch phase
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?

    // Callback for thinkspace switch (set by MainView)
    var onThinkspaceSwitch: ((String) -> Void)?
    // Callback for completing a drop (set by MainView)
    var onDropComplete: ((CanvasBlock, String, CGPoint) -> Void)?

    // MARK: - Begin Drag

    func beginDrag(block: CanvasBlock, sourceThinkspaceId: String?) {
        guard !isDragging else { return }
        isDragging = true
        draggedBlock = block
        self.sourceThinkspaceId = sourceThinkspaceId
        hasThinkspaceSwitched = false
        targetThinkspaceId = nil
        hoveredThinkspaceId = nil
        springLoadPulseHost.pulse = 0
    }

    // MARK: - Enter/Exit Sidebar

    func enterSidebar() {
        guard isDragging, !isOverSidebar else { return }
        isOverSidebar = true
        startEventMonitors()
    }

    func exitSidebar() {
        guard isOverSidebar else { return }
        isOverSidebar = false
        cancelHoverTimer()
        hoveredThinkspaceId = nil
        springLoadPulseHost.pulse = 0
        stopEventMonitors()
    }

    // MARK: - Update Cursor Position

    func updateCursorPosition(_ windowPoint: CGPoint) {
        floatingPosition = windowPoint

        guard isOverSidebar else { return }

        // Hit-test against thinkspace row frames
        var foundId: String?
        for (id, frame) in thinkspaceRowFrames {
            // Don't allow drop on source thinkspace
            if id == sourceThinkspaceId { continue }
            if frame.contains(windowPoint) {
                foundId = id
                break
            }
        }

        if foundId != hoveredThinkspaceId {
            hoveredThinkspaceId = foundId
            springLoadPulseHost.pulse = 0
            cancelHoverTimer()

            if foundId != nil {
                startHoverTimer()
            }
        }
    }

    // MARK: - Hover Timer (Spring-Loaded Switch)

    private func startHoverTimer() {
        blinkStartTime = Date()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.blinkStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                let totalDuration = self.hoverDelay + self.blinkDuration

                if elapsed < self.hoverDelay {
                    self.springLoadPulseHost.pulse = 0
                } else {
                    let blinkElapsed = min(elapsed - self.hoverDelay, self.blinkDuration)
                    let blinkPhase = (blinkElapsed / self.blinkDuration) * self.blinkCount
                    self.springLoadPulseHost.pulse = CGFloat(abs(sin(blinkPhase * .pi)))
                }

                if elapsed >= totalDuration {
                    self.springLoadPulseHost.pulse = 0
                    self.performThinkspaceSwitch()
                }
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        blinkStartTime = nil
        springLoadPulseHost.pulse = 0
    }

    // MARK: - Thinkspace Switch

    private func performThinkspaceSwitch() {
        cancelHoverTimer()
        guard let targetId = hoveredThinkspaceId else { return }

        hasThinkspaceSwitched = true
        targetThinkspaceId = targetId
        springLoadPulseHost.pulse = 0

        // Notify MainView to switch destination
        onThinkspaceSwitch?(targetId)
    }

    // MARK: - Complete Drop

    /// Called when the drag ends over the sidebar (quick drop or post-switch)
    func completeDrop(screenPosition: CGPoint) {
        guard let block = draggedBlock else {
            cancel()
            return
        }

        if let targetId = hoveredThinkspaceId ?? targetThinkspaceId {
            // Drop to the target thinkspace
            let dropPosition: CGPoint
            if hasThinkspaceSwitched {
                // Post-switch: use screen position (MainView's onDropComplete handles conversion)
                dropPosition = screenPosition
            } else {
                // Quick drop: center of canvas
                dropPosition = .zero
            }

            // onDropComplete handles both DB update and navigation
            onDropComplete?(block, targetId, dropPosition)
        }

        cleanup()
    }

    // MARK: - Cancel

    func cancel() {
        cleanup()
    }

    private func cleanup() {
        isDragging = false
        isOverSidebar = false
        draggedBlock = nil
        sourceThinkspaceId = nil
        hoveredThinkspaceId = nil
        springLoadPulseHost.pulse = 0
        hasThinkspaceSwitched = false
        targetThinkspaceId = nil
        floatingPosition = .zero
        cancelHoverTimer()
        stopEventMonitors()
    }

    /// The row that would spring-load if the hover dwell completes. Discrete —
    /// it flips only when the hovered row changes, so section bodies can read
    /// it without subscribing to the 60Hz pulse (that lives on the host).
    func isSpringLoadCandidate(_ thinkspaceId: String) -> Bool {
        isOverSidebar &&
        !hasThinkspaceSwitched &&
        hoveredThinkspaceId == thinkspaceId
    }

    // MARK: - NSEvent Monitors

    private func startEventMonitors() {
        guard mouseDragMonitor == nil else { return }

        mouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            Task { @MainActor in
                guard let self = self, self.isOverSidebar || self.hasThinkspaceSwitched else { return }
                guard let window = event.window else { return }

                let windowPoint = event.locationInWindow
                // Flip Y for SwiftUI coordinate system (origin at top-left of content area)
                let contentHeight = window.contentView?.bounds.height ?? window.frame.height
                let flippedPoint = CGPoint(
                    x: windowPoint.x,
                    y: contentHeight - windowPoint.y
                )
                self.floatingPosition = flippedPoint

                if self.hasThinkspaceSwitched {
                    // Post-switch: still tracking cursor for final placement
                    // Check if cursor re-entered canvas area
                    if windowPoint.x > self.sidebarTotalWidth {
                        self.isOverSidebar = false
                    }
                } else {
                    self.updateCursorPosition(flippedPoint)
                }
            }
            return event
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in
                guard let self = self, self.isDragging else { return }
                guard let window = event.window else { return }

                let windowPoint = event.locationInWindow
                let contentHeight = window.contentView?.bounds.height ?? window.frame.height
                let flippedPoint = CGPoint(
                    x: windowPoint.x,
                    y: contentHeight - windowPoint.y
                )

                if self.hasThinkspaceSwitched || self.isOverSidebar {
                    self.completeDrop(screenPosition: flippedPoint)
                }
            }
            return event
        }
    }

    private func stopEventMonitors() {
        if let monitor = mouseDragMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDragMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }
}

// MARK: - Notification Name

extension CosmoNotification.Canvas {
    static let crossThinkspaceDropBlock = Notification.Name("com.cosmo.canvas.crossThinkspaceDropBlock")
}

// MARK: - Floating Block Preview

struct CrossThinkspaceDragPreview: View {
    let block: CanvasBlock

    private var accent: Color { block.entityType.color }

    private var previewSize: CGSize {
        let sourceSize = CGSize(
            width: max(block.size.width, 220),
            height: max(block.size.height, 108)
        )
        let maxWidth: CGFloat = 176
        let maxHeight: CGFloat = 126
        let scale = min(maxWidth / sourceSize.width, maxHeight / sourceSize.height, 0.62)
        return CGSize(
            width: max(128, sourceSize.width * scale),
            height: max(88, sourceSize.height * scale)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(accent.opacity(0.85))
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: block.entityType.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(accent)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.entityType.rawValue.capitalized)
                            .dsSmallCapsLabel()

                        Text(block.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.text)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)
                }

                previewBody

                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(width: previewSize.width, height: previewSize.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var previewBody: some View {
        switch block.entityType {
        case .task:
            VStack(alignment: .leading, spacing: 8) {
                Text((block.subtitle?.isEmpty == false ? block.subtitle : nil) ?? "0/1 today")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)

                miniBarRow(
                    color: accent,
                    values: [0.60, 0.38, 0.43, 0.34, 0.49, 0.28]
                )

                miniPill(
                    label: block.metadata["status"]?.capitalized ?? "Not tracked",
                    tint: accent
                )
            }
        case .image:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.18),
                            accent.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    Text((block.subtitle?.isEmpty == false ? block.subtitle : nil) ?? "Image")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .lineLimit(1)
                        .padding(8)
                }
        default:
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle = block.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .lineLimit(block.entityType == .research ? 2 : 3)
                } else {
                    miniPlaceholderLines
                }

                HStack(spacing: 6) {
                    miniPill(label: block.entityType.rawValue.capitalized, tint: accent)

                    if let status = block.metadata["status"], !status.isEmpty {
                        miniPill(label: status.capitalized, tint: DS.textSecondary, isSecondary: true)
                    } else if let type = block.metadata["type"], !type.isEmpty {
                        miniPill(label: type.capitalized, tint: DS.textSecondary, isSecondary: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var miniPlaceholderLines: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<placeholderLineCount, id: \.self) { index in
                Capsule()
                    .fill(index == placeholderLineCount - 1 ? DS.borderSubtle.opacity(0.8) : DS.borderSubtle)
                    .frame(width: placeholderLineWidth(index: index), height: 5)
            }
        }
    }

    private var placeholderLineCount: Int {
        switch block.entityType {
        case .task:
            return 2
        case .research, .content, .note, .connection:
            return 3
        default:
            return 2
        }
    }

    private func placeholderLineWidth(index: Int) -> CGFloat {
        let widths = [0.92, 0.76, 0.58]
        let normalized = widths[min(index, widths.count - 1)]
        return max(54, previewSize.width * normalized - 20)
    }

    private func miniBarRow(color: Color, values: [CGFloat]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { value in
                Capsule()
                    .fill(value.element > 0.5 ? color.opacity(0.7) : DS.borderSubtle)
                    .frame(
                        width: max(16, (previewSize.width - 42) * value.element / 3.0),
                        height: 5
                    )
            }
        }
    }

    private func miniPill(label: String, tint: Color, isSecondary: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DS.bg, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(isSecondary ? 0.12 : 0.18), lineWidth: 1)
            )
    }
}
