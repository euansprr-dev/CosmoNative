// CosmoOS/Navigation/PaneDeckChromeContext.swift
// Chrome handoff for panes in the deck — the AtomWindowChromePayload pattern.
// The pane shell injects this into the FOCUSED pane's environment; the pane's
// own chrome row mounts the tab strip in its leading island (where the
// NavigationTrailIsland sits full-screen), so tabs and mode tools share one
// row of glass instead of stacking two bars.

import SwiftUI

// MARK: - Payload

/// One deck tab, described by the pane it names. The strip resolves glyph,
/// tint, and title through `PaneInfo` (+ `BrowserPaneRegistry` for live
/// browser titles), so the payload stays a thin description.
struct PaneDeckTab: Identifiable {
    let content: PaneContent
    let isFocused: Bool
    let isPinned: Bool
    /// 1-based deck position — the "⌘⌃n" in tooltips.
    let position: Int

    var id: String { content.id }
}

/// Deck mutations, pre-wrapped in the deck spring by the shell — the strip
/// calls these plainly and never touches PaneManager.
struct PaneDeckChromeActions {
    var focus: (String) -> Void
    var close: (String) -> Void
    var togglePin: (String) -> Void
    /// Move a pane by a slot delta (−1 left, +1 right).
    var move: (String, Int) -> Void
    var closeOthers: (String) -> Void
}

struct PaneDeckChromePayload {
    var tabs: [PaneDeckTab]
    var actions: PaneDeckChromeActions
    /// The focused pane's content width, quantized to 24pt steps — the tab
    /// strip derives its width budget and density from this instead of
    /// measuring itself (a hugging view cannot observe its offered space).
    /// Quantizing keeps divider drags from invalidating the environment
    /// every frame.
    var paneWidth: CGFloat

    static func quantizedWidth(_ width: CGFloat) -> CGFloat {
        (width / 24).rounded() * 24
    }
}

// MARK: - Environment

private struct PaneDeckChromeKey: EnvironmentKey {
    static let defaultValue: PaneDeckChromePayload? = nil
}

extension EnvironmentValues {
    /// Non-nil only inside the focused deck pane. Peek overlay, Atom windows,
    /// and full-screen focus modes never provide it — every unified-chrome
    /// branch is inert on those surfaces by construction.
    var paneDeckChrome: PaneDeckChromePayload? {
        get { self[PaneDeckChromeKey.self] }
        set { self[PaneDeckChromeKey.self] = newValue }
    }
}

// MARK: - Adoption

/// Which pane kinds mount the tab strip inside their own chrome row (the
/// AtomWindow merge). Everything else gets the shell's stacked standalone
/// row from PaneContentView — so no pane is ever tab-less mid-migration.
/// Container surfaces (canvas, Command Center, Swipe library, collaborator)
/// keep the standalone row permanently: their content carries top-anchored
/// mastheads, and a stacked row can never overlap them.
enum PaneDeckChromeAdoption {

    static func modeHostsDeckChrome(_ content: PaneContent) -> Bool {
        switch content {
        case .entity(let entity):
            return entityModeHostsDeckChrome(entity.type)
        case .webBrowser:
            // The browser toolbar hosts the strip in its leading seam —
            // tabs and browser controls share one glass row.
            return true
        case .cosmoWindow, .inlineAssistant:
            // The assistant toolbar follows the browser grammar: tabs, the
            // one close affordance, and the session spine share one glass row.
            return true
        case .thinkspace, .commandCenter, .swipeGallery, .collaborator:
            return false
        }
    }

    /// Entity focus modes flip here as each adopts the leading-island seam.
    /// `.research` covers both ResearchFocusModeView and SwipeStudyFocusModeView
    /// (swipe atoms route by `isSwipeFileAtom`) — both host the strip.
    private static func entityModeHostsDeckChrome(_ type: EntityType) -> Bool {
        switch type {
        case .research, .connection, .idea, .content, .note, .cosmoAI:
            return true
        default:
            // Unrouted entity kinds render the unsupported placeholder,
            // which has no chrome row — the shell row stays.
            return false
        }
    }
}
