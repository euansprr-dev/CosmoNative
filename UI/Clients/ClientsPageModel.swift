// CosmoOS/UI/Clients/ClientsPageModel.swift
// The Clients index: every client as a row with what matters at a glance —
// identity, in-pipeline count, next ship day, and this week's cadence quota.
// Counts come from the Pipeline loader (json-scoped SQL), never from the
// LIKE prefilter; cadence is the dossier's declared frequency, parsed.

import SwiftUI
import GRDB

struct ClientIndexRow: Identifiable, Equatable, Sendable {
    let uuid: String
    let name: String
    let handle: String?
    let niche: String?
    let platforms: [SocialPlatform]
    let postingFrequency: String?
    let inPipeline: Int
    let scheduled: Int
    let shipped30d: Int
    let nextShip: Date?
    let lastShipped: Date?
    let bestViews30d: Int?
    let cadence: ClientCadence?
    let metThisWeek: Int

    var id: String { uuid }

    var quota: (met: Int, target: Int)? {
        cadence.map { $0.quota(scheduledOrShipped: metThisWeek) }
    }
}

@MainActor
@Observable
final class ClientsPageModel {
    private(set) var rows: [ClientIndexRow] = []
    private(set) var isLoaded = false

    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var hasPrewarmed = false

    func start() async {
        startObserving()
        if !isLoaded { await load() }
    }

    func prewarmIfNeeded() async {
        guard !hasPrewarmed else { return }
        hasPrewarmed = true
        await load()
    }

    func stop() {
        observation?.cancel()
        observation = nil
    }

    func row(_ uuid: String) -> ClientIndexRow? {
        rows.first { $0.uuid == uuid }
    }

    private func startObserving() {
        guard observation == nil, let db = CosmoDatabase.shared.dbPool else { return }
        let tracked = ValueObservation
            .tracking { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) || ':' || COALESCE(MAX(updated_at), '') FROM atoms WHERE type IN ('content', 'client_profile') AND is_deleted = 0"
                ) ?? ""
            }
            .removeDuplicates()
        observation = tracked.start(in: db, onError: { _ in }) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func load() async {
        async let clientsLoad = ContentPipelineLoader.loadClients()
        async let contentLoad = ContentPipelineLoader.load(scope: .all, filters: PipelineFilters())
        async let perfLoad = ContentPerfStore.latestByContent()
        let (clients, content, perf) = await (clientsLoad, contentLoad, perfLoad)
        let profiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
        let handles = Dictionary(uniqueKeysWithValues: profiles.map { profile in
            (profile.uuid, profile.metadataValue(as: ClientProfileMetadata.self)?.handle)
        })

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let window = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let week = calendar.dateInterval(of: .weekOfYear, for: today)

        var byClient: [String: [PipelineContentItem]] = [:]
        for item in content {
            guard let uuid = item.clientUUID else { continue }
            byClient[uuid, default: []].append(item)
        }

        let built = clients.map { client -> ClientIndexRow in
            let items = byClient[client.uuid] ?? []
            let live = items.filter { !$0.isShipped }
            let scheduled = live.filter { $0.scheduledAt != nil && ($0.scheduledAt ?? today) >= today }
            let shipped = items.filter { $0.isShipped }
            let recentShipped = shipped.filter { ($0.latestPublish?.publishedAtDate ?? .distantPast) >= window }
            let nextShip = scheduled.compactMap(\.scheduledAt).min()
            let lastShipped = shipped.compactMap { $0.latestPublish?.publishedAtDate }.max()
            let bestViews = recentShipped.compactMap { perf[$0.id]?.views }.max()
            let metThisWeek = items.filter { item in
                guard let week else { return false }
                if let day = item.scheduledAt, week.contains(day) { return true }
                if let published = item.latestPublish?.publishedAtDate, week.contains(published) { return true }
                return false
            }.count
            return ClientIndexRow(
                uuid: client.uuid,
                name: client.name,
                handle: handles[client.uuid] ?? nil,
                niche: client.niche,
                platforms: client.platforms,
                postingFrequency: client.postingFrequency,
                inPipeline: live.count,
                scheduled: scheduled.count,
                shipped30d: recentShipped.count,
                nextShip: nextShip,
                lastShipped: lastShipped,
                bestViews30d: bestViews,
                cadence: ClientCadence.parse(client.postingFrequency),
                metThisWeek: metThisWeek
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        withAnimation(ProMotionSprings.gentle) {
            rows = built
            isLoaded = true
        }
    }
}
