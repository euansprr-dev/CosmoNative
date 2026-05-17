import XCTest
@testable import CosmoOS

final class CommandKFormModelTests: XCTestCase {
    func testCaptureSwipeFormRequiresURL() {
        var form = CommandKInlineFormModel(kind: .captureSwipe)

        XCTAssertEqual(form.primaryTitle, "Capture")
        XCTAssertFalse(form.validation.isValid)
        XCTAssertEqual(form.validation.message, "Paste a swipe URL")

        form.setValue("https://www.instagram.com/reel/abc", for: .url)

        XCTAssertTrue(form.validation.isValid)
        XCTAssertEqual(
            form.resolvedIntent,
            .executeTool(name: "capture_swipe", arguments: ["url": "https://www.instagram.com/reel/abc"])
        )
    }

    func testCreateTaskFormBuildsCreateTaskIntent() {
        var form = CommandKInlineFormModel(kind: .createTask)
        form.setValue("Review military-base swipe", for: .title)
        form.setValue("tomorrow", for: .date)

        XCTAssertTrue(form.validation.isValid)
        XCTAssertEqual(
            form.resolvedIntent,
            .executeTool(
                name: "create_task",
                arguments: ["title": "Review military-base swipe", "date": "tomorrow"]
            )
        )
    }
}
