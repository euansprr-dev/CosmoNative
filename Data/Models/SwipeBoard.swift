import Foundation
import GRDB

/// A user-defined swipe board (collection). Membership lives on each swipe atom
/// as `ResearchMetadata.swipeBoardIDs`; this record only defines the board itself.
struct SwipeBoard: Codable, Equatable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "swipe_boards"

    var uuid: String
    var name: String
    var icon: String
    var tintToken: String?
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: String
    var updatedAt: String

    var id: String { uuid }
}
