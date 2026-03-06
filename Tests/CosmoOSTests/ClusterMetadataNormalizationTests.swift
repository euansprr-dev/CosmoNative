import XCTest
@testable import CosmoOS

final class ClusterMetadataNormalizationTests: XCTestCase {
    func testTaskCanonicalMappings() {
        XCTAssertEqual(CanvasClusterEngine.canonicalTaskStatus("pending"), "todo")
        XCTAssertEqual(CanvasClusterEngine.canonicalTaskStatus("to do"), "todo")
        XCTAssertEqual(CanvasClusterEngine.canonicalTaskStatus("in progress"), "in_progress")
        XCTAssertEqual(CanvasClusterEngine.canonicalTaskStatus("done"), "completed")
        XCTAssertEqual(CanvasClusterEngine.canonicalTaskStatus("unknown"), "todo")
    }

    func testContentCanonicalMappings() {
        XCTAssertEqual(CanvasClusterEngine.canonicalContentPhase("brainstorm"), "ideation")
        XCTAssertEqual(CanvasClusterEngine.canonicalContentPhase("ideation"), "ideation")
        XCTAssertEqual(CanvasClusterEngine.canonicalContentPhase("draft"), "draft")
        XCTAssertEqual(CanvasClusterEngine.canonicalContentPhase("polish"), "polish")
        XCTAssertEqual(CanvasClusterEngine.canonicalContentPhase("archive"), "archived")
        XCTAssertEqual(CanvasClusterEngine.canonicalContentPhase("unknown"), "ideation")
    }

    func testIdeaCanonicalMappings() {
        XCTAssertEqual(CanvasClusterEngine.canonicalIdeaStatus("spark"), "spark")
        XCTAssertEqual(CanvasClusterEngine.canonicalIdeaStatus("developing"), "developing")
        XCTAssertEqual(CanvasClusterEngine.canonicalIdeaStatus("inproduction"), "ready")
        XCTAssertEqual(CanvasClusterEngine.canonicalIdeaStatus("published"), "ready")
        XCTAssertEqual(CanvasClusterEngine.canonicalIdeaStatus("archive"), "archived")
        XCTAssertEqual(CanvasClusterEngine.canonicalIdeaStatus("unknown"), "spark")
    }

    func testTypeRoutedNormalizationUsesEntityTypeRules() {
        XCTAssertEqual(
            CanvasClusterEngine.normalizedBoardColumnValue(for: .task, rawValue: "done"),
            "completed"
        )
        XCTAssertEqual(
            CanvasClusterEngine.normalizedBoardColumnValue(for: .content, rawValue: "brainstorm"),
            "ideation"
        )
        XCTAssertEqual(
            CanvasClusterEngine.normalizedBoardColumnValue(for: .idea, rawValue: "published"),
            "ready"
        )
    }
}
