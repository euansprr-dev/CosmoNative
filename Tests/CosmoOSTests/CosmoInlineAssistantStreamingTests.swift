// CosmoOS/Tests/CosmoOSTests/CosmoInlineAssistantStreamingTests.swift
// Streaming lands in the store's observable buffer (coalesced), never in the
// published message array per delta; finalize and stop settle the content.

import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineAssistantStreamingTests: XCTestCase {
    func testFirstDeltaCreatesAnEmptyMessageAndFillsTheBuffer() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)

        store.receivePaneAnswerDelta("Hel")

        XCTAssertEqual(store.paneMessages.count, 1)
        XCTAssertEqual(store.paneMessages.first?.role, .assistant)
        XCTAssertEqual(store.paneMessages.first?.content, "")
        XCTAssertTrue(store.isStreamingMessage(store.paneMessages[0].id))
        XCTAssertEqual(store.streamingAnswer.messageID, store.paneMessages[0].id)
        XCTAssertEqual(store.streamingAnswer.text, "Hel")
        XCTAssertEqual(store.phase, .drafting)
    }

    func testLaterDeltasCoalesceUntilFlushed() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receivePaneAnswerDelta("Hel")
        let revisionAfterFirst = store.streamingAnswer.revision

        store.receivePaneAnswerDelta("lo ")
        store.receivePaneAnswerDelta("world")

        // Nothing landed yet — the message array was not touched either.
        XCTAssertEqual(store.streamingAnswer.text, "Hel")
        XCTAssertEqual(store.streamingAnswer.revision, revisionAfterFirst)
        XCTAssertEqual(store.streamedAnswerText, "Hello world")
        XCTAssertEqual(store.paneMessages.first?.content, "")

        store.flushPendingStreamDelta()

        XCTAssertEqual(store.streamingAnswer.text, "Hello world")
        XCTAssertEqual(store.streamingAnswer.revision, revisionAfterFirst + 1)
    }

    func testFlushTimerLandsBufferedDeltas() async throws {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receivePaneAnswerDelta("a")
        store.receivePaneAnswerDelta("b")

        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(store.streamingAnswer.text, "ab")
    }

    func testFinalizeWritesAuthoritativeContentAndClosesTheBuffer() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receivePaneAnswerDelta("Hel")
        store.receivePaneAnswerDelta("lo")

        store.receivePaneAnswer(title: nil, answer: "Hello, **world**", route: .answer)

        XCTAssertEqual(store.paneMessages.count, 1)
        XCTAssertEqual(store.paneMessages.first?.content, "Hello, **world**")
        XCTAssertFalse(store.streamingAnswer.isActive)
        XCTAssertEqual(store.streamingAnswer.text, "")
        XCTAssertEqual(store.streamedAnswerText, "")
        XCTAssertFalse(store.isStreamingMessage(store.paneMessages[0].id))
    }

    func testFinalizeWithTitleInsertsSectionLabelBeforeTheStreamedMessage() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receivePaneAnswerDelta("Hel")

        store.receivePaneAnswer(title: "Hook review", answer: "Hello", route: .answer)

        XCTAssertEqual(store.paneMessages.map(\.role), [.system, .assistant])
        XCTAssertEqual(store.paneMessages.last?.content, "Hello")
        XCTAssertFalse(store.streamingAnswer.isActive)
    }

    func testUnchangedPhaseDoesNotRepublishOnEveryDelta() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receivePaneAnswerDelta("a")
        var publishes = 0
        let cancellable = store.objectWillChange.sink { _ in publishes += 1 }
        defer { cancellable.cancel() }

        store.receivePaneAnswerDelta("b")
        store.receivePaneAnswerDelta("c")
        store.flushPendingStreamDelta()

        XCTAssertEqual(publishes, 0, "streaming deltas must not publish the store")
    }
}
