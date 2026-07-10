import Foundation

actor CommandKUserCommandStore {
    private let fileURL: URL
    private var state: CommandKUserCommandState

    init(
        fileURL: URL = CommandKUserCommandStore.defaultFileURL(),
        seedBuiltIns: Bool = true
    ) {
        self.fileURL = fileURL
        self.state = (try? Self.load(from: fileURL)) ?? CommandKUserCommandState()

        if seedBuiltIns {
            var changed = false

            // Retired built-ins duplicated system commands row-for-row
            // ("swipes" ≡ Browse Swipes, "ideas" ≡ Open Ideas, …). Remove
            // previously seeded copies — but only while they still point at
            // the original route, so a user-repurposed alias survives.
            state.quicklinks.removeAll { quicklink in
                guard let retiredRoute = Self.retiredBuiltInRoutes[quicklink.id],
                      quicklink.route == retiredRoute else { return false }
                changed = true
                return true
            }

            let builtIns = Self.builtInQuicklinks()
            let existingIDs = Set(state.quicklinks.map(\.id))
            let missing = builtIns.filter { !existingIDs.contains($0.id) }
            if !missing.isEmpty {
                state.quicklinks.append(contentsOf: missing)
                changed = true
            }
            if changed {
                try? Self.persist(state, to: fileURL)
            }
        }
    }

    func saveQuicklink(_ quicklink: CommandKQuicklink) throws {
        state.quicklinks.removeAll { $0.id == quicklink.id }
        state.quicklinks.append(quicklink)
        state.quicklinks.sort { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
        try persist()
    }

    func searchQuicklinks(_ query: String) throws -> [CommandKQuicklink] {
        let normalized = Self.normalized(query)
        return state.quicklinks
            .filter { quicklink in
                normalized.isEmpty ||
                    Self.normalized(quicklink.alias).contains(normalized) ||
                    Self.normalized(quicklink.title).contains(normalized) ||
                    quicklink.query.map { Self.normalized($0).contains(normalized) } == true
            }
            .sorted { lhs, rhs in
                quicklinkScore(lhs, query: normalized) > quicklinkScore(rhs, query: normalized)
            }
    }

    func saveClip(_ clip: CommandKMemoryClip) throws {
        state.clips.removeAll { $0.id == clip.id }
        state.clips.append(clip)
        try persist()
    }

    func recentClips(limit: Int) throws -> [CommandKMemoryClip] {
        Array(state.clips.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(limit))
    }

    func saveSnippet(_ snippet: CommandKSnippet) throws {
        state.snippets.removeAll { $0.id == snippet.id }
        state.snippets.append(snippet)
        try persist()
    }

    func searchSnippets(_ query: String) throws -> [CommandKSnippet] {
        let normalized = Self.normalized(query)
        return state.snippets.filter {
            normalized.isEmpty ||
                Self.normalized($0.alias).contains(normalized) ||
                Self.normalized($0.title).contains(normalized) ||
                Self.normalized($0.body).contains(normalized)
        }
    }

    private func persist() throws {
        try Self.persist(state, to: fileURL)
    }

    private static func persist(_ state: CommandKUserCommandState, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private func quicklinkScore(_ quicklink: CommandKQuicklink, query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        let alias = Self.normalized(quicklink.alias)
        let title = Self.normalized(quicklink.title)
        if alias == query { return 100 }
        if alias.hasPrefix(query) { return 80 }
        if title.hasPrefix(query) { return 60 }
        if alias.contains(query) { return 40 }
        if title.contains(query) { return 20 }
        return 0
    }

    private static func load(from url: URL) throws -> CommandKUserCommandState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CommandKUserCommandState.self, from: data)
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CosmoOS", isDirectory: true)
            .appendingPathComponent("CommandKUserCommands.json")
    }

    private static func normalized(_ raw: String) -> String {
        raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Built-ins that were pure duplicates of system commands ("swipes"
    /// mirrored Browse Swipes, "ideas" mirrored Open Ideas, "today" mirrored
    /// Go to Command Center, "library"/"database" mirrored Open Library).
    /// The system commands own those destinations; keyed by id → the route
    /// each built-in originally shipped with.
    static let retiredBuiltInRoutes: [String: CommandKQuicklinkRoute] = [
        "today": .commandCenter,
        "swipes": .commandKDomain("swipeGallery"),
        "ideas": .commandKDomain("ideas"),
        "library": .commandKDomain("database"),
        "database": .commandKDomain("database")
    ]

    private static func builtInQuicklinks() -> [CommandKQuicklink] {
        let now = Date(timeIntervalSince1970: 1)
        return [
            CommandKQuicklink(
                id: "inquiries",
                alias: "inquiries",
                title: "Inquiries",
                route: .savedSearch("inquiry"),
                query: "inquiry",
                createdAt: now,
                updatedAt: now
            )
        ]
    }
}
