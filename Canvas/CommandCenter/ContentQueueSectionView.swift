// CosmoOS/Canvas/CommandCenter/ContentQueueSectionView.swift
// The Queue — a Command Center planning page for shipping content: what's
// scheduled (next two weeks, by day), what's drafted but unscheduled, and
// what's published (with real performance numbers when they've been
// recorded). Rows schedule/unschedule via key-merge metadata writes, open
// the export composer, and record performance snapshots.
// July 2026

import SwiftUI
import GRDB

// MARK: - Row Model

struct ContentQueueItem: Identifiable, Equatable {
    let atom: Atom
    let scheduledAt: Date?
    let status: String
    let clientName: String?

    var id: String { atom.uuid }

    var isPublished: Bool { status == "published" }

    var title: String {
        atom.title?.isEmpty == false ? atom.title! : "Untitled"
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
                clientName: clientName?.isEmpty == false ? clientName : nil
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

// MARK: - Page

struct ContentQueueSectionView: View {
    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    @State private var items: [ContentQueueItem] = []
    @State private var perfByContent: [String: ContentPerfSnapshot] = [:]
    @State private var isLoading = true
    @State private var exportItem: ContentQueueItem?
    @State private var perfItem: ContentQueueItem?

    var body: some View {
        CommandCenterPlanningPageScaffold(
            title: "Queue",
            icon: "paperplane",
            subtitle: subtitle,
            accent: DS.entityContent,
            actions: { EmptyView() },
            content: { content }
        )
        .task { await reload() }
        .sheet(item: $exportItem) { item in
            ContentExportSheet(
                atom: item.atom,
                draft: item.atom.body ?? "",
                onClose: { exportItem = nil }
            )
        }
        .sheet(item: $perfItem) { item in
            ContentPerfEntrySheet(atom: item.atom) {
                perfItem = nil
                Task { await reload() }
            }
        }
    }

    private var subtitle: String {
        let scheduled = items.filter { $0.scheduledAt != nil && !$0.isPublished }.count
        let dueToday = items.filter {
            guard let date = $0.scheduledAt, !$0.isPublished else { return false }
            return Calendar.current.isDateInToday(date)
        }.count
        if dueToday > 0 { return "\(dueToday) due today · \(scheduled) scheduled" }
        return scheduled == 1 ? "1 scheduled post" : "\(scheduled) scheduled posts"
    }

    private func reload() async {
        items = await ContentQueueLoader.load()
        perfByContent = await ContentPerfStore.latestByContent()
        isLoading = false
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DS.space20) {
                if isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.space24)
                } else if items.isEmpty {
                    emptyState
                } else {
                    scheduledGroups
                    unscheduledTray
                    publishedShelf
                }
            }
            .padding(.bottom, DS.space48)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "paperplane")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DS.textMuted.opacity(0.5))
                .accessibilityHidden(true)
            Text("Nothing in the queue")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text("Drafts appear here the moment a content page exists — schedule them, export them, and record how they performed.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.space48)
    }

    // MARK: - Scheduled

    private var scheduledUpcoming: [(day: Date, items: [ContentQueueItem])] {
        let calendar = Calendar.current
        let upcoming = items.filter { item in
            guard let date = item.scheduledAt, !item.isPublished else { return false }
            return date >= calendar.startOfDay(for: Date())
        }
        let grouped = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.scheduledAt!) }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]!.sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) })
        }
    }

    @ViewBuilder
    private var scheduledGroups: some View {
        if !scheduledUpcoming.isEmpty {
            VStack(alignment: .leading, spacing: DS.space10) {
                sectionLabel("SCHEDULED")
                ForEach(scheduledUpcoming, id: \.day) { group in
                    VStack(alignment: .leading, spacing: DS.space6) {
                        Text(dayLabel(group.day))
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(DS.textSecondary)
                        ForEach(group.items) { item in
                            queueRow(item)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Unscheduled + Published

    private var drafts: [ContentQueueItem] {
        items.filter { $0.scheduledAt == nil && !$0.isPublished }
    }

    private var published: [ContentQueueItem] {
        items.filter(\.isPublished)
    }

    @ViewBuilder
    private var unscheduledTray: some View {
        if !drafts.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                sectionLabel("DRAFTS")
                ForEach(drafts.prefix(20)) { item in
                    queueRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private var publishedShelf: some View {
        if !published.isEmpty {
            VStack(alignment: .leading, spacing: DS.space6) {
                sectionLabel("PUBLISHED")
                ForEach(published.prefix(20)) { item in
                    queueRow(item)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.smallCaps)
            .tracking(1.4)
            .foregroundStyle(DS.textMuted)
    }

    // MARK: - Row

    private func queueRow(_ item: ContentQueueItem) -> some View {
        HStack(spacing: DS.space10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(clientColor(item))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                HStack(spacing: DS.space6) {
                    if let clientName = item.clientName {
                        Text(clientName)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                    if item.isPublished, let perf = perfByContent[item.atom.uuid] {
                        Text("\(perf.views.formatted()) views · \(perf.engagement.formatted()) engagement")
                            .font(DS.caption2.monospacedDigit())
                            .foregroundStyle(DS.textSecondary)
                    } else if item.isPublished {
                        Text("No numbers yet — record performance")
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            rowActions(item)
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture { openItem(item) }
    }

    private func rowActions(_ item: ContentQueueItem) -> some View {
        HStack(spacing: DS.space6) {
            scheduleMenu(item)
            Button {
                exportItem = item
            } label: {
                Image(systemName: "paperplane")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Export")
            .accessibilityLabel("Export \(item.title)")

            Button {
                perfItem = item
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Record performance")
            .accessibilityLabel("Record performance for \(item.title)")
        }
    }

    private func scheduleMenu(_ item: ContentQueueItem) -> some View {
        Menu {
            Button("Today") { schedule(item, daysAhead: 0) }
            Button("Tomorrow") { schedule(item, daysAhead: 1) }
            Button("In 3 days") { schedule(item, daysAhead: 3) }
            Button("Next week") { schedule(item, daysAhead: 7) }
            Divider()
            if !item.isPublished {
                Menu("Mark Published on…") {
                    ForEach(SocialPlatform.allCases, id: \.self) { platform in
                        Button(platform.displayName) {
                            Task {
                                // Publish record (platform + time) — feeds client
                                // aggregates and the Margin's own-post pool.
                                await ContentPublishStore.markPublished(
                                    atomUuid: item.atom.uuid,
                                    platform: platform.rawValue
                                )
                                await reload()
                            }
                        }
                    }
                }
            }
            if item.scheduledAt != nil {
                Button("Unschedule", role: .destructive) {
                    Task {
                        await ContentQueueLoader.setSchedule(nil, status: nil, for: item.atom.uuid)
                        await reload()
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(DS.caption)
                if let date = item.scheduledAt {
                    Text(shortDate(date))
                        .font(DS.caption2)
                }
            }
            .foregroundStyle(item.scheduledAt != nil ? DS.text : DS.textSecondary)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Schedule")
    }

    // MARK: - Actions & Formatting

    private func schedule(_ item: ContentQueueItem, daysAhead: Int) {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: Date()))!
        Task {
            await ContentQueueLoader.setSchedule(target, status: item.isPublished ? nil : "scheduled", for: item.atom.uuid)
            await reload()
        }
    }

    private func openItem(_ item: ContentQueueItem) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": item.atom.uuid]
        )
    }

    private func clientColor(_ item: ContentQueueItem) -> Color {
        guard let clientUUID = item.atom.metadataValue(as: ContentAtomMetadata.self)?.clientProfileUUID else {
            return DS.entityContent
        }
        return DS.clientColor(for: clientUUID)
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tmrw" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
