// CosmoOS/UI/CommandK/CortexIdeasBrowser.swift
// "The Ledger" — a manuscript-style, typographic view of ideas grouped by client.
// Uses AtelierPrimitives to keep the aesthetic in lockstep with Idea Focus Mode.

import SwiftUI

struct CortexIdeasBrowser: View {
    @ObservedObject var viewModel: CommandKViewModel
    @State private var hasAppeared = false
    @State private var clientProfiles: [Atom] = []
    @State private var captureDraft = ""
    @FocusState private var captureFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                captureRow
                ledger
            }
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space20)
        }
        .task {
            await reload()
            withAnimation(.easeOut(duration: 0.55)) { hasAppeared = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            Task { await reload() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text(subtitle)
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkFaded)
                .frame(maxWidth: .infinity, alignment: .leading)
            hairRule
        }
        .padding(.bottom, DS.space16)
    }

    private var subtitle: String {
        let ideas = visibleIdeas.count
        guard ideas > 0 else { return "the ledger awaits" }
        let clients = clientSections.count
        let ready = visibleIdeas.filter { $0.status == .ready }.count
        let clientLabel = "\(clients) client\(clients == 1 ? "" : "s")"
        let ideaLabel = "\(ideas) idea\(ideas == 1 ? "" : "s")"
        return "\(ideaLabel) · \(clientLabel) · \(ready) ready"
    }

    // MARK: - Capture

    private var captureRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.space12) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DS.gilt.opacity(captureFocused ? 0.9 : 0.5))
                    .frame(width: 14)
                    .accessibilityHidden(true)
                TextField("what's on your mind?", text: $captureDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .italic(captureDraft.isEmpty)
                    .foregroundStyle(DS.text)
                    .focused($captureFocused)
                    .onSubmit(submitCapture)
                    .accessibilityLabel("Capture new idea")
                if captureFocused && !captureDraft.isEmpty {
                    Text("↵ save")
                        .font(DS.smallCaps)
                        .tracking(1.2)
                        .foregroundStyle(DS.giltMuted)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, DS.space12)
            .frame(minHeight: 44)
            .animation(ProMotionSprings.hover, value: captureFocused)
            hairRule
        }
        .padding(.bottom, DS.space20)
    }

    private func submitCapture() {
        let title = captureDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        captureDraft = ""
        captureFocused = false
        Task { await viewModel.createIdeaForClient(title: title, clientUUID: nil) }
    }

    // MARK: - Ledger

    @ViewBuilder
    private var ledger: some View {
        if !hasAppeared && viewModel.ideaGalleryItems.isEmpty {
            loadingState
        } else if visibleIdeas.isEmpty {
            emptyState
        } else {
            sections
        }
    }

    private var sections: some View {
        LazyVStack(spacing: DS.space24) {
            ForEach(Array(clientSections.enumerated()), id: \.element.id) { sectionIndex, section in
                clientSectionView(section, sectionIndex: sectionIndex)
            }
        }
    }

    private func clientSectionView(_ section: IdeasLedgerSection, sectionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            sectionHeader(section)
            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                LedgerRow(item: item) { openIdea(item) }
                    .atelierStaggerIn(
                        delay: staggerDelay(sectionIndex: sectionIndex, rowIndex: index),
                        appeared: hasAppeared
                    )
                if index < section.items.count - 1 {
                    Rectangle()
                        .fill(DS.sepiaSubtle)
                        .frame(height: 0.5)
                        .padding(.leading, DS.space16)
                }
            }
        }
    }

    private func sectionHeader(_ section: IdeasLedgerSection) -> some View {
        HStack(spacing: DS.space10) {
            Rectangle()
                .fill(section.color.opacity(0.6))
                .frame(width: 2, height: 14)
                .accessibilityHidden(true)
            Text(section.clientName.uppercased())
                .font(DS.smallCaps)
                .tracking(1.6)
                .foregroundStyle(DS.giltMuted)
                .fixedSize()
            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
            Text(section.countText)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.inkFaded)
        }
    }

    private var hairRule: some View {
        Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
    }

    // Stagger only the first ~12 rows to avoid cascade on large ledgers.
    private func staggerDelay(sectionIndex: Int, rowIndex: Int) -> Double {
        let ordinal = sectionIndex * 4 + rowIndex
        guard ordinal < 12 else { return 0 }
        return Double(ordinal) * 0.03
    }

    // MARK: - States

    private var loadingState: some View {
        Text("gathering the ledger…")
            .font(DS.dateSerif)
            .italic()
            .foregroundStyle(DS.inkFaded)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space40)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space20) {
            Text("no ideas yet —")
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkFaded)
            GiltBracketedCTA(title: "capture something", disabled: false) {
                captureFocused = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space40)
    }

    // MARK: - Data

    private static let activatedStatuses: Set<IdeaStatus> = [.inProduction, .published, .archived]

    private var visibleIdeas: [IdeaGalleryItem] {
        viewModel.ideaGalleryItems.filter { !Self.activatedStatuses.contains($0.status) }
    }

    private var clientSections: [IdeasLedgerSection] {
        var grouped: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []

        for item in visibleIdeas.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if let uuid = item.clientUUID {
                grouped[uuid, default: []].append(item)
            } else {
                unassigned.append(item)
            }
        }

        var sections: [IdeasLedgerSection] = []
        let sortedClients = clientProfiles.sorted { ($0.title ?? "") < ($1.title ?? "") }
        for client in sortedClients {
            guard let items = grouped[client.uuid], !items.isEmpty else { continue }
            sections.append(IdeasLedgerSection(
                id: client.uuid,
                clientName: client.title ?? "Client",
                clientUUID: client.uuid,
                color: DS.clientColor(for: client.uuid),
                items: items
            ))
        }
        if !unassigned.isEmpty {
            sections.append(IdeasLedgerSection(
                id: "__unassigned__",
                clientName: "Unassigned",
                clientUUID: nil,
                color: DS.entityIdea,
                items: unassigned
            ))
        }
        return sections
    }

    private func reload() async {
        await viewModel.loadIdeaGallery(forceReload: true)
        clientProfiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
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

// MARK: - Section Model

private struct IdeasLedgerSection: Identifiable {
    let id: String
    let clientName: String
    let clientUUID: String?
    let color: Color
    let items: [IdeaGalleryItem]

    var countText: String {
        "· \(items.count) idea\(items.count == 1 ? "" : "s")"
    }
}

// MARK: - Ledger Row

private struct LedgerRow: View {
    let item: IdeaGalleryItem
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: DS.space12) {
                accentBar
                titleColumn
                Spacer(minLength: DS.space12)
                trailing
            }
            .padding(.vertical, DS.space10)
            .padding(.horizontal, DS.space4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel(accessibilityText)
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

    private var accentBar: some View {
        Rectangle()
            .fill(accentColor.opacity(0.6))
            .frame(width: 2, height: 30)
            .accessibilityHidden(true)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: DS.space4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.gilt.opacity(0.7))
                        .accessibilityLabel("Pinned")
                }
                Text(item.title)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .italic(isHovered)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            }
            metaLine
        }
    }

    private var metaLine: some View {
        HStack(spacing: DS.space6) {
            Text(item.status.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.giltMuted)
            if let format = item.contentFormat {
                dotSeparator
                Text(format.displayName.lowercased())
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DS.inkFaded)
            }
            if let score = item.insightScore, score > 0 {
                dotSeparator
                Text(String(format: "%.0f%% match", score * 100))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.gilt.opacity(0.8))
            }
            if let swipes = item.matchingSwipeCount, swipes > 0 {
                dotSeparator
                Text("\(swipes) swipe\(swipes == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
            }
        }
    }

    private var dotSeparator: some View {
        Text("·")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(DS.inkFaded.opacity(0.5))
    }

    private var trailing: some View {
        HStack(spacing: DS.space8) {
            Text(relativeTime)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.inkFaded)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DS.gilt.opacity(isHovered ? 0.9 : 0.35))
                .offset(x: isHovered ? -2 : 0)
                .accessibilityHidden(true)
        }
    }

    private var accentColor: Color {
        if let uuid = item.clientUUID { return DS.clientColor(for: uuid) }
        return DS.entityIdea
    }

    private var accessibilityText: String {
        var parts: [String] = [item.title, item.status.displayName]
        if let client = item.clientName { parts.append(client) }
        return parts.joined(separator: ", ")
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

// IdeaSortMode and IdeaStatus.sortOrder live in IdeasTab.swift (still used elsewhere).
