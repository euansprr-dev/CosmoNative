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
    private let frameIncludesShadowOutsetKey = "cosmoWindowFrameIncludesShadowOutset"

    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    init() {
        let savedFrame = CosmoWindowPanelController.loadSavedFrame()
        let initialFrame = savedFrame ?? CosmoWindowPanelController.defaultFrame()

        // .titled — required for edge-drag resize cursors on macOS
        // .resizable — allows edge-drag resizing
        // .nonactivatingPanel — clicking doesn't activate the app
        // .fullSizeContentView — content fills entire window frame (hides titlebar)
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

        // Appearance — transparent window with SwiftUI-owned shadow. The native
        // window shadow creates a dark fringe around transparent rounded panels.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Hide traffic light buttons (close/minimize/zoom)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Size constraints
        panel.minSize = NSSize(
            width: CosmoWindowMetrics.floatingWindowMinWidth,
            height: CosmoWindowMetrics.floatingWindowMinHeight
        )
        panel.maxSize = NSSize(
            width: CosmoWindowMetrics.floatingWindowMaxWidth,
            height: CosmoWindowMetrics.floatingWindowMaxHeight
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
                .preferredColorScheme(ThemeManager.shared.currentTheme.isDark ? .dark : .light)
        )
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = false
        panel.contentView = contentView

        // Match panel appearance to active theme
        panel.appearance = NSAppearance(named: ThemeManager.shared.currentTheme.isDark ? .darkAqua : .aqua)

        // Listen for theme changes to update panel appearance
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.Theme.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let isDark = ThemeManager.shared.currentTheme.isDark
            self.panel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            // Rebuild hosting view with updated color scheme
            let updatedView = NSHostingView(
                rootView: CosmoWindowView(isVisible: isVisible)
                    .environment(\.cosmoWindowIsFloating, true)
                    .preferredColorScheme(isDark ? .dark : .light)
            )
            updatedView.wantsLayer = true
            updatedView.layer?.masksToBounds = false
            self.panel.contentView = updatedView
        }

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
                    if ContentFocusWritingAIScope.shared.tryOpen() {
                        return
                    }
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
        UserDefaults.standard.set(true, forKey: frameIncludesShadowOutsetKey)
    }

    private static func loadSavedFrame() -> NSRect? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "cosmoWindowPosX") != nil else { return nil }

        let x = defaults.double(forKey: "cosmoWindowPosX")
        let y = defaults.double(forKey: "cosmoWindowPosY")
        let w = defaults.double(forKey: "cosmoWindowWidth")
        let h = defaults.double(forKey: "cosmoWindowHeight")
        let includesShadowOutset = defaults.bool(forKey: "cosmoWindowFrameIncludesShadowOutset")
        // If saved dimensions exceed current max, discard stale frame and use defaults.
        // Old saved frames without the transparent shadow gutter are automatically
        // expanded so the visible panel keeps its prior size.
        let migratedWidth = includesShadowOutset ? w : w + CosmoWindowMetrics.floatingShadowOutset * 2
        let migratedHeight = includesShadowOutset ? h : h + CosmoWindowMetrics.floatingShadowOutset * 2
        if !includesShadowOutset {
            defaults.set(true, forKey: "cosmoWindowFrameIncludesShadowOutset")
        }
        guard migratedWidth <= CosmoWindowMetrics.floatingWindowMaxWidth,
              migratedHeight <= CosmoWindowMetrics.floatingWindowMaxHeight else { return nil }
        let clampedWidth = min(
            max(migratedWidth, CosmoWindowMetrics.floatingWindowMinWidth),
            CosmoWindowMetrics.floatingWindowMaxWidth
        )
        let clampedHeight = min(
            max(migratedHeight, CosmoWindowMetrics.floatingWindowMinHeight),
            CosmoWindowMetrics.floatingWindowMaxHeight
        )
        let frame = NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)

        // Validate the saved frame is on a visible screen
        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
        return isOnScreen ? frame : nil
    }

    private static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = CosmoWindowMetrics.floatingWindowDefaultWidth
        let h = CosmoWindowMetrics.floatingWindowDefaultHeight
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
