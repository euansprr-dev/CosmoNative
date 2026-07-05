// CosmoOS/UI/CosmoWindow/CosmoKeyablePanel.swift
// Shared floating-panel primitive: an NSPanel that can become key (so text
// fields inside it accept input) with edge-drag resizing. Used by the atom
// window panel controller. Extracted from the deleted CosmoWindowPanelController
// (the floating Cosmo chat window was removed July 2026 — One Cosmo).

import SwiftUI
import AppKit

// MARK: - Keyable Panel (allows text input when focused)

class CosmoKeyablePanel: NSPanel {
    private var visiblePanelResizeStartFrame: NSRect?
    private var visiblePanelResizeStartMouseLocation: NSPoint?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resizeFromVisiblePanelEdge(_ edge: CosmoWindowResizeEdge) {
        let startFrame = visiblePanelResizeStartFrame ?? frame
        let startMouseLocation = visiblePanelResizeStartMouseLocation ?? NSEvent.mouseLocation
        visiblePanelResizeStartFrame = startFrame
        visiblePanelResizeStartMouseLocation = startMouseLocation

        var nextFrame = startFrame
        let mouseLocation = NSEvent.mouseLocation
        let dx = mouseLocation.x - startMouseLocation.x
        let dy = mouseLocation.y - startMouseLocation.y

        if edge.adjustsLeft {
            nextFrame.origin.x = startFrame.origin.x + dx
            nextFrame.size.width = startFrame.size.width - dx
        }

        if edge.adjustsRight {
            nextFrame.size.width = startFrame.size.width + dx
        }

        if edge.adjustsTop {
            nextFrame.size.height = startFrame.size.height + dy
        }

        if edge.adjustsBottom {
            nextFrame.origin.y = startFrame.origin.y + dy
            nextFrame.size.height = startFrame.size.height - dy
        }

        nextFrame = clampedResizeFrame(nextFrame, startFrame: startFrame, edge: edge)
        setFrame(nextFrame, display: true)
    }

    func finishVisiblePanelResize() {
        visiblePanelResizeStartFrame = nil
        visiblePanelResizeStartMouseLocation = nil
    }

    private func clampedResizeFrame(_ proposedFrame: NSRect, startFrame: NSRect, edge: CosmoWindowResizeEdge) -> NSRect {
        var frame = proposedFrame
        let clampedWidth = min(max(frame.width, minSize.width), maxSize.width)
        let clampedHeight = min(max(frame.height, minSize.height), maxSize.height)

        if edge.adjustsLeft {
            frame.origin.x += frame.width - clampedWidth
        }
        if edge.adjustsBottom {
            frame.origin.y += frame.height - clampedHeight
        }

        frame.size.width = clampedWidth
        frame.size.height = clampedHeight

        if !edge.adjustsLeft {
            frame.origin.x = startFrame.origin.x
        }
        if !edge.adjustsBottom {
            frame.origin.y = startFrame.origin.y
        }

        return frame
    }
}

// MARK: - Environment Key for Floating Panel Detection

struct CosmoWindowIsFloatingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var cosmoWindowIsFloating: Bool {
        get { self[CosmoWindowIsFloatingKey.self] }
        set { self[CosmoWindowIsFloatingKey.self] = newValue }
    }
}
