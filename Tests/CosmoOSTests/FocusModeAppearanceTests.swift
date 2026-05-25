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

        XCTAssertTrue(swipeFocusSource.contains("sourceAndTeardownRail(atom: atom)"))
        XCTAssertTrue(swipeFocusSource.contains("private func sourceAndTeardownRail(atom: Atom) -> some View"))
        XCTAssertTrue(swipeFocusSource.contains("private struct SwipeStudyTeardownShell<Source: View, Transcript: View>"))
        XCTAssertFalse(swipeFocusSource.contains("@ViewBuilder marginalia: () -> Marginalia"))
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

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
