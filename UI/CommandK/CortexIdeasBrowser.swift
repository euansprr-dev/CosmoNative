// CosmoOS/UI/CommandK/CortexIdeasBrowser.swift
// Client-grouped ideas browser with collapsible sections and auto-reload

import SwiftUI

struct CortexIdeasBrowser: View {
    @ObservedObject var viewModel: CommandKViewModel
    @State private var hasAppeared = false
    @State private var statusFilter: IdeaStatus?
    @State private var clientFilter: String? // nil = all, "__unassigned__" = unassigned only
    @State private var sortMode: IdeaSortMode = .recent
    @State private var clientProfiles: [Atom] = []
    @State private var collapsedClients: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().foregroundStyle(DS.border.opacity(0.2))
            content
        }
        .task {
            await reloadData()
            withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            Task { await reloadData() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.ideaGalleryItems.isEmpty && !hasAppeared {
            loadingState
        } else if filteredIdeas.isEmpty {
            emptyState
        } else {
            sectionedList
        }
    }

    // MARK: - Filtered & Grouped Data

    private var filteredIdeas: [IdeaGalleryItem] {
        var items = viewModel.ideaGalleryItems
        if let status = statusFilter {
            items = items.filter { $0.status == status }
        }
        if let client = clientFilter {
            if client == "__unassigned__" {
                items = items.filter { $0.clientUUID == nil }
            } else {
                items = items.filter { $0.clientUUID == client }
            }
        }
        switch sortMode {
        case .recent:
            items.sort { $0.updatedAt > $1.updatedAt }
        case .priority:
            items.sort { ($0.isPinned ? 0 : 1, $0.status.sortOrder) < ($1.isPinned ? 0 : 1, $1.status.sortOrder) }
        case .insightScore:
            items.sort { ($0.insightScore ?? 0) > ($1.insightScore ?? 0) }
        }
        return items
    }

    private var clientSections: [IdeaClientSection] {
        var grouped: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []

        for item in filteredIdeas {
            if let clientUUID = item.clientUUID {
                grouped[clientUUID, default: []].append(item)
            } else {
                unassigned.append(item)
            }
        }

        var sections: [IdeaClientSection] = []
        let sorted = clientProfiles.sorted { ($0.title ?? "") < ($1.title ?? "") }
        for client in sorted {
            let items = grouped[client.uuid] ?? []
            guard !items.isEmpty || clientFilter == nil else { continue }
            sections.append(IdeaClientSection(
                id: client.uuid,
                clientName: client.title ?? "Client",
                clientUUID: client.uuid,
                color: DS.clientColor(for: client.uuid),
                items: items
            ))
        }

        // Unassigned last
        if !unassigned.isEmpty || clientFilter == nil {
            sections.append(IdeaClientSection(
                id: "__unassigned__",
                clientName: "Unassigned",
                clientUUID: nil,
                color: DS.entityIdea,
                items: unassigned
            ))
        }

        return sections
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: DS.space8) {
            Text("\(filteredIdeas.count) ideas")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            statusFilterMenu
            clientFilterMenu
            sortFilterMenu

            if statusFilter != nil || clientFilter != nil {
                Button("Clear") {
                    statusFilter = nil
                    clientFilter = nil
                }
                .font(DS.caption)
                .foregroundStyle(DS.red)
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, DS.space16)
        .frame(height: 32)
    }

    private var statusFilterMenu: some View {
        Menu {
            Button("All Statuses") { statusFilter = nil }
            Divider()
            ForEach(IdeaStatus.allCases, id: \.self) { status in
                Button {
                    statusFilter = status
                } label: {
                    HStack {
                        Circle()
                            .fill(colorForStatus(status))
                            .frame(width: 8, height: 8)
                        Text(status.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                if let status = statusFilter {
                    Circle()
                        .fill(colorForStatus(status))
                        .frame(width: 6, height: 6)
                    Text(status.displayName).font(DS.caption)
                } else {
                    Text("Status").font(DS.caption)
                }
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(statusFilter != nil ? DS.entityIdea : DS.textSecondary)
            .commandKToolbarChip(
                isActive: statusFilter != nil,
                activeFill: DS.entityIdea.opacity(0.12),
                activeBorder: DS.entityIdea.opacity(0.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var clientFilterMenu: some View {
        Menu {
            Button("All Clients") { clientFilter = nil }
            Divider()
            ForEach(clientProfiles.sorted(by: { ($0.title ?? "") < ($1.title ?? "") }), id: \.uuid) { profile in
                Button {
                    clientFilter = profile.uuid
                } label: {
                    HStack {
                        Circle()
                            .fill(DS.clientColor(for: profile.uuid))
                            .frame(width: 8, height: 8)
                        Text(profile.title ?? "Client")
                    }
                }
            }
            Divider()
            Button {
                clientFilter = "__unassigned__"
            } label: {
                HStack {
                    Circle().fill(DS.entityIdea).frame(width: 8, height: 8)
                    Text("Unassigned")
                }
            }
        } label: {
            HStack(spacing: DS.space4) {
                if let filter = clientFilter {
                    Circle()
                        .fill(filter == "__unassigned__" ? DS.entityIdea : DS.clientColor(for: filter))
                        .frame(width: 6, height: 6)
                    Text(clientNameForFilter(filter)).font(DS.caption)
                } else {
                    Text("Client").font(DS.caption)
                }
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(clientFilter != nil ? DS.accent : DS.textSecondary)
            .commandKToolbarChip(
                isActive: clientFilter != nil,
                activeFill: DS.accentSoft,
                activeBorder: DS.accent.opacity(0.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var sortFilterMenu: some View {
        Menu {
            ForEach(IdeaSortMode.allCases, id: \.self) { mode in
                Button(mode.displayName) { sortMode = mode }
            }
        } label: {
            HStack(spacing: DS.space4) {
                Text(sortMode.displayName).font(DS.caption)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(DS.textSecondary)
            .commandKToolbarChip()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sectioned List

    private var sectionedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(clientSections.enumerated()), id: \.element.id) { sectionIndex, section in
                    clientSectionView(section, sectionIndex: sectionIndex)
                }
            }
        }
    }

    @ViewBuilder
    private func clientSectionView(_ section: IdeaClientSection, sectionIndex: Int) -> some View {
        let isCollapsed = collapsedClients.contains(section.id)

        // Header
        Button {
            withAnimation(ProMotionSprings.snappy) {
                if isCollapsed {
                    collapsedClients.remove(section.id)
                } else {
                    collapsedClients.insert(section.id)
                }
            }
        } label: {
            sectionHeader(section, isCollapsed: isCollapsed)
        }
        .buttonStyle(.plain)

        // Ideas (when expanded)
        if !isCollapsed {
            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                CortexIdeaRow(item: item) { openIdea(item) }
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 6)
                    .animation(
                        ProMotionSprings.staggered(index: sectionIndex * 10 + index),
                        value: hasAppeared
                    )
                if index < section.items.count - 1 {
                    Divider().foregroundStyle(DS.border.opacity(0.08)).padding(.leading, 36)
                }
            }
        }
    }

    private func sectionHeader(_ section: IdeaClientSection, isCollapsed: Bool) -> some View {
        HStack(spacing: DS.space8) {
            Circle()
                .fill(section.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(section.clientName)
                .font(DS.callout)
                .fontWeight(.semibold)
                .foregroundStyle(DS.text)

            Text("(\(section.items.count))")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer()

            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .accessibilityLabel(isCollapsed ? "Expand" : "Collapse")
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .background(section.color.opacity(0.04))
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: DS.space8) {
            ProgressView().scaleEffect(0.8).tint(DS.textMuted)
            Text("Loading ideas...")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 28))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text(statusFilter != nil || clientFilter != nil ? "No ideas match filters" : "No ideas yet")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    // MARK: - Data Loading

    private func reloadData() async {
        await viewModel.loadIdeaGallery(forceReload: true)
        clientProfiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
    }

    // MARK: - Helpers

    private func colorForStatus(_ status: IdeaStatus) -> Color {
        switch status {
        case .spark: return DS.green
        case .developing: return DS.orange
        case .ready: return DS.info
        case .inProduction: return DS.orange
        case .published: return DS.accent
        case .archived: return DS.textMuted
        }
    }

    private func clientNameForFilter(_ filter: String) -> String {
        if filter == "__unassigned__" { return "Unassigned" }
        return clientProfiles.first(where: { $0.uuid == filter })?.title ?? "Client"
    }

    private func openIdea(_ item: IdeaGalleryItem) {
        Task { try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.atomUUID, type: .view) }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil, userInfo: ["atomUUID": item.atomUUID]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }
}

// MARK: - Idea Row

private struct CortexIdeaRow: View {
    let item: IdeaGalleryItem
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.space10) {
                statusDot
                titleColumn
                Spacer()
                metadataColumn
            }
            .padding(.horizontal, DS.space16)
            .padding(.leading, DS.space20) // indent under section header
            .padding(.vertical, DS.space8)
            .background(isHovered ? DS.glassCardFill.opacity(0.5) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(item.title)
        .commandKCardContextMenu(
            atomUUID: item.atomUUID,
            entityId: item.entityId,
            atomType: .idea,
            onDelete: {
                Task {
                    try? await AtomRepository.shared.delete(uuid: item.atomUUID)
                    NotificationCenter.default.post(
                        name: Notification.Name("ideaDeleted"),
                        object: nil,
                        userInfo: ["uuid": item.atomUUID]
                    )
                }
            }
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.space4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.orange)
                        .accessibilityLabel("Pinned")
                }
                Text(item.title)
                    .font(DS.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }

            HStack(spacing: DS.space4) {
                Text(item.status.displayName)
                    .font(DS.caption2)
                    .foregroundStyle(statusColor)
                if let format = item.contentFormat {
                    Text("·").font(DS.caption2).foregroundStyle(DS.textMuted)
                    Text(format.displayName).font(DS.caption2).foregroundStyle(DS.textMuted)
                }
                if let score = item.insightScore, score > 0 {
                    Text("·").font(DS.caption2).foregroundStyle(DS.textMuted)
                    Text(String(format: "%.0f%%", score * 100))
                        .font(DS.caption2)
                        .foregroundStyle(DS.accent)
                }
            }
        }
    }

    private var metadataColumn: some View {
        Text(relativeTime)
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
    }

    private var statusColor: Color {
        switch item.status {
        case .spark: return DS.green
        case .developing: return DS.orange
        case .ready: return DS.info
        case .inProduction: return DS.orange
        case .published: return DS.accent
        case .archived: return DS.textMuted
        }
    }

    private var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: item.updatedAt) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(max(1, Int(interval / 60)))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }
}

// IdeaStatus.sortOrder and IdeaSortMode.displayName are defined in IdeasTab.swift
