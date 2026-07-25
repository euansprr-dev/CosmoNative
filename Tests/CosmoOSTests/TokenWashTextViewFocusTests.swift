import AppKit
import XCTest
@testable import CosmoOS

/// Clicks on the wash field's floating chrome (placeholder, ghost tail) must
/// hit-test to the text view itself. Under SwiftUI's window, a click that
/// hit-tests to a label only reaches the text view as a responder-chain
/// forward — a path that never makes it first responder — so an empty field
/// whose placeholder swallowed the hit could not be clicked into focus
/// (Today quick-add regression, July 2026).
@MainActor
final class TokenWashTextViewFocusTests: XCTestCase {

    private func makeFieldStack() -> (window: NSWindow, textView: WashTextView) {
        // Mirror TokenWashTextView.makeNSView: WashTextView inside an NSScrollView.
        let textView = WashTextView(usingTextLayoutManager: true)
        textView.configureWashField()

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 360, height: 20))
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(scrollView)
        return (window, textView)
    }

    private func hitTest(at pointInTextView: NSPoint, window: NSWindow, textView: WashTextView) -> NSView? {
        let frameView = window.contentView!.superview!
        return frameView.hitTest(textView.convert(pointInTextView, to: frameView))
    }

    func testClickOverPlaceholderHitsTheTextView() {
        let (window, textView) = makeFieldStack()
        textView.placeholderLabel.stringValue = "Add task... (try \"Write at 6pm every Tue\")"
        textView.placeholderLabel.isHidden = false
        window.layoutIfNeeded()

        let labelCenter = NSPoint(x: textView.placeholderLabel.frame.midX, y: textView.placeholderLabel.frame.midY)
        let hit = hitTest(at: labelCenter, window: window, textView: textView)

        XCTAssertTrue(
            hit === textView,
            "Click over the placeholder must hit the text view so the window focuses it; hit \(String(describing: hit)) instead"
        )
    }

    func testClickOverGhostTailHitsTheTextView() throws {
        let (window, textView) = makeFieldStack()
        textView.string = "g"
        textView.ghost = ("roceries", .gray)
        window.layoutIfNeeded()
        textView.layout()

        let ghostLabel = try XCTUnwrap(
            textView.subviews.compactMap { $0 as? NSTextField }
                .first { $0 !== textView.placeholderLabel && !$0.isHidden }
        )
        let ghostCenter = NSPoint(x: ghostLabel.frame.midX, y: ghostLabel.frame.midY)
        let hit = hitTest(at: ghostCenter, window: window, textView: textView)

        XCTAssertTrue(
            hit === textView,
            "Click over the ghost completion must hit the text view; hit \(String(describing: hit)) instead"
        )
    }
}
