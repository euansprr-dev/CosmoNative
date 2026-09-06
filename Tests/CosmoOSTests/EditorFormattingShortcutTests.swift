import AppKit
import XCTest
@testable import CosmoOS

/// ⌘B / ⌘I / ⌘U / ⇧⌘X reach the FOCUSED editor. A Page mounts many
/// CosmoTextViews in one window (title + one per hydrated block row) and the
/// window's key-equivalent traversal offers the key to every one of them in
/// hierarchy order — a bystander that claims it swallows the shortcut before
/// the focused row is asked. Same window, same class of bug as the clipboard
/// fix in FocusModeEditorBlurTests.
@MainActor
final class EditorFormattingShortcutTests: XCTestCase {

    func testBystanderEditorDefersFormattingKeysToTheFocusedEditor() {
        let (window, bystander, focused) = makeTwoEditorWindow()
        XCTAssertTrue(window.makeFirstResponder(focused))

        for character in ["b", "i", "u"] {
            XCTAssertFalse(
                bystander.performKeyEquivalent(with: keyEvent(character, modifiers: [.command])),
                "⌘\(character.uppercased()) must fall through a bystander so the traversal reaches the focused row"
            )
            XCTAssertTrue(
                focused.performKeyEquivalent(with: keyEvent(character, modifiers: [.command])),
                "the focused editor owns ⌘\(character.uppercased())"
            )
        }
        XCTAssertEqual(focused.selectedRange(), NSRange(location: 0, length: 5), "deferring never disturbs the live selection")
    }

    func testStrikethroughShortcutIsShiftCommandXOnTheFocusedEditorOnly() {
        let (window, bystander, focused) = makeTwoEditorWindow()
        XCTAssertTrue(window.makeFirstResponder(focused))

        XCTAssertFalse(bystander.performKeyEquivalent(with: keyEvent("x", modifiers: [.command, .shift])))
        XCTAssertTrue(focused.performKeyEquivalent(with: keyEvent("x", modifiers: [.command, .shift])))
        // Plain ⌘X stays the clipboard's — never strikethrough.
        NSPasteboard.general.clearContents()
        XCTAssertTrue(focused.performKeyEquivalent(with: keyEvent("x", modifiers: [.command])))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
    }

    func testBlockShortcutsNeverStealTheCaretFromABystander() {
        let (window, bystander, focused) = makeTwoEditorWindow()
        XCTAssertTrue(window.makeFirstResponder(focused))

        // ⌘D duplicate, ⇧⌘L checklist, ⌥⌘↓ move — all block rows' keys.
        XCTAssertFalse(bystander.performKeyEquivalent(with: keyEvent("d", modifiers: [.command])))
        XCTAssertFalse(bystander.performKeyEquivalent(with: keyEvent("l", modifiers: [.command, .shift])))
        XCTAssertFalse(bystander.performKeyEquivalent(with: keyEvent("", modifiers: [.command, .option], keyCode: 125)))
        XCTAssertTrue(window.firstResponder === focused)
    }

    // MARK: - Helpers

    private func makeTwoEditorWindow() -> (NSWindow, CosmoTextView, CosmoTextView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        // The bystander is added first so it is the one a real traversal
        // reaches ahead of the focused editor.
        let bystander = CosmoTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
        let focused = CosmoTextView(frame: NSRect(x: 180, y: 0, width: 160, height: 100))
        bystander.isEditable = true
        focused.isEditable = true
        contentView.addSubview(bystander)
        contentView.addSubview(focused)
        window.contentView = contentView

        bystander.string = "bystander"
        focused.string = "hello world"
        focused.setSelectedRange(NSRange(location: 0, length: 5))
        return (window, bystander, focused)
    }

    private func keyEvent(_ character: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
