import Foundation

enum SwipeLibraryMode: String, CaseIterable, Identifiable {
    case grid
    case clusters
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Grid"
        case .clusters: return "Clusters"
        case .compact: return "Compact"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2.fill"
        case .clusters: return "rectangle.stack.fill"
        case .compact: return "list.bullet"
        }
    }
}

enum SwipeLibrarySmartPreset: String, CaseIterable, Identifiable {
    case all
    case fearHooks
    case curiosity
    case threads
    case reels
    case highScore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .fearHooks: return "Fear hooks"
        case .curiosity: return "Curiosity"
        case .threads: return "Threads"
        case .reels: return "Reels"
        case .highScore: return "High score"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .fearHooks: return "exclamationmark.triangle.fill"
        case .curiosity: return "eye.fill"
        case .threads: return "text.line.first.and.arrowtriangle.forward"
        case .reels: return "play.rectangle.fill"
        case .highScore: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum SwipeLibrarySectionSelection: Equatable, Hashable {
    case all
    case recentlyAdded
    case highHookScore
    case unstudied
    case board(String)

    var title: String {
        switch self {
        case .all: return "All Swipes"
        case .recentlyAdded: return "Recently Added"
        case .highHookScore: return "High Hook Score"
        case .unstudied: return "Unstudied"
        case .board(let name): return name
        }
    }
}

enum SwipeLibraryShelfID: String, CaseIterable, Identifiable {
    case recentlyAdded
    case highPerforming
    case hooksToTry
    case continueStudying

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .highPerforming: return "High-Performing Patterns"
        case .hooksToTry: return "Hooks to Try"
        case .continueStudying: return "Continue Studying"
        }
    }
}

struct SwipeLibraryShelf: Identifiable {
    let id: SwipeLibraryShelfID
    let items: [SwipeGalleryItem]

    var title: String { id.title }
}

struct SwipeLibraryFacetSummary: Equatable {
    var totalCount: Int
    var filteredCount: Int
    var highScoreCount: Int
    var unstudiedCount: Int
    var averageHookScore: Double?

    static let empty = SwipeLibraryFacetSummary(
        totalCount: 0,
        filteredCount: 0,
        highScoreCount: 0,
        unstudiedCount: 0,
        averageHookScore: nil
    )
}

struct SwipeLibraryFilterState: Equatable {
    var smartPreset: SwipeLibrarySmartPreset = .all
    var platforms: Set<String> = []
    var hookTypes: Set<SwipeHookType> = []
    var frameworks: Set<SwipeFrameworkType> = []
    var narratives: Set<NarrativeStyle> = []
    var formats: Set<ContentFormat> = []
    var creator: String?
    var niche: String?
    var onlyStudied = false
    var onlyUnstudied = false
    var minimumHookScore: Double?

    var hasActiveFilters: Bool {
        smartPreset != .all ||
        !platforms.isEmpty ||
        !hookTypes.isEmpty ||
        !frameworks.isEmpty ||
        !narratives.isEmpty ||
        !formats.isEmpty ||
        creator != nil ||
        niche != nil ||
        onlyStudied ||
        onlyUnstudied ||
        minimumHookScore != nil
    }

    mutating func reset() {
        self = SwipeLibraryFilterState()
    }
}
