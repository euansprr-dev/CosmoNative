import XCTest
@testable import CosmoOS

/// Regressions from the July 2026 invisible-inspector session: the bench's
/// right panel rendered hit-testable but never composited on first open, and
/// the Recommended shelf showed the identical global top-4 on every idea.
final class IdeaInspectorRegressionTests: XCTestCase {
    // MARK: - The shell never animates its own panel seats

    /// The inspector column used to insert under the shell's own implicit
    /// `.animation(value:)` when the first width resolve flipped the
    /// breakpoint — inside the bench's entrance transaction. That orphaned
    /// the slide mid-flight: the panel was laid out and hit-testable (hover
    /// tooltips fired) but never drawn until a manual close/reopen re-seated
    /// it. The law: the shell seats panels instantly; only toggle sites
    /// supply an animated transaction via `withAnimation`.
    func testWorkbenchShellCarriesNoImplicitPanelAnimation() throws {
        let source = try atelierPrimitivesSource()

        guard let shellStart = source.range(of: "struct WorkbenchShell"),
              let shellEnd = source.range(of: "// MARK: - Stagger-in modifier") else {
            return XCTFail("WorkbenchShell region not found — update this test's markers.")
        }
        // Comment lines narrate the law and may name the banned modifier;
        // only code counts.
        let shell = source[shellStart.lowerBound..<shellEnd.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        XCTAssertFalse(
            shell.contains(".animation("),
            "WorkbenchShell must not animate panel insertion itself: a breakpoint-driven seat riding the bench's entrance transaction orphans the transition and the panel renders invisible-but-hit-testable. Toggle sites own the transaction (withAnimation)."
        )
        XCTAssertTrue(
            shell.contains(".transition(.move(edge: .trailing)"),
            "Panels keep their move/opacity transitions — they animate only when a toggle site wraps the state change in withAnimation."
        )
    }

    /// Every user-facing toggle must bring its own transaction now that the
    /// shell no longer animates for them.
    func testIdeaToggleSitesWrapWithAnimation() throws {
        for file in ["UI/FocusMode/Ideas/IdeaWorkspaceToolbar.swift",
                     "UI/FocusMode/Ideas/IdeaFocusModeView.swift"] {
            let source = try String(
                contentsOf: repositoryRoot().appendingPathComponent(file),
                encoding: .utf8
            )
            for toggle in ["toggleInspector()", "toggleConversation()"] {
                for range in source.occurrenceRanges(of: "workspace.\(toggle)") {
                    let windowStart = source.index(
                        range.lowerBound, offsetBy: -140,
                        limitedBy: source.startIndex
                    ) ?? source.startIndex
                    XCTAssertTrue(
                        source[windowStart..<range.lowerBound].contains("withAnimation("),
                        "\(file): workspace.\(toggle) must run inside withAnimation — the shell no longer supplies the panel-slide transaction."
                    )
                }
            }
        }
    }

    // MARK: - Recommended shelf rotation

    /// One seed per (idea, day): stable while an idea is being worked, and
    /// that is what makes the pick reproducible at all.
    @MainActor
    func testShelfSeedIsDeterministicForSameIdeaAndDay() {
        XCTAssertEqual(
            IdeaFocusModeViewModel.shelfSeed(ideaUUID: "idea-a", dayOrdinal: 700_000),
            IdeaFocusModeViewModel.shelfSeed(ideaUUID: "idea-a", dayOrdinal: 700_000)
        )
    }

    /// Different ideas draw different shelves — the original global top-4
    /// rendered the identical four swipes on every idea in the format family,
    /// which read as "recommendations stopped running".
    @MainActor
    func testShelfSeedVariesAcrossIdeasAndDays() {
        let base = IdeaFocusModeViewModel.shelfSeed(ideaUUID: "idea-a", dayOrdinal: 700_000)
        XCTAssertNotEqual(
            base,
            IdeaFocusModeViewModel.shelfSeed(ideaUUID: "idea-b", dayOrdinal: 700_000),
            "Two ideas on the same day must not share a shelf seed."
        )
        XCTAssertNotEqual(
            base,
            IdeaFocusModeViewModel.shelfSeed(ideaUUID: "idea-a", dayOrdinal: 700_001),
            "The same idea must rotate its shelf across days."
        )
    }

    /// The pick draws 4 from a top-12 performance pool, seeded — never a
    /// bare global `prefix(4)`.
    func testRecommendedShelfDrawsSeededFromTopPool() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("UI/FocusMode/Ideas/IdeaFocusModeViewModel.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "func loadRecommendedSwipes"),
              let end = source.range(of: "func updateFormat") else {
            return XCTFail("loadRecommendedSwipes region not found — update this test's markers.")
        }
        let region = source[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(
            region.contains(".prefix(12)"),
            "The shelf must draw from a top-12 performance pool."
        )
        XCTAssertTrue(
            region.contains("shelfSeed(ideaUUID:"),
            "The shelf pick must be seeded per (idea, day) so it rotates instead of freezing on the global top-4."
        )
    }

    // MARK: - Helpers

    private func atelierPrimitivesSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("UI/FocusMode/Shared/AtelierPrimitives.swift"),
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

private extension String {
    /// All non-overlapping ranges of `needle` — named to avoid colliding with
    /// the stdlib's `ranges(of:)` overloads.
    func occurrenceRanges(of needle: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = startIndex
        while let found = range(of: needle, range: searchStart..<endIndex) {
            result.append(found)
            searchStart = found.upperBound
        }
        return result
    }
}
