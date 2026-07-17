// CosmoOS/Navigation/Browser/CosmoBrowserStore.swift
// JSON-backed persistence for browser pins and history, keyed per profile.

import Foundation

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

    func upsertPin(_ pin: CosmoBrowserPinnedSite, for profileID: String) throws -> [CosmoBrowserPinnedSite] {
        var pins = snapshot.pinnedSitesByProfile[profileID] ?? []
        pins.removeAll { $0.pageKey == pin.pageKey }
        pins.append(pin)
        pins.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        snapshot.pinnedSitesByProfile[profileID] = pins
        try persist()
        return pins
    }

    func removePin(id: UUID, for profileID: String) throws -> [CosmoBrowserPinnedSite] {
        var pins = snapshot.pinnedSitesByProfile[profileID] ?? []
        pins.removeAll { $0.id == id }
        snapshot.pinnedSitesByProfile[profileID] = pins
        try persist()
        return pins
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
