import XCTest
@testable import CosmoOS

final class IdeaFocusPersistenceRegressionTests: XCTestCase {
    func testOutlineSlideNoteEditsScheduleAutoSave() throws {
        let source = try ideaFocusViewSource()

        XCTAssertTrue(
            source.contains("viewModel.updateOutlineSlideNote(slideId: slideId, note: newValue)"),
            "Outline slide note edits must go through the view model so every keystroke refreshes the autosave snapshot."
        )
    }

    func testIdeaFocusAsyncWritesRecheckFreshnessInsideDatabaseTransaction() throws {
        let source = try ideaFocusViewModelSource()

        XCTAssertTrue(
            source.contains("IdeaFocusWritePolicy.allowsWrite"),
            "Idea Focus writes must validate snapshot freshness inside the DB transaction so stale autosaves cannot overwrite newer close saves."
        )
    }

    func testIdeaPromotionPersistsIdeaClientIntoContentFocusStateAndMetadata() throws {
        let source = try ideaFocusViewModelSource()

        XCTAssertTrue(
            source.contains("let inheritedClientUUID = linkedClient?.uuid ?? idea.ideaMetadata?.clientUUID"),
            "Promotion must fall back to the idea metadata client UUID when the linked client atom is not loaded."
        )
        XCTAssertTrue(
            source.contains("focusState.clientProfileUUID = inheritedClientUUID"),
            "Promotion must set the focus state client before serializing metadata, otherwise the focus state overwrites the content metadata client with nil."
        )
        XCTAssertTrue(
            source.contains("contentMeta.clientProfileUUID = inheritedClientUUID"),
            "Promotion must persist the inherited client on the content atom metadata."
        )
    }

    func testContextEditorDoesNotForceBlurDuringSwiftUIUpdates() throws {
        let source = try ideaManuscriptEditorsSource()
        guard let editorRange = source.range(of: "struct IdeaContextTextEditor"),
              let hookRange = source.range(of: "struct HookLineEditor") else {
            XCTFail("Could not locate IdeaContextTextEditor source.")
            return
        }

        let editorSource = String(source[editorRange.lowerBound..<hookRange.lowerBound])
        XCTAssertFalse(
            editorSource.contains("makeFirstResponder(nil)"),
            "The context editor must not force-resign first responder during SwiftUI updates because that blurs typing after each keystroke."
        )
        XCTAssertFalse(
            editorSource.contains("requestFocusWhenReady()"),
            "The context editor should let AppKit place focus from mouse clicks so the insertion point does not jump to the previous selection."
        )
    }

    func testContextTextEditorPinsTextContainerOriginToTopInset() throws {
        let source = try ideaManuscriptEditorsSource()
        guard let textViewRange = source.range(of: "final class IdeaContextTextView"),
              let hookRange = source.range(of: "struct HookLineEditor") else {
            XCTFail("Could not locate IdeaContextTextView source.")
            return
        }

        let textViewSource = String(source[textViewRange.lowerBound..<hookRange.lowerBound])
        XCTAssertTrue(
            textViewSource.contains("override var textContainerOrigin: NSPoint"),
            "The context editor must pin NSTextView's text container to the top when the editor is taller than its content."
        )
        XCTAssertTrue(
            textViewSource.contains("NSPoint(x: textContainerInset.width, y: textContainerInset.height)"),
            "The pinned text-container origin should start at the configured top/leading inset."
        )
    }

    func testContextEditorFrameTopAlignsRepresentableInsideFullWidthFocusMode() throws {
        let source = try ideaFocusViewSource()

        XCTAssertTrue(
            source.contains(".frame(maxWidth: .infinity, minHeight: IdeaContextTextView.minimumHeight, alignment: .topLeading)"),
            "The context NSTextView representable must be top-aligned in its SwiftUI frame so full-width focus mode does not place short context text at the bottom."
        )
    }

    func testFocusModeTextViewsShareClipboardKeyEquivalentHandling() throws {
        let source = try ideaManuscriptEditorsSource()
        for className in ["IdeaContextTextView", "HookLineTextView", "OutlineSlideNoteTextView"] {
            let classSource = try sourceBlock(named: className, in: source)
            XCTAssertTrue(
                classSource.contains("FocusModeTextClipboardTarget.performKeyEquivalent(event, fallback: self)"),
                "\(className) must handle Cmd-C/X/V/A through the shared focus-mode clipboard key equivalent path."
            )
        }
    }

    func testIdeaFocusWritePolicyRejectsSnapshotOlderThanPersistedState() throws {
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let staleDate = Date(timeIntervalSince1970: 1_000)
        let metadata = #"{"lastModifiedUnix":2000}"#

        XCTAssertFalse(IdeaFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: staleDate
        ))
        XCTAssertTrue(IdeaFocusWritePolicy.allowsWrite(
            existingMetadata: metadata,
            snapshotLastModified: newerDate
        ))
    }

    /// June 2026 Idea v2: the advanced outline (physics grid, element browser,
    /// drag items) was removed — only the simple outline remains.
    func testIdeaFocusViewDroppedAdvancedOutlineMode() throws {
        let source = try ideaFocusViewSource()
        XCTAssertFalse(source.contains("outlineAdvancedMode"))
        XCTAssertFalse(source.contains("CodexDragItem"))
        XCTAssertFalse(source.contains("AdvancedElementBrowser"))
    }

    @MainActor
    func testIdeaWorkspaceBreakpointAndInspectorToggle() {
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1400), .regular)
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1000), .regular)
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 999), .compact)

        let model = IdeaWorkspaceModel()
        XCTAssertTrue(model.isInspectorShowing, "Inspector is a visible side column at full width")
        model.toggleInspector()
        XCTAssertFalse(model.isInspectorVisible)

        model.breakpoint = .compact
        XCTAssertFalse(model.isInspectorShowing, "Compact widths hide the inspector by default")
        model.toggleInspector()
        XCTAssertTrue(model.isInspectorOverlayPresented)
    }

    private func ideaFocusViewSource() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeView.swift"),
            encoding: .utf8
        )
    }

    private func ideaFocusViewModelSource() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeViewModel.swift"),
            encoding: .utf8
        )
    }

    /// The AppKit-backed editors moved to their own file in the June 2026
    /// Idea v2 revamp; editor-internals assertions read it directly.
    private func ideaManuscriptEditorsSource() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("UI/FocusMode/Ideas/IdeaManuscriptEditors.swift"),
            encoding: .utf8
        )
    }

    private func sourceBlock(named className: String, in source: String) throws -> String {
        let marker = "class \(className)"
        guard let classRange = source.range(of: marker) else {
            XCTFail("Could not locate \(className) source.")
            return ""
        }

        let remainder = source[classRange.lowerBound...]
        guard let nextTypeRange = remainder.range(
            of: #"\n(?:private\s+)?(?:final\s+)?(?:class|struct|enum)\s+"#,
            options: .regularExpression,
            range: remainder.index(after: classRange.lowerBound)..<remainder.endIndex
        ) else {
            return String(remainder)
        }

        return String(source[classRange.lowerBound..<nextTypeRange.lowerBound])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
