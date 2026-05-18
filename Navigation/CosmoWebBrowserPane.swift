// CosmoOS/Navigation/CosmoWebBrowserPane.swift
// Split-pane WebKit browser for in-app social source review.

import SwiftUI
import WebKit
import AppKit
import AuthenticationServices

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

    static func normalizedHost(for url: URL) -> String {
        let host = url.host(percentEncoded: false)?.lowercased() ?? url.host?.lowercased() ?? url.absoluteString.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
        pinnedSites.removeAll { $0.host == pin.host }
        pinnedSites.append(pin)
        pinnedSites.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        updatedAt = date
        return pin
    }

    mutating func unpin(host: String, at date: Date = Date()) {
        pinnedSites.removeAll { $0.host == host }
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

struct CosmoBrowserStoreSnapshot: Codable, Equatable {
    var profiles: [CosmoBrowserProfile] = CosmoBrowserProfile.builtIns
    var pinnedSitesByProfile: [String: [CosmoBrowserPinnedSite]] = [:]
    var historyByProfile: [String: [CosmoBrowserHistoryItem]] = [:]
}

actor CosmoBrowserStore {
    static let shared = CosmoBrowserStore()

    private let fileURL: URL
    private var snapshot: CosmoBrowserStoreSnapshot

    init(fileURL: URL = CosmoBrowserStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.snapshot = (try? Self.load(from: fileURL)) ?? CosmoBrowserStoreSnapshot()
    }

    func pins(for profileID: String) -> [CosmoBrowserPinnedSite] {
        snapshot.pinnedSitesByProfile[profileID] ?? []
    }

    func allPins() -> [CosmoBrowserPinnedSite] {
        snapshot.pinnedSitesByProfile.values.flatMap { $0 }
    }

    func history(for profileID: String) -> [CosmoBrowserHistoryItem] {
        snapshot.historyByProfile[profileID] ?? []
    }

    func savePins(_ pins: [CosmoBrowserPinnedSite], for profileID: String) throws {
        snapshot.pinnedSitesByProfile[profileID] = pins
        try persist()
    }

    func renamePin(_ pinID: UUID, to displayName: String, for profileID: String) throws {
        guard var pins = snapshot.pinnedSitesByProfile[profileID],
              let index = pins.firstIndex(where: { $0.id == pinID }) else {
            return
        }

        pins[index].rename(to: displayName)
        pins.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        snapshot.pinnedSitesByProfile[profileID] = pins
        try persist()
    }

    func recordVisit(_ item: CosmoBrowserHistoryItem, for profileID: String, limit: Int = 200) throws {
        var history = snapshot.historyByProfile[profileID] ?? []
        history.removeAll { $0.url == item.url }
        history.insert(item, at: 0)
        snapshot.historyByProfile[profileID] = Array(history.prefix(limit))
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> CosmoBrowserStoreSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CosmoBrowserStoreSnapshot.self, from: Data(contentsOf: url))
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CosmoOS", isDirectory: true)
            .appendingPathComponent("CosmoBrowserState.json")
    }
}

@MainActor
final class CosmoBrowserSystemAuthenticationCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isAuthenticating = false

    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?

    func start(url: URL) -> Bool {
        session?.cancel()

        let authenticationSession = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
            Task { @MainActor in
                self?.isAuthenticating = false
                self?.session = nil
            }
        }
        authenticationSession.prefersEphemeralWebBrowserSession = false
        authenticationSession.presentationContextProvider = self

        anchor = NSApp.keyWindow ?? NSApp.mainWindow
        session = authenticationSession
        isAuthenticating = true

        let didStart = authenticationSession.start()
        if !didStart {
            isAuthenticating = false
            session = nil
        }
        return didStart
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
    }
}

private struct CosmoBrowserNavigationRequest: Equatable {
    let id = UUID()
    let url: URL
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CosmoWebBrowserPane: View {
    let url: URL
    let title: String?
    let onClose: () -> Void

    @StateObject private var browserState: CosmoWebBrowserState
    @StateObject private var authenticationCoordinator = CosmoBrowserSystemAuthenticationCoordinator()
    @State private var renamingPin: CosmoBrowserPinnedSite?
    @FocusState private var isAddressFieldFocused: Bool
    @Environment(\.isPaneActive) private var isPaneActive

    init(url: URL, title: String?, onClose: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.onClose = onClose
        _browserState = StateObject(wrappedValue: CosmoWebBrowserState(initialURL: url, title: title, profile: .standard))
    }

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            pinnedSitesBar

            ZStack(alignment: .top) {
                CosmoBrowserWebView(state: browserState)
                    .id(browserState.webViewIdentity)
                    .background(DS.bg)

                if browserState.isLoading {
                    ProgressView(value: browserState.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(DS.entitySwipe)
                        .frame(height: 2)
                        .transition(.opacity)
                }

                if let errorMessage = browserState.errorMessage {
                    browserErrorView(errorMessage)
                        .padding(18)
                }

                if case .externalSystemSession(let reason) = browserState.authenticationRoute {
                    authenticationNotice(reason: reason)
                        .padding(18)
                }

                if browserState.hasSelection {
                    browserCaptureBar
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(DS.bg)
        .task {
            await browserState.loadPersistedPins()
        }
        .sheet(item: $renamingPin) { pin in
            CosmoBrowserRenamePinSheet(
                pin: pin,
                onCancel: {
                    renamingPin = nil
                },
                onSave: { name in
                    Task {
                        await browserState.renamePin(pin.id, to: name)
                    }
                    renamingPin = nil
                }
            )
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            CosmoBrowserToolbarButton(systemName: "xmark", help: "Close browser", action: onClose)

            Divider()
                .frame(height: 18)
                .overlay(DS.borderSubtle)
                .padding(.horizontal, 2)

            CosmoBrowserToolbarButton(
                systemName: "chevron.left",
                help: "Back",
                isEnabled: browserState.canGoBack,
                action: browserState.goBack
            )
            CosmoBrowserToolbarButton(
                systemName: "chevron.right",
                help: "Forward",
                isEnabled: browserState.canGoForward,
                action: browserState.goForward
            )
            CosmoBrowserToolbarButton(
                systemName: browserState.isLoading ? "xmark.circle" : "arrow.clockwise",
                help: browserState.isLoading ? "Stop loading" : "Reload",
                action: browserState.reloadOrStop
            )
            profileMenu
            historyMenu

            HStack(spacing: 8) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.entitySwipe)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    TextField("Search or enter URL", text: $browserState.addressText)
                        .textFieldStyle(.plain)
                        .font(DS.caption)
                        .foregroundStyle(DS.text)
                        .focused($isAddressFieldFocused)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onSubmit {
                            browserState.commitAddressText()
                            isAddressFieldFocused = false
                        }
                    Text(browserState.displayTitle)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                Task { @MainActor in
                    await Task.yield()
                    isAddressFieldFocused = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isPaneActive ? DS.entitySwipe.opacity(0.45) : DS.borderSubtle, lineWidth: 1)
            )

            CosmoBrowserToolbarButton(
                systemName: browserState.isCurrentSitePinned ? "pin.fill" : "pin",
                help: browserState.isCurrentSitePinned ? "Unpin site" : "Pin site",
                action: browserState.toggleCurrentSitePin
            )

            CosmoBrowserToolbarButton(systemName: "safari", help: "Open in external browser") {
                NSWorkspace.shared.open(browserState.currentURL ?? url)
            }
        }
        .padding(10)
    }

    private var profileMenu: some View {
        Menu {
            ForEach(CosmoBrowserProfile.builtIns) { profile in
                Button {
                    Task {
                        await browserState.switchProfile(profile)
                    }
                } label: {
                    Label(profile.title, systemImage: profile.systemImage)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: browserState.profile.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(browserState.profile.title)
                    .font(DS.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(DS.borderSubtle, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Browser profile")
    }

    private var historyMenu: some View {
        Menu {
            if browserState.recentHistory.isEmpty {
                Text("No Recent Pages")
            } else {
                ForEach(browserState.recentHistory.prefix(10)) { item in
                    Button {
                        browserState.load(item.url)
                    } label: {
                        Label(item.title, systemImage: "clock")
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(browserState.recentHistory.isEmpty ? DS.textMuted.opacity(0.55) : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(DS.borderSubtle, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Recent pages")
    }

    @ViewBuilder
    private var pinnedSitesBar: some View {
        if !browserState.pins.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(browserState.pins) { pin in
                        Button {
                            browserState.load(pin.url)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(pin.displayName)
                                    .font(DS.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(DS.surfaceElevated, in: Capsule())
                            .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(pin.url.absoluteString)
                        .contextMenu {
                            Button {
                                browserState.load(pin.url)
                            } label: {
                                Label("Open", systemImage: "arrow.up.forward.app")
                            }

                            Button {
                                renamingPin = pin
                            } label: {
                                Label("Rename Pin", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                browserState.unpin(pin)
                            } label: {
                                Label("Unpin", systemImage: "pin.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    private var browserCaptureBar: some View {
        HStack(spacing: 8) {
            Text("\(browserState.selectedText.count) chars selected")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)

            CosmoBrowserCaptureButton(title: "Quote", systemName: "quote.opening") {
                dispatchCapture(.quote)
            }
            CosmoBrowserCaptureButton(title: "Research", systemName: "doc.text.magnifyingglass") {
                dispatchCapture(.research)
            }
            CosmoBrowserCaptureButton(title: "Swipe", systemName: "bolt.fill") {
                dispatchCapture(.swipe)
            }
            CosmoBrowserCaptureButton(title: "Ask", systemName: "sparkles") {
                dispatchCapture(.askCosmo)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.borderSubtle, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private var sourceIcon: String {
        if (browserState.currentURL ?? url).host?.contains("instagram.com") == true {
            return "camera.fill"
        }
        return "globe"
    }

    private func authenticationNotice(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(DS.orange)
                Text("Use system browser for this sign-in")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.text)
            }
            Text(reason)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = browserState.currentURL {
                    let didStart = authenticationCoordinator.start(url: url)
                    if !didStart {
                        NSWorkspace.shared.open(url)
                    }
                }
            } label: {
                Label(
                    authenticationCoordinator.isAuthenticating ? "Opening System Sign-In" : "Use System Sign-In",
                    systemImage: "key.horizontal"
                )
                    .font(DS.buttonText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(DS.accent, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(DS.textOnAccent)
            }
            .buttonStyle(.plain)
            Button {
                if let url = browserState.currentURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open Externally", systemImage: "arrow.up.right.square")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.borderSubtle, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private func dispatchCapture(_ kind: CosmoBrowserResearchCaptureKind) {
        guard let capture = browserState.makeResearchCapture(kind: kind) else { return }

        switch kind {
        case .quote:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\"\(capture.body)\"\n\(capture.sourceURL.absoluteString)", forType: .string)
            browserState.clearSelectedText()
        case .research:
            Task {
                _ = try? await AgentToolExecutor.shared.execute(
                    toolName: "capture_research",
                    arguments: [
                        "title": capture.title,
                        "url": capture.sourceURL.absoluteString,
                        "body": capture.body
                    ]
                )
                await MainActor.run { browserState.clearSelectedText() }
            }
        case .swipe:
            Task {
                _ = try? await AgentToolExecutor.shared.execute(
                    toolName: "capture_swipe",
                    arguments: [
                        "url": capture.sourceURL.absoluteString,
                        "hook": capture.body
                    ]
                )
                await MainActor.run { browserState.clearSelectedText() }
            }
        case .askCosmo:
            Task { @MainActor in
                CosmoWindowPanelController.shared.show()
                await CosmoWindowViewModel.shared.sendMessage("""
                Analyze this selected passage from \(capture.title):

                \(capture.body)

                Source: \(capture.sourceURL.absoluteString)
                """)
                browserState.clearSelectedText()
            }
        }
    }

    private func browserErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DS.orange)
            Text("Could not load this page")
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
            Text(message)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(action: browserState.reload) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(DS.buttonText)
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DS.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }
}

private struct CosmoBrowserCaptureButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct CosmoBrowserRenamePinSheet: View {
    let pin: CosmoBrowserPinnedSite
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var draftName: String
    @FocusState private var isNameFocused: Bool

    init(
        pin: CosmoBrowserPinnedSite,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.pin = pin
        self.onCancel = onCancel
        self.onSave = onSave
        _draftName = State(initialValue: pin.displayName)
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.entitySwipe)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Pin")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                    Text(pin.host)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }

            TextField("Pin name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(save)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(DS.bg)
        .onAppear {
            isNameFocused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
    }
}

private struct CosmoBrowserToolbarButton: View {
    let systemName: String
    let help: String
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? DS.textSecondary : DS.textMuted.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered && isEnabled ? DS.surfaceHover : DS.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isHovered && isEnabled ? DS.borderActive : DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
            if hovering && isEnabled {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

@MainActor
final class CosmoWebBrowserState: ObservableObject {
    @Published var displayTitle: String
    @Published var displayURL: String
    @Published var addressText: String
    @Published var currentURL: URL?
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?
    @Published var selectedText: String = ""
    @Published var pins: [CosmoBrowserPinnedSite] = []
    @Published var recentHistory: [CosmoBrowserHistoryItem] = []
    @Published var authenticationRoute: CosmoBrowserAuthenticationRoute = .embedded
    @Published private(set) var profile: CosmoBrowserProfile
    @Published private(set) var webViewIdentity = UUID()

    private weak var webView: WKWebView?
    private var session: CosmoBrowserSession
    private let initialURL: URL
    let store: CosmoBrowserStore
    fileprivate var navigationRequest: CosmoBrowserNavigationRequest
    private var lastRecordedVisitSignature: String?

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
        self.navigationRequest = CosmoBrowserNavigationRequest(url: initialURL)
    }

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isCurrentSitePinned: Bool {
        guard let currentURL else { return false }
        let host = CosmoBrowserPinnedSite.normalizedHost(for: currentURL)
        return pins.contains { $0.host == host }
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
        load(url)
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

    func toggleCurrentSitePin() {
        guard let currentURL else { return }
        let host = CosmoBrowserPinnedSite.normalizedHost(for: currentURL)

        if isCurrentSitePinned {
            session.unpin(host: host)
            pins.removeAll { $0.host == host }
        } else {
            session.recordVisit(url: currentURL, title: displayTitle)
            guard let pin = session.pinCurrentSite() else { return }
            pins.removeAll { $0.host == pin.host }
            pins.append(pin)
            pins.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }

        let pinsSnapshot = pins
        let profileID = profile.id
        Task {
            try? await store.savePins(pinsSnapshot, for: profileID)
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
        session.unpin(host: pin.host)
        pins.removeAll { $0.id == pin.id }
        session.pinnedSites = pins

        let pinsSnapshot = pins
        let profileID = profile.id
        Task {
            try? await store.savePins(pinsSnapshot, for: profileID)
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

private struct CosmoBrowserWebView: NSViewRepresentable {
    @ObservedObject var state: CosmoWebBrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = state.profile.websiteDataMode.makeDataStore()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = context.coordinator.userContentController

        let webView = CosmoBrowserWKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        context.coordinator.webView = webView
        context.coordinator.installDeleteKeyMonitor(for: webView)
        state.attach(webView)
        context.coordinator.lastNavigationRequestID = state.navigationRequest.id
        webView.load(URLRequest(url: state.navigationRequest.url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastNavigationRequestID != state.navigationRequest.id else { return }
        context.coordinator.lastNavigationRequestID = state.navigationRequest.id
        webView.load(URLRequest(url: state.navigationRequest.url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let state: CosmoWebBrowserState
        weak var webView: WKWebView?
        let userContentController: WKUserContentController
        var lastNavigationRequestID: UUID?
        private var deleteKeyMonitor: Any?

        init(state: CosmoWebBrowserState) {
            self.state = state
            self.userContentController = WKUserContentController()
            super.init()
            installSelectionBridge()
        }

        deinit {
            if let deleteKeyMonitor {
                NSEvent.removeMonitor(deleteKeyMonitor)
            }
            userContentController.removeScriptMessageHandler(forName: "cosmoSelection")
        }

        private func installSelectionBridge() {
            let script = WKUserScript(
                source: """
                (function() {
                    let lastSelection = '';
                    function notifySelection() {
                        const selection = window.getSelection ? window.getSelection().toString() : '';
                        if (selection !== lastSelection) {
                            lastSelection = selection;
                            window.webkit.messageHandlers.cosmoSelection.postMessage(selection);
                        }
                    }
                    document.addEventListener('mouseup', notifySelection);
                    document.addEventListener('keyup', notifySelection);
                    document.addEventListener('selectionchange', function() {
                        window.clearTimeout(window.__cosmoSelectionTimer);
                        window.__cosmoSelectionTimer = window.setTimeout(notifySelection, 120);
                    });
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(script)
            userContentController.add(self, name: "cosmoSelection")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "cosmoSelection", let text = message.body as? String else { return }
            Task { @MainActor in
                state.updateSelectedText(text)
            }
        }

        func installDeleteKeyMonitor(for webView: WKWebView) {
            if let deleteKeyMonitor {
                NSEvent.removeMonitor(deleteKeyMonitor)
            }

            deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak webView] event in
                guard let webView,
                      Self.isPlainDeleteKey(event),
                      Self.browserOwnsFirstResponder(in: event.window, webView: webView)
                else {
                    return event
                }

                event.window?.firstResponder?.keyDown(with: event)
                return nil
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateState(from: webView, clearError: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failState(with: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failState(with: error)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" || scheme == "about" else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func updateState(from webView: WKWebView, clearError: Bool = false) {
            let url = webView.url
            let title = webView.title
            let isLoading = webView.isLoading
            let estimatedProgress = webView.estimatedProgress
            let canGoBack = webView.canGoBack
            let canGoForward = webView.canGoForward

            Task { @MainActor in
                if clearError {
                    state.clearError()
                }
                state.applySnapshot(
                    url: url,
                    title: title,
                    isLoading: isLoading,
                    estimatedProgress: estimatedProgress,
                    canGoBack: canGoBack,
                    canGoForward: canGoForward
                )
            }
        }

        private func failState(with error: Error) {
            let message = error.localizedDescription
            Task { @MainActor in
                state.fail(with: NSError(domain: "CosmoWebBrowserPane", code: 0, userInfo: [NSLocalizedDescriptionKey: message]))
            }
        }

        private static func isPlainDeleteKey(_ event: NSEvent) -> Bool {
            guard event.keyCode == 51 || event.keyCode == 117 else { return false }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return !modifiers.contains(.command) && !modifiers.contains(.control)
        }

        private static func browserOwnsFirstResponder(in window: NSWindow?, webView: WKWebView) -> Bool {
            guard let responder = window?.firstResponder else { return false }

            if responder === webView {
                return true
            }

            if let responderView = responder as? NSView {
                return responderView === webView || responderView.isDescendant(of: webView)
            }

            return String(describing: type(of: responder)).contains("WK")
        }
    }
}

private final class CosmoBrowserWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
