// CosmoOS/UI/CosmoWindow/MentionComposerTextView.swift
// NSViewRepresentable chat composer with live @-mention colorization
// March 2026

import SwiftUI
import AppKit

/// A multiline text editor for the Cosmo overlay that colorizes @-mention
/// patterns inline using entity-type colors from `CosmoMentionColors`.
struct MentionComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let mentionedAtoms: [Atom]
    let placeholder: String
    var isFocused: Binding<Bool>
    var isMentionOverlayVisible: Bool = false
    var onSubmit: () -> Void
    var onTextChange: () -> Void
    var onDismissMentionOverlayFromBackspace: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ComposerScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = ComposerNSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(DS.text)
        textView.insertionPointColor = NSColor(DS.text)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.isMentionOverlayVisible = isMentionOverlayVisible
        textView.onDismissMentionOverlayFromBackspace = onDismissMentionOverlayFromBackspace
        textView.string = text
        textView.placeholderString = placeholder
        textView.setSelectedRange(MentionComposerTextSelectionPolicy.clamped(selection, in: text))

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }

        // Update callbacks
        textView.onSubmit = onSubmit
        textView.isMentionOverlayVisible = isMentionOverlayVisible
        textView.onDismissMentionOverlayFromBackspace = onDismissMentionOverlayFromBackspace
        context.coordinator.parent = self

        // Sync text if it changed externally (e.g., mention insertion, clear on send)
        if textView.string != text {
            let oldLength = (textView.string as NSString).length
            let selectionWasAtOldEnd = selection.location == oldLength && selection.length == 0
            textView.string = text

            let newSelection: NSRange
            if selectionWasAtOldEnd {
                newSelection = NSRange(location: (text as NSString).length, length: 0)
            } else {
                newSelection = MentionComposerTextSelectionPolicy.clamped(selection, in: text)
            }
            textView.setSelectedRange(newSelection)
        } else {
            let clampedSelection = MentionComposerTextSelectionPolicy.clamped(selection, in: text)
            if !MentionComposerTextSelectionPolicy.rangesEqual(textView.selectedRange(), clampedSelection) {
                textView.setSelectedRange(clampedSelection)
            }
        }

        // Apply mention highlighting
        context.coordinator.applyMentionHighlighting(textView)

        // Recalculate intrinsic height
        context.coordinator.updateIntrinsicHeight(textView)

        // Update placeholder visibility
        textView.needsDisplay = true
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MentionComposerTextView
        weak var textView: ComposerNSTextView?
        weak var scrollView: ComposerScrollView?

        init(_ parent: MentionComposerTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusRequest),
                name: .focusCosmoComposer,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleFocusRequest() {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selection = textView.selectedRange()
            parent.text = textView.string
            parent.onTextChange()
            applyMentionHighlighting(textView)
            updateIntrinsicHeight(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange = textView.selectedRange()
            if !MentionComposerTextSelectionPolicy.rangesEqual(parent.selection, selectedRange) {
                parent.selection = selectedRange
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }

        /// Recalculates the scroll view's intrinsic content height based on text content,
        /// capped at `maxVisibleLines` lines before becoming scrollable.
        func updateIntrinsicHeight(_ textView: NSTextView) {
            guard let scrollView, let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let textHeight = usedRect.height + textView.textContainerInset.height * 2

            let clampedHeight = MentionComposerSizingPolicy.clampedHeight(forContentHeight: textHeight)

            // Only update if height actually changed to avoid layout loops
            if abs(scrollView.intrinsicHeight - clampedHeight) > 0.5 {
                scrollView.intrinsicHeight = clampedHeight
                scrollView.invalidateIntrinsicContentSize()
            }
        }

        func applyMentionHighlighting(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let content = textView.string
            guard !content.isEmpty else { return }

            let fullRange = NSRange(location: 0, length: (content as NSString).length)
            let selectedRange = textView.selectedRange()

            storage.beginEditing()

            // Reset all text to default appearance
            storage.addAttribute(.foregroundColor, value: NSColor(DS.text), range: fullRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .regular), range: fullRange)
            storage.removeAttribute(.backgroundColor, range: fullRange)

            // Colorize each mentioned atom's @Title
            for atom in parent.mentionedAtoms {
                let title = atom.title ?? "Untitled"
                let pattern = "@\(title)"
                let entityType = EntityType(rawValue: atom.type.rawValue) ?? .note
                let color = CosmoMentionColors.nsColor(for: entityType)

                var searchStart = content.startIndex
                while let range = content.range(of: pattern, range: searchStart..<content.endIndex) {
                    let nsRange = NSRange(range, in: content)
                    storage.addAttribute(.foregroundColor, value: color, range: nsRange)
                    storage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.1), range: nsRange)
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .semibold), range: nsRange)
                    searchStart = range.upperBound
                }
            }

            storage.endEditing()

            // Restore cursor position
            if selectedRange.location <= (content as NSString).length {
                textView.setSelectedRange(selectedRange)
            }
        }
    }
}

// MARK: - Custom ScrollView with intrinsic height

enum MentionComposerSizingPolicy {
    /// Maximum number of visible lines before scrolling kicks in.
    static let maxVisibleLines = 4
    /// Approximate line height for the composer font.
    static let composerLineHeight: CGFloat = 20
    static let minimumHeight: CGFloat = composerLineHeight + 4

    static func clampedHeight(forContentHeight textHeight: CGFloat) -> CGFloat {
        let maxHeight = composerLineHeight * CGFloat(maxVisibleLines) + 4
        return max(minimumHeight, min(textHeight, maxHeight))
    }
}

struct MentionComposerActiveMention: Equatable {
    let query: String
    let range: NSRange
}

struct MentionComposerTextReplacement: Equatable {
    let text: String
    let selection: NSRange
}

enum MentionComposerMentionParser {
    static func activeMention(in text: String, selectedRange: NSRange) -> MentionComposerActiveMention? {
        let nsText = text as NSString
        let caret = MentionComposerTextSelectionPolicy.clamped(selectedRange, in: text).location
        guard caret > 0 else { return nil }

        var index = caret - 1
        while index >= 0 {
            let character = nsText.substring(with: NSRange(location: index, length: 1))
            if character == "@" {
                guard isMentionBoundaryBefore(index: index, in: nsText) else { return nil }

                let queryRange = NSRange(location: index + 1, length: caret - index - 1)
                let query = nsText.substring(with: queryRange)
                guard query.rangeOfCharacter(from: .newlines) == nil else { return nil }

                return MentionComposerActiveMention(
                    query: query,
                    range: NSRange(location: index, length: caret - index)
                )
            }

            if character.rangeOfCharacter(from: .newlines) != nil {
                return nil
            }

            index -= 1
        }

        return nil
    }

    static func replacingActiveMention(
        in text: String,
        selectedRange: NSRange,
        title: String
    ) -> MentionComposerTextReplacement {
        if let activeMention = activeMention(in: text, selectedRange: selectedRange) {
            return replacingRange(
                activeMention.range,
                in: text,
                withMentionTitle: title
            )
        }

        return insertingMentionTitle(title, in: text, selectedRange: selectedRange)
    }

    static func insertingMentionTrigger(
        in text: String,
        selectedRange: NSRange
    ) -> MentionComposerTextReplacement {
        let nsText = text as NSString
        let selectedRange = MentionComposerTextSelectionPolicy.clamped(selectedRange, in: text)
        let prefix = nsText.substring(to: selectedRange.location)
        let needsLeadingSpace = !prefix.isEmpty && !prefix.hasSuffixWhitespace
        let insertion = needsLeadingSpace ? " @" : "@"
        let updated = nsText.replacingCharacters(in: selectedRange, with: insertion)
        let cursor = selectedRange.location + (insertion as NSString).length

        return MentionComposerTextReplacement(
            text: updated,
            selection: NSRange(location: cursor, length: 0)
        )
    }

    static func removingActiveMention(
        in text: String,
        selectedRange: NSRange
    ) -> MentionComposerTextReplacement? {
        guard let activeMention = activeMention(in: text, selectedRange: selectedRange) else { return nil }
        let nsText = text as NSString
        let updated = nsText.replacingCharacters(in: activeMention.range, with: "")

        return MentionComposerTextReplacement(
            text: updated,
            selection: NSRange(location: activeMention.range.location, length: 0)
        )
    }

    private static func replacingRange(
        _ range: NSRange,
        in text: String,
        withMentionTitle title: String
    ) -> MentionComposerTextReplacement {
        let nsText = text as NSString
        var replacement = "@\(title)"
        let suffixStart = range.location + range.length
        let suffixStartsWithWhitespace = suffixStart < nsText.length
            && nsText.substring(with: NSRange(location: suffixStart, length: 1)).hasPrefixWhitespace

        if !suffixStartsWithWhitespace {
            replacement += " "
        }

        let updated = nsText.replacingCharacters(in: range, with: replacement)
        let replacementLength = (replacement as NSString).length
        let separatorLength = suffixStartsWithWhitespace ? 1 : 0
        let cursor = min(range.location + replacementLength + separatorLength, (updated as NSString).length)

        return MentionComposerTextReplacement(
            text: updated,
            selection: NSRange(location: cursor, length: 0)
        )
    }

    private static func insertingMentionTitle(
        _ title: String,
        in text: String,
        selectedRange: NSRange
    ) -> MentionComposerTextReplacement {
        let trigger = insertingMentionTrigger(in: text, selectedRange: selectedRange)
        return replacingActiveMention(in: trigger.text, selectedRange: trigger.selection, title: title)
    }

    private static func isMentionBoundaryBefore(index: Int, in text: NSString) -> Bool {
        guard index > 0 else { return true }
        let previous = text.substring(with: NSRange(location: index - 1, length: 1))
        return previous.rangeOfCharacter(from: .alphanumerics) == nil && previous != "_"
    }
}

enum MentionComposerTextSelectionPolicy {
    static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = max(0, min(range.location, length))
        let upperBound = max(location, min(range.location + range.length, length))
        return NSRange(location: location, length: upperBound - location)
    }

    static func rangesEqual(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        lhs.location == rhs.location && lhs.length == rhs.length
    }
}

enum MentionComposerKeyHandlingPolicy {
    static let backspaceKeyCode: UInt16 = 51

    static func shouldDismissMentionOverlay(keyCode: UInt16, isMentionOverlayVisible: Bool) -> Bool {
        isMentionOverlayVisible && keyCode == backspaceKeyCode
    }
}

private extension String {
    var hasSuffixWhitespace: Bool {
        guard let last else { return false }
        return last.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    var hasPrefixWhitespace: Bool {
        guard let first else { return false }
        return first.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

/// NSScrollView subclass that reports an intrinsic content size so SwiftUI
/// can size the composer based on text content, capped at a maximum height.
final class ComposerScrollView: NSScrollView {
    var intrinsicHeight: CGFloat = MentionComposerSizingPolicy.minimumHeight

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: intrinsicHeight)
    }
}

// MARK: - Custom NSTextView

/// Notification posted to request focus on the Cosmo composer.
extension Notification.Name {
    static let focusCosmoComposer = Notification.Name("focusCosmoComposer")
}

/// Custom NSTextView that handles Enter/Escape and shows placeholder text.
final class ComposerNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onDismissMentionOverlayFromBackspace: (() -> Void)?
    var isMentionOverlayVisible = false
    var placeholderString: String = ""

    override func keyDown(with event: NSEvent) {
        if MentionComposerKeyHandlingPolicy.shouldDismissMentionOverlay(
            keyCode: event.keyCode,
            isMentionOverlayVisible: isMentionOverlayVisible
        ) {
            onDismissMentionOverlayFromBackspace?()
        } else if event.keyCode == 36 { // Return key
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                onSubmit?()
            }
        } else if event.keyCode == 53 { // Escape key
            // Let the responder chain handle Escape (CosmoWindowView dismisses overlay)
            super.keyDown(with: event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder when empty
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(DS.textMuted),
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
            let placeholder = NSAttributedString(string: placeholderString, attributes: attrs)
            let inset = textContainerInset
            let padding = textContainer?.lineFragmentPadding ?? 0
            let rect = NSRect(
                x: inset.width + padding,
                y: inset.height,
                width: bounds.width - (inset.width + padding) * 2,
                height: bounds.height - inset.height * 2
            )
            placeholder.draw(in: rect)
        }
    }
}
