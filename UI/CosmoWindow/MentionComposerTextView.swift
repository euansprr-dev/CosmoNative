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
    /// When true, completed mentions render as atomic capsule pills (icon + title) and
    /// `text` is projected back to plain `"@<title>"` tokens. Opt-in per composer.
    var usesPillMentions: Bool = false
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

        // Sync text if it changed externally (e.g., mention insertion, clear on send).
        // In pill mode the text view holds attachments, so compare against the plain
        // projection and rebuild pills + map the plain selection back to text-view offsets.
        let currentPlain = context.coordinator.currentPlainText(textView)
        let textChanged = currentPlain != text

        if usesPillMentions {
            if textChanged {
                textView.string = text
                context.coordinator.applyMentionPills(textView)
            }
            if let storage = textView.textStorage {
                let attributed = ComposerMentionSerializer.attributedRange(forPlainRange: selection, in: storage)
                if textChanged || !MentionComposerTextSelectionPolicy.rangesEqual(textView.selectedRange(), attributed) {
                    textView.setSelectedRange(attributed)
                }
            }
        } else if textChanged {
            let oldLength = (currentPlain as NSString).length
            let selectionWasAtOldEnd = selection.location == oldLength && selection.length == 0
            textView.string = text

            let newSelection: NSRange
            if selectionWasAtOldEnd {
                newSelection = NSRange(location: (text as NSString).length, length: 0)
            } else {
                newSelection = MentionComposerTextSelectionPolicy.clamped(selection, in: text)
            }
            textView.setSelectedRange(newSelection)
            context.coordinator.applyMentionHighlighting(textView)
        } else {
            let clampedSelection = MentionComposerTextSelectionPolicy.clamped(selection, in: text)
            if !MentionComposerTextSelectionPolicy.rangesEqual(textView.selectedRange(), clampedSelection) {
                textView.setSelectedRange(clampedSelection)
            }
            context.coordinator.applyMentionHighlighting(textView)
        }

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
            if parent.usesPillMentions, let storage = textView.textStorage {
                parent.selection = ComposerMentionSerializer.plainRange(forAttributedRange: textView.selectedRange(), in: storage)
                parent.text = ComposerMentionSerializer.plainString(from: storage)
            } else {
                parent.selection = textView.selectedRange()
                parent.text = textView.string
                applyMentionHighlighting(textView)
            }
            parent.onTextChange()
            updateIntrinsicHeight(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange: NSRange
            if parent.usesPillMentions, let storage = textView.textStorage {
                selectedRange = ComposerMentionSerializer.plainRange(forAttributedRange: textView.selectedRange(), in: storage)
            } else {
                selectedRange = textView.selectedRange()
            }
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

        /// Plain-text projection of the composer (pills become their `"@<title>"` token).
        func currentPlainText(_ textView: NSTextView) -> String {
            if parent.usesPillMentions, let storage = textView.textStorage {
                return ComposerMentionSerializer.plainString(from: storage)
            }
            return textView.string
        }

        /// Replaces completed mention tokens with atomic capsule pills, preserving the
        /// caret in plain space across the length change.
        func applyMentionPills(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }

            let plainCaret = ComposerMentionSerializer.plainOffset(
                forAttributedOffset: textView.selectedRange().location,
                in: storage
            )

            storage.beginEditing()

            let fullRange = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.foregroundColor, value: NSColor(DS.text), range: fullRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .regular), range: fullRange)
            storage.removeAttribute(.backgroundColor, range: fullRange)

            for atom in parent.mentionedAtoms {
                let token = "@\(atom.title ?? "Untitled")"
                guard token.count > 1 else { continue }

                // Collect matches against the live string, then substitute back-to-front
                // so earlier ranges stay valid as the text shortens.
                var matches: [NSRange] = []
                var searchStart = 0
                while searchStart < storage.length {
                    let searchRange = NSRange(location: searchStart, length: storage.length - searchStart)
                    let found = (storage.string as NSString).range(of: token, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }
                    matches.append(found)
                    searchStart = found.location + found.length
                }

                for range in matches.reversed() {
                    let pill = CosmoMentionPillAttachment(atom: atom, token: token)
                    storage.replaceCharacters(in: range, with: NSAttributedString(attachment: pill))
                }
            }

            storage.endEditing()

            // Keep new typing as normal text rather than inheriting attachment attributes.
            textView.typingAttributes = [
                .foregroundColor: NSColor(DS.text),
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]

            let restored = ComposerMentionSerializer.attributedOffset(forPlainOffset: plainCaret, in: storage)
            textView.setSelectedRange(NSRange(location: min(restored, storage.length), length: 0))
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

// MARK: - Mention pills

/// A single, atomic mention rendered as a capsule (type icon + title) inside the
/// composer's text storage. It stores `token` — the plain-text projection (`"@<title>"`)
/// — so the composer can serialize back to a clean string for the agent and the parser.
final class CosmoMentionPillAttachment: NSTextAttachment {
    let token: String
    let title: String
    let tint: NSColor

    init(atom: Atom, token: String) {
        self.token = token
        self.title = atom.title ?? "Untitled"
        let entityType = EntityType(rawValue: atom.type.rawValue) ?? .note
        self.tint = CosmoMentionColors.nsColor(for: entityType)
        super.init(data: nil, ofType: nil)
        self.attachmentCell = CosmoMentionPillCell(
            title: title,
            iconName: atom.type.iconName,
            tint: tint
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CosmoMentionPillAttachment is not archivable")
    }
}

/// Draws the capsule: tinted rounded background, type SF Symbol, and the title.
/// Property names are prefixed to avoid colliding with `NSCell`'s `title`/`font`.
final class CosmoMentionPillCell: NSTextAttachmentCell {
    private let pillTitle: String
    private let pillIcon: NSImage?
    private let pillTint: NSColor
    private let pillFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    private let hPad: CGFloat = 8
    private let iconSize: CGFloat = 12
    private let gap: CGFloat = 5
    private let vPad: CGFloat = 2
    private let maxTitleChars = 32

    init(title: String, iconName: String, tint: NSColor) {
        self.pillTitle = title
        self.pillTint = tint
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        self.pillIcon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("CosmoMentionPillCell is not archivable")
    }

    private var displayTitle: String {
        guard pillTitle.count > maxTitleChars else { return pillTitle }
        return String(pillTitle.prefix(maxTitleChars - 1)) + "…"
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [.font: pillFont, .foregroundColor: pillTint]
    }

    private func titleSize() -> NSSize {
        (displayTitle as NSString).size(withAttributes: titleAttributes)
    }

    override func cellSize() -> NSSize {
        let titleWidth = ceil(titleSize().width)
        let width = hPad + iconSize + gap + titleWidth + hPad
        let height = ceil(pillFont.ascender - pillFont.descender) + vPad * 2
        return NSSize(width: width, height: height)
    }

    override func cellBaselineOffset() -> NSPoint {
        // Drop the capsule so the title baseline lines up with the surrounding text.
        NSPoint(x: 0, y: pillFont.descender - vPad)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        let radius = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        pillTint.withAlphaComponent(0.12).setFill()
        path.fill()

        let midY = rect.midY
        var cursorX = rect.minX + hPad

        if let pillIcon {
            let tinted = Self.tinted(pillIcon, with: pillTint)
            let iconRect = NSRect(x: cursorX, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            tinted.draw(in: iconRect)
            cursorX += iconSize + gap
        }

        let size = titleSize()
        let textRect = NSRect(x: cursorX, y: midY - size.height / 2, width: size.width, height: size.height)
        (displayTitle as NSString).draw(in: textRect, withAttributes: titleAttributes)
    }

    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}

/// Projects between the composer's attributed storage (which contains pill attachments)
/// and the plain `"@<title>"` token string the agent and mention parser operate on.
enum ComposerMentionSerializer {
    static func plainString(from storage: NSTextStorage) -> String {
        let nsString = storage.string as NSString
        var result = ""
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let pill = value as? CosmoMentionPillAttachment {
                result += pill.token
            } else {
                result += nsString.substring(with: range)
            }
        }
        return result
    }

    /// Attributed (text-view) offset → plain projection offset.
    static func plainOffset(forAttributedOffset attributedOffset: Int, in storage: NSTextStorage) -> Int {
        let clamped = max(0, min(attributedOffset, storage.length))
        var plain = 0
        var index = 0
        while index < clamped {
            if let pill = storage.attribute(.attachment, at: index, effectiveRange: nil) as? CosmoMentionPillAttachment {
                plain += (pill.token as NSString).length
            } else {
                plain += 1
            }
            index += 1
        }
        return plain
    }

    /// Plain projection offset → attributed (text-view) offset.
    static func attributedOffset(forPlainOffset plainOffset: Int, in storage: NSTextStorage) -> Int {
        var plain = 0
        var index = 0
        while index < storage.length {
            if plain >= plainOffset { return index }
            if let pill = storage.attribute(.attachment, at: index, effectiveRange: nil) as? CosmoMentionPillAttachment {
                plain += (pill.token as NSString).length
            } else {
                plain += 1
            }
            index += 1
        }
        return storage.length
    }

    static func attributedRange(forPlainRange plainRange: NSRange, in storage: NSTextStorage) -> NSRange {
        let start = attributedOffset(forPlainOffset: plainRange.location, in: storage)
        let end = attributedOffset(forPlainOffset: plainRange.location + plainRange.length, in: storage)
        return NSRange(location: start, length: max(0, end - start))
    }

    static func plainRange(forAttributedRange attributedRange: NSRange, in storage: NSTextStorage) -> NSRange {
        let start = plainOffset(forAttributedOffset: attributedRange.location, in: storage)
        let end = plainOffset(forAttributedOffset: attributedRange.location + attributedRange.length, in: storage)
        return NSRange(location: start, length: max(0, end - start))
    }
}
