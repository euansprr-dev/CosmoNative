// CosmoOS/Editor/IdeaEditorView.swift
// Premium idea editor with Apple Notes-quality UX
// Centered layout matching web app quality
// December 2025 - Animated underline, inline save badge, ProMotion springs

import SwiftUI
import GRDB
import Combine

struct IdeaEditorView: View {
    let ideaId: Int64?
    let presentation: EditorPresentation

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var voiceEngine: VoiceEngine

    @State private var title = ""
    @State private var attributedContent = NSAttributedString()
    @State private var plainContent = ""
    @State private var tags: [String] = []
    @State private var createdAt: Date = Date()
    @State private var showTagEditor = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var observationCancellable: AnyCancellable?
    @State private var isInitialLoad = true

    // Premium animation states
    @State private var isTitleFocused = false
    @State private var saveState: SaveState = .idle
    @State private var titleUnderlineProgress: CGFloat = 0
    @State private var contentAppeared = false

    private let database = CosmoDatabase.shared
    private let localLLM = LocalLLM.shared
    private let autoSaveDelay: TimeInterval = 1.5
    private let contextTracker = EditingContextTracker.shared

    /// Save state for inline badge
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    init(ideaId: Int64?, presentation: EditorPresentation = .focus) {
        self.ideaId = ideaId
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
                // MARK: - Title with animated underline
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .leading) {
                        if title.isEmpty {
                            Text("Untitled Idea")
                                .font(titleFont)
                                .foregroundColor(CosmoColors.textTertiary)
                        }
                        TextField("", text: $title, onEditingChanged: { editing in
                            withAnimation(ProMotionSprings.hover) {
                                isTitleFocused = editing
                            }
                            // Animate underline
                            withAnimation(ProMotionSprings.bouncy) {
                                titleUnderlineProgress = editing ? 1 : 0
                            }
                        })
                            .textFieldStyle(.plain)
                            .font(titleFont)
                            .foregroundColor(CosmoColors.textPrimary)
                            .onChange(of: title) { _, _ in
                                if !isInitialLoad { triggerAutoSave() }
                            }
                    }

                    // Animated underline (only in focus mode)
                    if presentation == .focus {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            CosmoMentionColors.idea.opacity(titleUnderlineProgress * 0.8),
                                            CosmoMentionColors.idea.opacity(titleUnderlineProgress * 0.4),
                                            CosmoMentionColors.idea.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * titleUnderlineProgress, height: 2)
                                .shadow(
                                    color: CosmoMentionColors.idea.opacity(titleUnderlineProgress * 0.4),
                                    radius: 4,
                                    y: 2
                                )
                        }
                        .frame(height: 2)
                    }
                }
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.top, topPadding)
                .padding(.bottom, presentation == .focus ? 12 : 6)
                // Staggered entrance (only in focus mode)
                .opacity(presentation == .focus ? (contentAppeared ? 1 : 0) : 1)
                .offset(y: presentation == .focus ? (contentAppeared ? 0 : 12) : 0)
                .blur(radius: presentation == .focus ? (contentAppeared ? 0 : 4) : 0)

                // MARK: - Date + Tags Row (only in focus mode)
                if presentation.showsDateAndTags {
                    HStack(spacing: 16) {
                        // Date
                        Text(createdAt, format: .dateTime.month(.wide).day().year())
                            .font(CosmoTypography.body)
                            .foregroundColor(CosmoColors.textSecondary)

                        // Inline save badge
                        if saveState != .idle {
                            InlineSaveBadge(state: saveState)
                                .transition(.scale.combined(with: .opacity))
                        }

                        // Tags (inline)
                        if !tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(tags.prefix(3), id: \.self) { tag in
                                    Text(tag)
                                        .font(CosmoTypography.caption)
                                        .foregroundColor(CosmoColors.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(CosmoColors.glassGrey.opacity(0.4), in: Capsule())
                                }
                                if tags.count > 3 {
                                    Text("+\(tags.count - 3)")
                                        .font(CosmoTypography.caption)
                                        .foregroundColor(CosmoColors.textTertiary)
                                }
                            }
                        }

                        Button(action: {
                            CosmicHaptics.shared.play(.selection)
                            showTagEditor = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag")
                                    .font(.system(size: 11))
                                    .symbolEffect(.bounce, value: showTagEditor)
                                Text(tags.isEmpty ? "Add tags" : "Edit")
                                    .font(CosmoTypography.caption)
                            }
                            .foregroundColor(CosmoColors.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CosmoColors.glassGrey.opacity(0.25), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .padding(.bottom, 24)
                    // Staggered entrance (delay after title)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 8)
                    .animation(ProMotionSprings.staggered(index: 1), value: contentAppeared)
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
                    text: $attributedContent,
                    plainText: $plainContent,
                    placeholder: presentation == .focus
                        ? "Start writing your idea...\n\nTry:\n• Type / for formatting commands\n• Type @ to mention other ideas, research, or content"
                        : "Start writing...",
                    onSave: { _ in if !isInitialLoad { triggerAutoSave() } }
                )
                .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, editorVerticalPadding)
                // Extra bottom padding for word count overlay + breathing room
                .padding(.bottom, presentation == .focus ? 60 : editorVerticalPadding)
                .onChange(of: plainContent) { _, _ in
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
                    Text("\(plainContent.count) chars")
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
            startObservingIdea()

            // Trigger entrance animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    contentAppeared = true
                }
            }
        }
        .onDisappear {
            observationCancellable?.cancel()
            contextTracker.clearEditingContext()
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(tags: $tags)
        }
    }

    // MARK: - Computed Properties
    private var wordCount: Int {
        plainContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Live Observation (2-Way Sync)
    private func startObservingIdea() {
        guard let id = ideaId else { return }

        let observation = ValueObservation.tracking { db in
            try Atom
                .filter(Column("id") == id)
                .filter(Column("type") == AtomType.idea.rawValue)
                .fetchOne(db)
        }

        observationCancellable = observation.publisher(in: database.dbQueue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ Idea observation error: \(error)")
                    }
                },
                receiveValue: { [self] atom in
                    guard let atom = atom else { return }
                    let idea = IdeaWrapper(atom: atom)

                    // Only update UI if content differs (prevents looping)
                    if idea.content != plainContent || idea.title != title {
                        title = idea.title ?? ""
                        plainContent = idea.content
                        attributedContent = parseMarkdown(idea.content)
                        tags = idea.tagsList
                        if let date = ISO8601DateFormatter().date(from: idea.createdAt) {
                            createdAt = date
                        }
                    }

                    // Update editing context for telepathy/context-aware search
                    contextTracker.updateEditingContext(
                        entityType: .idea,
                        entityId: idea.id ?? 0,
                        entityUUID: idea.uuid,
                        title: idea.title ?? "",
                        content: idea.content,
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

    // MARK: - Save Idea
    private func saveIdea() {
        // Show inline saving badge
        withAnimation(ProMotionSprings.snappy) {
            saveState = .saving
        }

        Task {
            let tagsJSON = tags.isEmpty ? "" : (try? JSONEncoder().encode(tags).base64EncodedString()) ?? ""
            let titleCopy = title
            let contentCopy = plainContent

            do {
                if let id = ideaId {
                    try await database.asyncWrite { db in
                        try db.execute(
                            sql: """
                            UPDATE ideas
                            SET title = ?,
                                content = ?,
                                tags = ?,
                                updated_at = ?,
                                _local_version = _local_version + 1
                            WHERE id = ?
                            """,
                            arguments: [
                                titleCopy.isEmpty ? nil : titleCopy,
                                contentCopy,
                                tagsJSON,
                                ISO8601DateFormatter().string(from: Date()),
                                id
                            ]
                        )
                    }
                } else {
                    // Create new idea using AtomRepository
                    let now = ISO8601DateFormatter().string(from: Date())
                    try await database.asyncWrite { db in
                        try db.execute(
                            sql: """
                            INSERT INTO ideas (uuid, title, content, tags, is_pinned, priority, is_deleted, created_at, updated_at, _local_version, _sync_version)
                            VALUES (?, ?, ?, ?, 0, 'medium', 0, ?, ?, 1, 0)
                            """,
                            arguments: [
                                UUID().uuidString,
                                titleCopy.isEmpty ? nil : titleCopy,
                                contentCopy,
                                "",
                                now,
                                now
                            ]
                        )
                    }
                }

                await MainActor.run {
                    // Show saved badge with haptic
                    CosmicHaptics.shared.play(.success)
                    withAnimation(ProMotionSprings.snappy) {
                        saveState = .saved
                    }

                    // Auto-hide after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(ProMotionSprings.gentle) {
                            saveState = .idle
                        }
                    }
                }
            } catch {
                print("❌ Failed to save idea: \(error)")
                await MainActor.run {
                    CosmicHaptics.shared.play(.error)
                    withAnimation(ProMotionSprings.snappy) {
                        saveState = .idle
                    }
                    GlobalStatusService.shared.showError("Failed to save")
                }
            }
        }
    }

    private func triggerAutoSave() {
        autoSaveTask?.cancel()

        // Update editing context immediately for telepathy (before debounce)
        if let id = ideaId {
            contextTracker.updateEditingContext(
                entityType: .idea,
                entityId: id,
                entityUUID: nil,
                title: title,
                content: plainContent,
                cursorPosition: 0
            )
        }

        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    saveIdea()
                }
            } catch {
                // Cancelled
            }
        }
    }

    // MARK: - Markdown Parsing
    private func parseMarkdown(_ text: String) -> NSAttributedString {
        return CosmoMarkdown.parse(text, fontSize: 15)
    }
}

// MARK: - Premium Paragraph Style
extension CosmoTypography {
    static func bodyParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = bodyLineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func headerParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = titleLineSpacing
        style.paragraphSpacingBefore = 24
        style.paragraphSpacing = 8
        return style
    }
}

// MARK: - Tag Editor Sheet
struct TagEditorSheet: View {
    @Binding var tags: [String]
    @Environment(\.dismiss) var dismiss
    @State private var newTag = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Tags")
                    .font(CosmoTypography.title)
                    .foregroundColor(CosmoColors.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CosmoColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(CosmoColors.glassGrey.opacity(0.3), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                TextField("Add tag...", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(CosmoTypography.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(CosmoColors.glassGrey.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { addTag() }

                Button(action: addTag) {
                    Text("Add")
                        .font(CosmoTypography.label)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(newTag.isEmpty ? CosmoColors.glassGrey : CosmoColors.lavender, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(newTag.isEmpty)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                                .font(CosmoTypography.body)
                                .foregroundColor(CosmoColors.textPrimary)
                            Spacer()
                            Button(action: { removeTag(tag) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(CosmoColors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(CosmoColors.glassGrey.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(height: 200)

            Button(action: { dismiss() }) {
                Text("Done")
                    .font(CosmoTypography.label)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(CosmoColors.lavender, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 340)
        .background(CosmoColors.softWhite)
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
            newTag = ""
        }
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

// MARK: - Inline Save Badge
/// Premium inline save indicator with symbol effects
struct InlineSaveBadge: View {
    let state: IdeaEditorView.SaveState

    @State private var pulseScale: CGFloat = 1.0
    @State private var checkmarkBounce = false

    var body: some View {
        HStack(spacing: 4) {
            Group {
                switch state {
                case .idle:
                    EmptyView()
                case .saving:
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolEffect(.rotate, isActive: true)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(CosmoColors.lavender)
                        .symbolEffect(.bounce, value: checkmarkBounce)
                }
            }
            .font(.system(size: 11, weight: .medium))

            Text(state == .saving ? "Saving..." : "Saved")
                .font(CosmoTypography.caption)
        }
        .foregroundColor(state == .saved ? CosmoColors.lavender : CosmoColors.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    state == .saved
                        ? CosmoColors.lavender.opacity(0.12)
                        : CosmoColors.glassGrey.opacity(0.25)
                )
                .shadow(
                    color: state == .saved ? CosmoColors.lavender.opacity(0.2) : .clear,
                    radius: 4,
                    y: 1
                )
        )
        .scaleEffect(pulseScale)
        .onAppear {
            if state == .saving {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                ) {
                    pulseScale = 1.03
                }
            }
        }
        .onChange(of: state) { _, newState in
            if newState == .saved {
                pulseScale = 1.0
                checkmarkBounce.toggle()
            }
        }
    }
}
