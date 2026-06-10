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
