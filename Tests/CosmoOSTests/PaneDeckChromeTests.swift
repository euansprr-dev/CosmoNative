import XCTest
@testable import CosmoOS

/// Unified pane chrome (July 2026): the deck tab strip lives inside each
/// focus mode's own chrome row — one row of islands per pane, no stacked
/// bars, close only in tabs, and structurally overlap-free at pane widths.
@MainActor
final class PaneDeckChromeTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - Strip layout policy (the two-rung ladder)

    private func rank(_ presentation: PaneTabStripPresentation) -> Int {
        switch presentation {
        case .titled: return 1
        case .overflow: return 0
        }
    }

    func testTwoTabsAtEverydaySplitShowBothTitles() {
        // 50/50 split on a 14" MacBook window (~756pt pane): both tabs must
        // be named — this exact case regressed to anonymous chips once.
        let budget = PaneTabStripLayoutPolicy.budget(paneWidth: 756)
        guard case .titled(let cap) = PaneTabStripLayoutPolicy.presentation(budget: budget, tabCount: 2) else {
            return XCTFail("Two tabs at a half split must both show titles.")
        }
        XCTAssertGreaterThanOrEqual(cap, 100)
    }

    func testCrampedPaneFallsBackToNamedOverflowNeverChips() {
        // At the 420pt pane floor two tabs can't both carry readable names —
        // the fallback is the focused tab + a "+N" menu, never nameless dots.
        let budget = PaneTabStripLayoutPolicy.budget(
            paneWidth: PaneSlotPresentationPolicy.minimumContentWidth
        )
        guard case .overflow(let focusedCap) = PaneTabStripLayoutPolicy.presentation(budget: budget, tabCount: 2) else {
            return XCTFail("A floor-width pane must use the overflow rung.")
        }
        XCTAssertGreaterThanOrEqual(focusedCap, 72)
    }

    func testManyTabsPreferNamedOverflowOverMicroTitles() {
        // Six tabs never squeeze into sub-readable titles — even a huge pane
        // routes the siblings into the named menu.
        let budget = PaneTabStripLayoutPolicy.budget(paneWidth: 2000)
        XCTAssertEqual(
            rank(PaneTabStripLayoutPolicy.presentation(budget: budget, tabCount: 6)),
            rank(.overflow(focusedCap: 0))
        )
    }

    func testLadderIsMonotonicAcrossWidths() {
        // The rung never improves as the pane narrows.
        for tabCount in 1...6 {
            var previous = Int.max
            for paneWidth in stride(from: 2000.0, through: 420.0, by: -20.0) {
                let presentation = PaneTabStripLayoutPolicy.presentation(
                    budget: PaneTabStripLayoutPolicy.budget(paneWidth: paneWidth),
                    tabCount: tabCount
                )
                XCTAssertLessThanOrEqual(rank(presentation), previous)
                previous = rank(presentation)
            }
        }
    }

    func testTitledCapsStayWithinReadableBand() {
        // Whenever the ladder chooses titles, each title is between the
        // readable floor and the calm ceiling.
        for tabCount in 1...6 {
            for paneWidth in stride(from: 420.0, through: 2000.0, by: 20.0) {
                let presentation = PaneTabStripLayoutPolicy.presentation(
                    budget: PaneTabStripLayoutPolicy.budget(paneWidth: paneWidth),
                    tabCount: tabCount
                )
                if case .titled(let cap) = presentation, tabCount > 1 {
                    XCTAssertGreaterThanOrEqual(cap, PaneTabStripLayoutPolicy.minTitleWidth)
                    XCTAssertLessThanOrEqual(cap, PaneTabStripLayoutPolicy.maxTitleWidth)
                }
            }
        }
    }

    func testBudgetIsClampedToItsBand() {
        XCTAssertEqual(PaneTabStripLayoutPolicy.budget(paneWidth: 200), 140)
        XCTAssertEqual(PaneTabStripLayoutPolicy.budget(paneWidth: 5000), 560)
        // The dense reserve always yields a smaller or equal budget.
        XCTAssertLessThanOrEqual(
            PaneTabStripLayoutPolicy.budget(paneWidth: 900, hostReserve: PaneTabStripLayoutPolicy.denseHostReserve),
            PaneTabStripLayoutPolicy.budget(paneWidth: 900)
        )
    }

    func testSingleTabAlwaysShowsItsTitle() {
        XCTAssertEqual(
            PaneTabStripLayoutPolicy.presentation(budget: 140, tabCount: 1),
            .titled(titleCap: PaneTabStripLayoutPolicy.soloTitleCap)
        )
    }

    func testAnonymousChipRungIsDeleted() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/PaneDeckTabStrip.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            source.contains("PaneTabStripDensity"),
            "The glyph-chip rung was the design error — hidden panes get the named overflow menu."
        )
        XCTAssertTrue(source.contains("PaneDeckOverflowMenu"))
    }

    func testQuantizedPaneWidthStepsBy24() {
        XCTAssertEqual(PaneDeckChromePayload.quantizedWidth(500), 504)
        XCTAssertEqual(PaneDeckChromePayload.quantizedWidth(504), 504)
        XCTAssertEqual(PaneDeckChromePayload.quantizedWidth(511), 504)
        XCTAssertEqual(PaneDeckChromePayload.quantizedWidth(516.1), 528)
    }

    // MARK: - Seam conformance (every migrated mode, one shape)

    /// The seven migrated surfaces mount the strip and no longer own a pane
    /// close button — close lives in the deck tab.
    func testMigratedFocusModesMountStripAndDropPaneClose() throws {
        let migratedFiles = [
            "UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift",
            "UI/FocusMode/Notes/NoteFocusModeView.swift",
            "UI/FocusMode/Content/ContentFocusModeView.swift",
            "UI/FocusMode/Research/ResearchFocusModeView.swift",
            "UI/FocusMode/Ideas/IdeaWorkspaceToolbar.swift",
            "UI/FocusMode/Connection/ConnectionWorkspaceToolbar.swift",
            "UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift",
        ]

        for file in migratedFiles {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(file),
                encoding: .utf8
            )
            XCTAssertTrue(
                source.contains("PaneDeckTabStrip(") && source.contains("context: paneDeckChrome"),
                "\(file) must mount the deck tab strip in its chrome row."
            )
            XCTAssertFalse(
                source.contains("isPaneContext, !isPeekContext, atomChrome == nil"),
                "\(file) must not keep a mode-owned pane close — close lives in the tab."
            )
        }
    }

    /// Absolute centering overlaps side clusters at pane widths; migrated
    /// rows with center content must flow it in pane context.
    func testPaneContextRowsFlowTheirCenterSlot() throws {
        let rowsWithCenters = [
            "UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift",
            "UI/FocusMode/Content/ContentFocusModeView.swift",
            "UI/FocusMode/Ideas/IdeaWorkspaceToolbar.swift",
            "UI/FocusMode/Connection/ConnectionWorkspaceToolbar.swift",
        ]
        for file in rowsWithCenters {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(file),
                encoding: .utf8
            )
            XCTAssertTrue(
                source.contains("centersAbsolutely: !isPaneContext"),
                "\(file) must flow its center slot in pane context (no ZStack overlap)."
            )
        }
    }

    /// Elevation class rule: persistent bars attached to a pane cast no
    /// shadow (material-only separation); floating overlays keep theirs.
    /// The default is unchanged so every existing panel renders identically.
    func testAttachedBarsShedTheirCastShadow() throws {
        let panel = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Core/Components/CosmoGlassPanel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(panel.contains("castsShadow: Bool = true"))
        XCTAssertTrue(panel.contains("castsShadow ? DS.glassPanelShadow : .clear"))

        let browserBar = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/Browser/CosmoBrowserToolbar.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            browserBar.contains("castsShadow: false"),
            "The browser's persistent toolbar is an attached bar — no cast shadow inside the pane."
        )
    }

    /// CosmoChromeRow's flow mode is additive — the default stays absolute
    /// centering so unmigrated call sites render byte-identical.
    func testChromeRowFlowModeDefaultsToAbsoluteCentering() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Core/Components/CosmoChromeIsland.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("var centersAbsolutely: Bool = true"))
    }

    // MARK: - Adoption table

    func testAdoptionTableMatchesMigratedSurfaces() {
        // Unified Pages use the shell's tabs above their document toolbar.
        XCTAssertFalse(PaneDeckChromeAdoption.modeHostsDeckChrome(
            .entity(EntitySelection(id: 1, type: .note))
        ))
        // Mode-hosted: the other migrated entity families and the browser.
        XCTAssertTrue(PaneDeckChromeAdoption.modeHostsDeckChrome(
            .entity(EntitySelection(id: 2, type: .research))
        ))
        XCTAssertTrue(PaneDeckChromeAdoption.modeHostsDeckChrome(
            .webBrowser(url: URL(string: "https://example.com")!, title: "Example")
        ))
        // The assistant toolbar hosts the strip like the browser — one row
        // of glass, the pane's name and close live only in its tab.
        XCTAssertTrue(PaneDeckChromeAdoption.modeHostsDeckChrome(.cosmoWindow))
        XCTAssertTrue(PaneDeckChromeAdoption.modeHostsDeckChrome(.inlineAssistant))

        // Shell-hosted standalone row: container surfaces.
        XCTAssertFalse(PaneDeckChromeAdoption.modeHostsDeckChrome(.commandCenter))
        XCTAssertFalse(PaneDeckChromeAdoption.modeHostsDeckChrome(.swipeGallery))
        XCTAssertFalse(PaneDeckChromeAdoption.modeHostsDeckChrome(.thinkspace(thinkspaceId: "t")))
        XCTAssertFalse(PaneDeckChromeAdoption.modeHostsDeckChrome(.collaborator(
            target: CollaborationTarget(
                source: .focusMode,
                entityID: 1,
                entityType: .note,
                atomUUID: "a",
                title: "Draft"
            ),
            presetId: nil
        )))
    }

    /// The shell fallback must be stacked (VStack), never overlaid — the
    /// container surfaces carry top-anchored mastheads a floating island
    /// could cover.
    func testStandaloneChromeIsStackedNotOverlaid() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Navigation/PaneContentView.swift"),
            encoding: .utf8
        )
        let bodyStart = try XCTUnwrap(source.range(of: "var body: some View {")?.lowerBound)
        let taskStart = try XCTUnwrap(source.range(of: ".task(id: content.entitySelection)")?.lowerBound)
        let bodyChrome = String(source[bodyStart..<taskStart])

        XCTAssertTrue(bodyChrome.contains("VStack(spacing: 0)"))
        XCTAssertTrue(bodyChrome.contains("PaneDeckStandaloneChrome(context: paneDeckChrome)"))
        XCTAssertFalse(
            bodyChrome.contains(".overlay(alignment: .topTrailing)"),
            "The old floating close overlay must not return — chrome stacks, content clears it."
        )
    }
}
