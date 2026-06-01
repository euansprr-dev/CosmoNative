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
            XCTAssertTrue(
                source.contains("DS.focusImmersiveBackground") || source.contains("focusBackground"),
                "\(file) should route its top-level surface through immersive focus tokens"
            )
        }
    }

    func testCanvasDocumentCardsUseCanvasDocumentSurfaceInsteadOfPureWhite() throws {
        let wrapperSource = try source("Canvas/CosmoBlockWrapper.swift")

        XCTAssertTrue(wrapperSource.contains("DS.canvasDocumentSurface"))
    }

    func testCanvasNoteBodyUsesBlockListEditorForStructuredElements() throws {
        let noteBlockSource = try source("Canvas/NoteBlockView.swift")
        let bodyViewRange = try XCTUnwrap(noteBlockSource.range(of: "private var bodyView: some View"))
        let footerRange = try XCTUnwrap(noteBlockSource.range(of: "private var noteFooter: some View"))
        let bodyViewSource = String(noteBlockSource[bodyViewRange.lowerBound..<footerRange.lowerBound])

        XCTAssertTrue(bodyViewSource.contains("BlockListView("))
        XCTAssertFalse(bodyViewSource.contains("CosmoDocumentEditor("))
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
        XCTAssertTrue(draftEditorSource.contains("minHeight: max(400, height - 200)"))
    }

    func testMarginaliaLabelsUseSubtleFocusRulesInBlackMono() throws {
        let primitivesSource = try source("UI/FocusMode/Shared/AtelierPrimitives.swift")

        XCTAssertTrue(primitivesSource.contains("private var marginaliaRuleColor"))
        XCTAssertTrue(primitivesSource.contains("DS.usesImmersiveFocusAppearance ? DS.focusImmersiveBorder.opacity(0.9) : DS.sepiaSubtle"))
        XCTAssertTrue(primitivesSource.contains(".fill(marginaliaRuleColor)"))
    }

    func testPremiumFocusModesUseSharedGlassChromePrimitives() throws {
        let premiumChromeSource = try source("UI/FocusMode/Shared/FocusModePremiumChrome.swift")
        let ideaFocusSource = try source("UI/FocusMode/Ideas/IdeaFocusModeView.swift")
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        XCTAssertTrue(premiumChromeSource.contains("struct FocusModeGlassRail"))
        XCTAssertTrue(premiumChromeSource.contains("struct FocusModeInspectorSection"))
        XCTAssertTrue(premiumChromeSource.contains("struct FocusModeMediaWell"))
        XCTAssertTrue(ideaFocusSource.contains("FocusModeInspectorSection"))
        XCTAssertTrue(swipeFocusSource.contains("FocusModeInspectorSection"))
    }

    func testIdeaFocusModeRemovesUnusedCosmoMarginaliaComposer() throws {
        let ideaFocusSource = try source("UI/FocusMode/Ideas/IdeaFocusModeView.swift")

        XCTAssertFalse(ideaFocusSource.contains("marginaliaCosmoSection"))
        XCTAssertFalse(ideaFocusSource.contains("FocusCosmoPanel(session: cosmoSession"))
    }

    func testSwipeTeardownLivesBelowSourcePreviewInsteadOfThirdColumn() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        XCTAssertTrue(swipeFocusSource.contains("sourceStage(atom: atom)"))
        XCTAssertTrue(swipeFocusSource.contains("teardownRail"))
        XCTAssertTrue(swipeFocusSource.contains("private struct SwipeStudyTeardownShell<Source: View, Transcript: View, Teardown: View>"))
        XCTAssertFalse(swipeFocusSource.contains("@ViewBuilder marginalia: () -> Marginalia"))
    }

    func testSwipeCompactLayoutPlacesTranscriptBeforeTeardown() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")
        let compactRange = try XCTUnwrap(swipeFocusSource.range(of: "private var compactStack: some View"))
        let wideRange = try XCTUnwrap(swipeFocusSource.range(of: "private var wideTable: some View"))
        let compactSource = String(swipeFocusSource[compactRange.lowerBound..<wideRange.lowerBound])

        let sourceRange = try XCTUnwrap(compactSource.range(of: "source"))
        let transcriptRange = try XCTUnwrap(compactSource.range(of: "transcript"))
        let teardownRange = try XCTUnwrap(compactSource.range(of: "teardown"))

        XCTAssertLessThan(sourceRange.lowerBound, transcriptRange.lowerBound)
        XCTAssertLessThan(transcriptRange.lowerBound, teardownRange.lowerBound)
    }

    func testSwipeSourcePreviewAvoidsDoubleContainerChrome() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        XCTAssertTrue(swipeFocusSource.contains("sourcePreviewCard(atom: atom)"))
        XCTAssertFalse(swipeFocusSource.contains("FocusModeMediaWell(maxWidth: isPaneContext ? 360 : 460)"))
    }

    func testSwipeTeardownStartsWithInsightStructureAndPhysics() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        XCTAssertFalse(swipeFocusSource.contains("HookAnalysisCard(analysis: analysis)"))
        XCTAssertFalse(swipeFocusSource.contains("MarginaliaLabel(\"TEARDOWN\")"))

        let insightRange = try XCTUnwrap(swipeFocusSource.range(of: "marginaliaInsight(insight)"))
        let structureRange = try XCTUnwrap(swipeFocusSource.range(of: "StructureMapView("))
        let physicsRange = try XCTUnwrap(swipeFocusSource.range(of: "ContentPhysicsSection(profile: physicsProfile)"))

        XCTAssertLessThan(insightRange.lowerBound, structureRange.lowerBound)
        XCTAssertLessThan(structureRange.lowerBound, physicsRange.lowerBound)
    }

    func testSwipeAnalysisRailUsesInspectorContainersForLowerSections() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")
        let similarSwipesSource = try source("UI/FocusMode/SwipeStudy/SimilarSwipesSection.swift")

        XCTAssertTrue(swipeFocusSource.contains("FocusModeInspectorSection(\"TAXONOMY\")"))
        XCTAssertTrue(similarSwipesSource.contains("FocusModeInspectorSection(\"PATTERNS\")"))
        XCTAssertTrue(similarSwipesSource.contains("FocusModeInspectorSection(\"RELATED\")"))
        XCTAssertFalse(swipeFocusSource.contains("instagramAnalysisPlaceholder"))
        XCTAssertFalse(swipeFocusSource.contains("Coming Soon"))
    }

    func testSwipeAnalysisRailPlacesPhysicsAtBottom() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        let taxonomyRange = try XCTUnwrap(swipeFocusSource.range(of: "FocusModeInspectorSection(\"TAXONOMY\")"))
        let relatedRange = try XCTUnwrap(swipeFocusSource.range(of: "SimilarSwipesSection("))
        let physicsRange = try XCTUnwrap(swipeFocusSource.range(of: "FocusModeInspectorSection(\"PHYSICS\")"))

        XCTAssertLessThan(taxonomyRange.lowerBound, relatedRange.lowerBound)
        XCTAssertLessThan(relatedRange.lowerBound, physicsRange.lowerBound)
    }

    func testSwipeStudyUsesThinCustomScrollChrome() throws {
        let swipeFocusSource = try source("UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift")

        XCTAssertTrue(swipeFocusSource.contains("@State private var teardownScrollMetrics = CortexScrollMetrics()"))
        XCTAssertTrue(swipeFocusSource.contains("CortexScrollViewIntrospector"))
        XCTAssertTrue(swipeFocusSource.contains("CortexThinScrollbar(metrics: teardownScrollMetrics)"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
