// CosmoOS/UI/FocusMode/Notes/NoteFocusModeView.swift
// Full-screen dark-themed writing surface for ideas/notes
// February 2026 - Focus mode with GRDB observation + 1.5s debounce auto-save

import SwiftUI
import GRDB
import Combine

struct NoteFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._floatingBlocksManager = StateObject(wrappedValue: FocusFloatingBlocksManager(ownerAtomUUID: atom.uuid))
    }

    // MARK: - State

    @StateObject private var floatingBlocksManager: FocusFloatingBlocksManager

    @State private var title: String = ""
    @State private var attributedContent = NSAttributedString()
    @State private var plainContent: String = ""
    @State private var tags: [String] = []
    @State private var createdAt: Date = Date()
    @State private var showTagEditor = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var observationCancellable: AnyCancellable?
    @State private var isInitialLoad = true

    // Animation states
    @State private var contentAppeared = false
    @State private var isTitleFocused = false
    @State private var titleUnderlineProgress: CGFloat = 0

    // Save state
    @State private var saveState: SaveState = .idle

    private let database = CosmoDatabase.shared
    private let autoSaveDelay: TimeInterval = 1.5

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full-bleed dark background
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                // Top bar with gradient
                topBar

                // Scrollable writing surface
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Title field
                            titleSection
                                .padding(.top, 32)

                            // Date + tags row
                            dateTagsRow
                                .padding(.top, 12)
                                .padding(.bottom, 24)

                            // Divider
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                                .frame(maxWidth: CosmoTypography.optimalReadingWidth)

                            // Rich text editor — use remaining height so it fills the page
                            RichTextEditor(
                                text: $attributedContent,
                                plainText: $plainContent,
                                placeholder: "Start writing......",
                                darkMode: true,
                                onSave: { _ in if !isInitialLoad { triggerAutoSave() } }
                            )
                            .frame(maxWidth: CosmoTypography.optimalReadingWidth, alignment: .topLeading)
                            .frame(minHeight: max(400, geometry.size.height - 200))
                            .padding(.top, 24)
                            .padding(.bottom, 60)
                            .onChange(of: plainContent) { _, _ in
                                if !isInitialLoad { triggerAutoSave() }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 40)
                    }
                }
            }

            // Persistent floating blocks overlay
            GeometryReader { geo in
                FocusFloatingBlocksLayer(manager: floatingBlocksManager)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            // Footer overlay
            VStack {
                Spacer()
                footerBar
            }
        }
        .focusBlockContextMenu(
            manager: floatingBlocksManager,
            ownerAtomUUID: atom.uuid
        )
        .onAppear {
            startObservingAtom()
            listenForAtomPicker()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    contentAppeared = true
                }
            }
            // Safety fallback: ensure isInitialLoad clears even if GRDB observation
            // never fires (e.g. atom deleted between load and observation start)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if isInitialLoad {
                    isInitialLoad = false
                }
            }
        }
        .onDisappear {
            // Force an immediate save before closing — don't lose unsaved edits
            autoSaveTask?.cancel()
            saveAtomImmediately()
            floatingBlocksManager.saveImmediately()
            observationCancellable?.cancel()
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorSheet(tags: $tags)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Close button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            // Type badge
            HStack(spacing: 4) {
                Image(systemName: "note.text")
                    .font(.system(size: 10))
                Text("NOTE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundColor(CosmoColors.blockNote)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CosmoColors.blockNote.opacity(0.15), in: Capsule())

            // Save indicator
            if saveState != .idle {
                noteSaveBadge
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    CosmoColors.thinkspaceVoid.opacity(0.95),
                    CosmoColors.thinkspaceVoid.opacity(0.8),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                if title.isEmpty {
                    Text("Untitled Note")
                        .font(CosmoTypography.display)
                        .foregroundColor(.white.opacity(0.25))
                }
                TextField("", text: $title, onEditingChanged: { editing in
                    withAnimation(ProMotionSprings.hover) {
                        isTitleFocused = editing
                    }
                    withAnimation(ProMotionSprings.bouncy) {
                        titleUnderlineProgress = editing ? 1 : 0
                    }
                })
                .textFieldStyle(.plain)
                .font(CosmoTypography.display)
                .foregroundColor(.white)
                .onChange(of: title) { _, _ in
                    if !isInitialLoad { triggerAutoSave() }
                }
            }

            // Animated underline
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CosmoColors.blockNote.opacity(titleUnderlineProgress * 0.8),
                                CosmoColors.blockNote.opacity(titleUnderlineProgress * 0.4),
                                CosmoColors.blockNote.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * titleUnderlineProgress, height: 2)
                    .shadow(
                        color: CosmoColors.blockNote.opacity(titleUnderlineProgress * 0.4),
                        radius: 4,
                        y: 2
                    )
            }
            .frame(height: 2)
        }
        .frame(maxWidth: CosmoTypography.optimalReadingWidth, alignment: .leading)
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 12)
        .blur(radius: contentAppeared ? 0 : 4)
    }

    // MARK: - Date + Tags Row

    private var dateTagsRow: some View {
        HStack(spacing: 16) {
            // Date
            Text(createdAt, format: .dateTime.month(.wide).day().year())
                .font(CosmoTypography.body)
                .foregroundColor(.white.opacity(0.5))

            // Tags
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(CosmoTypography.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(CosmoTypography.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }

            Button(action: {
                showTagEditor = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                        .symbolEffect(.bounce, value: showTagEditor)
                    Text(tags.isEmpty ? "Add tags" : "Edit")
                        .font(CosmoTypography.caption)
                }
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: CosmoTypography.optimalReadingWidth, alignment: .leading)
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 8)
        .animation(ProMotionSprings.staggered(index: 1), value: contentAppeared)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Spacer()
            Text("\(wordCount) words")
                .font(CosmoTypography.caption)
                .foregroundColor(.white.opacity(0.3))
            Text("·")
                .foregroundColor(.white.opacity(0.3))
            Text("\(plainContent.count) chars")
                .font(CosmoTypography.caption)
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, CosmoColors.thinkspaceVoid],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .offset(y: -20)
        )
    }

    // MARK: - Save Badge

    private var noteSaveBadge: some View {
        HStack(spacing: 4) {
            Group {
                switch saveState {
                case .idle:
                    EmptyView()
                case .saving:
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolEffect(.rotate, isActive: true)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(CosmoColors.blockNote)
                        .symbolEffect(.bounce, value: saveState == .saved)
                }
            }
            .font(.system(size: 11, weight: .medium))

            Text(saveState == .saving ? "Saving..." : "Saved")
                .font(CosmoTypography.caption)
        }
        .foregroundColor(saveState == .saved ? CosmoColors.blockNote : .white.opacity(0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    saveState == .saved
                        ? CosmoColors.blockNote.opacity(0.15)
                        : Color.white.opacity(0.08)
                )
        )
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        plainContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Floating Block Listeners

    /// Listen for atom picker notifications to add existing atoms as floating blocks
    private func listenForAtomPicker() {
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.FocusMode.addAtomAsFloatingBlock,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let atomUUID = userInfo["atomUUID"] as? String,
                  let atomTypeRaw = userInfo["atomType"] as? String,
                  let atomType = AtomType(rawValue: atomTypeRaw),
                  let title = userInfo["title"] as? String else { return }

            let position = CGPoint(
                x: 500 + CGFloat.random(in: -60...60),
                y: 300 + CGFloat.random(in: -60...60)
            )

            floatingBlocksManager.addBlock(
                linkedAtomUUID: atomUUID,
                linkedAtomType: atomType,
                title: title,
                position: position
            )
        }
    }

    // MARK: - GRDB Live Observation

    private func startObservingAtom() {
        let uuid = atom.uuid

        let observation = ValueObservation.tracking { db in
            try Atom
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }

        observationCancellable = observation.publisher(in: database.dbQueue)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Note observation error: \(error)")
                    }
                },
                receiveValue: { [self] fetchedAtom in
                    guard let fetchedAtom = fetchedAtom else { return }

                    // Only update if content differs to prevent loops
                    if fetchedAtom.content != plainContent || fetchedAtom.title != title {
                        title = fetchedAtom.title ?? ""
                        plainContent = fetchedAtom.content
                        attributedContent = CosmoMarkdown.parse(fetchedAtom.content, fontSize: 15)
                        tags = fetchedAtom.tagsList
                        if let date = ISO8601DateFormatter().date(from: fetchedAtom.createdAt) {
                            createdAt = date
                        }
                    }

                    if isInitialLoad {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInitialLoad = false
                        }
                    }
                }
            )
    }

    // MARK: - Auto-Save

    private func triggerAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { saveAtom() }
            } catch {
                // Cancelled
            }
        }
    }

    /// Debounced save with UI feedback (used during editing)
    private func saveAtom() {
        withAnimation(ProMotionSprings.snappy) {
            saveState = .saving
        }
        performSave { success in
            if success {
                withAnimation(ProMotionSprings.snappy) {
                    saveState = .saved
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(ProMotionSprings.gentle) {
                        saveState = .idle
                    }
                }
            } else {
                withAnimation(ProMotionSprings.snappy) {
                    saveState = .idle
                }
            }
        }
    }

    /// Immediate save without UI feedback (used on close)
    private func saveAtomImmediately() {
        performSave(completion: nil)
    }

    /// Core save logic — writes to DB using atom UUID (never fails due to nil id)
    private func performSave(completion: ((Bool) -> Void)?) {
        let titleCopy = title
        let contentCopy = plainContent
        let uuid = atom.uuid

        Task {
            do {
                try await database.asyncWrite { db in
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
                            titleCopy.isEmpty ? nil : titleCopy,
                            contentCopy,
                            ISO8601DateFormatter().string(from: Date()),
                            uuid
                        ]
                    )
                }
                // Notify floating blocks to reload immediately (GRDB observation is backup)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .noteFocusStateDidChange,
                        object: nil,
                        userInfo: ["atomUUID": uuid, "title": titleCopy, "body": contentCopy]
                    )
                }
                if let completion {
                    await MainActor.run { completion(true) }
                }
            } catch {
                print("Failed to save note: \(error)")
                if let completion {
                    await MainActor.run { completion(false) }
                }
            }
        }
    }
}
