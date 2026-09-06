import Foundation

/// A palette's origin is captured once. A destination is a value the user can
/// explicitly change; neither ever follows the last-used canvas behind it.
struct CommandKSpaceContext: Equatable, Identifiable, Sendable {
    let spaceID: String
    let spaceTitle: String
    var containerUUID: String? = nil
    var containerTitle: String? = nil
    var containerKind: SpaceCompositionKind? = nil
    var view: SpaceCompositionView? = nil
    var path: [String] = []

    var id: String { spaceID + "/" + (containerUUID ?? "root") }
    var title: String { containerTitle ?? spaceTitle }
    var breadcrumb: String { ([spaceTitle] + path).joined(separator: " › ") }
    var symbol: String { containerKind?.symbol ?? "folder" }
    var root: Self { .init(spaceID: spaceID, spaceTitle: spaceTitle) }
    var addTitle: String {
        if containerKind?.isAuthored == true { return "Attach as source to \(title)" }
        return "Add to \(title)"
    }
    var addExplanation: String {
        if containerKind?.isAuthored == true { return "Reference the original in this \(containerKind!.title.lowercased())" }
        if containerKind == .group { return "Include the original in this Group" }
        return "Keep the original in every other Space"
    }

    func supportsCreation(_ kind: SpaceCompositionKind) -> Bool {
        // Starters are rooted books/courses; a Group can collect them. Groups
        // themselves are never authored children.
        if kind != .page, containerKind?.isAuthored == true { return false }
        return true
    }
}

struct CommandKSpaceSearchInfo: Equatable, Sendable {
    let kind: SpaceCompositionKind?
    let locations: [CommandKSpaceContext]
    var location: CommandKSpaceContext? { locations.first }
    var subtitle: String? {
        let parts = [kind?.title, location?.breadcrumb].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum CommandKSpaceDestinationPurpose: Equatable {
    case create(SpaceCompositionKind)
    case add([String])
    case map
    case open
}

struct CommandKSpaceDestinationPicker: Equatable {
    let purpose: CommandKSpaceDestinationPurpose
    var root: CommandKSpaceContext?
    var destinations: [CommandKSpaceContext] = []
    var isLoading = false
}

enum CommandKSpaceError: LocalizedError {
    case chooseSpace, destinationUnavailable, invalidDestination, originalUnavailable
    var errorDescription: String? {
        switch self {
        case .chooseSpace: return "Choose a Space for this item."
        case .destinationUnavailable: return "This destination is no longer available. Choose another Space or Page."
        case .invalidDestination: return "Choose a Space or Group for this kind of item."
        case .originalUnavailable: return "This original is no longer available. Refresh your search."
        }
    }
}
