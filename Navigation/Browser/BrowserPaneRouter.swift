// CosmoOS/Navigation/Browser/BrowserPaneRouter.swift
// Pure routing policy for opening URLs in the research browser. The default
// disposition navigates the existing pane in place — casual opens never
// multiply panes; splitting is always a deliberate gesture.

import Foundation

/// How the caller wants the URL opened. Carried in the openWebBrowserPane
/// notification's "disposition" userInfo key.
enum BrowserOpenDisposition: String {
    /// Navigate an existing browser pane (or activate the pane already
    /// showing the page). Opens a pane only when none exists. The default.
    case reuse
    /// Open a fresh browser pane (⌘⏎ on a browser result).
    case newPane
    /// Open a fresh browser pane beside the current one, pinning the source
    /// (⌘-click a favorite or link).
    case split
}

enum BrowserPaneRouter {
    enum Action: Equatable {
        case activateExisting(paneId: String)
        case navigateExisting(paneId: String, url: URL)
        case openNewPane(besideCurrent: Bool)
    }

    /// Route an open request. At the browser-pane cap, new-pane requests fall
    /// back to navigating the focused browser pane — never a silent drop.
    static func route(
        url: URL,
        disposition: BrowserOpenDisposition,
        paneShowingURL: String?,
        focusedBrowserPaneId: String?,
        canOpenNewPane: Bool
    ) -> Action? {
        // Never duplicate a page that's already on screen.
        if let paneShowingURL {
            return .activateExisting(paneId: paneShowingURL)
        }

        switch disposition {
        case .reuse:
            if let focusedBrowserPaneId {
                return .navigateExisting(paneId: focusedBrowserPaneId, url: url)
            }
            return canOpenNewPane ? .openNewPane(besideCurrent: false) : nil
        case .newPane, .split:
            if canOpenNewPane {
                return .openNewPane(besideCurrent: disposition == .split)
            }
            if let focusedBrowserPaneId {
                return .navigateExisting(paneId: focusedBrowserPaneId, url: url)
            }
            return nil
        }
    }
}
