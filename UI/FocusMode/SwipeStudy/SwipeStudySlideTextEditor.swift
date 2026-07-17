// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudySlideTextEditor.swift
// Per-slide transcript editor (NSTextView). Command-Return inserts a new
// slide; Return is a plain newline. Extracted verbatim from the old
// SwipeStudyFocusModeView during the July 2026 rebuild.

import SwiftUI
import AppKit

// MARK: - Transcript card palette (shared by slide cards + editor)

enum SwipeTranscriptCardPalette {
    static var fill: Color {
        DS.palette.isDark ? DS.surfaceCard : DS.vellumDeep
    }

    static var border: Color {
        DS.palette.isDark ? DS.focusImmersiveBorder : DS.sepiaBorder
    }

    static var text: Color {
        DS.palette.isDark ? DS.text : DS.inkWash
    }

    static var secondaryText: Color {
        DS.palette.isDark ? DS.textSecondary : DS.inkFaded
    }

    static var mutedText: Color {
        DS.palette.isDark ? DS.textMuted : DS.inkFaded
    }
}

/// A text editor for a single transcript slide.
/// Command-Return creates a new slide; Return inserts a newline.
struct SlideTextEditor: NSViewRepresentable {
    let slideID: UUID
    @Binding var text: String
    @Binding var focusRequestID: UUID?
    var onNewSlide: () -> Void
    var textColor: Color = SwipeTranscriptCardPalette.text

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        let editorTextColor = NSColor(textColor)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = editorTextColor
        textView.backgroundColor = .clear
        textView.insertionPointColor = editorTextColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isVerticallyResizable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 4)

        // Add visual spacing between paragraphs (lines separated by \n)
        // This is display-only — doesn't modify stored text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: editorTextColor,
            .paragraphStyle: paragraphStyle,
        ]
        textView.delegate = context.coordinator

        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        // Set initial text with paragraph spacing
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: textView.typingAttributes))

        context.coordinator.textView = textView
        context.coordinator.lastSyncedText = text
        context.coordinator.lastAppliedColor = textColor

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        // Color churn guard: NSColor(Color) conversion + property sets on
        // every SwiftUI update are wasted work when nothing changed (there is
        // one editor per slide — a transcript re-eval touches all of them).
        if context.coordinator.lastAppliedColor != textColor {
            let editorTextColor = NSColor(textColor)
            textView.textColor = editorTextColor
            textView.insertionPointColor = editorTextColor
            context.coordinator.lastAppliedColor = textColor
        }
        // Compare against the coordinator's shadow copy — `textView.string`
        // bridges (copies) the whole document on every access.
        if context.coordinator.lastSyncedText != text {
            let editorTextColor = NSColor(textColor)
            let selectedRange = textView.selectedRange()
            let isFirstResponder = textView.window?.firstResponder === textView
            // Apply paragraph spacing via attributed string so it persists through updates
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = 6
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: editorTextColor,
                .paragraphStyle: paragraphStyle,
            ]
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
            context.coordinator.lastSyncedText = text
            if isFirstResponder {
                let clampedLocation = min(selectedRange.location, text.utf16.count)
                let remainingLength = max(0, text.utf16.count - clampedLocation)
                let clampedLength = min(selectedRange.length, remainingLength)
                textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            }
        }

        if focusRequestID == slideID,
           textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
            let caretLocation = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
            focusRequestID = nil
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 260
        guard let textView = nsView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return CGSize(width: width, height: 60)
        }
        // Only resize the container on a real width change and never force a
        // full relayout — SwiftUI probes repeatedly, and the forced-invalidate
        // pattern livelocked the assistant pane (July 2026). Edits invalidate
        // through the text storage on their own.
        let containerWidth = width - 8
        if abs(textContainer.containerSize.width - containerWidth) > 0.25 {
            textContainer.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: width, height: max(60, ceil(usedRect.height) + 12))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onNewSlide: onNewSlide)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onNewSlide: () -> Void
        weak var textView: NSTextView?
        var lastSyncedText: String = ""
        var lastAppliedColor: Color?

        init(text: Binding<String>, onNewSlide: @escaping () -> Void) {
            self.text = text
            self.onNewSlide = onNewSlide
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Command-Return inserts a new slide beneath the current one.
                if NSEvent.modifierFlags.contains(.command) {
                    onNewSlide()
                    return true
                }
            }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lastSyncedText = textView.string
            text.wrappedValue = textView.string
        }
    }
}
