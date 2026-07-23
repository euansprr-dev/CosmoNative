import XCTest
@testable import CosmoOS

@MainActor
final class ExplicitLessonCaptureTests: XCTestCase {
    private let explicitLessonMessage = """
    Please save this as a lesson for future reference:

    Never have that 3 beat pattern in sentences like "X. Y. Z.", always use commas, dots, or elipsis. (example: "The VA loan covers 100% of the purchase price. No down payment. No PMI." should be "The VA loan covers 100% of the purchase price so you don't need any downpayment".

    This makes everything MUCH more conversational.
    """

    func testExplicitLessonParserExtractsFullRuleAndEvidence() {
        let request = ExplicitLessonCaptureParser.parse(explicitLessonMessage)

        XCTAssertNotNil(request)
        XCTAssertEqual(
            request?.rule,
            #"Never have that 3 beat pattern in sentences like "X. Y. Z.", always use commas, dots, or elipsis. (example: "The VA loan covers 100% of the purchase price. No down payment. No PMI." should be "The VA loan covers 100% of the purchase price so you don't need any downpayment"."#
        )
        XCTAssertEqual(request?.category, "voice")
        XCTAssertEqual(request?.evidence, "This makes everything MUCH more conversational.")
    }

    func testExplicitLessonParserIgnoresLessonQueries() {
        XCTAssertNil(ExplicitLessonCaptureParser.parse("What lessons have you learned?"))
        XCTAssertNil(ExplicitLessonCaptureParser.parse("show my lessons"))
    }

    func testFlashLiteGuardForcesLessonRequestsToAgentFallback() {
        XCTAssertTrue(FlashLiteRouter.shouldForceAgentFallback(explicitLessonMessage))
        XCTAssertFalse(FlashLiteRouter.shouldForceAgentFallback("Idea: build a calculator app"))
    }
}

@MainActor
final class CommandKSearchTests: XCTestCase {
    func testCaseAndDiacriticInsensitiveMatchingAcrossCommandKSurfaces() {
        let swipe = makeSwipe(
            title: "Cafe Swipe",
            hookText: "How to scale a Café business"
        )
        XCTAssertTrue(CommandKViewModel.matchesSwipeGallerySearch(swipe, query: "CAFÉ"))

        let idea = IdeaGalleryItem(
            id: "idea-1",
            atomUUID: "idea-1",
            entityId: 1,
            title: "Résumé Hook",
            body: "Use a sharp résumé opener",
            status: .spark,
            contentFormat: .carousel,
            platform: nil,
            clientName: "Acme Client",
            clientUUID: nil,
            tags: ["Naïve Bayes"],
            insightScore: 0.8,
            matchingSwipeCount: nil,
            suggestedFramework: nil,
            isPinned: false,
            contentCount: 0,
            createdAt: isoNow,
            updatedAt: isoNow
        )
        XCTAssertTrue(IdeasTab.matchesSearch(idea, query: "resume"))
        XCTAssertTrue(IdeasTab.matchesSearch(idea, query: "NAIVE"))

        var atom = Atom.new(type: .content, title: "Crème Strategy", body: "Roadmap for launch")
        atom.id = 42
        let libraryItem = LibraryItem(atom: atom)
        XCTAssertTrue(LibraryTab.matchesSearch(libraryItem, query: "CREME"))

        let highlight = ReadwiseLibraryHighlight(
            id: 1,
            text: "Build a naïve but useful first draft.",
            note: "Café example",
            location: nil,
            color: nil,
            tags: ["Resumé"],
            bookId: 9,
            highlightedAt: isoNow
        )
        let book = ReadwiseLibraryBook(
            id: 9,
            title: "Deep Work",
            author: "Cal Newport",
            category: .books,
            coverImageUrl: nil,
            sourceUrl: nil,
            numHighlights: 1,
            highlights: [highlight],
            bookTags: []
        )
        XCTAssertTrue(ReadwiseBookStore.matchesSearch(book, query: "NAIVE"))
        XCTAssertTrue(ReadwiseLibraryTab.matchesSearch(highlight, query: "cafe"))
    }

    func testUnifiedSearchPromotesHybridSwipeIntoSwipeCardPayload() {
        let swipe = makeSwipe(title: "Command K Swipe", hookText: "Command K hook")
        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "command k",
            hybridResults: [makeHybridResearchResult(uuid: swipe.atomUUID, title: swipe.title)],
            swipeGalleryItems: [swipe],
            ideaGalleryItems: [],
            readwiseBooks: []
        )

        XCTAssertEqual(output.flatResults.first?.source, .swipes)

        let cardItems = CommandKUnifiedSearchComposer.buildCardItems(
            flatResults: output.flatResults,
            libraryItemsByID: [:],
            swipeItemsByUUID: [swipe.atomUUID: swipe]
        )

        guard case .swipe(let promotedSwipe)? = cardItems.first else {
            return XCTFail("Expected promoted swipe card payload")
        }
        XCTAssertEqual(promotedSwipe.atomUUID, swipe.atomUUID)
    }

    func testUnifiedSearchDeduplicatesSwipeMatchedByHybridAndGallery() {
        let swipe = makeSwipe(title: "Duplicate Swipe", hookText: "Duplicate hook")
        let output = CommandKUnifiedSearchComposer.buildOutput(
            query: "duplicate",
            hybridResults: [makeHybridResearchResult(uuid: swipe.atomUUID, title: swipe.title)],
            swipeGalleryItems: [swipe],
            ideaGalleryItems: [],
            readwiseBooks: []
        )

        let matchingUUIDs = output.flatResults.compactMap(\.atomUUID).filter { $0 == swipe.atomUUID }
        XCTAssertEqual(matchingUUIDs.count, 1)
    }

    func testUnifiedSearchPreloadEnablesSwipePromotionOnFirstBuild() async {
        let swipe = makeSwipe(title: "First Search Swipe", hookText: "First pass swipe")
        let hybrid = [makeHybridResearchResult(uuid: swipe.atomUUID, title: swipe.title)]

        let beforePreload = CommandKUnifiedSearchComposer.buildOutput(
            query: "first search",
            hybridResults: hybrid,
            swipeGalleryItems: [],
            ideaGalleryItems: [],
            readwiseBooks: []
        )
        XCTAssertEqual(beforePreload.flatResults.first?.source, .atoms)

        var loadedSwipes: [SwipeGalleryItem] = []
        await CommandKViewModel.preloadUnifiedSearchSupportData(
            swipeGalleryLoaded: false,
            ideaGalleryLoaded: false,
            loadSwipeGallery: {
                try? await Task.sleep(nanoseconds: 10_000_000)
                loadedSwipes = [swipe]
            },
            loadIdeaGallery: {}
        )

        let afterPreload = CommandKUnifiedSearchComposer.buildOutput(
            query: "first search",
            hybridResults: hybrid,
            swipeGalleryItems: loadedSwipes,
            ideaGalleryItems: [],
            readwiseBooks: []
        )
        XCTAssertEqual(afterPreload.flatResults.first?.source, .swipes)
    }

    private var isoNow: String {
        ISO8601.string(from: Date())
    }

    private func makeSwipe(title: String, hookText: String) -> SwipeGalleryItem {
        SwipeGalleryItem(
            atomUUID: UUID().uuidString,
            title: title,
            hookText: hookText,
            hookScore: 8.2,
            hookType: nil,
            dominantEmotion: nil,
            frameworkType: nil,
            platform: "instagram_reel",
            thumbnailUrl: nil,
            author: "Casey",
            duration: 42,
            createdAt: isoNow,
            isStudied: false,
            entityId: 1,
            primaryNarrative: nil,
            swipeContentFormat: .reel,
            niche: "Marketing",
            creatorName: "Casey",
            clientUUID: nil,
            clientName: nil,
            instagramId: nil
        )
    }

    private func makeHybridResearchResult(uuid: String, title: String) -> RankedResult {
        RankedResult(
            atomUUID: uuid,
            atomType: .research,
            title: title,
            snippet: "Hybrid result snippet",
            semanticWeight: 0.6,
            structuralWeight: 0.4,
            recencyWeight: 0.8,
            usageWeight: 0.2,
            updatedAt: isoNow,
            accessCount: 0
        )
    }
}
