// CosmoOS/Daemon/AXContextService.swift
// Accessibility API context capture running in daemon (NOT sandboxed app)
// "God Mode" - captures active window context from Chrome, Safari, VS Code, etc.
// macOS 26+ optimized

import Foundation
import AppKit
import ApplicationServices

// MARK: - Window Context

public struct WindowContext: Codable, Sendable {
    public let appName: String
    public let bundleIdentifier: String?
    public let windowTitle: String
    public let url: String?
    public let selectedText: String?
    public let visibleText: String
    public let focusedElement: String?
    public let captureTime: Date
    public let captureMethod: CaptureMethod

    public enum CaptureMethod: String, Codable, Sendable {
        case accessibility = "AX"
        case screenCapture = "ScreenCapture"
        case hybrid = "Hybrid"
        case fallback = "Fallback"
    }

    public init(
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String,
        url: String?,
        selectedText: String?,
        visibleText: String,
        focusedElement: String?,
        captureTime: Date,
        captureMethod: CaptureMethod
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
        self.visibleText = visibleText
        self.focusedElement = focusedElement
        self.captureTime = captureTime
        self.captureMethod = captureMethod
    }

    /// Check if context has meaningful content
    public var hasContent: Bool {
        !visibleText.isEmpty || selectedText != nil || url != nil
    }

    /// Get a summary for LLM context
    public var contextSummary: String {
        var parts: [String] = []

        parts.append("App: \(appName)")
        if let url = url {
            parts.append("URL: \(url)")
        }
        parts.append("Window: \(windowTitle)")

        if let selected = selectedText, !selected.isEmpty {
            parts.append("Selected: \"\(selected.prefix(500))\"")
        }

        if !visibleText.isEmpty {
            parts.append("Visible: \"\(visibleText.prefix(1500))\"")
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - AX Context Service

public final class AXContextService: @unchecked Sendable {
    // MARK: - Singleton

    public static let shared = AXContextService()

    // MARK: - Configuration

    private let maxVisibleTextLength = 2000
    private let minTextLengthForFallback = 50

    // MARK: - Initialization

    public init() {
        print("AXContextService: Initialized (running in daemon)")
    }

    // MARK: - Permission Check

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = getAccessibilityPromptOptions()
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Context Capture

    /// Capture context from the active window
    public func captureActiveWindowContext() async -> WindowContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return createEmptyContext(reason: "No frontmost app")
        }

        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier

        // Create AXUIElement for the app
        let axApp = AXUIElementCreateApplication(pid)

        // Get window title
        let windowTitle = getWindowTitle(axApp: axApp) ?? appName

        // Strategy varies by app
        let context: WindowContext

        switch bundleId {
        case "com.google.Chrome", "com.google.Chrome.canary":
            context = await captureChromeContext(axApp: axApp, appName: appName, bundleId: bundleId, windowTitle: windowTitle)

        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            context = await captureSafariContext(axApp: axApp, appName: appName, bundleId: bundleId, windowTitle: windowTitle)

        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            context = await captureVSCodeContext(axApp: axApp, appName: appName, bundleId: bundleId, windowTitle: windowTitle)

        case "com.apple.Terminal", "com.googlecode.iterm2":
            context = await captureTerminalContext(axApp: axApp, appName: appName, bundleId: bundleId, windowTitle: windowTitle)

        case "com.apple.finder":
            context = await captureFinderContext(axApp: axApp, appName: appName, bundleId: bundleId, windowTitle: windowTitle)

        default:
            context = await captureGenericContext(axApp: axApp, appName: appName, bundleId: bundleId, windowTitle: windowTitle)
        }

        // Check if we need fallback to screen capture
        if context.visibleText.count < minTextLengthForFallback {
            return await captureWithFallback(axContext: context, axApp: axApp, appName: appName, bundleId: bundleId, windowTitle: windowTitle)
        }

        return context
    }

    // MARK: - App-Specific Capture

    private func captureChromeContext(axApp: AXUIElement, appName: String, bundleId: String?, windowTitle: String) async -> WindowContext {
        // Get URL from address bar
        let url = getURLFromAddressBar(axApp: axApp, browserType: .chrome)

        // Get selected text
        let selectedText = getSelectedText(axApp: axApp)

        // Get visible text from web content
        let visibleText = getWebPageText(axApp: axApp, browserType: .chrome)

        // Get focused element
        let focusedElement = getFocusedElementDescription(axApp: axApp)

        return WindowContext(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            url: url,
            selectedText: selectedText,
            visibleText: visibleText,
            focusedElement: focusedElement,
            captureTime: Date(),
            captureMethod: .accessibility
        )
    }

    private func captureSafariContext(axApp: AXUIElement, appName: String, bundleId: String?, windowTitle: String) async -> WindowContext {
        // Get URL from address bar
        let url = getURLFromAddressBar(axApp: axApp, browserType: .safari)

        // Get selected text
        let selectedText = getSelectedText(axApp: axApp)

        // Get visible text from web content
        let visibleText = getWebPageText(axApp: axApp, browserType: .safari)

        // Get focused element
        let focusedElement = getFocusedElementDescription(axApp: axApp)

        return WindowContext(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            url: url,
            selectedText: selectedText,
            visibleText: visibleText,
            focusedElement: focusedElement,
            captureTime: Date(),
            captureMethod: .accessibility
        )
    }

    private func captureVSCodeContext(axApp: AXUIElement, appName: String, bundleId: String?, windowTitle: String) async -> WindowContext {
        // Parse file path from window title (VS Code format: "filename — folder — VS Code")
        let filePath = parseVSCodeFilePath(windowTitle: windowTitle)

        // Get selected text (code selection)
        let selectedText = getSelectedText(axApp: axApp)

        // Get visible code from editor
        let visibleText = getEditorContent(axApp: axApp)

        // Get focused element (current line/function)
        let focusedElement = getFocusedElementDescription(axApp: axApp)

        return WindowContext(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            url: filePath,  // Use file path as "URL"
            selectedText: selectedText,
            visibleText: visibleText,
            focusedElement: focusedElement,
            captureTime: Date(),
            captureMethod: .accessibility
        )
    }

    private func captureTerminalContext(axApp: AXUIElement, appName: String, bundleId: String?, windowTitle: String) async -> WindowContext {
        // Get terminal output
        let visibleText = getTerminalContent(axApp: axApp)

        // Get selected text
        let selectedText = getSelectedText(axApp: axApp)

        // Parse current directory from title or prompt
        let currentDir = parseTerminalDirectory(windowTitle: windowTitle, content: visibleText)

        return WindowContext(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            url: currentDir,  // Use directory as "URL"
            selectedText: selectedText,
            visibleText: visibleText,
            focusedElement: nil,
            captureTime: Date(),
            captureMethod: .accessibility
        )
    }

    private func captureFinderContext(axApp: AXUIElement, appName: String, bundleId: String?, windowTitle: String) async -> WindowContext {
        // Get current folder path
        let folderPath = getFinderPath(axApp: axApp)

        // Get selected items
        let selectedItems = getFinderSelectedItems(axApp: axApp)

        return WindowContext(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            url: folderPath,
            selectedText: selectedItems,
            visibleText: folderPath ?? windowTitle,
            focusedElement: nil,
            captureTime: Date(),
            captureMethod: .accessibility
        )
    }

    private func captureGenericContext(axApp: AXUIElement, appName: String, bundleId: String?, windowTitle: String) async -> WindowContext {
        // Generic strategy: get whatever text we can find

        // Get selected text
        let selectedText = getSelectedText(axApp: axApp)

        // Get visible text from any text areas
        let visibleText = getGenericVisibleText(axApp: axApp)

        // Get focused element
        let focusedElement = getFocusedElementDescription(axApp: axApp)

        return WindowContext(
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            url: nil,
            selectedText: selectedText,
            visibleText: visibleText,
            focusedElement: focusedElement,
            captureTime: Date(),
            captureMethod: .accessibility
        )
    }

    // MARK: - AX Helpers

    private func getWindowTitle(axApp: AXUIElement) -> String? {
        var windowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard windowResult == .success, let window = windowValue else {
            // Try main window
            var mainWindowValue: CFTypeRef?
            let mainResult = AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &mainWindowValue)
            guard mainResult == .success, let mainWindow = mainWindowValue else {
                return nil
            }
            return getElementValue(mainWindow as! AXUIElement, attribute: kAXTitleAttribute)
        }

        return getElementValue(window as! AXUIElement, attribute: kAXTitleAttribute)
    }

    private func getSelectedText(axApp: AXUIElement) -> String? {
        // First try focused UI element
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        if focusedResult == .success, let focused = focusedValue {
            let focusedElement = focused as! AXUIElement

            // Try to get selected text
            var selectedValue: CFTypeRef?
            let selectedResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedValue)

            if selectedResult == .success, let selected = selectedValue as? String, !selected.isEmpty {
                return selected
            }
        }

        return nil
    }

    private func getElementValue(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        if result == .success, let stringValue = value as? String {
            return stringValue
        }
        return nil
    }

    private func getFocusedElementDescription(axApp: AXUIElement) -> String? {
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        guard focusedResult == .success, let focused = focusedValue else {
            return nil
        }

        let focusedElement = focused as! AXUIElement

        // Get role and description
        let role = getElementValue(focusedElement, attribute: kAXRoleAttribute) ?? "unknown"
        let description = getElementValue(focusedElement, attribute: kAXDescriptionAttribute)
        let title = getElementValue(focusedElement, attribute: kAXTitleAttribute)

        var parts = [role]
        if let title = title {
            parts.append("'\(title)'")
        }
        if let description = description {
            parts.append("(\(description))")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Browser-Specific

    private enum BrowserType {
        case chrome
        case safari
    }

    private func getURLFromAddressBar(axApp: AXUIElement, browserType: BrowserType) -> String? {
        // Find the address bar text field
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard let window = windowValue else { return nil }

        // Search for text field with URL
        return findURLInElement(window as! AXUIElement, browserType: browserType)
    }

    private func findURLInElement(_ element: AXUIElement, browserType: BrowserType, depth: Int = 0) -> String? {
        guard depth < 10 else { return nil }  // Prevent infinite recursion

        // Check if this is the address bar
        let role = getElementValue(element, attribute: kAXRoleAttribute)

        if role == "AXTextField" || role == "AXComboBox" {
            // Check identifier or description
            let identifier = getElementValue(element, attribute: kAXIdentifierAttribute)
            let description = getElementValue(element, attribute: kAXDescriptionAttribute)

            let isAddressBar = identifier?.contains("address") == true ||
                               identifier?.contains("url") == true ||
                               identifier?.contains("location") == true ||
                               description?.lowercased().contains("address") == true ||
                               description?.lowercased().contains("url") == true

            if isAddressBar {
                return getElementValue(element, attribute: kAXValueAttribute)
            }
        }

        // Check for web area and get URL from it
        if role == "AXWebArea" {
            if let url = getElementValue(element, attribute: "AXURL") {
                return url
            }
        }

        // Recurse into children
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let url = findURLInElement(child, browserType: browserType, depth: depth + 1) {
                    return url
                }
            }
        }

        return nil
    }

    private func getWebPageText(axApp: AXUIElement, browserType: BrowserType) -> String {
        // Find web area and extract text
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard let window = windowValue else { return "" }

        return findTextInWebArea(window as! AXUIElement)
    }

    private func findTextInWebArea(_ element: AXUIElement, depth: Int = 0) -> String {
        guard depth < 15 else { return "" }

        let role = getElementValue(element, attribute: kAXRoleAttribute)

        if role == "AXWebArea" {
            // Found web area - extract text content
            return extractTextFromElement(element)
        }

        // Recurse into children
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                let text = findTextInWebArea(child, depth: depth + 1)
                if !text.isEmpty {
                    return text
                }
            }
        }

        return ""
    }

    private func extractTextFromElement(_ element: AXUIElement, depth: Int = 0) -> String {
        guard depth < 20 else { return "" }

        var text = ""

        // Get value or title
        if let value = getElementValue(element, attribute: kAXValueAttribute) {
            text += value + " "
        }
        if let title = getElementValue(element, attribute: kAXTitleAttribute) {
            text += title + " "
        }

        // Check for static text
        let role = getElementValue(element, attribute: kAXRoleAttribute)
        if role == "AXStaticText" {
            if let staticText = getElementValue(element, attribute: kAXValueAttribute) {
                text += staticText + " "
            }
        }

        // Recurse into children
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                if text.count < maxVisibleTextLength {
                    text += extractTextFromElement(child, depth: depth + 1)
                }
            }
        }

        return String(text.prefix(maxVisibleTextLength))
    }

    // MARK: - Editor-Specific

    private func parseVSCodeFilePath(windowTitle: String) -> String? {
        // VS Code format: "filename — folder — Visual Studio Code"
        let parts = windowTitle.components(separatedBy: " — ")
        if parts.count >= 2 {
            return parts[0] // Filename
        }
        return nil
    }

    private func getEditorContent(axApp: AXUIElement) -> String {
        // Find text area in VS Code
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard let window = windowValue else { return "" }

        return findEditorText(window as! AXUIElement)
    }

    private func findEditorText(_ element: AXUIElement, depth: Int = 0) -> String {
        guard depth < 15 else { return "" }

        let role = getElementValue(element, attribute: kAXRoleAttribute)

        // VS Code uses AXTextArea or similar for editor
        if role == "AXTextArea" || role == "AXScrollArea" {
            if let value = getElementValue(element, attribute: kAXValueAttribute) {
                return String(value.prefix(maxVisibleTextLength))
            }
        }

        // Recurse
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                let text = findEditorText(child, depth: depth + 1)
                if !text.isEmpty {
                    return text
                }
            }
        }

        return ""
    }

    // MARK: - Terminal-Specific

    private func getTerminalContent(axApp: AXUIElement) -> String {
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard let window = windowValue else { return "" }

        return findTerminalText(window as! AXUIElement)
    }

    private func findTerminalText(_ element: AXUIElement, depth: Int = 0) -> String {
        guard depth < 10 else { return "" }

        let role = getElementValue(element, attribute: kAXRoleAttribute)

        // Terminal uses AXTextArea
        if role == "AXTextArea" {
            if let value = getElementValue(element, attribute: kAXValueAttribute) {
                // Get last portion (recent output)
                let lines = value.split(separator: "\n")
                let recentLines = lines.suffix(50)
                return String(recentLines.joined(separator: "\n").prefix(maxVisibleTextLength))
            }
        }

        // Recurse
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if childrenResult == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                let text = findTerminalText(child, depth: depth + 1)
                if !text.isEmpty {
                    return text
                }
            }
        }

        return ""
    }

    private func parseTerminalDirectory(windowTitle: String, content: String) -> String? {
        // Try to parse from window title first
        // Format often: "user@host: ~/path" or "~/path — Terminal"
        if let match = windowTitle.firstMatch(of: /[~\/][^\s—]+/) {
            return String(match.0)
        }

        // Try to find from prompt in content
        let lines = content.split(separator: "\n")
        if let lastPrompt = lines.last(where: { $0.contains("$") || $0.contains("%") }) {
            if let match = lastPrompt.firstMatch(of: /[~\/][^\s$%]+/) {
                return String(match.0)
            }
        }

        return nil
    }

    // MARK: - Finder-Specific

    private func getFinderPath(axApp: AXUIElement) -> String? {
        // Try to get path from window title or toolbar
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard let window = windowValue else { return nil }

        // Get document attribute (path)
        if let document = getElementValue(window as! AXUIElement, attribute: kAXDocumentAttribute) {
            return document
        }

        // Fall back to title
        return getElementValue(window as! AXUIElement, attribute: kAXTitleAttribute)
    }

    private func getFinderSelectedItems(axApp: AXUIElement) -> String? {
        // Get selected files/folders
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard let window = windowValue else { return nil }

        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSelectedChildrenAttribute as CFString, &selectedValue)

        if selectedResult == .success, let selected = selectedValue as? [AXUIElement] {
            let names = selected.compactMap { getElementValue($0, attribute: kAXTitleAttribute) }
            return names.joined(separator: ", ")
        }

        return nil
    }

    // MARK: - Generic

    private func getGenericVisibleText(axApp: AXUIElement) -> String {
        var windowValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard let window = windowValue else { return "" }

        return extractTextFromElement(window as! AXUIElement)
    }

    // MARK: - Fallback

    private func captureWithFallback(axContext: WindowContext, axApp: AXUIElement, appName: String, bundleId: String?, windowTitle: String) async -> WindowContext {
        // AX didn't get enough text - would trigger ScreenCapture + Vision here
        // For now, return what we have with fallback method noted

        return WindowContext(
            appName: axContext.appName,
            bundleIdentifier: axContext.bundleIdentifier,
            windowTitle: axContext.windowTitle,
            url: axContext.url,
            selectedText: axContext.selectedText,
            visibleText: axContext.visibleText,
            focusedElement: axContext.focusedElement,
            captureTime: Date(),
            captureMethod: axContext.visibleText.count < minTextLengthForFallback ? .fallback : .accessibility
        )
    }

    private func createEmptyContext(reason: String) -> WindowContext {
        return WindowContext(
            appName: "Unknown",
            bundleIdentifier: nil,
            windowTitle: reason,
            url: nil,
            selectedText: nil,
            visibleText: "",
            focusedElement: nil,
            captureTime: Date(),
            captureMethod: .fallback
        )
    }
}

// MARK: - Concurrency-Safe Helpers

/// Accessibility prompt options - built at file load time for concurrency safety
/// Using nonisolated(unsafe) because CFString/CFDictionary are not Sendable
/// The kAXTrustedCheckOptionPrompt value is literally "AXTrustedCheckOptionPrompt"
private nonisolated(unsafe) let accessibilityPromptOptions: CFDictionary = {
    let key = "AXTrustedCheckOptionPrompt" as CFString
    return [key: kCFBooleanTrue as Any] as CFDictionary
}()

/// Helper to get the accessibility prompt options safely
private nonisolated func getAccessibilityPromptOptions() -> CFDictionary {
    return accessibilityPromptOptions
}
