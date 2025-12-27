// CosmoOS/Sync/StatePersistence.swift
// Persists UI state locally - window positions, canvas state, etc.
// Ensures nothing moves or glitches on restart

import Foundation
import SwiftUI

@MainActor
class StatePersistence: ObservableObject {
    static let shared = StatePersistence()

    private let userDefaults = UserDefaults.standard
    private let stateKey = "com.cosmo.ui-state"

    // MARK: - Window State
    struct WindowState: Codable {
        var frame: CGRect
        var isVisible: Bool
        var isMinimized: Bool

        init(frame: CGRect = .zero, isVisible: Bool = true, isMinimized: Bool = false) {
            self.frame = frame
            self.isVisible = isVisible
            self.isMinimized = isMinimized
        }
    }

    // MARK: - Canvas State
    struct CanvasState: Codable {
        var viewport: CGPoint
        var zoom: CGFloat
        var selectedBlockIds: [String]

        init(viewport: CGPoint = .zero, zoom: CGFloat = 1.0, selectedBlockIds: [String] = []) {
            self.viewport = viewport
            self.zoom = zoom
            self.selectedBlockIds = selectedBlockIds
        }
    }

    // MARK: - App State
    struct AppUIState: Codable {
        var mainWindowState: WindowState
        var cosmoDockState: WindowState
        var voicePillState: WindowState
        var canvasState: CanvasState
        var selectedSection: String
        var sidebarWidth: CGFloat
        var lastOpenedEntityType: String?
        var lastOpenedEntityId: Int64?

        init() {
            self.mainWindowState = WindowState()
            self.cosmoDockState = WindowState()
            self.voicePillState = WindowState()
            self.canvasState = CanvasState()
            self.selectedSection = "today"
            self.sidebarWidth = 250
            self.lastOpenedEntityType = nil
            self.lastOpenedEntityId = nil
        }
    }

    @Published var state: AppUIState {
        didSet {
            saveState()
        }
    }

    private init() {
        state = Self.loadState()
    }

    // MARK: - Save State
    private func saveState() {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: stateKey)
            print("💾 UI state saved")
        } catch {
            print("❌ Failed to save UI state: \(error)")
        }
    }

    // MARK: - Load State
    private static func loadState() -> AppUIState {
        guard let data = UserDefaults.standard.data(forKey: "com.cosmo.ui-state"),
              let state = try? JSONDecoder().decode(AppUIState.self, from: data) else {
            return AppUIState()
        }
        print("📂 UI state loaded")
        return state
    }

    // MARK: - Window State
    func saveWindowState(_ windowId: String, frame: CGRect, isVisible: Bool) {
        switch windowId {
        case "main":
            state.mainWindowState = WindowState(frame: frame, isVisible: isVisible)
        case "cosmoDock":
            state.cosmoDockState = WindowState(frame: frame, isVisible: isVisible)
        case "voicePill":
            state.voicePillState = WindowState(frame: frame, isVisible: isVisible)
        default:
            break
        }
    }

    func getWindowState(_ windowId: String) -> WindowState? {
        switch windowId {
        case "main": return state.mainWindowState
        case "cosmoDock": return state.cosmoDockState
        case "voicePill": return state.voicePillState
        default: return nil
        }
    }

    // MARK: - Canvas State
    func saveCanvasState(viewport: CGPoint, zoom: CGFloat, selectedBlockIds: [String]) {
        state.canvasState = CanvasState(
            viewport: viewport,
            zoom: zoom,
            selectedBlockIds: selectedBlockIds
        )
    }

    func getCanvasState() -> CanvasState {
        return state.canvasState
    }

    // MARK: - Navigation State
    func saveSelectedSection(_ section: NavigationSection) {
        state.selectedSection = section.rawValue
    }

    func getSelectedSection() -> NavigationSection {
        return NavigationSection(rawValue: state.selectedSection) ?? .today
    }

    // MARK: - Sidebar Width
    func saveSidebarWidth(_ width: CGFloat) {
        state.sidebarWidth = width
    }

    func getSidebarWidth() -> CGFloat {
        return state.sidebarWidth
    }

    // MARK: - Last Opened Entity
    func saveLastOpenedEntity(type: EntityType, id: Int64) {
        state.lastOpenedEntityType = type.rawValue
        state.lastOpenedEntityId = id
    }

    func getLastOpenedEntity() -> (type: EntityType, id: Int64)? {
        guard let typeStr = state.lastOpenedEntityType,
              let type = EntityType(rawValue: typeStr),
              let id = state.lastOpenedEntityId else {
            return nil
        }
        return (type, id)
    }

    // MARK: - Reset State
    func resetState() {
        state = AppUIState()
    }
}

// NOTE: CGRect and CGPoint are already Codable in CoreGraphics (macOS 13+)
