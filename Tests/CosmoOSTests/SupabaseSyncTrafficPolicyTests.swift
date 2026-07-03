import XCTest
import GRDB
@testable import CosmoOS

final class SupabaseSyncTrafficPolicyTests: XCTestCase {
    func testFetchChangesCanExcludeMacOriginatedRowsBeforeDownload() {
        let queryItems = SupabaseClient.fetchChangesQueryItems(
            since: nil,
            userId: "user-1",
            excludeLocalSource: true
        )

        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "user_id", value: "eq.user-1")))
        XCTAssertTrue(queryItems.contains(SupabaseSyncTrafficPolicy.remoteOnlyQueryItem))
    }

    func testRemoteApplyPolicyKeepsMacAndMissingSourceOut() {
        XCTAssertFalse(SupabaseSyncTrafficPolicy.shouldApplyRemoteChange(source: nil))
        XCTAssertFalse(SupabaseSyncTrafficPolicy.shouldApplyRemoteChange(source: "mac"))
        XCTAssertTrue(SupabaseSyncTrafficPolicy.shouldApplyRemoteChange(source: "cloud"))
        XCTAssertTrue(SupabaseSyncTrafficPolicy.shouldApplyRemoteChange(source: "ios"))
    }

    func testPushPolicyRequiresAuthentication() {
        XCTAssertFalse(SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: false, allowsNetworkSync: true))
        XCTAssertTrue(SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: true, allowsNetworkSync: true))
    }

    /// Tests must NEVER reach the real Supabase project: the local database is
    /// sandboxed, but the keychain session is the developer's real one. This
    /// kill-switch is what keeps test fixtures out of production cloud data —
    /// if it regresses, every test run writes fixture atoms other devices pull.
    func testNetworkSyncIsDisabledInsideTestHost() {
        XCTAssertTrue(ProcessInfo.processInfo.isRunningTests)
        XCTAssertFalse(SupabaseSyncTrafficPolicy.allowsNetworkSync)
        XCTAssertFalse(SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: true))
    }

    /// REGRESSION (July 2026 cloud-rebuild disaster): GRDB stores SQLite
    /// integers as Int64, and `row["col"] as? Int` on the untyped subscript
    /// silently fails — payload builders that used it pushed EVERY local
    /// tombstone to the cloud as `is_deleted = false`, resurrecting months of
    /// deleted atoms on each rebuild, and flattened all block positions to 0.
    /// This pins the typed-subscript reads in cloudSyncPayload.
    func testCanvasCloudPayloadReadsIntegerAndBoolColumnsFromGRDBRow() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE canvas_blocks (
                    id TEXT PRIMARY KEY, uuid TEXT, entity_uuid TEXT,
                    thinkspace_id TEXT, position_x INTEGER, position_y INTEGER,
                    width INTEGER, height INTEGER, z_index INTEGER,
                    is_collapsed INTEGER, is_pinned INTEGER,
                    document_type TEXT, document_id INTEGER, document_uuid TEXT,
                    entity_id INTEGER, entity_type TEXT, entity_title TEXT,
                    zone TEXT, note_content TEXT, is_deleted INTEGER,
                    created_at TEXT, updated_at TEXT, _local_version INTEGER
                )
                """)
            try db.execute(
                sql: """
                INSERT INTO canvas_blocks
                    (id, uuid, entity_uuid, position_x, position_y, z_index, is_deleted, is_pinned, _local_version)
                VALUES ('block-1', 'block-1', 'entity-1', 42, -7, 3, 1, 1, 5)
                """)
        }

        let payload = try queue.read { db -> [String: Any]? in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM canvas_blocks") else { return nil }
            return CanvasBlockRecord.cloudSyncPayload(row: row)
        }

        let unwrapped = try XCTUnwrap(payload)
        XCTAssertEqual(unwrapped["is_deleted"] as? Bool, true, "tombstone flag must survive the Row read — false here resurrects deleted rows in the cloud")
        XCTAssertEqual(unwrapped["position_x"] as? Int, 42)
        XCTAssertEqual(unwrapped["position_y"] as? Int, -7)
        XCTAssertEqual(unwrapped["z_index"] as? Int, 3)
        XCTAssertEqual(unwrapped["is_pinned"] as? Bool, true)
    }

    func testQuotaFailuresStayPendingAndKeepLocalPendingProtection() {
        let resolution = SyncFailurePolicy.resolve(
            currentRetryCount: 2,
            maxRetries: 3,
            error: SupabaseError.updateFailed(statusCode: 402)
        )

        XCTAssertEqual(resolution.status, "pending")
        XCTAssertEqual(resolution.retryCount, 2)
        XCTAssertFalse(resolution.shouldClearLocalPending)
        XCTAssertTrue(resolution.shouldPauseFurtherAttempts)
    }

    func testAuthPolicyFailuresStayPendingAndKeepLocalPendingProtection() {
        let resolution = SyncFailurePolicy.resolve(
            currentRetryCount: 2,
            maxRetries: 3,
            error: SupabaseError.upsertFailed(
                statusCode: 401,
                body: #"{"code":"42501","message":"new row violates row-level security policy for table \"atoms\""}"#
            )
        )

        XCTAssertEqual(resolution.status, "pending")
        XCTAssertEqual(resolution.retryCount, 2)
        XCTAssertFalse(resolution.shouldClearLocalPending)
        XCTAssertTrue(resolution.shouldPauseFurtherAttempts)
    }

    func testNonQuotaFailuresStillFailAfterMaxRetries() {
        let resolution = SyncFailurePolicy.resolve(
            currentRetryCount: 2,
            maxRetries: 3,
            error: SupabaseError.updateFailed(statusCode: 500)
        )

        XCTAssertEqual(resolution.status, "failed")
        XCTAssertEqual(resolution.retryCount, 3)
        XCTAssertTrue(resolution.shouldClearLocalPending)
        XCTAssertFalse(resolution.shouldPauseFurtherAttempts)
    }
}
