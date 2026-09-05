import XCTest
import GRDB
import AppKit
import SwiftUI
@testable import CosmoOS

@MainActor
final class CanvasPersistenceTests: XCTestCase {
    func testStickySaveCreatesOneAtomPreservesMetadataAndRecordsHistory() async throws {
        let engine = SpatialEngine()
        let block = CanvasBlock.stickyNoteBlock(position: .zero, content: "Original")
        await engine.saveBlock(block)
        defer {
            try? CosmoDatabase.shared.write { db in
                try db.execute(sql: "DELETE FROM canvas_blocks WHERE id = ?", arguments: [block.id])
                try db.execute(sql: "DELETE FROM atom_revisions WHERE atom_uuid = ?", arguments: [block.entityUuid])
                try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [block.entityUuid])
            }
        }
        try engine.updateBlockMetadata(blockID: block.id, patch: ["stickyColor": "blue", "unrelated": "keep"])
        let first = try CosmoDatabase.shared.write { db in
            try CanvasNotePersistence.saveSticky(in: db, blockID: block.id,
                document: .empty, plainText: "Latest keystroke")
        }
        let second = try CosmoDatabase.shared.write { db in
            try CanvasNotePersistence.saveSticky(in: db, blockID: block.id,
                document: RichDocument.migrateLegacy("Latest keystroke"), plainText: "")
        }
        XCTAssertEqual(first.atom.id, second.atom.id)
        XCTAssertEqual(first.atom.body, "Latest keystroke")
        XCTAssertEqual(second.atom.body, "", "An intentional deletion must persist")
        XCTAssertEqual(second.metadata["unrelated"], "keep")
        XCTAssertEqual(second.metadata["stickyColor"], "blue")
        let pending = try CosmoDatabase.shared.read { db in
            try Bool.fetchOne(db, sql: "SELECT _local_pending FROM canvas_blocks WHERE id = ?", arguments: [block.id])
        }
        XCTAssertEqual(pending, true, "The committed draft must be shielded from stale remote changes before enqueueing")
        let oldBody = try CosmoDatabase.shared.read { db in
            try String.fetchOne(db, sql: "SELECT body FROM atom_revisions WHERE atom_uuid = ? ORDER BY id LIMIT 1", arguments: [block.entityUuid])
        }
        XCTAssertEqual(oldBody, "Original")
    }

    func testMissingStickySaveThrowsInsteadOfReportingSuccess() throws {
        XCTAssertThrowsError(try CosmoDatabase.shared.write { db in
            try CanvasNotePersistence.saveSticky(in: db, blockID: UUID().uuidString,
                document: .empty, plainText: "Do not silently drop this")
        })
    }

    func testFailedStickyTransactionPreservesOriginalAndRecoveryDraft() async throws {
        let engine = SpatialEngine()
        let block = CanvasBlock.stickyNoteBlock(position: .zero, content: "Original")
        await engine.saveBlock(block)
        defer {
            try? CanvasNotePersistence.clearRecovery(blockID: block.id)
            try? CosmoDatabase.shared.write { db in
                try db.execute(sql: "DROP TRIGGER IF EXISTS reject_sticky_save")
                try db.execute(sql: "DELETE FROM canvas_blocks WHERE id = ?", arguments: [block.id])
            }
        }
        try CosmoDatabase.shared.write { db in
            try db.execute(sql: """
                CREATE TEMP TRIGGER reject_sticky_save BEFORE UPDATE OF note_content ON canvas_blocks
                BEGIN SELECT RAISE(ABORT, 'injected write failure'); END;
                """)
        }
        XCTAssertThrowsError(try CosmoDatabase.shared.write { db in
            try CanvasNotePersistence.saveSticky(in: db, blockID: block.id, document: .empty, plainText: "Unsaved draft")
        })
        let body = try CosmoDatabase.shared.read { db in
            try String.fetchOne(db, sql: "SELECT note_content FROM canvas_blocks WHERE id = ?", arguments: [block.id])
        }
        XCTAssertEqual(body, "Original")
        let atomCount = try CosmoDatabase.shared.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM atoms WHERE uuid = ?", arguments: [block.entityUuid])
        }
        XCTAssertEqual(atomCount, 0, "Atom creation rolls back with the failed placement update")
        try CanvasNotePersistence.stashRecovery(blockID: block.id, document: .empty, plainText: "Unsaved draft")
        XCTAssertEqual(try CanvasNotePersistence.loadRecovery(blockID: block.id)?.plainText, "Unsaved draft")
    }

    func testDelayedLayoutSaveDoesNotResurrectDeletedBlock() async throws {
        let engine = SpatialEngine()
        let block = CanvasBlock.stickyNoteBlock(position: .zero)
        await engine.saveBlock(block)
        defer {
            try? CosmoDatabase.shared.write { db in
                try db.execute(sql: "DELETE FROM canvas_blocks WHERE id = ?", arguments: [block.id])
            }
        }
        try CosmoDatabase.shared.write { db in
            try db.execute(sql: "UPDATE canvas_blocks SET is_deleted = 1 WHERE id = ?", arguments: [block.id])
        }
        await engine.saveBlock(block)
        let deleted = try CosmoDatabase.shared.read { db in
            try Bool.fetchOne(db, sql: "SELECT is_deleted FROM canvas_blocks WHERE id = ?", arguments: [block.id])
        }
        XCTAssertEqual(deleted, true)
    }

    func testStickyQuitFlushIncludesTypingBeforeDocumentDebounce() async throws {
        _ = NSApplication.shared
        let engine = SpatialEngine()
        let block = CanvasBlock.stickyNoteBlock(position: .zero)
        await engine.saveBlock(block)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: StickyNoteBlockView(block: block))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        defer {
            window.orderOut(nil)
            window.contentView = nil
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            try? CosmoDatabase.shared.write { db in
                try db.execute(sql: "DELETE FROM canvas_blocks WHERE id = ?", arguments: [block.id])
                try db.execute(sql: "DELETE FROM atoms WHERE uuid = ?", arguments: [block.entityUuid])
            }
        }
        func editor(in view: NSView) -> CosmoTextView? {
            if let editor = view as? CosmoTextView { return editor }
            return view.subviews.compactMap { editor(in: $0) }.first
        }
        let textView = try XCTUnwrap(window.contentView.flatMap { editor(in: $0) })
        textView.isEditable = true
        window.makeFirstResponder(textView)
        textView.insertText("Unsent last keystrokes", replacementRange: NSRange(location: 0, length: 0))
        // No run-loop delay: the structured document has not serialized yet.
        DirtyEditorRegistry.shared.flushAll()
        let saved = try CosmoDatabase.shared.read { db in
            try String.fetchOne(db, sql: "SELECT note_content FROM canvas_blocks WHERE id = ?", arguments: [block.id])
        }
        XCTAssertEqual(saved, "Unsent last keystrokes")
    }

    func testLayoutSaveCannotOverwriteNewerStickyText() async throws {
        let engine = SpatialEngine()
        let space = "persistence-test-\(UUID().uuidString)"
        engine.currentThinkspaceId = space
        var stale = CanvasBlock.stickyNoteBlock(position: .zero)
        await engine.saveBlock(stale)
        defer {
            try? CosmoDatabase.shared.write { db in
                try db.execute(sql: "DELETE FROM canvas_blocks WHERE thinkspace_id = ?", arguments: [space])
            }
        }

        // Closing the editor commits text while the mounted canvas still has
        // its pre-edit block value. A later pin/resize used to erase the edit.
        let document = RichDocument.migrateLegacy("Keep the last sentence.")
        let metadata = RichDocumentPersistence.writeBlockDocument(
            document, key: RichDocumentMetadataKeys.bodyDocument,
            metadata: ["content": document.plainText, "stickyColor": "pink"]
        )
        try CosmoDatabase.shared.write { db in
            try db.execute(
                sql: "UPDATE canvas_blocks SET note_content = ?, metadata = ? WHERE id = ?",
                arguments: [document.plainText, SpatialEngine.encodeBlockMetadataJSON(metadata), stale.id]
            )
        }
        stale.isPinned = true
        stale.position = CGPoint(x: 400, y: 200)
        await engine.saveBlock(stale)

        // Repeated database-backed space re-entry must show the same text.
        for _ in 0..<3 {
            let blocks = await engine.fetchBlocksSnapshot(thinkspaceId: space)
            let block = try XCTUnwrap(blocks?.first)
            XCTAssertEqual(block.metadata["content"], document.plainText)
            XCTAssertEqual(block.metadata["stickyColor"], "pink")
            XCTAssertEqual(block.position, stale.position)
            XCTAssertTrue(block.isPinned)
            XCTAssertEqual(RichDocumentPersistence.loadBlockDocument(
                key: RichDocumentMetadataKeys.bodyDocument, metadata: block.metadata,
                fallbackPlainText: block.metadata["content"]
            ).plainText, document.plainText)
        }
    }
}
