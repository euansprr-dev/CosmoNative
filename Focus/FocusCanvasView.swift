// CosmoOS/Focus/FocusCanvasView.swift
// Premium full-screen editor with floating blocks
// Clean, centered layout matching web app quality

import SwiftUI
import AppKit
import GRDB

/// Full-screen focus mode editor with optional floating blocks
/// Right-click anywhere to add floating notes, ideas, or tasks
/// Uses unified canvas block system (DocumentBlocksLayer) for consistency with home canvas
/// Supports infinite horizontal panning with recenter functionality
struct FocusCanvasView: View {
    let entity: EntitySelection

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoiceEngine
    @EnvironmentObject var database: CosmoDatabase

    // Use unified canvas blocks layer (same system as home canvas)
    @State private var documentBlocksLayer: DocumentBlocksLayer?

    // Voice state
    @State private var isVoiceActive = false
    @State private var voiceStatus = ""

    // Animation state
    @State private var isAppearing = false
    @State private var editorAppeared = false

    // Atom for new Focus Mode views (Research/Connection)
    @State private var loadedAtom: Atom?

    // MARK: - Infinite Canvas State
    /// Horizontal offset for infinite panning (like home canvas)
    @State private var canvasOffset: CGSize = .zero
    /// Gesture state for smooth panning
    @GestureState private var panOffset: CGSize = .zero

    /// Distance from center to show recenter button
    private var distanceFromCenter: CGFloat {
        let totalOffsetX = canvasOffset.width + panOffset.width
        return abs(totalOffsetX)
    }

    init(entity: EntitySelection) {
        self.entity = entity
    }

    /// Whether this entity type uses a full-canvas focus mode (no wrapper needed)
    private var isFullCanvasMode: Bool {
        entity.type == .connection || entity.type == .research || entity.type == .idea || entity.type == .content || entity.type == .note || entity.type == .cosmoAI
    }

    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let totalHorizontalOffset = canvasOffset.width + panOffset.width

            // Full-canvas modes (Connection, Research) render directly without wrapper
            if isFullCanvasMode {
                fullCanvasModeView
            } else {
                // Standard focus mode with wrapper
                ZStack {
                    // MARK: - Base Surface
                    CosmoColors.softWhite
                        .ignoresSafeArea()

                    // Subtle ambient glow (moves with canvas for parallax effect)
                    AmbientFocusBackground(geometry: geometry)
                        .opacity(0.2)
                        .offset(x: totalHorizontalOffset * 0.1) // Subtle parallax

                    // MARK: - Full-screen Editor (with horizontal offset for infinite canvas)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Top padding for header
                            Spacer()
                                .frame(height: 72)

                            editorView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .scaleEffect(editorAppeared ? 1.0 : 0.98)
                                .opacity(editorAppeared ? 1.0 : 0)

                            // Minimal bottom padding - text extends to bottom
                            Spacer()
                                .frame(height: 20)
                        }
                        .frame(minHeight: geometry.size.height, alignment: .top)
                    }
                    .offset(x: totalHorizontalOffset) // Apply horizontal pan offset
                    .background(
                        // Invisible tap target to blur floating blocks
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Blur all floating blocks when clicking in editor area
                                NotificationCenter.default.post(name: .blurAllBlocks, object: nil)
                            }
                    )

                    // MARK: - User-Placed Floating Blocks (above editor)
                    // Uses unified DocumentBlocksLayer (same block system as home canvas)
                    // Pinned blocks move with canvas, unpinned blocks stay fixed on viewport
                    DocumentBlocksLayer(
                        documentType: entity.type.rawValue,
                        documentId: entity.id,
                        canvasCenter: screenCenter,
                        canvasOffset: CGSize(width: totalHorizontalOffset, height: 0)
                    )
                    .environmentObject(database)
                    .offset(x: totalHorizontalOffset) // Apply horizontal pan offset to floating blocks
                    // NOTE: Unpinned blocks subtract this offset internally to stay fixed on screen
                    .zIndex(100) // Ensure floating blocks appear above editor

                    // MARK: - Header + Footer Overlays (fixed position, don't move with canvas)
                    VStack {
                        HStack(alignment: .top) {
                            FocusCanvasHeader(
                                entity: entity,
                                isVoiceActive: isVoiceActive,
                                voiceStatus: voiceStatus,
                                onClose: closeFocusMode
                            )

                            Spacer()

                            // MARK: - Recenter Button (appears when panned far from center)
                            if distanceFromCenter > 200 {
                                FocusRecenterButton {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                        canvasOffset = .zero
                                    }
                                }
                                .padding(.top, 20)
                                .padding(.trailing, 20)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }

                        Spacer()

                        FocusCanvasFooter()
                    }
                }
                // MARK: - Pan Gesture for Infinite Horizontal Scrolling (standard mode only)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .updating($panOffset) { value, state, _ in
                            // Only allow horizontal panning (vertical is handled by ScrollView)
                            state = CGSize(width: value.translation.width, height: 0)
                        }
                        .onEnded { value in
                            // Commit the horizontal pan offset
                            canvasOffset.width += value.translation.width
                        }
                )
                // Right-click context menu for adding floating blocks (standard mode only)
                .contextMenu {
                    Button {
                        addFocusBlock(type: .note, title: "Note", at: screenCenter.applying(.init(translationX: -200, y: 0)))
                    } label: {
                        Label("Add Note", systemImage: "note.text")
                    }

                    Button {
                        addFocusBlock(type: .idea, title: "Idea", at: screenCenter.applying(.init(translationX: 200, y: 0)))
                    } label: {
                        Label("Add Idea", systemImage: "lightbulb")
                    }

                    Button {
                        addFocusBlock(type: .task, title: "Task", at: screenCenter.applying(.init(translationX: 0, y: -150)))
                    } label: {
                        Label("Add Task", systemImage: "checkmark.circle")
                    }

                    Divider()

                    Button {
                        addCosmoAIBlock(at: screenCenter.applying(.init(translationX: 150, y: 100)))
                    } label: {
                        Label("Add AI Researcher", systemImage: "brain.head.profile")
                    }
                }
            }
        }
        .onAppear {
            setupFocusMode()
        }
        .onDisappear {
            cleanupFocusMode()
        }
    }

    // MARK: - Full Canvas Mode View
    /// Renders full-canvas focus modes (Connection, Research) directly without wrapper
    @ViewBuilder
    private var fullCanvasModeView: some View {
        switch entity.type {
        case .idea:
            if let atom = loadedAtom {
                IdeaFocusModeView(atom: atom, onClose: closeFocusMode)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    CosmoColors.thinkspaceVoid.ignoresSafeArea()
                    ProgressView("Loading...")
                        .tint(.white)
                }
                .onAppear { loadAtomForFocusMode() }
            }
        case .research:
            if let atom = loadedAtom {
                if atom.isSwipeFileAtom {
                    SwipeStudyFocusModeView(atom: atom, onClose: closeFocusMode)
                        .ignoresSafeArea()
                } else {
                    ResearchFocusModeView(atom: atom, onClose: closeFocusMode)
                        .ignoresSafeArea()
                }
            } else {
                ZStack {
                    CosmoColors.thinkspaceVoid.ignoresSafeArea()
                    ProgressView("Loading...")
                        .tint(.white)
                }
                .onAppear { loadAtomForFocusMode() }
            }
        case .connection:
            if let atom = loadedAtom {
                ConnectionFocusModeView(atom: atom, onClose: closeFocusMode)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    CosmoColors.thinkspaceVoid.ignoresSafeArea()
                    ProgressView("Loading...")
                        .tint(.white)
                }
                .onAppear { loadAtomForFocusMode() }
            }
        case .content:
            if let atom = loadedAtom {
                ContentFocusModeView(atom: atom, onClose: closeFocusMode)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    CosmoColors.thinkspaceVoid.ignoresSafeArea()
                    ProgressView("Loading...")
                        .tint(.white)
                }
                .onAppear { loadAtomForFocusMode() }
            }
        case .note:
            if let atom = loadedAtom {
                NoteFocusModeView(atom: atom, onClose: closeFocusMode)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    CosmoColors.thinkspaceVoid.ignoresSafeArea()
                    ProgressView("Loading...")
                        .tint(.white)
                }
                .onAppear { loadAtomForFocusMode() }
            }
        case .cosmoAI:
            if let atom = loadedAtom {
                CosmoAIFocusModeView(atom: atom, onClose: closeFocusMode)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    CosmoColors.thinkspaceVoid.ignoresSafeArea()
                    ProgressView("Loading...")
                        .tint(.white)
                }
                .onAppear { loadAtomForFocusMode() }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Editor View
    @ViewBuilder
    private var editorView: some View {
        switch entity.type {
        case .idea:
            IdeaEditorView(ideaId: entity.id)
                .environmentObject(voiceEngine)
        case .content:
            ContentEditorView(contentId: entity.id)
                .environmentObject(voiceEngine)
        case .research, .connection, .cosmoAI:
            // Handled by fullCanvasModeView
            EmptyView()
        default:
            GenericEntityEditor(entity: entity)
        }
    }

    // MARK: - Atom Loading
    private func loadAtomForFocusMode() {
        Task {
            do {
                if entity.id > 0, let atom = try await AtomRepository.shared.fetch(id: entity.id) {
                    await MainActor.run {
                        loadedAtom = atom
                    }
                } else {
                    // Entity has no backing atom (id <= 0) — create one
                    let atomType = AtomType(rawValue: entity.type.rawValue) ?? .idea
                    let newAtom = try await AtomRepository.shared.create(type: atomType, title: "Untitled \(entity.type.rawValue.capitalized)")
                    await MainActor.run {
                        loadedAtom = newAtom
                    }
                }
            } catch {
                print("❌ loadAtomForFocusMode failed: \(error)")
            }
        }
    }

    // MARK: - Actions
    private func closeFocusMode() {
        // Block persistence is automatic via DocumentBlocksLayer/SpatialEngine
        withAnimation(.spring(response: 0.3)) {
            appState.focusedEntity = nil
        }
    }

    // Add a floating block using unified canvas block system
    private func addFocusBlock(type: EntityType, title: String, at position: CGPoint) {
        Task {
            // Create block record directly in database
            do {
                var entityId: Int64 = -1
                var entityUUID = UUID().uuidString

                // Create entity based on type using AtomRepository
                switch type {
                case .idea:
                    if let atom = try? await AtomRepository.shared.createIdea(title: title, content: "") {
                        entityId = atom.id ?? -1
                        entityUUID = atom.uuid
                    }
                case .task:
                    if let atom = try? await AtomRepository.shared.createTask(title: title) {
                        entityId = atom.id ?? -1
                        entityUUID = atom.uuid
                    }
                default:
                    break
                }

                // Create canvas block record
                // Default to unpinned (stays fixed on screen, doesn't scroll with content)
                let record = CanvasBlockRecord(
                    id: UUID().uuidString,
                    uuid: entityUUID,
                    userId: nil,
                    documentType: entity.type.rawValue,
                    documentId: Int(entity.id),
                    documentUuid: nil,
                    entityId: Int(entityId),
                    entityUuid: entityUUID,
                    entityType: type.rawValue,
                    entityTitle: title,
                    positionX: Int(position.x),
                    positionY: Int(position.y),
                    width: 240,
                    height: 180,
                    isCollapsed: false,
                    zone: nil,
                    noteContent: nil,
                    zIndex: 0,
                    isPinned: false,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    updatedAt: ISO8601DateFormatter().string(from: Date()),
                    syncedAt: nil,
                    isDeleted: false,
                    localVersion: 1,
                    serverVersion: 0,
                    syncVersion: 0,
                    localPending: 0
                )

                try await database.asyncWrite { db in
                    let mutableRecord = record
                    try mutableRecord.insert(db)
                }

                // Notify DocumentBlocksLayer to reload blocks
                NotificationCenter.default.post(
                    name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                    object: nil
                )

                print("✅ Added focus block: \(type.rawValue) - \(title)")
            } catch {
                print("❌ Failed to add focus block: \(error)")
            }
        }
    }

    /// Add a Cosmo AI block to the focus mode document
    private func addCosmoAIBlock(at position: CGPoint, query: String? = nil, mode: String? = nil) {
        Task {
            do {
                let entityUUID = UUID().uuidString

                // Build metadata JSON for AI block state
                var metadata: [String: String] = [
                    "mode": mode ?? "idle",
                    "created": ISO8601DateFormatter().string(from: Date())
                ]
                if let query = query, !query.isEmpty {
                    metadata["query"] = query
                }
                let metadataJSON = try? JSONEncoder().encode(metadata)
                let metadataString = metadataJSON.flatMap { String(data: $0, encoding: .utf8) }

                // Create canvas block record for AI block
                // Default to unpinned (stays fixed on screen)
                let record = CanvasBlockRecord(
                    id: UUID().uuidString,
                    uuid: entityUUID,
                    userId: nil,
                    documentType: entity.type.rawValue,
                    documentId: Int(entity.id),
                    documentUuid: nil,
                    entityId: -1,  // AI blocks don't link to database entities
                    entityUuid: entityUUID,
                    entityType: EntityType.cosmoAI.rawValue,
                    entityTitle: "Cosmo AI",
                    positionX: Int(position.x),
                    positionY: Int(position.y),
                    width: 320,
                    height: 280,
                    isCollapsed: false,
                    zone: nil,
                    noteContent: metadataString,  // Store metadata in noteContent field
                    zIndex: 10,
                    isPinned: false,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    updatedAt: ISO8601DateFormatter().string(from: Date()),
                    syncedAt: nil,
                    isDeleted: false,
                    localVersion: 1,
                    serverVersion: 0,
                    syncVersion: 0,
                    localPending: 0
                )

                try await database.asyncWrite { db in
                    let mutableRecord = record
                    try mutableRecord.insert(db)
                }

                // Notify DocumentBlocksLayer to reload blocks
                NotificationCenter.default.post(
                    name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                    object: nil
                )

                if let query = query, !query.isEmpty {
                    print("✅ Added Cosmo AI block with query: \(query)")
                } else {
                    print("✅ Added Cosmo AI block to focus document")
                }
            } catch {
                print("❌ Failed to add Cosmo AI block: \(error)")
            }
        }
    }

    private func setupFocusMode() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isAppearing = true
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
            editorAppeared = true
        }

        // DocumentBlocksLayer handles its own loading via .task modifier

        // Eagerly load atom for full canvas modes
        if isFullCanvasMode && loadedAtom == nil {
            loadAtomForFocusMode()
        }

        setupVoiceListeners()
    }

    private func cleanupFocusMode() {
        // DocumentBlocksLayer auto-saves via SpatialEngine
        cleanupVoiceListeners()
    }

    // MARK: - Voice Listeners
    private func setupVoiceListeners() {
        // Remove any existing observers first to prevent duplicates
        cleanupVoiceListeners()

        NotificationCenter.default.addObserver(
            forName: .voiceRecordingStateChanged,
            object: nil,
            queue: .main
        ) { [self] notification in
            let isRecording = notification.userInfo?["isRecording"] as? Bool
            Task { @MainActor in
                if let isRecording {
                isVoiceActive = isRecording
                if !isRecording { voiceStatus = "" }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .voiceTranscription,
            object: nil,
            queue: .main
        ) { [self] notification in
            let text = notification.userInfo?["text"] as? String
            Task { @MainActor in
                if let text {
                voiceStatus = text
                }
            }
        }

        // Listen for "bring related blocks" voice command
        NotificationCenter.default.addObserver(
            forName: .bringRelatedBlocks,
            object: nil,
            queue: .main
        ) { [self] notification in
            let quantity = notification.userInfo?["quantity"] as? Int ?? 3
            let entityType = notification.userInfo?["entityType"] as? String ?? "idea"
            let query = notification.userInfo?["query"] as? String ?? entity.type.rawValue
            Task { @MainActor in
                handleBringRelatedBlocks(quantity: quantity, entityType: entityType, query: query)
            }
        }

        // Listen for exit focus mode command
        NotificationCenter.default.addObserver(
            forName: .exitFocusMode,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
            closeFocusMode()
            }
        }

        // Listen for @mention clicks to open as floating blocks
        NotificationCenter.default.addObserver(
            forName: .openMentionAsFloatingBlock,
            object: nil,
            queue: .main
        ) { [self] notification in
            let entityType = notification.userInfo?["entityType"] as? EntityType
            let entityId = notification.userInfo?["entityId"] as? Int64
            Task { @MainActor in
                if let entityType, let entityId {
                    await createFloatingBlockFromEntity(type: entityType, id: entityId)
                }
            }
        }

        // Listen for createEntityInFocusMode from Command Hub single-click or forwarded from CanvasView
        NotificationCenter.default.addObserver(
            forName: .createEntityInFocusMode,
            object: nil,
            queue: .main
        ) { [self] notification in
            let entityType = notification.userInfo?["type"] as? EntityType
            let entityId = notification.userInfo?["id"] as? Int64
            let position = notification.userInfo?["position"] as? CGPoint
            let prefillContent = notification.userInfo?["content"] as? String
            let prefillTitle = notification.userInfo?["title"] as? String

            Task { @MainActor in
                if let entityType {
                    if let entityId {
                        // Open existing entity as floating block
                        await createFloatingBlockFromEntity(type: entityType, id: entityId)
                    } else {
                        // Create NEW entity as floating block
                        let title = prefillTitle ?? "New \(entityType.rawValue.capitalized)"
                        let blockPosition = position ?? CGPoint(
                            x: 500 + CGFloat.random(in: -50...50),
                            y: 400 + CGFloat.random(in: -50...50)
                        )
                        await createNewFloatingBlock(type: entityType, title: title, content: prefillContent, at: blockPosition)
                    }
                }
            }
        }

        // Listen for Cosmo AI block creation (redirected from main canvas when in focus mode)
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.Canvas.createCosmoAIBlock,
            object: nil,
            queue: .main
        ) { [self] notification in
            let position = notification.userInfo?["position"] as? CGPoint
            let query = notification.userInfo?["query"] as? String
            let mode = notification.userInfo?["mode"] as? String

            Task { @MainActor in
                let blockPosition = position ?? CGPoint(
                    x: 500 + CGFloat.random(in: -50...50),
                    y: 400 + CGFloat.random(in: -50...50)
                )
                addCosmoAIBlock(at: blockPosition, query: query, mode: mode)
            }
        }
    }

    private func cleanupVoiceListeners() {
        NotificationCenter.default.removeObserver(self, name: .voiceRecordingStateChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .voiceTranscription, object: nil)
        NotificationCenter.default.removeObserver(self, name: .bringRelatedBlocks, object: nil)
        NotificationCenter.default.removeObserver(self, name: .exitFocusMode, object: nil)
        NotificationCenter.default.removeObserver(self, name: .openMentionAsFloatingBlock, object: nil)
        NotificationCenter.default.removeObserver(self, name: .createEntityInFocusMode, object: nil)
        NotificationCenter.default.removeObserver(self, name: CosmoNotification.Canvas.createCosmoAIBlock, object: nil)
    }

    // MARK: - Bring Related Blocks Handler
    private func handleBringRelatedBlocks(quantity: Int, entityType: String, query: String) {
        print("🔗 Bringing \(quantity) related \(entityType) blocks...")

        // Find related entities based on the current focused entity
        Task { @MainActor in
            // Post to spatial engine to search and bring blocks
            NotificationCenter.default.post(
                name: .placeBlocksOnCanvas,
                object: nil,
                userInfo: [
                    "query": query,
                    "entityType": entityType,
                    "quantity": quantity,
                    "layout": "orbital"
                ]
            )
        }
    }

    // MARK: - Open Mention as Floating Block Handler
    private func handleOpenMentionAsFloatingBlock(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let entityType = userInfo["entityType"] as? EntityType,
              let entityId = userInfo["entityId"] as? Int64 else {
            return
        }

        print("🔗 Opening @mention as floating block: \(entityType.rawValue) id=\(entityId)")

        // Fetch entity info from database and create a floating block
        Task { @MainActor in
            await createFloatingBlockFromEntity(type: entityType, id: entityId)
        }
    }

    private func createFloatingBlockFromEntity(type: EntityType, id: Int64) async {
        var title = "Untitled"
        var entityUUID = UUID().uuidString

        do {
            // Fetch entity using AtomRepository
            if let atom = try await AtomRepository.shared.fetch(id: id) {
                title = atom.title ?? "Untitled \(type.rawValue.capitalized)"
                entityUUID = atom.uuid
            }
        } catch {
            print("❌ Failed to fetch entity for floating block: \(error)")
        }

        // Create floating block at a random position near center-right
        let randomOffsetX = CGFloat.random(in: 150...250)
        let randomOffsetY = CGFloat.random(in: -100...100)

        // Use unified canvas block system
        // Default to unpinned (stays fixed on screen)
        let record = CanvasBlockRecord(
            id: UUID().uuidString,
            uuid: entityUUID,
            userId: nil,
            documentType: entity.type.rawValue,
            documentId: Int(entity.id),
            documentUuid: nil,
            entityId: Int(id),
            entityUuid: entityUUID,
            entityType: type.rawValue,
            entityTitle: title,
            positionX: Int(randomOffsetX + 400),  // Offset from left edge
            positionY: Int(randomOffsetY + 300),  // Offset from top
            width: 240,
            height: 180,
            isCollapsed: false,
            zone: nil,
            noteContent: nil,
            zIndex: 0,
            isPinned: false,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            syncedAt: nil,
            isDeleted: false,
            localVersion: 1,
            serverVersion: 0,
            syncVersion: 0,
            localPending: 0
        )

        do {
            try await database.asyncWrite { db in
                let mutableRecord = record
                try mutableRecord.insert(db)
            }

            // Notify DocumentBlocksLayer to reload blocks
            NotificationCenter.default.post(
                name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                object: nil
            )

            print("✅ Created floating block from @mention: \(type.rawValue) - \(title)")
        } catch {
            print("❌ Failed to create floating block: \(error)")
        }
    }

    /// Create a NEW entity and floating block in Focus Mode
    private func createNewFloatingBlock(type: EntityType, title: String, content: String?, at position: CGPoint) async {
        var entityId: Int64 = -1
        var entityUUID = UUID().uuidString

        do {
            // Create the entity in database first using AtomRepository (except for notes which are block-only)
            switch type {
            case .idea:
                let atom = try await AtomRepository.shared.createIdea(title: title, content: content ?? "")
                entityId = atom.id ?? -1
                entityUUID = atom.uuid
            case .task:
                let atom = try await AtomRepository.shared.createTask(title: title)
                entityId = atom.id ?? -1
                entityUUID = atom.uuid
            case .content:
                let atom = try await AtomRepository.shared.createContent(title: title, body: content)
                entityId = atom.id ?? -1
                entityUUID = atom.uuid
            case .research:
                let atom = try await AtomRepository.shared.createResearch(title: title, url: "", summary: content)
                entityId = atom.id ?? -1
                entityUUID = atom.uuid
            case .connection:
                // Connections require source/target - use placeholder for now
                let atom = try await AtomRepository.shared.create(type: .connection, title: title)
                entityId = atom.id ?? -1
                entityUUID = atom.uuid
            case .note:
                // Notes don't have a separate entity - they're just canvas blocks
                entityId = -1
                entityUUID = UUID().uuidString
            default:
                entityId = -1
                entityUUID = UUID().uuidString
            }

            // Create canvas block record associated with the focused document
            // Default to unpinned (stays fixed on screen)
            let record = CanvasBlockRecord(
                id: UUID().uuidString,
                uuid: entityUUID,
                userId: nil,
                documentType: entity.type.rawValue,
                documentId: Int(entity.id),
                documentUuid: nil,
                entityId: Int(entityId),
                entityUuid: entityUUID,
                entityType: type.rawValue,
                entityTitle: title,
                positionX: Int(position.x),
                positionY: Int(position.y),
                width: type == .note ? 280 : 320,
                height: type == .note ? 200 : 240,
                isCollapsed: false,
                zone: nil,
                noteContent: type == .note ? (content ?? "") : nil,
                zIndex: 10,
                isPinned: false,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                syncedAt: nil,
                isDeleted: false,
                localVersion: 1,
                serverVersion: 0,
                syncVersion: 0,
                localPending: 0
            )

            try await database.asyncWrite { db in
                let mutableRecord = record
                try mutableRecord.insert(db)
            }

            // Notify DocumentBlocksLayer to reload blocks
            NotificationCenter.default.post(
                name: Notification.Name("com.cosmo.canvasBlocksChanged"),
                object: nil
            )

            print("✅ Created NEW floating block in Focus Mode: \(type.rawValue) - \(title)")
        } catch {
            print("❌ Failed to create new floating block: \(error)")
        }
    }
}

// MARK: - Focus Canvas Header (Simplified)
struct FocusCanvasHeader: View {
    let entity: EntitySelection
    let isVoiceActive: Bool
    let voiceStatus: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Close button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("Close")
                        .font(.system(size: 13))
                }
                .foregroundColor(CosmoColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CosmoColors.softWhite, in: Capsule())
                .shadow(color: CosmoColors.glassGrey.opacity(0.5), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)

            // Entity badge
            HStack(spacing: 6) {
                Image(systemName: entity.type.icon)
                    .font(.system(size: 11))
                Text(entity.type.rawValue.capitalized)
                    .font(CosmoTypography.labelSmall)
            }
            .foregroundColor(CosmoMentionColors.color(for: entity.type))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(CosmoMentionColors.color(for: entity.type).opacity(0.1), in: Capsule())

            Spacer()

            // Voice indicator (only when active)
            if isVoiceActive {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CosmoColors.coral)
                        .frame(width: 8, height: 8)
                    Text(voiceStatus.isEmpty ? "Listening..." : voiceStatus)
                        .font(.system(size: 13))
                        .foregroundColor(CosmoColors.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CosmoColors.coral.opacity(0.15), in: Capsule())
                .transition(.opacity)
            }
        }
        .padding(20)
    }
}

// MARK: - Focus Canvas Footer
struct FocusCanvasFooter: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Press Space to voice command")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
            Spacer()
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Focus Block View (Floating blocks)
struct FocusBlockView: View {
    let block: FocusBlock
    let isSelected: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let onUpdate: (String?, String?) -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedContent: String = ""

    private var blockColor: Color {
        switch block.entityType {
        case .note: return CosmoColors.note
        case .idea: return CosmoColors.lavender
        case .task: return CosmoColors.coral
        case .research: return CosmoColors.emerald
        default: return CosmoColors.glassGrey
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: block.entityType.icon)
                    .font(.system(size: 12))
                    .foregroundColor(blockColor)

                if isEditing {
                    TextField("Title", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)
                        .onSubmit {
                            onUpdate(editedTitle, editedContent)
                            isEditing = false
                        }
                } else {
                    Text(block.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CosmoColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textSecondary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
            } else if let content = block.content, !content.isEmpty {
                Text(content)
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(4)
            } else {
                Text("Double-click to edit...")
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textTertiary)
                    .italic()
            }
        }
        .padding(12)
        .frame(width: block.width, height: block.isMinimized ? 40 : block.height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CosmoColors.softWhite)
                .shadow(
                    color: blockColor.opacity(isHovered || isSelected ? 0.3 : 0.15),
                    radius: isHovered || isSelected ? 15 : 8,
                    y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? blockColor : blockColor.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
        .onTapGesture(count: 2) {
            editedTitle = block.title
            editedContent = block.content ?? ""
            isEditing = true
        }
    }
}

// MARK: - Focus Recenter Button
/// Button to recenter the focus mode canvas (horizontal position only)
/// Preserves vertical scroll position within the document
struct FocusRecenterButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .medium))
                Text("Recenter")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isHovered ? CosmoColors.textPrimary : CosmoColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CosmoColors.softWhite, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: CosmoColors.glassGrey.opacity(isHovered ? 0.6 : 0.4), radius: isHovered ? 10 : 6, y: 2)
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
