// CosmoOS/UI/Ideas/IdeasDeskView.swift
// The Desk — the Ideas destination's landing view (July 2026 reinvention).
// Three zones in the day's honest order: what you committed to (Up next),
// what's worth choosing per creator (ranked proposals with why-lines), and
// what still needs sorting (the sparks tray). ~20 objects instead of the
// whole corpus; every card earned its place. Scoped to one client, the same
// desk deals only their hand.

import SwiftUI

// MARK: - Layout (one tiling truth for the desk AND the keyboard cursor)

/// Integral tiling, the shelf law: a whole number of cards fits the measure
/// exactly — nothing is ever sliced mid-word. The shell reuses the same
/// counts so arrow keys walk exactly the visible cards.
struct IdeasDeskLayout {
    let contentWidth: CGFloat
    static let spacing = SwipeShelfMetrics.cardSpacing

    /// Proposal grid: ~300pt ideal, 2–4 per row.
    var proposalColumns: Int {
        guard contentWidth > 0 else { return 3 }
        return min(4, max(2, Int((contentWidth + Self.spacing) / (300 + Self.spacing))))
    }

    var proposalCardWidth: CGFloat {
        width(for: proposalColumns)
    }

    /// Hero shelf: ~360pt ideal, whole cards per page.
    var heroColumns: Int {
        guard contentWidth > 0 else { return 3 }
        return max(1, Int((contentWidth + Self.spacing) / (360 + Self.spacing)))
    }

    var heroCardWidth: CGFloat {
        width(for: heroColumns)
    }

    private func width(for count: Int) -> CGFloat {
        guard contentWidth > 0 else { return 300 }
        return (contentWidth - Self.spacing * CGFloat(count - 1)) / CGFloat(count)
    }

    /// The visible desk as ordered id sections — the shell's cursor map.
    /// Mirrors exactly what `IdeasDeskView` renders for the same inputs.
    @MainActor
    func cursorSections(model: IdeasPageModel, scopedClientId: String?) -> [[String]] {
        let desk = model.desk
        var sections: [[String]] = []

        if let scopedClientId {
            if scopedClientId == "__unassigned__" {
                sections.append(desk.sparks.map(\.atomUUID))
            } else {
                let upNext = desk.upNext.filter { $0.clientUUID == scopedClientId }
                if !upNext.isEmpty { sections.append(upNext.map(\.atomUUID)) }
                let proposals = (desk.proposalsByClient[scopedClientId] ?? []).prefix(proposalColumns * 2)
                if !proposals.isEmpty { sections.append(proposals.map(\.id)) }
            }
            return sections
        }

        if !desk.upNext.isEmpty {
            sections.append(desk.upNext.prefix(IdeasDeskView.upNextCap).map(\.atomUUID))
        }
        for group in model.clientGroups where group.clientUUID != nil {
            guard let clientUUID = group.clientUUID else { continue }
            let proposals = (desk.proposalsByClient[clientUUID] ?? []).prefix(proposalColumns)
            if !proposals.isEmpty { sections.append(proposals.map(\.id)) }
        }
        if !desk.sparks.isEmpty {
            sections.append(desk.sparks.prefix(IdeasDeskView.sparksCap).map(\.atomUUID))
        }
        return sections
    }
}

// MARK: - Desk

struct IdeasDeskView: View {
    let model: IdeasPageModel
    /// nil = the studio-wide desk; a client uuid (or "__unassigned__") deals
    /// one hand.
    var scopedClientId: String?
    let contentWidth: CGFloat
    let hasAppeared: Bool
    var cursorID: String?
    let onOpen: (IdeaGalleryItem) -> Void
    let onOpenAsPane: (IdeaGalleryItem) -> Void
    /// Digest-header door → scope the desk to that client.
    let onOpenClientDesk: (String) -> Void
    /// Scoped tail door → the All Ideas view.
    let onOpenAll: (String?) -> Void
    /// Sparks header door → the sorting ritual.
    let onSortSparks: () -> Void

    static let upNextCap = 8
    static let sparksCap = 10

    private var layout: IdeasDeskLayout { IdeasDeskLayout(contentWidth: contentWidth) }
    private var desk: IdeasDeskEngine.Desk { model.desk }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            if let scopedClientId {
                scopedDesk(scopedClientId)
            } else {
                studioDesk
            }
        }
    }

    // MARK: Studio-wide desk

    @ViewBuilder
    private var studioDesk: some View {
        upNextSection(desk.upNext.prefix(Self.upNextCap), totalCount: desk.upNext.count)
            .cascadeIn(hasAppeared, index: 0)

        let blocks = model.clientGroups.filter { $0.clientUUID != nil }
        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, group in
            clientBlock(group)
                .cascadeIn(hasAppeared, index: min(index + 1, 8))
        }

        if !desk.sparks.isEmpty {
            sparksTray
                .cascadeIn(hasAppeared, index: min(blocks.count + 1, 8))
        }
    }

    // MARK: One client's desk

    @ViewBuilder
    private func scopedDesk(_ clientId: String) -> some View {
        if clientId == "__unassigned__" {
            unassignedDesk
        } else {
            let theirs = desk.upNext.filter { $0.clientUUID == clientId }
            if !theirs.isEmpty {
                upNextSection(theirs.prefix(Self.upNextCap), totalCount: theirs.count)
                    .cascadeIn(hasAppeared, index: 0)
            }
            chooseNextSection(clientId)
                .cascadeIn(hasAppeared, index: 1)
            openAllDoor(clientId)
                .cascadeIn(hasAppeared, index: 2)
        }
    }

    /// The Unassigned pill's desk IS the tray, grid-sized: sorting sparks is
    /// this scope's whole job — the header doors into the ritual.
    private var unassignedDesk: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CosmoShelfHeader(
                title: "New sparks",
                detail: "\(desk.sparks.count)",
                onTap: desk.sparks.isEmpty ? nil : onSortSparks
            )
            if desk.sparks.isEmpty {
                teachingRow(
                    icon: "sparkles",
                    line: "Unassigned captures land here for sorting."
                )
            } else {
                sparkGrid(Array(desk.sparks))
            }
        }
        .cascadeIn(hasAppeared, index: 0)
    }

    // MARK: Up next

    @ViewBuilder
    private func upNextSection(_ ideas: ArraySlice<IdeaGalleryItem>, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CosmoShelfHeader(title: "Up next", detail: totalCount > 0 ? "\(totalCount)" : nil)
            if ideas.isEmpty {
                teachingRow(
                    icon: "pin",
                    line: "Pin an idea or schedule a session and it waits here."
                )
            } else {
                SwipeShelfScroller(cardPitch: layout.heroCardWidth + IdeasDeskLayout.spacing) {
                    ForEach(Array(ideas), id: \.atomUUID) { idea in
                        IdeaHeroCard(
                            idea: idea,
                            inspirationThumbs: model.inspirationThumbs[idea.atomUUID] ?? [],
                            clientTint: idea.clientUUID.map { DS.clientColor(for: $0) },
                            scheduledDay: model.scheduledDays[idea.atomUUID],
                            isCursor: cursorID == idea.atomUUID,
                            actions: actions(for: idea)
                        )
                        .frame(width: layout.heroCardWidth, alignment: .topLeading)
                        .id(idea.atomUUID)
                    }
                }
            }
        }
    }

    // MARK: Creator blocks

    /// One creator, one hand: digest header (a door to their desk) + their
    /// top proposals in a single tiled row.
    @ViewBuilder
    private func clientBlock(_ group: IdeasHomeGroup) -> some View {
        let proposals = Array((desk.proposalsByClient[group.clientUUID ?? ""] ?? []).prefix(layout.proposalColumns))
        VStack(alignment: .leading, spacing: DS.space10) {
            CosmoShelfHeader(
                title: group.name,
                detail: digestDetail(for: group),
                onTap: { onOpenClientDesk(group.id) }
            )
            if proposals.isEmpty {
                teachingRow(
                    icon: "checkmark.circle",
                    line: "Everything of \(group.name)'s is queued or in motion."
                )
            } else {
                proposalRow(proposals)
            }
        }
    }

    @ViewBuilder
    private func chooseNextSection(_ clientId: String) -> some View {
        let proposals = Array((desk.proposalsByClient[clientId] ?? []).prefix(layout.proposalColumns * 2))
        VStack(alignment: .leading, spacing: DS.space10) {
            CosmoShelfHeader(title: "Choose next", detail: proposals.isEmpty ? nil : "\(proposals.count)")
            if proposals.isEmpty {
                teachingRow(
                    icon: "checkmark.circle",
                    line: "Nothing waiting to be chosen — everything's queued or in motion."
                )
            } else {
                let rows = stride(from: 0, to: proposals.count, by: layout.proposalColumns).map {
                    Array(proposals[$0..<min($0 + layout.proposalColumns, proposals.count)])
                }
                VStack(alignment: .leading, spacing: DS.space12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        proposalRow(row)
                    }
                }
            }
        }
    }

    private func proposalRow(_ proposals: [IdeasDeskEngine.Proposal]) -> some View {
        HStack(alignment: .top, spacing: IdeasDeskLayout.spacing) {
            ForEach(proposals) { proposal in
                IdeaProposalCard(
                    proposal: proposal,
                    inspirationThumbs: model.inspirationThumbs[proposal.id] ?? [],
                    isCursor: cursorID == proposal.id,
                    actions: actions(for: proposal.item)
                )
                .frame(width: layout.proposalCardWidth, alignment: .topLeading)
                .id(proposal.id)
            }
        }
    }

    // MARK: Sparks tray

    private var sparksTray: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            CosmoShelfHeader(
                title: "New sparks",
                detail: "\(desk.sparks.count)",
                onTap: onSortSparks
            )
            SwipeShelfScroller(cardPitch: 220 + IdeasDeskLayout.spacing) {
                ForEach(desk.sparks.prefix(Self.sparksCap), id: \.atomUUID) { idea in
                    IdeaSparkChip(
                        idea: idea,
                        isCursor: cursorID == idea.atomUUID,
                        actions: actions(for: idea)
                    )
                    .id(idea.atomUUID)
                }
            }
        }
    }

    private func sparkGrid(_ sparks: [IdeaGalleryItem]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: DS.space12, alignment: .topLeading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: DS.space12) {
            ForEach(sparks, id: \.atomUUID) { idea in
                IdeaSparkChip(
                    idea: idea,
                    isCursor: cursorID == idea.atomUUID,
                    actions: actions(for: idea)
                )
                .id(idea.atomUUID)
            }
        }
    }

    // MARK: Doors & teaching rows

    private func openAllDoor(_ clientId: String) -> some View {
        Button {
            onOpenAll(clientId)
        } label: {
            HStack(spacing: DS.space4) {
                Text("Open all ideas")
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
            }
            .font(DS.callout.weight(.medium))
            .foregroundStyle(DS.textSecondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Browse the full list")
    }

    /// Absence teaches (never an empty gap): one quiet line in the section's
    /// place naming the next action.
    private func teachingRow(icon: String, line: String) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: icon)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.entityIdea.opacity(0.45))
                .accessibilityHidden(true)
            Text(line)
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.vertical, DS.space8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Plumbing

    private func digestDetail(for group: IdeasHomeGroup) -> String {
        let digest = group.clientUUID.flatMap { desk.digests[$0] }
            ?? IdeasDeskEngine.ClientDigest(ready: 0, developing: 0, total: group.ideas.count)
        var parts: [String] = []
        if digest.ready > 0 { parts.append("\(digest.ready) ready") }
        if digest.developing > 0 { parts.append("\(digest.developing) developing") }
        parts.append("\(digest.total)")
        // The studio pulse: how long since this creator last shipped.
        if let clientUUID = group.clientUUID, let shipped = model.shippedRecency[clientUUID] {
            parts.append("shipped \(shipped.cosmoCompactAge)")
        }
        return parts.joined(separator: " · ")
    }

    private func actions(for idea: IdeaGalleryItem) -> IdeaDeskActions {
        IdeaDeskActions(
            open: { onOpen(idea) },
            openAsPane: { onOpenAsPane(idea) },
            togglePin: { model.togglePin(idea) },
            pass: { model.pass(idea) },
            setStatus: { model.setStatus(idea, to: $0) },
            assignClient: { model.assignClient(idea, to: $0) },
            schedule: { model.scheduleDevelopment(idea, on: $0) },
            delete: { model.deferDelete(idea) },
            dropSwipe: { model.linkSwipe(uuid: $0, toIdea: idea.atomUUID) },
            assignableClients: model.assignableClients
        )
    }
}

