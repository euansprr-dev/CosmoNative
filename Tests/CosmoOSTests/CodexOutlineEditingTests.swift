import AppKit
import XCTest
@testable import CosmoOS

final class CodexOutlineEditingTests: XCTestCase {
    @MainActor
    func testOutlineSlideEditorRetriesPendingFocusUntilWindowAcceptsFirstResponder() throws {
        let window = FlakyFirstResponderWindow()
        let textView = OutlineSlideNoteTextView()
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        window.contentView?.addSubview(textView)

        textView.requestFocusWhenReady()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertIdentical(window.firstResponder, textView)
        XCTAssertGreaterThanOrEqual(window.makeFirstResponderAttempts, 2)
    }

    @MainActor
    func testOutlineSlideFocusRegistryFulfillsFocusRequestedBeforeEditorRegisters() throws {
        let slideID = UUID()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textView = OutlineSlideNoteTextView()
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        window.contentView?.addSubview(textView)

        OutlineSlideFocusRegistry.shared.requestFocus(slideID)
        OutlineSlideFocusRegistry.shared.register(textView, for: slideID)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertIdentical(window.firstResponder, textView)
        OutlineSlideFocusRegistry.shared.unregister(textView, for: slideID)
    }

    @MainActor
    func testOutlineSlideEditorMovesToNextSlideWithDownArrowAtEnd() throws {
        let textView = OutlineSlideNoteTextView()
        textView.string = "Hook"
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))

        var requestedDirection: OutlineSlideNavigationDirection?
        textView.onMoveFocus = { requestedDirection = $0 }
        textView.keyDown(with: arrowKeyEvent(keyCode: 125))

        XCTAssertEqual(requestedDirection, .next)
    }

    @MainActor
    func testOutlineSlideEditorMovesToPreviousSlideWithUpArrowAtStart() throws {
        let textView = OutlineSlideNoteTextView()
        textView.string = "Hook"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        var requestedDirection: OutlineSlideNavigationDirection?
        textView.onMoveFocus = { requestedDirection = $0 }
        textView.keyDown(with: arrowKeyEvent(keyCode: 126))

        XCTAssertEqual(requestedDirection, .previous)
    }

    @MainActor
    func testOutlineSlideEditorHandlesPasteboardKeyEquivalents() throws {
        let textView = OutlineSlideNoteTextView()
        textView.string = "copy me"
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.count))
        NSPasteboard.general.clearContents()

        XCTAssertTrue(textView.performKeyEquivalent(with: commandKeyEvent("c")))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "copy me")

        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("pasted text", forType: .string)

        XCTAssertTrue(textView.performKeyEquivalent(with: commandKeyEvent("v")))
        XCTAssertEqual(textView.string, "pasted text")
    }

    func testInsertSlideAfterFocusedSlideRenumbersAndReturnsInsertedID() {
        let firstID = UUID()
        let secondID = UUID()
        var outline = CodexOutlineModel(arcShape: "Problem-Solution", slides: [
            makeSlide(id: firstID, position: 1, note: "Hook"),
            makeSlide(id: secondID, position: 2, note: "Proof")
        ])

        let insertedID = CodexOutlineEditing.insertSlide(after: firstID, in: &outline)

        XCTAssertEqual(outline.slides.count, 3)
        XCTAssertEqual(outline.slides.map(\.id), [firstID, insertedID, secondID])
        XCTAssertEqual(outline.slides.map(\.position), [1, 2, 3])
        XCTAssertEqual(outline.slides[1].note, nil)
    }

    func testRemoveEmptySlideReturnsPreviousSlideForFocus() {
        let firstID = UUID()
        let emptyID = UUID()
        let thirdID = UUID()
        var outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: firstID, position: 1, note: "Hook"),
            makeSlide(id: emptyID, position: 2, note: ""),
            makeSlide(id: thirdID, position: 3, note: "CTA")
        ])

        let focusID = CodexOutlineEditing.removeSlideIfEmpty(emptyID, in: &outline)

        XCTAssertEqual(focusID, firstID)
        XCTAssertEqual(outline.slides.map(\.id), [firstID, thirdID])
        XCTAssertEqual(outline.slides.map(\.position), [1, 2])
    }

    func testRemoveEmptySlideDoesNotRemoveFirstSlide() {
        let firstID = UUID()
        var outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: firstID, position: 1, note: nil)
        ])

        let focusID = CodexOutlineEditing.removeSlideIfEmpty(firstID, in: &outline)

        XCTAssertNil(focusID)
        XCTAssertEqual(outline.slides.map(\.id), [firstID])
    }

    func testRemoveEmptySlideIgnoresNonEmptySlide() {
        let firstID = UUID()
        let secondID = UUID()
        var outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: firstID, position: 1, note: "Hook"),
            makeSlide(id: secondID, position: 2, note: "Proof")
        ])

        let focusID = CodexOutlineEditing.removeSlideIfEmpty(secondID, in: &outline)

        XCTAssertNil(focusID)
        XCTAssertEqual(outline.slides.map(\.id), [firstID, secondID])
    }

    func testDraftTemplateRepeatsSlideWorkspaceForEachOutlineSlide() {
        let outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: UUID(), position: 1, note: "Hook"),
            makeSlide(id: UUID(), position: 2, note: "Build tension"),
            makeSlide(id: UUID(), position: 3, note: "CTA")
        ])

        XCTAssertEqual(
            CodexOutlineDraftTemplate.make(from: outline),
            """
            SLIDE 1

            --
            SLIDE 2

            --
            SLIDE 3

            --
            """
        )
    }

    func testInsertIntoEmptySlideFillsWritingSpace() {
        let draft = "SLIDE 1\n\n--\nSLIDE 2\n\n--"
        let splice = ContentSlideDraftInsertion.splice(slideNumber: 2, text: "Already-written slide copy.", in: draft)
        let updated = (draft as NSString).replacingCharacters(in: splice.range, with: splice.replacement)

        XCTAssertEqual(updated, "SLIDE 1\n\n--\nSLIDE 2\nAlready-written slide copy.\n--")
    }

    func testInsertIntoSlideWithContentAppendsBelowExistingParagraph() {
        let draft = "SLIDE 1\nExisting hook line.\n--\nSLIDE 2\n\n--"
        let splice = ContentSlideDraftInsertion.splice(slideNumber: 1, text: "New supporting line.", in: draft)
        let updated = (draft as NSString).replacingCharacters(in: splice.range, with: splice.replacement)

        XCTAssertEqual(updated, "SLIDE 1\nExisting hook line.\n\nNew supporting line.\n--\nSLIDE 2\n\n--")
    }

    func testInsertAppendsMissingSlideSectionAtEnd() {
        let draft = "SLIDE 1\nHook.\n--"
        let splice = ContentSlideDraftInsertion.splice(slideNumber: 3, text: "CTA copy.", in: draft)
        let updated = (draft as NSString).replacingCharacters(in: splice.range, with: splice.replacement)

        XCTAssertEqual(updated, "SLIDE 1\nHook.\n--\nSLIDE 3\nCTA copy.\n--")
    }

    func testInsertIntoEmptyDraftCreatesSection() {
        let splice = ContentSlideDraftInsertion.splice(slideNumber: 1, text: "Hook.", in: "")
        let updated = ("" as NSString).replacingCharacters(in: splice.range, with: splice.replacement)

        XCTAssertEqual(updated, "SLIDE 1\nHook.\n--")
    }

    func testInsertRespectsEmDashSeparatorsAndDoesNotMatchLaterSlides() {
        let draft = "SLIDE 1\nDon't buy that Rolex.\n—\nSLIDE 10\n\n--"
        let splice = ContentSlideDraftInsertion.splice(slideNumber: 1, text: "Instead, cash flow.", in: draft)
        let updated = (draft as NSString).replacingCharacters(in: splice.range, with: splice.replacement)

        XCTAssertEqual(updated, "SLIDE 1\nDon't buy that Rolex.\n\nInstead, cash flow.\n—\nSLIDE 10\n\n--")
    }

    func testInsertIntoHeadingDirectlyFollowedBySeparator() {
        let draft = "SLIDE 1\n--\nSLIDE 2\n--"
        let splice = ContentSlideDraftInsertion.splice(slideNumber: 2, text: "Body.", in: draft)
        let updated = (draft as NSString).replacingCharacters(in: splice.range, with: splice.replacement)

        XCTAssertEqual(updated, "SLIDE 1\n--\nSLIDE 2\nBody.\n--")
    }

    func testDraftTemplateRequiresMultipleSlides() {
        let outline = CodexOutlineModel(arcShape: nil, slides: [
            makeSlide(id: UUID(), position: 1, note: "Hook")
        ])

        XCTAssertNil(CodexOutlineDraftTemplate.make(from: outline))
    }

    private func makeSlide(id: UUID, position: Int, note: String?) -> CodexOutlineSlide {
        CodexOutlineSlide(
            id: id,
            position: position,
            speechAct: nil,
            readerDeltas: [],
            frame: nil,
            distance: nil,
            techniques: [],
            transition: nil,
            note: note
        )
    }

    private func arrowKeyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
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

private final class FlakyFirstResponderWindow: NSWindow {
    var makeFirstResponderAttempts = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        makeFirstResponderAttempts += 1
        if makeFirstResponderAttempts == 1 {
            return false
        }
        return super.makeFirstResponder(responder)
    }
}
