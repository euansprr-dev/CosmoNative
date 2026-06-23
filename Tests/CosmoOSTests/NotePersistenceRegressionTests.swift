import AppKit
import XCTest
@testable import CosmoOS

final class NotePersistenceRegressionTests: XCTestCase {
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testOrdinaryReturnUsesLightweightTypingSyncInsteadOfSynchronousStructuralRelayout() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/TextKitCoordinator.swift"),
            encoding: .utf8
        )
        let newlineRange = try XCTUnwrap(source.range(of: "private func insertNormalNewline"))
        let menuRange = try XCTUnwrap(
            source.range(
                of: "// MARK: - Menu State",
                range: newlineRange.lowerBound..<source.endIndex
            )
        )
        let newlineSource = String(source[newlineRange.lowerBound..<menuRange.lowerBound])

        let elementRange = try XCTUnwrap(source.range(of: "func insertElement"))
        let collapseRange = try XCTUnwrap(
            source.range(
                of: "func toggleElementCollapse",
                range: elementRange.lowerBound..<source.endIndex
            )
        )
        let elementSource = String(source[elementRange.lowerBound..<collapseRange.lowerBound])

        XCTAssertTrue(newlineSource.contains("syncBindings(from: textView)"))
        XCTAssertFalse(newlineSource.contains("syncStructuralEditBindings(from: textView)"))
        XCTAssertTrue(newlineSource.contains("shouldUseAncestorTypewriterScroll"))
        XCTAssertTrue(newlineSource.contains("scheduleAncestorTypewriterScroll(for: textView)"))
        XCTAssertTrue(newlineSource.contains("captureAncestorScrollSnapshot"))
        XCTAssertTrue(newlineSource.contains("restoreAncestorScrollSnapshot"))
        XCTAssertTrue(elementSource.contains("syncStructuralEditBindings(from: textView)"))
    }

    func testTypewriterReturnScrollsAncestorInsteadOfRestoringOldScrollSnapshot() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/TextKitCoordinator.swift"),
            encoding: .utf8
        )
        let newlineRange = try XCTUnwrap(source.range(of: "private func insertNormalNewline"))
        let menuRange = try XCTUnwrap(
            source.range(
                of: "// MARK: - Menu State",
                range: newlineRange.lowerBound..<source.endIndex
            )
        )
        let newlineSource = String(source[newlineRange.lowerBound..<menuRange.lowerBound])

        XCTAssertTrue(newlineSource.contains("let shouldUseAncestorTypewriterScroll = shouldUseAncestorTypewriterScroll(for: textView)"))
        XCTAssertTrue(newlineSource.contains("let ancestorSnapshot = shouldUseAncestorTypewriterScroll ? nil : captureAncestorScrollSnapshot(for: textView)"))
        XCTAssertTrue(newlineSource.contains("if shouldUseAncestorTypewriterScroll"))
        XCTAssertTrue(newlineSource.contains("scheduleAncestorTypewriterScroll(for: textView)"))
        XCTAssertTrue(newlineSource.contains("scheduleAncestorScrollSnapshotRestores(ancestorSnapshot)"))
    }

    func testAncestorTypewriterScrollUsesTrailingNewlineCaretGeometry() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/TextKitCoordinator.swift"),
            encoding: .utf8
        )
        let rectRange = try XCTUnwrap(source.range(of: "private func cursorRectInAncestorDocument"))
        let nextRange = try XCTUnwrap(
            source.range(
                of: "private func boolAttribute",
                range: rectRange.lowerBound..<source.endIndex
            )
        )
        let rectSource = String(source[rectRange.lowerBound..<nextRange.lowerBound])

        XCTAssertTrue(rectSource.contains("layoutManager.extraLineFragmentRect"))
        XCTAssertTrue(rectSource.contains("characterLocation == textLength"))
        XCTAssertTrue(rectSource.contains("substring(with: NSRange(location: textLength - 1, length: 1)) == \"\\n\""))
        XCTAssertTrue(source.contains("visibleHeight * 0.44"))
    }

    func testNonScrollingResizeDoesNotFightSwiftUILayoutByResizingRepresentableRoot() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/TextKitCoordinator.swift"),
            encoding: .utf8
        )
        let resizeRange = try XCTUnwrap(source.range(of: "private func resizeAppKitFrameIfNeeded"))
        let notifyRange = try XCTUnwrap(
            source.range(
                of: "fileprivate func notifyContentHeightChange",
                range: resizeRange.lowerBound..<source.endIndex
            )
        )
        let resizeSource = String(source[resizeRange.lowerBound..<notifyRange.lowerBound])

        XCTAssertTrue(resizeSource.contains("textView.setFrameSize"))
        XCTAssertFalse(resizeSource.contains("scrollView.setFrameSize"))
        XCTAssertFalse(resizeSource.contains("scrollView.contentView.setFrameSize"))
    }

    func testNonScrollingBodyEditorsMoveVisualPaddingOutsideTextKitInset() throws {
        let textKitSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/TextKitCoordinator.swift"),
            encoding: .utf8
        )
        let richTextSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/RichTextEditor.swift"),
            encoding: .utf8
        )

        let insetRange = try XCTUnwrap(textKitSource.range(of: "private func resolvedTextInsets"))
        let singleLineHeightRange = try XCTUnwrap(
            textKitSource.range(
                of: "private func resolvedSingleLineHeight",
                range: insetRange.lowerBound..<textKitSource.endIndex
            )
        )
        let insetSource = String(textKitSource[insetRange.lowerBound..<singleLineHeightRange.lowerBound])

        XCTAssertTrue(insetSource.contains("EditorTextInsetPolicy.textContainerInset"))
        XCTAssertTrue(richTextSource.contains("externalTextPadding"))
        XCTAssertTrue(richTextSource.contains(".padding(externalTextPadding.edgeInsets)"))
    }

    func testEditorTextInsetPolicyKeepsJitterProneBodyPaddingOutsideTextKitOnly() {
        let nonScrollingBodyInset = EditorTextInsetPolicy.textContainerInset(
            scrollsInternally: false,
            singleLine: false,
            isTitleMode: false,
            compact: false,
            fontSize: 17
        )
        let nonScrollingBodyPadding = EditorTextInsetPolicy.externalTextPadding(
            scrollsInternally: false,
            singleLine: false,
            isTitleMode: false,
            compact: false,
            fontSize: 17
        )

        XCTAssertEqual(nonScrollingBodyInset.width, 0)
        XCTAssertEqual(nonScrollingBodyInset.height, 0)
        XCTAssertEqual(nonScrollingBodyPadding.leading, 16)
        XCTAssertEqual(nonScrollingBodyPadding.top, 16)

        let internallyScrollingBodyInset = EditorTextInsetPolicy.textContainerInset(
            scrollsInternally: true,
            singleLine: false,
            isTitleMode: false,
            compact: false,
            fontSize: 17
        )
        let internallyScrollingBodyPadding = EditorTextInsetPolicy.externalTextPadding(
            scrollsInternally: true,
            singleLine: false,
            isTitleMode: false,
            compact: false,
            fontSize: 17
        )

        XCTAssertEqual(internallyScrollingBodyInset.width, 16)
        XCTAssertEqual(internallyScrollingBodyInset.height, 16)
        XCTAssertEqual(internallyScrollingBodyPadding, .zero)

        let titleInset = EditorTextInsetPolicy.textContainerInset(
            scrollsInternally: false,
            singleLine: false,
            isTitleMode: true,
            compact: false,
            fontSize: 30
        )

        XCTAssertGreaterThan(titleInset.height, 0)
    }

    /// The Notes focus mode is a Notion-style block editor: every line is its
    /// own block field (BlockListView), with multi-block selection handled at
    /// the block level (BlockSelectionCoordinator) — NOT by collapsing the
    /// body into one continuous NSTextView. The canvas note block stays on the
    /// lightweight continuous editor.
    func testNoteFocusBodyUsesBlockEditorWithBlockLevelSelection() throws {
        let noteFocusSource = try String(
            contentsOf: packageRoot.appendingPathComponent("UI/FocusMode/Notes/NoteFocusModeView.swift"),
            encoding: .utf8
        )
        let noteBlockSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Canvas/NoteBlockView.swift"),
            encoding: .utf8
        )
        let blockListSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/BlockEditor/BlockListView.swift"),
            encoding: .utf8
        )

        let focusBodyRange = try XCTUnwrap(noteFocusSource.range(of: "private var centerColumn"))
        let focusRailRange = try XCTUnwrap(
            noteFocusSource.range(
                of: "private var outlineRail",
                range: focusBodyRange.lowerBound..<noteFocusSource.endIndex
            )
        )
        let focusBodySource = String(noteFocusSource[focusBodyRange.lowerBound..<focusRailRange.lowerBound])

        let blockBodyRange = try XCTUnwrap(noteBlockSource.range(of: "private var bodyView"))
        let blockFooterRange = try XCTUnwrap(
            noteBlockSource.range(
                of: "private var noteFooter",
                range: blockBodyRange.lowerBound..<noteBlockSource.endIndex
            )
        )
        let blockBodySource = String(noteBlockSource[blockBodyRange.lowerBound..<blockFooterRange.lowerBound])

        XCTAssertTrue(focusBodySource.contains("BlockListView("))
        XCTAssertFalse(focusBodySource.contains("CosmoDocumentEditor("))
        XCTAssertTrue(blockListSource.contains("BlockSelectionCoordinator"))
        XCTAssertTrue(blockBodySource.contains("CosmoDocumentEditor("))
        XCTAssertFalse(blockBodySource.contains("BlockListView("))
    }

    func testCosmoTextViewDoesNotOverrideSetFrameSizeForTextContainerInsetWorkaround() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/TextKitCoordinator.swift"),
            encoding: .utf8
        )
        let classRange = try XCTUnwrap(source.range(of: "final class CosmoTextView: NSTextView"))
        let extensionRange = try XCTUnwrap(
            source.range(
                of: "extension CosmoTextView",
                range: classRange.lowerBound..<source.endIndex
            )
        )
        let classSource = String(source[classRange.lowerBound..<extensionRange.lowerBound])

        XCTAssertFalse(classSource.contains("override func setFrameSize"))
    }

    func testBlockReturnSuppressesStaleFlushBeforeRunningSplitCommand() throws {
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Editor/TextKitCoordinator.swift"),
            encoding: .utf8
        )
        let returnCommandRange = try XCTUnwrap(
            source.range(of: "if commandSelector == #selector(NSResponder.insertNewline(_:))")
        )
        let splitBranchRange = try XCTUnwrap(
            source.range(
                of: "if parent.splitsOnReturn {",
                range: returnCommandRange.lowerBound..<source.endIndex
            )
        )
        let branchEndRange = try XCTUnwrap(
            source.range(
                of: "if let collapsedHeadingRange",
                range: splitBranchRange.lowerBound..<source.endIndex
            )
        )
        let splitBranch = String(source[splitBranchRange.lowerBound..<branchEndRange.lowerBound])
        let guardRange = try XCTUnwrap(splitBranch.range(of: "beginAwaitingExternalContent()"))
        let commandRange = try XCTUnwrap(splitBranch.range(of: "parent.onBoundaryCommand?(.splitBlock"))

        XCTAssertLessThan(guardRange.lowerBound, commandRange.lowerBound)
    }

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

    func testNoteAutosaveChangePolicySavesRichDocumentChangesWhenPlainTextIsUnchanged() {
        let previous = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Same words")])
        ])
        let next = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [.text("Same words")])
        ])

        XCTAssertTrue(NoteAutosaveChangePolicy.shouldAutosaveDocumentChange(
            isInitialLoad: false,
            previousDocument: previous,
            nextDocument: next,
            previousPlainText: previous.plainText,
            nextPlainText: next.plainText
        ))
    }

    func testNoteInitialDocumentsPreferStoredRichDocumentOverLossyPlainBody() {
        let richBody = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [.text("This is a title test")]),
            RichBlock(kind: .quote, inlines: [.text("This is a quote")])
        ])
        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy("Test note"),
            bodyDocument: richBody
        )
        let atom = Atom.new(
            type: .note,
            title: fields.title,
            body: "TITLEThis is a quote///TITLEThis is a quote///",
            metadata: fields.metadata
        )

        let initialDocuments = NoteFocusInitialDocuments.from(atom: atom)

        XCTAssertEqual(initialDocuments.bodyDocument, richBody)
        XCTAssertEqual(initialDocuments.plainContent, richBody.plainText)
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

    func testNonScrollingTextEditorRejectsProgrammaticClipScrolling() {
        let scrollView = CosmoTextView.scrollableCosmoTextView()
        scrollView.forwardsScrollEvents = true
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: 320, height: 600)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertEqual(scrollView.contentView.bounds.origin, .zero)
    }

    func testScrollingTextEditorAllowsProgrammaticClipScrolling() {
        let scrollView = CosmoTextView.scrollableCosmoTextView()
        scrollView.forwardsScrollEvents = false
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: 320, height: 600)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 80)
    }

    func testNonScrollingTextEditorRejectsAnimatedClipScrolling() {
        let scrollView = CosmoTextView.scrollableCosmoTextView()
        scrollView.forwardsScrollEvents = true
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: 320, height: 600)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: 80))
        }

        XCTAssertEqual(scrollView.contentView.bounds.origin, .zero)
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

    func testNoteObservationPolicySkipsBodyEchoWhileLocalEditsArePending() {
        XCTAssertFalse(NoteWritePolicy.shouldApplyObservedBody(
            isEditingBody: false,
            hasLocalEdits: true,
            observedBodyChanged: true
        ))
    }

    func testNoteObservationPolicyAppliesExternalBodyWhenBlockIsCleanAndInactive() {
        XCTAssertTrue(NoteWritePolicy.shouldApplyObservedBody(
            isEditingBody: false,
            hasLocalEdits: false,
            observedBodyChanged: true,
            isLocalSaveEcho: false
        ))
    }

    func testNoteObservationPolicySkipsLocalSaveEchoAfterEditFlagClears() {
        XCTAssertFalse(NoteWritePolicy.shouldApplyObservedBody(
            isEditingBody: false,
            hasLocalEdits: false,
            observedBodyChanged: true,
            isLocalSaveEcho: true
        ))
    }
}

// MARK: - Data-Safety Regression Tests (June 2026 audit)

/// Regression coverage for the data-safety pass: optimistic locking, conflict
/// merging, decode-corruption guards, NULL handling, restore behavior, and
/// recurrence end-condition counting. Each test pins an invariant whose
/// violation previously caused silent data loss.
@MainActor
final class DataSafetyRegressionTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    override func tearDown() async throws {
        let uuids = cleanupUUIDs.reversed()
        cleanupUUIDs.removeAll()
        for uuid in uuids {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }
        try await super.tearDown()
    }

    private func makeAtom(title: String = "Data-safety fixture", metadata: String? = nil, structured: String? = nil) async throws -> Atom {
        var atom = Atom.new(type: .note, title: "\(title) \(UUID().uuidString)")
        atom.metadata = metadata
        atom.structured = structured
        let created = try await AtomRepository.shared.create(atom)
        cleanupUUIDs.append(created.uuid)
        return created
    }

    /// RC1: ChangeTracker used to bump _local_version a second time after
    /// update()'s SQL already had, so every consecutive save with the returned
    /// atom failed the optimistic lock and fell into the lossy merge path.
    func testConsecutiveUpdatesKeepReturnedVersionInSyncWithDatabase() async throws {
        let created = try await makeAtom()

        var first = created
        first.body = "first edit"
        let afterFirst = try await AtomRepository.shared.update(first)

        let fetchedAfterFirst = try await AtomRepository.shared.fetch(uuid: created.uuid)
        XCTAssertEqual(fetchedAfterFirst?.localVersion, afterFirst.localVersion,
                       "DB version must match the returned atom — a mismatch resurrects the double-bump bug")

        var second = afterFirst
        second.body = "second edit"
        let afterSecond = try await AtomRepository.shared.update(second)

        XCTAssertEqual(afterSecond.localVersion, afterFirst.localVersion + 1,
                       "A clean consecutive save must increment exactly once (no conflict-path detour)")
        let fetchedAfterSecond = try await AtomRepository.shared.fetch(uuid: created.uuid)
        XCTAssertEqual(fetchedAfterSecond?.body, "second edit")
        XCTAssertEqual(fetchedAfterSecond?.localVersion, afterSecond.localVersion)
    }

    /// RC1: the conflict auto-merge replaced the whole metadata blob with the
    /// stale caller's copy, erasing the concurrent writer's keys.
    func testConflictMergePreservesBothWritersMetadataKeys() async throws {
        let created = try await makeAtom(metadata: #"{"a":"original"}"#)

        // Writer B lands first (bumps the version).
        var writerB = created
        writerB.metadata = #"{"a":"original","fromB":"b"}"#
        _ = try await AtomRepository.shared.update(writerB)

        // Writer A holds the STALE version and writes a different key.
        var writerA = created
        writerA.metadata = #"{"a":"updatedByA","fromA":"a"}"#
        _ = try await AtomRepository.shared.update(writerA)

        let final = try await AtomRepository.shared.fetch(uuid: created.uuid)
        let dict = final?.metadataDict
        XCTAssertEqual(dict?["fromB"] as? String, "b", "Concurrent writer's key must survive the conflict merge")
        XCTAssertEqual(dict?["fromA"] as? String, "a", "Stale caller's new key must be applied")
        XCTAssertEqual(dict?["a"] as? String, "updatedByA", "Caller wins for keys both writers touched")
    }

    /// RC2 aggravator: updateFields wrote "" instead of SQL NULL, manufacturing
    /// undecodable JSON columns that later fed the decode-default-resave wipe.
    func testUpdateFieldsNilWritesRealNull() async throws {
        let created = try await makeAtom(structured: #"{"x":1}"#)

        _ = try await AtomRepository.shared.updateFields(uuid: created.uuid, columns: ["structured": nil])

        let fetched = try await AtomRepository.shared.fetch(uuid: created.uuid)
        XCTAssertNil(fetched?.structured, "Nil column values must persist as SQL NULL, never as empty string")
    }

    /// RC6/RC7: updateSync (the quit-time save) used to skip sync tracking, so
    /// the final edit of a session never reached the cloud.
    func testUpdateSyncQueuesPendingSyncRow() async throws {
        let created = try await makeAtom()

        var edited = created
        edited.body = "close-save edit"
        let saved = try AtomRepository.shared.updateSync(edited)

        let (queued, pendingFlag): (Int, Int?) = try await CosmoDatabase.shared.asyncRead { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = ? AND status = 'pending'",
                arguments: [saved.uuid]
            ) ?? 0
            let pending = try Int.fetchOne(
                db,
                sql: "SELECT _local_pending FROM atoms WHERE uuid = ?",
                arguments: [saved.uuid]
            )
            return (count, pending)
        }
        XCTAssertEqual(queued, 1, "updateSync must queue the change for sync in the same transaction")
        XCTAssertEqual(pendingFlag, 1, "updateSync must raise the _local_pending shield")
        XCTAssertEqual(saved.body, "close-save edit")
    }

    /// RC1: links used to be whole-blob last-write-wins on conflict, erasing
    /// relationships the other writer had just created.
    func testMergedLinksUnionsBothWriters() throws {
        let fresh = #"[{"type":"reference","uuid":"AAA","entityType":"note"}]"#
        let caller = #"[{"type":"reference","uuid":"BBB","entityType":"note"}]"#

        let merged = AtomRepository.mergedLinks(fresh: fresh, caller: caller)
        let data = try XCTUnwrap(merged?.data(using: .utf8))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let uuids = Set(array.compactMap { $0["uuid"] as? String })
        XCTAssertEqual(uuids, ["AAA", "BBB"], "Conflict-merged links must union both writers' relationships")
    }

    /// RC2: a corrupt metadata column must never be overwritten by a
    /// default-constructed struct (decode-fail → default → re-save wipe).
    func testCorruptMetadataRefusesDefaultOverwrite() async throws {
        let corrupt = "not valid json {{{"
        var atom = Atom.new(type: .idea, title: "Corrupt metadata fixture")
        atom.metadata = corrupt

        XCTAssertTrue(atom.decodedMetadata(as: IdeaMetadata.self).isCorrupt)

        let afterMutation = atom.withUpdatedIdeaMetadata { _ in }
        XCTAssertEqual(afterMutation.metadata, corrupt,
                       "Mutating through a failed decode must refuse the write, preserving the recoverable payload")

        struct Patch: Codable { let mine: String }
        let afterMerge = atom.mergingMetadataKeys(Patch(mine: "value"))
        XCTAssertEqual(afterMerge.metadata, corrupt,
                       "Key-merge must refuse to overwrite an unparseable column")
    }

    /// RC3: typed-struct round-trips used to drop sibling JSON keys owned by
    /// other writers.
    func testMergingMetadataKeysPreservesSiblingKeys() throws {
        struct Patch: Codable { let mine: String }
        var atom = Atom.new(type: .note, title: "Sibling keys fixture")
        atom.metadata = #"{"keep":"me","nested":{"x":1}}"#

        let merged = atom.mergingMetadataKeys(Patch(mine: "value"))
        let dict = try XCTUnwrap(merged.metadataDict)
        XCTAssertEqual(dict["keep"] as? String, "me")
        XCTAssertNotNil(dict["nested"], "Sibling keys the struct doesn't model must survive")
        XCTAssertEqual(dict["mine"] as? String, "value")
    }

    /// Deleting an atom soft-deletes its canvas placements; restore must bring
    /// BOTH back, or the restored atom stays invisible on every canvas.
    func testRestoreResurrectsCanvasBlocks() async throws {
        let created = try await makeAtom()
        let blockId = UUID().uuidString

        try await CosmoDatabase.shared.asyncWrite { [uuid = created.uuid] db in
            try db.execute(
                sql: """
                INSERT INTO canvas_blocks
                    (id, document_type, document_id, entity_id, entity_uuid, entity_type,
                     position_x, position_y, is_deleted)
                VALUES (?, 'home', 0, ?, ?, 'note', 100, 100, 0)
                """,
                arguments: [blockId, created.id ?? 0, uuid]
            )
        }

        try await AtomRepository.shared.delete(uuid: created.uuid)
        let deletedFlag = try await CosmoDatabase.shared.asyncRead { db in
            try Int.fetchOne(db, sql: "SELECT is_deleted FROM canvas_blocks WHERE id = ?", arguments: [blockId])
        }
        XCTAssertEqual(deletedFlag, 1, "Soft delete must cascade to canvas placements")

        try await AtomRepository.shared.restore(uuid: created.uuid)
        let restoredAtom = try await AtomRepository.shared.fetch(uuid: created.uuid)
        XCTAssertEqual(restoredAtom?.isDeleted, false)
        let restoredFlag = try await CosmoDatabase.shared.asyncRead { db in
            try Int.fetchOne(db, sql: "SELECT is_deleted FROM canvas_blocks WHERE id = ?", arguments: [blockId])
        }
        XCTAssertEqual(restoredFlag, 0, "Restore must also resurrect the atom's canvas placements")
    }

    /// "End after N occurrences" is a property of the series, not of each query
    /// window — the old per-window counter emitted N occurrences per window,
    /// resurrecting ghost occurrences forever.
    func testAfterOccurrencesEndsSeriesAcrossQueryWindows() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let rule = RecurrenceRule.daily(every: 1, endCondition: .afterOccurrences(3))

        let firstWindow = DateInterval(
            start: start,
            end: calendar.date(byAdding: .day, value: 4, to: start)!
        )
        XCTAssertEqual(rule.occurrenceDates(in: firstWindow, startingFrom: start, calendar: calendar).count, 3)

        let laterWindow = DateInterval(
            start: calendar.date(byAdding: .day, value: 5, to: start)!,
            end: calendar.date(byAdding: .day, value: 12, to: start)!
        )
        XCTAssertTrue(rule.occurrenceDates(in: laterWindow, startingFrom: start, calendar: calendar).isEmpty,
                      "A series ended by afterOccurrences must emit nothing in later windows")
    }
}
