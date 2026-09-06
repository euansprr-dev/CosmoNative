// CosmoOS/UI/AtomWindow/AtomWindowPanelController.swift
// System-wide floating NSPanel for the universal atom viewer
// Accessible from any app via Control+Option+E (and Option+E)
// April 2026

import SwiftUI
import AppKit

// MARK: - Panel Controller

@MainActor
final class AtomWindowPanelController: NSWindowController {
    static let shared = AtomWindowPanelController()

    private var panel: CosmoKeyablePanel!
    private(set) var isShown = false

    // The view model powering the hosted SwiftUI view
    let viewModel = AtomWindowViewModel()

    // UserDefaults keys for position persistence
    private let posXKey = "atomWindowPosX"
    private let posYKey = "atomWindowPosY"
    private let widthKey = "atomWindowWidth"
    private let heightKey = "atomWindowHeight"

    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private var contentLoadTask: Task<Void, Never>?

    init() {
        let savedFrame = AtomWindowPanelController.loadSavedFrame()
        let initialFrame = savedFrame ?? AtomWindowPanelController.defaultFrame()

        panel = CosmoKeyablePanel(
            contentRect: initialFrame,
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        // Floating panel configuration
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true

        // Appearance — transparent window, system shadow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Hide traffic light buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Size constraints
        panel.minSize = NSSize(
            width: AtomWindowMetrics.minWidth,
            height: AtomWindowMetrics.minHeight
        )
        panel.maxSize = NSSize(
            width: AtomWindowMetrics.maxWidth,
            height: AtomWindowMetrics.maxHeight
        )

        // Allow keyboard input
        panel.becomesKeyOnlyIfNeeded = false

        // Host the SwiftUI view
        buildHostingView()

        // Listen for theme changes
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.Theme.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.buildHostingView()
            }
        }

        // Start hidden
        panel.orderOut(nil)

        // Observe position/size changes for persistence
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveFrame()
            }
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveFrame()
            }
        }

        // Fallback hotkey monitors (Option+E, keyCode 14)
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 14,
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift) {
                Task { @MainActor in
                    self?.toggle()
                }
            }
        }

        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let self, event.window === self.panel,
               event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "k" {
                self.viewModel.toggleSwitcher()
                return nil
            }
            if event.keyCode == 14,
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift) {
                Task { @MainActor in
                    self?.toggle()
                }
                return nil // Consume the event
            }
            return event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            contentLoadTask?.cancel()
            if let observer = moveObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = resizeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let monitor = globalHotkeyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = localHotkeyMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    // MARK: - Hosting View

    private func buildHostingView() {
        panel.makeFirstResponder(nil)
        DirtyEditorRegistry.shared.flushAll()
        let isDark = ThemeManager.shared.isDark
        let contentView = NSHostingView(
            rootView: AtomWindowRootView(viewModel: viewModel)
                .environment(\.cosmoWindowIsFloating, true)
                .environment(\.isPaneContext, true)
                .environment(\.isPaneActive, true)
                .preferredColorScheme(isDark ? .dark : .light)
        )
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = false
        panel.contentView = contentView
        panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    // MARK: - Show / Hide / Toggle

    func toggle() {
        if isShown {
            hide()
        } else {
            show()
        }
    }

    func show() {
        isShown = true
        viewModel.isPresented = true
        panel.alphaValue = 1 // a hide() mid-teardown may have dropped it
        panel.orderFrontRegardless()
        panel.makeKey()
        contentLoadTask?.cancel()
        contentLoadTask = Task { @MainActor in
            await viewModel.restoreLastSession()
        }
    }

    func hide() {
        isShown = false
        contentLoadTask?.cancel()
        contentLoadTask = nil

        // Commit every surface holding unsaved edits, synchronously, BEFORE the
        // session is torn down and the editing lock released.
        // Resigning flushes TextKit's pending buffer into the document before
        // the persistence registry takes its snapshot.
        panel.makeFirstResponder(nil)
        DirtyEditorRegistry.shared.flushAll()

        // Then let SwiftUI actually process the teardown. The hosted focus
        // view's `onDisappear` owns the close-save (and defers one turn so the
        // editor's pending text sync lands first) — but it only runs if SwiftUI
        // commits the transaction. Ordering the panel out in the SAME turn as
        // the unload put the window off-screen first, and AppKit defers
        // layout/display for an ordered-out window, so that save could never
        // run. Drop alpha for an instant visual close, order out once the
        // teardown has been processed.
        panel.alphaValue = 0
        viewModel.isPresented = false
        // The switcher layer never survives a hide — ⌥E reopens onto the
        // item exactly as it was left.
        viewModel.prepareForHide()
        // Keep the one open note mounted: reopening preserves its scroll,
        // undo history, and hydrated editors. Other focus modes still use
        // their existing teardown lifecycle.
        if viewModel.currentAtom?.type != .note {
            viewModel.unloadCurrentSession()
        }
        DispatchQueue.main.async { [weak self] in
            // A show() may have raced in behind us — never yank it back out.
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        }
    }

    /// Open the panel and navigate to a specific atom
    func show(atomUUID: String) {
        isShown = true
        viewModel.isPresented = true
        contentLoadTask?.cancel()
        panel.alphaValue = 1 // a hide() mid-teardown may have dropped it
        panel.orderFrontRegardless()
        panel.makeKey()
        contentLoadTask = Task { @MainActor in
            if viewModel.currentAtom?.uuid == atomUUID {
                await viewModel.restoreLastSession()
            } else {
                await viewModel.navigate(to: atomUUID)
            }
        }
    }

    // MARK: - Frame Persistence

    private func saveFrame() {
        let frame = panel.frame
        UserDefaults.standard.set(Double(frame.origin.x), forKey: posXKey)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: posYKey)
        UserDefaults.standard.set(Double(frame.size.width), forKey: widthKey)
        UserDefaults.standard.set(Double(frame.size.height), forKey: heightKey)
    }

    private static func loadSavedFrame() -> NSRect? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "atomWindowPosX") != nil else { return nil }

        let x = defaults.double(forKey: "atomWindowPosX")
        let y = defaults.double(forKey: "atomWindowPosY")
        let w = defaults.double(forKey: "atomWindowWidth")
        let h = defaults.double(forKey: "atomWindowHeight")

        guard w <= AtomWindowMetrics.maxWidth, h <= AtomWindowMetrics.maxHeight else { return nil }

        let clampedWidth = min(max(w, AtomWindowMetrics.minWidth), AtomWindowMetrics.maxWidth)
        let clampedHeight = min(max(h, AtomWindowMetrics.minHeight), AtomWindowMetrics.maxHeight)
        let frame = NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)

        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
        return isOnScreen ? frame : nil
    }

    private static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = AtomWindowMetrics.defaultWidth
        let h = AtomWindowMetrics.defaultHeight
        let x = screen.midX - w / 2
        let y = screen.midY - h / 2
        return NSRect(x: x, y: y, width: w, height: h)
    }
}
