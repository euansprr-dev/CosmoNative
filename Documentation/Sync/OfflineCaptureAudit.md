# Offline capture audit — 6 September 2026

An offline capture could be saved locally, then falsely reported as uploaded. This affected inbox items, lane captures, lanes, and attachment records on both platforms.

## Reproduction

1. Create a capture with no network connection. Its server version is zero.
2. Classify, route, edit, or attach media before the first upload. The queue coalesces the create into an update.
3. Reconnect. Previously, capture-domain updates always used PATCH, even if the cloud record had never been inserted.
4. PostgREST can return a successful HTTP response for a PATCH affecting zero rows. The clients accepted that response, marked the queue entry synced, and cleared the local pending flag.

The Mac database retained four receipts matching this sequence around the user's reported time on 5 September. The corresponding capture contents remain in the local database. Their presence in the live cloud could not be independently checked because the app's non-interactive credentials were not available to the diagnostic. A consistent read-only database snapshot was saved before this investigation; no production rows were edited during testing.

## Changes

- Every domain selects upsert when its server version is zero, including coalesced updates.
- Updates request and check the saved record UUID. A zero-row response remains a failed upload. Deleting an already-absent record stays idempotent.
- Connectivity errors, rate limits, and temporary server failures pause delivery without consuming a record's permanent-failure retry budget.
- Capture-domain repositories save their record, pending flag, and latest upload payload in one database transaction. Queue failures roll back the save. Generated capture IDs are collected before queue insertion.
- Delayed tracking callbacks reload the current row, so stale snapshots cannot be labelled with a newer version.
- Capture uploads use the queued uploader; concurrent flush requests are coalesced. Failure bookkeeping is limited to the attempted version.
- Startup/delivery heals previously saved but unqueued capture records.
- A one-time recovery checks false-success receipts against the cloud. It uses the current local record and inserts only when missing. Server-side ignore-on-conflict preserves existing cloud edits and tombstones. Failed recovery retains its receipts and retries.
- The Mac pending count includes uploads awaiting retry or review, rather than subtracting attempts as though they all succeeded.

## Verification

`python3 scripts/verify_offline_capture_sync.py` compiles the production Mac REST client and write policies against a local mock cloud. It reproduced 29 failures before the fixes and passes afterwards, including missing-row acknowledgements, first uploads across six domains, outage retries, and recovery preserving newer cloud records and deletions.

The same harness accepts `--ios-core /path/to/CosmoCoreKit` to exercise the iOS client. It uses fixture credentials and loopback networking only.

The iOS test suites `OfflineCaptureSyncTests`, `OfflineCaptureDurabilityTests`, `CaptureOutboxRecoveryTests`, and `InboxCaptureServiceTests` cover routing, atomic rollback, unqueued-record repair, latest-payload preservation, and photo ownership. They run with temporary databases and production sync disabled.

Recovery of actual cloud records occurs when the updated app next runs an authenticated online sync. Building and testing do not perform that recovery or establish that the live cloud has been repaired.
