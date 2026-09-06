
@main struct OfflineCaptureSyncRegression {
    @MainActor static func main() async throws {
        let client = SupabaseClient(url: CommandLine.arguments[1], key: "local-test-key")
        client.setAuthToken("local-test-token")
        client.setUserId("local-test-user")
        var failures: [String] = []
        func check(_ success: Bool, _ description: String) {
            if !success { failures.append(description); print("FAIL: \(description)") }
        }
        let tables = ["inbox_items", "captured_items", "capture_destinations", "media_attachments", "capture_requests", "seedlings"]
        for table in tables {
            for path in ["immediate", "batch"] {
                let operation = path == "immediate"
                    ? immediateDisposition(table: table, operation: "UPDATE", serverVersion: 0)
                    : batchDisposition(tableName: table, operation: "UPDATE", serverVersion: 0)
                check(operation == .upsert, "\(path) \(table): first upload must create the row after offline edits")
                let uuid = "\(table)-\(path)"
                let payload: [String: Any] = ["uuid": uuid, "rawText": "Latest offline capture", "status": "routed"]
                switch operation {
                case .upsert: try await client.upsert(table: table, data: payload, onConflict: "uuid")
                case .update: try await client.update(table: table, uuid: uuid, data: payload)
                }
                let row = try await client.fetchOne(table: table, uuid: uuid)
                check(row?["rawText"] as? String == "Latest offline capture", "\(path) \(table): reconnect actually stores the capture")
            }
        }
        do {
            try await client.update(table: "inbox_items", uuid: "missing", data: ["rawText": "Must not disappear"])
            check(false, "An update affecting zero cloud rows must not acknowledge a save")
        } catch { }
        // Deleting a record that never uploaded is already satisfied remotely.
        try await client.softDelete(table: "inbox_items", uuid: "never-uploaded-delete")
        // Recovery inserts missing records without overwriting a concurrent
        // edit or resurrecting a tombstone created by the other device.
        try await client.upsert(table: "inbox_items", data: ["uuid": "recovery", "rawText": "Original offline capture"], onConflict: "uuid", preservingExisting: true)
        try await client.update(table: "inbox_items", uuid: "recovery", data: ["rawText": "Newer cloud edit"])
        try await client.upsert(table: "inbox_items", data: ["uuid": "recovery", "rawText": "Stale recovery snapshot"], onConflict: "uuid", preservingExisting: true)
        let preserved = try await client.fetchOne(table: "inbox_items", uuid: "recovery")
        check(preserved?["rawText"] as? String == "Newer cloud edit", "Recovery must preserve a cloud row created while it was checking existence")
        try await client.softDelete(table: "inbox_items", uuid: "recovery")
        try await client.upsert(table: "inbox_items", data: ["uuid": "recovery", "is_deleted": false], onConflict: "uuid", preservingExisting: true)
        let tombstone = try await client.fetchOne(table: "inbox_items", uuid: "recovery")
        check(tombstone?["is_deleted"] as? Bool == true, "Recovery must never resurrect a remote deletion")
        for code in [URLError.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost] {
            let policy = SyncFailurePolicy.resolve(currentRetryCount: 2, maxRetries: 3, error: URLError(code))
            check(policy.status == "pending" && policy.retryCount == 2 && policy.shouldPauseFurtherAttempts,
                  "\(code): losing connectivity must preserve the queued capture and retry budget")
        }
        check(immediateDisposition(table: "inbox_items", operation: "UPDATE", serverVersion: 3) == .update, "Existing cloud captures still use updates")
        guard failures.isEmpty else {
            print("\(failures.count) offline sync regression failures")
            exit(1)
        }
        print("PASS: both push policies preserve six capture domains offline; empty updates are rejected; deletes remain idempotent; connectivity failures stay queued")
    }
}
