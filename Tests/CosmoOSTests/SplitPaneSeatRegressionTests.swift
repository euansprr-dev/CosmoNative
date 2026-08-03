import XCTest
@testable import CosmoOS

/// Regression from the August 2026 idea-bench-beside-pane clipping session:
/// opening a pane animates `mainSplitRatio`, and on macOS 26 an animated
/// `.frame(width:)` over a GeometryReader-fed subtree can commit ONE
/// mid-flight proposal and then stop updating. The main slot's content
/// latched at an intermediate width (the Idea bench measured 1111pt inside a
/// 960pt slot) and rendered clipped on both edges until the next un-animated
/// width stream (divider drag / window resize) re-proposed.
///
/// The law pinned here: in `SplitPaneContainer`, SEATS ARE LAYOUT, SPRINGS
/// ARE CLIPS. The main slot lays its content out at a seat width that only
/// ever changes inside a `disablesAnimations` transaction; the animated
/// split ratio may move nothing but the clip window around that seat.
final class SplitPaneSeatRegressionTests: XCTestCase {

    func testMainSlotSeatsContentOutsideTheSplitSpring() throws {
        let source = try splitPaneContainerSource()
        let code = codeLines(of: source)

        XCTAssertTrue(
            code.contains("seatedMainWidth ?? mainWidth"),
            "The main slot must lay content out at the SEAT width (seatedMainWidth, falling back to the target on first render) — laying it out at the animated mainWidth directly re-opens the macOS 26 mid-flight latch."
        )
        XCTAssertTrue(
            code.contains("seat.disablesAnimations = true"),
            "Seat adoption must run in a disablesAnimations transaction: the seat lands in one un-animated layout pass while the clip window springs."
        )
        XCTAssertTrue(
            code.contains("withTransaction(seat)"),
            "The seat state change must be committed through withTransaction(seat) so no inherited animation can ride it."
        )
    }

    /// The seat and the clip are two frames: the inner (seat) uses the seated
    /// width, the outer (clip) uses the live target. Both are leading-aligned
    /// so mid-spring the content stays anchored at the left edge — an
    /// oversized child of `.frame(width:)` is otherwise centred-and-clipped
    /// on BOTH edges, which is the broken look this session fixed.
    func testSeatAndClipFramesAreLeadingAligned() throws {
        let source = try splitPaneContainerSource()
        let code = codeLines(of: source)

        XCTAssertTrue(
            code.contains(".frame(width: seatedMainWidth ?? mainWidth, height: geo.size.height, alignment: .leading)"),
            "The seat frame must be leading-aligned."
        )
        XCTAssertTrue(
            code.contains(".frame(width: mainWidth, height: geo.size.height, alignment: .leading)"),
            "The clip frame must be leading-aligned so overflow is only ever revealed/covered at the trailing edge."
        )
    }

    // MARK: - The destination layer is layout-inert

    /// August 3 2026, the real root cause of the pane-open clipping: a ZStack
    /// sizes to its children's UNION and re-proposes it to every sibling.
    /// The main slot's ZStack holds the always-alive canvas, the active
    /// destination, and the focus overlay — and both the warm canvas and the
    /// Today dashboard have ~1111pt incompressible minimums. With a pane open
    /// (slot ~700-960pt) the hidden wide layer inflated the union and the
    /// focus overlay laid out hundreds of points wider than its slot,
    /// rendering centred-and-clipped. The law: destination layers render
    /// inside GeometryReader windows that always report the proposal, so a
    /// hidden layer can never shape the stack.
    func testDestinationLayerIsWrappedInAProposalWindow() throws {
        let source = try mainViewSource()
        let code = codeLines(of: source)

        XCTAssertTrue(
            code.contains("GeometryReader { destinationWindow in"),
            "destinationContent must render inside a GeometryReader window — without it, a destination's incompressible minimum inflates the main-slot ZStack union and every sibling (including the focus overlay) is re-proposed the inflated width."
        )
        XCTAssertTrue(
            code.contains("width: destinationWindow.size.width"),
            "The destination window must pin the destination layer to the proposal width and clip its overflow."
        )
        XCTAssertTrue(
            code.contains("GeometryReader { canvasWindow in"),
            "The keep-alive CanvasView must render inside its own GeometryReader window so its minimum cannot inflate the destination ZStack for sibling destination pages."
        )
    }

    // MARK: - Helpers

    /// Comment lines narrate the law and may name banned patterns; only code counts.
    private func codeLines(of source: String) -> String {
        source
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func splitPaneContainerSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("Navigation/SplitPaneContainer.swift"),
            encoding: .utf8
        )
    }

    private func mainViewSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
