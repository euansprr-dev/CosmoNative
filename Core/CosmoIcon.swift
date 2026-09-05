import SwiftUI

/// The vocabulary of Cosmo's places and objects. Custom artwork belongs to
/// identities; familiar actions stay SF Symbols. Never infer meaning from a
/// raw symbol string: `link` the action and Concept the object are different.
enum CosmoIcon: Hashable, Sendable {
    case space, command, content, swipe, idea, concept, research, pipeline
    case inbox, today, upcoming, anytime, someday, logbook, habits, reports
    case calendar, clients, creators, discover, boards, captureLanes, commands
    case task, project, area, note, library
    case system(String)

    var assetName: String? {
        switch self {
        case .space: return "cosmo.space"
        case .command: return "cosmo.command"
        case .content: return "cosmo.content"
        case .swipe: return "cosmo.swipe"
        case .idea: return "cosmo.idea"
        case .concept: return "cosmo.concept"
        case .research: return "cosmo.research"
        case .pipeline: return "cosmo.pipeline"
        default: return nil
        }
    }

    /// Native representation for APIs that explicitly require an SF Symbol
    /// name (menus, persisted user choices, and platform integrations).
    var systemName: String {
        switch self {
        case .space: return "rectangle.3.group"
        case .command: return "safari"
        case .content: return "doc.richtext"
        case .swipe: return "rectangle.stack"
        case .idea: return "lightbulb"
        case .concept: return "point.3.connected.trianglepath.dotted"
        case .research: return "book.closed"
        case .pipeline: return "rectangle.split.3x1"
        case .inbox: return "tray"
        case .today: return "sun.max"
        case .upcoming: return "calendar.badge.clock"
        case .anytime: return "square.stack.3d.up"
        case .someday: return "archivebox"
        case .logbook: return "checkmark.rectangle.stack"
        case .habits: return "repeat"
        case .reports: return "chart.bar"
        case .calendar: return "calendar"
        case .clients: return "person.crop.rectangle"
        case .creators: return "person.2"
        case .discover: return "binoculars"
        case .boards: return "square.grid.2x2"
        case .captureLanes: return "tray.2"
        case .commands: return "terminal"
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .area: return "square.stack"
        case .note: return "note.text"
        case .library: return "books.vertical"
        case .system(let name): return name
        }
    }
}

extension Image {
    /// A real symbol image: inherits font size, weight, scale and foreground
    /// style without fixed frames, rasterization, or per-view sizing recipes.
    init(cosmo icon: CosmoIcon) {
        if let asset = icon.assetName {
            self.init(asset)
        } else {
            self.init(systemName: icon.systemName)
        }
    }
}
