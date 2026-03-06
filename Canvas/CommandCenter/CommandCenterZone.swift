// Canvas/CommandCenter/CommandCenterZone.swift
// Data model and persistence for Command Center zones
// March 2026

import SwiftUI

// MARK: - Zone Type

enum CommandCenterZoneType: String, Codable, CaseIterable {
    // Unified dashboard (replaces all legacy zones)
    case dashboard

    // Legacy zone types (kept for migration detection)
    case welcomeHub
    case planningDock
    case goalForge
    case questBoard
    case habitTracker
    case visionBoard
    case canvasEmbed
    case notes
    case bookmarks

    var displayName: String {
        switch self {
        case .dashboard:     return "Command Center"
        case .welcomeHub:    return "Welcome Hub"
        case .planningDock:  return "Planning Dock"
        case .goalForge:     return "Goal Forge"
        case .questBoard:    return "Quest Board"
        case .habitTracker:  return "Habit Tracker"
        case .visionBoard:   return "Vision Board"
        case .canvasEmbed:   return "Canvas"
        case .notes:         return "Notes"
        case .bookmarks:     return "Bookmarks"
        }
    }

    var iconName: String {
        switch self {
        case .dashboard:     return "square.grid.3x1.below.line.grid.1x2"
        case .welcomeHub:    return "sun.max"
        case .planningDock:  return "calendar.badge.clock"
        case .goalForge:     return "target"
        case .questBoard:    return "flag.2.crossed"
        case .habitTracker:  return "repeat"
        case .visionBoard:   return "photo.on.rectangle.angled"
        case .canvasEmbed:   return "square.grid.3x3"
        case .notes:         return "note.text"
        case .bookmarks:     return "bookmark"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .dashboard:     return CGSize(width: 1400, height: 900)
        case .welcomeHub:    return CGSize(width: 600, height: 700)
        case .planningDock:  return CGSize(width: 700, height: 800)
        case .goalForge:     return CGSize(width: 500, height: 400)
        case .questBoard:    return CGSize(width: 500, height: 500)
        case .habitTracker:  return CGSize(width: 400, height: 400)
        case .visionBoard:   return CGSize(width: 500, height: 400)
        case .canvasEmbed:   return CGSize(width: 500, height: 400)
        case .notes:         return CGSize(width: 400, height: 400)
        case .bookmarks:     return CGSize(width: 400, height: 400)
        }
    }

    var accentColor: Color {
        switch self {
        case .dashboard:     return DS.accent
        case .welcomeHub:    return DS.accent
        case .planningDock:  return DS.entityTask
        case .goalForge:     return Color(hex: "D97706")
        case .questBoard:    return Color(hex: "6366F1")
        case .habitTracker:  return DS.green
        case .visionBoard:   return DS.entityConnection
        case .canvasEmbed:   return DS.entityContent
        case .notes:         return DS.entityNote
        case .bookmarks:     return DS.entityReadwise
        }
    }

    var defaultPosition: CGPoint {
        switch self {
        case .dashboard:     return .zero
        case .welcomeHub:    return .zero
        case .goalForge:     return CGPoint(x: 0, y: -900)
        case .planningDock:  return CGPoint(x: 800, y: 0)
        case .questBoard:    return CGPoint(x: -800, y: 0)
        default:             return CGPoint(x: 0, y: 900)
        }
    }

    /// Core zones — single unified dashboard
    static var coreZones: [CommandCenterZoneType] {
        [.dashboard]
    }

    /// Legacy zone types used before the dashboard redesign
    static var legacyZoneTypes: Set<String> {
        ["welcomeHub", "planningDock", "goalForge", "questBoard"]
    }
}

