// CosmoOS/UI/FocusMode/FloatingPanel/FloatingPanelManager.swift
// Manages floating panels on Focus Mode canvas
// Handles lifecycle, persistence, and content loading
// December 2025 - Focus Mode floating panel system

import SwiftUI
import Combine
import GRDB

// MARK: - Floating Panel Manager

/// Manages the lifecycle and state of floating panels on a Focus Mode canvas.
/// Handles adding, removing, updating panels, and persisting their state.
@MainActor
class FloatingPanelManager: ObservableObject {
    // MARK: - Published State

    /// All panels currently on the canvas
    @Published private(set) var panels: [FloatingPanelData] = []

    /// Content loaded for each panel (keyed by panel ID)
    @Published private(set) var panelContents: [UUID: FloatingPanelContent] = [:]

    /// Currently selected panel ID
    @Published var selectedPanelID: UUID?

    /// Loading state for panel content
    @Published private(set) var isLoadingContent: Bool = false

    // MARK: - Properties

    /// UUID of the focus atom this canvas belongs to
    private let focusAtomUUID: String

    /// UserDefaults for persistence
    private let userDefaults = UserDefaults.standard

    /// Cancellables for async operations
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(focusAtomUUID: String) {
        self.focusAtomUUID = focusAtomUUID
        loadPersistedState()
    }

    // MARK: - Panel Management

    /// Add a new panel to the canvas
    /// - Parameters:
    ///   - atomUUID: UUID of the atom to display
    ///   - atomType: Type of the atom
    ///   - position: Initial position on canvas
    ///   - displayState: Initial display state (default: .standard)
    /// - Returns: The created panel data
    @discardableResult
    func addPanel(
        atomUUID: String,
        atomType: AtomType,
        position: CGPoint,
        displayState: FloatingPanelDisplayState = .standard
    ) -> FloatingPanelData {
        // Check if panel for this atom already exists
        if let existingPanel = panels.first(where: { $0.atomUUID == atomUUID }) {
            // Select and return existing panel
            selectPanel(existingPanel.id)
            return existingPanel
        }

        let panel = FloatingPanelData(
            atomUUID: atomUUID,
            atomType: atomType,
            position: position,
            displayState: displayState
        )

        withAnimation(ProMotionSprings.snappy) {
            panels.append(panel)
        }

        // Load content for the new panel
        Task {
            await loadContent(for: panel)
        }

        // Persist state
        persistState()

        return panel
    }

    /// Remove a panel from the canvas
    /// - Parameter id: Panel ID to remove
    func removePanel(id: UUID) {
        withAnimation(ProMotionSprings.snappy) {
            panels.removeAll { $0.id == id }
            panelContents.removeValue(forKey: id)

            if selectedPanelID == id {
                selectedPanelID = nil
            }
        }

        persistState()
    }

    /// Remove panel by atom UUID
    /// - Parameter atomUUID: Atom UUID of the panel to remove
    func removePanel(atomUUID: String) {
        if let panel = panels.first(where: { $0.atomUUID == atomUUID }) {
            removePanel(id: panel.id)
        }
    }

    /// Update a panel's data
    /// - Parameter panel: Updated panel data
    func updatePanel(_ panel: FloatingPanelData) {
        if let index = panels.firstIndex(where: { $0.id == panel.id }) {
            panels[index] = panel
            persistState()
        }
    }

    /// Update panel position
    /// - Parameters:
    ///   - id: Panel ID
    ///   - position: New position
    func updatePosition(_ id: UUID, position: CGPoint) {
        if let index = panels.firstIndex(where: { $0.id == id }) {
            panels[index].position = position
            persistState()
        }
    }

    /// Update panel display state
    /// - Parameters:
    ///   - id: Panel ID
    ///   - state: New display state
    func updateDisplayState(_ id: UUID, state: FloatingPanelDisplayState) {
        if let index = panels.firstIndex(where: { $0.id == id }) {
            withAnimation(ProMotionSprings.snappy) {
                panels[index].displayState = state
            }
            persistState()
        }
    }

    /// Cycle panel to next display state
    /// - Parameter id: Panel ID
    func cycleDisplayState(_ id: UUID) {
        if let index = panels.firstIndex(where: { $0.id == id }) {
            withAnimation(ProMotionSprings.snappy) {
                panels[index].displayState = panels[index].displayState.next
            }
            persistState()
        }
    }

    // MARK: - Selection

    /// Select a panel
    /// - Parameter id: Panel ID to select (nil to deselect all)
    func selectPanel(_ id: UUID?) {
        // Deselect previously selected panel
        if let previousID = selectedPanelID,
           let index = panels.firstIndex(where: { $0.id == previousID }) {
            panels[index].isSelected = false
        }

        // Select new panel
        selectedPanelID = id
        if let id = id, let index = panels.firstIndex(where: { $0.id == id }) {
            panels[index].isSelected = true
        }
    }

    /// Deselect all panels
    func deselectAll() {
        selectPanel(nil)
    }

    /// Get the currently selected panel
    var selectedPanel: FloatingPanelData? {
        guard let id = selectedPanelID else { return nil }
        return panels.first { $0.id == id }
    }

    // MARK: - Content Loading

    /// Load content for a specific panel from the database
    /// - Parameter panel: Panel to load content for
    func loadContent(for panel: FloatingPanelData) async {
        // Check if content already loaded
        guard panelContents[panel.id] == nil else { return }

        // Set placeholder while loading
        panelContents[panel.id] = .placeholder

        do {
            let content = try await fetchAtomContent(uuid: panel.atomUUID, type: panel.atomType)
            await MainActor.run {
                panelContents[panel.id] = content
            }
        } catch {
            print("⚠️ FloatingPanelManager: Failed to load content for \(panel.atomUUID): \(error)")
            // Keep placeholder on error
        }
    }

    /// Load content for all panels
    func loadAllContent() async {
        isLoadingContent = true
        defer { isLoadingContent = false }

        await withTaskGroup(of: Void.self) { group in
            for panel in panels {
                group.addTask {
                    await self.loadContent(for: panel)
                }
            }
        }
    }

    /// Refresh content for a specific panel
    /// - Parameter id: Panel ID to refresh
    func refreshContent(id: UUID) async {
        guard let panel = panels.first(where: { $0.id == id }) else { return }

        // Clear existing content to force reload
        panelContents.removeValue(forKey: id)
        await loadContent(for: panel)
    }

    /// Fetch atom content from database
    private func fetchAtomContent(uuid: String, type: AtomType) async throws -> FloatingPanelContent {
        // Use AtomRepository to fetch the atom
        guard let atom = try await AtomRepository.shared.fetch(uuid: uuid) else {
            throw FloatingPanelError.atomNotFound
        }

        // Extract metadata based on atom type
        var author: String?
        var duration: String?
        var platform: String?
        var sourceType: String?
        var thumbnailURL: String?

        // Try to parse structured data for research atoms
        if type == .research, let structuredData = atom.structured {
            if let data = structuredData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                author = json["author"] as? String ?? json["channel"] as? String
                duration = json["duration"] as? String
                platform = json["platform"] as? String ?? json["source_type"] as? String
                sourceType = json["source_type"] as? String
                thumbnailURL = json["thumbnail_url"] as? String
            }
        }

        // Count annotations and linked atoms
        let annotationCount = await countAnnotations(for: uuid)
        let linkedCount = await countLinkedAtoms(for: uuid)

        return FloatingPanelContent(
            title: atom.title ?? "Untitled",
            preview: atom.body?.prefix(200).description,
            thumbnailURL: thumbnailURL,
            metadata: FloatingPanelContent.PanelMetadata(
                author: author,
                duration: duration,
                platform: platform,
                sourceType: sourceType
            ),
            annotationCount: annotationCount,
            linkedCount: linkedCount,
            updatedAt: parseDate(atom.updatedAt) ?? Date()
        )
    }

    /// Parse ISO8601 date string to Date
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    /// Count annotations for an atom
    private func countAnnotations(for atomUUID: String) async -> Int {
        // Query annotations from database
        // This would use the actual annotation storage when implemented
        // For now, return 0 as placeholder
        return 0
    }

    /// Count linked atoms
    private func countLinkedAtoms(for atomUUID: String) async -> Int {
        do {
            let queryEngine = GraphQueryEngine()
            let edges = try await queryEngine.getEdges(for: atomUUID, direction: .both)
            return edges.count
        } catch {
            return 0
        }
    }

    // MARK: - Persistence

    /// Persist current panel state to UserDefaults
    private func persistState() {
        let state = CanvasPanelsState(focusAtomUUID: focusAtomUUID, panels: panels)
        let key = CanvasPanelsState.persistenceKey(focusAtomUUID: focusAtomUUID)

        if let encoded = try? JSONEncoder().encode(state) {
            userDefaults.set(encoded, forKey: key)
        }
    }

    /// Load persisted panel state from UserDefaults
    private func loadPersistedState() {
        let key = CanvasPanelsState.persistenceKey(focusAtomUUID: focusAtomUUID)

        guard let data = userDefaults.data(forKey: key),
              let state = try? JSONDecoder().decode(CanvasPanelsState.self, from: data) else {
            return
        }

        panels = state.panels

        // Load content for all panels
        Task {
            await loadAllContent()
        }
    }

    /// Clear all persisted state for this canvas
    func clearPersistedState() {
        let key = CanvasPanelsState.persistenceKey(focusAtomUUID: focusAtomUUID)
        userDefaults.removeObject(forKey: key)
    }

    // MARK: - Bulk Operations

    /// Remove all panels from canvas
    func removeAllPanels() {
        withAnimation(ProMotionSprings.snappy) {
            panels.removeAll()
            panelContents.removeAll()
            selectedPanelID = nil
        }
        persistState()
    }

    /// Arrange panels in a grid layout
    /// - Parameters:
    ///   - origin: Top-left origin point
    ///   - columns: Number of columns
    ///   - spacing: Spacing between panels
    func arrangeInGrid(origin: CGPoint, columns: Int = 3, spacing: CGFloat = 20) {
        guard !panels.isEmpty else { return }

        withAnimation(ProMotionSprings.gentle) {
            for (index, _) in panels.enumerated() {
                let col = index % columns
                let row = index / columns

                let panelWidth = panels[index].displayState.width
                let panelHeight = panels[index].displayState.minHeight

                let x = origin.x + CGFloat(col) * (panelWidth + spacing) + panelWidth / 2
                let y = origin.y + CGFloat(row) * (panelHeight + spacing) + panelHeight / 2

                panels[index].position = CGPoint(x: x, y: y)
            }
        }

        persistState()
    }

    /// Set all panels to same display state
    /// - Parameter state: Display state to apply
    func setAllDisplayState(_ state: FloatingPanelDisplayState) {
        withAnimation(ProMotionSprings.snappy) {
            for index in panels.indices {
                panels[index].displayState = state
            }
        }
        persistState()
    }

    // MARK: - Computed Properties

    /// Number of panels on canvas
    var panelCount: Int {
        panels.count
    }

    /// Check if canvas has any panels
    var isEmpty: Bool {
        panels.isEmpty
    }

    /// Get content for a panel
    func content(for panelID: UUID) -> FloatingPanelContent {
        panelContents[panelID] ?? .placeholder
    }

    /// Get binding for a specific panel
    func binding(for panelID: UUID) -> Binding<FloatingPanelData>? {
        guard let index = panels.firstIndex(where: { $0.id == panelID }) else {
            return nil
        }

        return Binding(
            get: { self.panels[index] },
            set: { self.updatePanel($0) }
        )
    }
}

// MARK: - Errors

enum FloatingPanelError: Error, LocalizedError {
    case atomNotFound
    case contentLoadFailed

    var errorDescription: String? {
        switch self {
        case .atomNotFound:
            return "Atom not found in database"
        case .contentLoadFailed:
            return "Failed to load panel content"
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension FloatingPanelManager {
    /// Create a preview manager with sample data
    static var preview: FloatingPanelManager {
        let manager = FloatingPanelManager(focusAtomUUID: "preview-focus-atom")

        // Add sample panels
        let panel1 = FloatingPanelData(
            atomUUID: "sample-research-1",
            atomType: .research,
            position: CGPoint(x: 200, y: 150),
            displayState: .standard
        )

        let panel2 = FloatingPanelData(
            atomUUID: "sample-connection-1",
            atomType: .connection,
            position: CGPoint(x: 500, y: 200),
            displayState: .collapsed
        )

        let panel3 = FloatingPanelData(
            atomUUID: "sample-idea-1",
            atomType: .idea,
            position: CGPoint(x: 300, y: 400),
            displayState: .expanded
        )

        manager.panels = [panel1, panel2, panel3]

        // Add sample content
        manager.panelContents[panel1.id] = FloatingPanelContent(
            title: "Dan Koe - How to Reinvent Your Life in 6-12 Months",
            preview: "Identity is not fixed — it's a story you tell yourself. Real transformation comes from subtraction, not addition.",
            thumbnailURL: nil,
            metadata: FloatingPanelContent.PanelMetadata(
                author: "Dan Koe",
                duration: "42:18",
                platform: "YouTube",
                sourceType: "youtube"
            ),
            annotationCount: 5,
            linkedCount: 3,
            updatedAt: Date()
        )

        manager.panelContents[panel2.id] = FloatingPanelContent(
            title: "Atomic Habits Framework",
            preview: "The 4 laws of behavior change: make it obvious, make it attractive, make it easy, make it satisfying.",
            thumbnailURL: nil,
            metadata: FloatingPanelContent.PanelMetadata(
                author: nil,
                duration: nil,
                platform: nil,
                sourceType: nil
            ),
            annotationCount: 0,
            linkedCount: 7,
            updatedAt: Date()
        )

        manager.panelContents[panel3.id] = FloatingPanelContent(
            title: "Morning Routine Optimization",
            preview: "Start with exercise, then meditation, then deep work. No phone for first hour.",
            thumbnailURL: nil,
            metadata: FloatingPanelContent.PanelMetadata(
                author: nil,
                duration: nil,
                platform: nil,
                sourceType: nil
            ),
            annotationCount: 2,
            linkedCount: 1,
            updatedAt: Date()
        )

        return manager
    }
}
#endif
