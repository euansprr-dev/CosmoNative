import XCTest
@testable import CosmoOS

/// GUARD-TWIN of `IdeaInspectorRegressionTests`: the July 2026 macOS 26
/// dropped-first-commit bug reached the concept workspace next — the 280pt
/// inspector column seated but never composited (blank strip over the board,
/// cards clipped mid-word by a stale raster). Same law, second shell.
final class ConnectionInspectorRegressionTests: XCTestCase {
    // MARK: - The shell never animates its own panel seats

    /// The inspector column used to insert under the shell's own implicit
    /// `.animation(value:)`. When that slide rode a transaction the shell
    /// didn't own, macOS 26 dropped the panel subtree's compositor commit:
    /// laid out and hit-testable, never drawn — and the board beside it kept
    /// a stale wider raster clipped at the new bounds. The law: the shell
    /// seats panels instantly; only toggle sites supply an animated
    /// transaction via `withAnimation`.
    func testConnectionShellCarriesNoImplicitPanelAnimation() throws {
        let source = try connectionWorkspaceViewSource()

        guard let shellStart = source.range(of: "struct ConnectionWorkspaceView"),
              let shellEnd = source.range(of: "// MARK: - Staged-edit review") else {
            return XCTFail("ConnectionWorkspaceView region not found — update this test's markers.")
        }
        // Comment lines narrate the law and may name the banned modifier;
        // only code counts.
        let shell = source[shellStart.lowerBound..<shellEnd.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        XCTAssertFalse(
            shell.contains(".animation("),
            "ConnectionWorkspaceView must not animate panel insertion itself: a seat riding a transaction it doesn't own orphans the transition and the panel renders invisible-but-hit-testable on macOS 26. Toggle sites own the transaction (withAnimation)."
        )
        XCTAssertTrue(
            shell.contains(".transition(.move(edge: .trailing)"),
            "Panels keep their move/opacity transitions — they animate only when a toggle site wraps the state change in withAnimation."
        )
    }

    /// Every user-facing toggle must bring its own transaction now that the
    /// shell no longer animates for them.
    func testConnectionToggleSitesWrapWithAnimation() throws {
        for file in ["UI/FocusMode/Connection/ConnectionWorkspaceToolbar.swift",
                     "UI/FocusMode/Connection/ConnectionFocusModeView.swift"] {
            let source = try String(
                contentsOf: repositoryRoot().appendingPathComponent(file),
                encoding: .utf8
            )
            for toggle in ["toggleInspector()", "toggleNavigator()"] {
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

    // MARK: - The entrance never scales a seated panel

    /// The concept workspace enters as a plain crossfade: its inspector is
    /// visible by default, so the very first commit seats a panel — under the
    /// bloom's scale transition macOS 26 drops that commit and the inspector
    /// opens invisible. Same exemption the idea bench and study surfaces use.
    func testConnectionFocusEntranceIsPlainFade() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Navigation/MainView.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "let usesPlainFade"),
              let end = source.range(of: "FocusModeView(entity: focusEntity)") else {
            return XCTFail("usesPlainFade region not found — update this test's markers.")
        }
        XCTAssertTrue(
            source[start.lowerBound..<end.lowerBound].contains(".connection"),
            "Connection focus must enter with the plain fade — the bloom's scale over its hosted scroll panels drops the seated inspector's first compositor commit on macOS 26."
        )
    }

    // MARK: - Helpers

    private func connectionWorkspaceViewSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("UI/FocusMode/Connection/ConnectionWorkspaceView.swift"),
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
