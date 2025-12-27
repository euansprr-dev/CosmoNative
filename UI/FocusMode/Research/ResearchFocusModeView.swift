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
    @State private var viewportState = CanvasViewportState()
    @State private var showCommandK = false
    @State private var showResearchAgentSheet = false

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: ResearchFocusModeViewModel(atom: atom))
        self._panelManager = StateObject(wrappedValue: FloatingPanelManager(focusAtomUUID: atom.uuid))
    }

    // MARK: - Body

    var body: some View {
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

            // Top bar overlay (minimal)
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
                    }
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            loadState()
        }
        .onDisappear {
            saveState()
        }
        // Right-click for radial menu
        .onTapGesture(count: 1) {
            // Deselect all panels on background click
            panelManager.deselectAll()
        }
        .gesture(
            TapGesture(count: 1)
                .modifiers(.control)
                .onEnded { _ in
                    // Control-click opens radial menu at mouse location
                    // Note: Getting actual mouse position requires NSEvent
                    viewModel.radialMenuPosition = CGPoint(x: 400, y: 300)
                }
        )
        // Keyboard shortcuts
        .onKeyPress(.escape) {
            if viewModel.radialMenuPosition != nil {
                viewModel.radialMenuPosition = nil
                return .handled
            }
            if showCommandK {
                showCommandK = false
                return .handled
            }
            onClose()
            return .handled
        }
        .onKeyPress { keyPress in
            if keyPress.characters == "k" && keyPress.modifiers.contains(.command) {
                showCommandK = true
                return .handled
            }
            return .ignored
        }
        // Command-K sheet
        .sheet(isPresented: $showCommandK) {
            CommandKView()
                .frame(minWidth: 900, minHeight: 600)
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
                    onAnnotationEdit: { annotation in
                        viewModel.editInstagramAnnotation(annotation)
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
                    onAnnotationEdit: { annotation in
                        viewModel.editInstagramAnnotation(annotation)
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
                        onAnnotationEdit: { annotation in
                            viewModel.editInstagramAnnotation(annotation)
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
                    onAnnotationTap: { annotation in
                        viewModel.selectAnnotation(annotation.id)
                    },
                    onAnnotationEdit: { annotation in
                        viewModel.editAnnotation(annotation)
                    },
                    onAnnotationDelete: { annotation in
                        viewModel.deleteAnnotation(annotation.id)
                    }
                )
                .frame(width: 600)
            }
        }
    }

    // MARK: - Floating Panels Layer

    @ViewBuilder
    private var floatingPanelsLayer: some View {
        // Floating panels from database
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

    // MARK: - Top Bar (Minimal)

    private var topBar: some View {
        HStack(spacing: 16) {
            // Close button (X only, cleaner)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Annotation count (centered)
            HStack(spacing: 4) {
                Image(systemName: "note.text")
                    .font(.system(size: 11))
                Text("\(viewModel.state.allAnnotations.count)")
                    .font(.system(size: 11, weight: .medium))
                Text("annotations")
                    .font(.system(size: 11))
            }
            .foregroundColor(.white.opacity(0.5))

            Spacer()

            // Right side actions
            HStack(spacing: 8) {
                // Research Agent button
                Button {
                    showResearchAgentSheet = true
                } label: {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#06B6D4"))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "#06B6D4").opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)

                // Command-K button
                Button {
                    showCommandK = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                        Text("⌘K")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func handleRadialAction(_ action: RadialAction) {
        viewModel.radialMenuPosition = nil

        switch action.type {
        case .createNote:
            // Create note atom and add as panel
            Task {
                if let noteAtom = await viewModel.createNote() {
                    addPanelForAtom(noteAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createContent:
            Task {
                if let contentAtom = await viewModel.createContent() {
                    addPanelForAtom(contentAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createResearch:
            Task {
                if let researchAtom = await viewModel.createResearch() {
                    addPanelForAtom(researchAtom, at: viewModel.lastTapPosition)
                }
            }

        case .createConnection:
            Task {
                if let connectionAtom = await viewModel.createConnection() {
                    addPanelForAtom(connectionAtom, at: viewModel.lastTapPosition)
                }
            }

        case .researchAgent:
            showResearchAgentSheet = true

        case .fromDatabase:
            showCommandK = true
        }
    }

    private func addPanelForAtom(_ atom: Atom, at position: CGPoint) {
        panelManager.addPanel(
            atomUUID: atom.uuid,
            atomType: atom.type,
            position: position
        )
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
        // Parse structured data from atom
        guard let structuredJSON = atom.structured,
              let data = structuredJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Extract source info
        if let url = json["url"] as? String ?? json["source_url"] as? String {
            state.contentType = ResearchSource.detectContentType(from: url)

            state.source = ResearchSource(
                url: url,
                platform: json["platform"] as? String ?? ResearchSource.detectPlatform(from: url),
                author: json["author"] as? String,
                channelName: json["channel"] as? String ?? json["channel_name"] as? String,
                publishedAt: nil, // Would parse from json["published_at"]
                duration: json["duration"] as? TimeInterval ?? parseDuration(json["duration_string"] as? String),
                thumbnailURL: json["thumbnail_url"] as? String ?? json["thumbnail"] as? String
            )
        }

        // Parse transcript if available
        if let transcriptData = json["transcript"] as? [[String: Any]] {
            state.transcriptSections = transcriptData.compactMap { segmentData -> TranscriptSection? in
                guard let start = segmentData["start"] as? TimeInterval,
                      let end = segmentData["end"] as? TimeInterval,
                      let text = segmentData["text"] as? String else {
                    return nil
                }

                return TranscriptSection(
                    startTime: start,
                    endTime: end,
                    text: text,
                    speakerName: segmentData["speaker"] as? String
                )
            }
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

    func editAnnotation(_ annotation: ResearchAnnotation) {
        // Would open edit sheet
        print("Edit annotation: \(annotation.content)")
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
            title: "New Connection",
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
    func editInstagramAnnotation(_ annotation: InstagramAnnotation) {
        // Would open edit sheet - for now just log
        print("Edit Instagram annotation: \(annotation.id)")
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
                updatedAtom.updatedAt = ISO8601DateFormatter().string(from: Date())
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
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "#06B6D4"))

                Text("Research Agent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }

            Text("Ask a question and the Research Agent will search the web and synthesize findings.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Query input
            TextField("What would you like to research?", text: $query, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .focused($isFocused)
                .lineLimit(3...6)

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))

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
                    .background(Color(hex: "#06B6D4"), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(query.isEmpty)
                .opacity(query.isEmpty ? 0.5 : 1)
            }
        }
        .padding(24)
        .frame(width: 450)
        .background(Color(hex: "#1A1A25"))
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

    private let agentColor = Color(hex: "#06B6D4") // Cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12))
                    .foregroundColor(agentColor)

                Text("RESEARCH AGENT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(agentColor)
                    .tracking(0.8)

                Spacer()

                // Status indicator
                statusBadge

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            // Query
            Text(result.query)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)

            Divider()
                .background(Color.white.opacity(0.1))

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
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .shadow(
            color: result.status == .complete ? agentColor.opacity(0.2) : Color.black.opacity(0.3),
            radius: isHovered ? 16 : 10
        )
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
                Text("Searching...")
                    .font(.system(size: 9))
                    .foregroundColor(agentColor)
            }

        case .complete:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#22C55E"))
                Text("Complete")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#22C55E"))
            }

        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.red)
                Text("Failed")
                    .font(.system(size: 9))
                    .foregroundColor(Color.red)
            }

        case .pending:
            Text("Pending")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Content Views

    private var runningContent: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(agentColor)

            Text("Searching sources...")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var completeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Summary
            Text(result.summary)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(isExpanded ? nil : 4)

            // Citations count
            if !result.citations.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                    Text("\(result.citations.count) sources")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white.opacity(0.5))
            }

            // Actions
            HStack {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "View full")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(agentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onConvertToAtom) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 10))
                        Text("Save as Atom")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(agentColor.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var failedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(Color.red.opacity(0.7))

            Text("Research failed. Please try again.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Edit Query") {
                    // Would open edit sheet
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))

                Button("Retry") {
                    // Would retry query
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(agentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var pendingContent: some View {
        Text("Waiting to start...")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // MARK: - Styling

    private var panelBackground: some View {
        ZStack {
            Color(hex: "#1A1A25")
            LinearGradient(
                colors: [agentColor.opacity(0.03), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch result.status {
        case .complete: return Color(hex: "#22C55E").opacity(0.5) // Green
        case .failed: return Color.red.opacity(0.5)
        case .running: return agentColor.opacity(0.3)
        case .pending: return Color.white.opacity(0.1)
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
