// CosmoOS/UI/Ideas/IdeasPageModel.swift
// The Ideas destination's model (extracted July 2026, the Desk reinvention).
// Owns the live idea set, the dealt desk, and the page's verbs — pin, pass,
// assign, ripen, schedule — every one a key-preserving metadata write with a
// ⌘Z registration (the undo-everywhere law). MainView owns the instance so
// launch prewarming loads it before the first visit.

import SwiftUI
import GRDB

// MARK: - Client group

struct IdeasHomeGroup: Identifiable {
    let id: String
    let name: String
    let clientUUID: String?
    let ideas: [IdeaGalleryItem]
}

// MARK: - Model

@MainActor
@Observable
final class IdeasPageModel {
    /// Every live idea, newest first.
    var ideas: [IdeaGalleryItem] = []
    /// idea uuid → linked swipe thumbnail candidates, best first (the durable
    /// mirror can 400 when the upload never ran — the CDN original still
    /// serves; the card walks the list and collapses if every one fails).
    var inspirationThumbs: [String: [String]] = [:]
    /// idea uuid → the next OPEN development session's day (the focus-mode
    /// scheduled chip, card-sized): earliest planned day among the idea's
    /// non-completed linked tasks.
    var scheduledDays: [String: Date] = [:]
    /// The dealt desk — committed lane, per-client proposals, sparks tray.
    var desk: IdeasDeskEngine.Desk = .empty
    /// Passed (archived) ideas — never on the desk, browsable behind the
    /// ledger's Archived filter, searchable forever. Ideas promoted into
    /// content (inProduction/published) stay excluded: they're content now.
    var archivedIdeas: [IdeaGalleryItem] = []
    /// clientUUID → when their most recent piece went live (the digest's
    /// "shipped 3d" note), from content atoms past the publish line.
    var shippedRecency: [String: Date] = [:]
    // Derived state is STORED, rebuilt once per data change — never computed
    // per body read. A page body may evaluate many times between loads; the
    // grouping/sorting/scoring work happens exactly once per load.
    /// Clients alphabetical, Unassigned last; orphaned client ids fall into
    /// Unassigned rather than vanishing.
    private(set) var clientGroups: [IdeasHomeGroup] = []
    /// Clients you can assign a spark to — alphabetical, real profiles only.
    private(set) var assignableClients: [(uuid: String, name: String)] = []
    /// Everything the user still owns — live AND passed (search + lookups).
    private(set) var searchCorpus: [IdeaGalleryItem] = []
    /// uuid → desk-engine score, precomputed so the ledger's Ripest sort
    /// never re-parses dates per evaluation.
    private(set) var ripenessScores: [String: Double] = [:]
    var isLoaded = false
    var toastMessage: String?
    /// A deleted idea waiting out its undo window.
    private(set) var pendingDelete: IdeaGalleryItem?
    /// A passed (archived) idea whose undo toast is still up. Unlike delete,
    /// the write is already committed — the toast just offers the way back.
    private(set) var pendingPass: PendingPass?

    struct PendingPass {
        let idea: IdeaGalleryItem
        let previousStatus: IdeaStatus?
        let previousChangedAt: String?
    }

    private var clientProfiles: [Atom] = []
    private var pendingRemovals: Set<String> = []
    private var deleteCommitTask: Task<Void, Never>?
    private var passDismissTask: Task<Void, Never>?
    private var observation: AnyDatabaseCancellable?

    func start() async {
        await load()
        startObserving()
    }

    /// Launch-time warm: one load so the first visit paints instantly. No
    /// observation — that belongs to the page's visible lifetime (start/stop),
    /// and the page's own start() refreshes anything that moved while away.
    func prewarmIfNeeded() async {
        guard !isLoaded else { return }
        await load()
    }

    func stop() {
        observation?.cancel()
        observation = nil
        deleteCommitTask?.cancel()
        passDismissTask?.cancel()
    }

    /// Any idea-table write re-queries — local edits, sync applies, drops.
    private func startObserving() {
        guard observation == nil, let db = CosmoDatabase.shared.dbPool else { return }
        // Tasks ride the same trigger: scheduling an idea writes only a task
        // atom (the link lives ON the task), and the desk's committed lane
        // must follow it live.
        let tracked = ValueObservation
            .tracking { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) || ':' || COALESCE(MAX(updated_at), '') FROM atoms WHERE type IN ('idea', 'task') AND is_deleted = 0"
                ) ?? ""
            }
            .removeDuplicates()
        observation = tracked.start(in: db, onError: { _ in }) { [weak self] _ in
            Task { @MainActor in await self?.load() }
        }
    }

    func load() async {
        let atoms = (try? await AtomRepository.shared.fetchAll(type: .idea)) ?? []
        clientProfiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? clientProfiles

        let clientNames = Dictionary(
            uniqueKeysWithValues: clientProfiles.map { ($0.uuid, $0.title ?? "Client") }
        )
        // Activated ideas (Begin Writing → inProduction/published/archived) are
        // content pieces now — reachable via the content's sources, not the boards.
        let survivors = atoms.filter { !pendingRemovals.contains($0.uuid) }
        let live = survivors
            .filter { !($0.ideaMetadata?.ideaStatus?.isActivated ?? false) }
            .sorted { $0.updatedAt > $1.updatedAt }
        // Passed ideas keep a home: archived-by-hand, not promoted-to-content.
        let archived = survivors
            .filter { $0.ideaMetadata?.ideaStatus == .archived }
            .sorted {
                let a = $0.ideaMetadata?.statusChangedAt ?? $0.updatedAt
                let b = $1.ideaMetadata?.statusChangedAt ?? $1.updatedAt
                return a > b
            }

        func item(_ atom: Atom) -> IdeaGalleryItem? {
            atom.toIdeaGalleryItem(clientName: atom.ideaMetadata?.clientUUID.flatMap { clientNames[$0] })
        }
        let items = live.compactMap(item)
        let archivedItems = archived.compactMap(item)
        let thumbs = await Self.resolveInspiration(for: live + archived)
        let scheduled = await Self.resolveScheduledDays()
        let shipped = await Self.resolveShippedRecency()
        let dealt = IdeasDeskEngine.makeDesk(
            ideas: items,
            scheduledDays: scheduled,
            inspiration: Set(thumbs.keys),
            knownClientIds: Set(clientProfiles.map(\.uuid))
        )

        let corpus = items + archivedItems
        let inspiration = Set(thumbs.keys)
        let scoreNow = Date()
        var scores: [String: Double] = [:]
        scores.reserveCapacity(corpus.count)
        for idea in corpus {
            scores[idea.atomUUID] = IdeasDeskEngine.score(for: idea, inspiration: inspiration, now: scoreNow)
        }

        withAnimation(ProMotionSprings.gentle) {
            ideas = items
            archivedIdeas = archivedItems
            inspirationThumbs = thumbs
            scheduledDays = scheduled
            shippedRecency = shipped
            desk = dealt
            clientGroups = Self.groupByClient(items: items, clientProfiles: clientProfiles)
            assignableClients = Self.sortedAssignableClients(clientProfiles)
            searchCorpus = corpus
            ripenessScores = scores
            isLoaded = true
        }
    }

    /// Per client, when their most recent piece crossed the publish line
    /// (published or analyzing — a phase you only reach by shipping).
    private static func resolveShippedRecency() async -> [String: Date] {
        let contents = (try? await AtomRepository.shared.fetchAll(type: .content)) ?? []
        var recency: [String: Date] = [:]
        for content in contents {
            guard let meta = content.metadataValue(as: ContentAtomMetadata.self),
                  meta.phase == .published || meta.phase == .analyzing,
                  let clientUUID = meta.clientProfileUUID else { continue }
            let shippedAt = meta.phaseEnteredAt.flatMap { ISO8601.date(from: $0) }
                ?? meta.lastPhaseTransition
                ?? ISO8601.date(from: content.updatedAt)
            guard let shippedAt else { continue }
            if let existing = recency[clientUUID], existing >= shippedAt { continue }
            recency[clientUUID] = shippedAt
        }
        return recency
    }

    /// The cards' scheduled chips: walk the task table once and keep, per
    /// linked idea, the earliest open session day.
    ///
    /// Matching lives in `IdeaTaskLinkService.openSessionDaysByIdea` so this
    /// page and the idea's own ⌘⇧T popover can never disagree about whether a
    /// session exists — they used to, and a promoted idea's chip went blank
    /// while the session sat on the calendar.
    private static func resolveScheduledDays() async -> [String: Date] {
        let tasks = (try? await AtomRepository.shared.fetchAll(type: .task)) ?? []
        return IdeaTaskLinkService.openSessionDaysByIdea(in: tasks)
    }

    /// The card's anchor: the linked swipe's thumbnail, cheapest source first.
    private static func resolveInspiration(for atoms: [Atom]) async -> [String: [String]] {
        var swipeByIdea: [String: String] = [:]
        for atom in atoms {
            let meta = atom.ideaMetadata
            guard let swipeUUID = meta?.linkedSwipeIds?.first
                ?? meta?.originSwipeUUID
                ?? meta?.supportingSwipeUUIDs?.first else { continue }
            swipeByIdea[atom.uuid] = swipeUUID
        }

        var thumbsBySwipe: [String: [String]] = [:]
        for swipeUUID in Set(swipeByIdea.values) {
            guard let swipe = try? await AtomRepository.shared.fetch(uuid: swipeUUID) else { continue }
            // Preferred (the Supabase mirror when present) first, the origin
            // CDN url second — mirrors are durable but occasionally missing.
            var candidates: [String] = []
            if let preferred = swipe.toSwipeGalleryItem()?.thumbnailUrl { candidates.append(preferred) }
            if let cdn = swipe.researchMetadata?.thumbnailUrl, !candidates.contains(cdn) { candidates.append(cdn) }
            if !candidates.isEmpty { thumbsBySwipe[swipeUUID] = candidates }
        }

        return swipeByIdea.compactMapValues { thumbsBySwipe[$0] }
    }

    // MARK: Grouping (the ⌘K board grammar — build once per load)

    private static func groupByClient(items: [IdeaGalleryItem], clientProfiles: [Atom]) -> [IdeasHomeGroup] {
        var byClient: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []
        let knownClientIds = Set(clientProfiles.map(\.uuid))

        for idea in items {
            if let clientUUID = idea.clientUUID, knownClientIds.contains(clientUUID) {
                byClient[clientUUID, default: []].append(idea)
            } else {
                unassigned.append(idea)
            }
        }

        var groups: [IdeasHomeGroup] = clientProfiles
            .sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
            .compactMap { client in
                guard let items = byClient[client.uuid], !items.isEmpty else { return nil }
                return IdeasHomeGroup(id: client.uuid, name: client.title ?? "Client", clientUUID: client.uuid, ideas: items)
            }
        if !unassigned.isEmpty {
            groups.append(IdeasHomeGroup(id: "__unassigned__", name: "Unassigned", clientUUID: nil, ideas: unassigned))
        }
        return groups
    }

    private static func sortedAssignableClients(_ clientProfiles: [Atom]) -> [(uuid: String, name: String)] {
        clientProfiles
            .map { ($0.uuid, $0.title ?? "Client") }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    // MARK: - Desk verbs

    /// Pin ⇄ unpin: membership in the desk's committed lane. Undoing an unpin
    /// restores the original pinnedAt so the lane keeps its order.
    func togglePin(_ idea: IdeaGalleryItem) {
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: idea.atomUUID) else { return }
            let wasPinned = atom.ideaMetadata?.isPinned ?? false
            let previousPinnedAt = atom.ideaMetadata?.pinnedAt
            let nowISO = ISO8601.string(from: Date())

            await applyPin(atomUUID: idea.atomUUID, pinned: !wasPinned, pinnedAt: wasPinned ? nil : nowISO)
            registerUndo(wasPinned ? "Unpin Idea" : "Pin Idea") { [weak self] in
                await self?.applyPin(atomUUID: idea.atomUUID, pinned: wasPinned, pinnedAt: previousPinnedAt)
            } redo: { [weak self] in
                await self?.applyPin(atomUUID: idea.atomUUID, pinned: !wasPinned, pinnedAt: wasPinned ? nil : nowISO)
            }
        }
    }

    private func applyPin(atomUUID: String, pinned: Bool, pinnedAt: String?) async {
        await mutateIdea(uuid: atomUUID) { atom in
            atom.withUpdatedIdeaMetadata { meta in
                meta.isPinned = pinned
                if let pinnedAt { meta.pinnedAt = pinnedAt }
            }
        }
    }

    /// Pass: not this one. Archives through the pipeline's own vocabulary —
    /// the idea leaves every board via the existing isActivated filter and
    /// stays recoverable (toast Undo now, ⌘Z after, the Archived filter
    /// forever). `quiet` skips the toast and registers ⌘Z immediately — the
    /// triage ritual's advance IS the confirmation.
    func pass(_ idea: IdeaGalleryItem, quiet: Bool = false) {
        passDismissTask?.cancel()
        if let previous = pendingPass { finalizePass(previous) }
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: idea.atomUUID) else { return }
            let record = PendingPass(
                idea: idea,
                previousStatus: atom.ideaMetadata?.ideaStatus,
                previousChangedAt: atom.ideaMetadata?.statusChangedAt
            )
            await applyStatus(atomUUID: idea.atomUUID, status: .archived, changedAt: ISO8601.string(from: Date()))
            if quiet {
                finalizePass(record)
                return
            }
            withAnimation(ProMotionSprings.snappy) { pendingPass = record }
            passDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard let self, !Task.isCancelled else { return }
                withAnimation(ProMotionSprings.gentle) {
                    self.finalizePass(record)
                    self.pendingPass = nil
                }
            }
        }
    }

    func undoPass() {
        passDismissTask?.cancel()
        passDismissTask = nil
        guard let record = pendingPass else { return }
        withAnimation(ProMotionSprings.snappy) { pendingPass = nil }
        Task {
            await applyStatus(atomUUID: record.idea.atomUUID, status: record.previousStatus, changedAt: record.previousChangedAt)
        }
    }

    /// The toast expired untouched — hand the way back to the app-level ⌘Z
    /// stack (the delete flow's contract).
    private func finalizePass(_ record: PendingPass) {
        let uuid = record.idea.atomUUID
        registerUndo("Archive Idea") { [weak self] in
            await self?.applyStatus(atomUUID: uuid, status: record.previousStatus, changedAt: record.previousChangedAt)
        } redo: { [weak self] in
            await self?.applyStatus(atomUUID: uuid, status: .archived, changedAt: ISO8601.string(from: Date()))
        }
    }

    /// Ripen from the page: spark → developing → ready without a bench visit.
    func setStatus(_ idea: IdeaGalleryItem, to status: IdeaStatus) {
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: idea.atomUUID) else { return }
            let previousStatus = atom.ideaMetadata?.ideaStatus
            let previousChangedAt = atom.ideaMetadata?.statusChangedAt
            guard previousStatus != status else { return }
            let nowISO = ISO8601.string(from: Date())

            await applyStatus(atomUUID: idea.atomUUID, status: status, changedAt: nowISO)
            registerUndo("Set Idea Status") { [weak self] in
                await self?.applyStatus(atomUUID: idea.atomUUID, status: previousStatus, changedAt: previousChangedAt)
            } redo: { [weak self] in
                await self?.applyStatus(atomUUID: idea.atomUUID, status: status, changedAt: nowISO)
            }
            withAnimation(ProMotionSprings.gentle) { toastMessage = "Marked \(status.displayName)" }
        }
    }

    /// nil status/changedAt = the field was genuinely unset before — remove
    /// the keys (a struct re-encode omits nils and the merge would keep the
    /// old value; see `removingMetadataKeys`).
    private func applyStatus(atomUUID: String, status: IdeaStatus?, changedAt: String?, reload: Bool = true) async {
        await mutateIdea(uuid: atomUUID, reload: reload) { atom in
            var updated = atom.withUpdatedIdeaMetadata { meta in
                if let status { meta.ideaStatus = status }
                if let changedAt { meta.statusChangedAt = changedAt }
            }
            var keysToRemove: [String] = []
            if status == nil { keysToRemove.append("ideaStatus") }
            if changedAt == nil { keysToRemove.append("statusChangedAt") }
            if !keysToRemove.isEmpty { updated = updated.removingMetadataKeys(keysToRemove) }
            return updated
        }
    }

    /// Assign a spark (or reassign an idea) to a client's board. `quiet`
    /// drops the toast — the ritual's advance already answers.
    func assignClient(_ idea: IdeaGalleryItem, to clientUUID: String, quiet: Bool = false) {
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: idea.atomUUID) else { return }
            let previousUUID = atom.ideaMetadata?.clientUUID
            let previousName = atom.ideaMetadata?.clientName
            guard previousUUID != clientUUID else { return }
            let name = clientProfiles.first { $0.uuid == clientUUID }?.title ?? "Client"

            await applyClient(atomUUID: idea.atomUUID, clientUUID: clientUUID, clientName: name)
            registerUndo("Assign Idea") { [weak self] in
                await self?.applyClient(atomUUID: idea.atomUUID, clientUUID: previousUUID, clientName: previousName)
            } redo: { [weak self] in
                await self?.applyClient(atomUUID: idea.atomUUID, clientUUID: clientUUID, clientName: name)
            }
            if !quiet {
                withAnimation(ProMotionSprings.gentle) { toastMessage = "Assigned to \(name)" }
            }
        }
    }

    // MARK: - Bulk verbs (the ledger's multi-select)

    /// Archive many at once: one write sweep, ONE ⌘Z registration, one toast.
    func bulkArchive(_ items: [IdeaGalleryItem]) {
        guard !items.isEmpty else { return }
        Task {
            var records: [(uuid: String, status: IdeaStatus?, changedAt: String?)] = []
            let nowISO = ISO8601.string(from: Date())
            for item in items {
                guard let atom = try? await AtomRepository.shared.fetch(uuid: item.atomUUID),
                      atom.ideaMetadata?.ideaStatus != .archived else { continue }
                records.append((item.atomUUID, atom.ideaMetadata?.ideaStatus, atom.ideaMetadata?.statusChangedAt))
                await applyStatus(atomUUID: item.atomUUID, status: .archived, changedAt: nowISO, reload: false)
            }
            await load()
            guard !records.isEmpty else { return }
            registerUndo("Archive \(records.count) Ideas") { [weak self] in
                for record in records {
                    await self?.applyStatus(atomUUID: record.uuid, status: record.status, changedAt: record.changedAt, reload: false)
                }
                await self?.load()
            } redo: { [weak self] in
                for record in records {
                    await self?.applyStatus(atomUUID: record.uuid, status: .archived, changedAt: nowISO, reload: false)
                }
                await self?.load()
            }
            withAnimation(ProMotionSprings.gentle) {
                toastMessage = records.count == 1 ? "Archived 1 idea" : "Archived \(records.count) ideas"
            }
        }
    }

    /// Assign many at once — same single-undo, single-toast contract.
    func bulkAssign(_ items: [IdeaGalleryItem], to clientUUID: String) {
        guard !items.isEmpty else { return }
        Task {
            let name = clientProfiles.first { $0.uuid == clientUUID }?.title ?? "Client"
            var records: [(uuid: String, clientUUID: String?, clientName: String?)] = []
            for item in items {
                guard let atom = try? await AtomRepository.shared.fetch(uuid: item.atomUUID),
                      atom.ideaMetadata?.clientUUID != clientUUID else { continue }
                records.append((item.atomUUID, atom.ideaMetadata?.clientUUID, atom.ideaMetadata?.clientName))
                await applyClient(atomUUID: item.atomUUID, clientUUID: clientUUID, clientName: name, reload: false)
            }
            await load()
            guard !records.isEmpty else { return }
            registerUndo("Assign \(records.count) Ideas") { [weak self] in
                for record in records {
                    await self?.applyClient(atomUUID: record.uuid, clientUUID: record.clientUUID, clientName: record.clientName, reload: false)
                }
                await self?.load()
            } redo: { [weak self] in
                for record in records {
                    await self?.applyClient(atomUUID: record.uuid, clientUUID: clientUUID, clientName: name, reload: false)
                }
                await self?.load()
            }
            withAnimation(ProMotionSprings.gentle) {
                toastMessage = records.count == 1 ? "Assigned 1 idea to \(name)" : "Assigned \(records.count) ideas to \(name)"
            }
        }
    }

    private func applyClient(atomUUID: String, clientUUID: String?, clientName: String?, reload: Bool = true) async {
        await mutateIdea(uuid: atomUUID, reload: reload) { atom in
            var updated = atom.withUpdatedIdeaMetadata { meta in
                if let clientUUID { meta.clientUUID = clientUUID }
                if let clientName { meta.clientName = clientName }
            }
            if clientUUID == nil { updated = updated.removingMetadataKeys(["clientUUID", "clientName"]) }
            updated = updated.removingLinks(ofType: .ideaToClient)
            if let clientUUID { updated = updated.addingLink(.ideaToClient(clientUUID)) }
            return updated
        }
    }

    /// Book a development session straight from the desk (the bench's
    /// schedule popover grammar, quick-day sized).
    func scheduleDevelopment(_ idea: IdeaGalleryItem, on day: Date) {
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: idea.atomUUID) else { return }
            guard let task = try? await IdeaTaskLinkService.createScheduledTask(for: atom, on: day) else {
                withAnimation(ProMotionSprings.gentle) { toastMessage = "Couldn't schedule the session" }
                return
            }
            let taskUUID = task.uuid
            // Delete/restore, NEVER delete/re-create. Re-creating on redo mints a
            // new uuid that this captured closure doesn't know about, so the next
            // undo deletes the already-dead original and leaves the new task
            // alive — one orphan per redo. The soft delete keeps the uuid stable
            // in both directions, so the pair stays symmetric forever.
            registerUndo("Schedule Development") { [weak self] in
                try? await IdeaTaskLinkService.removeScheduledTask(taskUUID: taskUUID)
                await self?.load()
            } redo: { [weak self] in
                try? await IdeaTaskLinkService.restoreScheduledTask(taskUUID: taskUUID)
                await self?.load()
            }
            withAnimation(ProMotionSprings.gentle) {
                toastMessage = "Development session · \(Self.dayLabel(day))"
            }
            await load()
        }
    }

    /// The scheduled chip's day words — Today/Tomorrow, then "Tue 28".
    static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).day())
    }

    // MARK: - Verb plumbing

    /// One write path for every desk verb: fetch fresh, transform, stamp
    /// updatedAt + localVersion (the sync contract), save, reload (bulk
    /// sweeps defer the reload to their last write).
    private func mutateIdea(uuid: String, reload: Bool = true, _ transform: (Atom) -> Atom) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
        var updated = transform(atom)
        updated.updatedAt = ISO8601.string(from: Date())
        updated.localVersion += 1
        _ = try? await AtomRepository.shared.update(updated)
        if reload { await load() }
    }

    private func registerUndo(
        _ description: String,
        undo: @escaping () async -> Void,
        redo: @escaping () async -> Void
    ) {
        CosmoUndoManager.shared.register(InlineUndoAction(
            actionDescription: description,
            undo: undo,
            redo: redo
        ))
    }

    // MARK: Deferred delete (card leaves now, atom later — undo in between)

    func deferDelete(_ idea: IdeaGalleryItem) {
        deleteCommitTask?.cancel()
        if let previous = pendingDelete {
            commitDelete(previous)
        }
        pendingRemovals.insert(idea.atomUUID)
        withAnimation(ProMotionSprings.snappy) {
            ideas.removeAll { $0.atomUUID == idea.atomUUID }
            archivedIdeas.removeAll { $0.atomUUID == idea.atomUUID }
            desk = IdeasDeskEngine.makeDesk(
                ideas: ideas,
                scheduledDays: scheduledDays,
                inspiration: Set(inspirationThumbs.keys),
                knownClientIds: Set(clientProfiles.map(\.uuid))
            )
            // Stored derivations follow the mutation (the card leaves every
            // surface at once — desk, groups, search).
            clientGroups = Self.groupByClient(items: ideas, clientProfiles: clientProfiles)
            searchCorpus = ideas + archivedIdeas
            pendingDelete = idea
        }
        deleteCommitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled else { return }
            self.commitDelete(idea)
            withAnimation(ProMotionSprings.gentle) { self.pendingDelete = nil }
        }
    }

    func undoDelete() {
        deleteCommitTask?.cancel()
        deleteCommitTask = nil
        guard let idea = pendingDelete else { return }
        pendingRemovals.remove(idea.atomUUID)
        withAnimation(ProMotionSprings.snappy) { pendingDelete = nil }
        Task { await load() }
    }

    private func commitDelete(_ idea: IdeaGalleryItem) {
        pendingRemovals.remove(idea.atomUUID)
        Task {
            try? await AtomRepository.shared.delete(uuid: idea.atomUUID)
            // Once the deferred delete commits (toast gone), ⌘Z still works —
            // the app-level stack takes over from the toast's local undo.
            await MainActor.run {
                CosmoUndoManager.shared.register(InlineUndoAction(
                    actionDescription: "Delete Idea",
                    undo: { [weak self] in
                        try? await AtomRepository.shared.restore(uuid: idea.atomUUID)
                        await self?.load()
                    },
                    redo: { [weak self] in
                        try? await AtomRepository.shared.delete(uuid: idea.atomUUID)
                        await self?.load()
                    }
                ))
            }
            NotificationCenter.default.post(
                name: Notification.Name("ideaDeleted"),
                object: nil,
                userInfo: ["uuid": idea.atomUUID]
            )
        }
    }

    // MARK: Drag grammar — a swipe dropped on an idea becomes inspiration

    /// Appends the swipe to `linkedSwipeIds` through the key-preserving
    /// metadata merge — the iPhone reads the same field for the card thumb.
    func linkSwipe(uuid swipeUUID: String, toIdea ideaUUID: String) {
        guard swipeUUID != ideaUUID else { return }
        Task {
            guard let swipe = try? await AtomRepository.shared.fetch(uuid: swipeUUID),
                  swipe.type == .research, swipe.isSwipeFileAtom else {
                withAnimation(ProMotionSprings.gentle) { toastMessage = "Drop a swipe to link inspiration" }
                return
            }
            guard let idea = try? await AtomRepository.shared.fetch(uuid: ideaUUID) else { return }

            let existing = idea.ideaMetadata?.linkedSwipeIds ?? []
            guard !existing.contains(swipeUUID) else {
                withAnimation(ProMotionSprings.gentle) { toastMessage = "Already linked to this idea" }
                return
            }

            await mutateIdea(uuid: ideaUUID) { atom in
                atom.withUpdatedIdeaMetadata { meta in
                    var ids = meta.linkedSwipeIds ?? []
                    ids.append(swipeUUID)
                    meta.linkedSwipeIds = ids
                }
            }
            withAnimation(ProMotionSprings.gentle) { toastMessage = "Swipe linked as inspiration" }
        }
    }

    // MARK: Creation (⌘N — client prefilled on a board)

    func createIdea(clientUUID: String?) {
        Task {
            var atom = Atom.new(type: .idea, title: "Untitled Idea", body: nil, metadata: nil)
            if let clientUUID {
                let clientName = clientProfiles.first { $0.uuid == clientUUID }?.title
                atom = atom.withUpdatedIdeaMetadata { meta in
                    meta.clientUUID = clientUUID
                    if let clientName { meta.clientName = clientName }
                }
                atom = atom.addingLink(.ideaToClient(clientUUID))
            }
            guard let created = try? await AtomRepository.shared.create(atom), let id = created.id else { return }
            await load()
            NotificationCenter.default.post(
                name: .enterFocusMode,
                object: nil,
                userInfo: ["type": EntityType.idea, "id": id]
            )
        }
    }
}
