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

fileprivate extension NSView {
    func nearestAncestorScrollView(excluding excluded: NSScrollView? = nil) -> NSScrollView? {
        var currentSuperview: NSView? = superview
        while let view = currentSuperview {
            if let scrollView = view as? NSScrollView, scrollView !== excluded {
                return scrollView
            }
            currentSuperview = view.superview
        }
        return nil
    }
}

// MARK: - Scroll-Transparent NSScrollView

/// When `forwardsScrollEvents` is true, scroll wheel events pass through to the
/// next responder (the parent SwiftUI ScrollView) instead of being consumed.
final class CosmoScrollView: NSScrollView {
    var forwardsScrollEvents: Bool = false
    var intrinsicHeight: CGFloat?

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: intrinsicHeight ?? NSView.noIntrinsicMetric
        )
    }

    override func scrollWheel(with event: NSEvent) {
        if forwardsScrollEvents {
            if let ancestorScrollView = nearestAncestorScrollView(excluding: self) {
                ancestorScrollView.scrollWheel(with: event)
            } else {
                nextResponder?.scrollWheel(with: event)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - Custom NSTextView

final class CosmoTextView: NSTextView {
    fileprivate weak var shortcutDelegate: CosmoTextViewShortcutDelegate?

    /// When true, scroll events are handled by the enclosing NSScrollView
    /// instead of being forwarded up the responder chain (canvas zoom).
    var scrollsInternally: Bool = false

    /// Called when the user clicks while the editor is read-only (isEditable == false).
    /// Used by canvas blocks to enter edit mode from a single click.
    var onTapWhileReadOnly: (() -> Void)?
    var onBecomeFirstResponder: (() -> Void)?
    var onResignFirstResponder: (() -> Void)?

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
                    .foregroundColor: PolishHighlightColors.link,
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

    /// Trampoline for calling super.mouseDown from a closure (Swift doesn't allow super in closures).
    private func superMouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditable else {
            // Notify the canvas block to enter edit mode.
            // After SwiftUI re-renders with isEditable=true, we become
            // first responder and replay the click so the cursor lands
            // at the correct position — single-click-to-edit.
            let savedEvent = event
            onTapWhileReadOnly?()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEditable else { return }
                self.window?.makeFirstResponder(self)
                self.superMouseDown(with: savedEvent)
            }
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if scrollsInternally {
            // Let the enclosing NSScrollView handle scrolling within the block
            super.scrollWheel(with: event)
        } else {
            // Forward scroll events to the nearest ancestor scroll view so the
            // surrounding SwiftUI page scrolls as one unit.
            if let ancestorScrollView = nearestAncestorScrollView(excluding: enclosingScrollView) {
                ancestorScrollView.scrollWheel(with: event)
            } else if let scrollView = enclosingScrollView {
                scrollView.nextResponder?.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
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

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onBecomeFirstResponder?()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onResignFirstResponder?()
        }
        return resigned
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        // When embedded in a SwiftUI ScrollView (non-scrolling mode), suppress
        // internal scroll-to-cursor. NSTextView calls this during insertText,
        // which shifts the clip view BEFORE the frame has grown to fit the new
        // content — causing a visible upward jitter on newline insertion.
        guard scrollsInternally else { return }
        super.scrollRangeToVisible(range)
    }
}

extension CosmoTextView {
    static func scrollableCosmoTextView() -> CosmoScrollView {
        let scrollView = CosmoScrollView()
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

enum EditorLayoutMetrics {
    static func singleLineVerticalInset(fontSize: CGFloat, compact: Bool) -> CGFloat {
        max(4, ceil(fontSize * 0.15))
    }

    static func singleLineHeight(
        fontSize: CGFloat,
        compact: Bool,
        baseFontWeight: NSFont.Weight = .regular
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        let inset = singleLineVerticalInset(fontSize: fontSize, compact: compact)
        return ceil(font.ascender - font.descender + font.leading + inset * 2 + 2)
    }

    static func titleVerticalInset(fontSize: CGFloat, compact: Bool) -> CGFloat {
        max(compact ? 4 : 6, ceil(fontSize * (compact ? 0.10 : 0.12)))
    }

    static func titleHeight(
        fontSize: CGFloat,
        compact: Bool,
        baseFontWeight: NSFont.Weight = .regular,
        lineCount: Int
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        let inset = titleVerticalInset(fontSize: fontSize, compact: compact)
        return ceil((font.ascender - font.descender + font.leading) * CGFloat(max(1, lineCount)) + inset * 2 + 2)
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
    var overrideTextColor: NSColor? = nil
    var overrideFont: NSFont? = nil
    var allowSlashCommands: Bool = true
    var allowMentions: Bool = true
    var allowImages: Bool = true
    var allowSelectionMenu: Bool = true
    var singleLine: Bool = false
    var titleConfiguration: TitleEditorConfiguration? = nil
    var baseFontWeight: NSFont.Weight = .regular
    var polishHighlights: WritingAnalysis? = nil
    var focusBandRange: NSRange? = nil
    var textAlignment: NSTextAlignment = .natural

    var typewriterMode: Bool = false

    var isEditable: Bool = true
    var scrollsInternally: Bool = false

    var onSlashCommand: ((CGPoint) -> Void)?
    var onMention: ((CGPoint, String) -> Void)?
    var onSelectionChange: ((EditorSelectionSnapshot) -> Void)?
    var onDismissMenus: (() -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?
    var onCommit: (() -> Void)?
    /// Direct per-keystroke plain text callback — fires from syncBindings immediately,
    /// bypassing the SwiftUI @Binding→onChange chain which can coalesce/skip updates.
    var onPlainTextDidChange: ((String) -> Void)?

    func makeNSView(context: Context) -> CosmoScrollView {
        let scrollView = CosmoTextView.scrollableCosmoTextView()
        scrollView.forwardsScrollEvents = !scrollsInternally

        guard let textView = scrollView.documentView as? CosmoTextView else {
            return scrollView
        }

        configureTextView(textView, context: context, isInitial: true)
        textView.textStorage?.setAttributedString(attributedText)
        applyStorageOverrides(textView.textStorage)
        context.coordinator.applyPolishHighlights(to: textView)
        context.coordinator.applyFocusBand(to: textView)
        context.coordinator.textViewReference = textView
        context.coordinator.installScrollDismissObserver(for: scrollView)
        context.coordinator.installFrameChangeObserver(for: scrollView)
        context.coordinator.normalizeSingleLineViewport(for: textView)
        context.coordinator.notifyContentHeightChange(for: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: CosmoScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CosmoTextView else { return }
        scrollView.forwardsScrollEvents = !scrollsInternally
        context.coordinator.parent = self
        // Flag that we're inside SwiftUI's layout pass — delegate callbacks must not
        // write @Binding values synchronously (causes "Modifying state during view update").
        context.coordinator.isUpdatingFromSwiftUI = true
        defer { context.coordinator.isUpdatingFromSwiftUI = false }
        configureTextView(textView, context: context, isInitial: false)

        // Skip text storage replacement when the change originated from user typing —
        // the text view already has the correct content, avoiding scroll position resets.
        // ALSO skip when the text view IS the first responder (user is actively editing).
        // The 50ms deferred attributedText sync means `attributedText` binding can be stale.
        // Without this guard, GRDB observation spam triggers updateNSView which overwrites
        // the NSTextView with stale binding content, destroying text the user just typed.
        let isFirstResponder = textView.window?.firstResponder == textView
        guard !context.coordinator.isUpdatingFromTextView, !isFirstResponder else {
            context.coordinator.applyPolishHighlights(to: textView)
            context.coordinator.applyFocusBand(to: textView)
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
            applyStorageOverrides(textView.textStorage)
            let safeLocation = min(selectedRange.location, textView.string.count)
            let safeLength = min(selectedRange.length, textView.string.count - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            context.coordinator.normalizeSingleLineViewport(for: textView)
            context.coordinator.notifyContentHeightChange(for: textView)
        }

        context.coordinator.applyPolishHighlights(to: textView)
        context.coordinator.applyFocusBand(to: textView)
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
        textView.isEditable = isEditable
        textView.isSelectable = isEditable

        // Wire tap-to-edit callback for canvas blocks (read-only → editable on click)
        textView.onTapWhileReadOnly = isEditable ? nil : { [weak coordinator = context.coordinator] in
            coordinator?.parent.onActivate?()
        }
        textView.onBecomeFirstResponder = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onActivate?()
        }
        textView.onResignFirstResponder = { [weak coordinator = context.coordinator] in
            // Flush the deferred attributedText sync BEFORE firing onDeactivate.
            // syncBindings() debounces attributedText writes by 50ms — if the user
            // blurs before the deferred sync fires, flushPendingSync reads a stale
            // attributedText and the final keystrokes are lost.
            if let coordinator, let tv = coordinator.textViewReference {
                coordinator.deferredSyncWorkItem?.cancel()
                coordinator.parent.attributedText = tv.attributedString()
                coordinator.isUpdatingFromTextView = false
            }
            coordinator?.parent.onDeactivate?()
        }
        textView.scrollsInternally = scrollsInternally
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.importsGraphics = allowImages
        textView.allowsImageEditing = allowImages
        textView.drawsBackground = false

        // Only set font/textColor/alignment on initial setup.
        // Setting these on every update overwrites the entire text storage,
        // destroying any rich text formatting (bold, italic, etc.).
        if isInitial {
            textView.font = overrideFont ?? resolvedBaseFont()
            textView.textColor = overrideTextColor ?? (darkMode ? .white : NSColor(CosmoColors.textPrimary))
            textView.alignment = textAlignment
            textView.defaultParagraphStyle = baseParagraphStyle()
            textView.typingAttributes = defaultTypingAttributes()
        }

        textView.backgroundColor = .clear
        textView.insertionPointColor = overrideTextColor ?? (darkMode ? .white : NSColor(CosmoColors.textPrimary))
        textView.textContainerInset = resolvedTextInsets()
        textView.textContainer?.lineFragmentPadding = 0
        let isTitleMode = titleConfiguration != nil
        textView.isVerticallyResizable = !singleLine || isTitleMode
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: singleLine ? resolvedSingleLineHeight() : CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(
            width: 0,
            height: singleLine ? resolvedSingleLineHeight() : (isTitleMode ? resolvedTitleMinimumHeight() : 0)
        )
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
        if singleLine || titleConfiguration != nil {
            style.lineSpacing = 0
            style.paragraphSpacing = 0
        } else if compact {
            style.lineSpacing = 4
            style.paragraphSpacing = 8
        } else {
            style.lineSpacing = 6
            style.paragraphSpacing = 12
        }
        return style
    }

    private func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: overrideFont ?? resolvedBaseFont(),
            .foregroundColor: overrideTextColor ?? (darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary)),
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    /// Post-processes the text storage to force overrideTextColor and overrideFont
    /// across all ranges. The RichDocument serializer bakes theme colors into the
    /// attributed string, so passing overrideTextColor to the text view is not
    /// enough — stored per-character attributes win. This reapplies the overrides
    /// after each setAttributedString call.
    func applyStorageOverrides(_ storage: NSTextStorage?) {
        guard let storage, storage.length > 0 else { return }
        guard overrideTextColor != nil || overrideFont != nil else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        if let color = overrideTextColor {
            storage.enumerateAttribute(RichDocumentAttributeKeys.entityType, in: fullRange, options: []) { value, range, _ in
                // Preserve mention colors (entities carry their own color).
                guard value == nil else { return }
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
        if let font = overrideFont {
            storage.addAttribute(.font, value: font, range: fullRange)
        }
        storage.endEditing()
    }

    private func resolvedBaseFont() -> NSFont {
        NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
    }

    private func resolvedTextInsets() -> NSSize {
        if singleLine {
            let verticalInset = EditorLayoutMetrics.singleLineVerticalInset(fontSize: fontSize, compact: compact)
            return NSSize(width: compact ? 0 : 2, height: verticalInset)
        }
        if titleConfiguration != nil {
            let verticalInset = EditorLayoutMetrics.titleVerticalInset(fontSize: fontSize, compact: compact)
            return NSSize(width: compact ? 0 : 2, height: verticalInset)
        }
        if compact {
            return NSSize(width: 10, height: 8)
        }
        return NSSize(width: 16, height: 16)
    }

    private func resolvedSingleLineHeight() -> CGFloat {
        EditorLayoutMetrics.singleLineHeight(
            fontSize: fontSize,
            compact: compact,
            baseFontWeight: baseFontWeight
        )
    }

    private func resolvedTitleMinimumHeight() -> CGFloat {
        EditorLayoutMetrics.titleHeight(
            fontSize: fontSize,
            compact: compact,
            baseFontWeight: baseFontWeight,
            lineCount: 1
        )
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
        private weak var observedScrollView: NSScrollView?
        private var mentionStartIndex: Int?
        private var isInHeadingMode = false

        private enum ActiveBlockMode {
            case none
            case quote
            case bulletList
            case numberedList
            case checklist
        }
        private var activeBlockMode: ActiveBlockMode = .none
        private var hasAppliedHighlights = false
        /// Guards against updateNSView round-trip when change originated from user typing
        var isUpdatingFromTextView = false
        /// Guards against delegate callbacks writing bindings during SwiftUI's layout pass
        var isUpdatingFromSwiftUI = false
        /// Deferred attributedText sync — 50ms debounce for performance.
        /// Must be cancellable from resignFirstResponder to flush final state.
        var deferredSyncWorkItem: DispatchWorkItem?
        private var lastReportedHeight: CGFloat = 0
        private var lastObservedFrameWidth: CGFloat = 0
        private var selectionChangeWorkItem: DispatchWorkItem?
        /// Grace period after opening a menu — ignores auto-scroll dismiss
        private var menuOpenedAt: CFAbsoluteTime = 0

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
                selector: #selector(handleReplaceSelectionInEditor(_:)),
                name: .replaceSelectionInEditor,
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

        func installFrameChangeObserver(for scrollView: NSScrollView) {
            scrollView.postsFrameChangedNotifications = true
            observedScrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFrameChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: scrollView
            )
        }

        @objc private func handleFrameChange(_ notification: Notification) {
            guard let textView = textViewReference,
                  let scrollView = notification.object as? NSScrollView else { return }
            let newWidth = scrollView.frame.width
            guard abs(newWidth - lastObservedFrameWidth) > 0.5 else {
                return
            }
            lastObservedFrameWidth = newWidth
            notifyContentHeightChange(for: textView)
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
                    storage.addAttribute(.backgroundColor, value: PolishHighlightColors.complex, range: range)
                }
                for range in analysis.veryComplexSentenceRanges where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: PolishHighlightColors.veryComplex, range: range)
                }
                for range in analysis.passiveVoiceRanges where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: PolishHighlightColors.passive, range: range)
                }
                for range in analysis.adverbRanges where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: PolishHighlightColors.adverb, range: range)
                }
            }

            storage.endEditing()
            hasAppliedHighlights = true
        }

        func applyFocusBand(to textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
            guard fullRange.length > 0 else { return }

            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

            guard let requestedRange = parent.focusBandRange,
                  requestedRange.location != NSNotFound else {
                return
            }

            let activeLocation = min(max(0, requestedRange.location), fullRange.length)
            let activeLength = min(max(0, requestedRange.length), fullRange.length - activeLocation)
            let activeRange = NSRange(location: activeLocation, length: max(activeLength, 1))
            guard activeRange.location < fullRange.length else { return }

            let mutedColor = NSColor(DS.textMuted).withAlphaComponent(0.48)
            let activeColor = parent.overrideTextColor ?? NSColor(DS.text)

            layoutManager.addTemporaryAttribute(.foregroundColor, value: mutedColor, forCharacterRange: fullRange)
            layoutManager.addTemporaryAttribute(.foregroundColor, value: activeColor, forCharacterRange: activeRange)
        }

        // MARK: - Shortcut Delegate

        func textViewDidRequestFormattingShortcut(_ shortcut: FormattingType) {
            guard let textView = textViewReference else { return }
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
            // Skip when triggered by setAttributedString inside updateNSView —
            // writing bindings here would cause "Modifying state during view update".
            guard !isUpdatingFromSwiftUI else { return }

            normalizeSingleLineViewport(for: textView)
            syncBindings(from: textView)

            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            handleMentionState(in: textView, text: text, cursorLocation: cursorLocation)
            handleSlashState(in: textView, text: text, cursorLocation: cursorLocation)

            // Scroll behavior — only when editor owns its own scroll (scrollsInternally)
            // Skip when embedded inside a SwiftUI ScrollView (the default for focus modes)
            if parent.scrollsInternally {
                if parent.typewriterMode {
                    scrollToCursorCenter(textView)
                } else {
                    ensureScrollMargin(textView)
                }
            }
        }

        // MARK: - Typewriter Scrolling

        /// Keep cursor vertically centered — text scrolls around it
        private func scrollToCursorCenter(_ textView: NSTextView) {
            guard !parent.singleLine,
                  !textView.string.isEmpty,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }

            let cursorRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: cursorRange, actualCharacterRange: nil)
            let cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let cursorY = cursorRect.midY + textView.textContainerInset.height

            let visibleHeight = scrollView.contentView.bounds.height
            // Don't center-scroll if document is shorter than viewport
            let documentHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            guard documentHeight > visibleHeight else { return }

            let targetY = max(0, cursorY - visibleHeight / 2)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        // MARK: - Scroll Margin (30% Bottom)

        /// Start scrolling before cursor hits viewport bottom — keeps eyes in upper 2/3
        private func ensureScrollMargin(_ textView: NSTextView) {
            guard !parent.singleLine,
                  !textView.string.isEmpty,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }

            let cursorRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: cursorRange, actualCharacterRange: nil)
            let cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let cursorY = cursorRect.maxY + textView.textContainerInset.height

            let visibleRect = scrollView.contentView.bounds
            let bottomMargin = visibleRect.height * 0.3
            let bottomThreshold = visibleRect.maxY - bottomMargin

            if cursorY > bottomThreshold {
                let targetY = cursorY - visibleRect.height + bottomMargin
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.1
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: max(0, targetY)))
                }
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CosmoTextView else { return }
            normalizeSingleLineViewport(for: textView)
            let selectedRange = textView.selectedRange()

            // Skip binding writes when called from updateNSView (e.g. setAttributedString
            // triggers selection change) — writing state here causes "Modifying state
            // during view update" and layout thrashing.
            guard !isUpdatingFromSwiftUI else { return }

            parent.cursorPosition = selectedRange.location

            // Auto-detect block mode based on current line prefix (must run for ALL cursor positions)
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            if lineText.hasPrefix("│ ") {
                activeBlockMode = .quote
            } else if lineText.hasPrefix("• ") {
                activeBlockMode = .bulletList
            } else if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                activeBlockMode = .checklist
            } else if lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                activeBlockMode = .numberedList
            } else {
                activeBlockMode = .none
            }

            // No selection — dispatch empty immediately (cheap)
            guard selectedRange.length > 0 else {
                selectionChangeWorkItem?.cancel()
                parent.onSelectionChange?(cursorSnapshot(in: textView, selectedRange: selectedRange))
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

        private func cursorSnapshot(in textView: NSTextView, selectedRange: NSRange) -> EditorSelectionSnapshot {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return EditorSelectionSnapshot(range: selectedRange, text: "", rectInEditor: .zero)
            }

            let safeLocation = min(selectedRange.location, max(textView.string.utf16.count, 0))
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: safeLocation, length: 0),
                actualCharacterRange: nil
            )
            var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            if cursorRect.isEmpty {
                cursorRect = CGRect(x: 0, y: 0, width: 1, height: textView.font?.pointSize ?? 17)
            }
            let tcOrigin = textView.textContainerOrigin
            let textViewRect = CGRect(
                x: cursorRect.origin.x + tcOrigin.x,
                y: cursorRect.origin.y + tcOrigin.y,
                width: max(cursorRect.width, 1),
                height: max(cursorRect.height, textView.font?.pointSize ?? 17)
            )
            let localRect: CGRect
            if let scrollView = textView.enclosingScrollView {
                localRect = textView.convert(textViewRect, to: scrollView)
            } else {
                localRect = textViewRect
            }
            return EditorSelectionSnapshot(range: selectedRange, text: "", rectInEditor: localRect)
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

            // Shift+Enter — always continue current block
            if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                if activeBlockMode != .none, let prefix = continuationPrefix(for: textView) {
                    textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
                    syncBindings(from: textView)
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if parent.singleLine || parent.titleConfiguration?.commitsOnReturn == true || parent.onCommit != nil {
                    dismissMenus()
                    parent.onCommit?()
                    return true
                }

                // Block continuation: quotes, bullets, numbered lists, checklists
                if activeBlockMode != .none {
                    if isEmptyBlockLine(in: textView) {
                        // Empty block line → exit block mode, remove prefix
                        let lineRange = currentLineRange(in: textView)
                        let prefixLen = blockPrefixLength(in: textView)
                        if prefixLen > 0 {
                            textView.textStorage?.replaceCharacters(
                                in: NSRange(location: lineRange.location, length: prefixLen),
                                with: ""
                            )
                        }
                        activeBlockMode = .none
                        resetToNormalTypingAttributes(textView)
                        syncBindings(from: textView)
                        return true
                    } else if activeBlockMode == .quote {
                        // Quote blocks: continue with prefix on single Enter
                        // Use tight paragraph spacing so quote lines stay visually connected
                        if let prefix = continuationPrefix(for: textView) {
                            let quoteStyle = NSMutableParagraphStyle()
                            quoteStyle.lineSpacing = parent.compact ? 2 : 4
                            quoteStyle.paragraphSpacing = parent.compact ? 2 : 4
                            var quoteAttrs = textView.typingAttributes
                            quoteAttrs[.paragraphStyle] = quoteStyle
                            textView.typingAttributes = quoteAttrs

                            textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
                            syncBindings(from: textView)
                            return true
                        }
                    } else if let prefix = continuationPrefix(for: textView) {
                        // Bullets/numbered/checklists: continue with prefix, reset inline formatting
                        textView.insertText("\n" + prefix, replacementRange: textView.selectedRange())
                        resetInlineFormattingOnly(textView)
                        syncBindings(from: textView)
                        return true
                    }
                }

                // Default Enter: reset typing attributes BEFORE inserting newline
                // so the \n character itself doesn't carry heading/bold attributes
                resetToNormalTypingAttributes(textView)
                textView.insertText("\n", replacementRange: textView.selectedRange())

                // Stamp normal attributes on the \n character we just inserted,
                // so adjacent text insertion (slash command prefixes) won't inherit heading font.
                // Batch inside beginEditing/endEditing so a single processEditing fires
                // (instead of separate cycles for addAttributes + removeAttribute).
                let cursorPos = textView.selectedRange().location
                if cursorPos > 0 {
                    let nlRange = NSRange(location: cursorPos - 1, length: 1)
                    textView.textStorage?.beginEditing()
                    textView.textStorage?.addAttributes([
                        .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                        .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                        .paragraphStyle: defaultParagraphStyle()
                    ], range: nlRange)
                    textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingLevel, range: nlRange)
                    textView.textStorage?.endEditing()
                }
                return true
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) &&
                (parent.singleLine || parent.titleConfiguration != nil) {
                return true
            }

            return false
        }

        // MARK: - Block Continuation Helpers

        private func continuationPrefix(for textView: NSTextView) -> String? {
            switch activeBlockMode {
            case .none: return nil
            case .quote: return "│ "
            case .bulletList: return "• "
            case .checklist: return "☐ "
            case .numberedList:
                let lineRange = currentLineRange(in: textView)
                let lineText = (textView.string as NSString).substring(with: lineRange)
                if let match = lineText.range(of: #"^(\d+)\."#, options: .regularExpression) {
                    let numStr = String(lineText[match])
                        .replacingOccurrences(of: ".", with: "")
                    if let num = Int(numStr) {
                        return "\(num + 1). "
                    }
                }
                return "1. "
            }
        }

        private func isEmptyBlockLine(in textView: NSTextView) -> Bool {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            let trimmed = lineText.trimmingCharacters(in: .newlines)
            switch activeBlockMode {
            case .none: return false
            case .quote: return trimmed == "│" || trimmed == "│ "
            case .bulletList: return trimmed == "•" || trimmed == "• "
            case .checklist: return trimmed == "☐" || trimmed == "☐ " || trimmed == "☑" || trimmed == "☑ "
            case .numberedList: return trimmed.range(of: #"^\d+\.\s*$"#, options: .regularExpression) != nil
            }
        }

        private func blockPrefixLength(in textView: NSTextView) -> Int {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            switch activeBlockMode {
            case .none: return 0
            case .quote: return lineText.hasPrefix("│ ") ? 2 : 1
            case .bulletList: return lineText.hasPrefix("• ") ? 2 : 1
            case .checklist: return (lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ")) ? 2 : 1
            case .numberedList:
                if let match = lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                    return lineText.distance(from: lineText.startIndex, to: match.upperBound)
                }
                return 0
            }
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
                menuOpenedAt = CFAbsoluteTimeGetCurrent()
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
                menuOpenedAt = CFAbsoluteTimeGetCurrent()
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
            // Skip dismiss if a menu just opened — the scroll is auto-scroll
            // from the text insertion, not a user-initiated scroll.
            let elapsed = CFAbsoluteTimeGetCurrent() - menuOpenedAt
            guard elapsed > 0.3 else { return }
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

            let allowInactive = notification.userInfo?["allowInactive"] as? Bool ?? false
            guard allowInactive || textView.window?.firstResponder === textView else { return }

            let positionRaw = notification.userInfo?["position"] as? String ?? EditorCommandBus.InsertPosition.cursor.rawValue
            insertText(text, position: positionRaw, into: textView)
        }

        @objc private func handleReplaceSelectionInEditor(_ notification: Notification) {
            guard let textView = activeTextView,
                  let text = notification.userInfo?["text"] as? String else { return }

            let allowInactive = notification.userInfo?["allowInactive"] as? Bool ?? false
            guard allowInactive || textView.window?.firstResponder === textView else { return }
            insertText(text, position: EditorCommandBus.InsertPosition.cursor.rawValue, into: textView)
        }

        @objc private func handleSetTypingAttributes(_ notification: Notification) {
            guard let textView = activeTextView,
                  textView.window?.firstResponder === textView,
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
            guard parent.allowSlashCommands,
                  let textView = activeTextView,
                  textView.window?.firstResponder === textView,
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
            case .writingAI:
                NotificationCenter.default.post(name: .contentFocusOpenWritingAI, object: nil)
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

            // Force layout update after format changes to prevent view clipping (Bug 2)
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.sizeToFit()
            notifyContentHeightChange(for: textView)

            dismissMenus()
        }

        @objc private func handleToggleFormatting(_ notification: Notification) {
            guard let textView = activeTextView,
                  textView.window?.firstResponder === textView,
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
            let font: NSFont

            switch level {
            case 1:
                font = NSFont.systemFont(ofSize: max(32, parent.fontSize + 16), weight: .bold)
            case 2:
                font = NSFont.systemFont(ofSize: max(24, parent.fontSize + 8), weight: .semibold)
            default:
                font = NSFont.systemFont(ofSize: max(20, parent.fontSize + 4), weight: .medium)
            }

            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)

            // Strip legacy visible prefixes if present (backward compat)
            let existingPrefixes = ["### ", "## ", "# "]
            if let existingPrefix = existingPrefixes.first(where: { lineText.hasPrefix($0) }) {
                textView.textStorage?.replaceCharacters(
                    in: NSRange(location: lineRange.location, length: existingPrefix.count),
                    with: ""
                )
            }

            // Check if line already has this heading level — toggle off
            let checkRange = currentLineRange(in: textView)
            if checkRange.length > 0,
               let currentLevel = textView.textStorage?.attribute(
                   RichDocumentAttributeKeys.headingLevel,
                   at: checkRange.location,
                   effectiveRange: nil
               ) as? Int,
               currentLevel == level {
                // Remove heading — reset to normal
                textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingLevel, range: checkRange)
                textView.textStorage?.addAttributes([
                    .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                    .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                    .paragraphStyle: defaultParagraphStyle()
                ], range: checkRange)
                isInHeadingMode = false
                resetToNormalTypingAttributes(textView)
                syncBindings(from: textView)
                return
            }

            // Apply heading attributes (no prefix insertion)
            let updatedLineRange = currentLineRange(in: textView)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 12
            // Proportional top margin — larger headings get more breathing room above
            switch level {
            case 1: paragraphStyle.paragraphSpacingBefore = 32
            case 2: paragraphStyle.paragraphSpacingBefore = 24
            default: paragraphStyle.paragraphSpacingBefore = 16
            }

            if updatedLineRange.length > 0 {
                textView.textStorage?.addAttributes([
                    .font: font,
                    .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                    .paragraphStyle: paragraphStyle,
                    RichDocumentAttributeKeys.headingLevel: level
                ], range: updatedLineRange)
            }

            textView.typingAttributes = [
                .font: font,
                .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                .paragraphStyle: paragraphStyle,
                RichDocumentAttributeKeys.headingLevel: level
            ]
            isInHeadingMode = true

            // Force layout update to prevent clipping (Bug 2)
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
        }

        private func toggleBlockPrefix(_ prefix: String, kind: RichBlockKind, in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            var newMode: ActiveBlockMode = .none
            if lineText.hasPrefix(prefix) {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: prefix.count), with: "")
                newMode = .none
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
                switch kind {
                case .quote: newMode = .quote
                case .bulletList: newMode = .bulletList
                case .checklist: newMode = .checklist
                case .numberedList: newMode = .numberedList
                default: break
                }
            }

            if kind == .quote {
                // Quote blocks use tight paragraph spacing so lines stay visually connected
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.lineSpacing = parent.compact ? 2 : 4
                quoteStyle.paragraphSpacing = parent.compact ? 2 : 4
                var quoteAttrs = textView.typingAttributes
                quoteAttrs[.paragraphStyle] = quoteStyle
                textView.typingAttributes = quoteAttrs

                let updatedLineRange = currentLineRange(in: textView)
                if updatedLineRange.length > 0 {
                    textView.textStorage?.addAttribute(.paragraphStyle, value: quoteStyle, range: updatedLineRange)
                }
            } else {
                resetToNormalTypingAttributes(textView)

                // Stamp normal paragraph attributes on the entire line to clear any
                // inherited heading/bold attributes from adjacent text storage
                let updatedLineRange = currentLineRange(in: textView)
                if updatedLineRange.length > 0 {
                    textView.textStorage?.addAttributes([
                        .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                        .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                        .paragraphStyle: defaultParagraphStyle()
                    ], range: updatedLineRange)
                    textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingLevel, range: updatedLineRange)
                }
            }

            // Set block mode AFTER reset so it isn't overwritten
            activeBlockMode = newMode

            // Force layout update to prevent clipping (Bug 2)
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
        }

        private func toggleNumberedList(in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            var newMode: ActiveBlockMode = .none
            if let match = lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let count = lineText.distance(from: lineText.startIndex, to: match.upperBound)
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: count), with: "")
                newMode = .none
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "1. ")
                newMode = .numberedList
            }
            resetToNormalTypingAttributes(textView)

            // Clear inherited heading/bold attributes from the line
            let updatedLineRange = currentLineRange(in: textView)
            if updatedLineRange.length > 0 {
                textView.textStorage?.addAttributes([
                    .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                    .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                    .paragraphStyle: defaultParagraphStyle()
                ], range: updatedLineRange)
                textView.textStorage?.removeAttribute(RichDocumentAttributeKeys.headingLevel, range: updatedLineRange)
            }

            activeBlockMode = newMode

            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
        }

        private func toggleChecklist(in textView: NSTextView) {
            let lineRange = currentLineRange(in: textView)
            let lineText = (textView.string as NSString).substring(with: lineRange)
            var newMode: ActiveBlockMode = .none
            if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 2), with: "")
                newMode = .none
            } else {
                textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "☐ ")
                newMode = .checklist
            }
            resetToNormalTypingAttributes(textView)
            activeBlockMode = newMode

            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            textView.sizeToFit()
        }

        private func currentLineRange(in textView: NSTextView) -> NSRange {
            (textView.string as NSString).lineRange(for: textView.selectedRange())
        }

        private func resetToNormalTypingAttributes(_ textView: NSTextView) {
            isInHeadingMode = false
            activeBlockMode = .none
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight),
                .foregroundColor: parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
                .paragraphStyle: defaultParagraphStyle()
            ]
        }

        /// Reset only inline formatting (bold/italic/heading font) but preserve block mode
        /// so bullet/list continuation still works on the new line.
        private func resetInlineFormattingOnly(_ textView: NSTextView) {
            isInHeadingMode = false
            var attrs = textView.typingAttributes
            attrs[.font] = NSFont.systemFont(ofSize: parent.fontSize, weight: parent.baseFontWeight)
            attrs[.foregroundColor] = parent.darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary)
            attrs.removeValue(forKey: RichDocumentAttributeKeys.headingLevel)
            // Preserve existing paragraphStyle (block indentation) if in a list
            if attrs[.paragraphStyle] == nil {
                attrs[.paragraphStyle] = defaultParagraphStyle()
            }
            textView.typingAttributes = attrs
        }

        private func defaultParagraphStyle() -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            if parent.singleLine || parent.titleConfiguration != nil {
                style.lineSpacing = 0
                style.paragraphSpacing = 0
            } else if parent.compact {
                style.lineSpacing = 4
                style.paragraphSpacing = 8
            } else {
                style.lineSpacing = 6
                style.paragraphSpacing = 12
            }
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
            let currentString = textView.string
            parent.plainText = currentString
            parent.cursorPosition = textView.selectedRange().location
            // Fire direct callback immediately — SwiftUI's @Binding→onChange chain
            // can coalesce/skip when mutations come from AppKit outside the update cycle.
            parent.onPlainTextDidChange?(currentString)

            // Immediately resize AppKit frame so there's no visual gap
            // between text insertion and container resize (the deferred
            // notifyContentHeightChange fires 50ms later for the SwiftUI callback,
            // but AppKit needs to match right now to prevent a visible glitch).
            resizeAppKitFrameIfNeeded(for: textView)

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

        /// Immediate AppKit resize + single coordinated SwiftUI update.
        /// Resizes the NSTextView frame, updates intrinsicContentSize, AND fires
        /// the SwiftUI height callback in one synchronous pass. This prevents the
        /// double-jitter caused by intrinsicContentSize invalidation and the deferred
        /// SwiftUI callback landing in separate layout passes.
        private func resizeAppKitFrameIfNeeded(for textView: NSTextView) {
            guard !parent.scrollsInternally,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView as? CosmoScrollView else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let measuredHeight = measuredSingleLineContentHeight(for: textView)
                ?? ceil(usedRect.height + (textView.textContainerInset.height * 2))
            let newHeight = max(0, measuredHeight)

            let currentWidth = max(scrollView.contentSize.width, textView.frame.width)
            if textView.frame.height != newHeight || abs(textView.frame.width - currentWidth) > 0.5 {
                textView.setFrameSize(NSSize(width: currentWidth, height: newHeight))
            }
            if abs((scrollView.intrinsicHeight ?? 0) - newHeight) > 1.0 {
                scrollView.intrinsicHeight = newHeight
                scrollView.invalidateIntrinsicContentSize()
            }

            // Fire the SwiftUI callback NOW — keeps intrinsicContentSize and
            // bodyEditorHeight/textContentHeight in sync so SwiftUI does a single
            // layout pass, not two (which caused the visible double-jitter).
            if abs(newHeight - lastReportedHeight) > 1.0 {
                lastReportedHeight = newHeight
                parent.onContentHeightChange?(newHeight)
            }

            // Reset any internal scroll offset — in non-scrolling mode the clip
            // view should always sit at origin so content doesn't shift visually.
            let clipView = scrollView.contentView
            if clipView.bounds.origin != .zero {
                clipView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        fileprivate func notifyContentHeightChange(for textView: NSTextView) {
            guard let callback = parent.onContentHeightChange else {
                return
            }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            var nonScrollingViewportWidth: CGFloat?
            if !parent.scrollsInternally,
               let scrollView = textView.enclosingScrollView as? CosmoScrollView {
                let targetWidth = max(scrollView.contentSize.width, 1)
                // For singleLine editors, override container width to prevent wrapping.
                // For multi-line editors, widthTracksTextView handles the container width
                // automatically — do NOT set it manually (the double-change breaks layout).
                if parent.singleLine {
                    let targetContainerWidth = CGFloat.greatestFiniteMagnitude
                    if abs(textContainer.containerSize.width - targetContainerWidth) > 0.5 {
                        textContainer.containerSize = NSSize(
                            width: targetContainerWidth,
                            height: parent.resolvedSingleLineHeight()
                        )
                    }
                }
                if abs(textView.frame.width - targetWidth) > 0.5 {
                    textView.setFrameSize(NSSize(width: targetWidth, height: max(textView.frame.height, 1)))
                }
                nonScrollingViewportWidth = targetWidth
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let measuredHeight = measuredSingleLineContentHeight(for: textView)
                ?? ceil(usedRect.height + (textView.textContainerInset.height * 2))
            let minimum: CGFloat
            if parent.singleLine {
                minimum = parent.resolvedSingleLineHeight()
            } else if parent.titleConfiguration != nil {
                minimum = parent.resolvedTitleMinimumHeight()
            } else {
                minimum = 0
            }
            let newHeight = max(minimum, measuredHeight)

            if !parent.scrollsInternally,
               let scrollView = textView.enclosingScrollView as? CosmoScrollView {
                let currentWidth = nonScrollingViewportWidth ?? max(scrollView.contentSize.width, textView.frame.width)
                if textView.frame.height != newHeight || abs(textView.frame.width - currentWidth) > 0.5 {
                    textView.setFrameSize(NSSize(width: currentWidth, height: newHeight))
                }
                if abs((scrollView.intrinsicHeight ?? 0) - newHeight) > 1.0 {
                    scrollView.intrinsicHeight = newHeight
                    // Defer invalidation when called during SwiftUI's layout pass
                    // to avoid "Modifying state during view update" re-entrancy.
                    if isUpdatingFromSwiftUI {
                        DispatchQueue.main.async {
                            scrollView.invalidateIntrinsicContentSize()
                        }
                    } else {
                        scrollView.invalidateIntrinsicContentSize()
                    }
                }
            }
            // Only notify when height changes by >1pt to prevent sub-pixel jitter
            guard abs(newHeight - lastReportedHeight) > 1.0 else {
                return
            }
            lastReportedHeight = newHeight
            // Defer callback to next run loop — notifyContentHeightChange may be called
            // from makeNSView/updateNSView during SwiftUI's layout pass.
            DispatchQueue.main.async {
                callback(newHeight)
            }
        }

        fileprivate func normalizeSingleLineViewport(for textView: NSTextView) {
            guard parent.singleLine,
                  let scrollView = textView.enclosingScrollView else {
                return
            }

            let targetHeight = max(
                parent.resolvedSingleLineHeight(),
                measuredSingleLineContentHeight(for: textView) ?? 0
            )
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

        private func measuredSingleLineContentHeight(for textView: NSTextView) -> CGFloat? {
            guard parent.singleLine,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return nil
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return ceil(usedRect.height + (textView.textContainerInset.height * 2))
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
