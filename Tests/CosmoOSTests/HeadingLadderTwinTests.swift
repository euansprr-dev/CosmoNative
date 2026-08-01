// Tests/CosmoOSTests/HeadingLadderTwinTests.swift
// The Note-page heading ladder (jury, July 2026) lives in FOUR hand-copied
// tables. Nothing but agreement makes them a ladder — this suite makes the
// agreement machine-enforced (source-string asserts, the repo's established
// pattern for cross-file twins).

import XCTest
@testable import CosmoOS

final class HeadingLadderTwinTests: XCTestCase {
    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            let candidate = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("CosmoOS.xcodeproj").path) {
                return candidate
            }
            url = candidate
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func source(_ repoRelativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(repoRelativePath),
            encoding: .utf8
        )
    }

    /// All four heading tables carry the modular formulas at the agreed
    /// weights: H1 min(34, ×1.85) semibold · H2 ×1.45 semibold · H3 ×1.20
    /// medium. A drift in any one silently re-typesets rows at hydration,
    /// first-keystroke, or apply time.
    func testAllFourHeadingTablesAgree() throws {
        let serializer = try source("Editor/RichDocument.swift")
        XCTAssertTrue(serializer.contains("min(34, (fontSize * 1.85).rounded()), weight: .semibold"))
        XCTAssertTrue(serializer.contains("ofSize: (fontSize * 1.45).rounded(), weight: .semibold"))
        XCTAssertTrue(serializer.contains("ofSize: (fontSize * 1.20).rounded(), weight: .medium"))

        let coordinator = try source("Editor/TextKitCoordinator.swift")
        // applyHeading (parent.fontSize variant)
        XCTAssertTrue(coordinator.contains("min(34, (parent.fontSize * 1.85).rounded()), weight: .semibold"))
        XCTAssertTrue(coordinator.contains("ofSize: (parent.fontSize * 1.45).rounded(), weight: .semibold"))
        XCTAssertTrue(coordinator.contains("ofSize: (parent.fontSize * 1.20).rounded(), weight: .medium"))
        // seedTypingAttributesForEmptyRow — the fourth table
        XCTAssertTrue(coordinator.contains("size = min(34, (fontSize * 1.85).rounded())"))
        XCTAssertTrue(coordinator.contains("size = (fontSize * 1.45).rounded()"))
        XCTAssertTrue(coordinator.contains("size = (fontSize * 1.20).rounded()"))

        let placeholder = try source("Editor/BlockEditor/BlockListView.swift")
        XCTAssertTrue(placeholder.contains("min(34, (fontSize * 1.85).rounded()), weight: .semibold"))
        XCTAssertTrue(placeholder.contains("ofSize: (fontSize * 1.45).rounded(), weight: .semibold"))
        XCTAssertTrue(placeholder.contains("ofSize: (fontSize * 1.20).rounded(), weight: .medium"))
    }

    /// The old additive table must not resurface anywhere in the four twins.
    func testAdditiveLadderDoesNotResurface() throws {
        for path in [
            "Editor/RichDocument.swift",
            "Editor/TextKitCoordinator.swift",
            "Editor/BlockEditor/BlockListView.swift",
        ] {
            let text = try source(path)
            XCTAssertFalse(text.contains("max(32, fontSize + 16)"), "additive H1 back in \(path)")
            XCTAssertFalse(text.contains("max(32, parent.fontSize + 16)"), "additive H1 back in \(path)")
        }
    }

    /// The note-focus title (38 bold) must stay above the H1 clamp (34) —
    /// the page's one bold object outranks its first heading at every size.
    func testTitleTopsTheLadder() {
        XCTAssertEqual(SharedTitleSurfaceStyle.noteFocus.fontSize, 38)
        XCTAssertEqual(SharedTitleSurfaceStyle.noteFocus.baseFontWeight, .bold)
        XCTAssertGreaterThan(SharedTitleSurfaceStyle.noteFocus.fontSize, 34)
    }
}
