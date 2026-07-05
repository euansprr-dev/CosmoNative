// CosmoOS/UI/CosmoWindow/CosmoContextProvider.swift
// Protocol for views to provide context to the global Cosmo window
// February 2026

import SwiftUI

// MARK: - Context Provider Protocol

/// Protocol that views conform to for providing live context to the Cosmo AI window.
/// Each view registers its provider with `CosmoWindowViewModel.shared.updateContext(provider:)`.
/// Implementations should be lightweight -- just return current state, no computation.
@MainActor
protocol CosmoContextProvider: AnyObject {
    var contextType: CosmoContextType { get }
    var contextSummary: String { get }
    var contextData: CosmoContextData { get }
    var availableActions: [CosmoWindowAction] { get }
}

// MARK: - Context Type

/// Identifies which view is currently active and providing context.
enum CosmoContextType: String, Codable, Sendable {
    case commandCenter
    case contentFocusMode
    case swipeGallery
    case swipeStudy
    case researchFocusMode
    case connectionFocusMode
    case ideaFocusMode
    case noteFocusMode
    case library
    case plannerum
    case dayTimeline
    case thinkspaceCanvas
    case sanctuary
    case cosmoAIFocusMode
    case none

    var displayName: String {
        switch self {
        case .commandCenter: return "Command Center"
        case .contentFocusMode: return "Content"
        case .swipeGallery: return "Swipe Gallery"
        case .swipeStudy: return "Swipe Study"
        case .researchFocusMode: return "Research"
        case .connectionFocusMode: return "Concept"
        case .ideaFocusMode: return "Idea"
        case .noteFocusMode: return "Note"
        case .library: return "Library"
        case .plannerum: return "Plannerum"
        case .dayTimeline: return "Day Timeline"
        case .thinkspaceCanvas: return "Thinkspace"
        case .sanctuary: return "Sanctuary"
        case .cosmoAIFocusMode: return "Cosmo AI"
        case .none: return ""
        }
    }

    var icon: String {
        switch self {
        case .commandCenter: return "square.grid.2x2"
        case .contentFocusMode: return "doc.text"
        case .swipeGallery: return "rectangle.stack"
        case .swipeStudy: return "magnifyingglass"
        case .researchFocusMode: return "book"
        case .connectionFocusMode: return "link"
        case .ideaFocusMode: return "lightbulb"
        case .noteFocusMode: return "note.text"
        case .library: return "books.vertical"
        case .plannerum: return "calendar"
        case .dayTimeline: return "clock"
        case .thinkspaceCanvas: return "square.grid.3x3"
        case .sanctuary: return "sparkles"
        case .cosmoAIFocusMode: return "brain"
        case .none: return "circle"
        }
    }
}

// MARK: - Context Data

/// Flexible payload carrying the current view's state for AI context injection.
struct CosmoContextData: Codable, Sendable {
    var currentAtomUUID: String?
    var currentAtomType: String?
    var currentAtomTitle: String?
    var activeClientUUID: String?
    var viewSpecificData: [String: String]
    var visibleItemCount: Int?
    var activeFilters: [String]?
    var selectedText: String?

    init(
        currentAtomUUID: String? = nil,
        currentAtomType: String? = nil,
        currentAtomTitle: String? = nil,
        activeClientUUID: String? = nil,
        viewSpecificData: [String: String] = [:],
        visibleItemCount: Int? = nil,
        activeFilters: [String]? = nil,
        selectedText: String? = nil
    ) {
        self.currentAtomUUID = currentAtomUUID
        self.currentAtomType = currentAtomType
        self.currentAtomTitle = currentAtomTitle
        self.activeClientUUID = activeClientUUID
        self.viewSpecificData = viewSpecificData
        self.visibleItemCount = visibleItemCount
        self.activeFilters = activeFilters
        self.selectedText = selectedText
    }

    /// Serialize to a string block for system prompt injection.
    func toContextBlock() -> String {
        var lines: [String] = []

        if let title = currentAtomTitle {
            lines.append("Current item: \(title)")
        }
        if let type = currentAtomType {
            lines.append("Type: \(type)")
        }
        if let activeClientUUID, !activeClientUUID.isEmpty {
            lines.append("Active client UUID: \(activeClientUUID)")
        }
        if let count = visibleItemCount {
            lines.append("Visible items: \(count)")
        }
        if let filters = activeFilters, !filters.isEmpty {
            lines.append("Active filters: \(filters.joined(separator: ", "))")
        }
        if let selected = selectedText, !selected.isEmpty {
            lines.append("Selected text: \(selected)")
        }
        for (key, value) in viewSpecificData.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Active Context

/// Snapshot of the current context used by the ViewModel for rendering and AI injection.
struct CosmoActiveContext: Sendable {
    let type: CosmoContextType
    let summary: String
    let data: CosmoContextData
    let actions: [CosmoWindowAction]

    static let none = CosmoActiveContext(
        type: .none,
        summary: "",
        data: CosmoContextData(viewSpecificData: [:]),
        actions: []
    )
}

// MARK: - Window Anchor

/// Controls which side of the screen the Cosmo window anchors to.
enum CosmoWindowAnchor: String, Codable, CaseIterable, Sendable {
    case left
    case right
}
