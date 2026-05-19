import AppKit
import WebKit
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

    func testClickInsideTextEditorScrollContainerDoesNotRequestBlurForFocusedTextView() {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        scrollView.documentView = textView

        XCTAssertFalse(
            FocusModeEditorBlur.shouldClearEditableFirstResponder(
                currentResponder: textView,
                hitView: scrollView
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

@MainActor
final class MainKeyboardShortcutPolicyTests: XCTestCase {
    func testWebViewResponderReservesKeyboardInputForBrowser() {
        let webView = WKWebView()

        XCTAssertTrue(MainKeyboardShortcutPolicy.isTypingTarget(webView))
    }

    func testWebViewDescendantResponderReservesKeyboardInputForBrowser() {
        let webView = WKWebView()
        let descendant = NSView()
        webView.addSubview(descendant)

        XCTAssertTrue(MainKeyboardShortcutPolicy.isTypingTarget(descendant))
    }

    func testRegularResponderDoesNotReserveKeyboardInput() {
        XCTAssertFalse(MainKeyboardShortcutPolicy.isTypingTarget(NSButton()))
    }
}

final class NoteFocusHeaderLayoutPolicyTests: XCTestCase {
    func testEmptyNoteUsesEditableHeroTitle() {
        let mode = NoteFocusHeaderLayoutPolicy.chromeMode(
            titlePlainText: "",
            plainContent: ""
        )

        XCTAssertEqual(mode, .emptyEditableTitle)
        XCTAssertTrue(NoteFocusHeaderLayoutPolicy.showsEmptyGuidance(for: mode))
        XCTAssertTrue(NoteFocusHeaderLayoutPolicy.showsTitleUnderline(for: mode))
    }

    func testWrittenNoteUsesOnlyMetadataDividerBelowDateRow() {
        let mode = NoteFocusHeaderLayoutPolicy.chromeMode(
            titlePlainText: "A title",
            plainContent: "Body text"
        )

        XCTAssertEqual(mode, .documentHeader)
        XCTAssertFalse(NoteFocusHeaderLayoutPolicy.showsEmptyGuidance(for: mode))
        XCTAssertFalse(NoteFocusHeaderLayoutPolicy.showsTitleUnderline(for: mode))
        XCTAssertTrue(NoteFocusHeaderLayoutPolicy.showsMetadataDivider(for: mode))
    }
}
