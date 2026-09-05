import XCTest
import GRDB
@testable import CosmoOS

@MainActor
final class MediaAttachmentBatchTests: XCTestCase {
    func testBatchMatchesPerCaptureOrderAndExcludesDeletedMedia() async throws {
        let firstID = UUID().uuidString, secondID = UUID().uuidString
        var media = (0..<5).map { index in
            var attachment = MediaAttachment.makeLocal(owner: .capturedItem,
                ownerUUID: index < 3 ? firstID : secondID, kind: .image, localStoragePath: nil)
            attachment.createdAt = "2026-09-05T00:00:0\(index)Z"
            return attachment
        }
        media[1].isDeleted = true
        let fixtures = media
        try await CosmoDatabase.shared.asyncWrite { db in
            for attachment in fixtures { try attachment.insert(db) }
        }
        addTeardownBlock {
            try await CosmoDatabase.shared.asyncWrite { db in
                for attachment in fixtures {
                    try db.execute(sql: "DELETE FROM media_attachments WHERE uuid = ?", arguments: [attachment.uuid])
                }
            }
        }
        let repo = MediaAttachmentRepository.shared
        let batch = try await repo.fetch(capturedItemIds: [firstID, secondID])
        let first = try await repo.fetch(capturedItemId: firstID)
        let second = try await repo.fetch(capturedItemId: secondID)
        XCTAssertEqual(batch.count, 4)
        XCTAssertEqual(batch.filter { $0.capturedItemId == firstID }, first)
        XCTAssertEqual(batch.filter { $0.capturedItemId == secondID }, second)
        let empty = try await repo.fetch(capturedItemIds: [])
        XCTAssertTrue(empty.isEmpty)
    }
}
