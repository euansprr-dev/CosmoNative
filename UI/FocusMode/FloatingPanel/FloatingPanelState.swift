// CosmoOS/UI/FocusMode/FloatingPanel/FloatingPanelState.swift
// Data models and state management for floating panels
// December 2025 - Focus Mode floating panel system

import SwiftUI
import Foundation

// MARK: - Panel Display State

/// The three visual states a floating panel can be in
enum FloatingPanelDisplayState: String, Codable, CaseIterable {
    /// Collapsed: Compact view showing just icon + title (200pt width)
    case collapsed

    /// Standard: Default view with preview content (280pt width)
    case standard

    /// Expanded: Full view with all details (380pt width, variable height)
    case expanded

    /// Width for this display state
    var width: CGFloat {
        switch self {
        case .collapsed: return 200
        case .standard: return 280
        case .expanded: return 380
        }
    }

    /// Minimum height for this display state
    var minHeight: CGFloat {
        switch self {
        case .collapsed: return 60
        case .standard: return 140
        case .expanded: return 280
        }
    }

    /// Keyboard shortcut number (1, 2, 3)
    var keyboardShortcut: Character {
        switch self {
        case .collapsed: return "1"
        case .standard: return "2"
        case .expanded: return "3"
        }
    }

    /// Next state when toggling
    var next: FloatingPanelDisplayState {
        switch self {
        case .collapsed: return .standard
        case .standard: return .expanded
        case .expanded: return .collapsed
        }
    }
}

// MARK: - Floating Panel Data

/// Represents a floating panel on the canvas
struct FloatingPanelData: Identifiable, Codable, Equatable {
    let id: UUID

    /// The UUID of the atom this panel represents
    let atomUUID: String

    /// The type of atom
    let atomType: AtomType

    /// Position in canvas coordinates
    var position: CGPoint

    /// Current display state
    var displayState: FloatingPanelDisplayState

    /// Custom dimensions if user resized (only for expanded state)
    var customSize: CGSize?

    /// Whether this panel is selected
    var isSelected: Bool = false

    /// When this panel was added to canvas
    let addedAt: Date

    init(
        id: UUID = UUID(),
        atomUUID: String,
        atomType: AtomType,
        position: CGPoint,
        displayState: FloatingPanelDisplayState = .standard,
        customSize: CGSize? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.atomUUID = atomUUID
        self.atomType = atomType
        self.position = position
        self.displayState = displayState
        self.customSize = customSize
        self.addedAt = addedAt
    }

    /// Current effective size
    var effectiveSize: CGSize {
        if displayState == .expanded, let custom = customSize {
            return custom
        }
        return CGSize(width: displayState.width, height: displayState.minHeight)
    }
}

// MARK: - Panel Content

/// Content data loaded for a floating panel
struct FloatingPanelContent: Equatable {
    let title: String
    let preview: String?
    let thumbnailURL: String?
    let metadata: PanelMetadata
    let annotationCount: Int
    let linkedCount: Int
    let updatedAt: Date

    struct PanelMetadata: Equatable {
        let author: String?
        let duration: String?
        let platform: String?
        let sourceType: String?
    }

    static let placeholder = FloatingPanelContent(
        title: "Loading...",
        preview: nil,
        thumbnailURL: nil,
        metadata: PanelMetadata(author: nil, duration: nil, platform: nil, sourceType: nil),
        annotationCount: 0,
        linkedCount: 0,
        updatedAt: Date()
    )
}

// MARK: - Panel Type Configuration

/// Visual configuration for different panel atom types
struct FloatingPanelTypeConfig {
    let accentColor: Color
    let icon: String
    let label: String

    static func config(for atomType: AtomType) -> FloatingPanelTypeConfig {
        switch atomType {
        case .research:
            return FloatingPanelTypeConfig(
                accentColor: CosmoColors.blockResearch,
                icon: "magnifyingglass",
                label: "Research"
            )
        case .connection:
            return FloatingPanelTypeConfig(
                accentColor: CosmoColors.blockConnection,
                icon: "link.circle.fill",
                label: "Connection"
            )
        case .idea:
            return FloatingPanelTypeConfig(
                accentColor: CosmoColors.lavender,
                icon: "lightbulb.fill",
                label: "Idea"
            )
        case .task:
            return FloatingPanelTypeConfig(
                accentColor: CosmoColors.coral,
                icon: "checkmark.circle.fill",
                label: "Task"
            )
        case .content:
            return FloatingPanelTypeConfig(
                accentColor: CosmoColors.blockContent,
                icon: "doc.text.fill",
                label: "Content"
            )
        case .journalEntry:
            return FloatingPanelTypeConfig(
                accentColor: Color(hex: "#EC4899"),
                icon: "book.fill",
                label: "Journal"
            )
        default:
            return FloatingPanelTypeConfig(
                accentColor: CosmoColors.slate,
                icon: "doc",
                label: atomType.rawValue.capitalized
            )
        }
    }
}

// MARK: - Canvas Panels State

/// Persisted state for all panels on a Focus Mode canvas
struct CanvasPanelsState: Codable {
    let focusAtomUUID: String
    var panels: [FloatingPanelData]
    var lastModified: Date

    init(focusAtomUUID: String, panels: [FloatingPanelData] = []) {
        self.focusAtomUUID = focusAtomUUID
        self.panels = panels
        self.lastModified = Date()
    }

    mutating func addPanel(_ panel: FloatingPanelData) {
        panels.append(panel)
        lastModified = Date()
    }

    mutating func removePanel(id: UUID) {
        panels.removeAll { $0.id == id }
        lastModified = Date()
    }

    mutating func updatePanel(_ panel: FloatingPanelData) {
        if let index = panels.firstIndex(where: { $0.id == panel.id }) {
            panels[index] = panel
            lastModified = Date()
        }
    }
}

// MARK: - Panel Context Menu Actions

/// Actions available in the floating panel context menu
enum FloatingPanelContextAction: String, CaseIterable {
    case openFocusMode = "Open Focus Mode"
    case collapsed = "Collapsed"
    case standard = "Standard"
    case expanded = "Expanded"
    case duplicate = "Duplicate"
    case removeFromCanvas = "Remove from Canvas"
    case deleteAtom = "Delete Atom"

    var icon: String {
        switch self {
        case .openFocusMode: return "arrow.up.left.and.arrow.down.right"
        case .collapsed: return "rectangle.compress.vertical"
        case .standard: return "rectangle"
        case .expanded: return "rectangle.expand.vertical"
        case .duplicate: return "plus.square.on.square"
        case .removeFromCanvas: return "xmark.circle"
        case .deleteAtom: return "trash"
        }
    }

    var isDestructive: Bool {
        self == .deleteAtom
    }
}

// MARK: - Persistence Key

extension CanvasPanelsState {
    /// Generate UserDefaults key for this canvas state
    static func persistenceKey(focusAtomUUID: String) -> String {
        "focusModeCanvas_\(focusAtomUUID)"
    }
}
