// CosmoOS/Editor/TextKitCoordinator.swift
// TextKit 2 integration for native macOS rich text editing
// Handles slash commands, @mentions, and live markdown

import SwiftUI
import AppKit

// MARK: - Custom NSTextView with Hyperlink Paste Support

/// Custom NSTextView that converts selected text to hyperlinks when a URL is pasted
class CosmoTextView: NSTextView {

    /// Override paste to support hyperlink creation on selected text
    override func paste(_ sender: Any?) {
        // Check if we have selected text and the pasteboard contains a URL
        let selectedRange = self.selectedRange()

        if selectedRange.length > 0,
           let pasteboardString = NSPasteboard.general.string(forType: .string),
           let url = URL(string: pasteboardString),
           url.scheme != nil,
           (url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto") {

            // Get the selected text
            guard let textStorage = self.textStorage,
                  selectedRange.location + selectedRange.length <= textStorage.length else {
                super.paste(sender)
                return
            }

            let selectedText = textStorage.attributedSubstring(from: selectedRange)

            // Create hyperlink attributed string
            let linkAttributes: [NSAttributedString.Key: Any] = [
                .link: url,
                .foregroundColor: NSColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: self.font ?? NSFont.systemFont(ofSize: 16)
            ]

            let hyperlinkString = NSAttributedString(
                string: selectedText.string,
                attributes: linkAttributes
            )

            // Replace selected text with hyperlinked version
            if shouldChangeText(in: selectedRange, replacementString: hyperlinkString.string) {
                textStorage.replaceCharacters(in: selectedRange, with: hyperlinkString)
                didChangeText()

                // Place cursor after the link
                let newCursorPosition = selectedRange.location + hyperlinkString.length
                setSelectedRange(NSRange(location: newCursorPosition, length: 0))

                print("🔗 Created hyperlink: \(selectedText.string) → \(url.absoluteString)")
            }
        } else {
            // Normal paste behavior
            super.paste(sender)
        }
    }
}

// MARK: - Scrollable CosmoTextView Factory

extension CosmoTextView {
    /// Creates a scrollable CosmoTextView (similar to NSTextView.scrollableTextView())
    static func scrollableCosmoTextView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = CosmoTextView()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView

        return scrollView
    }
}

// MARK: - TextKit 2 Editor Representable
struct TextKitEditorRepresentable: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    @Binding var cursorPosition: Int
    @Binding var shouldRefocus: Bool  // Trigger refocus from parent

    var fontSize: CGFloat = 16 // Default font size
    var darkMode: Bool = false  // Dark mode for Thinkspace blocks

    var onSlashCommand: ((CGPoint) -> Void)?
    var onMention: ((CGPoint, String) -> Void)?
    var onSelectionChange: ((NSRange, CGPoint) -> Void)?
    var onDismissMenus: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        // Use CosmoTextView for hyperlink paste support
        let scrollView = CosmoTextView.scrollableCosmoTextView()

        guard let textView = scrollView.documentView as? CosmoTextView else {
            return scrollView
        }

        // Configure TextKit 2 text view
        configureTextView(textView, context: context)

        // Set initial content
        textView.textStorage?.setAttributedString(attributedText)

        // Store reference for refocusing
        context.coordinator.textViewReference = textView
        context.coordinator.installScrollDismissObserver(for: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if content changed externally
        if textView.attributedString() != attributedText {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(selectedRange)
        }

        // Handle refocus request
        if shouldRefocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                self.shouldRefocus = false
            }
        }
    }

    private func configureTextView(_ textView: NSTextView, context: Context) {
        // Basic configuration
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFontPanel = true
        textView.usesRuler = false
        textView.importsGraphics = true
        textView.allowsImageEditing = true

        // Typography - colors depend on dark mode
        textView.font = NSFont.systemFont(ofSize: fontSize)
        if darkMode {
            // Thinkspace dark mode: white text on dark glass
            textView.textColor = NSColor.white
            textView.backgroundColor = NSColor.clear
            textView.insertionPointColor = NSColor.white
        } else {
            // Light mode: dark text
            textView.textColor = NSColor(CosmoColors.textPrimary) // #2D2D2D
            textView.backgroundColor = NSColor.clear
            textView.insertionPointColor = NSColor(CosmoColors.textPrimary)
        }

        // Spacing
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0

        // Enable smart features
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true

        // Paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        textView.defaultParagraphStyle = paragraphStyle

        // Set delegate
        textView.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextKitEditorRepresentable
        private var isProcessingSlashCommand = false
        private var mentionStartIndex: Int?
        weak var textViewReference: NSTextView?  // Store reference for refocusing
        private weak var scrollContentView: NSClipView?
        private var isInHeadingMode = false  // Track if we're in heading formatting mode

        init(_ parent: TextKitEditorRepresentable) {
            self.parent = parent
            super.init()

            // Dismiss menus when app loses focus (e.g., click outside to another app)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppWillResignActive(_:)),
                name: NSApplication.willResignActiveNotification,
                object: nil
            )

            // Cross-surface insertions (e.g. drag a related block into the editor)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertMentionInEditor(_:)),
                name: .insertMentionInEditor,
                object: nil
            )

            // Plain text insertions (e.g. research results, AI-generated content)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertTextInEditor(_:)),
                name: .insertTextInEditor,
                object: nil
            )

            // Handle typing attribute changes from slash commands
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSetTypingAttributes(_:)),
                name: .setEditorTypingAttributes,
                object: nil
            )

            // Handle slash command execution
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePerformSlashCommand(_:)),
                name: .performSlashCommand,
                object: nil
            )

            // Handle formatting toggles from menu
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleToggleFormatting(_:)),
                name: .toggleEditorFormatting,
                object: nil
            )
        }

        deinit {
            if let scrollContentView {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollContentView)
            }
            NotificationCenter.default.removeObserver(self, name: NSApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: .insertMentionInEditor, object: nil)
            NotificationCenter.default.removeObserver(self, name: .insertTextInEditor, object: nil)
            NotificationCenter.default.removeObserver(self, name: .insertTextInEditor, object: nil)
            NotificationCenter.default.removeObserver(self, name: .setEditorTypingAttributes, object: nil)
            NotificationCenter.default.removeObserver(self, name: .performSlashCommand, object: nil)
            NotificationCenter.default.removeObserver(self, name: .toggleEditorFormatting, object: nil)
        }

        /// Refocus the text view - called after menu selection
        func refocusEditor() {
            guard let textView = textViewReference else { return }
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        // MARK: - Text Did Change
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Update bindings
            parent.attributedText = textView.attributedString()
            parent.plainText = textView.string
            parent.cursorPosition = textView.selectedRange().location

            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            // === TELEPATHY ENGINE INTEGRATION ===
            // Feed typing input for shadow search and autocomplete
            Task {
                await TelepathyEngine.shared.handleTypingInput(text, cursorPosition: cursorLocation)
            }

            // === SLASH COMMAND HANDLING ===
            // Check if slash is still present when menu is active
            if isProcessingSlashCommand {
                // Find if there's still a "/" before cursor
                let hasSlash = cursorLocation > 0 && {
                    let checkIndex = text.index(text.startIndex, offsetBy: cursorLocation - 1, limitedBy: text.endIndex)
                    if let idx = checkIndex, idx < text.endIndex {
                        return text[idx] == "/"
                    }
                    return false
                }()

                if !hasSlash {
                    // Slash was deleted - dismiss menu
                    isProcessingSlashCommand = false
                    dismissMenus()
                }
            }

            // === MENTION HANDLING ===
            // Check if @ is still present when menu is active
            if let startIndex = mentionStartIndex {
                // Verify @ is still at the start position
                let atStillExists = startIndex < text.count && {
                    let atIndex = text.index(text.startIndex, offsetBy: startIndex, limitedBy: text.endIndex)
                    if let idx = atIndex, idx < text.endIndex {
                        return text[idx] == "@"
                    }
                    return false
                }()

                if !atStillExists || cursorLocation <= startIndex {
                    // @ was deleted or cursor moved before it - dismiss menu
                    mentionStartIndex = nil
                    dismissMenus()
                }
            }

            // Check for new triggers
            if cursorLocation > 0 {
                let index = text.index(text.startIndex, offsetBy: cursorLocation - 1, limitedBy: text.endIndex) ?? text.endIndex
                if index < text.endIndex {
                    let char = text[index]

                    // New slash command trigger
                    if char == "/" && !isProcessingSlashCommand {
                        let isValidTrigger = cursorLocation == 1 || {
                            let prevIndex = text.index(text.startIndex, offsetBy: cursorLocation - 2, limitedBy: text.endIndex)
                            if let prevIndex = prevIndex {
                                let prevChar = text[prevIndex]
                                return prevChar.isWhitespace || prevChar.isNewline
                            }
                            return true
                        }()

                        if isValidTrigger {
                            let rect = textView.firstRect(forCharacterRange: NSRange(location: cursorLocation - 1, length: 1), actualRange: nil)
                            let position = textView.convert(NSPoint(x: rect.origin.x, y: rect.origin.y + rect.height), from: nil)
                            parent.onSlashCommand?(position)
                            isProcessingSlashCommand = true
                        }
                    }

                    // New @ mention trigger
                    if char == "@" && mentionStartIndex == nil {
                        mentionStartIndex = cursorLocation - 1
                        let rect = textView.firstRect(forCharacterRange: NSRange(location: cursorLocation - 1, length: 1), actualRange: nil)
                        let position = textView.convert(NSPoint(x: rect.origin.x, y: rect.origin.y + rect.height), from: nil)
                        parent.onMention?(position, "")
                    }

                    // Update mention search query
                    if let startIndex = mentionStartIndex, cursorLocation > startIndex {
                        let queryStart = text.index(text.startIndex, offsetBy: startIndex + 1)
                        let queryEnd = text.index(text.startIndex, offsetBy: cursorLocation)
                        let query = String(text[queryStart..<queryEnd])

                        if !query.contains(" ") && !query.contains("\n") {
                            let rect = textView.firstRect(forCharacterRange: NSRange(location: startIndex, length: 1), actualRange: nil)
                            let position = textView.convert(NSPoint(x: rect.origin.x, y: rect.origin.y + rect.height), from: nil)
                            parent.onMention?(position, query)
                        } else {
                            mentionStartIndex = nil
                            dismissMenus()
                        }
                    }
                }
            }

            // Apply live markdown shortcuts and formatting
            applyMarkdownShortcuts(textView)
            applyMarkdownFormatting(textView)
        }

        // MARK: - Markdown Shortcuts (Live Transformations)
        /// Transform common shortcuts into formatted elements as you type
        private func applyMarkdownShortcuts(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            // Get the current line
            let lineRange = (text as NSString).lineRange(for: NSRange(location: max(0, cursorLocation - 1), length: 0))
            let currentLine = (text as NSString).substring(with: lineRange)

            // === "- " at start of line → bullet point "• " ===
            if currentLine.hasPrefix("- ") && cursorLocation >= lineRange.location + 2 {
                let replaceRange = NSRange(location: lineRange.location, length: 2)
                textStorage.replaceCharacters(in: replaceRange, with: "• ")
                textView.setSelectedRange(NSRange(location: lineRange.location + 2, length: 0))
            }

            // === "-> " → arrow "→ " ===
            if currentLine.contains("-> ") {
                let range = (text as NSString).range(of: "-> ", options: [], range: lineRange)
                if range.location != NSNotFound {
                    textStorage.replaceCharacters(in: range, with: "→ ")
                    // Adjust cursor
                    if cursorLocation > range.location {
                        textView.setSelectedRange(NSRange(location: cursorLocation - 1, length: 0))
                    }
                }
            }

            // === "<- " → arrow "← " ===
            if currentLine.contains("<- ") {
                let range = (text as NSString).range(of: "<- ", options: [], range: lineRange)
                if range.location != NSNotFound {
                    textStorage.replaceCharacters(in: range, with: "← ")
                    if cursorLocation > range.location {
                        textView.setSelectedRange(NSRange(location: cursorLocation - 1, length: 0))
                    }
                }
            }

            // === "---" at start of line → divider "───────────────" ===
            if currentLine.trimmingCharacters(in: .whitespaces) == "---" {
                let divider = "\n───────────────\n"
                textStorage.replaceCharacters(in: lineRange, with: divider)
                textView.setSelectedRange(NSRange(location: lineRange.location + divider.count, length: 0))
            }

            // === "* " at start of line → bullet point "• " ===
            if currentLine.hasPrefix("* ") && !currentLine.hasPrefix("**") && cursorLocation >= lineRange.location + 2 {
                let replaceRange = NSRange(location: lineRange.location, length: 2)
                textStorage.replaceCharacters(in: replaceRange, with: "• ")
                textView.setSelectedRange(NSRange(location: lineRange.location + 2, length: 0))
            }

            // === "1. " → numbered list (keep as-is but add proper spacing) ===
            // Already handled by default behavior

            // === "[] " or "[ ] " → checkbox "☐ " ===
            if currentLine.hasPrefix("[] ") {
                let replaceRange = NSRange(location: lineRange.location, length: 3)
                textStorage.replaceCharacters(in: replaceRange, with: "☐ ")
                textView.setSelectedRange(NSRange(location: lineRange.location + 2, length: 0))
            } else if currentLine.hasPrefix("[ ] ") {
                let replaceRange = NSRange(location: lineRange.location, length: 4)
                textStorage.replaceCharacters(in: replaceRange, with: "☐ ")
                textView.setSelectedRange(NSRange(location: lineRange.location + 2, length: 0))
            }

            // === "[x] " → checked checkbox "☑ " ===
            if currentLine.hasPrefix("[x] ") || currentLine.hasPrefix("[X] ") {
                let replaceRange = NSRange(location: lineRange.location, length: 4)
                textStorage.replaceCharacters(in: replaceRange, with: "☑ ")
                textView.setSelectedRange(NSRange(location: lineRange.location + 2, length: 0))
            }
        }

        // MARK: - Markdown Formatting
        @MainActor
        private func applyMarkdownFormatting(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let text = textView.string
            let selectedRange = textView.selectedRange()

            // Bold: **text** or __text__
            applyPattern(
                pattern: "\\*\\*(.+?)\\*\\*|__(.+?)__",
                to: textStorage,
                in: text,
                attributes: [.font: NSFont.boldSystemFont(ofSize: 16)]
            )

            // Italic: *text* or _text_
            applyPattern(
                pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)",
                to: textStorage,
                in: text,
                attributes: [.font: NSFont.systemFont(ofSize: 16).italic()]
            )

            // Inline code: `code`
            applyPattern(
                pattern: "`(.+?)`",
                to: textStorage,
                in: text,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor
                ]
            )

            // Headers: # ## ###
            applyHeaderFormatting(textStorage, text: text)

            // Restore selection
            textView.setSelectedRange(selectedRange)
        }

        private func applyPattern(
            pattern: String,
            to textStorage: NSTextStorage,
            in text: String,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                textStorage.addAttributes(attributes, range: match.range)
            }
        }

        private func applyHeaderFormatting(_ textStorage: NSTextStorage, text: String) {
            let lines = text.components(separatedBy: .newlines)
            var currentLocation = 0

            for line in lines {
                if line.hasPrefix("### ") {
                    let range = NSRange(location: currentLocation, length: line.count)
                    textStorage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 18, weight: .semibold)
                    ], range: range)
                } else if line.hasPrefix("## ") {
                    let range = NSRange(location: currentLocation, length: line.count)
                    textStorage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 22, weight: .semibold)
                    ], range: range)
                } else if line.hasPrefix("# ") {
                    let range = NSRange(location: currentLocation, length: line.count)
                    textStorage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 28, weight: .bold)
                    ], range: range)
                }

                currentLocation += line.count + 1 // +1 for newline
            }
        }

        // MARK: - Key Events
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Escape to dismiss menus
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                dismissMenus()
                return true
            }

            // Handle Formatting Shortcuts (Cmd+B, Cmd+I) manually to ensure consistency
            if commandSelector == #selector(NSFontManager.addFontTrait(_:)) {
               // This selector is tricky to catch directly without the sender logic
            }
            
            if commandSelector == NSSelectorFromString("toggleBold:") {
                toggleBold()
                return true
            }
            if commandSelector == NSSelectorFromString("toggleItalic:") {
                toggleItalic()
                return true
            }


            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if isProcessingSlashCommand {
                    isProcessingSlashCommand = false
                    return false
                }

                // If in heading mode, reset to normal formatting after Enter
                if isInHeadingMode {
                    // Let the newline be inserted first, then reset formatting
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, let textView = self.textViewReference else { return }
                        self.resetToNormalTypingAttributes(textView)
                    }
                    return false  // Allow the newline to be inserted
                }
            }

            return false
        }

        // MARK: - Selection Did Change
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange = textView.selectedRange()
            
            // Defer state updates to avoid "modifying state during view update"
            DispatchQueue.main.async { [weak self] in
                self?.parent.cursorPosition = selectedRange.location
            }
            
            // Notify parent about selection for Floating Formatting Menu
            if selectedRange.length > 0 {
                let rect = textView.firstRect(forCharacterRange: selectedRange, actualRange: nil)
                // Convert to screen/window coordinates for overlay
                let position = textView.convert(NSPoint(x: rect.origin.x, y: rect.origin.y), from: nil)
                // Position above the selection - defer to avoid state modification during update
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onSelectionChange?(selectedRange, position)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onSelectionChange?(NSRange(location: NSNotFound, length: 0), .zero)
                }
            }
        }

        // MARK: - Link Click Handling
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Handle cosmo:// links - open as floating block in document
            let urlString: String?
            if let url = link as? URL {
                urlString = url.absoluteString
            } else if let str = link as? String {
                urlString = str
            } else {
                urlString = nil
            }

            guard let urlString = urlString,
                  let url = URL(string: urlString),
                  url.scheme == "cosmo" else {
                return false  // Let system handle other links
            }

            // Parse entity type and ID from URL: cosmo://idea/123
            guard let entityTypeString = url.host,
                  let entityType = EntityType(rawValue: entityTypeString),
                  let entityIdString = url.pathComponents.last,
                  let entityId = Int64(entityIdString) else {
                return false
            }

            // Post notification to open as floating block in current document
            NotificationCenter.default.post(
                name: .openMentionAsFloatingBlock,
                object: nil,
                userInfo: [
                    "entityType": entityType,
                    "entityId": entityId
                ]
            )

            return true  // We handled this link
        }

        // MARK: - Dismissal + Scroll Handling

        @MainActor
        func installScrollDismissObserver(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollContentView = scrollView.contentView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleEditorScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        @MainActor
        private func dismissMenus() {
            isProcessingSlashCommand = false
            mentionStartIndex = nil
            parent.onDismissMenus?()
        }

        @MainActor
        @objc private func handleEditorScroll(_ notification: Notification) {
            // If the user scrolls while a menu is open, treat it as "leave this transient UI"
            dismissMenus()
        }

        @MainActor
        @objc private func handleAppWillResignActive(_ notification: Notification) {
            dismissMenus()
        }

        @MainActor
        @objc private func handleInsertMentionInEditor(_ notification: Notification) {
            guard let textView = textViewReference else { return }

            // Only the active editor should respond.
            guard textView.window?.firstResponder === textView else { return }

            guard
                let rawType = notification.userInfo?["entityType"] as? String,
                let type = EntityType(rawValue: rawType),
                let title = notification.userInfo?["title"] as? String
            else { return }

            let id: Int64
            if let id64 = notification.userInfo?["entityId"] as? Int64 {
                id = id64
            } else if let idInt = notification.userInfo?["entityId"] as? Int {
                id = Int64(idInt)
            } else {
                return
            }

            insertMention(entityType: type, entityId: id, title: title, into: textView)
        }

        @MainActor
        @objc private func handleInsertTextInEditor(_ notification: Notification) {
            guard let textView = textViewReference else { return }

            // Only the active editor should respond
            guard textView.window?.firstResponder === textView else { return }

            guard let text = notification.userInfo?["text"] as? String else { return }
            let positionRaw = notification.userInfo?["position"] as? String ?? "cursor"

            insertText(text, position: positionRaw, into: textView)
        }

        /// Insert plain text at the specified position
        @MainActor
        private func insertText(_ text: String, position: String, into textView: NSTextView) {
            let storage = textView.textStorage
            guard let storage = storage else { return }

            let insertRange: NSRange
            switch position {
            case "end":
                insertRange = NSRange(location: storage.length, length: 0)
            case "newParagraph":
                // Insert at current cursor, but add newlines before
                let cursorLocation = textView.selectedRange().location
                let prefixedText = "\n\n" + text
                insertRange = NSRange(location: cursorLocation, length: 0)

                storage.beginEditing()
                storage.replaceCharacters(in: insertRange, with: prefixedText)
                storage.endEditing()

                // Move cursor to end of inserted text
                let newCursor = cursorLocation + prefixedText.count
                textView.setSelectedRange(NSRange(location: newCursor, length: 0))

                parent.attributedText = textView.attributedString()
                parent.plainText = textView.string
                return
            default: // "cursor"
                insertRange = textView.selectedRange()
            }

            storage.beginEditing()
            storage.replaceCharacters(in: insertRange, with: text)
            storage.endEditing()

            // Move cursor to end of inserted text
            let newCursor = insertRange.location + text.count
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))

            parent.attributedText = textView.attributedString()
            parent.plainText = textView.string
        }

        @MainActor
        @objc private func handleSetTypingAttributes(_ notification: Notification) {
            guard let textView = textViewReference else { return }
            
            // Check if this editor is the active one OR if no one is first responder yet
            // This allows the notification to work right after refocusing
            let isActiveEditor = textView.window?.firstResponder === textView
            let noFirstResponder = textView.window?.firstResponder == nil
            
            // Only skip if another text view is the first responder
            if !isActiveEditor && !noFirstResponder {
                if let firstResponder = textView.window?.firstResponder as? NSTextView,
                   firstResponder !== textView {
                    return  // Another editor is active
                }
            }

            guard let userInfo = notification.userInfo,
                  let font = userInfo["font"] as? NSFont,
                  let color = userInfo["color"] as? NSColor else { return }

            let isHeading = userInfo["isHeading"] as? Bool ?? false
            isInHeadingMode = isHeading

            // Set typing attributes so next typed characters use this style
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            
            // If heading, add paragraph styling for spacing
            if isHeading {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4
                paragraphStyle.paragraphSpacing = 12 // More spacing after headers
                paragraphStyle.paragraphSpacingBefore = 16
                attributes[.paragraphStyle] = paragraphStyle
                
                // ALSO apply to the current paragraph range immediately
                let range = textView.selectedRange()
                let lineRange = (textView.string as NSString).lineRange(for: range)
                textView.textStorage?.addAttributes(attributes, range: lineRange)
            }

            textView.typingAttributes = attributes
            
            // Update parent binding
            parent.attributedText = textView.attributedString()
        }

        /// Reset typing attributes to normal body style
        @MainActor
        private func resetToNormalTypingAttributes(_ textView: NSTextView) {
            isInHeadingMode = false

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 8

            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: parent.fontSize),
                .foregroundColor: NSColor(CosmoColors.textPrimary),
                .paragraphStyle: paragraphStyle
            ]
        }

        @MainActor
        @objc private func handleToggleFormatting(_ notification: Notification) {
            guard let textView = textViewReference,
                  let userInfo = notification.userInfo,
                  let type = userInfo["type"] as? FormattingType else { return }
            
            // Ensure we are the first responder
            guard textView.window?.firstResponder === textView else { return }
            
            let range = textView.selectedRange()
            guard let textStorage = textView.textStorage else { return }

            switch type {
            case .bold:
                toggleBold() // Use helper
            case .italic:
                toggleItalic()
            case .strikethrough:
                toggleStrikethrough(range: range, storage: textStorage)
            case .heading1:
                applyHeading(level: 1, textView: textView)
            case .heading2:
                applyHeading(level: 2, textView: textView)
            case .bulletList:
                // Simple bullet insertion for selection
                // Real implementation would be complex logic to wrap lines
                // For now, toggle bullet at start of line
                toggleBulletList(textView: textView)
            }
            
            // Force update binding
            parent.attributedText = textView.attributedString()
        }
        
        func toggleBold() {
            guard let textView = textViewReference else { return }
            let range = textView.selectedRange()
            let currentFontSize = parent.fontSize
            
            if range.length > 0 {
                // Apply to selection
                textView.textStorage?.applyFontTraits(.boldFontMask, range: range)
            } else {
                // Toggle typing attributes for cursor position
                let font = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: currentFontSize)
                let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                let newFont = isBold ? 
                    NSFont.systemFont(ofSize: font.pointSize) :
                    NSFont.boldSystemFont(ofSize: font.pointSize)
                
                var attributes = textView.typingAttributes
                attributes[.font] = newFont
                textView.typingAttributes = attributes
            }
            
            // Force update binding
            parent.attributedText = textView.attributedString()
        }

        // Helper for Italic
        func toggleItalic() {
            guard let textView = textViewReference else { return }
            let range = textView.selectedRange()
            let currentFontSize = parent.fontSize
            
            if range.length > 0 {
                // Apply to selection
                textView.textStorage?.applyFontTraits(.italicFontMask, range: range)
            } else {
                // Toggle typing attributes for cursor position
                let font = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: currentFontSize)
                let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                let newFont = isItalic ? 
                    NSFont.systemFont(ofSize: font.pointSize) :
                    (NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize) ?? font)
                
                var attributes = textView.typingAttributes
                attributes[.font] = newFont
                textView.typingAttributes = attributes
            }
            
            // Force update binding
            parent.attributedText = textView.attributedString()
        }
        
        func toggleStrikethrough(range: NSRange, storage: NSTextStorage) {
            if range.length == 0 { return }
            // Check if already struck through
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            if attributes[.strikethroughStyle] != nil {
                storage.removeAttribute(.strikethroughStyle, range: range)
            } else {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        
        @MainActor
        func applyHeading(level: Int, textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let font = level == 1 ? NSFont.systemFont(ofSize: 28, weight: .bold) : NSFont.systemFont(ofSize: 22, weight: .semibold)
            let color = NSColor(CosmoColors.textPrimary)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 12
            paragraphStyle.paragraphSpacingBefore = 16

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]

            // Set heading mode flag so Enter key resets to normal
            isInHeadingMode = true

            let range = textView.selectedRange()
            let text = textView.string
            let lineRange = (text as NSString).lineRange(for: range)
            let currentLine = (text as NSString).substring(with: lineRange)

            // Determine the markdown prefix for this heading level
            let markdownPrefix = level == 1 ? "# " : "## "

            // Check if line already has a heading prefix
            let hasH1 = currentLine.hasPrefix("# ") && !currentLine.hasPrefix("## ")
            let hasH2 = currentLine.hasPrefix("## ")

            // Remove existing heading prefix if present (toggle or change level)
            if hasH1 || hasH2 {
                let existingPrefix = hasH2 ? "## " : "# "
                let prefixRange = NSRange(location: lineRange.location, length: existingPrefix.count)
                textStorage.replaceCharacters(in: prefixRange, with: "")

                // If same level, we're toggling off - reset to normal formatting
                if (level == 1 && hasH1) || (level == 2 && hasH2) {
                    isInHeadingMode = false
                    resetToNormalTypingAttributes(textView)

                    // Re-calculate line range after removal and apply normal formatting
                    let newLineRange = (textView.string as NSString).lineRange(for: NSRange(location: lineRange.location, length: 0))
                    let normalAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: parent.fontSize),
                        .foregroundColor: NSColor(CosmoColors.textPrimary)
                    ]
                    if newLineRange.length > 0 {
                        textStorage.addAttributes(normalAttrs, range: newLineRange)
                    }
                    parent.attributedText = textView.attributedString()
                    parent.plainText = textView.string
                    return
                }

                // Different level - insert the new prefix
                textStorage.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: markdownPrefix)
            } else {
                // No heading prefix - insert it at start of line
                textStorage.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: markdownPrefix)
            }

            // Recalculate line range after insertion
            let newLineRange = (textView.string as NSString).lineRange(for: NSRange(location: lineRange.location, length: 0))

            // Apply visual attributes to the line
            if newLineRange.length > 0 {
                textStorage.addAttributes(attributes, range: newLineRange)
            }

            // Set typing attributes so new text uses heading style
            textView.typingAttributes = attributes

            // Move cursor to end of line (after any existing text)
            let endOfLine = newLineRange.location + newLineRange.length
            // Account for newline character at end
            let cursorPos = max(newLineRange.location + markdownPrefix.count, endOfLine > 0 ? endOfLine - 1 : endOfLine)
            textView.setSelectedRange(NSRange(location: cursorPos, length: 0))

            // Update parent binding to persist changes
            parent.attributedText = textView.attributedString()
            parent.plainText = textView.string
        }
        
        func toggleBulletList(textView: NSTextView) {
             // Basic toggle: Check start of line for "• "
             let range = textView.selectedRange()
             let lineRange = (textView.string as NSString).lineRange(for: range)
             let currentLine = (textView.string as NSString).substring(with: lineRange)
             
             if currentLine.hasPrefix("• ") {
                 textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 2), with: "")
             } else {
                 textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "• ")
             }
        }
        
        @MainActor
        @objc private func handlePerformSlashCommand(_ notification: Notification) {
            guard let textView = textViewReference else { return }
            
            // Loose check for focus to handle timing issues with overlay dismissal
            let isActiveEditor = textView.window?.firstResponder === textView
            let noFirstResponder = textView.window?.firstResponder == nil
             
            if !isActiveEditor && !noFirstResponder {
                if let firstResponder = textView.window?.firstResponder as? NSTextView,
                   firstResponder !== textView {
                    return
                }
            }

            guard let userInfo = notification.userInfo,
                  let command = userInfo["command"] as? SlashCommand,
                  let textStorage = textView.textStorage else { return }

            // 1. Remove the "/" trigger
            let cursorLocation = textView.selectedRange().location
            let text = textView.string
            var insertLocation = cursorLocation
            
            // Find the slash before the cursor (usually at cursorLocation - 1)
            if cursorLocation > 0 {
                let range = NSRange(location: cursorLocation - 1, length: 1)
                // Verify it's a slash
                if range.location < text.count {
                    let char = (text as NSString).substring(with: range)
                    if char == "/" {
                        textStorage.replaceCharacters(in: range, with: "")
                        insertLocation = range.location
                        // Update selection to reflect removal before proceeding
                        textView.setSelectedRange(NSRange(location: insertLocation, length: 0))
                    }
                }
            }
            
            let textColor = NSColor(CosmoColors.textPrimary)
            let secondaryColor = NSColor(CosmoColors.textSecondary)
            let tertiaryColor = NSColor(CosmoColors.textTertiary)

            switch command.type {
            case .heading1:
                applyHeading(level: 1, textView: textView)
            case .heading2:
                applyHeading(level: 2, textView: textView)
            case .bulletList:
                let bullet = NSAttributedString(string: "• ", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: textColor])
                textStorage.insert(bullet, at: insertLocation)
                // Move cursor after insertion
                textView.setSelectedRange(NSRange(location: insertLocation + bullet.length, length: 0))
            case .numberedList:
                let number = NSAttributedString(string: "1. ", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: textColor])
                textStorage.insert(number, at: insertLocation)
                textView.setSelectedRange(NSRange(location: insertLocation + number.length, length: 0))
            case .checkbox:
                let checkbox = NSAttributedString(string: "☐ ", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: textColor])
                textStorage.insert(checkbox, at: insertLocation)
                textView.setSelectedRange(NSRange(location: insertLocation + checkbox.length, length: 0))
            case .quote:
                let quote = NSAttributedString(string: "│ ", attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .light), .foregroundColor: secondaryColor])
                textStorage.insert(quote, at: insertLocation)
                textView.setSelectedRange(NSRange(location: insertLocation + quote.length, length: 0))
            case .code:
                let code = NSAttributedString(string: "```\n\n```", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: textColor, .backgroundColor: NSColor(CosmoColors.glassGrey.opacity(0.3))])
                textStorage.insert(code, at: insertLocation)
                textView.setSelectedRange(NSRange(location: insertLocation + 4, length: 0)) // Position inside code block
            case .divider:
                let divider = NSAttributedString(string: "\n───────────────\n", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: tertiaryColor])
                textStorage.insert(divider, at: insertLocation)
                textView.setSelectedRange(NSRange(location: insertLocation + divider.length, length: 0))
            case .callout:
                let callout = NSAttributedString(string: "💡 ", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: textColor])
                textStorage.insert(callout, at: insertLocation)
                textView.setSelectedRange(NSRange(location: insertLocation + callout.length, length: 0))
            case .linkIdea, .linkTask, .linkContent:
                break
            }
            
            // 3. Update bindings
            parent.attributedText = textView.attributedString()
            parent.plainText = textView.string
            parent.cursorPosition = textView.selectedRange().location
        }

        @MainActor
        private func insertMention(entityType: EntityType, entityId: Int64, title: String, into textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let color = CosmoMentionColors.nsColor(for: entityType)
            let mention = NSMutableAttributedString(
                string: "@\(title)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: color,
                    .link: "cosmo://\(entityType.rawValue)/\(entityId)",
                    .backgroundColor: color.withAlphaComponent(0.1),
                    .underlineStyle: 0,
                    NSAttributedString.Key("CosmoEntityType"): entityType.rawValue,
                    NSAttributedString.Key("CosmoEntityId"): entityId
                ]
            )

            // Add a trailing space for flow.
            mention.append(NSAttributedString(
                string: " ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor(CosmoColors.textPrimary)
                ]
            ))

            let selectedRange = textView.selectedRange()
            storage.replaceCharacters(in: selectedRange, with: mention)

            // Move cursor to end of inserted mention
            let newCursor = selectedRange.location + mention.length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))

            // Sync bindings
            parent.attributedText = textView.attributedString()
            parent.plainText = textView.string
            parent.cursorPosition = newCursor
        }
    }
}

// MARK: - NSFont Italic Extension
// Moved to CosmoMarkdown.swift

