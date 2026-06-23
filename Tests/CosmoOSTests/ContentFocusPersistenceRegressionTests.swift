import XCTest
@testable import CosmoOS

final class ContentFocusPersistenceRegressionTests: XCTestCase {
    func testPolishHighlightsAreOnlyEnabledDuringPolishStep() throws {
        XCTAssertFalse(ContentStep.brainstorm.enablesPolishHighlights)
        XCTAssertFalse(ContentStep.draft.enablesPolishHighlights)
        XCTAssertTrue(ContentStep.polish.enablesPolishHighlights)
    }

    func testContentFocusEditorHighlightsFollowCurrentStep() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("polishHighlights: viewModel.state.currentStep.enablesPolishHighlights ? polishAnalysis : nil"),
            "The content editor must clear polish highlights as soon as the user returns to Draft."
        )
    }

    func testAsyncContentFocusWriteRechecksFreshnessInsideDatabaseTransaction() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("ContentFocusWritePolicy.allowsWrite"),
            "Content Focus async writes must validate snapshot freshness inside the DB transaction so stale snapshots cannot overwrite newer draft saves."
        )
    }

    func testContentFocusEditorPlainTextChangesFeedAutosaveImmediately() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("onPlainTextChange: { plainText in\n                    handleDraftPlainTextChange(plainText)\n                }"),
            "Content Focus must update localDraftContent from the editor's per-keystroke plain-text callback, not only debounced rich-document serialization."
        )
        XCTAssertTrue(
            source.contains("private func handleDraftPlainTextChange(_ plainText: String)")
        )
        XCTAssertTrue(
            source.contains("triggerAutoSave()\n        if isPolishModeActive { debouncedPolishUpdate() }")
        )
    }

    func testContentFocusTerminationSynchronouslyPersistsCurrentEditorSnapshot() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusViewURL = packageRoot.appendingPathComponent("UI/FocusMode/Content/ContentFocusModeView.swift")
        let source = try String(contentsOf: focusViewURL, encoding: .utf8)

        let terminationHandler = try XCTUnwrap(
            slice(
                source,
                from: ".onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate))",
                to: ".onChange(of: viewModel.state.draftContent)"
            )
        )

        XCTAssertTrue(terminationHandler.contains("persistCurrentEditorSnapshot(reason: \"termination\")"))
        XCTAssertFalse(
            terminationHandler.contains("viewModel.state.draftContent = localDraftContent\n            viewModel.state.richDraftDocument = draftDocument"),
            "Termination must not stop after copying view-local state; it must synchronously write the snapshot."
        )

        let snapshotHelper = try XCTUnwrap(
            slice(
                source,
                from: "private func persistCurrentEditorSnapshot(reason: String)",
                to: "private func triggerAutoSave()"
            )
        )
        XCTAssertTrue(snapshotHelper.contains("autoSaveTask?.cancel()"))
        XCTAssertTrue(snapshotHelper.contains("viewModel.state.draftContent = localDraftContent"))
        XCTAssertTrue(snapshotHelper.contains("viewModel.state.lastModified = Date()"))
        XCTAssertTrue(snapshotHelper.contains("viewModel.saveOnClose()"))
    }

    func testContentFocusWritePolicyRejectsSnapshotOlderThanPersistedState() throws {
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let staleDate = Date(timeIntervalSince1970: 1_000)
        let metadata = #"{"lastModifiedUnix":2000}"#

        XCTAssertFalse(ContentFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: staleDate
        ))
        XCTAssertTrue(ContentFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: newerDate
        ))
    }

    func testContentFocusStatePersistsSubsecondModifiedTimestamp() throws {
        var state = ContentFocusModeState(atomUUID: "content-1")
        state.draftContent = "Draft that must survive"
        state.lastModified = Date(timeIntervalSince1970: 1_000.25)

        let fields = state.toAtomFields(existingMetadata: nil)
        let metadata = try XCTUnwrap(fields.metadata)
        let data = try XCTUnwrap(metadata.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let timestamp = try XCTUnwrap(dict["lastModifiedUnix"] as? Double)
        XCTAssertEqual(timestamp, 1_000.25, accuracy: 0.000001)
    }

    func testContentFocusStateUsesNewerPlainTextWhenRichDraftDocumentIsStale() throws {
        var state = ContentFocusModeState(atomUUID: "content-1")
        state.draftContent = "Slide 1\n\nSlide 2 edited seconds before quit"
        state.richDraftDocument = RichDocument.migrateLegacy("Slide 1")

        let fields = state.toAtomFields(existingMetadata: nil)

        XCTAssertEqual(fields.body, "Slide 1\n\nSlide 2 edited seconds before quit")
        let metadata = try XCTUnwrap(fields.metadata)
        let restored = RichDocumentMetadataStorage.readDocument(
            from: metadata,
            key: RichDocumentMetadataKeys.contentDraftDocument
        )
        XCTAssertEqual(restored?.plainText, "Slide 1\n\nSlide 2 edited seconds before quit")
    }

    func testContentFocusStateAllowsEmptyPlainTextToReplaceStaleRichDraftDocument() throws {
        var state = ContentFocusModeState(atomUUID: "content-1")
        state.draftContent = ""
        state.richDraftDocument = RichDocument.migrateLegacy("Deleted draft that must not come back")

        let fields = state.toAtomFields(existingMetadata: nil)

        XCTAssertNil(fields.body)
        let metadata = try XCTUnwrap(fields.metadata)
        let restored = RichDocumentMetadataStorage.readDocument(
            from: metadata,
            key: RichDocumentMetadataKeys.contentDraftDocument
        )
        XCTAssertEqual(restored?.plainText, "")
    }

    func testPresentationStyleChangesPreserveLivePlainTextWhenRichDocumentLags() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorURL = packageRoot.appendingPathComponent("Editor/CosmoDocumentEditor.swift")
        let source = try String(contentsOf: editorURL, encoding: .utf8)

        let presentationHandlers = try XCTUnwrap(
            slice(
                source,
                from: ".onChange(of: fontSize)",
                to: ".onChange(of: plainTextMirror)"
            )
        )

        XCTAssertEqual(presentationHandlers.components(separatedBy: "syncEditorForPresentationChange()").count - 1, 3)
        XCTAssertFalse(
            presentationHandlers.contains("syncEditorFromDocument()"),
            "Aa/style changes must not repaint the focused editor from a stale RichDocument while the plain-text lane has newer edits."
        )

        let presentationHelper = try XCTUnwrap(
            slice(
                source,
                from: "private func syncEditorForPresentationChange()",
                to: "private func handlePlainTextMirrorChange"
            )
        )
        XCTAssertTrue(presentationHelper.contains("preferLivePlainText: true"))

        let presentationResolver = try XCTUnwrap(
            slice(
                source,
                from: "private func resolvedDocumentForEditor(preferLivePlainText: Bool = false)",
                to: "private func liveDocumentForPresentationChange()"
            )
        )
        XCTAssertTrue(presentationResolver.contains("liveDocumentForPresentationChange()"))
        XCTAssertTrue(presentationResolver.contains("livePlainText == plainTextMirror"))
        XCTAssertTrue(
            source.contains("RichDocumentSerializer.document(from: attributedText)"),
            "Aa/style changes should preserve the live rich editor buffer when it is already synchronized with the latest plain text."
        )
    }

    private func slice(_ source: String, from startMarker: String, to endMarker: String) -> String? {
        guard let start = source.range(of: startMarker),
              let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            return nil
        }
        return String(source[start.upperBound..<end.lowerBound])
    }
}
