// CosmoOS/Navigation/Browser/CosmoBrowserState.swift
// Observable view-model driving one browser pane's WKWebView and chrome.

import SwiftUI
import WebKit

struct CosmoBrowserNavigationRequest: Equatable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class CosmoWebBrowserState {
    var displayTitle: String
    var displayURL: String
    var addressText: String
    var currentURL: URL?
    var isLoading = false
    var estimatedProgress: Double = 0
    var canGoBack = false
    var canGoForward = false
    var showsStartPage: Bool
    var errorMessage: String?
    var selectedText: String = ""
    var pins: [CosmoBrowserPinnedSite] = []
    var recentHistory: [CosmoBrowserHistoryItem] = []
    var authenticationRoute: CosmoBrowserAuthenticationRoute = .embedded
    private(set) var profile: CosmoBrowserProfile
    private(set) var webViewIdentity = UUID()

    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var session: CosmoBrowserSession
    @ObservationIgnored private let initialURL: URL
    @ObservationIgnored let store: CosmoBrowserStore
    var navigationRequest: CosmoBrowserNavigationRequest
    @ObservationIgnored private var lastRecordedVisitSignature: String?

    init(
        initialURL: URL,
        title: String?,
        profile: CosmoBrowserProfile = .standard,
        store: CosmoBrowserStore = .shared
    ) {
        self.initialURL = initialURL
        self.profile = profile
        self.store = store
        self.currentURL = initialURL
        self.session = CosmoBrowserSession.starting(at: initialURL, title: title, profile: profile)
        self.displayTitle = title?.nilIfBlank ?? CosmoBrowserURLResolver.displayTitle(for: initialURL)
        self.displayURL = CosmoBrowserURLResolver.displayURLString(for: initialURL)
        self.addressText = initialURL.absoluteString
        self.showsStartPage = initialURL == CosmoBrowserURLResolver.defaultHomeURL
        self.navigationRequest = CosmoBrowserNavigationRequest(url: initialURL)
    }

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isCurrentSitePinned: Bool {
        guard let currentURL else { return false }
        let pageKey = CosmoBrowserPinnedSite.pageKey(for: currentURL)
        return pins.contains { $0.pageKey == pageKey }
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        update(from: webView)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        clearError()
        if webView?.url == nil {
            webView?.load(URLRequest(url: currentURL ?? initialURL))
        } else {
            webView?.reload()
        }
    }

    func reloadOrStop() {
        if isLoading {
            webView?.stopLoading()
            update(from: webView)
        } else {
            reload()
        }
    }

    func update(from webView: WKWebView?) {
        guard let webView else { return }
        applySnapshot(
            url: webView.url,
            title: webView.title,
            isLoading: webView.isLoading,
            estimatedProgress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
    }

    func applySnapshot(
        url: URL?,
        title: String?,
        isLoading: Bool,
        estimatedProgress: Double,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        let resolvedURL = url ?? currentURL
        assignIfChanged(currentURL, resolvedURL) { currentURL = $0 }
        assignIfChanged(displayURL, CosmoBrowserURLResolver.displayURLString(for: resolvedURL ?? initialURL)) { displayURL = $0 }
        assignIfChanged(addressText, (resolvedURL ?? initialURL).absoluteString) { addressText = $0 }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assignIfChanged(displayTitle, title) { displayTitle = $0 }
        }
        assignIfChanged(self.isLoading, isLoading) { self.isLoading = $0 }
        assignIfChanged(self.estimatedProgress, estimatedProgress) { self.estimatedProgress = $0 }
        assignIfChanged(self.canGoBack, canGoBack) { self.canGoBack = $0 }
        assignIfChanged(self.canGoForward, canGoForward) { self.canGoForward = $0 }
        if let resolvedURL, !isLoading {
            recordVisit(url: resolvedURL, title: title)
        }
        if let resolvedURL {
            assignIfChanged(authenticationRoute, CosmoBrowserAuthenticationPolicy.recommendedRoute(for: resolvedURL)) {
                authenticationRoute = $0
            }
        }
    }

    func fail(with error: Error) {
        assignIfChanged(errorMessage, error.localizedDescription) { errorMessage = $0 }
        update(from: webView)
    }

    func clearError() {
        assignIfChanged(errorMessage, nil) { errorMessage = $0 }
    }

    func load(_ url: URL) {
        clearError()
        hideStartPage()
        assignIfChanged(currentURL, url) { currentURL = $0 }
        assignIfChanged(displayURL, CosmoBrowserURLResolver.displayURLString(for: url)) { displayURL = $0 }
        assignIfChanged(addressText, url.absoluteString) { addressText = $0 }
        assignIfChanged(authenticationRoute, CosmoBrowserAuthenticationPolicy.recommendedRoute(for: url)) {
            authenticationRoute = $0
        }
        navigationRequest = CosmoBrowserNavigationRequest(url: url)
        webView?.load(URLRequest(url: url))
    }

    func commitAddressText() {
        guard let url = CosmoBrowserURLResolver.resolve(addressText) else { return }
        hideStartPage()
        load(url)
    }

    /// Revert the address field to the current page after an abandoned edit.
    func restoreAddressText() {
        assignIfChanged(addressText, (currentURL ?? initialURL).absoluteString) { addressText = $0 }
    }

    func updateSelectedText(_ text: String) {
        assignIfChanged(selectedText, text.trimmingCharacters(in: .whitespacesAndNewlines)) { selectedText = $0 }
    }

    func clearSelectedText() {
        assignIfChanged(selectedText, "") { selectedText = $0 }
    }

    func makeResearchCapture(kind: CosmoBrowserResearchCaptureKind) -> CosmoBrowserResearchCapture? {
        guard let currentURL, hasSelection else { return nil }
        return CosmoBrowserResearchCapture(
            kind: kind,
            sourceURL: currentURL,
            pageTitle: displayTitle,
            selectedText: selectedText
        )
    }

    func pinCurrentSite() {
        guard let currentURL else { return }
        let profileID = profile.id

        session.recordVisit(url: currentURL, title: displayTitle)
        guard let pin = session.pinCurrentSite() else { return }
        pins.removeAll { $0.pageKey == pin.pageKey }
        pins.append(pin)
        pins.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        Task {
            guard let savedPins = try? await store.upsertPin(pin, for: profileID) else { return }
            guard profile.id == profileID else { return }
            pins = savedPins
            session.pinnedSites = savedPins
        }
    }

    func toggleCurrentFavorite() {
        guard let currentURL else { return }
        let pageKey = CosmoBrowserPinnedSite.pageKey(for: currentURL)
        if let existingPin = pins.first(where: { $0.pageKey == pageKey }) {
            unpin(existingPin)
        } else {
            pinCurrentSite()
        }
    }

    func renamePin(_ pinID: UUID, to displayName: String) async {
        guard let index = pins.firstIndex(where: { $0.id == pinID }) else { return }
        let profileID = profile.id

        pins[index].rename(to: displayName)
        pins.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        session.pinnedSites = pins

        try? await store.renamePin(pinID, to: displayName, for: profileID)
        let savedPins = await store.pins(for: profileID)
        guard profile.id == profileID else { return }
        pins = savedPins
        session.pinnedSites = savedPins
    }

    func unpin(_ pin: CosmoBrowserPinnedSite) {
        session.unpin(id: pin.id)
        pins.removeAll { $0.id == pin.id }
        session.pinnedSites = pins

        let profileID = profile.id
        Task {
            guard let savedPins = try? await store.removePin(id: pin.id, for: profileID) else { return }
            guard profile.id == profileID else { return }
            pins = savedPins
            session.pinnedSites = savedPins
        }
    }

    func loadPersistedPins() async {
        let savedPins = await store.pins(for: profile.id)
        let savedHistory = await store.history(for: profile.id)
        pins = savedPins
        recentHistory = savedHistory
        session.pinnedSites = savedPins
    }

    func switchProfile(_ newProfile: CosmoBrowserProfile) async {
        guard profile != newProfile else { return }

        let activeURL = currentURL ?? initialURL
        profile = newProfile
        session = CosmoBrowserSession.starting(at: activeURL, title: displayTitle, profile: newProfile)
        lastRecordedVisitSignature = nil
        clearError()
        clearSelectedText()
        assignIfChanged(authenticationRoute, CosmoBrowserAuthenticationPolicy.recommendedRoute(for: activeURL)) {
            authenticationRoute = $0
        }

        let savedPins = await store.pins(for: newProfile.id)
        let savedHistory = await store.history(for: newProfile.id)
        pins = savedPins
        recentHistory = savedHistory
        session.pinnedSites = savedPins
        navigationRequest = CosmoBrowserNavigationRequest(url: activeURL)
        webViewIdentity = UUID()
    }

    private func assignIfChanged<Value: Equatable>(_ currentValue: Value, _ newValue: Value, assign: (Value) -> Void) {
        guard currentValue != newValue else { return }
        assign(newValue)
    }

    private func hideStartPage() {
        guard showsStartPage else { return }
        showsStartPage = false
    }

    private func recordVisit(url: URL, title: String?) {
        let resolvedTitle = title?.nilIfBlank ?? displayTitle
        let signature = "\(profile.id)|\(url.absoluteString)|\(resolvedTitle)"
        guard lastRecordedVisitSignature != signature else { return }
        lastRecordedVisitSignature = signature

        session.recordVisit(url: url, title: resolvedTitle)
        guard let item = session.activeTab?.history.last else { return }
        let profileID = profile.id
        Task {
            try? await store.recordVisit(item, for: profileID)
            let history = await store.history(for: profileID)
            await MainActor.run {
                guard self.profile.id == profileID else { return }
                self.recentHistory = history
            }
        }
    }
}

fileprivate extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
