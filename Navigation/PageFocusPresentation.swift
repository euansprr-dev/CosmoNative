import SwiftUI
import Observation

/// A window's temporary reading/writing presentation. It never changes the
/// selected document, the saved sidebar preference, or the pane arrangement.
@MainActor @Observable
final class PageFocusPresentation {
    private(set) var focusedPageUUID: String?
    private(set) var focusedPaneID: String?

    var isFocused: Bool { focusedPageUUID != nil }

    func toggle(pageUUID: String, paneID: String? = nil) {
        if focusedPageUUID == pageUUID && focusedPaneID == paneID {
            exit()
        } else {
            focusedPageUUID = pageUUID
            focusedPaneID = paneID
        }
    }

    @discardableResult
    func exit() -> Bool {
        guard isFocused else { return false }
        focusedPageUUID = nil
        focusedPaneID = nil
        return true
    }

    func end(pageUUID: String, paneID: String? = nil) {
        guard focusedPageUUID == pageUUID, focusedPaneID == paneID else { return }
        exit()
    }
}

private struct PageFocusPresentationKey: EnvironmentKey {
    static let defaultValue: PageFocusPresentation? = nil
}

private struct UnifiedPageNavigationInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct PageFocusPaneIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var unifiedPageNavigationInset: CGFloat {
        get { self[UnifiedPageNavigationInsetKey.self] }
        set { self[UnifiedPageNavigationInsetKey.self] = newValue }
    }

    var pageFocusPresentation: PageFocusPresentation? {
        get { self[PageFocusPresentationKey.self] }
        set { self[PageFocusPresentationKey.self] = newValue }
    }

    var pageFocusPaneID: String? {
        get { self[PageFocusPaneIDKey.self] }
        set { self[PageFocusPaneIDKey.self] = newValue }
    }
}

/// Pages can open independently of their memberships. Structural containers
/// need a reachable workspace so their children and representations stay intact.
/// Explicit locations are exact for every kind, including unavailable ones.
enum PageOpenLocationPolicy {
    static func requiresSpace(for kind: SpaceCompositionKind?) -> Bool {
        kind.map { $0 != .page } ?? false
    }

    static func destination(exactSpaceID: String?, preferredSpaceID: String?,
                            reachableSpaceIDs: [String], compositionKind: SpaceCompositionKind? = .page) -> String? {
        if let exactSpaceID { return reachableSpaceIDs.contains(exactSpaceID) ? exactSpaceID : nil }
        if let preferredSpaceID, reachableSpaceIDs.contains(preferredSpaceID) { return preferredSpaceID }
        return compositionKind == .page ? nil : reachableSpaceIDs.first
    }
}
