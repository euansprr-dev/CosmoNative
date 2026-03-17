// CosmoOS/Editor/TextKitCoordinator.swift
// Shared TextKit editor infrastructure for rich writing surfaces.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
fileprivate protocol CosmoTextViewShortcutDelegate: AnyObject {
    func textViewDidRequestFormattingShortcut(_ shortcut: FormattingType)
    func textView(_ textView: NSTextView, shouldHandleImagePaste pasteboard: NSPasteboard) -> Bool
}

// MARK: - Custom NSTextView

final class CosmoTextView: NSTextView {
    fileprivate weak var shortcutDelegate: CosmoTextViewShortcutDelegate?

    override func paste(_ sender: Any?) {
        let selectedRange = self.selectedRange()

        if selectedRange.length > 0,
           let pasteboardString = NSPasteboard.general.string(forType: .string),
           let url = URL(string: pasteboardString),
           let scheme = url.scheme,
           ["http", "https", "mailto"].contains(scheme) {
            guard let textStorage = textStorage,
                  selectedRange.location + selectedRange.length <= textStorage.length else {
                super.paste(sender)
                return
            }

            let selectedText = textStorage.attributedSubstring(from: selectedRange)
            let hyperlinkString = NSAttributedString(
                string: selectedText.string,
                attributes: [
                    .link: url,
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .font: font ?? NSFont.systemFont(ofSize: 16)
                ]
            )

            if shouldChangeText(in: selectedRange, replacementString: hyperlinkString.string) {
                textStorage.replaceCharacters(in: selectedRange, with: hyperlinkString)
                didChangeText()
                setSelectedRange(NSRange(location: selectedRange.location + hyperlinkString.length, length: 0))
            }
            return
        }

        if shortcutDelegate?.textView(self, shouldHandleImagePaste: NSPasteboard.general) == true {
            return
        }

        super.paste(sender)
    }

    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to the outer SwiftUI ScrollView.
        // The enclosing NSScrollView doesn't scroll (text view grows to fit),
        // so we skip it and forward to the next responder in the chain.
        if let scrollView = enclosingScrollView {
            scrollView.nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch chars {
        case "b":
            shortcutDelegate?.textViewDidRequestFormattingShortcut(.bold)
            return true
        case "i":
            shortcutDelegate?.textViewDidRequestFormattingShortcut(.italic)
            return true
        case "u":
            shortcutDelegate?.textViewDidRequestFormattingShortcut(.underline)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

extension CosmoTextView {
    static func scrollableCosmoTextView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
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

// MARK: - Representable

struct TextKitEditorRepresentable: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    @Binding var cursorPosition: Int
    @Binding var shouldRefocus: Bool

    var fontSize: CGFloat = 16
    var compact: Bool = false
    var darkMode: Bool = false
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowImages: Bool = true
    var allowSelectionMenu: Bool = true
    var singleLine: Bool = false
    var baseFontWeight: NSFont.Weight = .regular
    var polishHighlights: WritingAnalysis? = nil
    var textAlignment: NSTextAlignment = .natural

    var onSlashCommand: ((CGPoint) -> Void)?
    var onMention: ((CGPoint, String) -> Void)?
    var onSelectionChange: ((EditorSelectionSnapshot) -> Void)?
    var onDismissMenus: (() -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CosmoTextView.scrollableCosmoTextView()

        guard let textView = scrollView.documentView as? CosmoTextView else {
            return scrollView
        }

        configureTextView(textView, context: context, isInitial: true)
        textView.textStorage?.setAttributedString(attributedText)
        context.coordinator.applyPolishHighlights(to: textView)
        context.coordinator.textViewReference = textView
        context.coordinator.installScrollDismissObserver(for: scrollView)
        context.coordinator.normalizeSingleLineViewport(for: textView)
        context.coordinator.notifyContentHeightChange(for: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CosmoTextView else { return }
        context.coordinator.parent = self
        configureTextView(textView, context: context, isInitial: false)

        // Skip text storage replacement when the change originated from user typing —
        // the text view already has the correct content, avoiding scroll position resets.
        guard !context.coordinator.isUpdatingFromTextView else {
            context.coordinator.applyPolishHighlights(to: textView)
            if shouldRefocus {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                    self.shouldRefocus = false
                }
            }
            return
        }

        if !textView.attributedString().isEqual(to: attributedText) {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            let safeLocation = min(selectedRange.location, textView.string.count)
            let safeLength = min(selectedRange.length, textView.string.count - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            context.coordinator.normalizeSingleLineViewport(for: textView)
            context.coordinator.notifyContentHeightChange(for: textView)
        }

        context.coordinator.applyPolishHighlights(to: textView)
        context.coordinator.normalizeSingleLineViewport(for: textView)

        if shouldRefocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                self.shouldRefocus = false
            }
        }
    }

    private func configureTextView(_ textView: CosmoTextView, context: Context, isInitial: Bool = true) {
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.importsGraphics = allowImages
        textView.allowsImageEditing = allowImages
        textView.drawsBackground = false

        // Only set font/textColor/alignment on initial setup.
        // Setting these on every update overwrites the entire text storage,
        // destroying any rich text formatting (bold, italic, etc.).
        if isInitial {
            textView.font = resolvedBaseFont()
            textView.textColor = darkMode ? .white : NSColor(CosmoColors.textPrimary)
            textView.alignment = textAlignment
            textView.defaultParagraphStyle = baseParagraphStyle()
            textView.typingAttributes = defaultTypingAttributes()
        }

        textView.backgroundColor = .clear
        textView.insertionPointColor = darkMode ? .white : NSColor(CosmoColors.textPrimary)
        textView.textContainerInset = resolvedTextInsets()
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = !singleLine
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: singleLine ? resolvedSingleLineHeight() : CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: singleLine ? resolvedSingleLineHeight() : 0)
        // For multi-line mode, preserve the current container width (tracked from the text view)
        // so word-wrapping works correctly. Only override height.
        let currentContainerWidth = textView.textContainer?.containerSize.width ?? textView.frame.width
        let containerWidth = singleLine ? CGFloat.greatestFiniteMagnitude : max(1, currentContainerWidth)
        textView.textContainer?.containerSize = NSSize(
            width: containerWidth,
            height: singleLine ? resolvedSingleLineHeight() : CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.maximumNumberOfLines = singleLine ? 1 : 0
        textView.textContainer?.lineBreakMode = singleLine ? .byClipping : .byWordWrapping

        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true

        textView.delegate = context.coordinator
        textView.shortcutDelegate = context.coordinator
    }

    private func baseParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = singleLine ? 0 : 4
        style.paragraphSpacing = singleLine ? 0 : 8
        return style
    }

    private func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: resolvedBaseFont(),
            .foregroundColor: darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    private func resolvedBaseFont() -> NSFont {
        NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
    }

    private func resolvedTextInsets() -> NSSize {
        if singleLine {
            return NSSize(width: compact ? 0 : 2, height: compact ? 4 : max(4, floor(fontSize * 0.12)))
        }
        if compact {
            return NSSize(width: 10, height: 8)
        }
        return NSSize(width: 16, height: 16)
    }

    private func resolvedSingleLineHeight() -> CGFloat {
        let font = resolvedBaseFont()
        let insets = resolvedTextInsets().height * 2
        return ceil(font.ascender - font.descender + font.leading + insets + 2)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, CosmoTextViewShortcutDelegate {
        var parent: TextKitEditorRepresentable

        weak var textViewReference: CosmoTextView?

        private weak var scrollContentView: NSClipView?
        private var mentionStartIndex: Int?
        private var isInHeadingMode = false
        private var hasAppliedHighlights = false
        /// Guards against updateNSView round-trip when change originated from user typing
        var isUpdatingFromTextView = false
        private var deferredSyncWorkItem: DispatchWorkItem?
        private var lastReportedHeight: CGFloat = 0
        private var selectionChangeWorkItem: DispatchWorkItem?

        init(_ parent: TextKitEditorRepresentable) {
            self.parent = parent
            super.init()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppWillResignActive(_:)),
                name: NSApplication.willResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertMentionInEditor(_:)),
                name: .insertMentionInEditor,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePerformMentionSelection(_:)),
                name: .performMentionSelection,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInsertTextInEditor(_:)),
                name: .insertTextInEditor,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSetTypingAttributes(_:)),
                name: .setEditorTypingAttributes,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePerformSlashCommand(_:)),
                name: .performSlashCommand,
                object: nil
            )
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
            NotificationCenter.default.removeObserver(self)
        }

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

        func applyPolishHighlights(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            if parent.polishHighlights == nil {
                guard hasAppliedHighlights else { return }
                storage.beginEditing()
                storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
                hasAppliedHighlights = false
                return
            }

            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)

            if let analysis = parent.polishHighlights {
                for range in analysis.complexSentenceRanges where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.15), range: range)
                }
                for range in analysis.veryComplexSentenceRanges where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: NSColor.red.withAlphaComponent(0.15), range: range)
                }
                for range in analysis.passiveVoiceRanges where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.15), range: range)
                }
                for range in analysis.adverbRanges where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: NSColor.purple.withAlphaComponent(0.15), range: range)
                }
            }

            storage.endEditing()
            hasAppliedHighlights = true
        }

        // MARK: - Shortcut Delegate

        func textViewDidRequestFormattingShortcut(_ shortcut: FormattingType) {
            guard let textView = textViewReference,
                  textView.window?.firstResponder === textView else { return }
            applyFormatting(shortcut, to: textView)
        }

        func textView(_ textView: NSTextView, shouldHandleImagePaste pasteboard: NSPasteboard) -> Bool {
            guard parent.allowImages else { return false }

            if let image = NSImage(pasteboard: pasteboard),
               let data = image.pngData() ?? image.tiffRepresentation {
                insertImage(data: data, filename: "Pasted Image.png", into: textView)
                return true
            }

            return false
        }

        // MARK: - Delegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CosmoTextView else { return }

            normalizeSingleLineViewport(for: textView)
            syncBindings(from: textView)

            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            Task {
                await TelepathyEngine.shared.handleTypingInput(text, cursorPosition: cursorLocation)
            }

            handleMentionState(in: textView, text: text, cursorLocation: cursorLocation)
            handleSlashState(in: textView, text: text, cursorLocation: cursorLocation)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CosmoTextView else { return }
            normalizeSingleLineViewport(for: textView)
            let selectedRange = textView.selectedRange()

            parent.cursorPosition = selectedRange.location

            // No selection — dispatch empty immediately (cheap)
            guard selectedRange.length > 0 else {
                selectionChangeWorkItem?.cancel()
                parent.onSelectionChange?(.empty)
                return
            }

            // Debounce expensive rect computation for actual selections
            selectionChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Use layoutManager for full selection bounding rect (covers all lines).
                // Then convert from textView coords to scrollView coords (what SwiftUI sees).
                let glyphRange = textView.layoutManager!.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
                let boundingRect = textView.layoutManager!.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!)
                let tcOrigin = textView.textContainerOrigin
                let textViewRect = CGRect(
                    x: boundingRect.origin.x + tcOrigin.x,
                    y: boundingRect.origin.y + tcOrigin.y,
                    width: boundingRect.width,
                    height: boundingRect.height
                )
                let localRect: CGRect
                if let scrollView = textView.enclosingScrollView {
                    localRect = textView.convert(textViewRect, to: scrollView)
                } else {
                    localRect = textViewRect
                }
                let selectedText = (textView.string as NSString).substring(with: selectedRange)
                let snapshot = EditorSelectionSnapshot(
                    range: selectedRange,
                    text: selectedText,
                    rectInEditor: localRect
                )
                self.parent.onSelectionChange?(snapshot)
            }
            selectionChangeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let urlString: String?
            if let url = link as? URL {
                urlString = url.absoluteString
            } else if let string = link as? String {
                urlString = string
            } else {
                urlString = nil
            }

            guard let urlString,
                  let url = URL(string: urlString),
                  url.scheme == "cosmo",
                  let entityTypeString = url.host,
                  let entityType = EntityType(rawValue: entityTypeString),
                  let entityIDString = url.pathComponents.last,
                  let entityID = Int64(entityIDString) else {
                return false
            }

            NotificationCenter.default.post(
                name: .openMentionAsFloatingBlock,
                object: nil,
                userInfo: [
                    "entityType": entityType,
                    "entityId": entityID
                ]
            )
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                dismissMenus()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.singleLine {
                    dismissMenus()
                    return true
                }

                if isInHeadingMode {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let textView = self.textViewReference else { return }
                        self.resetToNormalTypingAttributes(textView)
                    }
                }
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) && parent.singleLine {
                return true
            }

            return false
        }

        // MARK: - Menu State

        private func handleMentionState(in textView: CosmoTextView, text: String, cursorLocation: Int) {
            guard parent.allowMentions else {
                mentionStartIndex = nil
                return
            }

            if let startIndex = mentionStartIndex {
                let stillValid = startIndex < text.count &&
                    text[text.index(text.startIndex, offsetBy: startIndex)] == "@" &&
                    cursorLocation >= startIndex

                if !stillValid {
                    mentionStartIndex = nil
                    dismissMenus()
                    return
                }

                let queryRange = NSRange(location: startIndex + 1, length: max(0, cursorLocation - startIndex - 1))
                if queryRange.location <= text.count, NSMaxRange(queryRange) <= text.count {
                    let query = (text as NSString).substring(with: queryRange)
                    if query.contains(" ") || query.contains("\n") {
                        mentionStartIndex = nil
                        dismissMenus()
                        return
                    }

                    let position = caretPosition(for: startIndex, in: textView)
                    parent.onMention?(position, query)
                    return
                }
            }

            guard cursorLocation > 0 else { return }
            let char = (text as NSString).substring(with: NSRange(location: cursorLocation - 1, length: 1))
            if char == "@" {
                mentionStartIndex = cursorLocation - 1
                parent.onMention?(caretPosition(for: cursorLocation - 1, in: textView), "")
            }
        }

        private func handleSlashState(in textView: CosmoTextView, text: String, cursorLocation: Int) {
            guard parent.allowSlashCommands, cursorLocation > 0 else { return }
            let nsText = text as NSString
            let currentChar = nsText.substring(with: NSRange(location: cursorLocation - 1, length: 1))
            guard currentChar == "/" else { return }

            let isStartOfDocument = cursorLocation == 1
            let precededByWhitespace: Bool = {
                guard cursorLocation >= 2 else { return true }
                let previous = nsText.substring(with: NSRange(location: cursorLocation - 2, length: 1))
                return previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }()

            if isStartOfDocument || precededByWhitespace {
                parent.onSlashCommand?(caretPosition(for: cursorLocation - 1, in: textView))
            }
        }

        private func caretPosition(for location: Int, in textView: NSTextView) -> CGPoint {
            let safeLocation = max(0, min(location, textView.string.count))
            let screenRect = textView.firstRect(
                forCharacterRange: NSRange(location: safeLocation, length: 0),
                actualRange: nil
            )
            if let window = textView.window, let scrollView = textView.enclosingScrollView {
                let windowRect = window.convertFromScreen(screenRect)
                let local = scrollView.convert(windowRect.origin, from: nil)
                return CGPoint(x: local.x, y: local.y + screenRect.height)
            }
            return CGPoint(x: screenRect.origin.x, y: screenRect.origin.y + screenRect.height)
        }

        private func dismissMenus() {
            mentionStartIndex = nil
            parent.onDismissMenus?()
        }

        // MARK: - Commands

        @objc private func handleEditorScroll(_ notification: Notification) {
            dismissMenus()
        }

        @objc private func handleAppWillResignActive(_ notification: Notification) {
            dismissMenus()
        }

        @objc private func handleInsertMentionInEditor(_ notification: Notification) {
            guard let textView = activeTextView else { return }

            guard let rawType = notification.userInfo?["entityType"] as? String,
                  let type = EntityType(rawValue: rawType),
                  let title = notification.userInfo?["title"] as? String else {
                return
            }

            let entityID = notification.userInfo?["entityId"] as? Int64
            let entityUUID = notification.userInfo?["entityUUID"] as? String ?? UUID().uuidString

            replaceCurrentMentionOrSelection(
                in: textView,
                mention: RichMention(entityUUID: entityUUID, entityID: entityID, entityType: type, titleSnapshot: title)
            )
        }

        @objc private func handlePerformMentionSelection(_ notification: Notification) {
            guard let textView = activeTextView else { return }

            guard let rawType = notification.userInfo?["entityType"] as? String,
                  let type = EntityType(rawValue: rawType),
                  let title = notification.userInfo?["title"] as? String,
                  let uuid = notification.userInfo?["entityUUID"] as? String else {
                return
            }

            let entityID = notification.userInfo?["entityId"] as? Int64
            replaceCurrentMentionOrSelection(
                in: textView,
                mention: RichMention(entityUUID: uuid, entityID: entityID, entityType: type, titleSnapshot: title)
            )
            dismissMenus()
        }

        @objc private func handleInsertTextInEditor(_ notification: Notification) {
            guard let textView = activeTextView,
                  let text = notification.userInfo?["text"] as? String else { return }

            let positionRaw = notification.userInfo?["position"] as? String ?? EditorCommandBus.InsertPosition.cursor.rawValue
            insertText(text, position: positionRaw, into: textView)
        }

        @objc private func handleSetTypingAttributes(_ notification: Notification) {
            guard let textView = activeTextView,
                  let font = notification.userInfo?["font"] as? NSFont,
                  let color = notification.userInfo?["color"] as? NSColor else {
                return
            }

            let isHeading = notification.userInfo?["isHeading"] as? Bool ?? false
            isInHeadingMode = isHeading

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]

            if isHeading {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4
                paragraphStyle.paragraphSpacing = 12
                paragraphStyle.paragraphSpacingBefore = 16
                attributes[.paragraphStyle] = paragraphStyle
            } else {
                attributes[.paragraphStyle] = defaultParagraphStyle()
            }

            textView.typingAttributes = attributes
            syncBindings(from: textView)
        }

        @objc private func handlePerformSlashCommand(_ notification: Notification) {
            guard let textView = activeTextView,
                  let command = notification.userInfo?["command"] as? SlashCommand,
                  let storage = textView.textStorage else {
                return
            }

            var insertionPoint = textView.selectedRange().location
            if insertionPoint > 0 {
                let slashRange = NSRange(location: insertionPoint - 1, length: 1)
                if slashRange.location < storage.length,
                   (textView.string as NSString).substring(with: slashRange) == "/" {
                    storage.replaceCharacters(in: slashRange, with: "")
                    insertionPoint = slashRange.location
                    textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
                }
            }

            switch command.type {
            case .image:
                guard parent.allowImages else { return }
                presentImagePicker(for: textView)
            case .heading1:
                applyHeading(level: 1, textView: textView)
            case .heading2:
                applyHeading(level: 2, textView: textView)
            case .heading3:
                applyHeading(level: 3, textView: textView)
            case .quote:
                toggleBlockPrefix("│ ", kind: .quote, in: textView)
            case .divider:
                insertTextBlock("───────────────", at: insertionPoint, in: textView, appendTrailingNewline: true)
            case .bulletList:
                toggleBlockPrefix("• ", kind: .bulletList, in: textView)
            case .numberedList:
                toggleNumberedList(in: textView)
            case .checkbox:
                toggleChecklist(in: textView)
            }

            syncBindings(from: textView)
            dismissMenus()
        }

        @objc private func handleToggleFormatting(_ notification: Notification) {
            guard let textView = activeTextView,
                  let type = notification.userInfo?["type"] as? FormattingType else {
                return
            }

            // Ensure editor has focus (button click may have stolen it)
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }

            applyFormatting(type, to: textView)
        }

        // MARK: - Formatting

        private func applyFormatting(_ type: FormattingType, to textView: CosmoTextView) {
            switch type {
            case .bold, .italic:
                toggleFontTrait(type == .bold ? .boldFontMask : .italicFontMask, in: textView)
            case .underline:
                toggleAttribute(.underlineStyle, onValue: NSUnderlineStyle.single.rawValue, in: textView)
            case .strikethrough:
                toggleAttribute(.strikethroughStyle, onValue: NSUnderlineStyle.single.rawValue, in: textView)
            case .heading1:
                applyHeading(level: 1, textView: textView)
            case .heading2:
                applyHeading(level: 2, textView: textView)
            case .heading3:
                applyHeading(level: 3, textView: textView)
            case .bulletList:
                toggleBlockPrefix("• ", kind: .bulletList, in: textView)
            case .numberedList:
                toggleNumberedList(in: textView)
            case .checklist:
                toggleChecklist(in: textView)
            }

            syncBindings(from: textView)
        }

        private func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
            let range = textView.selectedRange()

            if range.length > 0 {
                textView.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                    let currentFont = (value as? NSFont) ?? NSFont.systemFont(ofSize: self.parent.fontSize)
                    let currentTraits = currentFont.fontDescriptor.symbolicTraits
                    let shouldRemove = (trait == .boldFontMask && currentTraits.contains(.bold)) ||
                        (trait == .italicFontMask && currentTraits.contains(.italic))
                    let newFont = shouldRemove
                        ? self.fontByRemovingTrait(trait, from: currentFont)
                        : NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
                    textView.textStorage?.addAttribute(.font, value: newFont, range: subrange)
                }
                return
            }

            var attributes = textView.typingAttributes
            let currentFont = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: parent.fontSize)
            let currentTraits = currentFont.fontDescriptor.symbolicTraits
            let shouldRemove = (trait == .boldFontMask && currentTraits.contains(.bold)) ||
                (trait == .italicFontMask && currentTraits.contains(.italic))
            attributes[.font] = shouldRemove
                ? fontByRemovingTrait(trait, from: currentFont)
                : NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
            textView.typingAttributes = attributes
        }

        private func fontByRemovingTrait(_ trait: NSFontTraitMask, from font: NSFont) -> NSFont {
            var traits = font.fontDescriptor.symbolicTraits
            if trait == .boldFontMask {
                traits.remove(.bold)
            } else if trait == .italicFontMask {
                traits.remove(.italic)
            }

            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            if let converted = NSFont(descriptor: descriptor, size: font.pointSize) {
                return converted
            }

            return NSFont.systemFont(ofSize: font.pointSize)
        }

        private func toggleAttribute(_ key: NSAttributedString.Key, onValue: Int, in textView: NSTextView) {
            let range = textView.selectedRange()

            if range.length > 0 {
                let current = textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0
                if current == onValue {
                    textView.textStorage?.removeAttribute(key, range: range)
                } else {
                    textView.textStorage?.addAttribute(key, value: onValue, range: range)
                }
                return
            }

            var attributes = textView.typingAttributes
            let current = attributes[key] as? Int ?? 0
            attributes[key] = current == onValue ? 0 : onValue
            textView.typingAttributes = attributes
        }

        private func applyHeading(level: Int, textView: NSTextView) {
            let prefix: String
            let font: NSFont

            switch level {
            case 1:
                prefix = "# "
                font = NSFont.systemFont(ofSize: max(28, parent.fontSize + 12), weight: .bold)
            case 2:
                prefix = "## "
                font = NSFont.systemFont(ofSize: max(22, parent.fontSize + 8), weight: .semibold)
            default:
                prefix = "### "
                font = NSFont.systemFont(ofSize: max(18, parent.fontSize + 4), weight: .semibold)
            }

            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            let existingPrefixes = ["### ", "## ", "# "]
            let existingPrefix = existingPrefixes.first(where: { lineText.hasPrefix($0) })

            if let existingPrefix {
                textView.textStorage?.replaceCharacters(
                    in: NSRange(location: lineRange.location, length: existingPrefix.count),
                    with: existingPrefix == prefix ? "" : prefix
                )

                if existingPrefix == prefix {
                    isInHeadingMode = false
                    resetToNormalTypingAttributes(textView)
                    syncBindings(from: textView)
                    return
                }
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
            }

            let updatedLineRange = currentLineRange(in: textView)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 12
            paragraphStyle.paragraphSpacingBefore = 16

            textView.textStorage?.addAttributes([
                .font: font,
                .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                .paragraphStyle: paragraphStyle
            ], range: updatedLineRange)

            textView.typingAttributes = [
                .font: font,
                .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                .paragraphStyle: paragraphStyle
            ]
            isInHeadingMode = true
        }

        private func toggleBlockPrefix(_ prefix: String, kind: RichBlockKind, in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            if lineText.hasPrefix(prefix) {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: prefix.count), with: "")
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
            }

            if kind != .quote {
                resetToNormalTypingAttributes(textView)
            }
        }

        private func toggleNumberedList(in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            if let match = lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let count = lineText.distance(from: lineText.startIndex, to: match.upperBound)
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: count), with: "")
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "1. ")
            }
            resetToNormalTypingAttributes(textView)
        }

        private func toggleChecklist(in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 2), with: "")
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "☐ ")
            }
            resetToNormalTypingAttributes(textView)
        }

        private func currentLineRange(in textView: NSTextView) -> NSRange {
            (textView.string as NSString).lineRange(for: textView.selectedRange())
        }

        private func resetToNormalTypingAttributes(_ textView: NSTextView) {
            isInHeadingMode = false
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                .paragraphStyle: defaultParagraphStyle()
            ]
        }

        private func defaultParagraphStyle() -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = parent.singleLine ? 0 : 4
            style.paragraphSpacing = parent.singleLine ? 0 : 8
            return style
        }

        // MARK: - Insertion

        private func insertText(_ text: String, position: String, into textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let range: NSRange
            switch position {
            case EditorCommandBus.InsertPosition.endOfDocument.rawValue:
                range = NSRange(location: storage.length, length: 0)
            case EditorCommandBus.InsertPosition.newParagraph.rawValue:
                range = textView.selectedRange()
                storage.replaceCharacters(in: range, with: "\n\n\(text)")
                textView.setSelectedRange(NSRange(location: range.location + text.count + 2, length: 0))
                syncBindings(from: textView)
                return
            default:
                range = textView.selectedRange()
            }

            storage.replaceCharacters(in: range, with: text)
            textView.setSelectedRange(NSRange(location: range.location + text.count, length: 0))
            syncBindings(from: textView)
        }

        private func replaceCurrentMentionOrSelection(in textView: NSTextView, mention: RichMention) {
            guard let storage = textView.textStorage else { return }

            let replacementRange: NSRange
            if let mentionStartIndex,
               mentionStartIndex <= textView.selectedRange().location {
                replacementRange = NSRange(
                    location: mentionStartIndex,
                    length: textView.selectedRange().location - mentionStartIndex
                )
            } else {
                replacementRange = textView.selectedRange()
            }

            let mentionString = NSMutableAttributedString(
                string: mention.displayText,
                attributes: mentionAttributes(for: mention)
            )
            mentionString.append(NSAttributedString(
                string: " ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: parent.fontSize),
                    .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary)
                ]
            ))

            storage.replaceCharacters(in: replacementRange, with: mentionString)
            let newCursor = replacementRange.location + mentionString.length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            mentionStartIndex = nil
            syncBindings(from: textView)
        }

        private func mentionAttributes(for mention: RichMention) -> [NSAttributedString.Key: Any] {
            let color = CosmoMentionColors.nsColor(for: mention.entityType)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(15, parent.fontSize - 1), weight: .semibold),
                .foregroundColor: color,
                .backgroundColor: color.withAlphaComponent(0.12),
                .underlineStyle: 0,
                RichDocumentAttributeKeys.entityType: mention.entityType.rawValue,
                RichDocumentAttributeKeys.entityUUID: mention.entityUUID
            ]

            if let entityID = mention.entityID {
                attributes[RichDocumentAttributeKeys.entityID] = entityID
                attributes[.link] = "cosmo://\(mention.entityType.rawValue)/\(entityID)"
            }

            return attributes
        }

        private func presentImagePicker(for textView: NSTextView) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .image]
            panel.title = "Insert Image"

            guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else {
                return
            }

            insertImage(data: data, filename: url.lastPathComponent, into: textView)
        }

        private func insertImage(data: Data, filename: String?, into textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            guard let saved = try? ImageStore.save(data, originalFilename: filename),
                  let image = ImageStore.load(path: saved.path) else {
                return
            }

            let attachment = NSTextAttachment()
            attachment.image = image.scaled(toFit: CGSize(width: min(680, saved.width), height: 420))

            let attributed = NSMutableAttributedString(attachment: attachment)
            attributed.addAttributes([
                RichDocumentAttributeKeys.imagePath: saved.path
            ], range: NSRange(location: 0, length: attributed.length))

            let replacementRange = textView.selectedRange()
            let prefix = replacementRange.location > 0 && !(textView.string as NSString).substring(with: NSRange(location: replacementRange.location - 1, length: 1)).hasSuffix("\n")
                ? "\n"
                : ""
            let suffix = "\n"

            let wrapped = NSMutableAttributedString(string: prefix)
            wrapped.append(attributed)
            wrapped.append(NSAttributedString(string: suffix))

            storage.replaceCharacters(in: replacementRange, with: wrapped)
            let cursor = replacementRange.location + wrapped.length
            textView.setSelectedRange(NSRange(location: cursor, length: 0))
            syncBindings(from: textView)
        }

        private func insertTextBlock(_ text: String, at location: Int, in textView: NSTextView, appendTrailingNewline: Bool) {
            let prefix = location > 0 && !(textView.string as NSString).substring(with: NSRange(location: location - 1, length: 1)).hasSuffix("\n") ? "\n" : ""
            let suffix = appendTrailingNewline ? "\n" : ""
            let output = prefix + text + suffix
            textView.textStorage?.replaceCharacters(in: NSRange(location: location, length: 0), with: output)
            textView.setSelectedRange(NSRange(location: location + output.count, length: 0))
        }

        // MARK: - Shared helpers

        private var activeTextView: CosmoTextView? {
            textViewReference
        }

        private func syncBindings(from textView: NSTextView) {
            // Lightweight per-keystroke sync: plain text + cursor position only
            parent.plainText = textView.string
            parent.cursorPosition = textView.selectedRange().location

            // Coalesce expensive attributedText sync + height measurement.
            // Fires after 50ms of inactivity — fast enough to feel instant,
            // slow enough to skip during rapid typing bursts.
            deferredSyncWorkItem?.cancel()
            isUpdatingFromTextView = true
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.parent.attributedText = textView.attributedString()
                self.notifyContentHeightChange(for: textView)
                DispatchQueue.main.async { self.isUpdatingFromTextView = false }
            }
            deferredSyncWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }

        fileprivate func notifyContentHeightChange(for textView: NSTextView) {
            guard let callback = parent.onContentHeightChange else { return }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let measuredHeight = ceil(usedRect.height + (textView.textContainerInset.height * 2))
            let minimum = parent.singleLine ? parent.resolvedSingleLineHeight() : 0
            let newHeight = max(minimum, measuredHeight)
            // Only notify when height changes by >1pt to prevent sub-pixel jitter
            guard abs(newHeight - lastReportedHeight) > 1.0 else { return }
            lastReportedHeight = newHeight
            callback(newHeight)
        }

        fileprivate func normalizeSingleLineViewport(for textView: NSTextView) {
            guard parent.singleLine,
                  let scrollView = textView.enclosingScrollView else {
                return
            }

            let targetHeight = parent.resolvedSingleLineHeight()
            let currentWidth = max(scrollView.contentSize.width, textView.frame.width)
            if textView.frame.height != targetHeight || textView.frame.width != currentWidth {
                textView.setFrameSize(NSSize(width: currentWidth, height: targetHeight))
            }

            let clipView = scrollView.contentView
            if clipView.bounds.origin != .zero {
                clipView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(clipView)
            }
        }
    }
}

fileprivate extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
