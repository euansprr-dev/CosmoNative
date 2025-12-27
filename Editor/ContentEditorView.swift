// CosmoOS/Editor/ContentEditorView.swift
// Premium content editor with centered layout matching web app
// Supports / commands + @mentions

import SwiftUI
import AppKit
import GRDB
import Combine

struct ContentEditorView: View {
    let contentId: Int64
    let presentation: EditorPresentation

    @EnvironmentObject var voiceEngine: VoiceEngine

    @State private var title = ""
    @State private var attributedBody = NSAttributedString()
    @State private var plainBody = ""
    @State private var status = "draft"
    @State private var createdAt: Date = Date()
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var observationCancellable: AnyCancellable?
    @State private var isInitialLoad = true

    private let database = CosmoDatabase.shared
    private let autoSaveDelay: TimeInterval = 1.5
    private let contextTracker = EditingContextTracker.shared

    init(contentId: Int64, presentation: EditorPresentation = .focus) {
        self.contentId = contentId
        self.presentation = presentation
    }

    // MARK: - Responsive Layout Properties

    /// Horizontal padding adapts to presentation mode
    private var horizontalPadding: CGFloat {
        presentation == .focus ? 40 : 12
    }

    /// Max width for content - only constrain in focus mode
    private var contentMaxWidth: CGFloat? {
        presentation == .focus ? CosmoTypography.optimalReadingWidth : nil
    }

    /// Top padding for title
    private var topPadding: CGFloat {
        presentation == .focus ? 32 : 8
    }

    /// Title font adapts to presentation
    private var titleFont: Font {
        presentation == .focus ? CosmoTypography.display : CosmoTypography.title
    }

    /// Vertical spacing for editor
    private var editorVerticalPadding: CGFloat {
        presentation == .focus ? 24 : 8
    }

    var body: some View {
        VStack(spacing: 0) {
            // Centered content container
            VStack(spacing: 0) {
                // MARK: - Title (centered, large display font)
                ZStack(alignment: .leading) {
                    if title.isEmpty {
                        Text("Untitled Content")
                            .font(titleFont)
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(titleFont)
                        .foregroundColor(CosmoColors.textPrimary)
                        .onChange(of: title) { _, _ in
                            if !isInitialLoad { triggerAutoSave() }
                        }
                }
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.top, topPadding)
                .padding(.bottom, presentation == .focus ? 12 : 6)

                // MARK: - Date + Status Row (only in focus mode)
                if presentation.showsDateAndTags {
                    HStack(spacing: 16) {
                        // Date
                        Text(createdAt, format: .dateTime.month(.wide).day().year())
                            .font(CosmoTypography.body)
                            .foregroundColor(CosmoColors.textSecondary)

                        // Status badge
                        Text(status.capitalized)
                            .font(CosmoTypography.caption)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusColor.opacity(0.12), in: Capsule())

                        Spacer()
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .padding(.bottom, 24)
                }

                // MARK: - Divider (only in focus mode)
                if presentation == .focus {
                    Rectangle()
                        .fill(CosmoColors.glassGrey.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: contentMaxWidth)
                }

                // MARK: - Main Editor
                // Editor expands to fill available space (Google Docs style)
                RichTextEditor(
                    text: $attributedBody,
                    plainText: $plainBody,
                    placeholder: presentation == .focus
                        ? "Start writing...\n\nTry:\n• Type / for formatting commands\n• Type @ to mention ideas, research, projects, or tasks"
                        : "Start writing...",
                    onSave: { _ in triggerAutoSave() }
                )
                .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, editorVerticalPadding)
                // Extra bottom padding for word count overlay + breathing room
                .padding(.bottom, presentation == .focus ? 60 : editorVerticalPadding)
                .onChange(of: plainBody) { _, _ in
                    if !isInitialLoad { triggerAutoSave() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill available space
            .padding(.horizontal, horizontalPadding)
        }
        // MARK: - Footer Overlay (word count) - floats at bottom, doesn't constrain editor
        .overlay(alignment: .bottom) {
            if presentation == .focus {
                HStack {
                    Spacer()
                    Text("\(wordCount) words")
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                    Text("·")
                        .foregroundColor(CosmoColors.textTertiary)
                    Text("\(plainBody.count) chars")
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [CosmoColors.softWhite.opacity(0), CosmoColors.softWhite],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .offset(y: -20)
                )
            }
        }
        .onAppear {
            startObservingContent()
        }
        .onDisappear {
            observationCancellable?.cancel()
            contextTracker.clearEditingContext()
        }
    }

    // MARK: - Computed
    private var wordCount: Int {
        plainBody.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var statusColor: Color {
        switch status.lowercased() {
        case "published": return CosmoColors.emerald
        case "draft": return CosmoColors.textSecondary
        case "archived": return CosmoColors.glassGrey
        default: return CosmoColors.textSecondary
        }
    }

    // MARK: - Live Observation (2-Way Sync)
    private func startObservingContent() {
        let idToTrack = contentId
        let observation = ValueObservation.tracking { db in
            try Atom
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("id") == idToTrack)
                .fetchOne(db)
                .map { ContentWrapper(atom: $0) }
        }

        observationCancellable = observation.publisher(in: database.dbQueue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ Content observation error: \(error)")
                    }
                },
                receiveValue: { [self] (content: CosmoContent?) in
                    guard let content = content else { return }

                    // Only update UI if content differs (prevents looping)
                    let newBody = content.body ?? ""
                    let contentTitle = content.title ?? ""
                    if newBody != plainBody || contentTitle != title {
                        title = contentTitle
                        plainBody = newBody
                        attributedBody = makeAttributedBody(from: newBody)
                        status = content.status
                        if let date = ISO8601DateFormatter().date(from: content.createdAt) {
                            createdAt = date
                        }
                    }

                    // Update editing context for telepathy/context-aware search
                    contextTracker.updateEditingContext(
                        entityType: .content,
                        entityId: content.id ?? contentId,
                        entityUUID: content.uuid,
                        title: content.title ?? "",
                        content: content.body ?? "",
                        cursorPosition: 0
                    )

                    // Mark initial load complete after first observation
                    if isInitialLoad {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInitialLoad = false
                        }
                    }
                }
            )
    }

    private func triggerAutoSave() {
        autoSaveTask?.cancel()

        // Update editing context immediately for telepathy (before debounce)
        contextTracker.updateEditingContext(
            entityType: .content,
            entityId: contentId,
            entityUUID: nil,
            title: title,
            content: plainBody,
            cursorPosition: 0
        )

        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    saveContent()
                }
            } catch {
                // Cancelled
            }
        }
    }

    private func saveContent() {
        GlobalStatusService.shared.showSaving()

        let currentTitle = title
        let currentBody = plainBody
        let currentContentId = contentId

        Task {
            do {
                try await database.asyncWrite { db in
                    try db.execute(
                        sql: """
                        UPDATE content
                        SET title = ?,
                            body = ?,
                            updated_at = ?,
                            _local_version = _local_version + 1
                        WHERE id = ?
                        """,
                        arguments: [
                            currentTitle,
                            currentBody,
                            ISO8601DateFormatter().string(from: Date()),
                            currentContentId
                        ]
                    )
                }

                await MainActor.run {
                    GlobalStatusService.shared.showSaved()
                }
            } catch {
                print("❌ Failed to save content: \(error)")
                await MainActor.run {
                    GlobalStatusService.shared.showError("Failed to save")
                }
            }
        }
    }

    private func makeAttributedBody(from text: String) -> NSAttributedString {
        // Use CosmoMarkdown to parse formatting (headings, bold, italic, etc.)
        return CosmoMarkdown.parse(text, fontSize: 16)
    }
}
