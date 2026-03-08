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
    @Published var hoverProgress: CGFloat = 0  // 0→1 over switchDelay
    @Published var hasThinkspaceSwitched = false
    @Published var targetThinkspaceId: String?

    // Floating preview
    @Published var floatingPosition: CGPoint = .zero

    // Sidebar row frames (window coordinates) — set via preference key
    var thinkspaceRowFrames: [String: CGRect] = [:]

    // Sidebar width for hit testing
    var sidebarWidth: CGFloat = UnifiedSidebarMetrics.defaultExpandedWidth

    // Timing
    private let switchDelay: TimeInterval = 0.8
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
        hoverProgress = 0
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
        hoverProgress = 0
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
            hoverProgress = 0
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
                let progress = min(elapsed / self.switchDelay, 1.0)
                self.hoverProgress = CGFloat(progress)

                if progress >= 1.0 {
                    self.performThinkspaceSwitch()
                }
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        blinkStartTime = nil
        hoverProgress = 0
    }

    // MARK: - Thinkspace Switch

    private func performThinkspaceSwitch() {
        cancelHoverTimer()
        guard let targetId = hoveredThinkspaceId else { return }

        hasThinkspaceSwitched = true
        targetThinkspaceId = targetId
        hoverProgress = 1.0

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
        hoverProgress = 0
        hasThinkspaceSwitched = false
        targetThinkspaceId = nil
        floatingPosition = .zero
        cancelHoverTimer()
        stopEventMonitors()
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
                    if windowPoint.x > self.sidebarWidth {
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

    deinit {
        hoverTimer?.invalidate()
        if let monitor = mouseDragMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
    }
}

// MARK: - Notification Name

extension CosmoNotification.Canvas {
    static let crossThinkspaceDropBlock = Notification.Name("com.cosmo.canvas.crossThinkspaceDropBlock")
}

// MARK: - Floating Block Preview

struct CrossThinkspaceDragPreview: View {
    let block: CanvasBlock

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(block.entityType.color.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: block.entityType.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(block.entityType.color)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Text(block.entityType.rawValue.capitalized)
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DS.border, lineWidth: 0.5)
        )
    }
}
