import XCTest
@testable import CosmoOS

final class UnifiedWritingEngineCostTests: XCTestCase {
    func testApplyBlockBudgetsLeavesBlock1Untouched() {
        let longBlock1 = String(repeating: "A", count: 40_000)
        let adjusted = UnifiedWritingEngine.applyBlockBudgets(
            block1: longBlock1,
            block2: "client profile",
            block2MaxChars: 100
        )

        XCTAssertEqual(adjusted.block1, longBlock1)
        XCTAssertEqual(adjusted.block2, "client profile")
    }

    func testComposeSystemBlocksCachesStableBlocksOnly() {
        let blocks = UnifiedWritingEngine.composeSystemBlocks(
            block1: "methodology",
            block2: "client",
            stableBlock3: "swipes",
            dynamicBlock3: "draft",
            ttl: "1h"
        )

        XCTAssertEqual(blocks.map(\.label), ["Block 1", "Block 2", "Block 3A", "Block 3B"])
        XCTAssertEqual(blocks.map(\.cacheControl), [true, true, true, false])
        XCTAssertEqual(blocks.prefix(3).compactMap { $0.ttl }, ["1h", "1h", "1h"])
        XCTAssertNil(blocks.last?.ttl)
    }

    func testWritingContentFormatUsesExactSwipeFamilies() {
        XCTAssertEqual(WritingContentFormat.instagramCarousel.swipeFormatFamily, Set([.carousel, .thread]))
        XCTAssertEqual(WritingContentFormat.instagramStory.swipeFormatFamily, Set([.carousel]))
        XCTAssertEqual(WritingContentFormat.twitterThread.swipeFormatFamily, Set([.carousel, .thread]))
        XCTAssertEqual(WritingContentFormat.twitterSingle.swipeFormatFamily, Set([.tweet]))
        XCTAssertEqual(WritingContentFormat.linkedinPost.swipeFormatFamily, Set([.post]))
        XCTAssertEqual(WritingContentFormat.staticPost.swipeFormatFamily, Set([.post]))
        XCTAssertEqual(WritingContentFormat.youtubeLongForm.swipeFormatFamily, Set([.youtube]))
        XCTAssertEqual(WritingContentFormat.newsletter.swipeFormatFamily, Set([.newsletter]))
        XCTAssertEqual(
            WritingContentFormat.instagramReel.swipeFormatFamily,
            Set([.reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA])
        )
        XCTAssertEqual(WritingContentFormat.youtubeShort.swipeFormatFamily, WritingContentFormat.instagramReel.swipeFormatFamily)
        XCTAssertEqual(WritingContentFormat.tiktokScript.swipeFormatFamily, WritingContentFormat.instagramReel.swipeFormatFamily)
    }

    func testFilterSameTypeLibrarySwipesExcludesCrossTypeAndUnknown() {
        let carousel = makeSwipe(title: "Carousel", format: .carousel)
        let thread = makeSwipe(title: "Thread", format: .thread)
        let reel = makeSwipe(title: "Reel", format: .reel)
        let unknown = makeSwipe(title: "Unknown", format: nil)

        let filtered = UnifiedWritingEngine.filterSameTypeLibrarySwipes(
            [carousel, thread, reel, unknown],
            targetFormat: .instagramCarousel
        )

        XCTAssertEqual(filtered.compactMap(\.title), ["Carousel", "Thread"])
    }

    func testWritingContextAssemblerFiltersSameTypeSwipesForLayer3() {
        let carousel = makeSwipe(title: "Carousel", format: .carousel)
        let tweet = makeSwipe(title: "Tweet", format: .tweet)
        let unknown = makeSwipe(title: "Unknown", format: nil)

        let filtered = WritingContextAssembler.filterSameTypeSwipesForLayer3(
            [carousel, tweet, unknown, carousel],
            targetFormat: .instagramCarousel
        )

        XCTAssertEqual(filtered.compactMap(\.title), ["Carousel"])
    }

    func testWritingContextAssemblerBuildsCacheableMegaContextBlocks() {
        let blocks = WritingContextAssembler.makeCachedBlocks(
            layer1: "methodology",
            layer2: "client",
            layer3: "swipes",
            layer4: "knowledge"
        )

        XCTAssertEqual(blocks.map(\.label), ["Layer 1", "Layer 2", "Layer 3", "Layer 4"])
        XCTAssertTrue(blocks.allSatisfy { $0.cacheControl })
        XCTAssertEqual(blocks.compactMap { $0.ttl }, ["1h", "1h", "1h", "1h"])
    }

    func testBuildAPIMessagesCompactsOlderWriteDraftHistory() {
        let largeDraftPayload = String(repeating: "draft-body-", count: 400)
        let toolCall = WritingToolCall(
            id: "tool_1",
            toolName: "write_draft",
            parameters: #"{"body":"\#(largeDraftPayload)"}"#,
            status: .completed
        )
        let toolResult = WritingToolResult(
            toolCallId: "tool_1",
            content: "Draft written."
        )

        let messages: [WritingMessage] = [
            WritingMessage(role: .assistant, content: "", toolCalls: [toolCall]),
            WritingMessage(role: .toolResult, content: "Draft written.", toolResults: [toolResult]),
            WritingMessage(role: .user, content: "User 1"),
            WritingMessage(role: .assistant, content: "Assistant 1"),
            WritingMessage(role: .user, content: "User 2"),
            WritingMessage(role: .assistant, content: "Assistant 2"),
            WritingMessage(role: .user, content: "User 3"),
            WritingMessage(role: .assistant, content: "Assistant 3")
        ]

        let apiMessages = UnifiedWritingEngine.buildAPIMessages(from: messages)
        let assistantContents = apiMessages.compactMap { message -> String? in
            guard message["role"] as? String == "assistant" else { return nil }
            return message["content"] as? String
        }

        XCTAssertFalse(apiMessages.contains { $0["tool_calls"] != nil })
        XCTAssertFalse(apiMessages.contains { ($0["tool_call_id"] as? String) == "tool_1" })
        XCTAssertTrue(
            assistantContents.contains {
                $0.contains("Earlier tool actions already applied to session state: write_draft")
            }
        )
    }

    func testFormatFilterMatchingUsesSwipeContentFormatFamilies() {
        XCTAssertEqual(WritingContentFormat.matchingSwipeFormats(for: "carousel") ?? [], Set([.carousel]))
        XCTAssertEqual(WritingContentFormat.matchingSwipeFormats(for: "thread") ?? [], Set([.thread]))
        XCTAssertEqual(WritingContentFormat.matchingSwipeFormats(for: "tweet") ?? [], Set([.tweet]))
        XCTAssertEqual(WritingContentFormat.matchingSwipeFormats(for: "linkedin post") ?? [], Set([.post]))
        XCTAssertEqual(WritingContentFormat.matchingSwipeFormats(for: "newsletter") ?? [], Set([.newsletter]))
        XCTAssertEqual(
            WritingContentFormat.matchingSwipeFormats(for: "reel") ?? [],
            Set([.reel, .voiceoverReel, .oneSliderReel, .multiSliderReel, .twoStepCTA])
        )
    }

    func testClassifyLoopResponseAcceptsShortBlankFinishTextAsFinal() {
        let response = makeToolUseResponse(text: "Draft complete.", stopReason: nil, completionTokens: 18)

        let disposition = UnifiedWritingEngine.classifyLoopResponse(
            response: response,
            cleanedText: response.textContent,
            emptyNoToolResponseCount: 0
        )

        XCTAssertEqual(disposition.decision, .acceptFinal)
        XCTAssertEqual(disposition.assistantText, "Draft complete.")
    }

    func testClassifyLoopResponseAcceptsTruncatedTextWithoutRetry() {
        let response = makeToolUseResponse(text: "Partial draft", stopReason: "length", completionTokens: 42)

        let disposition = UnifiedWritingEngine.classifyLoopResponse(
            response: response,
            cleanedText: response.textContent,
            emptyNoToolResponseCount: 0
        )

        XCTAssertEqual(disposition.decision, .acceptFinal)
        XCTAssertTrue(disposition.assistantText.contains("Partial draft"))
        XCTAssertTrue(disposition.assistantText.contains("continue"))
    }

    func testClassifyLoopResponseRetriesThenAbortsEmptyNoToolResponses() {
        let response = makeToolUseResponse(text: "", stopReason: nil, completionTokens: 0)

        let firstDisposition = UnifiedWritingEngine.classifyLoopResponse(
            response: response,
            cleanedText: response.textContent,
            emptyNoToolResponseCount: 0
        )
        let secondDisposition = UnifiedWritingEngine.classifyLoopResponse(
            response: response,
            cleanedText: response.textContent,
            emptyNoToolResponseCount: 1
        )

        XCTAssertEqual(firstDisposition.decision, .retryTransient)
        XCTAssertEqual(secondDisposition.decision, .abort)
        XCTAssertTrue(secondDisposition.assistantText.contains("burning tokens"))
    }

    func testClassifyLoopResponseAcceptsShortWriteDraftAcknowledgement() {
        let response = makeToolUseResponse(text: "Draft written.", stopReason: "--", completionTokens: 18)

        let disposition = UnifiedWritingEngine.classifyLoopResponse(
            response: response,
            cleanedText: response.textContent,
            emptyNoToolResponseCount: 0
        )

        XCTAssertEqual(disposition.decision, .acceptFinal)
        XCTAssertEqual(disposition.assistantText, "Draft written.")
    }

    func testClassifyLoopResponseUsesExactRetryBudget() {
        let response = makeToolUseResponse(text: "", stopReason: nil, completionTokens: 0)

        let stillRetrying = UnifiedWritingEngine.classifyLoopResponse(
            response: response,
            cleanedText: response.textContent,
            emptyNoToolResponseCount: 1,
            maxTransientRetries: 2
        )
        let exhaustedBudget = UnifiedWritingEngine.classifyLoopResponse(
            response: response,
            cleanedText: response.textContent,
            emptyNoToolResponseCount: 2,
            maxTransientRetries: 2
        )

        XCTAssertEqual(stillRetrying.decision, .retryTransient)
        XCTAssertEqual(exhaustedBudget.decision, .abort)
    }

    private func makeToolUseResponse(
        text: String,
        stopReason: String?,
        completionTokens: Int
    ) -> ClaudeToolUseResponse {
        ClaudeToolUseResponse(
            textContent: text,
            toolCalls: [],
            stopReason: stopReason,
            responseId: "resp_test",
            nativeFinishReason: nil,
            completionTokens: completionTokens
        )
    }

    private func makeSwipe(title: String, format: ContentFormat?) -> Atom {
        var atom = Atom.new(type: .research, title: title, body: "\(title) body")
        atom.isSwipeFile = true
        return atom.withSwipeAnalysis(
            SwipeAnalysis(
                hookText: "Hook",
                hookType: .story,
                hookScore: 8.5,
                analysisVersion: 1,
                isFullyAnalyzed: true,
                swipeContentFormat: format
            )
        )
    }
}
