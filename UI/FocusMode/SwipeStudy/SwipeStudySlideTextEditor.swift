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

/// First-paint stand-in for `SlideTextEditor`: renders the slide text as plain
/// SwiftUI Text, pixel-matched to the NSTextView (13pt system font, 4pt
/// insets, 60pt floor) so the later swap is invisible. Mounting one AppKit
/// text stack per slide during the study's entrance frame was the open hitch;
/// stand-ins cost nothing. A click promotes to the real editors immediately.
struct SlideTextStandIn: View {
    let text: String
    let onActivate: () -> Void

    var body: some View {
        Text(text)
            // Font.system(size:) is deliberate here despite the DS convention:
            // parity with the NSTextView's systemFont(ofSize: 13) is the whole
            // point — a DS token that drifts would make the swap visibly reflow.
            .font(Font.system(size: 13))
            .foregroundStyle(SwipeTranscriptCardPalette.text)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minHeight: 60, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Tap to edit")
    }
}

/// The slide editor's text view. One transcript is many NSTextViews, and a
/// plain NSTextView keeps its selection when it stops being first responder —
/// so highlighting slide 2 after slide 1 left BOTH lit (one in the active
/// wash, one in the grey inactive one), and the study read as two competing
/// selections. There is one highlight in a transcript: the one under your
/// hand. Losing first responder collapses the selection to its caret, so the
/// insertion point is exactly where you left it when you click back.
final class SwipeSlideTextView: NSTextView {

    /// The same scroll view / text view pairing `NSTextView.scrollableTextView()`
    /// builds — width-tracking container, vertically resizable, no scroller —
    /// but with this subclass as the document view.
    static func makeScrollableEditor() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        let textView = SwipeSlideTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            collapseSelectionToCaret()
        }
        return resigned
    }

    /// Fold any range down to its insertion point. Called on the way out of
    /// first responder, so the next slide you highlight is the only one lit.
    func collapseSelectionToCaret() {
        let range = selectedRange()
        guard range.length > 0 else { return }
        setSelectedRange(NSRange(location: range.location, length: 0))
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
        let scrollView = SwipeSlideTextView.makeScrollableEditor()
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
