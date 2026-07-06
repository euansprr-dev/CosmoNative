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
    /// The swipe context's single landing page — hero, shelves, and the full
    /// catalog on one surface.
    case home
    case all
    case highHookScore
    case unstudied
    case boards
    case board(String)

    var title: String {
        switch self {
        case .home: return "Swipe File"
        case .all: return "Library"
        case .highHookScore: return "High Hook Score"
        case .unstudied: return "Unstudied"
        case .boards: return "Boards"
        case .board(let name): return name
        }
    }
}

enum SwipeDiscoverySectionSelection: String, CaseIterable, Identifiable, Equatable, Hashable {
    case discover
    case creators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "Discover"
        case .creators: return "Creators"
        }
    }

    var subtitle: String {
        switch self {
        case .discover: return "High-performing posts across platforms"
        case .creators: return "Profiles to study"
        }
    }
}

enum SwipeDiscoveryFilterPresentation {
    static let primaryPlatforms: [SocialPlatform] = [
        .x,
        .youtube,
        .substack,
        .instagram,
        .tiktok,
        .linkedin
    ]

    static let minimumOutlierOptions: [Double?] = [nil, 3, 5, 10, 20]

    struct FollowerPreset: Identifiable, Equatable {
        let label: String
        let range: SocialFollowerRange
        var id: String { label }
    }

    static let followerPresets: [FollowerPreset] = [
        FollowerPreset(label: "Any", range: .any),
        FollowerPreset(label: "1K – 20K", range: .range(min: 1_000, max: 20_000)),
        FollowerPreset(label: "20K – 100K", range: .range(min: 20_000, max: 100_000)),
        FollowerPreset(label: "100K – 1M", range: .range(min: 100_000, max: 1_000_000)),
        FollowerPreset(label: "1M – 8M", range: .range(min: 1_000_000, max: 8_000_000)),
        FollowerPreset(label: "8M+", range: .range(min: 8_000_000, max: nil))
    ]

    /// Screenshot-style label for the platforms list; the enum's own `displayName`
    /// returns just "X" for the Twitter/X case.
    static func platformLabel(_ platform: SocialPlatform) -> String {
        platform == .x ? "X / Twitter" : platform.displayName
    }

    static func summary(for query: SocialDiscoveryQuery) -> String {
        let platformSummary: String
        switch query.platforms.count {
        case 0:
            platformSummary = "All"
        case 1:
            platformSummary = query.platforms.first.map(platformLabel) ?? "All"
        default:
            platformSummary = "\(query.platforms.count) platforms"
        }

        let outlierSummary = query.minimumOutlierMultiplier
            .map { "\(Int($0))×" } ?? "Any score"

        return "\(platformSummary) · \(query.postedWindow.displayName) · \(outlierSummary)"
    }
}

extension SocialPostedWindow {
    var displayName: String {
        switch self {
        case .lastWeek: return "Last week"
        case .lastMonth: return "Last month"
        case .lastThreeMonths: return "Last 3 months"
        case .lastYear: return "Last year"
        case .allTime: return "All time"
        }
    }
}

extension SocialDiscoverySort {
    var displayName: String {
        switch self {
        case .highestOutlier: return "Highest outlier"
        case .newest: return "Newest"
        case .mostViewed: return "Most viewed"
        case .mostLiked: return "Most liked"
        case .mostCommented: return "Most commented"
        case .mostShared: return "Most shared"
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
