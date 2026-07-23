// CosmoOS/UI/CaptureOverlay/CaptureOverlayPanelController.swift
// System-wide capture panel — summoned by the configurable capture hotkey
// (default ⌥C) from any app, any Space, even full-screen. Non-activating:
// the app the user was in keeps focus context; Esc returns them exactly
// where they were. Modeled on AtomWindowPanelController.
// July 2026 — Capture Anywhere

import AppKit
import SwiftUI

@MainActor
final class CaptureOverlayPanelController: NSWindowController {
    static let shared = CaptureOverlayPanelController()

    private var panel: CosmoKeyablePanel!
    private(set) var isShown = false

    let viewModel = CaptureOverlayViewModel()

    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?

    init() {
        let panel = CosmoKeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.panel = panel

        super.init(window: panel)

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true

        // Transparent window — the SwiftUI glass platter is the visible
        // surface and owns its own shadow.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.becomesKeyOnlyIfNeeded = false

        buildHostingView()

        NotificationCenter.default.addObserver(
            forName: CosmoNotification.Theme.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.buildHostingView()
            }
        }

        panel.orderOut(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Hosting

    private func buildHostingView() {
        let isDark = ThemeManager.shared.isDark
        let hostingView = NSHostingView(
            rootView: CaptureOverlayView(viewModel: viewModel)
                .environment(\.cosmoWindowIsFloating, true)
                .preferredColorScheme(isDark ? .dark : .light)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
        // The platter sizes itself; the panel follows the content.
        hostingView.sizingOptions = [.preferredContentSize]
        panel.contentView = hostingView
        panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    // MARK: - Show / hide / toggle

    func toggle() {
        if isShown {
            requestHide()
        } else {
            show()
        }
    }

    func show() {
        // Provenance: the app the user is capturing from, read before we
        // touch window ordering (the panel is non-activating, but be safe).
        let frontmost = NSWorkspace.shared.frontmostApplication
        let capturedFrom = (frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier)
            ? nil
            : frontmost?.localizedName

        viewModel.beginSession(capturedFrom: capturedFrom)

        centerOnMouseScreen()
        isShown = true
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()

        // Focus the thought field once the panel is key.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            viewModel.captureFieldFocusTick += 1
        }
    }

    /// Hide unless a drag is mid-flight over the panel — Esc during a drop
    /// would strand the payload.
    func requestHide() {
        guard !viewModel.isDropTargeted else { return }
        hide()
    }

    func hide() {
        isShown = false
        removeMonitors()
        // Staged-but-unsent files still land (individually, the bare-drop
        // path) — closing the panel never loses a capture.
        viewModel.flushStagedOnClose()
        panel.orderOut(nil)
    }

    // MARK: - Placement

    /// Center of the screen the mouse is on — the panel appears where the
    /// user is working, on every display, every Space.
    private func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        panel.layoutIfNeeded()
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            // Slightly above center — the Spotlight zone.
            y: visible.minY + visible.height * 0.55 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        // Esc / ⌘W close; ⌘V pastes into the capture session when no text
        // field owns focus (field paste keeps working normally).
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }

            if event.keyCode == 53 { // Esc
                Task { @MainActor in self.requestHide() }
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "w" {
                Task { @MainActor in self.requestHide() }
                return nil
            }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v",
               !self.panelFieldEditorIsActive() {
                Task { @MainActor in await self.viewModel.handlePaste() }
                return nil
            }
            return event
        }

        // Clicking into another Cosmo window means the capture session is
        // over. Clicks in OTHER apps deliberately keep the panel open —
        // summon → go find the file in Finder → drag it in is the core flow.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            if let self, event.window !== self.panel {
                Task { @MainActor in self.dismissIfIdle() }
            }
            return event
        }
    }

    /// Never dismisses while receiving promised files or mid-ingest — the
    /// session must land honestly.
    private func dismissIfIdle() {
        guard isShown, !viewModel.isBusy, !viewModel.isDropTargeted else { return }
        hide()
    }

    private func panelFieldEditorIsActive() -> Bool {
        guard let responder = panel.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func removeMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }
}
