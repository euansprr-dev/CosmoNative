// CosmoOS/Navigation/Browser/BrowserPaneRegistry.swift
// Live lookup from pane id to the browser state driving that pane. Repairs
// what URL-based pane identity used to provide: activation by current URL,
// live tab-rail titles, and current-URL capture for workbenches.

import Foundation

@MainActor
final class BrowserPaneRegistry {
    static let shared = BrowserPaneRegistry()

    private struct Entry {
        weak var state: CosmoWebBrowserState?
    }

    /// Pane id → browser state, in registration order (deterministic lookups).
    private var entries: [(paneId: String, entry: Entry)] = []

    func register(_ state: CosmoWebBrowserState, for paneId: String) {
        prune()
        entries.removeAll { $0.paneId == paneId }
        entries.append((paneId, Entry(state: state)))
    }

    func unregister(paneId: String) {
        entries.removeAll { $0.paneId == paneId }
    }

    func state(for paneId: String) -> CosmoWebBrowserState? {
        entries.first { $0.paneId == paneId }?.entry.state
    }

    /// The pane currently showing this page, matched on normalized page keys
    /// so tracking noise (utm_, fbclid, trailing slashes) doesn't defeat reuse.
    func paneId(showing url: URL) -> String? {
        let key = CosmoBrowserPinnedSite.pageKey(for: url)
        return entries.first { candidate in
            guard let currentURL = candidate.entry.state?.currentURL else { return false }
            return CosmoBrowserPinnedSite.pageKey(for: currentURL) == key
        }?.paneId
    }

    /// Navigate an existing browser pane in place.
    func navigate(paneId: String, to url: URL) {
        state(for: paneId)?.load(url)
    }

    func currentURL(for paneId: String) -> URL? {
        state(for: paneId)?.currentURL
    }

    func displayTitle(for paneId: String) -> String? {
        state(for: paneId)?.displayTitle
    }

    private func prune() {
        entries.removeAll { $0.entry.state == nil }
    }
}
