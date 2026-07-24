// CosmoOS/UI/CaptureOverlay/TokenWashTextView.swift
// The native highlighted text field — the Mac port of the iPhone's
// TokenWashTextView: ONE NSTextView (TextKit 2) that colors recognized runs,
// draws their soft rounded washes itself, and floats a ghost completion tail
// off the real caret rect, all in the same layout pass as the text. One text
// engine, zero drift — never a mirror Text over a real field.
// July 2026 — Capture Anywhere lane highlights

import SwiftUI
import AppKit

// TEMP [WashProbe] — remove after Today quick-add focus bug is diagnosed.
// NSLog does not persist to the unified log on this machine, so the probe
// appends straight to a file the debugging session tails.
func washProbeLog(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/cosmos-washprobe.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: url)
    }
}
// The window is the first responder of record after a makeFirstResponder(nil)
// — the exact state where keystrokes beep. Log every clear with its caller so
// the next recurrence names the code that yanked focus.
extension NSWindow {
    @objc func washProbe_makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // Swizzled: this call reaches the ORIGINAL implementation.
        let ok = washProbe_makeFirstResponder(responder)
        if ok {
            if responder == nil || responder === self {
                let stack = Thread.callStackSymbols.dropFirst().prefix(14).joined(separator: " | ")
                washProbeLog("FR CLEARED to window — caller: \(stack)")
            } else {
                washProbeLog("FR -> \(String(describing: type(of: responder!)))")
            }
        }
        return ok
    }
}
// END TEMP [WashProbe]

/// A highlighted run: UTF-16 range into the current text plus its ink color.
/// The wash behind the run is the ink at low opacity.
struct TextWashSegment: Equatable {
    let utf16Range: Range<Int>
    let ink: NSColor
}

struct TokenWashTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var ink: NSColor = NSColor(DS.text)
    var caretTint: NSColor = NSColor(DS.accent)
    var segments: [TextWashSegment] = []
    /// Display-only completion tail drawn after the text end ("g" shows
    /// "roceries:" ahead of the caret). Never part of the real text.
    var ghostText: String? = nil
    var ghostColor: NSColor = NSColor(DS.textMuted)
    /// Cap the field's growth at N lines. nil = grow forever.
    var maxLines: Int? = nil
    @Binding var isFocused: Bool
    var onSubmit: () -> Void = {}
    /// Optional Tab handler — hosts embedding the field in a form use this to
    /// move focus onward. nil keeps NSTextView's default (inserts a tab).
    var onTab: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 2 stack — never touch .layoutManager, which downgrades.
        let textView = WashTextView(usingTextLayoutManager: true)
        textView.configureWashField()
        textView.delegate = context.coordinator

        // An NSTextView belongs inside an NSScrollView: the scroll view is the
        // pane that CLIPS overflow and scrolls it. Without it the field —
        // vertically resizable — grows its own frame past the capped box and
        // the text spills out. We keep the scroller hidden so the input stays
        // a calm glass box; the scroll wheel and caret-follow still work, so a
        // long capture scrolls within its four lines instead of falling out.
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? WashTextView else { return }
        context.coordinator.parent = self

        textView.font = font
        textView.insertionPointColor = caretTint

        if textView.string != text {
            textView.string = text
            // External rewrites (suggestion acceptance) land the caret at the end.
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            textView.scrollCaretToVisible()
        }

        textView.placeholderLabel.stringValue = placeholder
        textView.placeholderLabel.font = font
        textView.placeholderLabel.textColor = NSColor(DS.textMuted)
        textView.placeholderLabel.isHidden = !text.isEmpty

        textView.applyInk(ink, font: font, segments: segments)
        textView.ghost = ghostText.map { ($0, ghostColor) }

        // Focus sync — deferred so first-responder moves never happen inside
        // a SwiftUI update pass. The block re-reads the CURRENT desire at
        // execution time so a stale capture can't fight a dismissal.
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            let wantsFocus = coordinator.parent.isFocused
            let isFirstResponder = window.firstResponder === textView
            if wantsFocus, !isFirstResponder {
                // TEMP [WashProbe] — remove after Today quick-add focus bug is diagnosed
                washProbeLog("update block acquires focus (placeholder: \(coordinator.parent.placeholder)); current FR: \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
                window.makeFirstResponder(textView)
            }
        }

        textView.needsLayout = true
        textView.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? WashTextView else { return nil }
        let width = proposal.width ?? 400
        textView.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        var height = ceil(textView.measuredTextHeight())
        let lineHeight = ceil(font.ascender + abs(font.descender) + font.leading)
        height = max(height, lineHeight)
        // The cap turns the box from "grows forever" into "scrolls past N lines":
        // we report the capped height, and the taller text view scrolls inside it.
        if let maxLines {
            height = min(height, ceil(lineHeight * CGFloat(maxLines)) + 1)
        }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TokenWashTextView

        init(parent: TokenWashTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? WashTextView else { return }
            parent.text = view.string
            view.placeholderLabel.isHidden = !view.string.isEmpty
            view.scrollCaretToVisible()
            view.needsLayout = true
            view.needsDisplay = true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)), let onTab = parent.onTab {
                onTab()
                return true
            }
            return false
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}

// MARK: - The NSTextView that paints its own washes

final class WashTextView: NSTextView {
    /// Same geometry as the iPhone renderer: pad each glyph-run rect a touch,
    /// merge same-line neighbours so a phrase reads as one wash, round the corners.
    private static let washInset = CGSize(width: -3.5, height: -1.5)
    private static let mergeGap: CGFloat = 8
    private static let washCornerRadius: CGFloat = 6

    let placeholderLabel = NSTextField(labelWithString: "")
    private let ghostLabel = NSTextField(labelWithString: "")

    private var currentSegments: [TextWashSegment] = []

    var ghost: (text: String, color: NSColor)? {
        didSet { needsLayout = true }
    }

    // TEMP [WashProbe] diagnostics — remove after Today quick-add focus bug is diagnosed.
    // Logs the deepest AppKit view under every left-click in any window, whether
    // mouseDown ever reaches a wash field, and who holds/steals first responder.
    private static let clickSpy: Void = {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            if let window = event.window,
               let frameView = window.contentView?.superview {
                let hit = frameView.hitTest(event.locationInWindow)
                washProbeLog("leftMouseDown at \(NSStringFromPoint(event.locationInWindow)) hit-tests to \(hit.map { String(describing: type(of: $0)) } ?? "nil") (FR before: \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"))")
            }
            return event
        }
        // Attribute every focus hand-off: log all makeFirstResponder calls,
        // with a call stack when something CLEARS focus (responder == nil) —
        // that clear is the suspected yank that leaves the window beeping.
        if let original = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.makeFirstResponder(_:))),
           let probe = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.washProbe_makeFirstResponder(_:))) {
            method_exchangeImplementations(original, probe)
        }
        return ()
    }()

    override func mouseDown(with event: NSEvent) {
        washProbeLog("mouseDown reached WashTextView (placeholder: \(placeholderLabel.stringValue))")
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        washProbeLog("becomeFirstResponder -> \(ok) (placeholder: \(placeholderLabel.stringValue))")
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            DispatchQueue.main.async { [weak self] in
                let fr = self?.window?.firstResponder
                washProbeLog("resigned first responder; new FR: \(fr.map { String(describing: type(of: $0)) } ?? "nil")")
            }
        }
        return ok
    }
    // END TEMP [WashProbe]

    /// One-time field setup — called from makeNSView (no init overrides, so
    /// the TextKit 2 convenience initializer stays inherited).
    func configureWashField() {
        _ = Self.clickSpy
        drawsBackground = false
        isRichText = false
        allowsUndo = true
        // The canonical NSTextView-in-NSScrollView geometry: the view grows
        // vertically with its content and lets the scroll view clip it, while
        // its width tracks the clip view so wrapping matches what's measured.
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
        textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.lineFragmentPadding = 0
        textContainerInset = .zero

        placeholderLabel.isSelectable = false
        addSubview(placeholderLabel)

        ghostLabel.isSelectable = false
        ghostLabel.setAccessibilityHidden(true)
        addSubview(ghostLabel)
    }

    /// Recolor the current text: base ink everywhere, segment inks on their
    /// runs. Font and layout NEVER change — color only — so this can run on
    /// every update without disturbing typing or undo. Skipped mid-composition.
    func applyInk(_ ink: NSColor, font: NSFont, segments: [TextWashSegment]) {
        currentSegments = segments
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        typingAttributes = base
        guard !hasMarkedText(), let storage = textStorage, storage.length > 0 else { return }

        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(base, range: full)
        for segment in segments {
            guard segment.utf16Range.lowerBound >= 0, segment.utf16Range.upperBound <= full.length else { continue }
            storage.addAttribute(
                .foregroundColor,
                value: segment.ink,
                range: NSRange(location: segment.utf16Range.lowerBound, length: segment.utf16Range.count)
            )
        }
        storage.endEditing()
        needsDisplay = true
    }

    func measuredTextHeight() -> CGFloat {
        guard let textLayoutManager else { return 0 }
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        return textLayoutManager.usageBoundsForTextContainer.height
    }

    /// Keep the insertion point inside the visible band as the capture grows
    /// past the cap — so typing scrolls the field instead of hiding the caret.
    func scrollCaretToVisible() {
        scrollRangeToVisible(selectedRange())
    }

    override func layout() {
        super.layout()
        placeholderLabel.sizeToFit()
        placeholderLabel.frame.origin = CGPoint(
            x: textContainerOrigin.x,
            y: textContainerOrigin.y
        )
        layoutGhost()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawWashes()
        super.draw(dirtyRect)
    }

    /// Wash rects come from the SAME TextKit 2 layout that draws the glyphs —
    /// per line fragment, so a token that wraps gets one wash per line, each
    /// exactly under its own glyphs.
    private func drawWashes() {
        guard !currentSegments.isEmpty,
              let textLayoutManager,
              let contentManager = textLayoutManager.textContentManager else { return }
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        var washes: [(rect: CGRect, color: NSColor)] = []
        let origin = textContainerOrigin

        for segment in currentSegments {
            guard segment.utf16Range.lowerBound >= 0,
                  let start = contentManager.location(contentManager.documentRange.location, offsetBy: segment.utf16Range.lowerBound),
                  let end = contentManager.location(contentManager.documentRange.location, offsetBy: segment.utf16Range.upperBound),
                  let textRange = NSTextRange(location: start, end: end) else { continue }

            // A whisper of a wash — the colored ink carries the token.
            let wash = segment.ink.withAlphaComponent(0.10)
            textLayoutManager.enumerateTextSegments(in: textRange, type: .highlight, options: []) { _, frame, _, _ in
                let rect = frame.offsetBy(dx: origin.x, dy: origin.y)
                    .insetBy(dx: Self.washInset.width, dy: Self.washInset.height)
                if let last = washes.last, rect.minX - last.rect.maxX < Self.mergeGap,
                   abs(rect.midY - last.rect.midY) < 1, last.color == wash {
                    washes[washes.count - 1].rect = last.rect.union(rect)
                } else {
                    washes.append((rect, wash))
                }
                return true
            }
        }

        for wash in washes {
            wash.color.setFill()
            NSBezierPath(
                roundedRect: wash.rect,
                xRadius: Self.washCornerRadius,
                yRadius: Self.washCornerRadius
            ).fill()
        }
    }

    /// The ghost completion rides the caret rect at the end of the document,
    /// so it always sits exactly after the last real glyph.
    private func layoutGhost() {
        guard let ghost, !string.isEmpty else {
            ghostLabel.isHidden = true
            return
        }
        ghostLabel.isHidden = false
        ghostLabel.stringValue = ghost.text
        ghostLabel.textColor = ghost.color
        ghostLabel.font = font
        ghostLabel.sizeToFit()

        guard let textLayoutManager else { return }
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        let endLocation = textLayoutManager.documentRange.endLocation
        var caret = CGRect(origin: textContainerOrigin, size: .zero)
        textLayoutManager.enumerateTextSegments(
            in: NSTextRange(location: endLocation), type: .standard, options: [.rangeNotRequired]
        ) { _, frame, _, _ in
            caret = frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            return false
        }
        ghostLabel.frame.origin = CGPoint(
            x: caret.maxX,
            y: caret.midY - ghostLabel.bounds.height / 2
        )
    }
}
