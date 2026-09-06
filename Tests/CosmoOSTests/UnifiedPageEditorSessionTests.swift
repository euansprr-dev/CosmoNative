import XCTest
@testable import CosmoOS

final class UnifiedPageEditorSessionTests: XCTestCase {
    private func page() -> Atom {
        let written = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: "{\"tags\":[\"original\"],\"spaceComposition\":{\"parentUUID\":\"book\"},\"references\":[\"source\"],\"futureKey\":true}",
            titleDocument: .migrateLegacy("Original title"), bodyDocument: .migrateLegacy("Original body"))
        return Atom.new(type: .note, title: written.title, body: written.body, metadata: written.metadata)
    }

    private func fields(_ atom: Atom) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data((atom.metadata ?? "{}").utf8)) as? [String: Any])
    }

    private func replacing(_ atom: Atom, fields updates: [String: Any]) throws -> Atom {
        var updated = try fields(atom)
        for (key, value) in updates { updated[key] = value }
        var result = atom
        result.metadata = String(decoding: try JSONSerialization.data(withJSONObject: updated), as: UTF8.self)
        return result
    }

    func testTitleOnlySavePreservesFreshBodyStructureReferencesAndUnknownStyleKeys() throws {
        let original = page()
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: SpacePageContentVersion.document(original), generation: 1,
            dirtyFields: [.title], titleDocument: .migrateLegacy("New title"))
        var fresh = try replacing(original, fields: [
            "spaceComposition": ["parentUUID": "new-book", "canvas": ["drawings": ["ink"]]],
            "references": ["new-source"], "note_document_style": ["fontFamily": "serif", "futureStyle": true]
        ])
        fresh.body = "Body from another editor"
        fresh.metadata = RichDocumentPersistence.writeAtomDocuments(existingMetadata: fresh.metadata,
            bodyDocument: .migrateLegacy(fresh.body!)).metadata
        let saved = try SpacePageContentWriter.applying(pending, to: fresh)
        XCTAssertEqual(saved.title, "New title")
        XCTAssertEqual(saved.body, fresh.body)
        XCTAssertEqual(SpacePageContentVersion.document(saved), SpacePageContentVersion.document(fresh))
        let metadata = try fields(saved)
        XCTAssertEqual((metadata["spaceComposition"] as? [String: Any])?["parentUUID"] as? String, "new-book")
        XCTAssertEqual(metadata["references"] as? [String], ["new-source"])
        XCTAssertEqual(metadata["futureKey"] as? Bool, true)
        XCTAssertEqual((metadata["note_document_style"] as? [String: Any])?["futureStyle"] as? Bool, true)
    }

    func testStyleAndTagsSaveTogetherWithoutClaimingTitleOrBody() throws {
        let original = page()
        var style = NoteDocumentStyle.default
        style.fontFamily = .serif
        style.cover = .dawn
        style.paperTone = .sage
        style.pageIcon = "leaf"
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: .migrateLegacy("An unowned body must not be written"), generation: 2,
            dirtyFields: [.style, .tags], style: style, tags: ["new", "shared"])
        var fresh = try replacing(original, fields: ["note_document_style": ["futureField": "keep"]])
        fresh.title = "Renamed elsewhere"
        fresh.body = "New remote words"
        let saved = try SpacePageContentWriter.applying(pending, to: fresh)
        XCTAssertEqual(saved.title, fresh.title)
        XCTAssertEqual(saved.body, fresh.body)
        XCTAssertEqual(NoteDocumentStyle.load(fromMetadata: saved.metadata), style)
        XCTAssertEqual(saved.tagsList, ["new", "shared"])
        XCTAssertEqual((try fields(saved)["note_document_style"] as? [String: Any])?["futureField"] as? String, "keep")
    }

    func testEachOwnedFieldDetectsItsOwnConcurrentChangeAndExplicitReplacementPreservesOtherFields() throws {
        let original = page()
        var style = NoteDocumentStyle.default
        style.textSize = .large
        for field in SpacePageOwnedField.allCases {
            let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
                document: .migrateLegacy("Local body"), generation: 1, dirtyFields: [field],
                titleDocument: .migrateLegacy("Local title"), style: style, tags: ["local"])
            var fresh = original
            switch field {
            case .body: fresh.body = "Remote body"
            case .title: fresh.title = "Remote title"
            case .style:
                var remoteStyle = NoteDocumentStyle.default
                remoteStyle.pageWidth = .wide
                fresh.metadata = remoteStyle.write(intoMetadata: fresh.metadata)
            case .tags: fresh = try replacing(fresh, fields: ["tags": ["remote"]])
            }
            XCTAssertThrowsError(try SpacePageContentWriter.applying(pending, to: fresh), "Expected conflict for \(field)") {
                XCTAssertEqual($0 as? SpacePageSaveFailure, .contentChanged)
            }
            let saved = try SpacePageContentWriter.applying(pending, to: fresh, replacingConflict: true)
            XCTAssertTrue(pending.matches(field, in: saved))
            XCTAssertEqual(try fields(saved)["references"] as? [String], ["source"])
            let repeated = try SpacePageContentWriter.applying(pending, to: saved)
            XCTAssertEqual(SpacePageContentVersion(repeated), SpacePageContentVersion(saved))
        }
    }

    func testRichTitleFormattingIsPreservedAndConcurrentFormattingConflicts() throws {
        let original = page()
        var title = SpacePageContentVersion.titleDocument(original)
        title.blocks[0].inlines[0].marks = [.bold]
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: SpacePageContentVersion.document(original), generation: 1, dirtyFields: [.title], titleDocument: title)
        let saved = try SpacePageContentWriter.applying(pending, to: original)
        XCTAssertEqual(SpacePageContentVersion.titleDocument(saved), title)
        var italic = SpacePageContentVersion.titleDocument(original)
        italic.blocks[0].inlines[0].marks = [.italic]
        var fresh = original
        fresh.metadata = RichDocumentPersistence.writeAtomDocuments(existingMetadata: fresh.metadata, titleDocument: italic).metadata
        XCTAssertThrowsError(try SpacePageContentWriter.applying(pending, to: fresh))
    }

    func testOldBodyOnlyRecoveryFilesRemainReadableAndDoNotOwnAuxiliaryFields() throws {
        let original = page()
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: .migrateLegacy("Recovered body"), generation: 1)
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pending)) as? [String: Any])
        for key in ["dirtyFields", "titleDocument", "style", "tags"] { encoded.removeValue(forKey: key) }
        var baseline = try XCTUnwrap(encoded["base"] as? [String: Any])
        for key in ["title", "richTitleDocument", "style", "tags"] { baseline.removeValue(forKey: key) }
        encoded["base"] = baseline
        let recovered = try JSONDecoder().decode(SpacePageDraft.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertEqual(recovered.dirtyFields, [.body])
        var fresh = original
        fresh.title = "Renamed after the crash"
        let saved = try SpacePageContentWriter.applying(recovered, to: fresh)
        XCTAssertEqual(saved.body, "Recovered body")
        XCTAssertEqual(saved.title, fresh.title)
        XCTAssertEqual(saved.tagsList, original.tagsList)
    }

    @MainActor
    func testRecoveryRestoresAllDirtyFieldsAndAdoptsFreshUneditedFields() throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SpacePageDraftJournal(directory: directory)
        var style = NoteDocumentStyle.default
        style.cover = .meadow
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: .migrateLegacy("Recovered body"), generation: 9,
            dirtyFields: Set(SpacePageOwnedField.allCases), titleDocument: .migrateLegacy("Recovered title"),
            style: style, tags: ["recovered"])
        try journal.saveSynchronously(pending)
        let session = SpacePageEditorSession(atom: original, journal: journal, publishesChanges: false)
        XCTAssertEqual(session.document, pending.document)
        XCTAssertEqual(session.titleDocument, pending.titleDocument)
        XCTAssertEqual(session.style, style)
        XCTAssertEqual(session.tags, ["recovered"])
        XCTAssertEqual(session.dirtyFields, Set(SpacePageOwnedField.allCases))
        XCTAssertTrue(session.isDirty)
        let saved = try SpacePageContentWriter.applying(pending, to: original)
        let clean = SpacePageEditorSession(atom: saved, journal: journal, publishesChanges: false)
        XCTAssertFalse(clean.isDirty, "An already-committed checkpoint must not revive a draft")
    }

    @MainActor
    func testSynchronousCommitThenHistoryRestoreDoesNotResurrectCommittedDraftOnReopen() throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SpacePageDraftJournal(directory: directory)
        let session = SpacePageEditorSession(atom: original, journal: journal, publishesChanges: false,
            saveSynchronously: { draft, replaces in
                var saved = try SpacePageContentWriter.applying(draft, to: original, replacingConflict: replaces)
                saved.localVersion = original.localVersion + 1
                return saved
            })
        session.edit(.migrateLegacy("Writing committed before restore"))
        session.editTitle(.migrateLegacy("Title committed before restore"))
        var style = NoteDocumentStyle.default
        style.fontFamily = .serif
        style.paperTone = .sage
        session.editStyle(style)
        session.editTags(["keep-current-tags"])
        XCTAssertTrue(session.flushSynchronously())
        XCTAssertFalse(session.isDirty)
        XCTAssertNil(try journal.load(uuid: original.uuid))

        var restored = AtomHistoryRestoreContent.applying(AtomRevision(of: original, source: .restore), to: session.atom)
        restored.localVersion = session.atom.localVersion + 1
        session.adoptRestored(restored)
        let reopened = SpacePageEditorSession(atom: restored, journal: journal, publishesChanges: false)
        XCTAssertFalse(reopened.isDirty)
        XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.document, SpacePageContentVersion.document(original))
        XCTAssertEqual(reopened.title, original.title)
        XCTAssertEqual(reopened.style, style)
        XCTAssertEqual(reopened.tags, ["keep-current-tags"])
    }

    @MainActor
    func testLoadingAlreadyCommittedCheckpointRetiresItBeforeLaterRestore() throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SpacePageDraftJournal(directory: directory)
        let pending = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: .migrateLegacy("Previously committed"), generation: 1)
        try journal.saveSynchronously(pending)
        let saved = try SpacePageContentWriter.applying(pending, to: original)
        let firstLaunch = SpacePageEditorSession(atom: saved, journal: journal, publishesChanges: false)
        XCTAssertFalse(firstLaunch.isDirty)
        XCTAssertNil(try journal.load(uuid: original.uuid))
        let restored = AtomHistoryRestoreContent.applying(AtomRevision(of: original, source: .restore), to: saved)
        let nextLaunch = SpacePageEditorSession(atom: restored, journal: journal, publishesChanges: false)
        XCTAssertFalse(nextLaunch.isDirty)
        XCTAssertEqual(nextLaunch.document, SpacePageContentVersion.document(original))
    }

    func testSynchronousCheckpointCleanupPreservesANewerPendingDraft() throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SpacePageDraftJournal(directory: directory)
        let committed = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: .migrateLegacy("Committed"), generation: 1)
        let newer = SpacePageDraft(uuid: original.uuid, base: SpacePageContentVersion(original),
            document: .migrateLegacy("New writing still pending"), generation: 2)
        try journal.saveSynchronously(committed)
        try journal.saveSynchronously(newer)
        try journal.removeSynchronously(uuid: original.uuid, through: committed.id)
        XCTAssertEqual(try journal.load(uuid: original.uuid)?.id, newer.id)
        XCTAssertEqual(try journal.load(uuid: original.uuid)?.document, newer.document)
    }

    @MainActor
    func testRepresentationsShareOneSessionAndHistoryAdoptsAllPageFields() async throws {
        let original = page()
        let store = SpacePageEditorStore()
        let session = store.session(for: original)
        XCTAssertTrue(session === store.session(for: original))
        let prepared = await session.prepareForHistory()
        XCTAssertTrue(prepared)
        var restored = original
        var style = NoteDocumentStyle.default
        style.cover = .dusk
        let written = RichDocumentPersistence.writeAtomDocuments(existingMetadata: style.write(intoMetadata: original.metadata),
            titleDocument: .migrateLegacy("Restored title"), bodyDocument: .migrateLegacy("Restored body"))
        restored.title = written.title
        restored.body = written.body
        restored.metadata = written.metadata
        restored.localVersion += 1
        session.adoptRestored(restored)
        XCTAssertEqual(session.title, "Restored title")
        XCTAssertEqual(session.document.plainText, "Restored body")
        XCTAssertEqual(session.style, style)
        XCTAssertFalse(session.isDirty)
        XCTAssertTrue(store.session(for: restored) === session)
    }

    @MainActor
    func testFailedHistoryPreparationRetainsTitleStyleTagsAndRecoveryCopy() async throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = SpacePageDraftJournal(directory: directory)
        defer {
            DirtyEditorRegistry.shared.unregister(id: "space-page-" + original.uuid)
            AtomRestoreAdopterRegistry.shared.unregister(uuid: original.uuid)
            AtomRepository.shared.releaseEditingLock(uuid: original.uuid)
            try? FileManager.default.removeItem(at: directory)
        }
        let session = SpacePageEditorSession(atom: original, journal: journal, publishesChanges: false,
            save: { _, _ in throw SpacePageSaveFailure.contentChanged })
        session.editTitle(.migrateLegacy("Draft title"))
        var style = NoteDocumentStyle.default
        style.paperTone = .mist
        session.editStyle(style)
        session.editTags(["draft"])
        let prepared = await session.prepareForHistory()
        XCTAssertFalse(prepared)
        XCTAssertTrue(session.isDirty)
        XCTAssertTrue(session.hasConflict)
        XCTAssertEqual(session.title, "Draft title")
        XCTAssertEqual(session.style, style)
        XCTAssertEqual(session.tags, ["draft"])
        XCTAssertEqual(try journal.load(uuid: original.uuid)?.dirtyFields, [.title, .style, .tags])
        XCTAssertTrue(AtomRepository.shared.isBeingEdited(original.uuid))
    }

    @MainActor
    func testFreshUneditedFieldsReachSessionWithoutReplacingDirtyBody() async throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            DirtyEditorRegistry.shared.unregister(id: "space-page-" + original.uuid)
            AtomRestoreAdopterRegistry.shared.unregister(uuid: original.uuid)
            AtomRepository.shared.releaseEditingLock(uuid: original.uuid)
            try? FileManager.default.removeItem(at: directory)
        }
        let session = SpacePageEditorSession(atom: original, journal: .init(directory: directory), publishesChanges: false,
            save: { _, _ in throw SpacePageSaveFailure.contentChanged })
        session.edit(.migrateLegacy("Unsaved body"))
        var style = NoteDocumentStyle.default
        style.fontFamily = .mono
        var fresh = original
        let written = RichDocumentPersistence.writeAtomDocuments(existingMetadata: style.write(intoMetadata: fresh.metadata),
            titleDocument: .migrateLegacy("Fresh title"), bodyDocument: .migrateLegacy("Conflicting remote body"))
        fresh.title = written.title
        fresh.body = written.body
        fresh.metadata = written.metadata
        fresh.localVersion += 1
        session.receive(fresh)
        XCTAssertEqual(session.document.plainText, "Unsaved body")
        XCTAssertEqual(session.title, "Fresh title")
        XCTAssertEqual(session.style, style)
        XCTAssertEqual(session.dirtyFields, [.body])
        _ = await session.flush()
    }

    @MainActor
    func testEditDuringSaveDrainsNewGenerationWithoutLosingNewFields() async throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = UnifiedPageSaveHarness(atom: original)
        let session = SpacePageEditorSession(atom: original, journal: .init(directory: directory), publishesChanges: false,
            save: { draft, replaces in try await harness.save(draft, replaces: replaces) })
        session.edit(.migrateLegacy("Body being saved"))
        let flush = Task { await session.flush() }
        await harness.waitUntilPaused()
        session.editTitle(.migrateLegacy("Title typed during save"))
        session.editTags(["during-save"])
        await harness.resume()
        let succeeded = await flush.value
        XCTAssertTrue(succeeded)
        XCTAssertFalse(session.isDirty)
        let saved = await harness.current()
        XCTAssertEqual(saved.body, "Body being saved")
        XCTAssertEqual(saved.title, "Title typed during save")
        XCTAssertEqual(saved.tagsList, ["during-save"])
        XCTAssertEqual(session.title, saved.title)
    }

    @MainActor
    func testFieldFirstEditedDuringSaveRetainsItsOriginalConflictBaseline() async throws {
        let original = page()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            DirtyEditorRegistry.shared.unregister(id: "space-page-" + original.uuid)
            AtomRestoreAdopterRegistry.shared.unregister(uuid: original.uuid)
            AtomRepository.shared.releaseEditingLock(uuid: original.uuid)
            try? FileManager.default.removeItem(at: directory)
        }
        let harness = UnifiedPageSaveHarness(atom: original)
        let journal = SpacePageDraftJournal(directory: directory)
        let session = SpacePageEditorSession(atom: original, journal: journal, publishesChanges: false,
            save: { draft, replaces in try await harness.save(draft, replaces: replaces) })
        session.edit(.migrateLegacy("Local body"))
        let flush = Task { await session.flush() }
        await harness.waitUntilPaused()
        session.editTitle(.migrateLegacy("Local title"))
        await harness.rename("Concurrent title")
        await harness.resume()
        let succeeded = await flush.value
        XCTAssertFalse(succeeded)
        XCTAssertEqual(session.title, "Local title")
        XCTAssertTrue(session.hasConflict)
        XCTAssertEqual(session.dirtyFields, [.title])
        let saved = await harness.current()
        XCTAssertEqual(saved.title, "Concurrent title")
        XCTAssertEqual(saved.body, "Local body")
        XCTAssertEqual(try journal.load(uuid: original.uuid)?.dirtyFields, [.title])
    }
}

private actor UnifiedPageSaveHarness {
    private var atom: Atom
    private var calls = 0
    private var paused: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(atom: Atom) { self.atom = atom }

    func save(_ draft: SpacePageDraft, replaces: Bool) async throws -> Atom {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { continuation in
                paused = continuation
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()
            }
        }
        var saved = try SpacePageContentWriter.applying(draft, to: atom, replacingConflict: replaces)
        saved.localVersion = atom.localVersion + 1
        atom = saved
        return saved
    }

    func waitUntilPaused() async {
        if paused != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume() { paused?.resume(); paused = nil }
    func current() -> Atom { atom }
    func rename(_ title: String) {
        let written = RichDocumentPersistence.writeAtomDocuments(existingMetadata: atom.metadata, titleDocument: .migrateLegacy(title))
        atom.title = written.title
        atom.metadata = written.metadata
        atom.localVersion += 1
    }
}
