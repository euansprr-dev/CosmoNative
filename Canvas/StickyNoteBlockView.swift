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

    // Guards against stale writes: only save if the user actually edited this block.
    // Without this, onDisappear would write back whatever was loaded from DB,
    // which could be an old version if a GRDB observation update was blocked by
    // isEditingBody (the same bug NoteBlockView fixed; see its saveNoteSync).
    @State private var hasLocalEdits = false

    // Prevents GRDB observation updates from triggering auto-save
    @State private var isSyncingFromDB = false

    // GRDB observation
    @State private var atomSubscription: CanvasAtomSubscription?

    // Visual states
    @State private var isSelected = false
    @State private var isHovered = false
    @Environment(\.canvasBlockSelectionSuppressed) private var selectionNotificationsSuppressed
    @State private var hasAppeared = false

    // Current sticky color
    @State private var stickyColor: StickyNoteColor = .yellow

    private static let stickyFontSize: CGFloat = 15
    /// Hand-lettered font for sticky notes. Preference order picks a readable
    /// display face with character — not a cursive script. Falls back to the
    /// system font if none are available.
    private static let stickyFont: NSFont = {
        let candidates = ["Bradley Hand", "Noteworthy-Light", "Noteworthy", "Marker Felt"]
        for name in candidates {
            if let font = NSFont(name: name, size: Self.stickyFontSize) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: Self.stickyFontSize)
    }()

    var body: some View {
        CosmoDocumentEditor(
            document: $noteBodyDocument,
            fontSize: Self.stickyFontSize,
            compact: true,
            placeholder: "Type here…",
            overrideTextColor: NSColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1),
            overrideFont: Self.stickyFont,
            allowSlashCommands: false,
            allowMentions: isEditingBody,
            allowSelectionMenu: false,
            allowImages: false,
            isEditable: isEditingBody,
            scrollsInternally: true,
            onDocumentChange: { _, plainText in
                print("[BLOCK-STICKY] onDocumentChange — len=\(plainText.count) preview=\"\(String(plainText.prefix(60)))\" isSyncingFromDB=\(isSyncingFromDB) uuid=\(block.entityUuid)")
                noteText = plainText
                if !isSyncingFromDB {
                    hasLocalEdits = true
                    scheduleAutoSave()
                }
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
            guard !selectionNotificationsSuppressed else { return }
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
            // Terminate-safe flush: the 1s debounce loses typing on ⌘Q without this.
            // The flush is dirty-gated inside saveNoteSync (no-op when clean).
            DirtyEditorRegistry.shared.register(id: "stickyblock-\(block.id)") {
                saveNoteSync()
            }
            withAnimation(ProMotionSprings.cardEntrance) {
                hasAppeared = true
            }
        }
        .onDisappear {
            autoSaveTask?.cancel()
            CanvasAtomObservationHub.shared.unsubscribe(atomSubscription)
            atomSubscription = nil
            // Defer sync save by one frame so CosmoDocumentEditor's flushPendingSync()
            // can propagate the latest text via onDocumentChange first.
            DispatchQueue.main.async {
                saveClosed = true
                saveNoteSync()
                DirtyEditorRegistry.shared.unregister(id: "stickyblock-\(block.id)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isEditingBody = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteFocusStateDidChange)) { notification in
            if let uuid = notification.userInfo?["atomUUID"] as? String,
               uuid == block.entityUuid {
                if let body = notification.userInfo?["body"] as? String {
                    isSyncingFromDB = true
                    noteText = body
                    noteBodyDocument = RichDocument.migrateLegacy(body)
                    hasLocalEdits = false
                    DispatchQueue.main.async {
                        isSyncingFromDB = false
                    }
                }
            }
        }
        // Authoritative blocks landed after a thinkspace switch — the mounted view
        // may still hold text from a stale snapshot cache. Re-run the load when
        // there's nothing local to lose. Targeted: a payload of changed block
        // ids scopes the reload to actually-affected views.
        .onReceive(NotificationCenter.default.publisher(for: .canvasBlocksDidResync)) { notification in
            if let changedIds = notification.userInfo?["blockIds"] as? [String],
               !changedIds.contains(block.id) {
                return
            }
            guard !isEditingBody, !hasLocalEdits else { return }
            isSyncingFromDB = true
            loadNote()
            loadColor()
            DispatchQueue.main.async {
                isSyncingFromDB = false
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

        // If linked to an atom, load freshest data — warm store first (the
        // thinkspace switch batch-fetched every entity atom), repository
        // round-trip only as a fallback for blocks outside a snapshot fetch.
        if block.entityId > 0 {
            if let warm = CanvasAtomWarmStore.shared.atom(id: block.entityId) {
                applyLoadedAtom(warm)
            } else {
                Task {
                    do {
                        if let atom = try await AtomRepository.shared.fetch(id: block.entityId) {
                            await MainActor.run {
                                applyLoadedAtom(atom)
                            }
                        }
                    } catch {
                        PersistenceHealth.note(.writeFailure, context: "stickyNote.loadAtom", detail: "uuid=\(block.entityUuid): \(error)")
                        print("StickyNote: Failed to load atom: \(error)")
                    }
                }
            }
        } else {
            // Atomless sticky: canvas_blocks.note_content is the source of truth.
            // The snapshot-cache copy in block.metadata can be stale — re-read it.
            let blockId = block.id
            Task {
                do {
                    let noteContent: String? = try await CosmoDatabase.shared.asyncRead { db in
                        try String.fetchOne(
                            db,
                            sql: "SELECT note_content FROM canvas_blocks WHERE id = ? AND is_deleted = 0",
                            arguments: [blockId]
                        )
                    }
                    guard let noteContent else { return }
                    await MainActor.run {
                        guard !isEditingBody, !hasLocalEdits, noteContent != noteText else { return }
                        isSyncingFromDB = true
                        noteText = noteContent
                        noteBodyDocument = RichDocument.migrateLegacy(noteContent)
                        DispatchQueue.main.async {
                            isSyncingFromDB = false
                        }
                    }
                } catch {
                    PersistenceHealth.note(.writeFailure, context: "stickyNote.loadNoteContent", detail: "block=\(blockId): \(error)")
                    print("StickyNote: Failed to load note_content: \(error)")
                }
            }
        }
    }

    /// Apply a freshly-loaded entity atom to view state. Shared by the warm
    /// store hit (synchronous, at mount) and the repository fallback.
    private func applyLoadedAtom(_ atom: Atom) {
        // Don't clobber text the user typed (or is typing) while
        // the load was in flight — mirror the hub observation.
        guard !isEditingBody, !hasLocalEdits else { return }
        isSyncingFromDB = true
        noteBodyDocument = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        )
        noteText = noteBodyDocument.plainText
        DispatchQueue.main.async {
            isSyncingFromDB = false
        }
    }

    // MARK: - Atom Observation (via shared canvas hub)

    private func startObservingAtom() {
        CanvasAtomObservationHub.shared.unsubscribe(atomSubscription)
        atomSubscription = nil

        let uuid = block.entityUuid
        guard !uuid.isEmpty else { return }

        // One hub observation covers every mounted block; version-keyed dedupe
        // there replaces the old per-block full-atom removeDuplicates.
        atomSubscription = CanvasAtomObservationHub.shared.subscribe(uuid: uuid) { atom in
            let newBodyDocument = RichDocumentPersistence.loadAtomDocument(
                field: .body,
                metadata: atom.metadata,
                fallbackPlainText: atom.body
            )
            let newBody = newBodyDocument.plainText
            let bodyChanged = newBody != noteText || newBodyDocument != noteBodyDocument
            // Only overwrite body from DB when NOT actively editing and
            // there are no unsaved local edits — otherwise the observation
            // echo from auto-save overwrites text the user typed since the
            // save was initiated.
            guard NoteWritePolicy.shouldApplyObservedBody(
                isEditingBody: isEditingBody,
                hasLocalEdits: hasLocalEdits,
                observedBodyChanged: bodyChanged
            ) else { return }
            isSyncingFromDB = true
            noteBodyDocument = newBodyDocument
            noteText = newBody
            hasLocalEdits = false
            DispatchQueue.main.async {
                isSyncingFromDB = false
            }
        }
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
                let savedBodyText = noteText
                print("[BLOCK-STICKY] saveNote() async DB write starting — uuid=\(uuid)")
                do {
                    try await CosmoDatabase.shared.asyncWrite { db in
                        var existingMetadata: String?
                        if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid]) {
                            existingMetadata = row["metadata"]
                        }
                        // Use current plain text for body document to avoid stale metadata
                        let currentBodyDoc = noteBodyDocument.plainText == noteText
                            ? noteBodyDocument
                            : RichDocument.migrateLegacy(noteText)
                        let fields = RichDocumentPersistence.writeAtomDocuments(
                            existingMetadata: existingMetadata,
                            titleDocument: nil,
                            bodyDocument: currentBodyDoc
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
                                noteText,
                                fields.metadata,
                                ISO8601.string(from: Date()),
                                uuid
                            ]
                        )
                    }
                    print("[BLOCK-STICKY] saveNote() async DB write DONE — uuid=\(uuid)")
                    // Sync to Supabase via ChangeTracker
                    var atomWasUpdated = false
                    if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                        atomWasUpdated = true
                        // skipVersionIncrement: raw SQL already did _local_version + 1
                        await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                    }
                    await MainActor.run {
                        // Atomless stickies persist via the .updateBlockContent
                        // notification round-trip — keep the dirty flag so the
                        // close/terminate sync write remains their safety net.
                        if atomWasUpdated, noteText == savedBodyText {
                            hasLocalEdits = false
                        }
                    }
                } catch {
                    PersistenceHealth.note(.writeFailure, context: "stickyNote.autosave", detail: "uuid=\(uuid): \(error)")
                    print("[BLOCK-STICKY] saveNote() async DB write FAILED — uuid=\(uuid) error=\(error)")
                }
            }
        }
    }

    /// Synchronous save — blocks until DB write completes.
    /// Used on close to guarantee data is persisted before the block exits.
    private func saveNoteSync() {
        let uuid = block.entityUuid
        print("[BLOCK-STICKY] saveNoteSync() — uuid=\(uuid) bodyLen=\(noteText.count) hasLocalEdits=\(hasLocalEdits) bodyPreview=\"\(String(noteText.prefix(80)))\"")
        guard !uuid.isEmpty else { print("[BLOCK-STICKY] saveNoteSync() SKIPPED — empty uuid"); return }
        // Only write if the user actually made edits in this block. Without this
        // guard, onDisappear would write back stale state (e.g. focus mode saved
        // newer text while isEditingBody blocked the GRDB observation, then this
        // close save resurrected the old version over it).
        guard hasLocalEdits else {
            print("[BLOCK-STICKY] saveNoteSync() SKIPPED — no local edits, avoiding stale overwrite uuid=\(uuid)")
            return
        }

        // Canonicalize: noteBodyDocument's serialization can lag the per-keystroke
        // noteText by ~150ms — never persist a metadata document that diverges
        // from the body text being written.
        let currentBodyDoc = noteBodyDocument.plainText == noteText
            ? noteBodyDocument
            : RichDocument.migrateLegacy(noteText)
        let blockMetadata = RichDocumentPersistence
            .writeBlockDocument(currentBodyDoc, key: RichDocumentMetadataKeys.bodyDocument, metadata: block.metadata)
            .merging(["content": noteText]) { _, new in new }
        let blockMetadataJSON = SpatialEngine.encodeBlockMetadataJSON(blockMetadata)

        do {
            let atomExisted = try CosmoDatabase.shared.write { db -> Bool in
                // Always persist to canvas_blocks — this is the primary storage
                // path for sticky notes (which may not have a backing atom row).
                // note_content and the metadata column move together so neither
                // can resurrect stale text over the other on the next load.
                try db.execute(
                    sql: """
                    UPDATE canvas_blocks
                    SET note_content = ?, metadata = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE entity_uuid = ? AND is_deleted = 0
                    """,
                    arguments: [noteText, blockMetadataJSON, uuid]
                )

                // Also update the atom row whenever one exists (its metadata may
                // legitimately be NULL — that must not skip the body update).
                let atomRow = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [uuid])
                guard let atomRow else { return false }
                let existingMetadata: String? = atomRow["metadata"]
                let fields = RichDocumentPersistence.writeAtomDocuments(
                    existingMetadata: existingMetadata,
                    titleDocument: nil,
                    bodyDocument: currentBodyDoc
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
                        noteText,
                        fields.metadata,
                        ISO8601.string(from: Date()),
                        uuid
                    ]
                )
                return true
            }
            hasLocalEdits = false
            if atomExisted {
                // Queue for Supabase push so the close-time edit reaches the cloud.
                Task {
                    if let updatedAtom = try? await AtomRepository.shared.fetch(uuid: uuid) {
                        // skipVersionIncrement: raw SQL already did _local_version + 1
                        await ChangeTracker.shared.trackUpdate(table: "atoms", entity: updatedAtom, skipVersionIncrement: true)
                    }
                }
            }
        } catch {
            PersistenceHealth.note(.writeFailure, context: "stickyNote.closeSave", detail: "uuid=\(uuid): \(error)")
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
                    newAtom.body = noteText
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
                    PersistenceHealth.note(.writeFailure, context: "stickyNote.createBackingAtom", detail: "block=\(block.id): \(error)")
                    print("StickyNote: Failed to create backing atom: \(error)")
                }
            }
        }
    }
}
