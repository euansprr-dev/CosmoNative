// CosmoOS/Canvas/CanvasAtomObservationHub.swift
// One shared GRDB observation + warm atom cache for all mounted canvas blocks.
//
// Before this existed, every mounted note/sticky block ran its own
// ValueObservation filtered by `uuid` — a non-rowid filter, so GRDB tracked
// the FULL atoms table per block and every atom write anywhere re-ran every
// block's fetch and compared multi-hundred-KB metadata strings on the main
// thread. Block views also re-fetched their entity atom on every mount even
// though the thinkspace switch had just batch-fetched the exact same rows.
//
// The hub replaces both patterns:
// - `CanvasAtomWarmStore` serves the switch's batch-fetched atoms to mounting
//   views synchronously (no per-block round-trips, no blank-content frames).
// - `CanvasAtomObservationHub` runs ONE light observation (uuid, version,
//   timestamp columns only) over the mounted uuids, batch-fetches just the
//   rows that actually changed, and fans full atoms out to subscribers.
//   Deduplication happens on version fields — never on payload strings.

import Foundation
import SwiftUI
import Combine
import GRDB

// MARK: - Warm Store

/// Most-recently-fetched entity atoms for canvas blocks, keyed by uuid and
/// row id. Populated by `SpatialEngine.fetchBlocksSnapshot` (thinkspace
/// switches, hover prewarm, cross-thinkspace reloads) and kept fresh by the
/// observation hub. Mounting block views consult this synchronously instead
/// of firing their own repository fetches.
@MainActor
final class CanvasAtomWarmStore {
    static let shared = CanvasAtomWarmStore()

    private struct Entry {
        let atom: Atom
        var stampedAt: Date
    }

    private var entriesByUUID: [String: Entry] = [:]
    private var uuidByID: [Int64: String] = [:]
    /// Generous: the whole DB holds a few thousand atoms and only canvas
    /// entities land here; the trim exists so long sessions can't grow the
    /// store without bound (note metadata columns can be hundreds of KB).
    private let capacity = 600

    private init() {}

    func atom(uuid: String) -> Atom? {
        guard !uuid.isEmpty else { return nil }
        return entriesByUUID[uuid]?.atom
    }

    func atom(id: Int64) -> Atom? {
        guard id > 0, let uuid = uuidByID[id] else { return nil }
        return entriesByUUID[uuid]?.atom
    }

    @discardableResult
    fileprivate func store(_ atom: Atom) -> Bool {
        if let current = entriesByUUID[atom.uuid]?.atom,
           atom.updatedAt < current.updatedAt
            || (atom.updatedAt == current.updatedAt && atom.localVersion < current.localVersion) {
            return false
        }
        entriesByUUID[atom.uuid] = Entry(atom: atom, stampedAt: Date())
        if let id = atom.id {
            uuidByID[id] = atom.uuid
        }
        trimIfNeeded()
        return true
    }

    private func trimIfNeeded() {
        guard entriesByUUID.count > capacity else { return }
        let victims = entriesByUUID
            .sorted { $0.value.stampedAt < $1.value.stampedAt }
            .prefix(entriesByUUID.count - capacity)
            .map(\.key)
        for uuid in victims {
            if let id = entriesByUUID[uuid]?.atom.id {
                uuidByID.removeValue(forKey: id)
            }
            entriesByUUID.removeValue(forKey: uuid)
        }
    }
}

// MARK: - Observation Hub

/// Handle returned by `subscribe` — hold it in view `@State` and pass it back
/// to `unsubscribe` on disappear (or before re-subscribing with a new uuid).
struct CanvasAtomSubscription {
    let uuid: String
    fileprivate let token: UUID
}

@MainActor
final class CanvasAtomObservationHub {
    static let shared = CanvasAtomObservationHub()

    private struct KnownVersion: Equatable {
        let localVersion: Int64
        let updatedAt: String
    }

    /// Light projection of an atoms row — the observation fetches ONLY these
    /// columns, so bookkeeping-only writes (`_local_pending`,
    /// `_server_version`) never wake subscribers at all.
    private struct LightRow {
        let uuid: String
        let localVersion: Int64
        let updatedAt: String
    }

    private var subscribers: [String: [UUID: @MainActor (Atom) -> Void]] = [:]
    /// Last version delivered (or baselined from the warm store) per uuid.
    private var knownVersions: [String: KnownVersion] = [:]

    private var observationCancellable: AnyCancellable?
    private var restartTask: Task<Void, Never>?
    private var fetchGeneration = 0

    private init() {}

    /// Register for full-atom updates. By default the subscriber's current
    /// content is assumed to match the warm-store vintage (canvas block views
    /// load from it at mount), so only strictly newer data is delivered —
    /// never an initial echo of what the view just rendered.
    ///
    /// `deliverCurrentValue: true` opts into an initial delivery (warm store
    /// synchronously, one batch fetch otherwise) for surfaces that LOAD via
    /// their observation, like note focus mode.
    func subscribe(
        uuid: String,
        deliverCurrentValue: Bool = false,
        onChange: @escaping @MainActor (Atom) -> Void
    ) -> CanvasAtomSubscription? {
        guard !uuid.isEmpty else { return nil }
        let token = UUID()
        subscribers[uuid, default: [:]][token] = onChange
        if knownVersions[uuid] == nil,
           let warm = CanvasAtomWarmStore.shared.atom(uuid: uuid) {
            knownVersions[uuid] = KnownVersion(
                localVersion: warm.localVersion,
                updatedAt: warm.updatedAt
            )
        }
        if deliverCurrentValue {
            if let warm = CanvasAtomWarmStore.shared.atom(uuid: uuid) {
                deliverInitialValue(warm, to: token, uuid: uuid)
            } else {
                Task { @MainActor [weak self] in
                    guard let atoms = try? await AtomRepository.shared.fetchBatch(uuids: [uuid]),
                          let atom = atoms.first else { return }
                    guard let self, self.subscribers[uuid]?[token] != nil else { return }
                    self.deliverInitialValue(atom, to: token, uuid: uuid)
                }
            }
        }
        scheduleObservationRestart()
        return CanvasAtomSubscription(uuid: uuid, token: token)
    }

    /// Initial-value delivery: newer-than-baseline data fans out to every
    /// subscriber of the uuid; an unchanged baseline still hands the
    /// requesting subscriber its current value (that's the point of asking).
    private func deliverInitialValue(_ fetchedAtom: Atom, to token: UUID, uuid: String) {
        CanvasAtomWarmStore.shared.store(fetchedAtom)
        let atom = CanvasAtomWarmStore.shared.atom(uuid: uuid) ?? fetchedAtom
        let incoming = KnownVersion(localVersion: atom.localVersion, updatedAt: atom.updatedAt)
        let known = knownVersions[uuid]
        knownVersions[uuid] = incoming
        if known != incoming, let callbacks = subscribers[uuid] {
            for callback in callbacks.values {
                callback(atom)
            }
        } else if let callback = subscribers[uuid]?[token] {
            callback(atom)
        }
    }

    func unsubscribe(_ subscription: CanvasAtomSubscription?) {
        guard let subscription else { return }
        subscribers[subscription.uuid]?.removeValue(forKey: subscription.token)
        if subscribers[subscription.uuid]?.isEmpty == true {
            subscribers.removeValue(forKey: subscription.uuid)
            knownVersions.removeValue(forKey: subscription.uuid)
        }
        scheduleObservationRestart()
    }

    /// Absorb a batch of freshly-fetched atoms: warm the store and deliver
    /// each atom that is newer than its subscriber's known baseline. Called
    /// by `SpatialEngine.fetchBlocksSnapshot` (so an authoritative switch
    /// fetch that differs from the applied snapshot corrects mounted views
    /// as targeted data updates) and by the hub's own observation wakes.
    func absorb(_ atoms: [Atom]) {
        for atom in atoms {
            guard CanvasAtomWarmStore.shared.store(atom) else { continue }
            deliverIfNewer(atom)
        }
    }

    private func deliverIfNewer(_ atom: Atom) {
        guard let callbacks = subscribers[atom.uuid], !callbacks.isEmpty else { return }
        let incoming = KnownVersion(localVersion: atom.localVersion, updatedAt: atom.updatedAt)
        if let known = knownVersions[atom.uuid] {
            if known == incoming { return }
            // Never regress: a slow batch fetch racing a newer wake must not
            // overwrite fresher content with an older row. ISO8601 strings
            // compare chronologically; equal stamps defer to version drift.
            if incoming.updatedAt < known.updatedAt
                || (incoming.updatedAt == known.updatedAt && incoming.localVersion < known.localVersion) { return }
        }
        knownVersions[atom.uuid] = incoming
        for callback in callbacks.values {
            callback(atom)
        }
    }

    // MARK: Observation lifecycle

    /// Mounts arrive in bursts (a thinkspace switch mounts every visible
    /// block in one frame) — coalesce restarts so a switch restarts the
    /// observation once, not once per block.
    private func scheduleObservationRestart() {
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.restartObservation()
        }
    }

    private func restartObservation() {
        observationCancellable?.cancel()
        observationCancellable = nil
        let uuids = Array(subscribers.keys)
        guard !uuids.isEmpty else { return }

        let placeholders = Array(repeating: "?", count: uuids.count).joined(separator: ",")
        let sql = """
            SELECT uuid, _local_version, updated_at FROM atoms
            WHERE uuid IN (\(placeholders))
            """
        let observation = ValueObservation.tracking { db -> [LightRow] in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(uuids)).map { row in
                LightRow(
                    uuid: row["uuid"] ?? "",
                    localVersion: row["_local_version"] ?? 0,
                    updatedAt: row["updated_at"] ?? ""
                )
            }
        }
        observationCancellable = observation
            .publisher(in: CosmoDatabase.shared.dbPool)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] rows in
                    self?.handleObservedRows(rows)
                }
            )
    }

    private func handleObservedRows(_ rows: [LightRow]) {
        var changedUUIDs: [String] = []
        for row in rows {
            let incoming = KnownVersion(localVersion: row.localVersion, updatedAt: row.updatedAt)
            if knownVersions[row.uuid] != incoming {
                changedUUIDs.append(row.uuid)
            }
        }
        guard !changedUUIDs.isEmpty else { return }

        // Full rows are fetched only for atoms that actually changed; a newer
        // wake supersedes an in-flight fetch (the superseded uuids still read
        // as changed on the next pass, so nothing is lost).
        fetchGeneration &+= 1
        let generation = fetchGeneration
        Task { @MainActor [weak self] in
            guard let atoms = try? await AtomRepository.shared.fetchBatch(uuids: changedUUIDs) else { return }
            guard let self, self.fetchGeneration == generation else { return }
            self.absorb(atoms)
        }
    }
}
