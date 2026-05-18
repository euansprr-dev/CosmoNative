import AppKit
import XCTest
@testable import CosmoOS

@MainActor
final class FocusModeEditorBlurTests: XCTestCase {
    func testClearFirstResponderReturnsFalseWithoutWindow() {
        XCTAssertFalse(FocusModeEditorBlur.clearFirstResponder(in: nil))
    }

    func testClickOutsideEditableTextRequestsBlurForFocusedTextView() {
        let textView = NSTextView()
        let button = NSButton()

        XCTAssertTrue(
            FocusModeEditorBlur.shouldClearEditableFirstResponder(
                currentResponder: textView,
                hitView: button
            )
        )
    }

    func testClickInsideEditableTextDoesNotRequestBlurForFocusedTextView() {
        let textView = NSTextView()

        XCTAssertFalse(
            FocusModeEditorBlur.shouldClearEditableFirstResponder(
                currentResponder: textView,
                hitView: textView
            )
        )
    }

    func testOutsideClickDoesNotRequestBlurWhenFocusedResponderIsNotEditableText() {
        let button = NSButton()

        XCTAssertFalse(
            FocusModeEditorBlur.shouldClearEditableFirstResponder(
                currentResponder: button,
                hitView: nil
            )
        )
    }
}
