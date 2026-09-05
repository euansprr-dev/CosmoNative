// CosmoOS/Canvas/Spaces/SpaceModels.swift
// A Space (thinkspace) is shaped by its purpose: a KIND chooses which VIEWS
// exist and which one opens. The switcher shows only enabled views; the
// space remembers the last one you used. Metadata stores raw strings so an
// unknown value from a newer client can never make the whole blob undecodable
// (a throwing decode used to reset clusters/places/flows — see
// ThinkspaceMetadata.init(from:)). `SpaceViewResolver` turns raws into views.

import SwiftUI

// MARK: - Views (the lenses a space can show)

enum SpaceView: String, Codable, CaseIterable, Identifiable, Sendable {
    case home
    case canvas
    case library
    case deepDive
    case board
    case calendar
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Overview"
        case .canvas: return "Canvas"
        case .library: return "Materials"
        case .deepDive: return "Deep Dive"
        case .board: return "Board"
        case .calendar: return "Calendar"
        case .tasks: return "Tasks"
        }
    }

    var icon: String {
        switch self {
        case .home: return "doc.text"
        case .canvas: return "square.grid.3x3"
        case .library: return "folder"
        case .deepDive: return "circle.hexagongrid.circle"
        case .board: return "rectangle.split.3x1"
        case .calendar: return "calendar"
        case .tasks: return "checklist"
        }
    }

    /// One-line teaching copy for the composer's view chips.
    var blurb: String {
        switch self {
        case .home: return "Your working notes, questions and linked outputs."
        case .canvas: return "Infinite canvas — position carries meaning."
        case .library: return "Finder-grade browser of everything in the space."
        case .deepDive: return "The topic's home: questions, sessions, seedlings."
        case .board: return "Content in this space by stage."
        case .calendar: return "Members with dates, by day."
        case .tasks: return "Tasks linked to this space."
        }
    }

    var trailGlyph: String { icon }

    /// What this build can render. Views persisted for a future build are
    /// kept in metadata but filtered out of the switcher.
    static var renderable: Set<SpaceView> { [.home, .canvas, .library, .deepDive] }

    /// Every space created before kinds existed: the three modes the canvas
    /// always offered, opening on the canvas.
    static let legacyDefault: [SpaceView] = [.canvas, .library, .deepDive]
}

// MARK: - Kinds (presets)

enum SpaceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case research
    case whiteboard
    case collection
    case project
    case client
    case custom

    var id: String { rawValue }

    struct Preset: Equatable, Sendable {
        let views: [SpaceView]
        let opens: SpaceView
    }

    var title: String {
        switch self {
        case .research: return "Research"
        case .whiteboard: return "Whiteboard"
        case .collection: return "Collection"
        case .project: return "Project"
        case .client: return "Client"
        case .custom: return "Custom"
        }
    }

    /// The fallback identity mark when a space has no emoji.
    var glyph: String {
        switch self {
        case .research: return "circle.hexagongrid.circle"
        case .whiteboard: return "square.grid.3x3"
        case .collection: return "folder"
        case .project: return "rectangle.stack"
        case .client: return "person.crop.circle"
        case .custom: return "rectangle.3.group"
        }
    }

    /// The default emoji offered at creation (overridable; a leading emoji
    /// typed into the name always wins).
    var suggestedEmoji: String {
        switch self {
        case .research: return "🔬"
        case .whiteboard: return "🗺️"
        case .collection: return "🗂️"
        case .project: return "📁"
        case .client: return "👤"
        case .custom: return "✦"
        }
    }

    var blurb: String {
        switch self {
        case .research: return "Topic mastery. Opens in Deep Dive; canvas and library one keystroke away."
        case .whiteboard: return "Goals map, brainstorm, positioning. Nothing but the canvas."
        case .collection: return "Reference dumps and files. Library first, canvas optional."
        case .project: return "A bounded piece of work: documents, a canvas, a board over its content."
        case .client: return "Everything about one client, beside their pipeline in Studio."
        case .custom: return "Any combination of views, in any order."
        }
    }

    var preset: Preset {
        switch self {
        case .research: return Preset(views: [.deepDive, .canvas, .library], opens: .deepDive)
        case .whiteboard: return Preset(views: [.canvas], opens: .canvas)
        case .collection: return Preset(views: [.library, .canvas], opens: .library)
        case .project: return Preset(views: [.library, .canvas, .board], opens: .library)
        case .client: return Preset(views: [.canvas, .library], opens: .canvas)
        case .custom: return Preset(views: SpaceView.legacyDefault, opens: .canvas)
        }
    }

    /// The kinds offered in the composer, in tile order.
    static let composerKinds: [SpaceKind] = [.research, .whiteboard, .collection, .project, .custom]
}

// MARK: - Resolver (raw metadata → views)

enum SpaceViewResolver {
    /// Persisted raw list → enabled views. Unknown raw values are dropped
    /// (never fatal), order is kept, duplicates collapse; an empty result
    /// falls back to the kind's preset, then to the legacy default.
    static func enabledViews(raw: [String]?, kind: SpaceKind?) -> [SpaceView] {
        var seen = Set<SpaceView>()
        let parsed = (raw ?? []).compactMap(SpaceView.init(rawValue:)).filter { seen.insert($0).inserted }
        if !parsed.isEmpty { return parsed }
        if let kind { return kind.preset.views }
        return SpaceView.legacyDefault
    }

    /// Enabled ∩ renderable, in switcher order. Never empty — a space with
    /// nothing this build can draw still has its canvas.
    static func renderableViews(_ enabled: [SpaceView]) -> [SpaceView] {
        // Tools are available in every Space; legacy view preferences no longer
        // prevent a collection from becoming research or a whiteboard gaining notes.
        [.home, .library, .canvas, .deepDive]
    }

    /// The opening ladder: where you left it → where the space prefers →
    /// where the kind opens → the first thing it can show.
    static func openingView(
        renderable: [SpaceView],
        lastRaw: String?,
        defaultRaw: String?,
        kind: SpaceKind?
    ) -> SpaceView {
        if let last = lastRaw.flatMap(SpaceView.init(rawValue:)), renderable.contains(last) {
            return last
        }
        if let preferred = defaultRaw.flatMap(SpaceView.init(rawValue:)), renderable.contains(preferred) {
            return preferred
        }
        if let kind, renderable.contains(kind.preset.opens) {
            return kind.preset.opens
        }
        if kind == nil, lastRaw == nil, defaultRaw == nil, renderable.contains(.canvas) { return .canvas }
        return renderable.first ?? .home
    }
}

// MARK: - Chrome metrics

enum SpaceChromeMetrics {
    /// The space chrome row sits on the app's island baseline; content that
    /// must not slide under it (library lenses, the drawing toolbar, the
    /// dossier's first line) pads to this.
    static let contentTopInset: CGFloat =
        CosmoChromeMetrics.topInset + CosmoChromeMetrics.height + CosmoSurfaceMetrics.chromeGap
}
