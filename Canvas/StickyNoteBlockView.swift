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
            onPlainTextChange: { plainText in
                noteText = plainText
                hasLocalEdits = true
                scheduleAutoSave()
            },
            onDocumentChange: { _, plainText in
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
            isEditingBody = false
            do {
                if let recovery = try CanvasNotePersistence.loadRecovery(blockID: block.id) {
                    noteText = recovery.plainText
                    noteBodyDocument = recovery.document.plainText == recovery.plainText
                        ? recovery.document : RichDocument.migrateLegacy(recovery.plainText)
                    hasLocalEdits = true
                    scheduleAutoSave()
                } else {
                    loadNote()
                }
            } catch {
                PersistenceHealth.note(.writeFailure, context: "stickyNote.recovery", detail: "\(error)")
                loadNote()
            }
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
                saveNoteSync()
                DirtyEditorRegistry.shared.unregister(id: "stickyblock-\(block.id)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isEditingBody = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteFocusStateDidChange)) { notification in
            if let uuid = notification.userInfo?["atomUUID"] as? String,
               uuid == block.entityUuid, !hasLocalEdits {
                if let body = notification.userInfo?["body"] as? String {
                    isSyncingFromDB = true
                    noteText = body
                    if let json = notification.userInfo?["bodyDocumentJSON"] as? String,
                       let document = try? JSONDecoder().decode(RichDocument.self, from: Data(json.utf8)) {
                        noteBodyDocument = document
                    } else {
                        noteBodyDocument = RichDocument.migrateLegacy(body)
                    }
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
        let updatedMetadata = ["stickyColor": newColor.rawValue]
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
            fallbackPlainText: block.metadata["content"],
            atomUUID: block.id
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
            fallbackPlainText: atom.body,
            atomUUID: atom.uuid
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
                fallbackPlainText: atom.body,
                atomUUID: atom.uuid
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
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveNoteSync()
        }
    }

    /// The same atomic commit serves autosave, navigation, and quit. Nothing
    /// deferred can replay an older edit after this transaction completes.
    @discardableResult
    private func saveNoteSync(ensureAtom: Bool = false) -> Atom? {
        guard hasLocalEdits || ensureAtom else { return nil }
        do {
            let saved = try CosmoDatabase.shared.write { db in
                try CanvasNotePersistence.saveSticky(
                    in: db, blockID: block.id, document: noteBodyDocument, plainText: noteText
                )
            }
            hasLocalEdits = false
            do { try CanvasNotePersistence.clearRecovery(blockID: block.id) }
            catch { PersistenceHealth.note(.writeFailure, context: "stickyNote.recoveryCleanup", detail: "\(error)") }
            ThinkspaceCanvasSnapshotCache.shared.invalidate(blockID: block.id)
            CanvasAtomObservationHub.shared.absorb([saved.atom])
            // Notify mounted canvases only after commit. This is a memory
            // refresh, never another database save of a stale block snapshot.
            NotificationCenter.default.post(name: .updateBlockMetadata, object: nil, userInfo: [
                "blockId": block.id, "metadata": saved.metadata, "alreadyPersisted": true
            ])
            NotificationCenter.default.post(name: .updateBlockEntity, object: nil, userInfo: [
                "blockId": block.id, "entityId": saved.atom.id ?? 0,
                "entityUuid": saved.atom.uuid, "alreadyPersisted": true
            ])
            return saved.atom
        } catch {
            do {
                try CanvasNotePersistence.stashRecovery(blockID: block.id, document: noteBodyDocument, plainText: noteText)
            } catch {
                PersistenceHealth.note(.writeFailure, context: "stickyNote.recoveryWrite", detail: "\(error)")
            }
            PersistenceHealth.note(.writeFailure, context: "stickyNote.save", detail: "block=\(block.id): \(error)")
            return nil
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        // Complete the edit and link atomless legacy stickies in the same
        // transaction before opening the document editor.
        autoSaveTask?.cancel()
        let atomID: Int64
        if hasLocalEdits || block.entityId <= 0 {
            guard let saved = saveNoteSync(ensureAtom: true), let id = saved.id else { return }
            atomID = id
        } else {
            atomID = block.entityId
        }
        NotificationCenter.default.post(name: .enterFocusMode, object: nil, userInfo: [
            "type": EntityType.note, "id": atomID
        ])
    }
}
