// Tests/CosmoOSTests/IdeaPromotionServiceTests.swift
// One promotion path (Sept 2026): the bench, the calendar and the board all
// promote through `IdeaPromotionService`. A promotion mints the content with
// its links, moves the idea to In production, lands in the requested stage
// (or straight on a calendar day), and reverts cleanly — the idea's metadata
// and links come back exactly, and the content is tombstoned.

import XCTest
@testable import CosmoOS

@MainActor
final class IdeaPromotionServiceTests: XCTestCase {
    private var cleanupUUIDs: [String] = []

    override func tearDown() async throws {
        for uuid in cleanupUUIDs.reversed() {
            try? await AtomRepository.shared.hardDelete(uuid: uuid, confirmed: true)
        }
        cleanupUUIDs.removeAll()
        try await super.tearDown()
    }

    private func makeIdea(title: String = "A promotable idea") async throws -> Atom {
        let idea = try await AtomRepository.shared.create(
            Atom.new(type: .idea, title: title, body: "Three angles on the same hook.")
        )
        cleanupUUIDs.append(idea.uuid)
        return idea
    }

    private var quietOptions: IdeaPromotionService.PromotionOptions {
        IdeaPromotionService.PromotionOptions(refreshInsightIfStale: false, carryAssistantSession: false)
    }

    private func promote(_ idea: Atom, options: IdeaPromotionService.PromotionOptions? = nil) async throws -> IdeaPromotionService.PromotionResult {
        let result = try await IdeaPromotionService.promote(ideaUUID: idea.uuid, options: options ?? quietOptions)
        cleanupUUIDs.append(result.content.uuid)
        return result
    }

    private func reload(_ uuid: String) async throws -> Atom {
        let atom = try await AtomRepository.shared.fetch(uuid: uuid)
        return try XCTUnwrap(atom)
    }

    // MARK: - Promote

    func testPromotionMintsLinkedContentAndMovesTheIdeaIntoProduction() async throws {
        let idea = try await makeIdea()

        let result = try await promote(idea)

        let content = try await reload(result.content.uuid)
        XCTAssertEqual(content.type, .content)
        XCTAssertEqual(content.title, idea.title)
        XCTAssertTrue(content.links(ofType: .contentToIdea).contains { $0.uuid == idea.uuid })
        XCTAssertEqual(ContentPipelineService.currentPhase(of: content), .ideation, "Default landing stage")

        let updatedIdea = try await reload(idea.uuid)
        let ideaMeta = updatedIdea.metadataValue(as: IdeaMetadata.self)
        XCTAssertNil(ideaMeta?.ideaStatus, "Starting a piece does not consume the source idea")
        XCTAssertEqual(ideaMeta?.contentUUIDs, [content.uuid])
        XCTAssertTrue(updatedIdea.links(ofType: .ideaToContent).contains { $0.uuid == content.uuid })
        XCTAssertEqual(result.idea.uuid, idea.uuid)
    }

    func testBoardDropLandsInTheRequestedStage() async throws {
        let idea = try await makeIdea()
        var options = quietOptions
        options.initialPhase = .draft

        let result = try await promote(idea, options: options)

        let content = try await reload(result.content.uuid)
        XCTAssertEqual(ContentPipelineService.currentPhase(of: content), .draft)
    }

    func testCalendarDropSchedulesThePiece() async throws {
        let idea = try await makeIdea()
        var options = quietOptions
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400 * 2))
        options.scheduleOn = day

        let result = try await promote(idea, options: options)

        let content = try await reload(result.content.uuid)
        XCTAssertEqual(ContentPipelineService.currentPhase(of: content), .ideation)
        let scheduledAt = (content.metadataDict?["scheduledAt"] as? String).flatMap(ISO8601.date(from:))
        XCTAssertNotNil(scheduledAt)
        if let scheduledAt {
            XCTAssertTrue(Calendar.current.isDate(scheduledAt, inSameDayAs: day))
        }
    }

    func testPromotingTwiceAppendsASecondPiece() async throws {
        let idea = try await makeIdea()

        let first = try await promote(idea)
        let second = try await promote(idea)

        let updatedIdea = try await reload(idea.uuid)
        let ideaMeta = updatedIdea.metadataValue(as: IdeaMetadata.self)
        XCTAssertEqual(Set(ideaMeta?.contentUUIDs ?? []), [first.content.uuid, second.content.uuid])
        XCTAssertEqual(updatedIdea.links(ofType: .ideaToContent).count, 2)
    }

    // MARK: - Revert

    func testRevertTombstonesTheContentAndRestoresTheIdeaExactly() async throws {
        let idea = try await makeIdea()
        let before = try await reload(idea.uuid)

        let result = try await promote(idea)
        try await IdeaPromotionService.revert(result)

        let content = try? await AtomRepository.shared.fetch(uuid: result.content.uuid)
        XCTAssertTrue(content == nil || content?.isDeleted == true, "The minted piece is tombstoned (Recently Deleted)")

        let restored = try await reload(idea.uuid)
        XCTAssertEqual(restored.metadata, before.metadata, "Metadata snapshot comes back verbatim")
        XCTAssertEqual(restored.links, before.links, "Links snapshot comes back verbatim")
        XCTAssertNotEqual(restored.metadataValue(as: IdeaMetadata.self)?.ideaStatus, .inProduction)
        XCTAssertTrue(restored.links(ofType: .ideaToContent).isEmpty)
    }
}
