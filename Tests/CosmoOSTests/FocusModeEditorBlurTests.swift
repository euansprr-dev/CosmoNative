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

    func testFocusModeClipboardRoutesKeyEquivalentToActiveTextViewWhenFirstResponderIsStale() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let staleFirstResponder = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
        let activeTextView = NSTextView(frame: NSRect(x: 180, y: 0, width: 160, height: 100))
        contentView.addSubview(staleFirstResponder)
        contentView.addSubview(activeTextView)
        window.contentView = contentView

        staleFirstResponder.string = ""
        activeTextView.string = ""
        activeTextView.setSelectedRange(NSRange(location: 0, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("outline paste", forType: .string)

        FocusModeTextClipboardTarget.activate(activeTextView)

        XCTAssertTrue(FocusModeTextClipboardTarget.performKeyEquivalent(commandKeyEvent("v"), fallback: staleFirstResponder))
        XCTAssertEqual(staleFirstResponder.string, "")
        XCTAssertEqual(activeTextView.string, "outline paste")
    }

    func testFocusModeClipboardSendActionUsesActiveTextView() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let activeTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
        window.contentView = activeTextView
        activeTextView.string = ""
        activeTextView.setSelectedRange(NSRange(location: 0, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("menu paste", forType: .string)

        FocusModeTextClipboardTarget.activate(activeTextView)

        XCTAssertTrue(FocusModeTextClipboardTarget.send(.paste, in: window))
        XCTAssertEqual(activeTextView.string, "menu paste")
    }

    func testContentBodyTextViewHandlesPasteboardKeyEquivalentsDirectly() {
        let textView = CosmoTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        textView.isEditable = true

        textView.string = "body copy"
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        NSPasteboard.general.clearContents()

        XCTAssertTrue(textView.performKeyEquivalent(with: commandKeyEvent("c")))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "body")

        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("body paste", forType: .string)

        XCTAssertTrue(textView.performKeyEquivalent(with: commandKeyEvent("v")))
        XCTAssertEqual(textView.string, "body paste")
    }

    func testFocusModeClipboardPrefersCurrentFieldEditorOverStaleActiveTarget() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let staleTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
        let fieldEditor = NSTextView(frame: NSRect(x: 180, y: 0, width: 160, height: 100))
        fieldEditor.isFieldEditor = true
        contentView.addSubview(staleTextView)
        contentView.addSubview(fieldEditor)
        window.contentView = contentView

        staleTextView.string = ""
        fieldEditor.string = ""
        fieldEditor.setSelectedRange(NSRange(location: 0, length: 0))
        FocusModeTextClipboardTarget.activate(staleTextView)
        XCTAssertTrue(window.makeFirstResponder(fieldEditor))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("outline paste", forType: .string)

        XCTAssertTrue(FocusModeTextClipboardTarget.send(.paste, in: window))
        XCTAssertEqual(staleTextView.string, "")
        XCTAssertEqual(fieldEditor.string, "outline paste")

        fieldEditor.setSelectedRange(NSRange(location: 0, length: 7))
        NSPasteboard.general.clearContents()

        XCTAssertTrue(FocusModeTextClipboardTarget.send(.copy, in: window))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "outline")
    }

    func testFocusModeClipboardPrefersFocusedEditableTextViewOverStaleActiveTarget() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let staleTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
        let focusedTextView = NSTextView(frame: NSRect(x: 180, y: 0, width: 160, height: 100))
        contentView.addSubview(staleTextView)
        contentView.addSubview(focusedTextView)
        window.contentView = contentView

        staleTextView.string = ""
        focusedTextView.string = ""
        focusedTextView.setSelectedRange(NSRange(location: 0, length: 0))
        FocusModeTextClipboardTarget.activate(staleTextView)
        XCTAssertTrue(window.makeFirstResponder(focusedTextView))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("assistant paste", forType: .string)

        XCTAssertTrue(FocusModeTextClipboardTarget.send(.paste, in: window))
        XCTAssertEqual(staleTextView.string, "")
        XCTAssertEqual(focusedTextView.string, "assistant paste")

        focusedTextView.setSelectedRange(NSRange(location: 0, length: 9))
        NSPasteboard.general.clearContents()

        XCTAssertTrue(FocusModeTextClipboardTarget.send(.copy, in: window))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "assistant")
    }

    func testAssistantComposerClaimsClipboardTargetWhenFocused() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let documentTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
        let composer = ComposerNSTextView(frame: NSRect(x: 180, y: 0, width: 160, height: 100))
        contentView.addSubview(documentTextView)
        contentView.addSubview(composer)
        window.contentView = contentView

        documentTextView.string = ""
        composer.string = ""
        composer.setSelectedRange(NSRange(location: 0, length: 0))
        FocusModeTextClipboardTarget.activate(documentTextView)

        XCTAssertTrue(window.makeFirstResponder(composer))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("assistant paste", forType: .string)

        XCTAssertTrue(FocusModeTextClipboardTarget.send(.paste, in: window))
        XCTAssertEqual(documentTextView.string, "")
        XCTAssertEqual(composer.string, "assistant paste")
    }

    func testAssistantComposerCopiesFromComposerSelectionAfterFocus() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let documentTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
        let composer = ComposerNSTextView(frame: NSRect(x: 180, y: 0, width: 160, height: 100))
        contentView.addSubview(documentTextView)
        contentView.addSubview(composer)
        window.contentView = contentView

        documentTextView.string = "document copy"
        documentTextView.setSelectedRange(NSRange(location: 0, length: 8))
        composer.string = "composer copy"
        composer.setSelectedRange(NSRange(location: 0, length: 8))
        FocusModeTextClipboardTarget.activate(documentTextView)

        XCTAssertTrue(window.makeFirstResponder(composer))

        NSPasteboard.general.clearContents()

        XCTAssertTrue(FocusModeTextClipboardTarget.send(.copy, in: window))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "composer")
    }

    private func commandKeyEvent(_ character: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        )!
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

    func testActiveEmptyTitleEditKeepsEditableHeroChromeAfterTyping() {
        let mode = NoteFocusHeaderLayoutPolicy.chromeMode(
            titlePlainText: "A",
            plainContent: "",
            activeEditChromeMode: .emptyEditableTitle
        )

        XCTAssertEqual(mode, .emptyEditableTitle)
    }
}
