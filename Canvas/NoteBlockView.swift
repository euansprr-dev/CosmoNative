// CosmoOS/Canvas/NoteBlockView.swift
// Orange-accented Note block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Thinkspace revamp

import SwiftUI
import GRDB
import Combine

struct NoteBlockView: View {
    let block: CanvasBlock

    @State private var noteTitle: String = ""
    @State private var noteText: String = ""
    @State private var isExpanded = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool

    // Auto-save debouncing
    @State private var autoSaveTask: Task<Void, Never>?

    // GRDB observation
    @State private var observationCancellable: AnyCancellable?

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Orange accent for notes
    private let accentColor = CosmoColors.blockNote

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "note.text",
            title: displayTitle,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            noteContent
        }
        .onAppear {
            loadNote()
            startObservingAtom()
        }
        .onDisappear {
            observationCancellable?.cancel()
        }
        // Listen for direct state change notifications from focus mode
        .onReceive(NotificationCenter.default.publisher(for: .noteFocusStateDidChange)) { notification in
            if let uuid = notification.userInfo?["atomUUID"] as? String,
               uuid == block.entityUuid {
                if let title = notification.userInfo?["title"] as? String {
                    noteTitle = title
                }
                if let body = notification.userInfo?["body"] as? String {
                    noteText = body
                }
            }
        }
    }

    // MARK: - Display Title

    private var displayTitle: String {
        // Use title field, or fall back to first line of content
        if !noteTitle.isEmpty {
            return String(noteTitle.prefix(40))
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
            // Title field
            ZStack(alignment: .topLeading) {
                // Placeholder
                if noteTitle.isEmpty {
                    Text("Heading")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(Color.white.opacity(0.35))
                        .allowsHitTesting(false)
                }

                // Title text field
                TextField("", text: $noteTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundColor(.white)
                    .focused($isTitleFocused)
                    .onSubmit {
                        isBodyFocused = true
                    }
            }

            // Body text editor
            ZStack(alignment: .topLeading) {
                // Placeholder
                if noteText.isEmpty && !isBodyFocused {
                    Text("Press / for commands...")
                        .font(.system(size: 15))
                        .foregroundColor(Color.white.opacity(0.35))
                        .allowsHitTesting(false)
                }

                // Body text editor
                TextEditor(text: $noteText)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isBodyFocused)
            }
            .frame(maxHeight: .infinity)

            // Timestamp at bottom
            if let timestamp = block.metadata["created"] {
                HStack {
                    Spacer()
                    Text(formatTimestamp(timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.3))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: noteTitle) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: noteText) { _, _ in
            scheduleAutoSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isTitleFocused = false
            isBodyFocused = false
        }
    }

    // MARK: - Load Note

    private func loadNote() {
        // First try block.metadata (for freeform blocks)
        if let title = block.metadata["title"] {
            noteTitle = title
        }
        if let content = block.metadata["content"] {
            noteText = content
        }

        // Fall back to block.title / block.subtitle (for atom-backed blocks via fromAtom())
        if noteTitle.isEmpty {
            let blockTitle = block.title
            if blockTitle != "Note" && blockTitle != "Untitled" {
                noteTitle = blockTitle
            }
        }
        if noteText.isEmpty, let subtitle = block.subtitle {
            noteText = subtitle
        }

        // If linked to an atom, load freshest data from database
        if block.entityId > 0 {
            Task {
                do {
                    if let atom = try await AtomRepository.shared.fetch(id: block.entityId) {
                        await MainActor.run {
                            noteTitle = atom.title ?? ""
                            noteText = atom.body ?? ""
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
        let uuid = block.entityUuid
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
                    if atom.title != noteTitle || atom.body != noteText {
                        noteTitle = atom.title ?? ""
                        noteText = atom.body ?? ""
                    }
                }
            )
    }

    // MARK: - Auto-save

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
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
                "title": noteTitle,
                "content": noteText
            ]
        )

        // Also update the atom in the database (for blocks linked to entities)
        let uuid = block.entityUuid
        if !uuid.isEmpty {
            Task {
                do {
                    try await CosmoDatabase.shared.asyncWrite { db in
                        try db.execute(
                            sql: """
                            UPDATE atoms
                            SET title = ?,
                                body = ?,
                                updated_at = ?,
                                _local_version = _local_version + 1
                            WHERE uuid = ?
                            """,
                            arguments: [
                                noteTitle.isEmpty ? nil : noteTitle,
                                noteText,
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

    // MARK: - Focus Mode

    private func openFocusMode() {
        if block.entityId > 0 {
            // Has backing atom, open directly
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: [
                    "type": EntityType.note,
                    "id": block.entityId
                ]
            )
        } else {
            // Create backing atom from current note data, then open
            Task {
                do {
                    var newAtom = Atom.new(
                        type: .note,
                        title: noteTitle.isEmpty ? nil : noteTitle,
                        body: noteText
                    )
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
            .environmentObject(BlockExpansionManager())
        }
        .frame(width: 500, height: 400)
    }
}
#endif
