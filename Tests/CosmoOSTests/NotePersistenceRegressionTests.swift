import XCTest
@testable import CosmoOS

final class NotePersistenceRegressionTests: XCTestCase {
    func testRelinkingBlockToSavedAtomPreservesCanvasIdentityAndUsesAtomContent() {
        var atom = Atom.new(
            type: .note,
            title: "Saved note",
            body: "The long pasted document that must stay attached to the block."
        )
        atom.id = 42

        let original = CanvasBlock.noteBlock(
            position: CGPoint(x: 120, y: 240),
            content: "stale draft"
        )

        let relinked = original.relinked(to: atom)

        XCTAssertEqual(relinked.id, original.id)
        XCTAssertEqual(relinked.position, original.position)
        XCTAssertEqual(relinked.size, original.size)
        XCTAssertEqual(relinked.entityType, .note)
        XCTAssertEqual(relinked.entityId, 42)
        XCTAssertEqual(relinked.entityUuid, atom.uuid)
        XCTAssertEqual(relinked.title, "Saved note")
        XCTAssertEqual(relinked.metadata["content"], atom.body)
    }

    func testNoteWritePolicyRejectsNonEditedEmptyOverwriteOfExistingBody() {
        XCTAssertFalse(NoteWritePolicy.allowsBodyWrite(
            existingBody: "Existing note body",
            proposedBody: "",
            hasLocalEdits: false
        ))
    }

    func testNoteWritePolicyAllowsIntentionalEmptyDeleteWhenLocallyEdited() {
        XCTAssertTrue(NoteWritePolicy.allowsBodyWrite(
            existingBody: "Existing note body",
            proposedBody: "",
            hasLocalEdits: true
        ))
    }
}
