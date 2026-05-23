import XCTest
@testable import CosmoOS

final class NotePersistenceRegressionTests: XCTestCase {
    func testNoteFocusTextAnalysisBuildsMetricsFromOneSnapshot() {
        let text = """
        # Opening
        Some linked [[Alpha]] text with several words.
        ## Middle
        Another [[Beta]] paragraph.
        ### Detail
        """

        let analysis = NoteFocusTextAnalysis.analyze(text)

        XCTAssertEqual(analysis.wordCount, 13)
        XCTAssertEqual(analysis.estimatedReadingMinutes, 1)
        XCTAssertEqual(analysis.outLinkCount, 2)
        XCTAssertEqual(
            analysis.headings,
            [
                NoteHeadingEntry(level: 1, text: "Opening"),
                NoteHeadingEntry(level: 2, text: "Middle"),
                NoteHeadingEntry(level: 3, text: "Detail")
            ]
        )
    }

    func testNoteAutosavePolicyUsesPlainTextLaneForLargeTypingSaves() {
        let policy = NoteAutosavePolicy(
            richCheckpointCharacterThreshold: 4_000,
            richCheckpointInterval: 30
        )

        let kind = policy.saveKind(
            plainTextCharacterCount: 12_000,
            now: Date(timeIntervalSince1970: 10),
            lastRichCheckpointAt: Date(timeIntervalSince1970: 0),
            isClosing: false
        )

        XCTAssertEqual(kind, .plainText)
    }

    func testNoteAutosavePolicyCheckpointsRichDocumentAfterIdleInterval() {
        let policy = NoteAutosavePolicy(
            richCheckpointCharacterThreshold: 4_000,
            richCheckpointInterval: 30
        )

        let kind = policy.saveKind(
            plainTextCharacterCount: 12_000,
            now: Date(timeIntervalSince1970: 31),
            lastRichCheckpointAt: Date(timeIntervalSince1970: 0),
            isClosing: false
        )

        XCTAssertEqual(kind, .richDocumentCheckpoint)
    }

    func testNoteAutosavePolicyAlwaysCheckpointsWhenClosing() {
        let policy = NoteAutosavePolicy(
            richCheckpointCharacterThreshold: 4_000,
            richCheckpointInterval: 30
        )

        let kind = policy.saveKind(
            plainTextCharacterCount: 12_000,
            now: Date(timeIntervalSince1970: 1),
            lastRichCheckpointAt: Date(timeIntervalSince1970: 0),
            isClosing: true
        )

        XCTAssertEqual(kind, .richDocumentCheckpoint)
    }

    func testNoteAutosaveChangePolicySkipsUnchangedEditorCallbacks() {
        XCTAssertFalse(NoteAutosaveChangePolicy.shouldAutosaveTextChange(
            isInitialLoad: false,
            didChange: false
        ))
    }

    func testNoteAutosaveChangePolicySavesChangedEditorCallbacksAfterInitialLoad() {
        XCTAssertTrue(NoteAutosaveChangePolicy.shouldAutosaveTextChange(
            isInitialLoad: false,
            didChange: true
        ))
    }

    func testNoteAutosaveChangePolicySkipsInitialLoadCallbacks() {
        XCTAssertFalse(NoteAutosaveChangePolicy.shouldAutosaveTextChange(
            isInitialLoad: true,
            didChange: true
        ))
    }

    func testEditorHeightUpdatePolicyIgnoresLayoutNoise() {
        XCTAssertFalse(EditorHeightUpdatePolicy.shouldPublish(
            current: 120,
            next: 120.4
        ))
    }

    func testEditorHeightUpdatePolicyPublishesMeaningfulHeightChanges() {
        XCTAssertTrue(EditorHeightUpdatePolicy.shouldPublish(
            current: 120,
            next: 124
        ))
    }

    func testEditorHeightUpdatePolicyRejectsInvalidHeights() {
        XCTAssertFalse(EditorHeightUpdatePolicy.shouldPublish(
            current: 120,
            next: .infinity
        ))
        XCTAssertFalse(EditorHeightUpdatePolicy.shouldPublish(
            current: 120,
            next: 0
        ))
    }

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

    func testNoteWritePolicyRequiresFlushBeforeFocusModeWhenBlockHasLocalEdits() {
        XCTAssertTrue(NoteWritePolicy.requiresBlockFlushBeforeFocusMode(
            hasLocalEdits: true,
            entityId: 42,
            entityUUID: "note-uuid"
        ))
    }

    func testNoteWritePolicyDoesNotFlushCleanBlockBeforeFocusMode() {
        XCTAssertFalse(NoteWritePolicy.requiresBlockFlushBeforeFocusMode(
            hasLocalEdits: false,
            entityId: 42,
            entityUUID: "note-uuid"
        ))
    }
}
