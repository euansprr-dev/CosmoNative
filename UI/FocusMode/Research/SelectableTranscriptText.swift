// CosmoOS/UI/FocusMode/Research/SelectableTranscriptText.swift
// NSViewRepresentable wrapping NSTextView for selectable, highlightable transcript text
// February 2026 - Feature 5: Transcript Text Highlighting for Annotation Creation

import SwiftUI
import AppKit

// MARK: - Selectable Transcript Text

/// An NSViewRepresentable that wraps NSTextView for selectable, highlightable transcript text.
/// Displays transcript text with colored highlight backgrounds for annotations,
/// and reports text selections back to SwiftUI via a callback.
struct SelectableTranscriptText: NSViewRepresentable {
    let text: String
    let highlights: [TextHighlight]
    let isPlaying: Bool
    let onTextSelected: (String, NSRange) -> Void

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()

        // Configure text view for display-only, selectable text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.delegate = context.coordinator

        // Size configuration — vertical resizing, fixed width
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        // Build attributed string with highlights applied
        let attributed = buildAttributedString()

        // Replace text storage content atomically via beginEditing/endEditing
        // to prevent garbled/overlapping text from partial layout updates
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(attributed)
        textView.textStorage?.endEditing()

        // Force NSTextView to recalculate display
        textView.needsLayout = true
        textView.needsDisplay = true
    }

    /// Tell SwiftUI the exact height this text view needs
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 260

        guard let layoutManager = nsView.layoutManager,
              let textContainer = nsView.textContainer else {
            return CGSize(width: width, height: 50)
        }

        // Set container width so layout computes correct line wrapping
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)

        // Invalidate entire layout BEFORE ensureLayout to clear stale cached
        // line fragment positions that cause garbled/overlapping text
        let fullRange = NSRange(location: 0, length: nsView.textStorage?.length ?? 0)
        layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: width, height: ceil(usedRect.height) + 4)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Attributed String Builder

    private func buildAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(isPlaying ? 1.0 : 0.7),
            .font: NSFont.systemFont(ofSize: 13),
            .paragraphStyle: paragraphStyle
        ])

        // Apply highlight backgrounds for each annotation highlight
        for highlight in highlights {
            let range = NSRange(
                location: highlight.startCharIndex,
                length: highlight.endCharIndex - highlight.startCharIndex
            )

            // Bounds check to avoid crashes
            guard range.location >= 0,
                  range.location + range.length <= (text as NSString).length else {
                continue
            }

            if highlight.isValid(in: text) {
                // Valid highlight — apply colored background
                attributed.addAttribute(
                    .backgroundColor,
                    value: highlight.annotationType.nsColor.withAlphaComponent(0.25),
                    range: range
                )
            } else {
                // Stale highlight — text has changed, show with underline instead
                attributed.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: highlight.annotationType.nsColor.withAlphaComponent(0.4)
                ], range: range)
            }
        }

        return attributed
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTranscriptText

        init(parent: SelectableTranscriptText) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }
            let selectedText = (textView.string as NSString).substring(with: selectedRange)
            parent.onTextSelected(selectedText, selectedRange)
        }
    }
}
