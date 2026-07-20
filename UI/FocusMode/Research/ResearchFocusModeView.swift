// CosmoOS/UI/FocusMode/Research/ResearchFocusModeView.swift
// Main Research Focus Mode view - canvas with anchored content and floating panels
// December 2025 - Complete rewrite following PRD spec

import SwiftUI
import Combine

// MARK: - Research Focus Mode View

/// Main view for Research Focus Mode.
/// Displays an infinite canvas with anchored research content, transcript spine,
/// floating panels, and Research Agent results.
struct ResearchFocusModeView: View {
    // MARK: - Properties

    /// The research atom being displayed
    let atom: Atom

    /// Callback to close focus mode
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var viewModel: ResearchFocusModeViewModel
    @StateObject private var panelManager: FloatingPanelManager
    @StateObject private var focusConnectManager = FocusConnectManager()
    @StateObject private var floatingBlocksManager: FocusFloatingBlocksManager
    @State private var viewportState = CanvasViewportState()
    @State private var showResearchAgentSheet = false
    @State private var sidebarVisible = false
    @State private var sidebarLocked = false
    @State private var showSettings = false
    @State private var rightClickMonitor: Any?
    @State private var ownedContextProvider: ResearchContextProvider?
    @State private var canvasFrameSize: CGSize = CGSize(width: 1440, height: 900)
    @State private var viewFrameInWindow: CGRect = .zero

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPeekContext) private var isPeekContext
    @Environment(\.isPaneActive) private var isPaneActive
    @Environment(\.atomWindowChromeContext) private var atomChrome
    @Environment(\.paneDeckChrome) private var paneDeckChrome

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: ResearchFocusModeViewModel(atom: atom))
        self._panelManager = StateObject(wrappedValue: FloatingPanelManager(focusAtomUUID: atom.uuid))
        self._floatingBlocksManager = StateObject(wrappedValue: FocusFloatingBlocksManager(ownerAtomUUID: atom.uuid))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ZStack {
                // Infinite canvas with content
                InfiniteCanvasView(
                    viewportState: $viewportState,
                    showGrid: true,
                    anchoredContent: {
                        anchoredContentStack
                    },
                    floatingContent: {
                        floatingPanelsLayer
                    }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { canvasFrameSize = geo.size }
                            .onChange(of: geo.size) { _, newSize in canvasFrameSize = newSize }
                    }
                )

                // Focus connection lines layer (universal linking)
                FocusConnectionLinesLayer(
                    connectManager: focusConnectManager,
                    focusAtomUUID: atom.uuid
                )

                // Top bar overlay
                VStack {
                    topBar
                    Spacer()
                }

                // Radial menu (on right-click)
                if let menuPosition = viewModel.radialMenuPosition {
                    RadialMenuView(
                        position: menuPosition,
                        onSelect: handleRadialAction,
                        onDismiss: {
                            viewModel.radialMenuPosition = nil
                        },
                        customActions: Self.focusModeActions
                    )
                }
            }
        }
        .focusBlockInspector(manager: floatingBlocksManager)
        .background(DS.focusImmersiveBackground.ignoresSafeArea())
        .focusImmersiveEntryTransition()
        .overlay(alignment: .topLeading) {
            FocusSidebarTrigger(isVisible: $sidebarVisible)
                .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            UniversalFocusSidebar(
                title: "Research",
                icon: "magnifyingglass",
                accentColor: DS.entityResearch,
                isVisible: $sidebarVisible,
                isLocked: $sidebarLocked
            ) {
                ResearchSidebarView(
                    atom: atom,
                    state: $viewModel.state,
                    isVisible: true
                )
            }
            .padding(.leading, 8)
            .padding(.top, 56)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewFrameInWindow = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in viewFrameInWindow = newFrame }
            }
        )
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            loadState()
            listenForAtomPicker()
            setupRightClickMonitor()
            // Register context provider for global Cosmo window
            let provider = ResearchContextProvider(atom: atom, viewModel: viewModel)
            if !isPaneContext || isPaneActive {
                ownedContextProvider = provider
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onChange(of: isPaneActive) { _, isActive in
            if isActive {
                let provider = ResearchContextProvider(atom: atom, viewModel: viewModel)
                ownedContextProvider = provider
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onDisappear {
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            saveState()
            floatingBlocksManager.saveImmediately()
            removeRightClickMonitor()
            // Window context follows presence: leaving research releases it.
            if let owned = ownedContextProvider {
                CosmoWindowViewModel.shared.releaseContext(provider: owned)
                ownedContextProvider = nil
            }
        }
        // Deselect panels on background click
        .onTapGesture(count: 1) {
            panelManager.deselectAll()
        }
        // Keyboard shortcuts
        .onKeyPress(.escape) {
            if viewModel.radialMenuPosition != nil {
                viewModel.radialMenuPosition = nil
                return .handled
            }
            onClose()
            return .handled
        }
        .onKeyPress { keyPress in
            if keyPress.characters == "k" && keyPress.modifiers.contains(.command) {
                presentSharedCommandK()
                return .handled
            }
            return .ignored
        }
        // Cmd+K single-click: add as floating block
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.NodeGraph.addItemToCurrentCanvas)) { notification in
            guard let uuid = notification.userInfo?["atomUUID"] as? String else { return }
            let title = notification.userInfo?["title"] as? String ?? "Untitled"
            let typeRaw = notification.userInfo?["atomType"] as? String ?? AtomType.idea.rawValue
            let atomType = AtomType(rawValue: typeRaw) ?? .idea
            floatingBlocksManager.addBlock(
                linkedAtomUUID: uuid,
                linkedAtomType: atomType,
                title: title,
                position: CGPoint(x: 200, y: 200)
            )
        }
        // Settings sheet
        .sheet(isPresented: $showSettings) {
            CosmoSettingsView()
        }
        // Research Agent sheet
        .sheet(isPresented: $showResearchAgentSheet) {
            ResearchAgentInputSheet(
                onSubmit: { query in
                    Task {
                        await viewModel.runResearchAgent(query: query)
                    }
                    showResearchAgentSheet = false
                },
                onCancel: {
                    showResearchAgentSheet = false
                }
            )
        }
    }

    // MARK: - Anchored Content Stack

    @ViewBuilder
    private var anchoredContentStack: some View {
        // Check for Instagram content and use appropriate layout
        if let instagramData = viewModel.instagramData {
            // Instagram-specific layouts
            switch instagramData.contentType {
            case .reel, .story:
                // Side-by-side layout for reels and stories
                InstagramReelLayout(
                    atom: atom,
                    currentTimestamp: $viewModel.currentTimestamp,
                    duration: viewModel.duration,
                    instagramData: instagramData,
                    onSeek: { time in
                        viewModel.seekTo(time)
                    },
                    onAddSection: { timestamp in
                        viewModel.addInstagramTranscriptSection(at: timestamp)
                    },
                    onSectionTap: { section in
                        viewModel.seekTo(section.startTime)
                    },
                    onAnnotationAdd: { sectionId, type in
                        viewModel.addInstagramAnnotation(type: type, toSection: sectionId)
                    },
                    onAnnotationEdit: { annotation, document in
                        viewModel.editInstagramAnnotation(annotation, document: document)
                    },
                    onAnnotationDelete: { id in
                        viewModel.deleteInstagramAnnotation(id)
                    }
                )
            case .carousel:
                // Carousel layout with per-slide notes
                InstagramCarouselLayout(
                    atom: atom,
                    instagramData: instagramData,
                    onAnnotationAdd: { slideIndex, type in
                        viewModel.addInstagramCarouselAnnotation(type: type, slideIndex: slideIndex)
                    },
                    onAnnotationEdit: { annotation, document in
                        viewModel.editInstagramAnnotation(annotation, document: document)
                    },
                    onAnnotationDelete: { id in
                        viewModel.deleteInstagramAnnotation(id)
                    }
                )
            case .videoPost:
                // Check aspect ratio - vertical videos use side-by-side
                if instagramData.usesSideBySideLayout {
                    InstagramReelLayout(
                        atom: atom,
                        currentTimestamp: $viewModel.currentTimestamp,
                        duration: viewModel.duration,
                        instagramData: instagramData,
                        onSeek: { time in
                            viewModel.seekTo(time)
                        },
                        onAddSection: { timestamp in
                            viewModel.addInstagramTranscriptSection(at: timestamp)
                        },
                        onSectionTap: { section in
                            viewModel.seekTo(section.startTime)
                        },
                        onAnnotationAdd: { sectionId, type in
                            viewModel.addInstagramAnnotation(type: type, toSection: sectionId)
                        },
                        onAnnotationEdit: { annotation, document in
                            viewModel.editInstagramAnnotation(annotation, document: document)
                        },
                        onAnnotationDelete: { id in
                            viewModel.deleteInstagramAnnotation(id)
                        }
                    )
                } else {
                    standardResearchLayout
                }
            case .image:
                standardResearchLayout
            }
        } else {
            // Standard research layout for non-Instagram content
            standardResearchLayout
        }
    }

    // MARK: - Standard Research Layout

    private var standardResearchLayout: some View {
        HStack(alignment: .top, spacing: 40) {
            // Research Core (video/article/pdf)
            ResearchCoreView(
                atom: atom,
                currentTimestamp: $viewModel.currentTimestamp,
                timelineMarkers: viewModel.state.timelineMarkers,
                duration: viewModel.duration,
                contentType: viewModel.state.contentType,
                source: viewModel.state.source,
                onSeek: { time in
                    viewModel.seekTo(time)
                },
                onMarkerTap: { marker in
                    viewModel.seekTo(marker.timestamp)
                },
                onCopyURL: {
                    viewModel.copyURL()
                },
                onOpenInBrowser: {
                    viewModel.openInBrowser()
                }
            )
            .frame(width: 560)

            // Transcript Spine (if available)
            if !viewModel.state.transcriptSections.isEmpty {
                TranscriptSpineView(
                    sections: viewModel.state.transcriptSections,
                    currentTimestamp: viewModel.currentTimestamp,
                    onSectionTap: { section in
                        viewModel.seekTo(section.startTime)
                    },
                    onAddAnnotation: { section, type in
                        viewModel.addAnnotation(
                            type: type,
                            toSection: section.id,
                            content: ""
                        )
                    },
                    onAnnotationEdit: { annotation, document in
                        viewModel.editAnnotation(annotation, document: document)
                    },
                    onAnnotationDelete: { annotation in
                        viewModel.deleteAnnotation(annotation.id)
                    },
                    onCreateHighlightAnnotation: { sectionID, type, selectedText, range in
                        viewModel.createHighlightAnnotation(sectionID: sectionID, type: type, selectedText: selectedText, range: range)
                    },
                    onPromoteToBlock: { annotation in
                        Task {
                            let title = annotation.highlightedText?.prefix(60).description
                                ?? annotation.type.label
                            let body = annotation.content

                            // Always create as note — annotations are working notes, not ideas
                            let newAtom = Atom.new(type: .note, title: String(title), body: body)
                            guard let created = try? await AtomRepository.shared.create(newAtom) else { return }

                            // Position to the right of the transcript
                            // Anchored HStack is 1160px wide (560+40+560), centered in canvas
                            let rightOfTranscript = canvasFrameSize.width / 2 + 640
                            let existingCount = CGFloat(floatingBlocksManager.blocks.count)
                            let yOffset = 150 + existingCount * 200

                            floatingBlocksManager.addBlock(
                                linkedAtomUUID: created.uuid,
                                linkedAtomType: .note,
                                title: String(title),
                                position: CGPoint(x: rightOfTranscript, y: yOffset)
                            )
                        }
                    }
                )
                .frame(width: 560)
            }
        }
    }

    // MARK: - Floating Panels Layer

    @ViewBuilder
    private var floatingPanelsLayer: some View {
        ZStack {
            // Persistent floating blocks (stored in atom metadata)
            FocusFloatingBlocksLayer(manager: floatingBlocksManager)

            // Floating panels from database (legacy UserDefaults-based)
            ForEach(panelManager.panels) { panel in
                FloatingPanelWrapper(
                    panelManager: panelManager,
                    panelID: panel.id,
                    atomUUID: panel.atomUUID
                )
            }

            // Research Agent results
            ForEach(viewModel.state.agentResults) { result in
                ResearchAgentPanelView(
                    result: result,
                    position: agentResultPosition(for: result),
                    onConvertToAtom: {
                        Task {
                            await viewModel.convertAgentToAtom(result)
                        }
                    },
                    onDismiss: {
                        viewModel.removeAgentResult(result.id)
                    }
                )
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            if let atomChrome {
                CosmoChromeIsland {
                    AtomWindowChromeLeadingControls(context: atomChrome)
                }
            }

            // Universal back/forward full-screen (the trail island carries the
            // sidebar toggle); the deck tab strip rides this seam in pane
            // context (tabs carry identity and close).
            if atomChrome == nil, !isPaneContext {
                NavigationTrailIsland()
            } else if let paneDeckChrome {
                CosmoChromeIsland { PaneDeckTabStrip(context: paneDeckChrome) }
            }

            // Title — the focused deck tab already names the pane, so the
            // inline title would say it twice there.
            if atomChrome == nil, paneDeckChrome == nil {
                Text(atom.title ?? "Research")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(DS.caption2)
                    Text("Research")
                        .font(DS.smallCaps)
                }
                .foregroundStyle(DS.entityResearch)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.entityResearch.opacity(0.12), in: Capsule())
            }

            Spacer()

            // Focus mode sidebar toggle
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(DS.callout)
                    .foregroundStyle(sidebarVisible ? DS.entityResearch : DS.textSecondary)
                    .padding(8)
                    .background(
                        sidebarVisible ? DS.entityResearch.opacity(0.15) : DS.border,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)

            // Annotation count
            HStack(spacing: 4) {
                Image(systemName: "note.text")
                    .font(DS.footnote)
                Text("\(viewModel.state.allAnnotations.count)")
                    .font(DS.caption)
            }
            .foregroundStyle(DS.textSecondary)

            // Floating block count
            if !floatingBlocksManager.blocks.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "square.on.square")
                        .font(DS.footnote)
                    Text("\(floatingBlocksManager.blocks.count)")
                        .font(DS.caption)
                }
                .foregroundStyle(DS.textSecondary)
            }

            if let atomChrome {
                CosmoChromeIsland {
                    AtomWindowChromeTrailingControls(context: atomChrome)
                }
            }

        }
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    DS.bg.opacity(0.95),
                    DS.bg.opacity(0.8),
                    DS.bg.opacity(0.4),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
        , alignment: .top)
    }

    // MARK: - Focus Mode Radial Actions

    /// 5-item radial menu matching canvas (Content/Note/Sticky/Connection/Database)
    private static let focusModeActions: [RadialAction] = [
        RadialAction(icon: "doc.text.fill", label: "Content", color: DS.entityContent, type: .createContent),
        RadialAction(icon: "note.text", label: "Note", color: DS.entityNote, type: .createNote),
        RadialAction(icon: "square.and.pencil", label: "Sticky", color: DS.entityStickyNote, type: .createStickyNote),
        RadialAction(icon: "person.2.fill", label: "Concept", color: DS.entityConnection, type: .createConnection),
        RadialAction(icon: "tray.full.fill", label: "Database", color: DS.textSecondary, type: .fromDatabase),
    ]

    // MARK: - Right-Click Monitor

    private func setupRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let window = event.window else { return event }

            let windowPoint = event.locationInWindow
            let windowHeight = window.frame.height

            // Convert to SwiftUI coordinates (flip Y, origin top-left)
            let screenPoint = CGPoint(
                x: windowPoint.x,
                y: windowHeight - windowPoint.y
            )

            // Only handle clicks within this view's frame
            guard viewFrameInWindow.contains(screenPoint) else { return event }

            // Convert to view-local coordinates
            let localPoint = CGPoint(
                x: screenPoint.x - viewFrameInWindow.minX,
                y: screenPoint.y - viewFrameInWindow.minY
            )

            // Convert local coordinates to canvas coordinates
            // Inverse of: local = canvas * zoom + offset
            let canvasPoint = CGPoint(
                x: (localPoint.x - viewportState.offset.x) / viewportState.zoomScale,
                y: (localPoint.y - viewportState.offset.y) / viewportState.zoomScale
            )

            viewModel.lastTapPosition = canvasPoint
            viewModel.radialMenuPosition = localPoint

            return nil // Consume the event
        }
    }

    private func removeRightClickMonitor() {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
    }

    // MARK: - Helpers

    private func handleRadialAction(_ action: RadialAction) {
        viewModel.radialMenuPosition = nil
        let position = viewModel.lastTapPosition

        switch action.type {
        case .createNote:
            Task {
                if let noteAtom = await viewModel.createNote() {
                    addPanelForAtom(noteAtom, at: position)
                }
            }

        case .createIdea:
            Task {
                if let ideaAtom = await viewModel.createIdea() {
                    addPanelForAtom(ideaAtom, at: position)
                }
            }

        case .createTask:
            Task {
                if let taskAtom = await viewModel.createTask() {
                    addPanelForAtom(taskAtom, at: position)
                }
            }

        case .createContent:
            Task {
                if let contentAtom = await viewModel.createContent() {
                    addPanelForAtom(contentAtom, at: position)
                }
            }

        case .createResearch:
            Task {
                if let researchAtom = await viewModel.createResearch() {
                    addPanelForAtom(researchAtom, at: position)
                }
            }

        case .createConnection:
            Task {
                if let connectionAtom = await viewModel.createConnection() {
                    addPanelForAtom(connectionAtom, at: position)
                }
            }

        case .createStickyNote:
            Task {
                let stickyAtom = Atom.new(type: .stickyNote, title: "", body: "")
                if let created = try? await AtomRepository.shared.create(stickyAtom) {
                    addPanelForAtom(created, at: position)
                }
            }

        case .createDeepDive:
            Task {
                if let deepDiveAtom = try? await InquiryRepository.shared.createDeepDive(title: "New Deep Dive") {
                    addPanelForAtom(deepDiveAtom, at: position)
                }
            }

        case .researchAgent:
            showResearchAgentSheet = true

        case .fromDatabase:
            presentSharedCommandK()
        }
    }

    /// The one shared ⌘K palette lives in MainView (zIndex 200, above focus
    /// modes). A local `.sheet(CommandKView())` here rendered a second,
    /// backdropped copy of the palette — never present ⌘K locally. The shared
    /// palette closes itself after posting a pick.
    private func presentSharedCommandK() {
        NotificationCenter.default.post(name: .showCommandPalette, object: nil)
    }

    private func addPanelForAtom(_ atom: Atom, at position: CGPoint) {
        // Add as persistent floating block (stored in atom metadata)
        floatingBlocksManager.addBlock(
            linkedAtomUUID: atom.uuid,
            linkedAtomType: atom.type,
            title: atom.title ?? "Untitled",
            position: position
        )
    }

    /// Listen for atom picker notifications to add existing atoms as floating blocks
    private func listenForAtomPicker() {
        NotificationCenter.default.addObserver(
            forName: CosmoNotification.FocusMode.addAtomAsFloatingBlock,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard !self.isPaneContext || self.isPaneActive else { return }
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

    private func agentResultPosition(for result: ResearchAgentResult) -> CGPoint {
        // Position agent results to the right of the main content
        let index = viewModel.state.agentResults.firstIndex(where: { $0.id == result.id }) ?? 0
        return CGPoint(x: 800, y: 200 + CGFloat(index) * 220)
    }

    private func loadState() {
        // Load viewport state
        let persistence = CanvasViewportPersistence()
        viewportState = persistence.load(forAtomUUID: atom.uuid)

        // ViewModel loads its own state
        viewModel.loadState()
    }

    private func saveState() {
        // Save viewport state
        let persistence = CanvasViewportPersistence()
        persistence.save(viewportState, forAtomUUID: atom.uuid)

        // Save focus mode state
        viewModel.saveState()
    }
}

// MARK: - Research Focus Mode ViewModel

/// ViewModel for Research Focus Mode state management
@MainActor
class ResearchFocusModeViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: ResearchFocusModeState
    @Published var currentTimestamp: TimeInterval = 0
    @Published var radialMenuPosition: CGPoint?
    @Published var lastTapPosition: CGPoint = CGPoint(x: 400, y: 300)
    @Published var selectedAnnotationID: UUID?

    // MARK: - Properties

    private let atom: Atom

    var duration: TimeInterval {
        state.source?.duration ?? 0
    }

    /// Instagram-specific data if this is Instagram content
    var instagramData: InstagramData? {
        // Try to extract from atom's rich content
        guard let structuredJSON = atom.structured,
              let data = structuredJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let igDataJSON = json["instagramData"] as? [String: Any] else {
            // Check metadata field as fallback
            if let metadataJSON = atom.metadata,
               let data = metadataJSON.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sourceType = json["sourceType"] as? String,
               sourceType.contains("instagram") {
                // Build basic InstagramData from metadata
                return buildInstagramDataFromMetadata(json)
            }
            return nil
        }

        // Decode InstagramData from JSON
        return try? JSONDecoder().decode(InstagramData.self, from: JSONSerialization.data(withJSONObject: igDataJSON))
    }

    private func buildInstagramDataFromMetadata(_ json: [String: Any]) -> InstagramData? {
        // Try to get URL from json or from structured data if it contains instagram.com
        let urlString: String
        if let jsonUrl = json["url"] as? String {
            urlString = jsonUrl
        } else if let structured = atom.structured, structured.contains("instagram.com") {
            urlString = structured
        } else {
            return nil
        }

        guard let url = URL(string: urlString) else {
            return nil
        }

        let contentType: InstagramContentType
        let sourceType = json["sourceType"] as? String ?? ""
        if sourceType.contains("reel") || urlString.contains("/reel") {
            contentType = .reel
        } else if sourceType.contains("carousel") {
            contentType = .carousel
        } else {
            contentType = .image
        }

        return InstagramData(
            originalURL: url,
            contentType: contentType,
            authorUsername: json["author"] as? String,
            caption: json["summary"] as? String ?? atom.body
        )
    }

    // MARK: - Initialization

    init(atom: Atom) {
        self.atom = atom
        self.state = ResearchFocusModeState(atomUUID: atom.uuid)
        parseAtomMetadata()
    }

    // MARK: - State Management

    func loadState() {
        if let savedState = ResearchFocusModeState.load(atomUUID: atom.uuid) {
            state = savedState
            currentTimestamp = savedState.currentTimestamp
        }
    }

    func saveState() {
        state.currentTimestamp = currentTimestamp
        state.lastModified = Date()
        state.save()
    }

    // MARK: - Metadata Parsing

    private func parseAtomMetadata() {
        // Use wrapper properties to access research data
        // The data is stored in structured.autoMetadata as ResearchRichContent
        let richContent = atom.richContent

        // Get URL from multiple possible sources
        var url = atom.url ?? extractURLFromStructured()

        // If no URL found, try to construct from videoId
        if url == nil, let videoId = richContent?.videoId {
            url = "https://www.youtube.com/watch?v=\(videoId)"
            print("🔧 Constructed YouTube URL from videoId: \(videoId)")
        }

        print("📊 ResearchFocusMode parsing: url=\(url ?? "nil"), richContent=\(richContent != nil ? "present" : "nil")")
        print("   atom.url=\(atom.url ?? "nil"), thumbnailUrl=\(atom.thumbnailUrl ?? "nil")")
        print("   richContent.sourceType=\(richContent?.sourceType?.rawValue ?? "nil")")
        print("   richContent.videoId=\(richContent?.videoId ?? "nil")")
        print("   richContent.author=\(richContent?.author ?? "nil")")
        print("   richContent.duration=\(richContent?.duration.map(String.init) ?? "nil")")

        if let url = url {
            state.contentType = ResearchSource.detectContentType(from: url)

            // Parse publishedAt string to Date if available
            let publishedDate: Date? = richContent?.publishedAt.flatMap { ISO8601.date(from: $0) }

            state.source = ResearchSource(
                url: url,
                platform: richContent?.sourceType?.displayName ?? ResearchSource.detectPlatform(from: url),
                author: richContent?.author,
                channelName: richContent?.author,
                publishedAt: publishedDate,
                duration: richContent?.duration.map { TimeInterval($0) },
                thumbnailURL: atom.thumbnailUrl ?? richContent?.thumbnailUrl
            )
            print("   ✅ Detected contentType: \(state.contentType), platform: \(state.source?.platform ?? "nil")")
        } else {
            print("   ⚠️ No URL found - will show generic content")
        }

        // Parse transcript from body field (stored as JSON string) or richContent
        if let transcriptSegments = richContent?.transcriptSegments, !transcriptSegments.isEmpty {
            state.transcriptSections = transcriptSegments.map { segment in
                TranscriptSection(
                    startTime: segment.start,
                    endTime: segment.end,
                    text: segment.text,
                    speakerName: nil
                )
            }
            print("   ✅ Loaded \(state.transcriptSections.count) transcript sections from richContent")
        } else if let bodyJSON = atom.body, !bodyJSON.isEmpty {
            // Try to parse transcript from body field
            parseTranscriptFromBody(bodyJSON)
            print("   ✅ Parsed \(state.transcriptSections.count) transcript sections from body")
        } else {
            print("   ⚠️ No transcript data found")
        }
    }

    /// Extract URL from structured JSON if not in metadata
    private func extractURLFromStructured() -> String? {
        guard let structuredJSON = atom.structured,
              let data = structuredJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["url"] as? String ?? json["source_url"] as? String
    }

    /// Parse transcript from body JSON string
    private func parseTranscriptFromBody(_ bodyJSON: String) {
        guard let data = bodyJSON.data(using: .utf8),
              let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) else {
            return
        }

        state.transcriptSections = segments.map { segment in
            TranscriptSection(
                startTime: segment.start,
                endTime: segment.end,
                text: segment.text,
                speakerName: nil
            )
        }
    }

    private func parseDuration(_ durationString: String?) -> TimeInterval? {
        guard let str = durationString else { return nil }
        let components = str.split(separator: ":").compactMap { Int($0) }

        switch components.count {
        case 2: // mm:ss
            return TimeInterval(components[0] * 60 + components[1])
        case 3: // hh:mm:ss
            return TimeInterval(components[0] * 3600 + components[1] * 60 + components[2])
        default:
            return nil
        }
    }

    // MARK: - Playback Control

    func seekTo(_ timestamp: TimeInterval) {
        withAnimation(ProMotionSprings.snappy) {
            currentTimestamp = timestamp
        }
    }

    // MARK: - URL Actions

    func copyURL() {
        guard let url = state.source?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    func openInBrowser() {
        guard let urlString = state.source?.url,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Annotation Management

    func addAnnotation(type: AnnotationType, toSection sectionID: UUID, content: String) {
        let annotation = ResearchAnnotation(
            type: type,
            content: content,
            timestamp: currentTimestamp
        )
        state.addAnnotation(annotation, toSection: sectionID)
        saveState()
    }

    func selectAnnotation(_ id: UUID) {
        selectedAnnotationID = id
    }

    func editAnnotation(_ annotation: ResearchAnnotation, document: RichDocument) {
        state.updateAnnotationDocument(id: annotation.id, document: document)
        saveState()
    }

    func updateAnnotationPosition(_ annotation: ResearchAnnotation, offset: CGPoint) {
        state.updateAnnotationPosition(id: annotation.id, offset: offset)
        saveState()
    }

    func createHighlightAnnotation(sectionID: UUID, type: AnnotationType, selectedText: String, range: NSRange) {
        let annotation = ResearchAnnotation(
            type: type,
            content: "",
            timestamp: currentTimestamp,
            highlightedText: selectedText,
            sectionID: sectionID
        )

        let highlight = TextHighlight(
            annotationID: annotation.id,
            startCharIndex: range.location,
            endCharIndex: range.location + range.length,
            annotationType: type,
            highlightedText: selectedText
        )

        state.addAnnotation(annotation, toSection: sectionID)
        state.addHighlight(highlight, toSection: sectionID)
        saveState()
    }

    func deleteAnnotation(_ id: UUID) {
        state.removeAnnotation(id: id)
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
        saveState()
    }

    // MARK: - Atom Creation

    func createNote() async -> Atom? {
        let note = Atom.new(
            type: .note,
            title: "New Note",
            body: ""
        )
        return try? await AtomRepository.shared.create(note)
    }

    func createIdea() async -> Atom? {
        let idea = Atom.new(
            type: .idea,
            title: "New Idea",
            body: ""
        )
        return try? await AtomRepository.shared.create(idea)
    }

    func createTask() async -> Atom? {
        let task = Atom.new(
            type: .task,
            title: "New Task",
            body: ""
        )
        return try? await AtomRepository.shared.create(task)
    }

    func createContent() async -> Atom? {
        let content = Atom.new(
            type: .content,
            title: "New Content",
            body: ""
        )
        return try? await AtomRepository.shared.create(content)
    }

    func createResearch() async -> Atom? {
        let research = Atom.new(
            type: .research,
            title: "New Research",
            body: ""
        )
        return try? await AtomRepository.shared.create(research)
    }

    func createConnection() async -> Atom? {
        let connection = Atom.new(
            type: .connection,
            title: "New Concept",
            body: ""
        )
        return try? await AtomRepository.shared.create(connection)
    }

    // MARK: - Research Agent

    func runResearchAgent(query: String) async {
        // Create pending result
        let result = ResearchAgentResult(
            query: query,
            summary: "",
            status: .running
        )
        state.agentResults.append(result)

        do {
            // Call Perplexity API
            let apiResult = try await PerplexityService.shared.research(query: query)

            // Update result
            if let index = state.agentResults.firstIndex(where: { $0.id == result.id }) {
                state.agentResults[index] = ResearchAgentResult(
                    id: result.id,
                    query: query,
                    summary: apiResult.summary,
                    citations: apiResult.citations.map {
                        ResearchAgentResult.Citation(
                            title: $0.title,
                            url: $0.url,
                            snippet: $0.snippet
                        )
                    },
                    relatedQuestions: apiResult.relatedQuestions,
                    status: .complete
                )
            }
        } catch {
            // Mark as failed
            if let index = state.agentResults.firstIndex(where: { $0.id == result.id }) {
                state.agentResults[index].status = .failed
            }
            print("Research Agent error: \(error)")
        }

        saveState()
    }

    func convertAgentToAtom(_ result: ResearchAgentResult) async {
        // Create research atom from agent result
        let research = Atom.new(
            type: .research,
            title: "Research: \(result.query)",
            body: result.summary
        )
        _ = try? await AtomRepository.shared.create(research)

        // Remove from agent results
        removeAgentResult(result.id)
    }

    func removeAgentResult(_ id: UUID) {
        state.agentResults.removeAll { $0.id == id }
        saveState()
    }

    // MARK: - Instagram Transcript Management

    /// Add a new manual transcript section at the given timestamp
    func addInstagramTranscriptSection(at timestamp: TimeInterval) {
        // Get or create instagram data for this atom
        var igData = instagramData ?? InstagramData(
            originalURL: URL(string: state.source?.url ?? "")!,
            contentType: .reel
        )

        // Initialize transcript if needed
        if igData.manualTranscript == nil {
            igData.manualTranscript = ManualTranscript(researchAtomID: atom.uuid)
        }

        // Create new section
        let newSection = ManualTranscriptSection(
            startTime: timestamp,
            text: ""
        )

        // Set end time of previous section
        if var sections = igData.manualTranscript?.sections,
           let lastIndex = sections.indices.last,
           sections[lastIndex].endTime == nil {
            sections[lastIndex].endTime = timestamp
            igData.manualTranscript?.sections = sections
        }

        igData.manualTranscript?.sections.append(newSection)
        igData.manualTranscript?.updatedAt = Date()

        // Save updated Instagram data to atom
        updateAtomInstagramData(igData)
    }

    /// Add an annotation to an Instagram transcript section
    func addInstagramAnnotation(type: InstagramAnnotation.AnnotationType, toSection sectionId: UUID) {
        guard var igData = instagramData,
              var transcript = igData.manualTranscript,
              let sectionIndex = transcript.sections.firstIndex(where: { $0.id == sectionId }) else {
            return
        }

        let annotation = InstagramAnnotation(
            type: type,
            content: "",
            timestamp: currentTimestamp
        )

        transcript.sections[sectionIndex].annotations.append(annotation)
        transcript.updatedAt = Date()
        igData.manualTranscript = transcript

        updateAtomInstagramData(igData)
    }

    /// Add an annotation to a carousel slide
    func addInstagramCarouselAnnotation(type: InstagramAnnotation.AnnotationType, slideIndex: Int) {
        guard var igData = instagramData else { return }

        // Initialize transcript if needed (we reuse transcript structure for carousel notes)
        if igData.manualTranscript == nil {
            igData.manualTranscript = ManualTranscript(researchAtomID: atom.uuid)
        }

        let annotation = InstagramAnnotation(
            type: type,
            content: "",
            slideIndex: slideIndex
        )

        // Add to first section (create one if needed)
        if igData.manualTranscript?.sections.isEmpty == true {
            let section = ManualTranscriptSection(startTime: 0, text: "Carousel Notes")
            igData.manualTranscript?.sections.append(section)
        }

        if var sections = igData.manualTranscript?.sections,
           !sections.isEmpty {
            sections[0].annotations.append(annotation)
            igData.manualTranscript?.sections = sections
            igData.manualTranscript?.updatedAt = Date()
        }

        updateAtomInstagramData(igData)
    }

    /// Edit an Instagram annotation
    func editInstagramAnnotation(_ annotation: InstagramAnnotation, document: RichDocument) {
        guard var igData = instagramData,
              var transcript = igData.manualTranscript else {
            return
        }

        for sectionIndex in transcript.sections.indices {
            if let annotationIndex = transcript.sections[sectionIndex].annotations.firstIndex(where: { $0.id == annotation.id }) {
                transcript.sections[sectionIndex].annotations[annotationIndex].document = document
                transcript.sections[sectionIndex].annotations[annotationIndex].plainText = document.plainText
                transcript.sections[sectionIndex].annotations[annotationIndex].content = document.plainText
                transcript.sections[sectionIndex].annotations[annotationIndex].updatedAt = Date()
            }
        }

        transcript.updatedAt = Date()
        igData.manualTranscript = transcript
        updateAtomInstagramData(igData)
    }

    /// Delete an Instagram annotation
    func deleteInstagramAnnotation(_ annotationId: UUID) {
        guard var igData = instagramData,
              var transcript = igData.manualTranscript else {
            return
        }

        // Find and remove the annotation from all sections
        for i in transcript.sections.indices {
            transcript.sections[i].annotations.removeAll { $0.id == annotationId }
        }

        transcript.updatedAt = Date()
        igData.manualTranscript = transcript

        updateAtomInstagramData(igData)
    }

    /// Update the atom with new Instagram data
    private func updateAtomInstagramData(_ igData: InstagramData) {
        Task {
            // Encode Instagram data to JSON
            guard let igDataJSON = try? JSONEncoder().encode(igData),
                  let igDataDict = try? JSONSerialization.jsonObject(with: igDataJSON) as? [String: Any] else {
                return
            }

            // Parse current structured data
            var structured: [String: Any] = [:]
            if let existingJSON = atom.structured,
               let data = existingJSON.data(using: .utf8),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                structured = existing
            }

            // Update with Instagram data
            structured["instagramData"] = igDataDict

            // Serialize back
            if let newStructuredData = try? JSONSerialization.data(withJSONObject: structured),
               let newStructuredString = String(data: newStructuredData, encoding: .utf8) {
                var updatedAtom = atom
                updatedAtom.structured = newStructuredString
                updatedAtom.updatedAt = ISO8601.string(from: Date())
                updatedAtom.localVersion += 1

                do {
                    try await AtomRepository.shared.update(updatedAtom)
                } catch {
                    print("Failed to update atom with Instagram data: \(error)")
                }
            }
        }
    }
}

// MARK: - Research Agent Input Sheet

/// Sheet for entering Research Agent query
struct ResearchAgentInputSheet: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(DS.title1)
                    .foregroundStyle(DS.info)

                Text("Research Agent")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)

                Spacer()
            }

            Text("Ask a question and the Research Agent will search the web and synthesize findings.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Query input
            TextField("What would you like to research?", text: $query, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .padding(12)
                .dsGlassInput(isFocused: isFocused, cornerRadius: 8)
                .focused($isFocused)
                .lineLimit(3...6)

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)

                Spacer()

                Button {
                    if !query.isEmpty {
                        onSubmit(query)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Research")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DS.accent, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(DS.textOnAccent)
                }
                .buttonStyle(.plain)
                .disabled(query.isEmpty)
                .opacity(query.isEmpty ? 0.5 : 1)
            }
        }
        .padding(24)
        .frame(width: 450)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Research Agent Panel View

/// Floating panel displaying Research Agent results
struct ResearchAgentPanelView: View {
    let result: ResearchAgentResult
    let position: CGPoint
    let onConvertToAtom: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    private let agentColor = DS.info // Cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(DS.subheadline)
                    .foregroundStyle(agentColor)

                Text("Research Agent")
                    .font(DS.smallCaps)
                    .foregroundStyle(agentColor)

                Spacer()

                // Status indicator
                statusBadge

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Query
            Text(result.query)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(2)

            Divider()
                .background(DS.borderActive)

            // Content based on status
            switch result.status {
            case .running:
                runningContent
            case .complete:
                completeContent
            case .failed:
                failedContent
            case .pending:
                pendingContent
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .dsFloatingShadow()
        .position(position)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch result.status {
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(agentColor)
                Text("Searching…")
                    .font(DS.caption2)
                    .foregroundStyle(agentColor)
            }

        case .complete:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
                Text("Complete")
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
            }

        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.red)
                Text("Failed")
                    .font(DS.caption2)
                    .foregroundStyle(DS.red)
            }

        case .pending:
            Text("Pending")
                .font(DS.caption2)
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Content Views

    private var runningContent: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(agentColor)

            Text("Searching sources…")
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var completeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Summary
            Text(result.summary)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .lineLimit(isExpanded ? nil : 4)

            // Citations count
            if !result.citations.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(DS.caption2)
                    Text("\(result.citations.count) sources")
                        .font(DS.caption2)
                }
                .foregroundStyle(DS.textSecondary)
            }

            // Actions
            HStack {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "View full")
                        .font(DS.caption2)
                        .foregroundStyle(agentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onConvertToAtom) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(DS.caption2)
                        Text("Save as Atom")
                            .font(DS.caption2)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.accent.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var failedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.title1)
                .foregroundStyle(DS.red.opacity(0.7))

            Text("Research failed. Please try again.")
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Edit Query") {
                    // Would open edit sheet
                }
                .buttonStyle(.plain)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)

                Button("Retry") {
                    // Would retry query
                }
                .buttonStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(agentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var pendingContent: some View {
        Text("Waiting to start…")
            .font(DS.subheadline)
            .foregroundStyle(DS.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // MARK: - Styling

    private var borderColor: Color {
        switch result.status {
        case .complete: return DS.green.opacity(0.5) // Green
        case .failed: return DS.red.opacity(0.5)
        case .running: return agentColor.opacity(0.3)
        case .pending: return DS.borderActive
        }
    }
}

// MARK: - Floating Panel Wrapper

/// Helper view to handle the binding for FloatingPanelView
private struct FloatingPanelWrapper: View {
    @ObservedObject var panelManager: FloatingPanelManager
    let panelID: UUID
    let atomUUID: String

    var body: some View {
        if let binding = panelManager.binding(for: panelID) {
            FloatingPanelView(
                panel: binding,
                content: panelManager.content(for: panelID),
                onDoubleTap: {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Navigation.openBlockInFocusMode,
                        object: nil,
                        userInfo: ["atomUUID": atomUUID]
                    )
                },
                onRemove: {
                    panelManager.removePanel(id: panelID)
                },
                onDelete: {
                    Task {
                        try? await AtomRepository.shared.delete(uuid: atomUUID)
                        panelManager.removePanel(id: panelID)
                    }
                },
                onPositionChange: { newPosition in
                    panelManager.updatePosition(panelID, position: newPosition)
                }
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ResearchFocusModeView_Previews: PreviewProvider {
    static var previews: some View {
        ResearchFocusModeView(
            atom: Atom.new(
                type: .research,
                title: "Dan Koe - How to Reinvent Your Life in 6-12 Months",
                body: "Key insights from the video about identity transformation."
            ),
            onClose: { print("Close") }
        )
        .frame(width: 1200, height: 800)
    }
}
#endif

// MARK: - Cosmo Context Provider

@MainActor
class ResearchContextProvider: CosmoContextProvider {
    private let atom: Atom
    private weak var viewModel: ResearchFocusModeViewModel?

    init(atom: Atom, viewModel: ResearchFocusModeViewModel) {
        self.atom = atom
        self.viewModel = viewModel
    }

    var contextType: CosmoContextType { .researchFocusMode }

    var contextSummary: String {
        "Research: \(atom.title ?? "Untitled")"
    }

    var contextData: CosmoContextData {
        var viewData: [String: String] = [:]

        if let sections = viewModel?.state.transcriptSections, !sections.isEmpty {
            let fullTranscript = sections.map { $0.text }.joined(separator: " ")
            viewData["transcript"] = String(fullTranscript.prefix(1000))
            viewData["transcriptSectionCount"] = "\(sections.count)"
            let annotationCount = sections.reduce(0) { $0 + $1.annotations.count }
            if annotationCount > 0 {
                viewData["annotationCount"] = "\(annotationCount)"
            }
        }
        if let url = atom.url {
            viewData["sourceURL"] = url
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "research",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    var availableActions: [CosmoWindowAction] { [] }
}
