// CosmoOS/UI/CaptureOverlay/CaptureStatusItemController.swift
// The menu-bar leaf: click opens the Capture Anywhere panel; drag a file
// onto it and the capture lands instantly — no window at all. Also the
// escape hatch when Accessibility permission (and so the global hotkey)
// is missing.
// July 2026 — Capture Anywhere

import AppKit

@MainActor
final class CaptureStatusItemController {
    static let shared = CaptureStatusItemController()

    private var statusItem: NSStatusItem?
    private var dropView: CaptureDropTargetView?
    private var confirmationTask: Task<Void, Never>?

    private init() {}

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else { return }
        button.image = NSImage(
            systemSymbolName: "leaf",
            accessibilityDescription: "Capture to Cosmo"
        )
        button.target = self
        button.action = #selector(togglePanel)
        button.toolTip = "Capture to Cosmo — click to open, or drop files here"

        // The drop layer sits over the button; hitTest is nil so clicks
        // still reach the button while drags land on the registered view.
        let drop = CaptureDropTargetView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.viewModel = CaptureOverlayPanelController.shared.viewModel
        drop.onDropHandled = { [weak self] in
            self?.flashConfirmation()
        }
        button.addSubview(drop)
        dropView = drop
    }

    @objc private func togglePanel() {
        CaptureOverlayPanelController.shared.toggle()
    }

    /// A drop landed on the menu bar — swap the leaf for a checkmark beat.
    private func flashConfirmation() {
        guard let button = statusItem?.button else { return }
        confirmationTask?.cancel()
        button.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Captured"
        )
        confirmationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            button.image = NSImage(
                systemSymbolName: "leaf",
                accessibilityDescription: "Capture to Cosmo"
            )
        }
    }
}
