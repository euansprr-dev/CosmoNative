// CosmoOS/Canvas/NoteBlockView.swift
// Orange-accented Note block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Thinkspace revamp

import SwiftUI
import GRDB
import Combine

struct NoteBlockView: View {
    let block: CanvasBlock

    @State private var noteTitleDocument: RichDocument = .empty
    @State private var noteBodyDocument: RichDocument = .empty
    @State private var noteTitleText: String = ""
    @State private var noteText: String = ""
    @State private var noteWordCount: Int = 0
    @State private var titleEditorHeight: CGFloat = 50
    @State private var isEditingTitle = false
    @State private var isEditingBody = false

    // Mutable entity tracking — updated when a backing atom is created
    @State private var trackedEntityId: Int64 = 0
    @State private var trackedEntityUuid: String = ""

    // Auto-save debouncing
    @State private var autoSaveTask: Task<Void, Never>?

    // Prevents GRDB observation updates from triggering auto-save
    @State private var isSyncingFromDB = false

    // GRDB observation
    @State private var observationCancellable: AnyCancellable?

    // Orange accent for notes
    private let accentColor = CosmoColors.blockNote
    private let titleFontSize: CGFloat = 28

    private var titleMinHeight: CGFloat {
        max(
            50,
            EditorLayoutMetrics.singleLineHeight(
                fontSize: titleFontSize,
                compact: true,
                baseFontWeight: .semibold
            )
        )
    }

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "note.text",
            title: displayTitle,
            onFocusMode: openFocusMode
        ) {
            noteContent
        }
        .onAppear {
            trackedEntityId = block.entityId
            trackedEntityUuid = block.entityUuid
            loadNote()
            startObservingAtom()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            saveNoteSync()
            observationCancellable?.cancel()
        }
        // Listen for direct state change notifications from focus mode
        .onReceive(NotificationCenter.default.publisher(for: .noteFocusStateDidChange)) { notification in
            if let uuid = notification.userInfo?["atomUUID"] as? String,
               uuid == trackedEntityUuid {
                if let title = notification.userInfo?["title"] as? String {
                    noteTitleText = title
                    if let json = notification.userInfo?["titleDocumentJSON"] as? String,
                       let data = json.data(using: .utf8),
                       let doc = try? JSONDecoder().decode(RichDocument.self, from: data) {
                        noteTitleDocument = doc
                    } else {
                        noteTitleDocument = RichDocument.migrateLegacy(title)
                    }
                }
                if let body = notification.userInfo?["body"] as? String {
                    noteText = body
                    if let json = notification.userInfo?["bodyDocumentJSON"] as? String,
                       let data = json.data(using: .utf8),
                       let doc = try? JSONDecoder().decode(RichDocument.self, from: data) {
                        noteBodyDocument = doc
                    } else {
                        noteBodyDocument = RichDocument.migrateLegacy(body)
                    }
                }
            }
        }
        // Listen for entity linkage updates (when backing atom is created)
        .onReceive(NotificationCenter.default.publisher(for: .updateBlockEntity)) { notification in
            guard let blockId = notification.userInfo?["blockId"] as? String,
                  blockId == block.id,
                  let entityId = notification.userInfo?["entityId"] as? Int64,
                  let entityUuid = notification.userInfo?["entityUuid"] as? String else { return }
            trackedEntityId = entityId
            trackedEntityUuid = entityUuid
            // Restart GRDB observation with the new UUID
            observationCancellable?.cancel()
            startObservingAtom()
        }
    }

    // MARK: - Display Title

    private var displayTitle: String {
        // Use title field, or fall back to first line of content
        if !noteTitleText.isEmpty {
            return String(noteTitleText.prefix(40))
        }
        if let firstLine = noteText.components(separatedBy: .newlines).first,
           !firstLine.isEmpty {
            return String(firstLine.prefix(40))
        }
        return "Untitled Note"
    }

    // MARK: - Note Content

    private var noteContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Entity identity strip
            Capsule()
                .fill(accentColor.opacity(0.35))
                .frame(height: 3)
                .frame(maxWidth: .infinity)
                .padding(.bottom, -8)

            // Title — always-on editor, toggle isEditable (no view swap = no shift)
            CosmoDocumentEditor(
                document: $noteTitleDocument,
                fontSize: titleFontSize,
                compact: true,
                placeholder: "Heading",
                allowSlashCommands: false,
                allowMentions: isEditingTitle,
                allowSelectionMenu: false,
                allowImages: false,
                singleLine: true,
                baseFontWeight: .semibold,
                isEditable: isEditingTitle,
                onContentHeightChange: { newHeight in
                    titleEditorHeight = max(titleMinHeight, newHeight)
                },
                onDocumentChange: { document, _ in
                    noteTitleText = RichDocumentPersistence.titlePlainText(from: document)
                    if !isSyncingFromDB { scheduleAutoSave() }
                }
            )
            .frame(height: max(titleMinHeight, titleEditorHeight))
            .contentShape(Rectangle())
            .onTapGesture { isEditingTitle = true }

            // Body — always-on editor with in-block scrolling via NSScrollView
            CosmoDocumentEditor(
                document: $noteBodyDocument,
                fontSize: 15,
                compact: true,
                placeholder: "Press / for commands...",
                allowSlashCommands: isEditingBody,
                allowMentions: isEditingBody,
                allowSelectionMenu: isEditingBody,
                allowImages: isEditingBody,
                isEditable: isEditingBody,
                scrollsInternally: true,
                onDocumentChange: { _, plainText in
                    noteText = plainText
                    noteWordCount = plainText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                    if !isSyncingFromDB { scheduleAutoSave() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { isEditingBody = true }

            // Footer: word count + timestamp
            HStack(spacing: 6) {
                if noteWordCount > 0 {
                    Text("\(noteWordCount)w")
                        .font(DS.caption2)
                        .foregroundStyle(accentColor.opacity(0.6))
                }

                Spacer()

                if let timestamp = block.metadata["created"] {
                    Text(formatTimestamp(timestamp))
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isEditingTitle = false
            isEditingBody = false
        }
    }

    // MARK: - Load Note

    private func loadNote() {
        // First try block.metadata (for freeform blocks)
        noteTitleDocument = RichDocumentPersistence.loadBlockDocument(
            key: RichDocumentMetadataKeys.titleDocument,
            metadata: block.metadata,
            fallbackPlainText: block.metadata["title"]
        )
        noteBodyDocument = RichDocumentPersistence.loadBlockDocument(
            key: RichDocumentMetadataKeys.bodyDocument,
            metadata: block.metadata,
            fallbackPlainText: block.metadata["content"]
        )
        noteTitleText = RichDocumentPersistence.titlePlainText(from: noteTitleDocument)
        noteText = noteBodyDocument.plainText

        if noteTitleText.isEmpty, let title = block.metadata["title"] {
            noteTitleText = title
        }

        // Fall back to block.title / block.subtitle (for atom-backed blocks via fromAtom())
        if noteTitleText.isEmpty {
            let blockTitle = block.title
            if blockTitle != "Note" && blockTitle != "Untitled" {
                noteTitleText = blockTitle
                noteTitleDocument = RichDocument.migrateLegacy(blockTitle)
            }
        }
        if noteText.isEmpty, let subtitle = block.subtitle {
            noteText = subtitle
            noteBodyDocument = RichDocument.migrateLegacy(subtitle)
        }

        // If linked to an atom, load freshest data from database
        if trackedEntityId > 0 {
            Task {
                do {
                    if let atom = try await AtomRepository.shared.fetch(id: trackedEntityId) {
                        await MainActor.run {
                            noteTitleDocument = RichDocumentPersistence.loadAtomDocument(
                                field: .title,
                                metadata: atom.metadata,
                                fallbackPlainText: atom.title
                            )
                            noteBodyDocument = RichDocumentPersistence.loadAtomDocument(
                                field: .body,
                                metadata: atom.metadata,
                                fallbackPlainText: atom.body
                            )
                            noteTitleText = RichDocumentPersistence.titlePlainText(from: noteTitleDocument)
                            noteText = noteBodyDocument.plainText
                        }
                    }
                } catch {
                    print("NoteBlock: Failed to load atom: \(error)")
                }
            }
        }
    }

    // MARK: - GRDB Observation

    private func startObservingAtom() {
        let uuid = trackedEntityUuid
        // Only observe if we have a real UUID (not empty)
        guard !uuid.isEmpty else { return }

        let observation = ValueObservation.tracking { db in
            try Atom
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
        observationCancellable = observation.publisher(in: CosmoDatabase.shared.dbQueue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { fetchedAtom in
                    guard let atom = fetchedAtom else { return }
                    let newTitleDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .title,
                        metadata: atom.metadata,
                        fallbackPlainText: atom.title
                    )
                    let newBodyDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .body,
                        metadata: atom.metadata,
                        fallbackPlainText: atom.body
                    )
                    let newTitle = RichDocumentPersistence.titlePlainText(from: newTitleDocument)
                    let newBody = newBodyDocument.plainText
                    // Only update state if values actually changed (nil-safe)
                    guard newTitle != noteTitleText || newBody != noteText || newTitleDocument != noteTitleDocument || newBodyDocument != noteBodyDocument else { return }
                    isSyncingFromDB = true
                    noteTitleDocument = newTitleDocument
                    noteBodyDocument = newBodyDocument
                    noteTitleText = newTitle
                    noteText = newBody
                    // Defer clearing the flag so onChange handlers see it
                    DispatchQueue.main.async {
                        isSyncingFromDB = false
                    }
                }
            )
    }

    // MARK: - Auto-save

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()

        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                await MainActor.run {
                    saveNote()
                }
            }
        }
    }

    private func saveNote() {
        // Update block metadata (for SpatialEngine persistence)
        NotificationCenter.default.post(
            name: .updateBlockContent,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "title": noteTitleText,
                "content": noteText
            ]
        )

        let updatedMetadata = RichDocumentPersistence
            .writeBlockDocument(noteTitleDocument, key: RichDocumentMetadataKeys.titleDocument, metadata: block.metadata)
        let bodyMetadata = RichDocumentPersistence
            .writeBlockDocument(noteBodyDocument, key: RichDocumentMetadataKeys.bodyDocument, metadata: updatedMetadata)
        NotificationCenter.default.post(
            name: .updateBlockMetadata,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "metadata": bodyMetadata.merging([
                    "title": noteTitleText,
                    "content": noteText
                ]) { _, new in new }
            ]
        )

        // Also update the atom in the database (for blocks linked to entities)
        let uuid = trackedEntityUuid
        if !uuid.isEmpty {
            Task {
                do {
                    try await CosmoDatabase.shared.asyncWrite { db in
                        var existingMetadata: String?
                        if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                            existingMetadata = row["metadata"]
                        }
                        let fields = RichDocumentPersistence.writeAtomDocuments(
                            existingMetadata: existingMetadata,
                            titleDocument: noteTitleDocument,
                            bodyDocument: noteBodyDocument
                        )
                        try db.execute(
                            sql: """
                            UPDATE atoms
                            SET title = ?,
                                body = ?,
                                metadata = ?,
                                updated_at = ?,
                                _local_version = _local_version + 1
                            WHERE uuid = ?
                            """,
                            arguments: [
                                fields.title,
                                fields.body ?? "",
                                fields.metadata,
                                ISO8601DateFormatter().string(from: Date()),
                                uuid
                            ]
                        )
                    }
                } catch {
                    print("NoteBlock: Failed to save to atom: \(error)")
                }
            }
        }
    }

    /// Synchronous save — blocks until DB write completes.
    /// Used on close to guarantee data is persisted before the block/app exits.
    private func saveNoteSync() {
        let uuid = trackedEntityUuid
        guard !uuid.isEmpty else { return }

        do {
            try CosmoDatabase.shared.write { db in
                var existingMetadata: String?
                if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                    existingMetadata = row["metadata"]
                }
                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: existingMetadata,
                    titleDocument: noteTitleDocument,
                    bodyDocument: noteBodyDocument
                )
                try db.execute(
                    sql: """
                    UPDATE atoms
                    SET title = ?,
                        body = ?,
                        metadata = ?,
                        updated_at = ?,
                        _local_version = _local_version + 1
                    WHERE uuid = ?
                    """,
                    arguments: [
                        fields.title,
                        fields.body ?? "",
                        fields.metadata,
                        ISO8601DateFormatter().string(from: Date()),
                        uuid
                    ]
                )
            }
        } catch {
            print("NoteBlock: sync save failed: \(error)")
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        if trackedEntityId > 0 {
            // Has backing atom, open directly
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: [
                    "type": EntityType.note,
                    "id": trackedEntityId
                ]
            )
        } else {
            // Create backing atom from current note data, then open
            Task {
                do {
                    var newAtom = Atom.new(
                        type: .note,
                        title: noteTitleText.isEmpty ? nil : noteTitleText,
                        body: noteText
                    )
                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: newAtom.metadata,
                        titleDocument: noteTitleDocument,
                        bodyDocument: noteBodyDocument
                    )
                    newAtom.title = fields.title
                    newAtom.body = fields.body
                    newAtom.metadata = fields.metadata
                    let atomId = try await CosmoDatabase.shared.asyncWrite { db -> Int64 in
                        try newAtom.insert(db)
                        return db.lastInsertedRowID
                    }
                    // Update canvas block record to link to new atom
                    try await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(
                            sql: """
                            UPDATE canvas_blocks
                            SET entity_id = ?, entity_uuid = ?
                            WHERE id = ?
                            """,
                            arguments: [atomId, newAtom.uuid, block.id]
                        )
                    }
                    await MainActor.run {
                        // Update in-memory block in SpatialEngine + this view
                        NotificationCenter.default.post(
                            name: .updateBlockEntity,
                            object: nil,
                            userInfo: [
                                "blockId": block.id,
                                "entityId": atomId,
                                "entityUuid": newAtom.uuid
                            ]
                        )
                        NotificationCenter.default.post(
                            name: .enterFocusMode,
                            object: nil,
                            userInfo: [
                                "type": EntityType.note,
                                "id": atomId
                            ]
                        )
                    }
                } catch {
                    print("NoteBlock: Failed to create backing atom: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ timestamp: String) -> String {
        if let date = ISO8601DateFormatter().date(from: timestamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }
}

// MARK: - Notifications (keep existing for compatibility)

extension Notification.Name {
    static let updateBlockContent = Notification.Name("updateBlockContent")
    static let updateBlockMetadata = Notification.Name("updateBlockMetadata")
    static let updateBlockSize = Notification.Name("updateBlockSize")
    static let saveBlockSize = Notification.Name("saveBlockSize")
    static let blurAllBlocks = Notification.Name("blurAllBlocks")
    static let contentFocusStateDidChange = Notification.Name("contentFocusStateDidChange")
    static let contentFocusStateSaved = Notification.Name("contentFocusStateSaved")
    static let contentPhaseChanged = Notification.Name("contentPhaseChanged")
    static let noteFocusStateDidChange = Notification.Name("noteFocusStateDidChange")
    static let updateBlockEntity = Notification.Name("updateBlockEntity")
}

// MARK: - Preview

#if DEBUG
struct NoteBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            NoteBlockView(
                block: CanvasBlock.noteBlock(position: CGPoint(x: 200, y: 200))
            )
        }
        .frame(width: 500, height: 400)
    }
}
#endif
