import Foundation
import SwiftUI
import GRDB

/// Only dependencies that affect the two rails. Editing the space's working
/// notes changes its atom, but must not reload every material and inquiry.
struct SpaceHomeDependencyVersion: Equatable, Sendable, FetchableRecord, Decodable {
    let uuid: String
    let updated_at: String
    let _local_version: Int

    static func fetch(_ db: Database, spaceID: String, diveID: String?) throws -> [Self] {
        try fetchAll(db, sql: """
            SELECT uuid, updated_at, _local_version FROM atoms
            WHERE is_deleted = 0 AND (
                uuid IN (SELECT entity_uuid FROM canvas_blocks
                         WHERE thinkspace_id = ? AND document_type = 'home'
                           AND document_id = 0 AND is_deleted = 0)
                OR (type IN ('question', 'inquiry_session') AND
                    CASE WHEN json_valid(metadata) THEN json_extract(metadata, '$.parentDeepDiveUUID') END = ?)
            ) ORDER BY uuid
            """, arguments: [spaceID, diveID])
    }
}

/// Compatibility writer for legacy space documents. New Spaces expose these
/// documents as ordinary notes through SpaceResearchService.
@MainActor enum SpaceHomeModel {
    static let documentKey = "spaceHomeDocument"
    static func persist(_ document: RichDocument, spaceID: String) async throws -> Atom {
        try await CosmoDatabase.shared.asyncWrite { db in
            guard var space = try Atom.filter(Column("uuid") == spaceID).filter(Column("is_deleted") == false).fetchOne(db),
                  space.metadata == nil || space.metadataDict != nil else { throw ContentPipelineError.invalidMetadata }
            let before = space
            space.metadata = RichDocumentMetadataStorage.writeDocument(document, into: space.metadata, key: documentKey)
            space.body = document.plainText
            space.updatedAt = ISO8601.string(from: Date()); space.localVersion += 1
            AtomRevisionWriter.snapshotIfNeeded(db, previous: before, incoming: space, source: .userEdit)
            try space.update(db)
            try db.execute(sql: "UPDATE atoms SET _local_pending = 1 WHERE uuid = ?", arguments: [spaceID])
            return space
        }
    }
}
