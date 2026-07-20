// CosmoOS/Navigation/Browser/CosmoBrowserModels.swift
// Data models for the in-app research browser: profiles, pins, history,
// sessions, captures, auth policy, and URL resolution.

import Foundation
import WebKit

// MARK: - User Agent

/// The Safari token embedded WebKit presents to sites.
///
/// WKWebView's default user agent omits the `Version/… Safari/…` token
/// entirely, and large sites gate their modern bundle on a minimum Safari
/// major version — Instagram, for one, serves a stripped legacy bundle whose
/// image pipeline never paints to anything claiming less than Safari 18.
/// A frozen literal rots the moment a site raises that floor, so the version
/// tracks the running OS rather than a number someone typed once.
enum CosmoBrowserUserAgent {
    /// Value for `WKWebViewConfiguration.applicationNameForUserAgent`.
    ///
    /// Prefer this over `customUserAgent`: WebKit supplies the
    /// `Mozilla/5.0 … AppleWebKit/…` prefix itself, so the engine build stays
    /// truthful and only the Safari token is ours to state.
    static var applicationName: String {
        "Version/\(safariMarketingVersion) Safari/605.1.15"
    }

    /// Safari's marketing version tracks the macOS major version from macOS 26
    /// onward; macOS 15 — the deployment floor — shipped Safari 18.
    static var safariMarketingVersion: String {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major >= 26 ? "\(major).0" : "18.5"
    }
}

// MARK: - Browser Core

enum CosmoBrowserWebsiteDataMode: Codable, Equatable {
    case defaultPersistent
    case isolatedPersistent(UUID)
    case privateMemory

    @MainActor
    func makeDataStore() -> WKWebsiteDataStore {
        switch self {
        case .defaultPersistent:
            return .default()
        case .isolatedPersistent(let identifier):
            return WKWebsiteDataStore(forIdentifier: identifier)
        case .privateMemory:
            return .nonPersistent()
        }
    }
}

struct CosmoBrowserProfile: Identifiable, Codable, Equatable {
    static let researchWebsiteDataIdentifier = UUID(uuidString: "1C5F64AC-2066-46C9-B26C-16F976B2B4B8")!

    static let standard = CosmoBrowserProfile(
        id: "standard",
        title: "Default",
        subtitle: "Persistent accounts and browsing memory",
        systemImage: "globe",
        websiteDataIdentifier: UUID(uuidString: "0FD8D04B-F99B-46BE-AF1C-0C85D4BE8CF8")!,
        websiteDataMode: .defaultPersistent
    )

    static let privateBrowsing = CosmoBrowserProfile(
        id: "private",
        title: "Private",
        subtitle: "Temporary website data",
        systemImage: "eye.slash",
        websiteDataIdentifier: UUID(uuidString: "73775443-6FF2-4C25-96F6-B43F4E57AFA2")!,
        websiteDataMode: .privateMemory
    )

    static let research = CosmoBrowserProfile(
        id: "research",
        title: "Research",
        subtitle: "Persistent research profile",
        systemImage: "doc.text.magnifyingglass",
        websiteDataIdentifier: researchWebsiteDataIdentifier,
        websiteDataMode: .isolatedPersistent(researchWebsiteDataIdentifier)
    )

    static let builtIns: [CosmoBrowserProfile] = [.standard, .research, .privateBrowsing]

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let websiteDataIdentifier: UUID
    let websiteDataMode: CosmoBrowserWebsiteDataMode
}

struct CosmoBrowserHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var url: URL
    var title: String
    var visitedAt: Date

    init(id: UUID = UUID(), url: URL, title: String, visitedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
    }
}

struct CosmoBrowserPinnedSite: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var url: URL
    var title: String
    var displayName: String
    var host: String
    var pinnedAt: Date

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        displayName: String? = nil,
        pinnedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.displayName = displayName?.nilIfBlank ?? title
        self.host = Self.normalizedHost(for: url)
        self.pinnedAt = pinnedAt
    }

    var searchableText: String {
        [
            displayName,
            title,
            host,
            url.absoluteString,
        ].joined(separator: " ")
    }

    mutating func rename(to newName: String) {
        displayName = newName.nilIfBlank ?? title
    }

    var pageKey: String {
        Self.pageKey(for: url)
    }

    static func normalizedHost(for url: URL) -> String {
        let host = url.host(percentEncoded: false)?.lowercased() ?? url.host?.lowercased() ?? url.absoluteString.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func pageKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            var key = url.absoluteString
            while key.hasSuffix("/") {
                key.removeLast()
            }
            return key
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if let queryItems = components.queryItems {
            let filteredItems = queryItems
                .filter { item in
                    let name = item.name.lowercased()
                    return !name.hasPrefix("utm_") && name != "fbclid" && name != "gclid"
                }
                .sorted {
                    if $0.name == $1.name {
                        return ($0.value ?? "") < ($1.value ?? "")
                    }
                    return $0.name < $1.name
                }
            components.queryItems = filteredItems.isEmpty ? nil : filteredItems
        }

        var key = components.url?.absoluteString ?? url.absoluteString
        while key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case displayName
        case host
        case pinnedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)?.nilIfBlank ?? title
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? Self.normalizedHost(for: url)
        pinnedAt = try container.decode(Date.self, forKey: .pinnedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(host, forKey: .host)
        try container.encode(pinnedAt, forKey: .pinnedAt)
    }
}

struct CosmoBrowserTab: Identifiable, Codable, Equatable {
    let id: UUID
    var currentURL: URL
    var title: String
    var history: [CosmoBrowserHistoryItem]

    init(id: UUID = UUID(), currentURL: URL, title: String) {
        self.id = id
        self.currentURL = currentURL
        self.title = title
        self.history = []
    }
}

/// One pane = one tab by design; the pane deck is the tab system.
/// `tabs` stays single-element — do not add in-browser tab UI on top of it.
struct CosmoBrowserSession: Identifiable, Codable, Equatable {
    let id: UUID
    var profile: CosmoBrowserProfile
    var activeTabID: UUID
    var tabs: [CosmoBrowserTab]
    var pinnedSites: [CosmoBrowserPinnedSite]
    var createdAt: Date
    var updatedAt: Date

    static func starting(
        at url: URL,
        title: String?,
        profile: CosmoBrowserProfile = .standard,
        now: Date = Date()
    ) -> CosmoBrowserSession {
        let tab = CosmoBrowserTab(currentURL: url, title: title?.nilIfBlank ?? CosmoBrowserURLResolver.displayTitle(for: url))
        return CosmoBrowserSession(
            id: UUID(),
            profile: profile,
            activeTabID: tab.id,
            tabs: [tab],
            pinnedSites: [],
            createdAt: now,
            updatedAt: now
        )
    }

    var activeTab: CosmoBrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    mutating func recordVisit(url: URL, title: String?, at date: Date = Date()) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let resolvedTitle = title?.nilIfBlank ?? CosmoBrowserURLResolver.displayTitle(for: url)
        tabs[index].currentURL = url
        tabs[index].title = resolvedTitle
        tabs[index].history.append(CosmoBrowserHistoryItem(url: url, title: resolvedTitle, visitedAt: date))
        updatedAt = date
    }

    mutating func pinCurrentSite(at date: Date = Date()) -> CosmoBrowserPinnedSite? {
        guard let tab = activeTab else { return nil }
        let pin = CosmoBrowserPinnedSite(url: tab.currentURL, title: tab.title, pinnedAt: date)
        pinnedSites.removeAll { $0.pageKey == pin.pageKey }
        pinnedSites.append(pin)
        pinnedSites.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        updatedAt = date
        return pin
    }

    mutating func unpin(id: UUID, at date: Date = Date()) {
        pinnedSites.removeAll { $0.id == id }
        updatedAt = date
    }
}

enum CosmoBrowserResearchCaptureKind: String, Codable, Equatable {
    case quote
    case research
    case swipe
    case askCosmo
}

struct CosmoBrowserResearchCapture: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: CosmoBrowserResearchCaptureKind
    var sourceURL: URL
    var pageTitle: String
    var selectedText: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: CosmoBrowserResearchCaptureKind,
        sourceURL: URL,
        pageTitle: String,
        selectedText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sourceURL = sourceURL
        self.pageTitle = pageTitle
        self.selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }

    var title: String {
        pageTitle.nilIfBlank ?? CosmoBrowserURLResolver.displayTitle(for: sourceURL)
    }

    var body: String {
        selectedText
    }
}

enum CosmoBrowserAuthenticationRoute: Equatable {
    case embedded
    case externalSystemSession(reason: String)
}

enum CosmoBrowserAuthenticationPolicy {
    static func recommendedRoute(for url: URL) -> CosmoBrowserAuthenticationRoute {
        let host = url.host(percentEncoded: false)?.lowercased() ?? url.host?.lowercased() ?? ""
        let path = url.path(percentEncoded: false).lowercased()

        if host == "accounts.google.com" || host.hasSuffix(".accounts.google.com") || path.contains("/oauth") {
            return .externalSystemSession(reason: "Google OAuth blocks many embedded browser sign-in flows.")
        }

        return .embedded
    }
}

enum CosmoBrowserURLResolver {
    static let defaultHomeURL = URL(string: "https://www.google.com")!

    static func resolve(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultHomeURL }

        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return url
        }

        if looksLikeDomain(trimmed), let url = URL(string: "https://\(trimmed)") {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    static func displayTitle(for url: URL) -> String {
        let host = CosmoBrowserPinnedSite.normalizedHost(for: url)
        return host.isEmpty ? "Browser" : host
    }

    static func displayURLString(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = nil
        return components?.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? url.absoluteString
    }

    private static func looksLikeDomain(_ value: String) -> Bool {
        guard !value.contains(" ") else { return false }
        guard value.contains(".") else { return false }
        return value.range(of: #"^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil
    }
}

fileprivate extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
