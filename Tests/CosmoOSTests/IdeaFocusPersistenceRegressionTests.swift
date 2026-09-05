import AppKit
import XCTest
@testable import CosmoOS

final class IdeaFocusPersistenceRegressionTests: XCTestCase {
    /// AppKit resets `minSize` whenever a smaller frame is set, after which the
    /// vertically-resizable context editor shrinks to its content height. The
    /// SwiftUI platform-view host is non-flipped, so the shorter view pins to
    /// the BOTTOM of the reserved frame: the caret, typed text, and click
    /// target all sit ~170pt below the "What's the angle?" placeholder, and
    /// the top of the editor is dead space. The view must always fill the
    /// height its host reserved for it.
    @MainActor
    func testContextTextViewNeverShrinksBelowHostHeightSoTypingStartsAtTop() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 632, height: 200))
        let textView = IdeaContextTextView(frame: host.bounds)
        host.addSubview(textView)

        // Simulate AppKit's self-sizing pass collapsing the empty editor to
        // its content height (this is what bottom-anchored it in production).
        textView.setFrameSize(NSSize(width: 632, height: 32))
        XCTAssertEqual(
            textView.frame.height, 200,
            "The context editor must keep filling the SwiftUI-reserved height; a shorter view bottom-anchors in the non-flipped host and typing lands at the bottom."
        )

        // Content taller than the reserved frame must still win, so the
        // editor expands as the user writes more.
        textView.setFrameSize(NSSize(width: 632, height: 329))
        XCTAssertEqual(
            textView.frame.height, 329,
            "Content taller than the reserved frame must not be clamped down."
        )
    }

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
        // Sept 2026: promotion lives in IdeaPromotionService (one path for the
        // bench, the calendar and the Pipeline board). The bench saves first,
        // so the persisted idea client IS the session's linked client.
        let viewModel = try ideaFocusViewModelSource()
        XCTAssertTrue(
            viewModel.contains("await save()") && viewModel.contains("IdeaPromotionService.promote("),
            "The bench must persist its session state, then promote through the shared service."
        )

        let source = try ideaPromotionServiceSource()
        XCTAssertTrue(
            source.contains("let inheritedClientUUID = meta?.clientUUID"),
            "Promotion must read the client from the idea metadata (the bench's linked client is saved there first)."
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

    // MARK: - The 2026-07-29 stale-model clobber

    // An idea was open with three minutes of unsaved-to-the-row typing. On quit,
    // a DISCARDED duplicate view model — built from the pre-edit atom, kept alive
    // by the loader tasks its initializer fired, and subscribed to termination in
    // that same initializer — flushed its own copy. Because every write path
    // stamped `lastModified = Date()` immediately before comparing, the stale
    // writer looked like the freshest one, passed `allowsWrite`, and reverted the
    // row. The five tests below pin each link of that chain.

    /// A model built from a row, which then takes NO edits of its own, must not
    /// out-rank that row after someone else saves it. Before the fix the model's
    /// clock was stamped at write time, so this comparison always passed and the
    /// pre-edit copy won.
    func testUneditedModelCannotOutrankARowSavedAfterItWasBuilt() {
        let builtFrom = #"{"lastModifiedUnix":1000}"#
        let savedAgainLater = #"{"lastModifiedUnix":1002}"#

        let seed = IdeaFocusWritePolicy.seededModifiedTime(metadata: builtFrom, updatedAt: nil)

        XCTAssertEqual(
            seed, Date(timeIntervalSince1970: 1_000),
            "A new model's content clock must start at the row's persisted stamp, never at `now`."
        )
        XCTAssertFalse(
            IdeaFocusWritePolicy.allowsWrite(
                existingMetadata: savedAgainLater,
                snapshotLastModified: seed
            ),
            "A model holding the pre-edit copy must be refused once the row has been saved again — this is the 2026-07-29 clobber."
        )
    }

    func testSeededModifiedTimeFallsBackToRowTimestampThenDistantPast() {
        let updatedAt = "2026-07-29T04:22:12Z"

        XCTAssertEqual(
            IdeaFocusWritePolicy.seededModifiedTime(metadata: nil, updatedAt: updatedAt),
            ISO8601.date(from: updatedAt),
            "With no metadata stamp the row's own updated_at is the honest starting point."
        )
        XCTAssertEqual(
            IdeaFocusWritePolicy.seededModifiedTime(metadata: nil, updatedAt: nil),
            .distantPast,
            "With nothing to seed from, a model must rank LAST rather than newest."
        )
    }

    /// `lastModified` means "content changed", not "write attempted". Exactly one
    /// place may move it.
    func testOnlyMarkEditedStampsTheContentModificationClock() throws {
        let source = try ideaFocusViewModelSource()

        XCTAssertEqual(
            source.components(separatedBy: "lastModified = Date()").count - 1, 1,
            "Only `markEdited()` may stamp `lastModified`; stamping it on a write path is what defeated the freshness guard."
        )
        XCTAssertTrue(
            source.contains("private func markEdited() {\n        lastModified = Date()"),
            "The single stamp must live in `markEdited()`."
        )
        XCTAssertFalse(
            source.contains("nextSaveSequence(markModified:"),
            "`nextSaveSequence` must not carry a modification-stamping side effect."
        )
    }

    /// GUARD-TWIN assertion: both exit flushes gate on a recorded edit.
    func testCloseAndTerminationFlushesRequireARecordedEdit() throws {
        let source = try ideaFocusViewModelSource()

        for function in ["func saveOnClose() {", "func flushForTermination() {"] {
            guard let start = source.range(of: function) else {
                XCTFail("Could not locate \(function)")
                return
            }
            let body = String(source[start.lowerBound...].prefix(1_200))
            XCTAssertTrue(
                body.contains("guard hasRecordedEdit else { return }"),
                "\(function) must not write for a model that never took an edit — that write is the pre-edit copy."
            )
        }
    }

    /// The termination flush belongs to the mounted view. `State(initialValue:)`
    /// is not lazy, so subscribing in the model's initializer enrolls every
    /// discarded duplicate as a writer.
    func testTerminationFlushIsSubscribedOnTheViewNotInTheViewModelInitializer() throws {
        XCTAssertFalse(
            try ideaFocusViewModelSource().contains("publisher(for: .cosmoAppWillTerminate)"),
            "The view model must not subscribe to termination: its initializer runs for every discarded duplicate model."
        )
        XCTAssertTrue(
            try ideaFocusViewSource().contains(
                ".onReceive(NotificationCenter.default.publisher(for: .cosmoAppWillTerminate))"
            ),
            "The mounted view owns the termination flush (the Content/Notes idiom)."
        )
    }

    /// Loader I/O in `init` is what kept discarded models alive to quit time.
    func testLoaderLadderRunsFromStartNotTheInitializer() throws {
        let source = try ideaFocusViewModelSource()
        guard let initRange = source.range(of: "    init(atom: Atom) {"),
              let startRange = source.range(of: "    func start() {") else {
            XCTFail("Could not locate init and start().")
            return
        }
        XCTAssertTrue(
            initRange.lowerBound < startRange.lowerBound,
            "Expected init to precede start() in the file."
        )

        let initBody = String(source[initRange.lowerBound..<startRange.lowerBound])
        for loader in ["loadRecommendedSwipes()", "loadLinkedSwipes()", "loadClientProfiles()", "loadScheduledTasks()"] {
            XCTAssertFalse(
                initBody.contains(loader),
                "\(loader) must not run from init — every discarded duplicate model would run it and stay alive on the task."
            )
        }
        XCTAssertTrue(
            try ideaFocusViewSource().contains("viewModel.start()"),
            "The mounted view must start the loader ladder."
        )
    }

    /// This path writes raw SQL instead of going through AtomRepository, so it
    /// has to snapshot the pre-image itself or the idea accumulates no history —
    /// the gap that forced recovery from the sync queue on 2026-07-29.
    func testRawWriteSnapshotsPreImageIntoRevisionHistory() throws {
        let source = try ideaFocusViewModelSource()

        XCTAssertTrue(
            source.contains("AtomRevisionWriter.snapshotBeforeRawWrite("),
            "The raw-SQL idea write must snapshot the pre-image in-transaction so a clobber stays recoverable."
        )
        guard let writeRange = source.range(of: "static func write(snapshot: IdeaFocusSaveSnapshot"),
              let snapshotRange = source.range(of: "AtomRevisionWriter.snapshotBeforeRawWrite("),
              let updateRange = source.range(of: "UPDATE atoms") else {
            XCTFail("Could not locate the raw write.")
            return
        }
        XCTAssertTrue(
            writeRange.lowerBound < snapshotRange.lowerBound && snapshotRange.lowerBound < updateRange.lowerBound,
            "The snapshot must be taken inside the write transaction and BEFORE the UPDATE overwrites the row."
        )
    }

    /// June 2026 Idea v2: the advanced outline (physics grid, element browser,
    /// drag items) was removed — only the simple outline remains.
    func testIdeaFocusViewDroppedAdvancedOutlineMode() throws {
        let source = try ideaFocusViewSource()
        XCTAssertFalse(source.contains("outlineAdvancedMode"))
        XCTAssertFalse(source.contains("CodexDragItem"))
        XCTAssertFalse(source.contains("AdvancedElementBrowser"))
    }

    /// The width class is column-count aware now — see
    /// `IdeaWorkspaceLayoutPolicyTests` for the budget itself. This case only
    /// guards the inspector toggle riding on top of it.
    @MainActor
    func testIdeaWorkspaceBreakpointAndInspectorToggle() {
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1400, columns: 1), .regular)
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1000, columns: 1), .regular)
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 860, columns: 1), .compact)

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

    private func ideaPromotionServiceSource() throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent("Data/Services/IdeaPromotionService.swift"),
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
