// CosmoOS/Canvas/StickyNoteBlockView.swift
// Warm yellow sticky note block for Thinkspace canvas
// Square, minimal chrome, paper aesthetic — no datetime or header

import SwiftUI
import GRDB
import Combine

// MARK: - Sticky Note Color Palette

enum StickyNoteColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case orange
    case lavender

    var id: String { rawValue }

    var paper: Color {
        switch self {
        case .yellow:   return Color(hex: "F5E6A3")
        case .green:    return Color(hex: "C4E6C3")
        case .blue:     return Color(hex: "B8D4E8")
        case .pink:     return Color(hex: "F0C4D0")
        case .orange:   return Color(hex: "F5D4A8")
        case .lavender: return Color(hex: "D4C8E8")
        }
    }

    var border: Color {
        switch self {
        case .yellow:   return Color(hex: "E8D88C")
        case .green:    return Color(hex: "A8D4A6")
        case .blue:     return Color(hex: "96BCD4")
        case .pink:     return Color(hex: "DCA0B4")
        case .orange:   return Color(hex: "E0BC88")
        case .lavender: return Color(hex: "BAA8D4")
        }
    }

    var hoverBorder: Color {
        switch self {
        case .yellow:   return Color(hex: "E0CC7A")
        case .green:    return Color(hex: "90C48E")
        case .blue:     return Color(hex: "7CACC8")
        case .pink:     return Color(hex: "D088A0")
        case .orange:   return Color(hex: "D0A870")
        case .lavender: return Color(hex: "A890C4")
        }
    }

    var selectedBorder: Color {
        switch self {
        case .yellow:   return Color(hex: "D4C36A")
        case .green:    return Color(hex: "78B476")
        case .blue:     return Color(hex: "6498B8")
        case .pink:     return Color(hex: "C47090")
        case .orange:   return Color(hex: "C09458")
        case .lavender: return Color(hex: "9478B4")
        }
    }

    var fold: Color { border }

    var swatch: Color { border }
}

// MARK: - Corner Fold Shape

/// Triangular fold for the sticky note top-right corner
private struct StickyNoteFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Sticky Note Block View

struct StickyNoteBlockView: View {
    let block: CanvasBlock

    @State private var noteBodyDocument: RichDocument = .empty
    @State private var noteText: String = ""
    @State private var isEditingBody = false

    // Auto-save debouncing
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveClosed = false

    // Prevents GRDB observation updates from triggering auto-save
    @State private var isSyncingFromDB = false

    // GRDB observation
    @State private var observationCancellable: AnyCancellable?

    // Visual states
    @State private var isSelected = false
    @State private var isHovered = false
    @State private var hasAppeared = false

    // Current sticky color
    @State private var stickyColor: StickyNoteColor = .yellow

    var body: some View {
        CosmoDocumentEditor(
            document: $noteBodyDocument,
            fontSize: 14,
            compact: true,
            placeholder: "Type here...",
            allowSlashCommands: false,
            allowMentions: isEditingBody,
            allowSelectionMenu: false,
            allowImages: false,
            isEditable: isEditingBody,
            scrollsInternally: true,
            onDocumentChange: { _, plainText in
                print("[BLOCK-STICKY] onDocumentChange — len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" isSyncingFromDB=\(isSyncingFromDB) uuid=\(block.entityUuid)")
                noteText = plainText
                if !isSyncingFromDB { scheduleAutoSave() }
            },
            onActivate: { isEditingBody = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .frame(
            width: block.defaultSize.width,
            height: block.defaultSize.height,
            alignment: .topLeading
        )
        .background(stickyColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Corner fold detail
        .overlay(alignment: .topTrailing) {
            StickyNoteFold()
                .fill(stickyColor.fold)
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.04), radius: 2, x: -1, y: 1)
                .allowsHitTesting(false)
        }
        // Paper grain texture
        .overlay(
            FilmGrainOverlay(opacity: 0.03)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
        )
        // Multi-layer border with warm glow on selection
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? stickyColor.selectedBorder : (isHovered ? stickyColor.hoverBorder : stickyColor.border),
                        lineWidth: isSelected ? 1.5 : 1
                    )
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(stickyColor.selectedBorder.opacity(0.25), lineWidth: 3)
                        .blur(radius: 4)
                }
            }
        )
        // Animated shadow elevation (3-tier: resting → hover → selected)
        .shadow(
            color: .black.opacity(isSelected ? 0.08 : (isHovered ? 0.06 : 0.04)),
            radius: isSelected ? 14 : (isHovered ? 12 : 8),
            x: 0,
            y: isSelected ? 4 : (isHovered ? 4 : 2)
        )
        .shadow(
            color: .black.opacity(0.02),
            radius: 2, x: 0, y: 1
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.blockSelected,
                object: nil,
                userInfo: ["blockId": block.id]
            )
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                openFocusMode()
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.blockSelected)) { notification in
            if let selectedId = notification.userInfo?["blockId"] as? String {
                isSelected = (selectedId == block.id)
            }
        }
        // Entry animation
        .scaleEffect(hasAppeared ? 1.0 : 0.92)
        .opacity(hasAppeared ? 1.0 : 0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .animation(ProMotionSprings.hover, value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stickyColor)
        .onAppear {
            loadNote()
            loadColor()
            startObservingAtom()
            withAnimation(ProMotionSprings.cardEntrance) {
                hasAppeared = true
            }
        }
        .onDisappear {
            print("[BLOCK-STICKY] onDisappear — uuid=\(block.entityUuid) bodyLen=\(noteText.count) bodyPreview=\"\(String(noteText.prefix(60)))\"")
            autoSaveTask?.cancel()
            saveClosed = true
            saveNoteSync()
            observationCancellable?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isEditingBody = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteFocusStateDidChange)) { notification in
            if let uuid = notification.userInfo?["atomUUID"] as? String,
               uuid == block.entityUuid {
                if let body = notification.userInfo?["body"] as? String {
                    noteText = body
                    noteBodyDocument = RichDocument.migrateLegacy(body)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.changeStickyColor)) { notification in
            guard let targetId = notification.userInfo?["blockId"] as? String,
                  targetId == block.id,
                  let colorKey = notification.userInfo?["color"] as? String,
                  let newColor = StickyNoteColor(rawValue: colorKey) else { return }
            changeColor(newColor)
        }
    }

    // MARK: - Color

    private func loadColor() {
        if let colorKey = block.metadata["stickyColor"],
           let color = StickyNoteColor(rawValue: colorKey) {
            stickyColor = color
        }
    }

    private func changeColor(_ newColor: StickyNoteColor) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            stickyColor = newColor
        }
        var updatedMetadata = block.metadata
        updatedMetadata["stickyColor"] = newColor.rawValue
        NotificationCenter.default.post(
            name: .updateBlockMetadata,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "metadata": updatedMetadata
            ]
        )
    }

    private func deleteBlock() {
        NotificationCenter.default.post(
            name: .removeBlock,
            object: nil,
            userInfo: ["blockId": block.id]
        )
    }

    // MARK: - Load Note

    private func loadNote() {
        noteBodyDocument = RichDocumentPersistence.loadBlockDocument(
            key: RichDocumentMetadataKeys.bodyDocument,
            metadata: block.metadata,
            fallbackPlainText: block.metadata["content"]
        )
        noteText = noteBodyDocument.plainText

        // If linked to an atom, load freshest data from database
        if block.entityId > 0 {
            Task {
                do {
                    if let atom = try await AtomRepository.shared.fetch(id: block.entityId) {
                        await MainActor.run {
                            noteBodyDocument = RichDocumentPersistence.loadAtomDocument(
                                field: .body,
                                metadata: atom.metadata,
                                fallbackPlainText: atom.body
                            )
                            noteText = noteBodyDocument.plainText
                        }
                    }
                } catch {
                    print("StickyNote: Failed to load atom: \(error)")
                }
            }
        }
    }

    // MARK: - GRDB Observation

    private func startObservingAtom() {
        let uuid = block.entityUuid
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
                    let newBodyDocument = RichDocumentPersistence.loadAtomDocument(
                        field: .body,
                        metadata: atom.metadata,
                        fallbackPlainText: atom.body
                    )
                    let newBody = newBodyDocument.plainText
                    let bodyChanged = newBody != noteText || newBodyDocument != noteBodyDocument
                    print("[BLOCK-STICKY] 🔔 GRDB observation fired — uuid=\(uuid) isEditingBody=\(isEditingBody) bodyChanged=\(bodyChanged) dbBodyLen=\(newBody.count) localBodyLen=\(noteText.count) dbPreview=\"\(String(newBody.prefix(60)))\"")
                    guard bodyChanged else { return }
                    print("[BLOCK-STICKY] 🔔 observation APPLYING body — uuid=\(uuid) ⚠️ NO isEditingBody guard — overwriting local with dbLen=\(newBody.count)")
                    isSyncingFromDB = true
                    noteBodyDocument = newBodyDocument
                    noteText = newBody
                    DispatchQueue.main.async {
                        isSyncingFromDB = false
                    }
                }
            )
    }

    // MARK: - Auto-save

    private func scheduleAutoSave() {
        print("[BLOCK-STICKY] scheduleAutoSave() — 1s debounce uuid=\(block.entityUuid)")
        autoSaveTask?.cancel()

        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                print("[BLOCK-STICKY] scheduleAutoSave() debounce elapsed, calling saveNote() uuid=\(block.entityUuid)")
                await MainActor.run {
                    saveNote()
                }
            }
        }
    }

    private func saveNote() {
        print("[BLOCK-STICKY] saveNote() — uuid=\(block.entityUuid) bodyLen=\(noteText.count) bodyPreview=\"\(String(noteText.prefix(80)))\" saveClosed=\(saveClosed)")
        // Update block metadata (for SpatialEngine persistence)
        NotificationCenter.default.post(
            name: .updateBlockContent,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "title": "",
                "content": noteText
            ]
        )

        let bodyMetadata = RichDocumentPersistence
            .writeBlockDocument(noteBodyDocument, key: RichDocumentMetadataKeys.bodyDocument, metadata: block.metadata)
        NotificationCenter.default.post(
            name: .updateBlockMetadata,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "metadata": bodyMetadata.merging([
                    "content": noteText
                ]) { _, new in new }
            ]
        )

        // Also update the atom in the database (for blocks linked to entities)
        let uuid = block.entityUuid
        if !uuid.isEmpty {
            Task {
                guard !saveClosed else {
                    print("[BLOCK-STICKY] saveNote() async SKIPPED — saveClosed=true uuid=\(uuid)")
                    return
                }
                print("[BLOCK-STICKY] saveNote() async DB write starting — uuid=\(uuid)")
                do {
                    try await CosmoDatabase.shared.asyncWrite { db in
                        var existingMetadata: String?
                        if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                            existingMetadata = row["metadata"]
                        }
                        let fields = RichDocumentPersistence.writeAtomDocuments(
                            existingMetadata: existingMetadata,
                            titleDocument: nil,
                            bodyDocument: noteBodyDocument
                        )
                        try db.execute(
                            sql: """
                            UPDATE atoms
                            SET body = ?,
                                metadata = ?,
                                updated_at = ?,
                                _local_version = _local_version + 1,
                                _local_pending = 1
                            WHERE uuid = ?
                            """,
                            arguments: [
                                fields.body ?? "",
                                fields.metadata,
                                ISO8601DateFormatter().string(from: Date()),
                                uuid
                            ]
                        )
                    }
                    print("[BLOCK-STICKY] saveNote() async DB write DONE — uuid=\(uuid) ⚠️ NOTE: ChangeTracker NOT called (missing)")
                } catch {
                    print("[BLOCK-STICKY] saveNote() async DB write FAILED — uuid=\(uuid) error=\(error)")
                }
            }
        }
    }

    /// Synchronous save — blocks until DB write completes.
    /// Used on close to guarantee data is persisted before the block exits.
    private func saveNoteSync() {
        let uuid = block.entityUuid
        print("[BLOCK-STICKY] saveNoteSync() — uuid=\(uuid) bodyLen=\(noteText.count) bodyPreview=\"\(String(noteText.prefix(80)))\"")
        guard !uuid.isEmpty else { print("[BLOCK-STICKY] saveNoteSync() SKIPPED — empty uuid"); return }

        do {
            try CosmoDatabase.shared.write { db in
                var existingMetadata: String?
                if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                    existingMetadata = row["metadata"]
                }
                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: existingMetadata,
                    titleDocument: nil,
                    bodyDocument: noteBodyDocument
                )
                try db.execute(
                    sql: """
                    UPDATE atoms
                    SET body = ?,
                        metadata = ?,
                        updated_at = ?,
                        _local_version = _local_version + 1,
                        _local_pending = 1
                    WHERE uuid = ?
                    """,
                    arguments: [
                        fields.body ?? "",
                        fields.metadata,
                        ISO8601DateFormatter().string(from: Date()),
                        uuid
                    ]
                )
            }
        } catch {
            print("StickyNote: sync save failed: \(error)")
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        if block.entityId > 0 {
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: [
                    "type": EntityType.note,
                    "id": block.entityId
                ]
            )
        } else {
            // Create backing atom from current sticky note data, then open
            Task {
                do {
                    var newAtom = Atom.new(
                        type: .stickyNote,
                        title: nil,
                        body: noteText
                    )
                    let fields = RichDocumentPersistence.writeAtomDocuments(
                        existingMetadata: newAtom.metadata,
                        titleDocument: nil,
                        bodyDocument: noteBodyDocument
                    )
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
                    print("StickyNote: Failed to create backing atom: \(error)")
                }
            }
        }
    }
}
