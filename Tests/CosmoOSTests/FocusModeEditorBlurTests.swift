import AppKit
import XCTest
@testable import CosmoOS

@MainActor
final class FocusModeEditorBlurTests: XCTestCase {
    func testClearFirstResponderBlursFocusedTextView() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.close() }

        let textView = NSTextView(frame: NSRect(x: 20, y: 20, width: 280, height: 160))
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.addSubview(textView)

        XCTAssertTrue(window.makeFirstResponder(textView))
        XCTAssertTrue(window.firstResponder === textView)

        XCTAssertTrue(FocusModeEditorBlur.clearFirstResponder(in: window))
        XCTAssertFalse(window.firstResponder === textView)
    }

    func testClearFirstResponderReturnsFalseWithoutWindow() {
        XCTAssertFalse(FocusModeEditorBlur.clearFirstResponder(in: nil))
    }
}
