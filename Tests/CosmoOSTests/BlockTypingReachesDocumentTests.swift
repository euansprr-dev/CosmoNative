import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

/// Regression tests for the July 20 2026 data-loss bug: text typed into a
/// block row never reached the bound RichDocument, so an autosave (and the
/// close-save) persisted a stale document. Only Return-splits — which carry
/// `livePlainText` explicitly — rescued a block's text, which is why blocks
/// the user pressed Return after survived and the rest were truncated to
/// whatever the document happened to hold.
///
/// These tests drive the REAL NSTextView (view → document direction), which
/// the performance bench does not: it edits through the binding instead.
@MainActor
final class BlockTypingReachesDocumentTests: XCTestCase {

    @Observable
    final class DocumentModel {
        var document: RichDocument
        init(document: RichDocument) { self.document = document }
    }

    private struct Host: View {
        let model: DocumentModel
        let focusCoordinator: BlockFocusCoordinator

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                BlockListView(
                    document: Binding(
                        get: { model.document },
                        set: { model.document = $0 }
                    ),
                    fontSize: 17,
                    placeholder: "",
                    darkMode: false,
                    overrideTextColor: NSColor.textColor,
                    allowSlashCommands: true,
                    allowMentions: true,
                    allowSelectionMenu: true,
                    allowImages: true,
                    typewriterMode: false,
                    scrollsInternally: false,
                    editorTargetID: "test:note",
                    focusCoordinator: focusCoordinator
                )
                .frame(width: 700, alignment: .topLeading)
            }
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func textViews(in root: NSView?) -> [CosmoTextView] {
        guard let root else { return [] }
        var found: [CosmoTextView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let tv = view as? CosmoTextView { found.append(tv) }
            stack.append(contentsOf: view.subviews)
        }
        // Subview walk order is not document order; sort by window Y (top first).
        return found.sorted {
            let a = $0.convert($0.bounds, to: nil).origin.y
            let b = $1.convert($1.bounds, to: nil).origin.y
            return a > b
        }
    }

    /// Mounts the list and returns (window, model, sorted text views).
    private func mount(_ document: RichDocument) -> (NSWindow, DocumentModel, [CosmoTextView]) {
        let model = DocumentModel(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(
            rootView: Host(model: model, focusCoordinator: BlockFocusCoordinator())
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        pump(1.0)
        return (window, model, textViews(in: window.contentView))
    }

    private func text(of model: DocumentModel, at index: Int) -> String {
        guard index < model.document.blocks.count else { return "<missing>" }
        return model.document.blocks[index].plainInlineText
    }

    func testSelectedBlocksCopyAndDeleteThroughRealEditor() throws {
        let original = RichDocument(blocks: [.paragraph("First"), .paragraph("Second"), .paragraph("Third")])
        let (window, model, views) = mount(original)
        defer { window.contentView = nil; window.orderOut(nil) }
        let row = try XCTUnwrap(views.first)
        window.makeFirstResponder(row)
        XCTAssertTrue(row.onSelectAllEscalation?() == true)
        pump(0.15)

        XCTAssertTrue(MainKeyboardShortcutPolicy.reservesDocumentKeyboard(in: window))
        XCTAssertTrue(BlockSelectionClipboardTarget.send(.copy, in: window))
        let data = try XCTUnwrap(NSPasteboard.general.data(forType: .cosmoBlocks))
        XCTAssertEqual(try JSONDecoder().decode([RichBlock].self, from: data), original.blocks)

        let otherWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        XCTAssertFalse(BlockSelectionClipboardTarget.send(.delete, in: otherWindow))
        XCTAssertEqual(model.document, original, "A different window must never delete the note's selection")

        let delete = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51
        ))
        XCTAssertTrue(row.performKeyEquivalent(with: delete))
        pump(0.2)
        XCTAssertEqual(model.document.blocks.count, 1)
        XCTAssertEqual(model.document.blocks.first?.plainInlineText, "")
        XCTAssertTrue(window.undoManager?.canUndo == true)
        window.undoManager?.undo()
        pump(0.15)
        XCTAssertEqual(model.document, original)
    }

    /// THE BUG: type several characters into a bullet row; every one of them
    /// must reach the document. Before the fix only the first landed.
    func testTypingMultipleCharactersReachesDocument() throws {
        let doc = RichDocument(blocks: [
            RichBlock(kind: .bulletList, inlines: [.text("first line")]),
            RichBlock(kind: .bulletList, inlines: [.text("")]),
            RichBlock(kind: .bulletList, inlines: [.text("third line")])
        ])
        let (window, model, views) = mount(doc)
        defer { window.orderOut(nil) }

        XCTAssertGreaterThanOrEqual(views.count, 3, "expected a text view per block")
        let target = views[1]
        window.makeFirstResponder(target)
        pump(0.3)
        // Caret at the very end, past the rendered "• " prefix.
        target.setSelectedRange(NSRange(location: (target.string as NSString).length, length: 0))

        let typed = "Testing the viral hook as an ad"
        for character in typed {
            target.insertText(String(character), replacementRange: target.selectedRange())
            pump(0.02) // faster than the 50ms coalesce, like real typing
        }
        pump(1.0) // let every deferred sync + document write settle

        XCTAssertEqual(
            text(of: model, at: 1), typed,
            "typed text never reached the document — this is the data-loss bug"
        )
    }

    /// The same row, but the user pauses between characters (each keystroke
    /// gets its own deferred-sync window). This passed even before the fix
    /// for the first character only, so it pins the incremental case.
    func testTypingWithPausesReachesDocument() throws {
        let doc = RichDocument(blocks: [
            RichBlock(kind: .bulletList, inlines: [.text("")])
        ])
        let (window, model, views) = mount(doc)
        defer { window.orderOut(nil) }

        let target = try XCTUnwrap(views.first)
        window.makeFirstResponder(target)
        pump(0.3)
        target.setSelectedRange(NSRange(location: (target.string as NSString).length, length: 0))

        for character in "Claude" {
            target.insertText(String(character), replacementRange: target.selectedRange())
            pump(0.25) // well past the 50ms coalesce
        }
        pump(0.5)

        XCTAssertEqual(text(of: model, at: 0), "Claude")
    }
}
