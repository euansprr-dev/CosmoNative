// CosmoOS/UI/CommandK/CortexIdeasBrowser.swift
// Greenhouse-native ideas ledger for Command-K with per-column expansion.

import SwiftUI

struct CortexIdeasBrowser: View {
    @ObservedObject var viewModel: CommandKViewModel
    @State private var hasAppeared = false
    @State private var clientProfiles: [Atom] = []
    @State private var captureDrafts: [String: String] = [:]
    @State private var expandedClients: Set<String> = []
    @FocusState private var focusedClient: String?

    private static let previewLimit = 5
    private static let unassignedKey = "__unassigned__"
    private static let minimumColumnWidth: CGFloat = 340

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    ledger(availableWidth: geometry.size.width)
                }
                .padding(.horizontal, DS.space24)
                .padding(.vertical, DS.space20)
            }
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
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            hairRule
        }
        .padding(.bottom, DS.space20)
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

    // MARK: - Ledger

    @ViewBuilder
    private func ledger(availableWidth: CGFloat) -> some View {
        if !hasAppeared && viewModel.ideaGalleryItems.isEmpty {
            loadingState
        } else if clientSections.isEmpty {
            emptyState
        } else {
            columns(availableWidth: availableWidth)
        }
    }

    private func columns(availableWidth: CGFloat) -> some View {
        let columnWidth = max(
            Self.minimumColumnWidth,
            (availableWidth - (DS.space24 * 2) - (DS.space24 * CGFloat(max(clientSections.count - 1, 0)))) / CGFloat(max(clientSections.count, 1))
        )

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.space24) {
                ForEach(Array(clientSections.enumerated()), id: \.element.id) { sectionIndex, section in
                    clientColumn(section, sectionIndex: sectionIndex)
                        .frame(width: columnWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DS.space8)
        }
    }

    private func clientColumn(_ section: IdeasLedgerSection, sectionIndex: Int) -> some View {
        let visibleItems = CortexIdeasLedgerLayout.visibleItems(
            from: section.items,
            isExpanded: expandedClients.contains(section.id),
            previewLimit: Self.previewLimit
        )
        let hiddenCount = section.items.count - visibleItems.count

        return VStack(alignment: .leading, spacing: DS.space12) {
            columnHeader(section)
            IdeaMaterialCaptureRow(
                section: section,
                draft: Binding(
                    get: { captureDrafts[section.id] ?? "" },
                    set: { captureDrafts[section.id] = $0 }
                ),
                focusedClient: $focusedClient
            ) {
                submitCapture(for: section)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    IdeaMaterialLedgerRow(item: item) { openIdea(item) }
                        .atelierStaggerIn(
                            delay: staggerDelay(sectionIndex: sectionIndex, rowIndex: index),
                            appeared: hasAppeared
                        )
                    if index < visibleItems.count - 1 {
                        Rectangle()
                            .fill(DS.glassBorder.opacity(0.55))
                            .frame(height: 0.5)
                            .padding(.leading, DS.space12)
                    }
                }
            }
            if hiddenCount > 0 {
                showMoreButton(section: section, hiddenCount: hiddenCount)
            } else if expandedClients.contains(section.id) && section.items.count > Self.previewLimit {
                showLessButton(section: section)
            }
        }
        .padding(DS.space16)
        .modifier(IdeaMaterialLaneChrome(accentColor: section.color))
    }

    private func columnHeader(_ section: IdeasLedgerSection) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space10) {
                Circle()
                    .fill(section.color.opacity(0.82))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(section.clientName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer(minLength: DS.space8)

                Text(section.countText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space4)
            .padding(.vertical, DS.space4)

            Rectangle()
                .fill(DS.glassBorder.opacity(0.7))
                .frame(height: 0.5)
        }
    }

    private func submitCapture(for section: IdeasLedgerSection) {
        guard let title = CortexIdeasCapture.normalizedTitle(from: captureDrafts[section.id] ?? "") else { return }
        captureDrafts[section.id] = ""
        focusedClient = section.id
        Task { await viewModel.createIdeaForClient(title: title, clientUUID: section.clientUUID) }
    }

    // MARK: - Expansion

    private func showMoreButton(section: IdeasLedgerSection, hiddenCount: Int) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                _ = expandedClients.insert(section.id)
            }
        } label: {
            HStack(spacing: DS.space6) {
                Text("Show \(hiddenCount) more ideas")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(section.color.opacity(0.8))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.space10)
            .padding(.horizontal, DS.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(section.color.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(section.color.opacity(0.16), lineWidth: 0.5)
        )
        .accessibilityLabel("Show \(hiddenCount) more ideas for \(section.clientName)")
    }

    private func showLessButton(section: IdeasLedgerSection) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                _ = expandedClients.remove(section.id)
            }
        } label: {
            HStack(spacing: DS.space6) {
                Text("Collapse preview")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(section.color.opacity(0.8))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.space10)
            .padding(.horizontal, DS.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(DS.glassInputFill.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.65), lineWidth: 0.5)
        )
        .accessibilityLabel("Collapse ideas preview for \(section.clientName)")
    }

    private var hairRule: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 0.5)
    }

    private func staggerDelay(sectionIndex: Int, rowIndex: Int) -> Double {
        let ordinal = sectionIndex * 4 + rowIndex
        guard ordinal < 12 else { return 0 }
        return Double(ordinal) * 0.03
    }

    // MARK: - States

    private var loadingState: some View {
        Text("gathering the ledger…")
            .font(DS.callout)
            .foregroundStyle(DS.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space40)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space12) {
            Text("the ledger is empty —")
                .font(DS.title3)
                .foregroundStyle(DS.text)
            Text(clientProfiles.isEmpty ? "add a client to begin" : "capture a spark in any column")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
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
        CortexIdeasSectionBuilder.sections(
            visibleIdeas: visibleIdeas,
            clientProfiles: clientProfiles,
            unassignedKey: Self.unassignedKey
        )
    }

    private func reload() async {
        await viewModel.loadIdeaGallery(forceReload: true)
        clientProfiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
    }

    private func openIdea(_ item: IdeaGalleryItem) {
        Task { try? await NodeGraphEngine.shared.recordAccess(atomUUID: item.atomUUID, type: .view) }
        NotificationCenter.default.post(
            name: CosmoNotification.NodeGraph.openAtomFromCommandK,
            object: nil,
            userInfo: ["atomUUID": item.atomUUID]
        )
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
    }
}

// MARK: - Section Model

struct IdeasLedgerSection: Identifiable {
    let id: String
    let clientName: String
    let clientUUID: String?
    let color: Color
    let items: [IdeaGalleryItem]

    var countText: String {
        "\(items.count) idea\(items.count == 1 ? "" : "s")"
    }
}

enum CortexIdeasSectionBuilder {
    static func sections(
        visibleIdeas: [IdeaGalleryItem],
        clientProfiles: [Atom],
        unassignedKey: String = "__unassigned__"
    ) -> [IdeasLedgerSection] {
        var grouped: [String: [IdeaGalleryItem]] = [:]
        var unassigned: [IdeaGalleryItem] = []

        for item in visibleIdeas.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if let uuid = item.clientUUID {
                grouped[uuid, default: []].append(item)
            } else {
                unassigned.append(item)
            }
        }

        let clientSections = clientProfiles
            .sorted { ($0.title ?? "") < ($1.title ?? "") }
            .map { client in
                IdeasLedgerSection(
                    id: client.uuid,
                    clientName: client.title ?? "Client",
                    clientUUID: client.uuid,
                    color: DS.clientColor(for: client.uuid),
                    items: grouped[client.uuid] ?? []
                )
            }

        guard !unassigned.isEmpty else { return clientSections }

        return clientSections + [
            IdeasLedgerSection(
                id: unassignedKey,
                clientName: "Unassigned",
                clientUUID: nil,
                color: DS.entityIdea,
                items: unassigned
            )
        ]
    }
}

// MARK: - Material Chrome

private struct IdeaMaterialLaneChrome: ViewModifier {
    let accentColor: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(DS.glassCardFill.opacity(0.30))
                    shape.fill(accentColor.opacity(0.025))
                }
            }
            .overlay {
                shape.strokeBorder(DS.glassBorder.opacity(0.74), lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                DS.sidebarMaterialHighlight.opacity(0.22),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.55
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: DS.sidebarMaterialShadow.opacity(0.42), radius: 10, x: 0, y: 4)
            .shadow(color: Color.black.opacity(DS.palette.isDark ? 0.035 : 0.018), radius: 2, x: 0, y: 1)
    }
}

private struct IdeaMaterialCaptureRow: View {
    let section: IdeasLedgerSection
    @Binding var draft: String
    @FocusState.Binding var focusedClient: String?
    let onSubmit: () -> Void

    private var isActive: Bool {
        focusedClient == section.id
    }

    private var canSubmit: Bool {
        CortexIdeasCapture.normalizedTitle(from: draft) != nil
    }

    var body: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: canSubmit ? "plus.circle.fill" : "plus.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(canSubmit ? section.color : DS.textMuted)
                .frame(width: 16)
                .accessibilityHidden(true)

            TextField("add idea", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .italic(draft.isEmpty)
                .foregroundStyle(isActive || !draft.isEmpty ? DS.text : DS.textMuted)
                .focused($focusedClient, equals: section.id)
                .onSubmit(onSubmit)
                .accessibilityLabel("Add idea for \(section.clientName)")

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSubmit ? section.color : DS.textMuted.opacity(0.58))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .help("Capture idea")
            .accessibilityLabel("Capture idea for \(section.clientName)")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(isActive ? section.color.opacity(0.065) : DS.glassInputFill.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .strokeBorder(isActive ? section.color.opacity(0.24) : DS.glassBorder.opacity(0.62), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .animation(ProMotionSprings.hover, value: isActive)
        .animation(ProMotionSprings.hover, value: canSubmit)
        .onTapGesture {
            focusedClient = section.id
        }
    }
}

// MARK: - Ledger Row

struct IdeaMaterialLedgerRow: View {
    let item: IdeaGalleryItem
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: DS.space8) {
                accentBar
                titleColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space12)
            .frame(minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .fill(isHovered ? accentColor.opacity(0.055) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .strokeBorder(isHovered ? accentColor.opacity(0.14) : Color.clear, lineWidth: 0.5)
            )
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
            .fill(accentColor.opacity(0.85))
            .frame(width: 3)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.gilt.opacity(0.8))
                        .accessibilityLabel("Pinned")
                }

                Text(item.title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .italic(isHovered)
                    .foregroundStyle(DS.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metaLine
        }
    }

    private var metaLine: some View {
        HStack(spacing: DS.space6) {
            Text(item.status.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(accentColor.opacity(0.8))

            if let format = item.contentFormat {
                dotSeparator
                Text(format.displayName.lowercased())
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }

            if let score = item.insightScore, score > 0 {
                dotSeparator
                Text(String(format: "%.0f%%", score * 100))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var dotSeparator: some View {
        Text("·")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(DS.textMuted.opacity(0.6))
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(relativeTime)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.textSecondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(accentColor.opacity(isHovered ? 0.9 : 0.35))
                .offset(x: isHovered ? -2 : 0)
                .accessibilityHidden(true)
        }
        .padding(.top, 2)
    }

    private var accentColor: Color {
        if let uuid = item.clientUUID {
            return DS.clientColor(for: uuid)
        }
        return DS.entityIdea
    }

    private var accessibilityText: String {
        var parts: [String] = [item.title, item.status.displayName]
        if let client = item.clientName {
            parts.append(client)
        }
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

enum CortexIdeasLedgerLayout {
    static func visibleItems(from items: [IdeaGalleryItem], isExpanded: Bool, previewLimit: Int) -> [IdeaGalleryItem] {
        guard !isExpanded else { return items }
        return Array(items.prefix(previewLimit))
    }
}

enum CortexIdeasCapture {
    static func normalizedTitle(from draft: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// IdeaSortMode and IdeaStatus.sortOrder live in IdeasTab.swift (still used elsewhere).
