// CosmoOS/UI/CosmoWindow/MentionComposerTextView.swift
// NSViewRepresentable chat composer with live @-mention colorization
// March 2026

import SwiftUI
import AppKit

/// A multiline text editor for the Cosmo overlay that colorizes @-mention
/// patterns inline using entity-type colors from `CosmoMentionColors`.
struct MentionComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let mentionedAtoms: [Atom]
    let placeholder: String
    var isFocused: Binding<Bool>
    var onSubmit: () -> Void
    var onTextChange: () -> Void

    /// Maximum number of visible lines before scrolling kicks in.
    private static let maxVisibleLines = 4
    /// Approximate line height for the composer font.
    fileprivate static let composerLineHeight: CGFloat = 20

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
        textView.string = text
        textView.placeholderString = placeholder

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }

        // Update callbacks
        textView.onSubmit = onSubmit
        context.coordinator.parent = self

        // Sync text if it changed externally (e.g., mention insertion, clear on send)
        if textView.string != text {
            textView.string = text
            // Place cursor at end when text is set externally
            let end = (text as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
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
            parent.text = textView.string
            parent.onTextChange()
            applyMentionHighlighting(textView)
            updateIntrinsicHeight(textView)
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

            let maxHeight = MentionComposerTextView.composerLineHeight * CGFloat(MentionComposerTextView.maxVisibleLines) + 4
            let clampedHeight = min(textHeight, maxHeight)

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

/// NSScrollView subclass that reports an intrinsic content size so SwiftUI
/// can size the composer based on text content, capped at a maximum height.
final class ComposerScrollView: NSScrollView {
    var intrinsicHeight: CGFloat = MentionComposerTextView.composerLineHeight + 4

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
    var placeholderString: String = ""

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return key
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
