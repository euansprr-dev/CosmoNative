import XCTest
@testable import CosmoOS

/// The bench must always be able to COMPRESS into the width it is handed.
/// When it can't — when the columns HStack reports more width than the sheet
/// was given — the container's `.frame(width:)` centres the oversized child
/// and clips it on both edges, which is the "text goes behind everything"
/// state. The width classes are what keep that from happening, so the
/// threshold is derived from the column budget rather than typed.
@MainActor
final class IdeaWorkspaceLayoutPolicyTests: XCTestCase {

    private static let conversationDefaultsKey = "idea.workbench.conversation"
    private var savedConversationDefault: Bool!

    override func setUp() {
        super.setUp()
        savedConversationDefault = UserDefaults.standard.bool(forKey: Self.conversationDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedConversationDefault, forKey: Self.conversationDefaultsKey)
        super.tearDown()
    }

    private func model(inspector: Bool, conversation: Bool) -> IdeaWorkspaceModel {
        UserDefaults.standard.set(conversation, forKey: Self.conversationDefaultsKey)
        let workspace = IdeaWorkspaceModel()
        workspace.isInspectorVisible = inspector
        return workspace
    }

    // MARK: - Column budget

    func testSeatsColumnsLeavesTheManuscriptItsMeasure() {
        let column = IdeaWorkspaceMetrics.columnWidth
        let measure = IdeaWorkspaceMetrics.minimumManuscriptMeasure
        let inset = IdeaWorkspaceMetrics.sheetInset

        // Exactly enough is enough; one point less is not.
        XCTAssertTrue(IdeaWorkspaceMetrics.seatsColumns(count: 1, in: inset + column + measure))
        XCTAssertFalse(IdeaWorkspaceMetrics.seatsColumns(count: 1, in: inset + column + measure - 1))

        XCTAssertTrue(IdeaWorkspaceMetrics.seatsColumns(count: 2, in: inset + 2 * column + measure))
        XCTAssertFalse(IdeaWorkspaceMetrics.seatsColumns(count: 2, in: inset + 2 * column + measure - 1))
    }

    /// The predicate answers one question — does the manuscript keep its
    /// measure with `count` columns beside it — so a sheet too narrow for the
    /// manuscript alone is compact even with nothing to seat. Harmless (there
    /// is no column to place either way), but worth pinning: it means the
    /// answer is never "yes" purely because the caller asked for nothing.
    func testTheMeasureIsRequiredEvenWithNoColumns() {
        XCTAssertTrue(IdeaWorkspaceMetrics.seatsColumns(count: 0, in: 1400))
        XCTAssertFalse(IdeaWorkspaceMetrics.seatsColumns(count: 0, in: 420))
    }

    /// The regression the old flat 1000pt threshold produced: two 300pt
    /// columns seated in a sheet with no room left for the manuscript.
    func testTwoColumnsAreNotSeatedAtTheOldThreshold() {
        XCTAssertFalse(IdeaWorkspaceMetrics.seatsColumns(count: 2, in: 1000))
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1000, columns: 2), .compact)
    }

    /// …and the regression a flat RAISED threshold would have produced
    /// instead: the common single-inspector setup thrown into overlay mode at
    /// widths where it fits beside the manuscript perfectly well.
    func testOneColumnSurvivesTheBandWhereTwoDoNot() {
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1000, columns: 1), .regular)
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1100, columns: 1), .regular)
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 1100, columns: 2), .compact)
    }

    func testPaneWidthsAreCompact() {
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 420, columns: 1), .compact)
        XCTAssertEqual(IdeaWorkspaceBreakpoint(width: 680, columns: 1), .compact)
    }

    // MARK: - Requested columns

    func testRequestedColumnCountReadsIntentNotPresentation() {
        XCTAssertEqual(model(inspector: true, conversation: true).requestedColumnCount, 2)
        XCTAssertEqual(model(inspector: true, conversation: false).requestedColumnCount, 1)
        XCTAssertEqual(model(inspector: false, conversation: false).requestedColumnCount, 0)

        // Overlay flags are presentation, not intent — they must not count.
        let workspace = model(inspector: false, conversation: false)
        workspace.isInspectorOverlayPresented = true
        workspace.isConversationOverlayPresented = true
        XCTAssertEqual(workspace.requestedColumnCount, 0)
    }

    // MARK: - Toggles

    /// The circularity guard. At this width the inspector fits as a column but
    /// a second column does not, so asking for the conversation panel is
    /// itself what pushes the sheet into compact. If the toggle only raised
    /// the intent flag, the user's click would show nothing at all.
    func testAskingForAPanelThatDoesNotFitAsAColumnStillShowsIt() {
        let workspace = model(inspector: true, conversation: false)
        let width: CGFloat = 1100

        workspace.breakpoint = IdeaWorkspaceBreakpoint(width: width, columns: workspace.requestedColumnCount)
        XCTAssertEqual(workspace.breakpoint, .regular)
        XCTAssertTrue(workspace.isInspectorShowing(at: workspace.breakpoint))

        workspace.toggleConversation()

        let resolved = IdeaWorkspaceBreakpoint(width: width, columns: workspace.requestedColumnCount)
        XCTAssertEqual(resolved, .compact, "a second column does not fit at this width")
        XCTAssertTrue(
            workspace.isConversationShowing(at: resolved),
            "the panel the user just asked for must appear, as an overlay if not as a column"
        )
    }

    func testTogglingAVisiblePanelOffHidesItInBothClasses() {
        for breakpoint in [IdeaWorkspaceBreakpoint.regular, .compact] {
            let workspace = model(inspector: true, conversation: false)
            workspace.breakpoint = breakpoint
            if breakpoint == .compact { workspace.isInspectorOverlayPresented = true }
            XCTAssertTrue(workspace.isInspectorShowing)

            workspace.toggleInspector()
            XCTAssertFalse(workspace.isInspectorVisible)
            XCTAssertFalse(workspace.isInspectorOverlayPresented)
            XCTAssertFalse(workspace.isInspectorShowing(at: .regular))
            XCTAssertFalse(workspace.isInspectorShowing(at: .compact))
        }
    }

    func testOverlaysStayExclusive() {
        let workspace = model(inspector: false, conversation: false)
        workspace.breakpoint = .compact

        workspace.toggleInspector()
        XCTAssertTrue(workspace.isInspectorOverlayPresented)

        workspace.toggleConversation()
        XCTAssertTrue(workspace.isConversationOverlayPresented)
        XCTAssertFalse(workspace.isInspectorOverlayPresented, "opening one overlay closes the other")
    }

    func testConversationIntentPersists() {
        let workspace = model(inspector: true, conversation: false)
        workspace.breakpoint = .regular

        workspace.toggleConversation()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.conversationDefaultsKey))

        workspace.toggleConversation()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.conversationDefaultsKey))
    }
}
