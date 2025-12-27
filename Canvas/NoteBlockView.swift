// CosmoOS/Canvas/NoteBlockView.swift
// Orange-accented Note block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Thinkspace revamp

import SwiftUI

struct NoteBlockView: View {
    let block: CanvasBlock

    @State private var noteTitle: String = ""
    @State private var noteText: String = ""
    @State private var isExpanded = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool

    // Auto-save debouncing
    @State private var autoSaveTask: Task<Void, Never>?

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
        if let title = block.metadata["title"] {
            noteTitle = title
        }
        if let content = block.metadata["content"] {
            noteText = content
        }
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
        NotificationCenter.default.post(
            name: .updateBlockContent,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "title": noteTitle,
                "content": noteText
            ]
        )
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.note,
                "id": block.entityId,
                "blockId": block.id,
                "content": noteText
            ]
        )
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
