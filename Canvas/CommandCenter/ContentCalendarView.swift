// Canvas/CommandCenter/ContentCalendarView.swift
// Upcoming's Content lens: the month is the planning surface. Scheduled
// posts sit on their day as client-colored chips, published posts land on
// the day they actually shipped (with real numbers once performance is
// logged), and ideas/drafts drag in from the Shelf rail to lock onto a
// day. Past days are the scoreboard; future days are the plan.
//
// Lifecycle law: the Shelf holds what still needs a decision; the calendar
// holds what's decided; ideas are seeds and are never consumed.
//
// Perf law (canvas-120fps): ALL derivation happens in ContentCalendarSnapshot
// .build — once per (data, month), off the main actor. Day cells consume
// flat arrays; nothing in a body decodes metadata.
// Successor to the retired Queue page — ContentQueueLoader lives on here.
// July 2026

import SwiftUI
import GRDB

// MARK: - Row Model (shared with the Shelf rail)

struct ContentQueueItem: Identifiable, Equatable, Sendable {
    let atom: Atom
    let scheduledAt: Date?
    let status: String
    let clientName: String?
    /// Resolved ONCE at load — never a metadata decode in a view body.
    let clientUUID: String?

    var id: String { atom.uuid }

    var isPublished: Bool { status == "published" }

    var title: String {
        atom.title?.isEmpty == false ? atom.title! : "Untitled"
    }

    var clientColor: Color {
        guard let clientUUID else { return DS.entityContent }
        return DS.clientColor(for: clientUUID)
    }
}

// MARK: - Loader

enum ContentQueueLoader {
    /// All live content atoms with their queue-facing fields decoded.
    static func load() async -> [ContentQueueItem] {
        let atoms: [Atom] = (try? await CosmoDatabase.shared.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("updated_at").desc)
                .limit(300)
                .fetchAll(db)
        }) ?? []

        var clientNames: [String: String] = [:]
        var items: [ContentQueueItem] = []
        for atom in atoms {
            let lens = atom.metadataValue(as: ContentMetadata.self)
            let pipeline = atom.metadataValue(as: ContentAtomMetadata.self)
            let scheduled = lens?.scheduledAt.flatMap { ISO8601.date(from: $0) }
            let status = lens?.status
                ?? (pipeline?.phase == .published ? "published" : "draft")

            var clientName: String?
            if let clientUUID = pipeline?.clientProfileUUID {
                if let cached = clientNames[clientUUID] {
                    clientName = cached
                } else if let client = try? await AtomRepository.shared.fetch(uuid: clientUUID) {
                    clientName = client.title
                    clientNames[clientUUID] = client.title ?? ""
                }
            }

            items.append(ContentQueueItem(
                atom: atom,
                scheduledAt: scheduled,
                status: status,
                clientName: clientName?.isEmpty == false ? clientName : nil,
                clientUUID: pipeline?.clientProfileUUID
            ))
        }
        return items
    }

    /// Key-merge write: only the queue's own keys change; every other
    /// metadata key (pipeline phase, inherited context, …) survives intact.
    static func setSchedule(_ date: Date?, status: String?, for atomUuid: String) async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUuid) else { return }
        var dict: [String: Any] = [:]
        if let metadata = atom.metadata,
           let data = metadata.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = decoded
        }
        if let date {
            dict["scheduledAt"] = ISO8601.string(from: date)
        } else {
            dict.removeValue(forKey: "scheduledAt")
        }
        if let status {
            dict["status"] = status
        }
        guard let merged = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: merged, encoding: .utf8) else { return }
        var updated = atom
        updated.metadata = json
        _ = try? await AtomRepository.shared.update(updated)
    }
}

// MARK: - Shelf Drag Session

/// In-flight drag state for shelf→calendar drags. `.onDrag` closures set it
/// so targeted day cells can ring in the dragged item's client color —
/// dropDestination's isTargeted callback carries no payload.
@MainActor
@Observable
final class ShelfDragSession {
    static let shared = ShelfDragSession()

    private(set) var activeColor: Color?

    private init() {}

    func begin(color: Color) {
        activeColor = color
    }

    func end() {
        activeColor = nil
    }
}

/// Drag payload vocabulary. Bare uuids (older drag sources) read as content.
enum ContentShelfPayload {
    case idea(String)
    case content(String)

    init(string: String) {
        if let uuid = string.removingPrefix("idea:") {
            self = .idea(uuid)
        } else if let uuid = string.removingPrefix("content:") {
            self = .content(uuid)
        } else {
            self = .content(string)
        }
    }

    var dragString: String {
        switch self {
        case .idea(let uuid): return "idea:\(uuid)"
        case .content(let uuid): return "content:\(uuid)"
        }
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

// MARK: - Calendar Actions

enum ContentCalendarActions {
    /// Dropping an idea on a day promotes it: a content draft is born
    /// carrying the idea's client, scheduled onto that day, with lineage in
    /// both directions (sourceIdeaUUID ↔ contentUUIDs). All writes key-merge.
    /// The idea itself stays on the shelf — seeds are never consumed.
    static func promoteIdea(uuid: String, to day: Date) async -> Bool {
        guard let idea = try? await AtomRepository.shared.fetch(uuid: uuid),
              idea.type == .idea else { return false }
        let ideaMeta = idea.metadataValue(as: IdeaMetadata.self)

        guard let content = try? await ContentPipelineService().createContent(
            title: idea.title?.isEmpty == false ? idea.title! : "Untitled idea",
            clientUUID: ideaMeta?.clientUUID
        ) else { return false }

        struct LineageOverlay: Encodable { var sourceIdeaUUID: String }
        let linked = content.mergingMetadataKeys(LineageOverlay(sourceIdeaUUID: idea.uuid))
        _ = try? await AtomRepository.shared.update(linked)

        await ContentQueueLoader.setSchedule(day, status: "scheduled", for: content.uuid)

        struct IdeaOverlay: Encodable { var contentUUIDs: [String] }
        var contentUUIDs = ideaMeta?.contentUUIDs ?? []
        contentUUIDs.append(content.uuid)
        let ideaUpdated = idea.mergingMetadataKeys(IdeaOverlay(contentUUIDs: contentUUIDs))
        _ = try? await AtomRepository.shared.update(ideaUpdated)
        return true
    }

    static func handleDrop(_ payloads: [String], on day: Date) async -> Bool {
        var handled = false
        for raw in payloads {
            switch ContentShelfPayload(string: raw) {
            case .idea(let uuid):
                handled = await promoteIdea(uuid: uuid, to: day) || handled
            case .content(let uuid):
                // A published item dragged to a future day becomes a planned
                // repost: scheduledAt moves, publish history stays put.
                // Dragged to today or the past, the drag IS the correction:
                // the publish records move to that day so the chip follows.
                let calendar = Calendar.current
                let targetDay = calendar.startOfDay(for: day)
                if targetDay <= calendar.startOfDay(for: Date()),
                   await ContentPublishStore.moveRecords(atomUuid: uuid, to: targetDay, calendar: calendar) {
                    await ContentQueueLoader.setSchedule(targetDay, status: nil, for: uuid)
                } else {
                    await ContentQueueLoader.setSchedule(day, status: nil, for: uuid)
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - Cadence Pulse

/// A client's posting rhythm, read from real publish records — no config.
/// Median gap between publishes projects the next "due" day; that day's
/// cell carries a faint dashed ring in the client's color. Clients with
/// fewer than four publishes stay silent (not enough rhythm to claim one).
struct ContentCadencePulse: Identifiable, Equatable, Sendable {
    let clientUUID: String
    let clientName: String
    let dueDay: Date
    let medianGapDays: Int

    var id: String { clientUUID }
    var color: Color { DS.clientColor(for: clientUUID) }
}

enum ContentCadenceEngine {
    static let minimumPublishes = 4

    /// Pure: publish dates per client → at most one pulse per client.
    /// An overdue rhythm pulses today, never in the past.
    static func pulses(
        publishDatesByClient: [String: [Date]],
        clientNames: [String: String],
        today: Date = Calendar.current.startOfDay(for: Date()),
        calendar: Calendar = .current
    ) -> [ContentCadencePulse] {
        publishDatesByClient.compactMap { clientUUID, dates in
            let days = dates
                .map { calendar.startOfDay(for: $0) }
                .sorted()
            guard days.count >= minimumPublishes, let last = days.last else { return nil }

            let gaps = zip(days.dropFirst(), days)
                .map { calendar.dateComponents([.day], from: $1, to: $0).day ?? 0 }
                .filter { $0 > 0 }
                .sorted()
            guard !gaps.isEmpty else { return nil }
            let median = gaps[gaps.count / 2]

            let projected = calendar.date(byAdding: .day, value: median, to: last) ?? last
            let dueDay = max(calendar.startOfDay(for: projected), today)
            return ContentCadencePulse(
                clientUUID: clientUUID,
                clientName: clientNames[clientUUID] ?? "This client",
                dueDay: dueDay,
                medianGapDays: median
            )
        }
        .sorted { $0.clientName < $1.clientName }
    }
}

// MARK: - Day Entry

/// One chip on the month grid.
struct ContentCalendarEntry: Identifiable, Equatable {
    let item: ContentQueueItem
    let day: Date
    let isPublished: Bool
    let platform: String?
    /// Published history replayed onto a future planned day.
    var isRepost: Bool = false
    /// Scheduled in the past and never shipped — the honest miss.
    var isMissed: Bool = false

    var id: String { "\(item.id)|\(isRepost ? "repost" : "primary")" }
}

// MARK: - Snapshot (ALL derivation lives here, off the main actor)

/// Everything the month grid renders, computed once per (data, month).
/// Pure and unit-tested; view bodies only index into it.
struct ContentCalendarSnapshot: Equatable {
    var entriesByDay: [Date: [ContentCalendarEntry]] = [:]
    var viewsByDay: [Date: Int] = [:]
    var pulsesByDay: [Date: [ContentCadencePulse]] = [:]
    var bestDay: Date?

    func entries(on day: Date) -> [ContentCalendarEntry] { entriesByDay[day] ?? [] }
    func views(on day: Date) -> Int { viewsByDay[day] ?? 0 }
    func pulses(on day: Date) -> [ContentCadencePulse] { pulsesByDay[day] ?? [] }

    var isEmpty: Bool { entriesByDay.isEmpty }

    static func build(
        items: [ContentQueueItem],
        perf: [String: ContentPerfSnapshot],
        monthDates: [Date],
        today: Date = Calendar.current.startOfDay(for: Date()),
        calendar: Calendar = .current
    ) -> ContentCalendarSnapshot {
        var snapshot = ContentCalendarSnapshot()
        let monthDaySet = Set(monthDates)

        var publishDatesByClient: [String: [Date]] = [:]
        var clientNames: [String: String] = [:]

        func append(_ entry: ContentCalendarEntry, on day: Date) {
            guard monthDaySet.contains(day) else { return }
            snapshot.entriesByDay[day, default: []].append(entry)
        }

        for item in items {
            // Publish records decode exactly once, here.
            let records = ContentPublishStore.records(for: item.atom)

            if let clientUUID = item.clientUUID, !records.isEmpty {
                publishDatesByClient[clientUUID, default: []]
                    .append(contentsOf: records.map(\.publishedAtDate))
                if let name = item.clientName { clientNames[clientUUID] = name }
            }

            if item.isPublished, let latest = records.max(by: { $0.publishedAtDate < $1.publishedAtDate }) {
                // History: the day it actually shipped. Immutable.
                let shippedDay = calendar.startOfDay(for: latest.publishedAtDate)
                append(
                    ContentCalendarEntry(item: item, day: shippedDay, isPublished: true, platform: latest.platform),
                    on: shippedDay
                )
                // Plan: a future scheduledAt on a published item is a repost.
                if let scheduled = item.scheduledAt {
                    let plannedDay = calendar.startOfDay(for: scheduled)
                    if plannedDay >= today && plannedDay != shippedDay {
                        append(
                            ContentCalendarEntry(item: item, day: plannedDay, isPublished: true, platform: latest.platform, isRepost: true),
                            on: plannedDay
                        )
                    }
                }
            } else if let scheduled = item.scheduledAt {
                let day = calendar.startOfDay(for: scheduled)
                append(
                    ContentCalendarEntry(item: item, day: day, isPublished: false, platform: nil, isMissed: day < today),
                    on: day
                )
            }
        }

        for (day, entries) in snapshot.entriesByDay {
            snapshot.entriesByDay[day] = entries.sorted {
                $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
            }
            // The scoreboard: logged views on past days, published chips only.
            if day < today {
                let views = entries
                    .filter { $0.isPublished && !$0.isRepost }
                    .compactMap { perf[$0.item.id]?.views }
                    .reduce(0, +)
                if views > 0 { snapshot.viewsByDay[day] = views }
            }
        }

        snapshot.bestDay = snapshot.viewsByDay.max { $0.value < $1.value }?.key

        // Cadence pulses land only on days without a chip already answering
        // that client's rhythm.
        let allPulses = ContentCadenceEngine.pulses(
            publishDatesByClient: publishDatesByClient,
            clientNames: clientNames,
            today: today,
            calendar: calendar
        )
        for pulse in allPulses where monthDaySet.contains(pulse.dueDay) {
            let planned = Set(snapshot.entries(on: pulse.dueDay).compactMap(\.item.clientUUID))
            if !planned.contains(pulse.clientUUID) {
                snapshot.pulsesByDay[pulse.dueDay, default: []].append(pulse)
            }
        }

        return snapshot
    }
}

// MARK: - The Calendar

extension Notification.Name {
    /// The month grid asking the Shelf rail to focus its search field
    /// (the shelf is the composer — the calendar never grows its own).
    static let contentShelfFocusSearch = Notification.Name("com.cosmo.commandCenter.contentShelfFocusSearch")
    /// Content atoms changed through calendar/shelf actions — both sides reload.
    static let contentCalendarNeedsReload = Notification.Name("com.cosmo.commandCenter.contentCalendarReload")
}

struct ContentCalendarView: View {
    var viewModel: CommandCenterDashboardViewModel

    @State private var items: [ContentQueueItem] = []
    @State private var perfByContent: [String: ContentPerfSnapshot] = [:]
    @State private var snapshot = ContentCalendarSnapshot()
    @State private var isLoading = true
    @State private var selectedDay: Date?
    @State private var perfItem: ContentQueueItem?
    @State private var datePickTarget: ContentQueueItem?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(minimum: 92), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            monthGrid
            Spacer(minLength: 0)
        }
        .task { await reload() }
        .onChange(of: viewModel.upcomingAnchorDate) { _, _ in
            selectedDay = nil
            Task { await rebuildSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contentCalendarNeedsReload)) { _ in
            Task { await reload() }
        }
        .sheet(item: $perfItem) { item in
            ContentPerfEntrySheet(atom: item.atom) {
                perfItem = nil
                Task { await reload() }
            }
        }
        .popover(item: $datePickTarget, arrowEdge: .bottom) { item in
            ContentDatePickPopover(item: item) { day in
                datePickTarget = nil
                schedule(item, on: day)
            }
        }
    }

    /// Full reload: one DB pass, then one off-main derivation pass.
    private func reload() async {
        items = await ContentQueueLoader.load()
        perfByContent = await ContentPerfStore.latestByContent()
        await rebuildSnapshot()
        isLoading = false
    }

    /// Derivation only — month stepping never re-hits the database.
    private func rebuildSnapshot() async {
        let inputItems = items
        let inputPerf = perfByContent
        let dates = monthDates
        snapshot = await Task.detached(priority: .userInitiated) {
            ContentCalendarSnapshot.build(items: inputItems, perf: inputPerf, monthDates: dates)
        }.value
    }

    // MARK: Grid

    private var monthDates: [Date] {
        CommandCenterCalendarLayout.visibleDates(
            anchor: viewModel.upcomingAnchorDate,
            scope: .month,
            calendar: calendar
        )
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                Text(day)
                    .font(DS.caption).fontWeight(.semibold)
                    .foregroundStyle(DS.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(monthDates, id: \.self) { day in
                dayCell(day)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle.opacity(0.55))
                .frame(height: 0.5)
        }
        .overlay {
            if !isLoading && snapshot.isEmpty {
                emptyMonthTeaching
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        ContentCalendarDayCell(
            day: day,
            isInDisplayedMonth: calendar.isDate(day, equalTo: viewModel.upcomingAnchorDate, toGranularity: .month),
            entries: snapshot.entries(on: day),
            pulses: snapshot.pulses(on: day),
            dayViews: snapshot.views(on: day),
            isBestDayOfMonth: snapshot.bestDay == day,
            onOpenDay: { selectedDay = day },
            onDrop: { payloads in drop(payloads, on: day) },
            onChipAction: { handleChipAction($0, entry: $1) }
        )
        .frame(minHeight: 108)
        .popover(
            isPresented: Binding(
                get: { selectedDay == day },
                set: { if !$0 { selectedDay = nil } }
            ),
            arrowEdge: .bottom
        ) {
            ContentDayLedger(
                day: day,
                entries: snapshot.entries(on: day),
                perfByContent: perfByContent,
                onOpen: { open($0) },
                onLogPerformance: { item in
                    selectedDay = nil
                    perfItem = item
                }
            )
        }
    }

    private var emptyMonthTeaching: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "calendar.badge.plus")
                .font(DS.title2.weight(.light))
                .foregroundStyle(DS.textMuted.opacity(0.6))
                .accessibilityHidden(true)
            Text("Nothing planned this month")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text("Drag an idea or draft from the shelf onto a day to lock it in.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(DS.space20)
        .frame(maxWidth: 340)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        .allowsHitTesting(false)
    }

    // MARK: Actions

    private func handleChipAction(_ action: ChipAction, entry: ContentCalendarEntry) {
        switch action {
        case .moveToday:
            schedule(entry.item, on: calendar.startOfDay(for: Date()))
        case .moveTomorrow:
            schedule(entry.item, on: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!)
        case .moveNextWeek:
            schedule(entry.item, on: calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: Date()))!)
        case .pickDate:
            datePickTarget = entry.item
        case .unschedule:
            Task {
                await ContentQueueLoader.setSchedule(nil, status: nil, for: entry.item.id)
                await notifyAndReload()
            }
        }
    }

    private func schedule(_ item: ContentQueueItem, on day: Date) {
        Task {
            await ContentQueueLoader.setSchedule(day, status: item.isPublished ? nil : "scheduled", for: item.id)
            await notifyAndReload()
        }
    }

    private func drop(_ payloads: [String], on day: Date) -> Bool {
        guard !payloads.isEmpty else { return false }
        ShelfDragSession.shared.end()
        Task {
            _ = await ContentCalendarActions.handleDrop(payloads, on: day)
            await notifyAndReload()
        }
        return true
    }

    private func notifyAndReload() async {
        await reload()
        NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
    }

    private func open(_ item: ContentQueueItem) {
        selectedDay = nil
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": item.atom.uuid]
        )
    }
}

// MARK: - Date Pick Popover

/// "Pick a date…" — the reschedule-two-months-out path, no cross-month drag.
private struct ContentDatePickPopover: View {
    let item: ContentQueueItem
    let onPick: (Date) -> Void

    @State private var day = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text(item.title)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)

            DatePicker("", selection: $day, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()

            HStack {
                Spacer()
                Button {
                    onPick(Calendar.current.startOfDay(for: day))
                } label: {
                    Text("Schedule")
                        .font(DS.subheadline).fontWeight(.semibold)
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, DS.space12)
                        .frame(height: 28)
                        .background(DS.accent, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(DS.space12)
        .frame(width: 280)
    }
}

// MARK: - Day Cell

private struct ContentCalendarDayCell: View {
    let day: Date
    let isInDisplayedMonth: Bool
    let entries: [ContentCalendarEntry]
    let pulses: [ContentCadencePulse]
    let dayViews: Int
    let isBestDayOfMonth: Bool
    let onOpenDay: () -> Void
    let onDrop: ([String]) -> Bool
    let onChipAction: (ContentCalendarView.ChipAction, ContentCalendarEntry) -> Void

    @State private var isHovered = false
    @State private var isDropTargeted = false

    private let calendar = Calendar.current

    private var isToday: Bool { calendar.isDateInToday(day) }
    private var isPast: Bool { day < calendar.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            header
            chipList
            Spacer(minLength: 0)
            footer
        }
        .padding(DS.space8)
        .background(cellBackground)
        .overlay(Rectangle().stroke(DS.borderSubtle, lineWidth: 0.5))
        .overlay(dropRing)
        .opacity(isInDisplayedMonth ? 1 : 0.42)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDay)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .dropDestination(for: String.self) { payloads, _ in
            onDrop(payloads)
        } isTargeted: { targeting in
            withAnimation(ProMotionSprings.snappy) { isDropTargeted = targeting }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var header: some View {
        HStack {
            Text("\(calendar.component(.day, from: day))")
                .font(DS.subheadline).fontWeight(isToday ? .bold : .semibold)
                .foregroundStyle(isToday ? DS.textOnAccent : (isInDisplayedMonth ? DS.text : DS.textMuted))
                .frame(width: 26, height: 22)
                .background(isToday ? DS.accent : Color.clear, in: Capsule())

            Spacer()

            if isHovered && !isPast {
                Button {
                    NotificationCenter.default.post(name: .contentShelfFocusSearch, object: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(DS.caption2).fontWeight(.bold)
                        .foregroundStyle(DS.accent)
                        .frame(width: 22, height: 22)
                        .background(DS.accentSoft.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Find something on the shelf to plan here")
                .accessibilityLabel("Plan content for this day")
            } else if isHovered && isPast {
                Button(action: onOpenDay) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(DS.caption2).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(DS.glassCardFill, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Log how this day's content performed")
                .accessibilityLabel("Log performance for this day")
            }
        }
    }

    private var chipList: some View {
        VStack(alignment: .leading, spacing: DS.space2 + 1) {
            ForEach(entries.prefix(3)) { entry in
                ContentCalendarChip(entry: entry, onAction: { onChipAction($0, entry) })
            }
            if entries.count > 3 {
                Text("+\(entries.count - 3) more")
                    .font(DS.caption2).fontWeight(.medium)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DS.space4) {
            // Cadence pulses: this client's rhythm says a post is due here.
            ForEach(pulses) { pulse in
                Circle()
                    .strokeBorder(pulse.color.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
                    .frame(width: 7, height: 7)
                    .help("\(pulse.clientName) posts about every \(pulse.medianGapDays) day\(pulse.medianGapDays == 1 ? "" : "s") — one is due here")
                    .accessibilityLabel("\(pulse.clientName)'s posting rhythm suggests a post here")
            }

            Spacer(minLength: 0)

            if dayViews > 0 {
                // The scoreboard figure — the month's best day earns gilt.
                Text(dayViews.cosmoCompactCount)
                    .font(DS.caption2.monospacedDigit()).fontWeight(.medium)
                    .foregroundStyle(isBestDayOfMonth ? DS.gilt : DS.textMuted)
                    .contentTransition(.numericText())
                    .help(isBestDayOfMonth
                        ? "\(dayViews.formatted()) logged views — the month's best day"
                        : "\(dayViews.formatted()) logged views across this day's posts")
            }
        }
    }

    private var cellBackground: Color {
        if isToday { return DS.accent.opacity(0.035) }
        return Color.clear
    }

    @ViewBuilder
    private var dropRing: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 8)
                .stroke(ShelfDragSession.shared.activeColor ?? DS.accent, lineWidth: 1.5)
                .padding(2)
        }
    }

    private var accessibilityText: String {
        let base = day.formatted(.dateTime.month().day())
        guard !entries.isEmpty else { return base }
        return "\(base), \(entries.count) post\(entries.count == 1 ? "" : "s")"
    }
}

extension ContentCalendarView {
    enum ChipAction {
        case moveToday
        case moveTomorrow
        case moveNextWeek
        case pickDate
        case unschedule
    }
}

// MARK: - Chip

private struct ContentCalendarChip: View {
    let entry: ContentCalendarEntry
    let onAction: (ContentCalendarView.ChipAction) -> Void

    var body: some View {
        HStack(spacing: DS.space4) {
            Rectangle()
                .fill(entry.item.clientColor.opacity(entry.isMissed ? 0.45 : 1))
                .frame(width: 2, height: 12)
                .clipShape(.rect(cornerRadius: 1))

            Text(entry.item.title)
                .font(DS.caption2).fontWeight(.medium)
                .foregroundStyle(chipTextColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            if entry.isRepost {
                Image(systemName: "repeat")
                    .font(DS.caption2.weight(.semibold))
                    .imageScale(.small)
                    .foregroundStyle(DS.textMuted)
                    .accessibilityLabel("Planned repost")
            } else if entry.isPublished, let platform = entry.platform {
                PlatformBrandMark(platform: platform, size: 8, color: DS.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DS.space4)
        .frame(height: 18)
        .background(entry.item.clientColor.opacity(entry.isMissed ? 0.05 : 0.09), in: .rect(cornerRadius: 4))
        .draggable(ContentShelfPayload.content(entry.item.id).dragString) {
            Text(entry.item.title)
                .font(DS.caption)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 4)
                .background(DS.surfaceElevated, in: Capsule())
        }
        .contextMenu { chipMenu }
        .help(chipHelp)
    }

    @ViewBuilder
    private var chipMenu: some View {
        if entry.isMissed {
            Button("Move to Today") { onAction(.moveToday) }
            Divider()
        } else {
            Button("Move to Today") { onAction(.moveToday) }
            Button("Move to Tomorrow") { onAction(.moveTomorrow) }
            Button("Move to Next Week") { onAction(.moveNextWeek) }
        }
        Button("Pick a Date…") { onAction(.pickDate) }
        if entry.item.scheduledAt != nil {
            Divider()
            Button(entry.isRepost ? "Cancel Repost" : "Unschedule", role: .destructive) {
                onAction(.unschedule)
            }
        }
    }

    private var chipTextColor: Color {
        if entry.isMissed { return DS.textMuted }
        return entry.isPublished && !entry.isRepost ? DS.textSecondary : DS.text
    }

    private var chipHelp: String {
        if entry.isMissed { return "Planned but never shipped — right-click to move it forward" }
        if entry.isRepost { return "Planned repost — drag to move, right-click for options" }
        if entry.isPublished { return "Published — drag onto a future day to plan a repost" }
        return "Scheduled — drag to another day, or right-click for options"
    }
}

// MARK: - Day Ledger

/// Self-loading Day Ledger for hosts outside the content calendar (the
/// schedule lens's past-day headers): fetches the day's posts itself and
/// owns the performance sheet.
struct ContentDayLedgerPanel: View {
    let day: Date

    @State private var entries: [ContentCalendarEntry] = []
    @State private var perfByContent: [String: ContentPerfSnapshot] = [:]
    @State private var perfItem: ContentQueueItem?

    var body: some View {
        ContentDayLedger(
            day: day,
            entries: entries,
            perfByContent: perfByContent,
            onOpen: { item in
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil,
                    userInfo: ["atomUUID": item.atom.uuid]
                )
            },
            onLogPerformance: { perfItem = $0 }
        )
        .task { await reload() }
        .sheet(item: $perfItem) { item in
            ContentPerfEntrySheet(atom: item.atom) {
                perfItem = nil
                Task {
                    await reload()
                    NotificationCenter.default.post(name: .contentCalendarNeedsReload, object: nil)
                }
            }
        }
    }

    private func reload() async {
        let items = await ContentQueueLoader.load()
        let perf = await ContentPerfStore.latestByContent()
        let targetDay = Calendar.current.startOfDay(for: day)
        let built = await Task.detached(priority: .userInitiated) {
            ContentCalendarSnapshot.build(items: items, perf: perf, monthDates: [targetDay])
        }.value
        entries = built.entries(on: targetDay)
        perfByContent = perf
    }
}

/// The day popover: what shipped (or is planned) that day, with the
/// performance path one click away for past days.
struct ContentDayLedger: View {
    let day: Date
    let entries: [ContentCalendarEntry]
    let perfByContent: [String: ContentPerfSnapshot]
    let onOpen: (ContentQueueItem) -> Void
    let onLogPerformance: (ContentQueueItem) -> Void

    private var isPast: Bool { day < Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(day.formatted(.dateTime.weekday(.wide).month().day()))
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)

            if entries.isEmpty {
                Text(isPast ? "Nothing was planned here." : "Nothing planned yet — drag something in from the shelf.")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            } else {
                ForEach(entries) { entry in
                    ledgerRow(entry)
                }
            }
        }
        .padding(DS.space12)
        .frame(minWidth: 260, alignment: .leading)
    }

    private func ledgerRow(_ entry: ContentCalendarEntry) -> some View {
        HStack(spacing: DS.space8) {
            Circle()
                .fill(entry.item.clientColor)
                .frame(width: 6, height: 6)

            Button {
                onOpen(entry.item)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.item.title)
                        .font(DS.caption)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    HStack(spacing: DS.space4) {
                        if let clientName = entry.item.clientName {
                            Text(clientName)
                                .font(DS.caption2)
                                .foregroundStyle(DS.textMuted)
                        }
                        if let perf = perfByContent[entry.item.id] {
                            Text("\(perf.views.formatted()) views")
                                .font(DS.caption2.monospacedDigit())
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if entry.isPublished || isPast {
                Button {
                    onLogPerformance(entry.item)
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Log performance")
                .accessibilityLabel("Log performance for \(entry.item.title)")
            }
        }
    }
}

// MARK: - Compact Count

extension Int {
    /// "982", "12.4K", "1.2M" — the calendar's scoreboard voice.
    var cosmoCompactCount: String {
        let value = Double(self)
        switch self {
        case ..<1000:
            return "\(self)"
        case ..<1_000_000:
            return String(format: value.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0fK" : "%.1fK", value / 1000)
        default:
            return String(format: "%.1fM", value / 1_000_000)
        }
    }
}
