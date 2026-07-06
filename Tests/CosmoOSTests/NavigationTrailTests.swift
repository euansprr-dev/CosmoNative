import XCTest
@testable import CosmoOS

/// The trail's recency-unique law: a place lives at most once in the trail,
/// so Back walks distinct places in recency order instead of replaying
/// ping-pong duplicates (deep dive ↔ inquiry session, folder in/out).
@MainActor
final class NavigationTrailTests: XCTestCase {

    private func sidebar(_ id: String) -> NavigationTrail.Moment.Destination {
        .sidebar(.thinkspace(id: id))
    }

    private func focus(_ id: Int64, _ type: EntityType) -> NavigationTrail.Moment.Destination {
        .focusMode(EntitySelection(id: id, type: type))
    }

    private func arrive(_ trail: NavigationTrail, _ destination: NavigationTrail.Moment.Destination) {
        trail.recordArrival(destination, title: "", glyph: "circle")
    }

    private func backDestinations(_ trail: NavigationTrail) -> [NavigationTrail.Moment.Destination] {
        trail.recentBackTrail(limit: .max).map(\.destination)
    }

    func testLinearNavigationWalksStraightBack() {
        let trail = NavigationTrail()
        let home = sidebar("home")
        let note = focus(1, .note)
        let idea = focus(2, .idea)
        arrive(trail, home)
        arrive(trail, note)
        arrive(trail, idea)

        XCTAssertEqual(trail.stepBack()?.destination, note)
        XCTAssertEqual(trail.stepBack()?.destination, home)
        XCTAssertNil(trail.stepBack())
        XCTAssertEqual(trail.stepForward()?.destination, note)
        XCTAssertEqual(trail.stepForward()?.destination, idea)
    }

    /// The deep-dive afternoon: hopping topic ↔ session over and over must
    /// not bury history under alternating duplicates — Back visits each
    /// session once, then leaves the deep dive.
    func testDeepDiveSessionHopsNeverCircle() {
        let trail = NavigationTrail()
        let thinkspace = sidebar("ts")
        let topic = focus(10, .deepDive)
        let session1 = focus(11, .inquirySession)
        let session2 = focus(12, .inquirySession)

        arrive(trail, thinkspace)
        arrive(trail, topic)
        arrive(trail, session1)
        arrive(trail, topic)      // close session → reopens topic
        arrive(trail, session2)
        arrive(trail, topic)

        XCTAssertEqual(
            backDestinations(trail),
            [session2, session1, thinkspace],
            "Back walks distinct places in recency order, no topic/session ping-pong"
        )
    }

    func testReturningToAPlaceHoistsItInsteadOfDuplicating() {
        let trail = NavigationTrail()
        let a = sidebar("a")
        let b = focus(1, .note)
        arrive(trail, a)
        arrive(trail, b)
        arrive(trail, a)
        arrive(trail, b)

        XCTAssertEqual(backDestinations(trail), [a])
        XCTAssertEqual(trail.current?.destination, b)
    }

    func testFolderInAndOutLeavesSingleMoments() {
        let trail = NavigationTrail()
        let root = sidebar("ts")
        let folderID = UUID()
        let folder = NavigationTrail.Moment.Destination.libraryFolder(thinkspaceId: "ts", folderID: folderID)
        arrive(trail, root)
        arrive(trail, folder)
        arrive(trail, root)
        arrive(trail, folder)
        arrive(trail, root)

        XCTAssertEqual(backDestinations(trail), [folder])
    }

    func testForwardStackSurvivesBackWalk() {
        let trail = NavigationTrail()
        let a = sidebar("a")
        let b = focus(1, .note)
        let c = focus(2, .idea)
        arrive(trail, a)
        arrive(trail, b)
        arrive(trail, c)

        _ = trail.stepBack()
        _ = trail.stepBack()
        XCTAssertTrue(trail.canGoForward)
        XCTAssertEqual(trail.stepForward()?.destination, b)
        XCTAssertEqual(trail.stepForward()?.destination, c)
    }

    func testArrivalDuringJumpApplicationIsNotRecorded() {
        let trail = NavigationTrail()
        let a = sidebar("a")
        let b = focus(1, .note)
        arrive(trail, a)
        arrive(trail, b)

        trail.applyingJump {
            arrive(trail, sidebar("side-effect"))
        }
        XCTAssertEqual(trail.current?.destination, b)
        XCTAssertEqual(backDestinations(trail), [a])
    }
}
