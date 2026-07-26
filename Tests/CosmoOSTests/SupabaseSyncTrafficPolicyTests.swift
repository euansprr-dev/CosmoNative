import XCTest
import GRDB
import Auth
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
            error: SupabaseError.updateFailed(statusCode: 402, body: "")
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

    // REGRESSION (July 2026 silent sign-out): refreshSessionIfNeeded treated ANY
    // refresh error — including a network blip on wake — as "session truly
    // expired" and wiped the keychain auth. From then on every push bailed at
    // the auth guard with retry_count 0 and no error recorded, the sync queue
    // accumulated for hours, and other devices drifted until a manual
    // re-sign-in. Only server-rejected sessions may tear auth down.

    private func apiAuthError(code: Auth.ErrorCode) -> Error {
        Auth.AuthError.api(
            message: "rejected",
            errorCode: code,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(
                url: URL(string: "https://example.supabase.co/auth/v1/token")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func testTransientRefreshFailuresNeverTearDownTheSession() {
        XCTAssertFalse(SupabaseSessionRefreshPolicy.isTerminalAuthError(URLError(.notConnectedToInternet)))
        XCTAssertFalse(SupabaseSessionRefreshPolicy.isTerminalAuthError(URLError(.timedOut)))
        XCTAssertFalse(SupabaseSessionRefreshPolicy.isTerminalAuthError(URLError(.cannotFindHost)))
        // Server-side trouble that is not a verdict on the session:
        XCTAssertFalse(SupabaseSessionRefreshPolicy.isTerminalAuthError(apiAuthError(code: .unexpectedFailure)))
        XCTAssertFalse(SupabaseSessionRefreshPolicy.isTerminalAuthError(apiAuthError(code: ErrorCode("over_request_rate_limit"))))
        // Unknown/unclassifiable errors default to keeping the session (fail-safe).
        XCTAssertFalse(SupabaseSessionRefreshPolicy.isTerminalAuthError(SyncError.networkError))
    }

    func testServerRejectedSessionsAreTerminal() {
        XCTAssertTrue(SupabaseSessionRefreshPolicy.isTerminalAuthError(Auth.AuthError.sessionMissing))
        XCTAssertTrue(SupabaseSessionRefreshPolicy.isTerminalAuthError(apiAuthError(code: .sessionExpired)))
        XCTAssertTrue(SupabaseSessionRefreshPolicy.isTerminalAuthError(apiAuthError(code: .sessionNotFound)))
        XCTAssertTrue(SupabaseSessionRefreshPolicy.isTerminalAuthError(apiAuthError(code: .refreshTokenNotFound)))
        XCTAssertTrue(SupabaseSessionRefreshPolicy.isTerminalAuthError(apiAuthError(code: .refreshTokenAlreadyUsed)))
    }

    /// The app's own `AuthError` enum shadows the SDK's — casting to the wrong
    /// one made every SDK error look non-auth. Pins that the app-level type is
    /// (correctly) not treated as a terminal session error.
    func testAppLevelAuthErrorTypeIsNotMistakenForSDKError() {
        XCTAssertFalse(SupabaseSessionRefreshPolicy.isTerminalAuthError(CosmoOS.AuthError.sessionExpired))
    }

    func testNonQuotaFailuresStillFailAfterMaxRetries() {
        let resolution = SyncFailurePolicy.resolve(
            currentRetryCount: 2,
            maxRetries: 3,
            error: SupabaseError.updateFailed(statusCode: 500, body: "")
        )

        XCTAssertEqual(resolution.status, "failed")
        XCTAssertEqual(resolution.retryCount, 3)
        XCTAssertTrue(resolution.shouldClearLocalPending)
        XCTAssertFalse(resolution.shouldPauseFurtherAttempts)
    }

    // MARK: - Orphaned pending-shield reconciliation

    // REGRESSION (July 2026): `_local_pending` (the inbound shield in
    // applyRemoteChange) and `sync_queue` (the outbound push driver) are separate
    // stores. ~20 raw-SQL write paths + the synchronous close-save escort set
    // `_local_pending = 1` without an enqueue, leaving rows FROZEN in both
    // directions — the pusher never sees them, and the shield blocks every
    // inbound remote change. 136 atoms were stuck this way on the reporter's Mac.

    private func makeAtomsAndQueueSchema() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE atoms (
                    id INTEGER PRIMARY KEY, uuid TEXT, type TEXT, title TEXT, body TEXT,
                    structured TEXT, metadata TEXT, links TEXT,
                    created_at TEXT, updated_at TEXT, is_deleted INTEGER DEFAULT 0,
                    _local_version INTEGER DEFAULT 1, _server_version INTEGER DEFAULT 0,
                    _sync_version INTEGER DEFAULT 0, _local_pending INTEGER DEFAULT 0
                )
                """)
            try db.execute(sql: """
                CREATE TABLE sync_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT, table_name TEXT,
                    row_id INTEGER, operation TEXT, data TEXT, local_version INTEGER,
                    created_at INTEGER DEFAULT 0, status TEXT, retry_count INTEGER DEFAULT 0,
                    error_message TEXT, synced_at TEXT
                )
                """)
        }
        return queue
    }

    func testReconcilerReEnqueuesLocalAheadOrphanAndClearsStaleShield() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            // (a) local-ahead orphan → must be re-enqueued (stranded local edit).
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'AHEAD', 'task', 'Repurpose best posts', 0, 7, 2, 1)
                """)
            // (b) server-ahead orphan → shield is stale; clear it so pulls apply.
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (2, 'BEHIND', 'research', 'Content Physics', 0, 2, 15, 1)
                """)
            // (c) healthy: pending WITH a queue row → left untouched (no dup).
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (3, 'QUEUED', 'note', 'Has queue row', 0, 4, 3, 1)
                """)
            try db.execute(sql: "INSERT INTO sync_queue (uuid, table_name, operation, local_version, status) VALUES ('QUEUED', 'atoms', 'UPDATE', 4, 'pending')")
            // (d) not pending at all → ignored entirely.
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (4, 'CLEAN', 'note', 'Synced', 0, 5, 5, 0)
                """)
        }

        let outcome = try queue.write { db in
            try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db)
        }

        XCTAssertEqual(outcome.requeued, 1, "only the local-ahead orphan is re-enqueued")
        XCTAssertEqual(outcome.cleared, 1, "only the server-ahead stale shield is cleared")

        try queue.read { db in
            // AHEAD: new pending queue row carrying the current local_version + payload.
            let ahead = try Row.fetchOne(db, sql: "SELECT * FROM sync_queue WHERE uuid = 'AHEAD'")
            let unwrapped = try XCTUnwrap(ahead)
            XCTAssertEqual(unwrapped["status"] as String?, "pending")
            XCTAssertEqual(unwrapped["operation"] as String?, "UPDATE")
            XCTAssertEqual(unwrapped["local_version"] as Int?, 7)
            let payload = try XCTUnwrap((unwrapped["data"] as String?).flatMap { $0.data(using: .utf8) })
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
            XCTAssertEqual(json["title"] as? String, "Repurpose best posts")
            XCTAssertEqual(json["_local_version"] as? Int, 7)

            // AHEAD keeps its shield (drops only after the push lands).
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT _local_pending FROM atoms WHERE uuid = 'AHEAD'"), 1)
            // BEHIND: shield cleared, and NOT re-enqueued (never clobber newer cloud).
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT _local_pending FROM atoms WHERE uuid = 'BEHIND'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'BEHIND'"), 0)
            // QUEUED: no duplicate row created.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'QUEUED'"), 1)
        }
    }

    // REGRESSION (July 2026): a conflict auto-merge (ConflictResolver.handleConflict)
    // leaves the merged row local-ahead with the shield DOWN. The old healer
    // required _local_pending = 1, so the merged local-wins content never
    // re-pushed and devices silently diverged.
    func testReconcilerReEnqueuesLocalAheadRowEvenWithShieldDown() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'MERGED', 'note', 'Conflict-merged content', 0, 6, 4, 0)
                """)
        }

        let outcome = try queue.write { db in
            try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db)
        }

        XCTAssertEqual(outcome.requeued, 1, "local-ahead rows must upload even when the shield is down")
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'MERGED' AND status = 'pending'"), 1)
        }
    }

    func testReconcilerNeverDuplicatesAFailedQueueRow() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'FAILED', 'task', 'Push failed earlier', 0, 8, 3, 1)
                """)
            // requeueStaleFailedPushes owns this row's retry cadence.
            try db.execute(sql: "INSERT INTO sync_queue (uuid, table_name, operation, local_version, status) VALUES ('FAILED', 'atoms', 'UPDATE', 8, 'failed')")
        }

        let outcome = try queue.write { db in
            try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db)
        }

        XCTAssertEqual(outcome.requeued, 0, "failed rows already have a retry owner — no duplicate enqueue")
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'FAILED'"), 1)
        }
    }

    // MARK: - Explicit resurrection gate (restoredAt wire contract, shared with iOS)

    func testExplicitRestoreRequiresMarkerStrictlyNewerThanTombstone() {
        let tombstonedAt = "2026-07-10T08:00:00Z"

        // Marker newer than the tombstone → deliberate restore, accepted.
        XCTAssertTrue(SyncEngine.remoteCarriesExplicitRestore(
            data: ["metadata": "{\"restoredAt\":\"2026-07-11T09:00:00Z\"}"],
            localTombstoneUpdatedAt: tombstonedAt
        ))

        // Marker older than a re-delete → blocked.
        XCTAssertFalse(SyncEngine.remoteCarriesExplicitRestore(
            data: ["metadata": "{\"restoredAt\":\"2026-07-09T09:00:00Z\"}"],
            localTombstoneUpdatedAt: tombstonedAt
        ))

        // No marker (stale mirror re-pushing an old live row) → blocked.
        XCTAssertFalse(SyncEngine.remoteCarriesExplicitRestore(
            data: ["metadata": "{\"other\":true}"],
            localTombstoneUpdatedAt: tombstonedAt
        ))

        // JSONB dictionary shape (pre-Postgres-conversion path) → accepted.
        XCTAssertTrue(SyncEngine.remoteCarriesExplicitRestore(
            data: ["metadata": ["restoredAt": "2026-07-11T09:00:00Z"]],
            localTombstoneUpdatedAt: tombstonedAt
        ))

        // Unparseable/missing tombstone timestamp fails CLOSED.
        XCTAssertFalse(SyncEngine.remoteCarriesExplicitRestore(
            data: ["metadata": "{\"restoredAt\":\"2026-07-11T09:00:00Z\"}"],
            localTombstoneUpdatedAt: nil
        ))
        XCTAssertFalse(SyncEngine.remoteCarriesExplicitRestore(
            data: ["metadata": "{\"restoredAt\":\"not-a-date\"}"],
            localTombstoneUpdatedAt: tombstonedAt
        ))
    }

    func testRestoreStampMergesMarkerWithoutDestroyingMetadata() throws {
        // Existing metadata keeps its keys and gains the marker.
        let stamped = try XCTUnwrap(AtomRepository.metadataStampingRestoredAt(
            "{\"noteStyle\":\"paper\"}", restoredAt: "2026-07-15T04:00:00Z"
        ))
        let dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(stamped.utf8)) as? [String: Any])
        XCTAssertEqual(dict["noteStyle"] as? String, "paper")
        XCTAssertEqual(dict["restoredAt"] as? String, "2026-07-15T04:00:00Z")

        // Empty/absent metadata becomes a fresh object with the marker.
        let fresh = try XCTUnwrap(AtomRepository.metadataStampingRestoredAt(nil, restoredAt: "2026-07-15T04:00:00Z"))
        XCTAssertTrue(fresh.contains("restoredAt"))

        // Unparseable metadata → nil (caller keeps the original column).
        XCTAssertNil(AtomRepository.metadataStampingRestoredAt("not json", restoredAt: "2026-07-15T04:00:00Z"))
    }

    func testReconcilerIsIdempotentAcrossRepeatedPasses() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'AHEAD', 'task', 'Stuck', 0, 7, 2, 1)
                """)
        }

        let first = try queue.write { db in try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db) }
        let second = try queue.write { db in try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db) }

        XCTAssertEqual(first.requeued, 1)
        XCTAssertEqual(second.requeued, 0, "the row now has a pending queue entry — no duplicate enqueue")
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'AHEAD'"), 1)
        }
    }

    // MARK: - Failed-push dead-lettering

    // REGRESSION (July 2026): pushes that kept failing were either retried
    // forever (pollution pump — a stale row whose cloud copy was tombstoned
    // re-pushed is_deleted = 0 every cool-down) or abandoned SILENTLY with the
    // atom's _local_pending shield still up. applyRemoteChange and
    // ConflictResolver both skip shielded rows, and the orphaned-pending healer
    // skips rows that still have a queue row — so the atom was permanently
    // frozen against ALL inbound remote updates. Dead-lettering ends the retry
    // loop, keeps the payload, lowers the shield, and surfaces the loss.

    private let sevenDaysAgoMs = Int64((Date().timeIntervalSince1970 - 7 * 86_400) * 1000)

    func testAbandonLowersShieldAndKeepsDeadLetterPayload() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'FROZEN', 'note', 'Edit that never uploaded', 0, 8, 3, 1)
                """)
            try db.execute(sql: """
                INSERT INTO sync_queue (uuid, table_name, operation, data, local_version, created_at, status, error_message)
                VALUES ('FROZEN', 'atoms', 'UPDATE', '{"title":"Edit that never uploaded"}', 8, 1000, 'failed', 'RLS violation')
                """)
        }

        let abandoned = try queue.write { db in
            try SyncQueueReconciler.abandonFailedPushes(db, olderThanMs: sevenDaysAgoMs)
        }

        XCTAssertEqual(abandoned.count, 1)
        XCTAssertEqual(abandoned.first?.uuid, "FROZEN")
        XCTAssertEqual(abandoned.first?.tableName, "atoms")
        XCTAssertEqual(abandoned.first?.localVersion, 8)
        XCTAssertEqual(abandoned.first?.errorMessage, "RLS violation")

        try queue.read { db in
            let row = try XCTUnwrap(try Row.fetchOne(db, sql: "SELECT * FROM sync_queue WHERE uuid = 'FROZEN'"))
            XCTAssertEqual(row["status"] as String?, "abandoned")
            XCTAssertEqual(row["data"] as String?, "{\"title\":\"Edit that never uploaded\"}", "the dead letter is the last copy of the local edit once a remote overwrite lands — it must survive")
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT _local_pending FROM atoms WHERE uuid = 'FROZEN'"), 0,
                "shield must come down or the atom stays frozen against every inbound remote update"
            )
        }
    }

    func testAbandonKeepsShieldWhenANewerLocalEditIsInFlight() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            // Atom edited again (v9) after the v8 push started failing — the
            // newer edit's shield must survive its dead letter.
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'EDITED', 'task', 'Newer edit pending', 0, 9, 3, 1)
                """)
            try db.execute(sql: """
                INSERT INTO sync_queue (uuid, table_name, operation, local_version, created_at, status)
                VALUES ('EDITED', 'atoms', 'UPDATE', 8, 1000, 'failed')
                """)
        }

        let abandoned = try queue.write { db in
            try SyncQueueReconciler.abandonFailedPushes(db, olderThanMs: sevenDaysAgoMs)
        }

        XCTAssertEqual(abandoned.count, 1)
        try queue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM sync_queue WHERE uuid = 'EDITED'"), "abandoned")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT _local_pending FROM atoms WHERE uuid = 'EDITED'"), 1)
        }
    }

    func testAbandonLeavesFreshFailedRowsForRetry() throws {
        let queue = try makeAtomsAndQueueSchema()
        let recent = Int64(Date().timeIntervalSince1970 * 1000)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'RECENT', 'note', 'Still retrying', 0, 4, 1, 1)
                """)
            try db.execute(
                sql: "INSERT INTO sync_queue (uuid, table_name, operation, local_version, created_at, status) VALUES ('RECENT', 'atoms', 'UPDATE', 4, ?, 'failed')",
                arguments: [recent]
            )
        }

        let abandoned = try queue.write { db in
            try SyncQueueReconciler.abandonFailedPushes(db, olderThanMs: sevenDaysAgoMs)
        }

        XCTAssertTrue(abandoned.isEmpty)
        try queue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM sync_queue WHERE uuid = 'RECENT'"), "failed", "fresh failures stay owned by the slow-cadence retry")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT _local_pending FROM atoms WHERE uuid = 'RECENT'"), 1)
        }
    }

    func testAbandonSurvivesQueueRowsForCloudOnlyTables() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            // swipe_boards has no local table (cloud-only mirror) — there is no
            // shield to lower, but the row must still dead-letter, not throw.
            try db.execute(sql: """
                INSERT INTO sync_queue (uuid, table_name, operation, local_version, created_at, status)
                VALUES ('BOARD', 'swipe_boards', 'INSERT', 1, 1000, 'failed')
                """)
        }

        let abandoned = try queue.write { db in
            try SyncQueueReconciler.abandonFailedPushes(db, olderThanMs: sevenDaysAgoMs)
        }

        XCTAssertEqual(abandoned.count, 1)
        try queue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM sync_queue WHERE uuid = 'BOARD'"), "abandoned")
        }
    }

    func testReconcilerDoesNotResurrectAbandonedPushAtSameVersion() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            // Post-abandonment state: shield down, still local-ahead, dead
            // letter covers the current version. Re-enqueueing would restart
            // the doomed push loop dead-lettering just ended.
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'DEAD', 'note', 'Abandoned edit', 0, 8, 3, 0)
                """)
            try db.execute(sql: """
                INSERT INTO sync_queue (uuid, table_name, operation, local_version, status)
                VALUES ('DEAD', 'atoms', 'UPDATE', 8, 'abandoned')
                """)
        }

        let outcome = try queue.write { db in try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db) }

        XCTAssertEqual(outcome.requeued, 0, "a dead letter at the current version owns this content — no resurrection")
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'DEAD'"), 1)
        }
    }

    func testReconcilerRetriesWhenALocalEditSupersedesTheDeadLetter() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            // The user edited the atom again (v9) after v8 was dead-lettered —
            // new content deserves a fresh push attempt.
            try db.execute(sql: """
                INSERT INTO atoms (id, uuid, type, title, is_deleted, _local_version, _server_version, _local_pending)
                VALUES (1, 'REVIVED', 'note', 'Edited after abandonment', 0, 9, 3, 1)
                """)
            try db.execute(sql: """
                INSERT INTO sync_queue (uuid, table_name, operation, local_version, status)
                VALUES ('REVIVED', 'atoms', 'UPDATE', 8, 'abandoned')
                """)
        }

        let outcome = try queue.write { db in try SyncQueueReconciler.reconcileOrphanedPendingAtoms(db) }

        XCTAssertEqual(outcome.requeued, 1, "a newer local edit supersedes the dead letter")
        try queue.read { db in
            let pending = try XCTUnwrap(try Row.fetchOne(db, sql: "SELECT * FROM sync_queue WHERE uuid = 'REVIVED' AND status = 'pending'"))
            XCTAssertEqual(pending["local_version"] as Int?, 9)
            // The dead letter itself is untouched until a push SUCCEEDS.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'REVIVED' AND status = 'abandoned'"), 1)
        }
    }

    func testSuccessfulPushClearsSupersededDeadLetters() throws {
        let queue = try makeAtomsAndQueueSchema()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO sync_queue (uuid, table_name, operation, local_version, status) VALUES ('X', 'atoms', 'UPDATE', 5, 'abandoned')")
            try db.execute(sql: "INSERT INTO sync_queue (uuid, table_name, operation, local_version, status) VALUES ('X', 'atoms', 'UPDATE', 9, 'abandoned')")
            try db.execute(sql: "INSERT INTO sync_queue (uuid, table_name, operation, local_version, status) VALUES ('Y', 'atoms', 'UPDATE', 2, 'abandoned')")
        }

        try queue.write { db in
            try SyncQueueReconciler.clearSupersededDeadLetters(db, uuid: "X", table: "atoms", upToVersion: 7)
        }

        try queue.read { db in
            // v5 superseded by the successful v7 push; v9 is NEWER content the
            // cloud still hasn't seen; Y belongs to another row entirely.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'X' AND local_version = 5"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'X' AND local_version = 9"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_queue WHERE uuid = 'Y'"), 1)
        }
    }
}
