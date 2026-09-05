# Persistence audit — 5 September 2026

## What the local data shows

Inspected an online SQLite backup of the live database, leaving user records untouched. The forensic snapshot is `/tmp/cosmo-persistence-audit-20260905.db`.

- SQLite `quick_check` and full `integrity_check`: `ok`; `foreign_key_check`: no violations.
- 3,838 active atoms, including 123 notes, 201 content documents, 33 connections, and 10 sticky-note atoms.
- 15 active sticky placements. All 15 used the legacy canvas-only representation. Four contained text; 11 were empty in both `note_content` and their rich documents. Empty stored values do **not** establish whether a note was intentionally blank or previously overwritten.
- The September 4 and September 5 backups contain no additional text for those currently active stickies. The 11 blank placements also have no nonempty copy in other placements with the same entity UUID, retained sync-queue payloads, or atom revisions.
- No malformed nonempty JSON in active atom metadata, atom structured data, or canvas metadata. Two empty metadata strings belonged to deleted fixture rows.
- All 123 active note bodies agree with their rich-document text (84 exactly, 39 differing only in surrounding whitespace). The eight sticky-note atoms with rich documents agree exactly; two older sticky atoms have no rich document.
- Of 201 content documents, 124 have simple paragraph drafts that agree with the stored body (102 exactly, 22 whitespace-only). Fifty-five structured drafts were excluded from that plain-text comparison; 22 have no rich draft. No mismatches appeared in the compared content records.
- No missing backing atoms for active non-sticky document placements.
- All 1,398 graph edges reference existing atoms. Forty-seven touch tombstoned atoms, which remain available for recovery.
- 172 active agent conversations; 84 inline/window preference archives, all valid JSON, totaling approximately 2.3 MB.
- One existing sync conflict for a task retains its 912-character payload. It was not discarded or force-resolved; it is unrelated to the blank sticky placements.

During validation, the machine ran out of disk space. Inactive generated build folders were removed to make room; user documents and database backups were retained. A full disk is a real save-failure condition, independent of the code defects below.

## Confirmed defects and changes

### Sticky notes and canvas writes

The original `SpatialEngine.saveBlock` rewrote document text and metadata during layout saves. Replaying its original SQL reproduced a committed sentence being overwritten with an empty string from an older canvas value.

- Existing-placement layout saves now leave text, rich metadata, and titles alone. Content changes patch the current database row explicitly.
- Delayed layout saves cannot resurrect tombstoned placements.
- Sticky notes receive the editor's immediate typing callback, including keystrokes that precede rich-document serialization.
- One transaction now saves sticky text, rich document, and atom linkage. Legacy stickies gain an atom on their first edit, preserving the previous content in normal revision history.
- Autosave, leaving the view, and quitting share the same sticky save function. The separate asynchronous writer and duplicate write notifications were removed.
- Successful saves invalidate stale canvas snapshots. Notifications sent after a sticky commit update mounted state without writing the snapshot back to the database.
- The warm atom cache rejects delayed older reads, including lower versions with the same timestamp. Previously, subscriber delivery rejected some stale values while the cache silently retained them for the next mount.
- Space navigation flushes visible drafts before starting the next read. Deferred resize/undo saves capture their card before a space switch can replace the array.
- Sticky and metadata commits raise the local sync-pending shield in the same transaction, covering the interval before the asynchronous queue observer runs.
- Missing rows and malformed canvas metadata raise errors instead of being reported as successful saves.
- Failed sticky commits retain the draft in an atomic recovery file for the next open. A failure to write that recovery file is also reported.
- Reopened note editors reset their editing/closed state. Note raw-SQL writes now participate in revision history, and clearing even a short note preserves the immediately preceding body.
- The editor's close flush no longer treats “already emitted as plain text” as evidence that a keystroke reached the rich document.

### Notes, content, and connections

Reviewed the current content snapshot/freshness gates, note dirty gates and close saves, connection fresh-row merges and close escorts, atom revisions, and sync conflict preservation. Existing protections were retained.

- Note recovery copies are removed only after a successful retry, rather than before it.
- Content chat persistence accepts initially absent metadata and reports write failures.
- Content conversations and generation-history records are no longer truncated during persistence.
- The content chat's lazy list offers an explicit way to reveal earlier messages.
- Failed canvas reads report an error and do not turn failed atom reads into successful empty results.
- SQLite uses `synchronous=FULL` for stronger committed-write durability in WAL mode.

### AI chats

Canvas AI blocks can have no backing atom, but the old transcript writer required one. In addition, several persistence paths discarded old messages solely because a conversation grew longer.

- Canvas and focus AI chats share a database archive keyed by their stable chat UUID, including atomless blocks.
- Atom-backed canvas chats also commit a complete transcript into their existing atom, preserving that sync path and unrelated structured fields. New remote turns merge by message ID; the local archive and atom update are atomic.
- Submitted questions are archived before the AI request begins. Messages from another mounted surface are retained when transcripts merge by message ID.
- Existing legacy transcripts can be imported from atom structured data or retained agent memory when available.
- Inline and window archives move lazily from UserDefaults to SQLite. The legacy preference copies remain recoverable, and SQLite retains the previous distinct archive commit.
- Unreadable archives are not overwritten by a newly initialized empty/partial session.
- Empty agent-conversation saves do not delete prior history; reset and rollback use explicit deletion. Unreadable agent-memory records are preserved on a replacement save.
- Removed automatic chat-archive pruning and destructive conversation folding. Prompt-window limits remain separate from stored history.

The new local archive table is included in database backups. It is local storage; this audit does not certify cross-device synchronization of that table.

## Verification

The original layout overwrite was reproduced using its unmodified SQL. Executing the updated SQL against the same fixture retained the text, metadata, and title.

The focused regression run passed **362 tests with zero failures**. It used a frozen source copy with the 23 selected test files, covering real editor typing followed immediately by quit-flush, repeated canvas loads, deletion, atomic rollback, recovery drafts, history retention, corrupt archives, legacy archive migration, atom-backed chat sync payloads, and the existing note/content/connection/sync suites. Temporary test records were isolated from the live database. Log: `/tmp/cosmo-persistence-focused-tests.log`.

Final Xcode app-build result: failed in the isolated source snapshot because `DashboardTimeTracker.swift` referenced the missing design token `DS.radiusPanel` (lines 28 and 30). The shared working copy has since changed, so this does not establish the current checkout's build result. Full app-build verification remains incomplete; the 362 focused persistence regression tests passed. Build log: `/tmp/cosmo-persistence-isolated-app.log`. The running app was not replaced or restarted.

## Limits

This is a bounded audit and hardening change, not a mathematical guarantee against all data loss. Disk exhaustion, storage failure, forced process termination before a commit, and untested cross-device races remain possible. Text already absent from every available copy cannot be reconstructed reliably. No empty or deleted user record was automatically “repaired” based on guesses.
