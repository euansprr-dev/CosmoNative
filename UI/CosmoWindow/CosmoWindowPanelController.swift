// CosmoOS/UI/CosmoWindow/CosmoWindowPanelController.swift
// System-wide floating NSPanel for the Cosmo AI chat window
// Accessible from any app via Option+A hotkey
// March 2026

import SwiftUI
import AppKit

// MARK: - Keyable Panel (allows text input when focused)

class CosmoKeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Panel Controller

@MainActor
final class CosmoWindowPanelController: NSWindowController {
    static let shared = CosmoWindowPanelController()

    private var panel: CosmoKeyablePanel!
    private(set) var isShown = false

    // UserDefaults keys for position persistence
    private let posXKey = "cosmoWindowPosX"
    private let posYKey = "cosmoWindowPosY"
    private let widthKey = "cosmoWindowWidth"
    private let heightKey = "cosmoWindowHeight"

    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    init() {
        let savedFrame = CosmoWindowPanelController.loadSavedFrame()
        let initialFrame = savedFrame ?? CosmoWindowPanelController.defaultFrame()

        // No .titled — removes traffic lights and window chrome border
        // .resizable — allows edge-drag resizing
        // .nonactivatingPanel — clicking doesn't activate the app
        // .fullSizeContentView — content fills entire window frame
        panel = CosmoKeyablePanel(
            contentRect: initialFrame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable],
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

        // Appearance — fully transparent window, SwiftUI handles all visuals
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Size constraints
        panel.minSize = NSSize(
            width: CosmoWindowMetrics.minWidth,
            height: CosmoWindowMetrics.minHeight
        )
        panel.maxSize = NSSize(
            width: CosmoWindowMetrics.maxWidth,
            height: CosmoWindowMetrics.maxHeight
        )

        // Allow keyboard input (text field in chat)
        panel.becomesKeyOnlyIfNeeded = false

        // Host the existing CosmoWindowView with isFloatingPanel flag
        let isVisible = Binding<Bool>(
            get: { [weak self] in self?.isShown ?? false },
            set: { [weak self] newValue in
                if !newValue { self?.hide() }
            }
        )

        let contentView = NSHostingView(
            rootView: CosmoWindowView(isVisible: isVisible)
                .environment(\.cosmoWindowIsFloating, true)
        )
        contentView.wantsLayer = true
        panel.contentView = contentView

        // Start hidden
        panel.orderOut(nil)

        // Observe position/size changes for persistence
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        }

        // Fallback hotkey monitors — work WITHOUT Accessibility permission
        // Global monitor: fires when OTHER apps are focused
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 0, // 'A' key
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.control) {
                Task { @MainActor in
                    self?.toggle()
                }
            }
        }

        // Local monitor: fires when CosmoOS IS the active app (can consume event)
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 0, // 'A' key
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.control) {
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
        panel.orderFrontRegardless()
        panel.makeKey()

        // Update context when showing
        let vm = CosmoWindowViewModel.shared
        if vm.activeContext.type == .none {
            vm.updateContextManually(type: .none)
        }
    }

    func hide() {
        isShown = false
        panel.orderOut(nil)
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
        guard defaults.object(forKey: "cosmoWindowPosX") != nil else { return nil }

        let x = defaults.double(forKey: "cosmoWindowPosX")
        let y = defaults.double(forKey: "cosmoWindowPosY")
        let w = defaults.double(forKey: "cosmoWindowWidth")
        let h = defaults.double(forKey: "cosmoWindowHeight")
        let clampedWidth = min(max(w, CosmoWindowMetrics.minWidth), CosmoWindowMetrics.maxWidth)
        let clampedHeight = min(max(h, CosmoWindowMetrics.minHeight), CosmoWindowMetrics.maxHeight)
        let frame = NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)

        // Validate the saved frame is on a visible screen
        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
        return isOnScreen ? frame : nil
    }

    private static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = CosmoWindowMetrics.defaultWidth
        let h = CosmoWindowMetrics.defaultHeight
        let x = screen.maxX - w - 20
        let y = screen.midY - h / 2
        return NSRect(x: x, y: y, width: w, height: h)
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
