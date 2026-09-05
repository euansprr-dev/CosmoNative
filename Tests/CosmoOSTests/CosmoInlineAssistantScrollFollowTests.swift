// CosmoOS/Tests/CosmoOSTests/CosmoInlineAssistantScrollFollowTests.swift
// Sticky-bottom rules for the pane transcript.

import SwiftUI
import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantScrollFollowTests: XCTestCase {
    typealias Policy = CosmoInlineAssistantScrollFollowPolicy

    func testNearBottomAllowsSlack() {
        XCTAssertTrue(Policy.isNearBottom(visibleMaxY: 1000, contentHeight: 1000))
        XCTAssertTrue(Policy.isNearBottom(visibleMaxY: 960, contentHeight: 1000))
        XCTAssertFalse(Policy.isNearBottom(visibleMaxY: 900, contentHeight: 1000))
        // Short transcripts are always "at the bottom".
        XCTAssertTrue(Policy.isNearBottom(visibleMaxY: 400, contentHeight: 200))
    }

    func testUserSubmitAlwaysFollowsWhileExpanded() {
        XCTAssertTrue(Policy.shouldFollow(trigger: .userSubmitted, isNearBottom: false, isPaneExpanded: true))
        XCTAssertFalse(Policy.shouldFollow(trigger: .userSubmitted, isNearBottom: true, isPaneExpanded: false))
    }

    func testGrowthOnlyFollowsWhenReadingTheLatest() {
        for trigger in [Policy.Trigger.transcriptGrew, .streamingTick, .runStateChanged] {
            XCTAssertTrue(Policy.shouldFollow(trigger: trigger, isNearBottom: true, isPaneExpanded: true))
            XCTAssertFalse(Policy.shouldFollow(trigger: trigger, isNearBottom: false, isPaneExpanded: true), "\(trigger)")
        }
    }

    func testSizeChangeAnchorPinsTheEndOnlyWhileAtTheEnd() {
        XCTAssertEqual(Policy.sizeChangeAnchor(isNearBottom: true), .bottom)
        XCTAssertEqual(Policy.sizeChangeAnchor(isNearBottom: false), .top)
    }

    @MainActor
    func testFollowerHonoursPolicy() {
        let follower = CosmoInlineAssistantScrollFollower()
        var calls: [Bool] = []
        follower.scrollToBottom = { animated in calls.append(animated) }

        follower.isNearBottom = false
        follower.follow(.streamingTick, animated: false)
        XCTAssertTrue(calls.isEmpty)

        follower.follow(.userSubmitted, animated: true)
        XCTAssertEqual(calls, [true])

        follower.isNearBottom = true
        follower.follow(.streamingTick, animated: false)
        XCTAssertEqual(calls, [true, false])

        follower.isPaneExpanded = false
        follower.follow(.userSubmitted, animated: true)
        XCTAssertEqual(calls, [true, false])
    }
}
