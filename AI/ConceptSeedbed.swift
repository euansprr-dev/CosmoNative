// CosmoOS/AI/ConceptSeedbed.swift
// The Seedbed: concepts accrue mass on a Deep Dive while the user researches,
// and never become pages on their own. The live router's capture-time concept
// tags feed accrual in real time; ConceptResolver's session-wide pass tidies
// the bed (canonical names, aliases, folds, existing-page merge targets).
// Pages are born only through a development conversation (the Concept Desk).

import Foundation

// MARK: - Ripeness

/// Deterministic, legible ripeness signals (Gardener philosophy: signals the
/// user can read and verify, never vibes). Every ripe verdict carries the
/// reason shown on the badge.
enum ConceptRipeness {
    struct Verdict: Equatable, Sendable {
        var isRipe: Bool
        var reason: String?

        static let notRipe = Verdict(isRipe: false, reason: nil)
    }

    /// Pending (unconsumed) material across ≥2 sessions, a heavy single-session
    /// run, or a user pin. Developed and dismissed seedlings are never ripe.
    static func evaluate(_ seedling: IncubatingConcept) -> Verdict {
        guard seedling.status == .incubating else { return .notRipe }
        if seedling.pinnedAt != nil {
            return Verdict(isRipe: true, reason: "Pinned")
        }
        let pending = seedling.pendingItems
        let sessions = Set(pending.compactMap(\.sessionUUID)).count
        if pending.count >= 4, sessions >= 2 {
            return Verdict(isRipe: true, reason: "\(pending.count) captures · \(sessions) sessions")
        }
        let maxInOneSession = Dictionary(grouping: pending, by: { $0.sessionUUID ?? "" })
            .values.map(\.count).max() ?? 0
        if maxInOneSession >= 7 {
            return Verdict(isRipe: true, reason: "\(maxInOneSession) captures this session")
        }
        return .notRipe
    }
}

// MARK: - Reducer (pure, unit-tested)

enum ConceptSeedbedReducer {
    /// One routed capture's contribution: the live router's concept tags plus
    /// everything the evidence rail later needs to display it.
    struct AccrualEntry: Sendable {
        var conceptNames: [String]
        var extractUUID: String
        var rawSnippet: String
        var extractKind: ExtractKind?
        var sourceUUID: String?
        var sessionUUID: String?
        var capturedAt: String

        init(
            conceptNames: [String],
            extractUUID: String,
            rawSnippet: String,
            extractKind: ExtractKind? = nil,
            sourceUUID: String? = nil,
            sessionUUID: String? = nil,
            capturedAt: String = ISO8601.string(from: Date())
        ) {
            self.conceptNames = conceptNames
            self.extractUUID = extractUUID
            self.rawSnippet = rawSnippet
            self.extractKind = extractKind
            self.sourceUUID = sourceUUID
            self.sessionUUID = sessionUUID
            self.capturedAt = capturedAt
        }
    }

    struct AccrualResult: Sendable {
        var seedbed: [IncubatingConcept]
        var changed: Bool
        /// Keys that crossed the ripeness line during THIS accrual — the
        /// ripening-nudge trigger.
        var newlyRipeKeys: [String]
    }

    /// Upserts each tagged capture into its seedling(s). One extract carrying
    /// two concept tags lands in both seedlings (overlap is good — same rule
    /// as ConceptResolver). Dedup is per-seedling by sourceExtractUUID, so
    /// re-running a batch never double-counts. Dismissed seedlings stop
    /// accruing; developed ones keep collecting (their pending items become
    /// the "new since last visit" material on the page's evidence rail).
    static func accrue(
        _ seedbed: [IncubatingConcept],
        entries: [AccrualEntry],
        existingPageUUIDsByKey: [String: String] = [:]
    ) -> AccrualResult {
        var result = seedbed
        var changed = false
        var newlyRipe: [String] = []

        for entry in entries {
            let snippet = entry.rawSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snippet.isEmpty, !entry.extractUUID.isEmpty else { continue }
            for name in entry.conceptNames {
                let key = ConceptResolver.conceptKey(name)
                guard !key.isEmpty else { continue }
                if let idx = result.firstIndex(where: { $0.conceptKey == key }) {
                    guard result[idx].status != .dismissed else { continue }
                    guard !result[idx].stagedItems.contains(where: { $0.sourceExtractUUID == entry.extractUUID }) else { continue }
                    let wasRipe = ConceptRipeness.evaluate(result[idx]).isRipe
                    result[idx].stagedItems.append(item(from: entry, snippet: snippet))
                    result[idx].lastTouchedAt = entry.capturedAt
                    if result[idx].mergeTargetConnectionUUID == nil,
                       let pageUUID = existingPageUUIDsByKey[key] {
                        result[idx].mergeTargetConnectionUUID = pageUUID
                    }
                    changed = true
                    if !wasRipe, ConceptRipeness.evaluate(result[idx]).isRipe {
                        newlyRipe.append(key)
                    }
                } else {
                    result.append(IncubatingConcept(
                        conceptKey: key,
                        name: name,
                        stagedItems: [item(from: entry, snippet: snippet)],
                        mergeTargetConnectionUUID: existingPageUUIDsByKey[key],
                        createdAt: entry.capturedAt,
                        lastTouchedAt: entry.capturedAt
                    ))
                    changed = true
                }
            }
        }
        return AccrualResult(seedbed: result, changed: changed, newlyRipeKeys: newlyRipe)
    }

    private static func item(from entry: AccrualEntry, snippet: String) -> StagedConceptItem {
        StagedConceptItem(
            sourceExtractUUID: entry.extractUUID,
            rawSnippet: snippet,
            proposedSection: entry.extractKind.flatMap { ConnectionRoutingEngine.sectionType(for: $0)?.rawValue },
            sourceUUID: entry.sourceUUID,
            sessionUUID: entry.sessionUUID,
            capturedAt: entry.capturedAt
        )
    }

    /// ConceptResolver's whole-session view refines the bed: canonical names +
    /// aliases, parent/related links, merge targets for existing pages, missing
    /// items backfilled, and near-duplicate folds (a seedling the resolver did
    /// not name, whose every item it assigned to ONE survivor, folds into that
    /// survivor; its name lives on as an alias). Never destroys user-visible
    /// mass: seedlings the resolver never saw are left untouched, and pinned
    /// or developed seedlings never fold.
    static func applyTidy(
        _ seedbed: [IncubatingConcept],
        assignments: [ConceptResolver.ConceptAssignment],
        extracts: [Atom],
        sessionUUID: String?
    ) -> [IncubatingConcept] {
        var result = seedbed
        let extractsByUUID = Dictionary(
            extracts.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let now = ISO8601.string(from: Date())

        // 1. Upsert every assignment as a seedling; backfill missing items.
        for assignment in assignments {
            let idx: Int
            if let existing = result.firstIndex(where: { $0.conceptKey == assignment.conceptKey }) {
                idx = existing
            } else {
                result.append(IncubatingConcept(
                    conceptKey: assignment.conceptKey,
                    name: assignment.conceptName,
                    createdAt: now,
                    lastTouchedAt: now
                ))
                idx = result.count - 1
            }
            guard result[idx].status != .dismissed else { continue }
            result[idx].name = assignment.conceptName
            let knownAliases = Set((result[idx].aliases + [result[idx].name]).map(ConceptResolver.conceptKey) + [result[idx].conceptKey])
            result[idx].aliases += assignment.aliases.filter { !knownAliases.contains(ConceptResolver.conceptKey($0)) }
            if result[idx].parentConceptName == nil {
                result[idx].parentConceptName = assignment.parentConceptName
            }
            let knownRelated = Set(result[idx].relatedConceptNames.map(ConceptResolver.conceptKey))
            result[idx].relatedConceptNames += assignment.relatedConceptNames
                .filter { !knownRelated.contains(ConceptResolver.conceptKey($0)) }
            if case .mergeInto(let target) = assignment.action {
                result[idx].mergeTargetConnectionUUID = target
            }
            let knownExtracts = Set(result[idx].stagedItems.map(\.sourceExtractUUID))
            for uuid in assignment.extractUUIDs where !knownExtracts.contains(uuid) {
                guard let extract = extractsByUUID[uuid] else { continue }
                let body = (extract.body ?? extract.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                result[idx].stagedItems.append(StagedConceptItem(
                    sourceExtractUUID: uuid,
                    rawSnippet: body,
                    proposedSection: extract.extractMetadata.flatMap { ConnectionRoutingEngine.sectionType(for: $0.kind)?.rawValue },
                    sourceUUID: extract.extractMetadata?.sourceUUID,
                    sessionUUID: extract.extractMetadata?.parentSessionUUID ?? sessionUUID,
                    capturedAt: now
                ))
                result[idx].lastTouchedAt = now
            }
        }

        // 2. Fold near-duplicates the resolver consolidated away. A candidate
        //    folds only when the resolver saw EVERY one of its items and put
        //    them all under one surviving key.
        let assignmentKeys = Set(assignments.map(\.conceptKey))
        var extractHome: [String: String] = [:]   // extractUUID → surviving conceptKey
        for assignment in assignments {
            for uuid in assignment.extractUUIDs where extractHome[uuid] == nil {
                extractHome[uuid] = assignment.conceptKey
            }
        }
        var foldedKeys = Set<String>()
        for seedling in result
        where seedling.status == .incubating
            && seedling.pinnedAt == nil
            && !assignmentKeys.contains(seedling.conceptKey) {
            let itemUUIDs = seedling.stagedItems.map(\.sourceExtractUUID)
            guard !itemUUIDs.isEmpty,
                  itemUUIDs.allSatisfy({ extractHome[$0] != nil }) else { continue }
            let homes = Set(itemUUIDs.compactMap { extractHome[$0] })
            guard homes.count == 1, let home = homes.first, home != seedling.conceptKey,
                  let survivorIdx = result.firstIndex(where: { $0.conceptKey == home }) else { continue }
            let knownExtracts = Set(result[survivorIdx].stagedItems.map(\.sourceExtractUUID))
            result[survivorIdx].stagedItems += seedling.stagedItems.filter { !knownExtracts.contains($0.sourceExtractUUID) }
            let survivorAliasKeys = Set((result[survivorIdx].aliases + [result[survivorIdx].name]).map(ConceptResolver.conceptKey) + [home])
            if !survivorAliasKeys.contains(seedling.conceptKey) {
                result[survivorIdx].aliases.append(seedling.name)
            }
            result[survivorIdx].lastTouchedAt = now
            foldedKeys.insert(seedling.conceptKey)
        }
        result.removeAll { foldedKeys.contains($0.conceptKey) }
        return result
    }
}

// MARK: - Service (read-modify-write on the Deep Dive atom, serialized)

/// The single writer for `DeepDiveStructured.conceptSeedbed`. All mutations
/// chain behind the previous one — seedbed updates are read-modify-write on
/// the deep dive atom, and two in-flight batches must never clobber each
/// other's fetch.
@MainActor
final class ConceptSeedbedService {
    static let shared = ConceptSeedbedService()
    private init() {}

    private var writeChain: Task<Void, Never>?

    /// Live accrual from routed captures. Returns the seedlings that crossed
    /// the ripeness line in this write (the ripening-nudge payload).
    @discardableResult
    func accrue(
        deepDiveUUID: String,
        entries: [ConceptSeedbedReducer.AccrualEntry],
        existingPageUUIDsByKey: [String: String] = [:]
    ) async -> [IncubatingConcept] {
        guard !entries.isEmpty else { return [] }
        var newlyRipe: [IncubatingConcept] = []
        await enqueue {
            newlyRipe = await Self.mutate(deepDiveUUID: deepDiveUUID) { seedbed in
                let result = ConceptSeedbedReducer.accrue(
                    seedbed,
                    entries: entries,
                    existingPageUUIDsByKey: existingPageUUIDsByKey
                )
                let ripe = result.seedbed.filter { result.newlyRipeKeys.contains($0.conceptKey) }
                return (result.seedbed, result.changed, ripe)
            }
        }
        return newlyRipe
    }

    /// The resolver's whole-session tidy pass.
    func applyTidy(
        deepDiveUUID: String,
        assignments: [ConceptResolver.ConceptAssignment],
        extracts: [Atom],
        sessionUUID: String?
    ) async {
        guard !assignments.isEmpty else { return }
        await enqueue {
            _ = await Self.mutate(deepDiveUUID: deepDiveUUID) { seedbed in
                let tidied = ConceptSeedbedReducer.applyTidy(
                    seedbed,
                    assignments: assignments,
                    extracts: extracts,
                    sessionUUID: sessionUUID
                )
                return (tidied, true, [])
            }
        }
    }

    /// Develops a seedling into a page: reuses the merge-target page when the
    /// seedling feeds an existing one, otherwise births an empty page (the
    /// development conversation fills it — never bulk filing), links it on the
    /// deep dive (`deepDiveConnection` is the scoping link), and marks the
    /// seedling developed. Returns the connection UUID to open.
    func developSeedling(deepDiveUUID: String, conceptKey: String) async -> String? {
        var opened: String?
        await enqueue {
            guard let deepDive = try? await AtomRepository.shared.fetch(uuid: deepDiveUUID) else { return }
            var structured = deepDive.deepDiveStructured ?? DeepDiveStructured()
            guard let idx = structured.conceptSeedbed.firstIndex(where: { $0.conceptKey == conceptKey }),
                  structured.conceptSeedbed[idx].status != .dismissed else { return }

            let seedling = structured.conceptSeedbed[idx]
            let connectionUUID: String
            if let existing = seedling.developedConnectionUUID ?? seedling.mergeTargetConnectionUUID {
                connectionUUID = existing
            } else {
                // The connection→dive backlink is what loadLinkTargets reads to
                // resolve siblings for inline mention links — pages born here
                // must carry it, like crystallization-born pages always did.
                let atom = Atom.new(type: .connection, title: seedling.name, body: nil, metadata: nil)
                    .addingLink(AtomLink(
                        type: AtomLinkType.deepDiveConnection.rawValue,
                        uuid: deepDiveUUID,
                        entityType: AtomType.deepDive.rawValue
                    ))
                guard let created = try? await AtomRepository.shared.create(atom) else { return }
                connectionUUID = created.uuid
            }

            structured.conceptSeedbed[idx].status = .developed
            structured.conceptSeedbed[idx].developedConnectionUUID = connectionUUID
            structured.conceptSeedbed[idx].lastTouchedAt = ISO8601.string(from: Date())

            var copy = deepDive.withStructured(structured)
            var links = copy.linksList
            let link = AtomLink(
                type: AtomLinkType.deepDiveConnection.rawValue,
                uuid: connectionUUID,
                entityType: AtomType.connection.rawValue
            )
            if !links.contains(where: { $0.type == link.type && $0.uuid == link.uuid }) {
                links.append(link)
                copy = copy.withLinks(links)
            }
            do {
                _ = try await AtomRepository.shared.update(copy)
            } catch {
                print("[ConceptSeedbedService] develop save failed: \(error)")
                return
            }
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.seedbedChanged,
                object: nil,
                userInfo: ["deepDiveUUID": deepDiveUUID]
            )
            opened = connectionUUID
        }
        return opened
    }

    /// The Desk closed on an untouched page: born ripe or not at all. Deletes
    /// the page ONLY when this development created it (a pre-existing merge
    /// target is never deleted), removes the scoping link, and reverts the
    /// seedling to incubating so its mass keeps ripening.
    func abandonEmptyDevelopment(deepDiveUUID: String, conceptKey: String) async {
        await enqueue {
            guard let deepDive = try? await AtomRepository.shared.fetch(uuid: deepDiveUUID) else { return }
            var structured = deepDive.deepDiveStructured ?? DeepDiveStructured()
            guard let idx = structured.conceptSeedbed.firstIndex(where: { $0.conceptKey == conceptKey }),
                  structured.conceptSeedbed[idx].status == .developed,
                  structured.conceptSeedbed[idx].mergeTargetConnectionUUID == nil,
                  let connectionUUID = structured.conceptSeedbed[idx].developedConnectionUUID else { return }
            structured.conceptSeedbed[idx].status = .incubating
            structured.conceptSeedbed[idx].developedConnectionUUID = nil
            var copy = deepDive.withStructured(structured)
            copy = copy.withLinks(copy.linksList.filter {
                !($0.type == AtomLinkType.deepDiveConnection.rawValue && $0.uuid == connectionUUID)
            })
            do {
                _ = try await AtomRepository.shared.update(copy)
                try await AtomRepository.shared.delete(uuid: connectionUUID)
            } catch {
                print("[ConceptSeedbedService] abandon failed: \(error)")
                return
            }
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.seedbedChanged,
                object: nil,
                userInfo: ["deepDiveUUID": deepDiveUUID]
            )
        }
    }

    /// Direct seedling mutations from UI actions (pin, dismiss, develop).
    func updateSeedling(
        deepDiveUUID: String,
        conceptKey: String,
        _ transform: @escaping @Sendable (inout IncubatingConcept) -> Void
    ) async {
        await enqueue {
            _ = await Self.mutate(deepDiveUUID: deepDiveUUID) { seedbed in
                var copy = seedbed
                guard let idx = copy.firstIndex(where: { $0.conceptKey == conceptKey }) else {
                    return (copy, false, [])
                }
                transform(&copy[idx])
                return (copy, true, [])
            }
        }
    }

    // MARK: - Internals

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = writeChain
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        writeChain = task
        await task.value
    }

    /// Fetch fresh → mutate → save. The transform returns (newSeedbed,
    /// changed, ripePayload); nothing is written when unchanged.
    private static func mutate(
        deepDiveUUID: String,
        _ transform: @MainActor ([IncubatingConcept]) -> ([IncubatingConcept], Bool, [IncubatingConcept])
    ) async -> [IncubatingConcept] {
        guard let deepDive = try? await AtomRepository.shared.fetch(uuid: deepDiveUUID) else { return [] }
        var structured = deepDive.deepDiveStructured ?? DeepDiveStructured()
        let (newSeedbed, changed, ripe) = transform(structured.conceptSeedbed)
        guard changed else { return ripe }
        structured.conceptSeedbed = newSeedbed
        do {
            _ = try await AtomRepository.shared.update(deepDive.withStructured(structured))
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.seedbedChanged,
                object: nil,
                userInfo: ["deepDiveUUID": deepDiveUUID]
            )
        } catch {
            print("[ConceptSeedbedService] seedbed save failed: \(error)")
            return []
        }
        return ripe
    }
}
