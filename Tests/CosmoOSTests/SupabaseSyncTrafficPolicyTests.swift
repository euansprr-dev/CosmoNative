import XCTest
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
        XCTAssertFalse(SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: false))
        XCTAssertTrue(SupabaseSyncTrafficPolicy.shouldAttemptPush(isAuthenticated: true))
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
