// CosmoOS/UI/Pipeline/PipelinePageModel.swift
// The Pipeline's one model: a scope (all / a client / unassigned / a space),
// a view (board / calendar / list), filters, and the verbs. Content is never
// filed — it appears by client, stage and date; every verb is a state write
// (fetch-fresh, key-merged, one ⌘Z) followed by a reload. Derived collections
// are STORED and rebuilt in load() (the Ideas perf law); the board snapshot
// is built off the main actor from plain values.

import SwiftUI
import GRDB

@MainActor
@Observable
final class PipelinePageModel {

    // MARK: State

    var scope: PipelineScope {
        didSet { if scope != oldValue, observation != nil { Task { await load() } } }
    }
    var view: PipelineView = .board
    var filters = PipelineFilters() {
        didSet { if filters != oldValue { Task { await rebuildSnapshot() } } }
    }
    /// Collapsed board columns, persisted. The backlog starts collapsed:
    /// the board reads short, the count stays visible, nothing is lost.
    var collapsedColumns: Set<PipelineBoardSnapshot.Column> = PipelinePageModel.storedCollapsedColumns() {
        didSet { Self.storeCollapsedColumns(collapsedColumns) }
    }

    private(set) var content: [PipelineContentItem] = []
    private(set) var archived: [PipelineContentItem] = []
    private(set) var clients: [PipelineClient] = []
    private(set) var snapshot = PipelineBoardSnapshot.empty
    private(set) var listRows: [PipelineContentItem] = []
    private(set) var sessionDaysByContent: [String: Date] = [:]
    private(set) var perfByContent: [String: ContentPerfSnapshot] = [:]
    private(set) var isLoaded = false

    var toastMessage: String?
    var errorMessage: String?
    private(set) var creatingDraft = false
    var showsArchivedIdeas = false
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let refresh = CoalescingRefresh()
    @ObservationIgnored private var snapshotGeneration = 0
    /// The card awaiting a date (Scheduled-column drop, "Schedule…").
    var pendingSchedule: PipelineContentItem?
    /// The piece awaiting the Export panel (Export…, ⌘E). Publishing never
    /// routes here: a piece dropped on Published was shipped elsewhere.
    var pendingExport: Atom?
    var pendingPerf: Atom?
    var quickLookID: String?

    /// In-motion count for the sidebar badge and the masthead line.
    var inMotionCount: Int { content.filter { !$0.isShipped && $0.productionStage != .notStarted }.count }
    var publishingThisWeekCount: Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return content.filter { item in
            guard let day = item.scheduledAt else { return false }
            return interval.contains(day) && !item.isShipped
        }.count
    }

    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var hasPrewarmed = false
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    init(scope: PipelineScope = .all) {
        self.scope = scope
    }

    // MARK: Lifecycle

    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleGeneration = 0

    func start(scope: PipelineScope? = nil) async {
        if let scope, scope != self.scope { self.scope = scope }
        if let startupTask { await startupTask.value; return }
        guard observation == nil else { return }
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        startObserving()
        let startup = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.load()
        }
        startupTask = startup
        await startup.value
        if generation == lifecycleGeneration { startupTask = nil }
    }

    func prewarmIfNeeded() async {
        guard !hasPrewarmed else { return }
        hasPrewarmed = true
        await load()
    }

    func stop() {
        lifecycleGeneration += 1
        startupTask?.cancel()
        startupTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        observation?.cancel()
        observation = nil
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens.removeAll()
    }

    /// Any content/idea/task/client write re-queries — local verbs, sync
    /// applies, drops elsewhere. The calendar's reload notification rides too.
    private func startObserving() {
        if observation == nil, let db = CosmoDatabase.shared.dbPool {
            var isInitialValue = true
            let tracked = ValueObservation
                .tracking { db in
                    try String.fetchOne(
                        db,
                        sql: "SELECT (SELECT COUNT(*) || ':' || COALESCE(SUM(_local_version), 0) || ':' || COALESCE(MAX(updated_at), '') FROM atoms WHERE type IN ('content', 'idea', 'task', 'client_profile')) || ':' || (SELECT COUNT(*) || ':' || COALESCE(SUM(_local_version), 0) || ':' || COALESCE(MAX(updated_at), '') FROM canvas_blocks)"
                    ) ?? ""
                }
                .removeDuplicates()
            observation = tracked.start(in: db, onError: { _ in }) { [weak self] _ in
                if isInitialValue { isInitialValue = false; return }
                Task { @MainActor in self?.scheduleReload() }
            }
        }
        if notificationTokens.isEmpty {
            let token = NotificationCenter.default.addObserver(
                forName: .contentCalendarNeedsReload,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleReload() }
            }
            notificationTokens.append(token)
        }
    }

    /// Coalesce bursts (a sync batch, a bulk verb) into one reload.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    // MARK: Loading

    #if DEBUG
    /// Counts actual loads, so tab-lifecycle regressions are measurable in tests.
    @ObservationIgnored private(set) var loadInvocationCount = 0
    #endif

    func load() async {
        await refresh.run { [weak self] in await self?.loadSnapshot() }
    }

    private func loadSnapshot() async {
        let interval = AppPerformanceInstrumentation.begin("content-pipeline-refresh")
        defer { AppPerformanceInstrumentation.end("content-pipeline-refresh", interval) }
        #if DEBUG
        loadInvocationCount += 1
        #endif
        loadGeneration += 1
        let generation = loadGeneration
        let scope = self.scope
        do {
        async let workspaceLoad = ContentPipelineLoader.loadWorkspace(scope: scope)
        async let tasksLoad = Self.loadOpenTasks()
        async let perfLoad = ContentPerfStore.latestByContent()
        let (workspace, tasks, perf) = try await (workspaceLoad, tasksLoad, perfLoad)
        let contentDays = IdeaTaskLinkService.openSessionDaysByContent(in: tasks)

        guard scope == self.scope, generation == loadGeneration, !Task.isCancelled else { return }
        errorMessage = nil
        content = workspace.content
        archived = workspace.archived
        clients = workspace.clients
        sessionDaysByContent = contentDays
        perfByContent = perf
        await rebuildSnapshot()
        isLoaded = true
        } catch {
            guard scope == self.scope, generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = "Couldn't load this content. Try again."
        }
    }

    /// Filters / grouping only — no database.
    func rebuildSnapshot() async {
        snapshotGeneration += 1
        let generation = snapshotGeneration
        let content = self.content
        let archived = self.archived
        let contentDays = sessionDaysByContent
        let perf = perfByContent
        let filters = self.filters
        let built = await Task.detached(priority: .userInitiated) {
            let snapshot = PipelineBoardSnapshot.build(
                content: content,
                sessionDaysByContent: contentDays,
                perf: perf,
                filters: filters
            )
            return (snapshot, Self.listRows(content: content, archived: archived, filters: filters))
        }.value
        guard generation == snapshotGeneration else { return }
        withAnimation(ProMotionSprings.gentle) {
            snapshot = built.0
            listRows = built.1
        }
    }

    private static func loadOpenTasks() async -> [Atom] {
        ((try? await AtomRepository.shared.fetchAll(type: .task)) ?? [])
            .filter { IdeaTaskLinkService.isOpenSession($0) }
    }

    nonisolated private static func listRows(
        content: [PipelineContentItem],
        archived: [PipelineContentItem],
        filters: PipelineFilters
    ) -> [PipelineContentItem] {
        let pool = filters.showArchived ? archived : content
        return pool.filter { item in
            filters.matches(title: item.atom.title ?? "", clientName: item.clientName,
                            platform: item.platform, format: item.format.flatMap(ContentFormat.init(rawValue:)))
        }
    }

    /// A new piece is a deliberate act, so it carries an explicit stage:
    /// the column it was born in, or In progress from the page-level verb.
    func createDraft(stage: ContentProductionStage = .inProgress) {
        guard !creatingDraft else { return }
        creatingDraft = true
        let capturedScope = scope
        Task {
            defer { creatingDraft = false }
            do {
                var prepared = Atom.new(type: .content, title: "Untitled", body: "")
                prepared.metadata = ContentAtomMetadata(phase: stage == .notStarted ? .ideation : .draft, clientProfileUUID: capturedScope.clientUUID,
                    wordCount: 0, createdPhaseAt: Date()).toJSON()
                prepared = prepared.mergingMetadataKeys(["productionStage": stage.rawValue])
                if let client = capturedScope.clientUUID {
                    prepared = prepared.addingLink(.contentToClient(client))
                }
                let saved: Atom
                if case .space(let id) = capturedScope {
                    saved = try await SpaceMembershipService.create(prepared, in: id)
                } else {
                    saved = try await AtomRepository.shared.create(prepared)
                    CosmoUndoManager.shared.register(InlineUndoAction(actionDescription: "Create draft",
                        undo: { try? await AtomRepository.shared.delete(uuid: saved.uuid) },
                        redo: { try? await AtomRepository.shared.restore(uuid: saved.uuid) }))
                }
                NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
                if let id = saved.id {
                    NotificationCenter.default.post(name: .enterFocusMode, object: nil,
                        userInfo: ["type": EntityType.content, "id": id])
                }
                await load()
            } catch { toast("Couldn't create a draft. Try again.") }
        }
    }

    // MARK: Lookups

    func item(_ uuid: String) -> PipelineContentItem? {
        content.first { $0.id == uuid } ?? archived.first { $0.id == uuid }
    }

    func client(_ uuid: String?) -> PipelineClient? {
        guard let uuid else { return nil }
        return clients.first { $0.uuid == uuid }
    }

    // MARK: Verbs (each = one state write + one ⌘Z + one reload)

    /// Every stage is a column. Collapse is the user's call, never a heuristic.
    var visibleColumns: [PipelineBoardSnapshot.Column] { PipelineBoardSnapshot.Column.allCases }

    func isCollapsed(_ column: PipelineBoardSnapshot.Column) -> Bool { collapsedColumns.contains(column) }

    func toggleCollapsed(_ column: PipelineBoardSnapshot.Column) {
        if collapsedColumns.contains(column) { collapsedColumns.remove(column) } else { collapsedColumns.insert(column) }
    }

    private static let collapsedColumnsKey = "pipeline.collapsedColumns"

    static func storedCollapsedColumns() -> Set<PipelineBoardSnapshot.Column> {
        guard let raw = UserDefaults.standard.array(forKey: collapsedColumnsKey) as? [String] else {
            return PipelineBoardSnapshot.Column.collapsedByDefault
        }
        return Set(raw.compactMap(PipelineBoardSnapshot.Column.init(rawValue:)))
    }

    private static func storeCollapsedColumns(_ columns: Set<PipelineBoardSnapshot.Column>) {
        UserDefaults.standard.set(columns.map(\.rawValue).sorted(), forKey: collapsedColumnsKey)
    }

    func move(_ uuid: String, to stage: ContentProductionStage) {
        guard let item = item(uuid), item.productionStage != stage || item.phase == .archived else { return }
        if stage == .published { publish([uuid]); return }
        Task {
            do {
                guard let fresh = try await AtomRepository.shared.fetch(uuid: uuid) else { return }
                let changed = try await ContentPipelineService.applyProductionStage(contentUUID: uuid, to: stage)
                let keys = ["productionStage", "phase", "status", "phaseBeforeSchedule"]
                let before = ContentMetadataSnapshot(atom: fresh, keys: keys)
                let after = ContentMetadataSnapshot(atom: changed, keys: keys)
                CosmoUndoManager.shared.register(InlineUndoAction(
                    actionDescription: "Move to \(stage.title)",
                    undo: { _ = await before.restore() }, redo: { _ = await after.restore() }
                ))
                toast("Moved to \(stage.title)")
            } catch { toast("Couldn't move the piece — \(error.localizedDescription)") }
            await load()
        }
    }

    /// Landing on Published records the ship: a per-platform publish record
    /// dated today (the piece's own platform, else "other") that the calendar,
    /// the client aggregates and the Published column all read. Nothing to
    /// export — the piece already went out. One ⌘Z for the whole batch.
    func publish(_ uuids: [String]) {
        let targets = uuids.compactMap { item($0) }.filter { !$0.isShipped }
        guard !targets.isEmpty else { return }
        Task {
            let keys = ["productionStage", "phase", "status", "phaseBeforeSchedule", "publishRecords"]
            var before: [ContentMetadataSnapshot] = []
            var after: [ContentMetadataSnapshot] = []
            for target in targets {
                guard let fresh = try? await AtomRepository.shared.fetch(uuid: target.id) else { continue }
                before.append(ContentMetadataSnapshot(atom: fresh, keys: keys))
                await ContentPublishStore.markPublished(atomUuid: target.id, platform: (target.platform ?? .other).rawValue)
                if let updated = try? await AtomRepository.shared.fetch(uuid: target.id) {
                    after.append(ContentMetadataSnapshot(atom: updated, keys: keys))
                }
            }
            let undo = before, redo = after
            if !undo.isEmpty {
                CosmoUndoManager.shared.register(InlineUndoAction(
                    actionDescription: undo.count == 1 ? "Publish" : "Publish \(undo.count) pieces",
                    undo: { for snapshot in undo { _ = await snapshot.restore() } },
                    redo: { for snapshot in redo { _ = await snapshot.restore() } }
                ))
            }
            toast(targets.count == 1 ? "Published · \(targets[0].title)" : "Published \(targets.count) pieces")
            NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
            await load()
        }
    }

    func schedule(_ uuid: String, on day: Date?) {
        Task {
            guard await ContentQueueLoader.setSchedule(day, status: nil, for: uuid) else {
                toast("Couldn’t save the publication date. Try again."); return
            }
            if let day {
                toast("Planned publication · \(Self.dayLabel(day))")
            } else {
                toast("Publication date removed")
            }
            NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
            await load()
        }
    }

    func assignClient(_ uuid: String, to clientUUID: String?) { bulkAssign([uuid], to: clientUUID) }

    func archive(_ uuids: [String]) {
        guard !uuids.isEmpty else { return }
        Task {
            var undone: [(String, ContentPhase)] = []
            var failures = 0
            for uuid in uuids {
                do {
                    guard let atom = try await AtomRepository.shared.fetch(uuid: uuid),
                          let phase = ContentPipelineService.currentPhase(of: atom), phase != .archived else { continue }
                    _ = try await ContentPipelineService.applyPhase(contentUUID: uuid, to: .archived, notes: nil)
                    undone.append((uuid, phase))
                } catch { failures += 1 }
            }
            let restore = undone
            if !restore.isEmpty { CosmoUndoManager.shared.register(InlineUndoAction(
                actionDescription: restore.count == 1 ? "Archive" : "Archive \(restore.count) pieces",
                undo: { [weak self] in
                    for (uuid, phase) in restore {
                        _ = try? await ContentPipelineService.applyPhase(contentUUID: uuid, to: phase, notes: nil)
                    }
                    await self?.load()
                },
                redo: { [weak self] in
                    for (uuid, _) in restore {
                        _ = try? await ContentPipelineService.applyPhase(contentUUID: uuid, to: .archived, notes: nil)
                    }
                    await self?.load()
                }
            )) }
            toast(failures > 0 ? "Archived \(restore.count) · \(failures) couldn't be saved. Try again."
                  : (restore.count == 1 ? "Archived" : "Archived \(restore.count) pieces"))
            NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
            await load()
        }
    }

    func restore(_ uuid: String) {
        Task {
            do {
                guard let atom = try await AtomRepository.shared.fetch(uuid: uuid) else { return }
                let prior = (atom.metadataDict?["phaseBeforeArchive"] as? String).flatMap(ContentPhase.init(rawValue:))
                let phase = prior == .archived ? .draft : (prior ?? (ContentProductionStage.of(atom) == .published ? .published : .draft))
                _ = try await ContentPipelineService().setPhase(contentUUID: uuid, to: phase, notes: "Restored from archive")
                toast("Restored to Content")
                await load()
            } catch { toast("Couldn't restore the piece. Try again.") }
        }
    }

    func bulkMove(_ uuids: [String], to stage: ContentProductionStage) {
        guard !uuids.isEmpty else { return }
        if stage == .published { publish(uuids); return }
        Task {
            var before: [ContentMetadataSnapshot] = []
            var after: [ContentMetadataSnapshot] = []
            let keys = ["productionStage", "phase", "status", "phaseBeforeSchedule"]
            do {
                for uuid in uuids {
                    guard let fresh = try await AtomRepository.shared.fetch(uuid: uuid) else { continue }
                    let updated = try await ContentPipelineService.applyProductionStage(contentUUID: uuid, to: stage)
                    before.append(ContentMetadataSnapshot(atom: fresh, keys: keys))
                    after.append(ContentMetadataSnapshot(atom: updated, keys: keys))
                }
            } catch { toast("Some pieces couldn't be moved — \(error.localizedDescription)") }
            let undo = before, redo = after
            if !undo.isEmpty {
                CosmoUndoManager.shared.register(InlineUndoAction(
                    actionDescription: "Move \(undo.count) pieces",
                    undo: { for snapshot in undo { _ = await snapshot.restore() } },
                    redo: { for snapshot in redo { _ = await snapshot.restore() } }
                ))
            }
            await load()
        }
    }

    func bulkAssign(_ uuids: [String], to clientUUID: String?) {
        guard !uuids.isEmpty else { return }
        Task {
            var previous: [(String, String?)] = []
            var failures = 0
            for uuid in uuids {
                do {
                    let change = try await ContentPipelineService.assignClient(contentUUID: uuid, to: clientUUID)
                    previous.append((uuid, change.before.metadataDict?["clientProfileUUID"] as? String))
                } catch { failures += 1 }
            }
            let committed = previous
            if !committed.isEmpty {
                CosmoUndoManager.shared.register(InlineUndoAction(
                    actionDescription: "Assign client",
                    undo: { for (uuid, client) in committed { _ = try? await ContentPipelineService.assignClient(contentUUID: uuid, to: client) } },
                    redo: { for (uuid, _) in committed { _ = try? await ContentPipelineService.assignClient(contentUUID: uuid, to: clientUUID) } }
                ))
            }
            toast(failures == 0 ? "Updated client for \(committed.count) piece\(committed.count == 1 ? "" : "s")" : "\(failures) pieces couldn't be assigned. Try again.")
            await load()
        }
    }


    /// Drag an idea into a stage column: the full Begin Writing promotion
    /// (hooks, swipes, concepts inherited), landing in that stage.
    /// Book a writing session for a piece — an ordinary task on the Upcoming
    /// board, linked to the content (the idea grammar, content flavour).
    func bookSession(_ uuid: String, on day: Date) {
        Task {
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
            guard let task = try? await IdeaTaskLinkService.createScheduledTask(for: atom, on: day) else {
                toast("Couldn't book the session")
                return
            }
            let taskUUID = task.uuid
            CosmoUndoManager.shared.register(InlineUndoAction(
                actionDescription: "Book Session",
                undo: { [weak self] in
                    try? await IdeaTaskLinkService.removeScheduledTask(taskUUID: taskUUID)
                    await self?.load()
                },
                redo: { [weak self] in
                    try? await IdeaTaskLinkService.restoreScheduledTask(taskUUID: taskUUID)
                    await self?.load()
                }
            ))
            toast("Session · \(Self.dayLabel(day))")
            await load()
        }
    }

    // MARK: Drops

    /// A drop on a column is a stage write. Bare uuids are refused (three
    /// vocabularies share the String channel); only content payloads route —
    /// ideas enter the board through Begin writing, never by drop.
    @discardableResult
    func handleDrop(_ payloads: [String], on column: PipelineBoardSnapshot.Column) -> Bool {
        let uuids = PipelineDropPayload.all(in: payloads).compactMap { payload -> String? in
            guard case .content(let uuid) = payload, item(uuid) != nil else { return nil }
            return uuid
        }
        guard !uuids.isEmpty else { return false }
        // Dropping on Published IS publishing — the piece went out elsewhere
        // and the board only records it. Export stays a deliberate act (⌘E).
        if column == .shipped { publish(uuids) }
        else if uuids.count == 1 { move(uuids[0], to: column.stage) }
        else { bulkMove(uuids, to: column.stage) }
        return true
    }

    // MARK: Opening

    func open(_ item: PipelineContentItem) {
        guard let id = item.atom.id, id > 0 else { return }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.content, "id": id]
        )
    }

    func openAsPane(_ item: PipelineContentItem) {
        guard let id = item.atom.id, id > 0 else { return }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openAsPane,
            object: nil,
            userInfo: ["type": EntityType.content, "id": id]
        )
    }

    func openIdea(_ idea: IdeaGalleryItem) {
        guard idea.entityId > 0 else { return }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.idea, "id": idea.entityId]
        )
    }

    // MARK: Plumbing

    private func toast(_ message: String) {
        withAnimation(ProMotionSprings.gentle) { toastMessage = message }
    }

    /// Today/Tomorrow, then "Tue 28" — the calendar chips' own day words.
    static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).day())
    }
}
