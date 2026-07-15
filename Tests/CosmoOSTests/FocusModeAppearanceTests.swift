import XCTest

final class FocusModeAppearanceTests: XCTestCase {
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testDocumentFocusModesUseImmersiveTokensForBlackMonoSurfaces() throws {
        let noteFocusSource = try source("UI/FocusMode/Notes/NoteFocusModeView.swift")
        let contentFocusSource = try source("UI/FocusMode/Content/ContentFocusModeView.swift")

        XCTAssertTrue(noteFocusSource.contains("focusBackground"))
        XCTAssertTrue(noteFocusSource.contains("focusText"))
        XCTAssertTrue(noteFocusSource.contains("darkMode: DS.usesImmersiveFocusAppearance"))
        XCTAssertTrue(noteFocusSource.contains("overrideTextColor: NSColor(focusText)"))

        XCTAssertTrue(contentFocusSource.contains("focusBackground"))
        XCTAssertTrue(contentFocusSource.contains("focusText"))
        XCTAssertTrue(contentFocusSource.contains("darkMode: DS.usesImmersiveFocusAppearance"))
        XCTAssertTrue(contentFocusSource.contains("overrideTextColor: NSColor(focusText)"))
    }

    func testAllFocusModeRootsReferenceImmersiveFocusBackground() throws {
        let focusModeFiles = [
            "UI/FocusMode/Notes/NoteFocusModeView.swift",
            "UI/FocusMode/Content/ContentFocusModeView.swift",
            "UI/FocusMode/Ideas/IdeaFocusModeView.swift",
            "UI/FocusMode/Connection/ConnectionFocusModeView.swift",
            "UI/FocusMode/Research/ResearchFocusModeView.swift",
            "UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift",
            "UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift",
            "UI/FocusMode/Template/TemplateFocusModeView.swift",
        ]

        for file in focusModeFiles {
            let source = try source(file)
            // June 2026 Greenhouse-clean workspaces (Connection, Idea) route
            // through DS.bg deliberately; everything else stays immersive.
            // July 2026: Swipe Study shares the Swipe File page surface
            // (SwipePageBackground = DS.swipeLibraryBackground) so the hero
            // zoom from the library lands on the same paper.
            XCTAssertTrue(
                source.contains("DS.focusImmersiveBackground")
                    || source.contains("focusBackground")
                    || source.contains("DS.bg.ignoresSafeArea")
                    || source.contains("SwipePageBackground()"),
                "\(file) should route its top-level surface through semantic focus tokens"
            )
        }
    }

    func testCanvasDocumentCardsUseCanvasDocumentSurfaceInsteadOfPureWhite() throws {
        let wrapperSource = try source("Canvas/CosmoBlockWrapper.swift")

        XCTAssertTrue(wrapperSource.contains("DS.canvasDocumentSurface"))
    }

    /// Canvas note blocks are lightweight previews/editors — they use the
    /// continuous CosmoDocumentEditor. The full block-line system
    /// (BlockListView) is the Notes focus mode's surface.
    func testCanvasNoteBodyUsesContinuousEditorWhileFocusModeOwnsBlocks() throws {
        let noteBlockSource = try source("Canvas/NoteBlockView.swift")
        let bodyViewRange = try XCTUnwrap(noteBlockSource.range(of: "private var bodyView: some View"))
        let footerRange = try XCTUnwrap(noteBlockSource.range(of: "private var noteFooter: some View"))
        let bodyViewSource = String(noteBlockSource[bodyViewRange.lowerBound..<footerRange.lowerBound])

        XCTAssertTrue(bodyViewSource.contains("CosmoDocumentEditor("))
        XCTAssertFalse(bodyViewSource.contains("BlockListView("))
    }

    func testHeadingDisclosureColorDefaultsToAdaptiveRendererColor() throws {
        let editorSource = try source("Editor/CosmoDocumentEditor.swift")

        XCTAssertTrue(editorSource.contains("var headingDisclosureColor: NSColor? = nil"))
        XCTAssertFalse(editorSource.contains("var headingDisclosureColor: NSColor? = .black"))
    }

    func testNoteFocusBodyDoesNotFeedTypingHeightBackIntoScrollLayout() throws {
        let noteFocusSource = try source("UI/FocusMode/Notes/NoteFocusModeView.swift")
        let centerColumnRange = try XCTUnwrap(noteFocusSource.range(of: "private var centerColumn: some View"))
        let dividerRange = try XCTUnwrap(noteFocusSource.range(of: "private var giltDivider: some View"))
        let centerColumnSource = String(noteFocusSource[centerColumnRange.lowerBound..<dividerRange.lowerBound])

        XCTAssertFalse(centerColumnSource.contains("bodyEditorHeight"))
        XCTAssertFalse(centerColumnSource.contains("onContentHeightChange: { newHeight in"))
        XCTAssertTrue(centerColumnSource.contains("minHeight: max(400, scrollViewportHeight - 200)"))
    }

    func testContentFocusDraftDoesNotFeedTypingHeightBackIntoScrollLayout() throws {
        let contentFocusSource = try source("UI/FocusMode/Content/ContentFocusModeView.swift")
        let draftEditorRange = try XCTUnwrap(contentFocusSource.range(of: "// Main draft editor"))
        let ctaRange = try XCTUnwrap(
            contentFocusSource.range(
                of: "scriptoriumCTA",
                range: draftEditorRange.lowerBound..<contentFocusSource.endIndex
            )
        )
        let draftEditorSource = String(contentFocusSource[draftEditorRange.lowerBound..<ctaRange.lowerBound])

        XCTAssertFalse(contentFocusSource.contains("@State private var textContentHeight"))
        XCTAssertFalse(contentFocusSource.contains("private func estimatedDraftEditorHeight"))
        XCTAssertFalse(draftEditorSource.contains("onContentHeightChange: { measuredHeight in"))
        XCTAssertFalse(draftEditorSource.contains("textContentHeight"))
        XCTAssertFalse(draftEditorSource.contains("estimatedDraftEditorHeight"))
        XCTAssertTrue(draftEditorSource.contains("minHeight: max(400, height - manuscriptEditorHeightOffset)"))
    }

    func testMarginaliaLabelsUseSubtleFocusRulesInBlackMono() throws {
        let primitivesSource = try source("UI/FocusMode/Shared/AtelierPrimitives.swift")

        XCTAssertTrue(primitivesSource.contains("private var marginaliaRuleColor"))
        XCTAssertTrue(primitivesSource.contains("DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBorder.opacity(0.9) : DS.sepiaSubtle"))
        XCTAssertTrue(primitivesSource.contains(".fill(marginaliaRuleColor)"))
    }

    func testPremiumFocusModesUseSharedGlassChromePrimitives() throws {
        let premiumChromeSource = try source("UI/FocusMode/Shared/FocusModePremiumChrome.swift")
        let railSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyInsightRail.swift")

        XCTAssertTrue(premiumChromeSource.contains("struct FocusModeGlassRail"))
        XCTAssertTrue(premiumChromeSource.contains("struct FocusModeInspectorSection"))
        XCTAssertTrue(premiumChromeSource.contains("struct FocusModeMediaWell"))
        // Idea v2 moved to IdeaInspectorView; Swipe Study v2 (July 2026) moved
        // to the Swipe File header voice — one grammar per screen.
        XCTAssertTrue(railSource.contains("struct SwipeStudyRailHeader"))
        XCTAssertFalse(railSource.contains("FocusModeInspectorSection"))
    }

    func testAtomWindowChromeIsInjectedByAtomWindowRootOnlyWhenHostingAtoms() throws {
        let atomRootSource = try source("UI/AtomWindow/AtomWindowRootView.swift")

        XCTAssertTrue(atomRootSource.contains(#".environment(\.atomWindowChromeContext, chromePayload(for: atom))"#))
        XCTAssertTrue(atomRootSource.contains("private func chromePayload(for atom: Atom) -> AtomWindowChromePayload"))
        XCTAssertFalse(atomRootSource.contains("AtomWindowHeaderBar(viewModel: viewModel)"))
    }

    func testAtomWindowChromeIsOptionalInFocusModeToolbars() throws {
        let focusToolbarFiles = [
            "UI/FocusMode/Notes/NoteFocusModeView.swift",
            "UI/FocusMode/Content/ContentFocusModeView.swift",
            "UI/FocusMode/Ideas/IdeaWorkspaceToolbar.swift",
            "UI/FocusMode/Connection/ConnectionWorkspaceToolbar.swift",
            "UI/FocusMode/Research/ResearchFocusModeView.swift",
            "UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift",
            "UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift",
        ]

        for file in focusToolbarFiles {
            let source = try source(file)

            XCTAssertTrue(source.contains(#"@Environment(\.atomWindowChromeContext)"#), "\(file) should read Atom chrome as optional environment")
            XCTAssertTrue(source.contains("if let atomChrome"), "\(file) should gate Atom chrome behind optional lookup")
            XCTAssertTrue(source.contains("AtomWindowChromeLeadingControls"), "\(file) should merge Atom leading controls into its toolbar")
            XCTAssertTrue(source.contains("AtomWindowChromeTrailingControls"), "\(file) should merge Atom trailing controls into its toolbar")
        }
    }

    func testNoteAtomWindowToolbarUsesFiniteAtomChromeLayout() throws {
        let noteSource = try source("UI/FocusMode/Notes/NoteFocusModeView.swift")
        let metricsSource = try source("UI/AtomWindow/AtomWindowMetrics.swift")

        XCTAssertTrue(noteSource.contains("private func atomWindowTopBar(_ atomChrome: AtomWindowChromePayload)"))
        XCTAssertTrue(noteSource.contains(".frame(height: AtomWindowMetrics.focusToolbarHeight)"))
        XCTAssertTrue(noteSource.contains("private var nativeFocusTopBar"))
        XCTAssertTrue(metricsSource.contains("static let focusToolbarHeight: CGFloat = 44"))
    }

    func testIdeaFocusModeRemovesUnusedCosmoMarginaliaComposer() throws {
        let ideaFocusSource = try source("UI/FocusMode/Ideas/IdeaFocusModeView.swift")

        XCTAssertFalse(ideaFocusSource.contains("marginaliaCosmoSection"))
        XCTAssertFalse(ideaFocusSource.contains("FocusCosmoPanel(session: cosmoSession"))
    }

    /// July 2026 workbench conversion: Swipe Study runs on the shared
    /// WorkbenchShell — the analysis rail is the LEADING panel, there is no
    /// trailing panel, and the three bespoke width tiers are gone (the shell
    /// owns displace/overlay behavior).
    func testSwipeStudyRunsOnTheWorkbenchShellWithLeadingAnalysisRail() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        XCTAssertTrue(swipeFocusSource.contains("WorkbenchShell("))
        XCTAssertTrue(swipeFocusSource.contains("SwipeStudyAnalysisPanel("))
        XCTAssertTrue(swipeFocusSource.contains("isTrailingShowing: false"))
        XCTAssertTrue(swipeFocusSource.contains(".studyPanelSurface(edge: .leading"))
        XCTAssertFalse(swipeFocusSource.contains("private func wideLayout"))
        XCTAssertFalse(swipeFocusSource.contains("private func mediumLayout"))
        XCTAssertFalse(swipeFocusSource.contains("private func compactLayout"))
    }

    /// The center column reads as the object of study: serif hero, then the
    /// media stage, then the transcript — one order at every width.
    func testSwipeStudyCenterReadsHeroThenStageThenTranscript() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")
        let centerRange = try XCTUnwrap(swipeFocusSource.range(of: "private func centerColumn"))
        let centerSource = String(swipeFocusSource[centerRange.lowerBound...])

        let heroRange = try XCTUnwrap(centerSource.range(of: "SwipeStudyHeroBlock(model: model, atom: atom)"))
        let stageRange = try XCTUnwrap(centerSource.range(of: "SwipeStudyStagePane(model: model, atom: atom)"))
        let transcriptRange = try XCTUnwrap(centerSource.range(of: "SwipeStudyTranscriptBlock(model: model, atom: atom)"))

        XCTAssertLessThan(heroRange.lowerBound, stageRange.lowerBound)
        XCTAssertLessThan(stageRange.lowerBound, transcriptRange.lowerBound)
    }

    func testSwipeStudyHasNoPhysicsOrCodexLayer() throws {
        // The July 2026 rebuild removed the physics/codex pass from Study —
        // the surface is transcript + one insight pass only.
        for file in ["SwipeStudyFocusModeView.swift", "SwipeStudyInsightRail.swift",
                     "SwipeStudyManuscript.swift", "SwipeStudyModel.swift"] {
            let text = try source("UI/FocusMode/SwipeStudy/\(file)")
            XCTAssertFalse(text.contains("ContentPhysicsSection"), "\(file) resurrects the physics section")
            XCTAssertFalse(text.contains("bestPhysicsProfile"), "\(file) resurrects the physics profile")
            XCTAssertFalse(text.contains("generateCodexProfile"), "\(file) resurrects codex generation")
        }
    }

    func testSwipeInsightRailOrdersInsightStructurePatternsDetails() throws {
        let railSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyInsightRail.swift")

        let insightRange = try XCTUnwrap(railSource.range(of: "insightSection(analysis)"))
        let structureRange = try XCTUnwrap(railSource.range(of: "structureSection(analysis)"))
        let patternsRange = try XCTUnwrap(railSource.range(of: "patternsSection\n"))
        let detailsRange = try XCTUnwrap(railSource.range(of: "detailsSection\n"))

        XCTAssertLessThan(insightRange.lowerBound, structureRange.lowerBound)
        XCTAssertLessThan(structureRange.lowerBound, patternsRange.lowerBound)
        XCTAssertLessThan(patternsRange.lowerBound, detailsRange.lowerBound)
    }

    func testSwipeManuscriptHasOneSerifMoment() throws {
        // The hero title is the single serif moment; the smallcaps ornament
        // row ("· · · SWIPE FILE · … · · ·") must never come back.
        let manuscriptSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyManuscript.swift")
        XCTAssertTrue(manuscriptSource.contains("DS.displaySerif"))
        XCTAssertFalse(manuscriptSource.contains("· · ·"))

        let shellSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")
        XCTAssertFalse(shellSource.contains("· · ·"))
        XCTAssertFalse(shellSource.contains(".italic()"))
    }

    func testSwipeStudyUsesThinCustomScrollChrome() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        XCTAssertTrue(swipeFocusSource.contains("@State private var scrollMetrics = CortexScrollMetrics()"))
        XCTAssertTrue(swipeFocusSource.contains("CortexScrollViewIntrospector"))
        XCTAssertTrue(swipeFocusSource.contains("CortexThinScrollbar(metrics: scrollMetrics)"))
    }

    func testIdeaFocusModeUsesContentFocusSizedCustomScrollbar() throws {
        let ideaFocusSource = try source("UI/FocusMode/Ideas/IdeaFocusModeView.swift")

        XCTAssertTrue(ideaFocusSource.contains("@State private var atelierScrollMetrics = CortexScrollMetrics()"))
        XCTAssertTrue(ideaFocusSource.contains("CortexScrollViewIntrospector"))
        XCTAssertTrue(ideaFocusSource.contains(".cortexThinScrollbar(metrics: atelierScrollMetrics)"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
