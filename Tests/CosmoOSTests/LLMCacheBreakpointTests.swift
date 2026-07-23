// CosmoOS/Tests/CosmoOSTests/LLMCacheBreakpointTests.swift
// The cache-breakpoint contract: every request carries the moving breakpoint
// on the final message, and long conversations ALSO carry a mid-tail anchor
// ~15 blocks from the end — Anthropic's cache walks back at most 20 content
// blocks, so without the anchor a long tool-loop turn misses every prior
// entry and re-writes the whole prefix at 2× instead of reading at 0.1×.

import XCTest
@testable import CosmoOS

final class LLMCacheBreakpointTests: XCTestCase {

    private func userMessage(_ text: String = "hello") -> [String: Any] {
        ["role": "user", "content": text]
    }

    /// A tool-loop pair rendered the way conversationMessages does: an
    /// assistant tool_use block + a user tool_result block.
    private func toolLoopMessages(pairs: Int) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for index in 0..<pairs {
            out.append([
                "role": "assistant",
                "content": [["type": "tool_use", "id": "t\(index)", "name": "recall", "input": [String: Any]()]]
            ])
            out.append([
                "role": "user",
                "content": [["type": "tool_result", "tool_use_id": "t\(index)", "content": "result"]]
            ])
        }
        return out
    }

    private func cacheMarkedBlockIndices(_ messages: [[String: Any]]) -> [Int] {
        var indices: [Int] = []
        var blockIndex = 0
        for message in messages {
            let blocks = message["content"] as? [[String: Any]]
                ?? (message["content"] as? String).map { [["type": "text", "text": $0]] }
                ?? []
            for block in blocks {
                if block["cache_control"] != nil { indices.append(blockIndex) }
                blockIndex += 1
            }
        }
        return indices
    }

    func testShortConversationMarksOnlyFinalMessage() {
        let messages = [userMessage("a"), userMessage("b"), userMessage("c")]
        let marked = AnthropicProvider.markingLastMessageForCache(messages)
        XCTAssertEqual(cacheMarkedBlockIndices(marked), [2])
    }

    func testStringContentConvertsToBlockForm() {
        let marked = AnthropicProvider.markingLastMessageForCache([userMessage()])
        let blocks = marked[0]["content"] as? [[String: Any]]
        XCTAssertEqual(blocks?.count, 1)
        XCTAssertEqual(blocks?[0]["text"] as? String, "hello")
        XCTAssertNotNil(blocks?[0]["cache_control"])
    }

    func testLongToolLoopGainsMidTailAnchor() {
        // 1 user turn + 15 tool pairs = 31 blocks — past the 20-block window.
        let messages = [userMessage()] + toolLoopMessages(pairs: 15)
        let marked = AnthropicProvider.markingLastMessageForCache(messages)
        let indices = cacheMarkedBlockIndices(marked)

        XCTAssertEqual(indices.count, 2, "long conversations carry the anchor + the moving breakpoint")
        XCTAssertEqual(indices.last, 30, "the moving breakpoint stays on the final block")

        // The anchor sits at the first message boundary at or past
        // (total − offset), and within the lookback window of the end —
        // so the final breakpoint can always find it.
        let anchor = indices[0]
        let total = 31
        XCTAssertGreaterThanOrEqual(anchor, total - AnthropicProvider.cacheLookbackWindow)
        XCTAssertLessThan(anchor, total - 1)
        XCTAssertLessThanOrEqual((total - 1) - anchor, AnthropicProvider.cacheLookbackWindow)
    }

    func testAnchorNeverLandsOnFinalMessage() {
        // 21 blocks, all single-block messages: target = 6 → anchor at
        // block 6, final breakpoint at block 20. Never doubled on the end.
        let messages = (0..<21).map { userMessage("m\($0)") }
        let marked = AnthropicProvider.markingLastMessageForCache(messages)
        let indices = cacheMarkedBlockIndices(marked)
        XCTAssertEqual(indices.count, 2)
        XCTAssertEqual(indices.last, 20)
        XCTAssertNotEqual(indices[0], 20)
    }

    func testExactlyTwentyBlocksStaysSingleBreakpoint() {
        let messages = (0..<20).map { userMessage("m\($0)") }
        let marked = AnthropicProvider.markingLastMessageForCache(messages)
        XCTAssertEqual(cacheMarkedBlockIndices(marked).count, 1)
    }
}
