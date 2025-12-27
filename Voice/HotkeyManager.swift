// CosmoOS/Voice/HotkeyManager.swift
// Global hotkey management using Carbon and AppKit
// Default: Option+Z (configurable via Settings)

import Foundation
import Carbon
import AppKit
import Combine

/// Represents a configurable hotkey combination
struct HotkeyConfig: Codable, Equatable {
    var keyCode: Int       // CGKeyCode
    var modifiers: UInt64  // CGEventFlags raw value
    var displayName: String

    // Default: Option+Z
    static let defaultVoiceHotkey = HotkeyConfig(
        keyCode: 6,           // 'Z' key
        modifiers: CGEventFlags.maskAlternate.rawValue,
        displayName: "⌥Z"
    )

    // Swipe File hotkey: Cmd+Shift+S (non-configurable)
    static let swipeFileHotkey = HotkeyConfig(
        keyCode: 1,           // 'S' key
        modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue,
        displayName: "⌘⇧S"
    )

    // Alternative options for user selection
    // Option+Space is recommended as most reliable push-to-talk style
    static let alternativeHotkeys: [HotkeyConfig] = [
        // Most reliable options first
        HotkeyConfig(keyCode: 49, modifiers: CGEventFlags.maskAlternate.rawValue, displayName: "⌥Space"),  // Recommended!
        HotkeyConfig(keyCode: 6, modifiers: CGEventFlags.maskAlternate.rawValue, displayName: "⌥Z"),
        HotkeyConfig(keyCode: 49, modifiers: CGEventFlags.maskShift.rawValue, displayName: "⇧Space"),
        HotkeyConfig(keyCode: 49, modifiers: CGEventFlags([.maskShift, .maskAlternate]).rawValue, displayName: "⇧⌥Space"),
        HotkeyConfig(keyCode: 47, modifiers: CGEventFlags.maskAlternate.rawValue, displayName: "⌥."),
        HotkeyConfig(keyCode: 1, modifiers: CGEventFlags([.maskControl, .maskShift]).rawValue, displayName: "⌃⇧S"),
        // Fn key - works on some Macs but may be intercepted by system
        HotkeyConfig(keyCode: -1, modifiers: CGEventFlags.maskSecondaryFn.rawValue, displayName: "Fn (experimental)"),
    ]

    var modifierFlags: CGEventFlags {
        CGEventFlags(rawValue: modifiers)
    }
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onPressCallback: (() -> Void)?
    private var onReleaseCallback: (() -> Void)?
    private var isActivated = false

    // MARK: - Swipe File Hotkey Support
    private var swipeFileCallback: (() -> Void)?
    private let swipeFileHotkey = HotkeyConfig.swipeFileHotkey

    // MARK: - Command Bar Typing Hotkey (Cmd+Shift+C)
    private var commandBarTypingCallback: (() -> Void)?
    private let commandBarTypingHotkey = HotkeyConfig(
        keyCode: 8,  // 'C' key
        modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue,
        displayName: "⌘⇧C"
    )

    /// Whether the hotkey was successfully registered (for UI feedback)
    @Published var isRegistered = false

    /// Last registration error (for debugging)
    @Published var registrationError: String?

    // Current hotkey configuration
    @Published var currentHotkey: HotkeyConfig {
        didSet {
            saveHotkeyConfig()
            // Re-register with new hotkey if already active
            if eventTap != nil, let press = onPressCallback, let release = onReleaseCallback {
                unregister()
                registerHotkey(onPress: press, onRelease: release)
            }
        }
    }

    private init() {
        // Load saved hotkey or use default
        self.currentHotkey = HotkeyManager.loadHotkeyConfig()
        print("🔑 HotkeyManager initialized with hotkey: \(currentHotkey.displayName)")
        print("🔑 Swipe File hotkey: \(swipeFileHotkey.displayName)")
    }

    // MARK: - Swipe File Hotkey Registration

    /// Register callback for Cmd+Shift+S swipe file capture
    func registerSwipeFileHotkey(onTrigger: @escaping () -> Void) {
        self.swipeFileCallback = onTrigger
        print("📋 Swipe File hotkey callback registered")
    }

    // MARK: - Command Bar Typing Hotkey Registration (Option-C)

    /// Register callback for Option-C to open command bar typing mode
    func registerCommandBarTypingHotkey(onTrigger: @escaping () -> Void) {
        self.commandBarTypingCallback = onTrigger
        print("⌨️ Command Bar Typing hotkey (⌥C) callback registered")
    }

    // MARK: - Persistence
    private static func loadHotkeyConfig() -> HotkeyConfig {
        if let data = UserDefaults.standard.data(forKey: "voiceHotkeyConfig"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            return config
        }
        return HotkeyConfig.defaultVoiceHotkey
    }

    private func saveHotkeyConfig() {
        if let data = try? JSONEncoder().encode(currentHotkey) {
            UserDefaults.standard.set(data, forKey: "voiceHotkeyConfig")
        }
        print("💾 Saved hotkey: \(currentHotkey.displayName)")
    }

    // MARK: - Register Global Hotkey
    func registerHotkey(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.onPressCallback = onPress
        self.onReleaseCallback = onRelease
        self.registrationError = nil

        print("🔑 Attempting to register hotkey: \(currentHotkey.displayName)")
        print("   keyCode: \(currentHotkey.keyCode), modifiers: \(currentHotkey.modifiers)")

        // Check accessibility permission first
        let hasPermission = checkAccessibilityPermission()

        if !hasPermission {
            let errorMsg = "Accessibility permission required for global hotkey"
            print("⚠️  \(errorMsg)")
            print("   Please grant permission in System Settings > Privacy & Security > Accessibility")
            print("   NOTE: When running from Xcode, use the in-app voice button instead")
            print("   ℹ️  App will continue without global hotkey (development mode)")

            self.registrationError = errorMsg
            self.isRegistered = false

            // Notify the app that permissions are needed
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .hotkeyPermissionNeeded,
                    object: nil
                )
            }
            return  // Non-blocking - app continues without hotkey
        }

        print("✅ Accessibility permission granted")

        // Create event tap
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: selfPointer
        )

        guard let tap = eventTap else {
            let errorMsg = "Failed to create event tap - accessibility permission may have been revoked"
            print("❌ \(errorMsg)")
            print("   ℹ️  App will continue without global hotkey (development mode)")
            self.registrationError = errorMsg
            self.isRegistered = false
            return  // Non-blocking
        }

        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.isRegistered = true
        self.registrationError = nil

        print("✅ Global \(currentHotkey.displayName) hotkey registered successfully!")
        print("   Event tap created and added to run loop")
    }

    // Legacy method for compatibility
    func registerSpaceHotkey(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        registerHotkey(onPress: onPress, onRelease: onRelease)
    }

    // Enable verbose logging for debugging (set to false for production)
    private let verboseLogging = false

    // MARK: - Event Handling
    private func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let requiredMods = currentHotkey.modifierFlags
        let hasRequiredMods = flags.contains(requiredMods)

        // MARK: Check for Swipe File hotkey (Cmd+Shift+S)
        // This takes priority and is a single-press action (not push-to-talk)
        if type == .keyDown && keyCode == swipeFileHotkey.keyCode {
            let swipeMods = swipeFileHotkey.modifierFlags
            let hasSwipeMods = flags.contains(swipeMods)

            // Ensure only Cmd+Shift are pressed (not other modifiers like Option)
            let hasOnlySwipeMods = hasSwipeMods &&
                !flags.contains(.maskAlternate) &&
                !flags.contains(.maskControl)

            // Debug logging for swipe file hotkey
            print("📋 Swipe hotkey check: keyCode=\(keyCode), hasSwipeMods=\(hasSwipeMods), hasOnlySwipeMods=\(hasOnlySwipeMods), isInTextField=\(isInTextField()), callbackRegistered=\(swipeFileCallback != nil)")

            if hasOnlySwipeMods {
                if !isInTextField() {
                    print("📋 Swipe File hotkey triggered (⌘⇧S)")
                    if swipeFileCallback != nil {
                        swipeFileCallback?()
                    } else {
                        print("⚠️ Swipe File callback is nil! Was registerSwipeFileHotkey called?")
                    }
                    return nil // Consume event
                } else {
                    print("📋 Swipe File hotkey blocked: currently in text field")
                }
            }
        }

        // MARK: Check for Command Bar Typing hotkey (Cmd+Shift+C)
        if type == .keyDown && keyCode == commandBarTypingHotkey.keyCode {
            let typingMods = commandBarTypingHotkey.modifierFlags
            let hasTypingMods = flags.contains(typingMods)

            // Ensure Cmd+Shift are pressed (not Option or Ctrl additionally)
            let hasCorrectMods = hasTypingMods &&
                !flags.contains(.maskAlternate) &&
                !flags.contains(.maskControl)

            if hasCorrectMods {
                if !isInTextField() {
                    print("⌨️ Command Bar Typing hotkey triggered (⌘⇧C)")
                    commandBarTypingCallback?()
                    return nil // Consume event
                }
            }
        }

        // Verbose logging for debugging hotkey issues
        if verboseLogging {
            let typeStr: String
            switch type {
            case .keyDown: typeStr = "keyDown"
            case .keyUp: typeStr = "keyUp"
            case .flagsChanged: typeStr = "flagsChanged"
            default: typeStr = "other(\(type.rawValue))"
            }
            print("🔍 Event: \(typeStr), keyCode=\(keyCode), flags=\(flags.rawValue), required=\(requiredMods.rawValue), hasRequired=\(hasRequiredMods)")
        }

        // MARK: Modifier-only hotkeys (e.g. Fn hold)
        // Fn typically arrives as flagsChanged (no keyDown/keyUp). Treat modifier press/release as push-to-talk.
        if currentHotkey.keyCode < 0 {
            if type == .flagsChanged {
                // Check specifically for the Fn flag
                let hasFnFlag = flags.contains(.maskSecondaryFn)

                if verboseLogging {
                    print("🔍 Fn hotkey mode: hasFnFlag=\(hasFnFlag), hasRequiredMods=\(hasRequiredMods), isActivated=\(isActivated)")
                }

                if hasRequiredMods || hasFnFlag {
                    if !isActivated {
                        isActivated = true
                        print("🎤 Fn pressed - starting voice")
                        onPressCallback?()
                        return nil // consume so system doesn't trigger alternative Fn behaviors
                    }
                } else {
                    if isActivated {
                        isActivated = false
                        print("🎤 Fn released - stopping voice")
                        onReleaseCallback?()
                        return nil
                    }
                }
            }
            return Unmanaged.passRetained(event)
        }

        // Handle flagsChanged for modifier-only deactivation
        if type == .flagsChanged {
            // If activated and required modifier was released, deactivate
            if isActivated {
                if !hasRequiredMods {
                    print("🔑 flagsChanged: modifier released while activated - calling onReleaseCallback")
                    isActivated = false
                    onReleaseCallback?()
                    print("🔑 flagsChanged: onReleaseCallback completed")
                }
            }
            return Unmanaged.passRetained(event)
        }

        // Check if this is our configured key
        guard keyCode == currentHotkey.keyCode else {
            return Unmanaged.passRetained(event)
        }

        // Check if we're in a text field (don't intercept if editing)
        if isInTextField() {
            return Unmanaged.passRetained(event)
        }

        // Check if correct modifiers are held
        let hasCorrectModifiers = hasRequiredMods

        // Don't block if Command is pressed (allow system shortcuts)
        if flags.contains(.maskCommand) {
            return Unmanaged.passRetained(event)
        }

        // Handle hotkey combo - ALWAYS consume our key when correct modifiers are held
        // This prevents the system beep by fully intercepting the event
        switch type {
        case .keyDown:
            print("🔑 keyDown detected: keyCode=\(keyCode), hasCorrectModifiers=\(hasCorrectModifiers), isActivated=\(isActivated)")
            if hasCorrectModifiers {
                if !isActivated {
                    isActivated = true
                    print("🔑 \(currentHotkey.displayName) pressed - calling onPressCallback")
                    onPressCallback?()
                    print("🔑 onPressCallback completed")
                }
                return nil // Always consume when our modifier combo is held
            }
        case .keyUp:
            // Consume keyUp if we're activated OR if the correct modifiers are still held
            // This prevents beep from the keyUp event
            print("🔑 keyUp detected: keyCode=\(keyCode), isActivated=\(isActivated), hasCorrectModifiers=\(hasCorrectModifiers)")
            if isActivated || hasCorrectModifiers {
                if isActivated {
                    isActivated = false
                    print("🔑 \(currentHotkey.displayName) released - calling onReleaseCallback")
                    onReleaseCallback?()
                    print("🔑 onReleaseCallback completed")
                }
                return nil // Consume to prevent beep
            }
        default:
            break
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Text Field Detection
    private func isInTextField() -> Bool {
        // Check ALL windows for text field focus (including SwiftUI)
        for window in NSApplication.shared.windows {
            guard let responder = window.firstResponder else { continue }

            // Direct type checks for AppKit text inputs
            if responder is NSTextView ||
               responder is NSTextField ||
               responder is NSSecureTextField {
                return true
            }

            // Check for SwiftUI text fields (wrapped in hosting views)
            let responderType = String(describing: type(of: responder))
            if responderType.contains("NSTextInputContext") ||
               responderType.contains("FieldEditor") ||
               responderType.contains("NSTextView") ||
               responderType.contains("TextField") ||
               responderType.contains("TextEditor") {
                return true
            }

            // Check parent responder chain for text views
            var current: NSResponder? = responder
            while let r = current {
                let typeString = String(describing: type(of: r))
                if typeString.contains("NSTextView") ||
                   typeString.contains("NSTextField") ||
                   typeString.contains("FieldEditor") {
                    return true
                }
                current = r.nextResponder
            }
        }

        return false
    }

    // MARK: - Permissions
    private func checkAccessibilityPermission() -> Bool {
        // Check without prompting first (non-intrusive)
        let trusted = AXIsProcessTrusted()
        return trusted
    }

    nonisolated func requestAccessibilityPermission() {
        // Only call this when user explicitly wants to enable hotkeys
        // kAXTrustedCheckOptionPrompt is a global C variable that we access in a nonisolated context
        let promptKey: CFString = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [promptKey: true] as CFDictionary

        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            print("⚠️  Accessibility permission required for global hotkey")
            print("   Please grant permission in System Settings > Privacy & Security > Accessibility")
        }
    }

    // MARK: - Unregister
    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        onPressCallback = nil
        onReleaseCallback = nil
        isActivated = false
        isRegistered = false

        print("🔇 Global hotkey unregistered")
    }

    /// Check if hotkey is currently working
    var status: String {
        if isRegistered {
            return "✅ \(currentHotkey.displayName) active"
        } else if let error = registrationError {
            return "❌ \(error)"
        } else {
            return "⏳ Not registered"
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let hotkeyPermissionNeeded = Notification.Name("hotkeyPermissionNeeded")
}
