// CosmoOS/UI/FocusMode/DeepDive/SeedlingShelf.swift
// The global Seedbed's shelf — unrooted growing concepts, surfaced in the
// Deep Dive world (where all concepts live) instead of the Inbox. Each row
// peeks its thought ledger; the two deliberate exits are Develop (the page is
// born from the user's own thoughts) and Root here (adopt into this dive's
// seedbed, joining its SEEDLINGS row and map). Ledger grammar: rows on DS.bg,
// hairline separators, hover verbs, no cards.
// July 2026 — moved out of the Inbox; the queue routes, it doesn't host.

import SwiftUI

/// Growing concepts that belong to no Deep Dive yet. Renders only when such
/// seedlings exist — a rooted seedbed keeps this strip invisible. Hosted on
/// every dive overview so an unrooted concept can never hide: whichever dive
/// the user is in offers "Root here".
struct UnrootedSeedlingsStrip: View {
    let deepDiveUUID: String
    let deepDiveTitle: String

    @ObservedObject private var seedlings = SeedlingRepository.shared

    var body: some View {
        if !seedlings.growing.isEmpty {
            StudySection(label: "UNROOTED", count: seedlings.growing.count) {
                VStack(alignment: .leading, spacing: 0) {
                    StudyTeachingRow(text: "Growing concepts that belong to no dive yet — root one here to give it a home, or develop it straight into a page.")
                    ForEach(seedlings.growing) { seedling in
                        SeedlingShelfRow(
                            seedling: seedling,
                            rootTargetUUID: deepDiveUUID,
                            rootTargetTitle: deepDiveTitle
                        )
                    }
                }
            }
        }
    }
}

// MARK: - One seedling in the ledger

struct SeedlingShelfRow: View {
    let seedling: Seedling
    /// When set, the row offers "Root here" — adopting the seedling into this
    /// dive's seedbed (its SEEDLINGS row and map).
    var rootTargetUUID: String? = nil
    var rootTargetTitle: String? = nil

    @State private var isHovered = false
    @State private var isDeveloping = false
    /// Click = peek at the accrued thoughts, never a surprise page birth.
    @State private var isPeeking = false
    /// Where else this concept is growing (a research dive) — a link worth
    /// proposing, never an automatic merge.
    @State private var alsoGrowingIn: String?
    /// Matching Readwise highlights — inspiration visible while it ripens.
    @State private var relatedHighlightCount = 0

    var body: some View {
        Button {
            isPeeking = true
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contextMenu { menu }
        .popover(isPresented: $isPeeking, arrowEdge: .trailing) {
            SeedlingPeekView(
                seedling: seedling,
                alsoGrowingIn: alsoGrowingIn,
                relatedHighlightCount: relatedHighlightCount,
                onDevelop: {
                    isPeeking = false
                    develop()
                }
            )
        }
        .task(id: seedling.conceptKey) { await loadCollision() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seedling.name), \(seedling.massSummary)\(seedling.isRipe ? ", ripe" : "")")
        .help(seedling.isRipe
            ? "Ripe — click to see its thoughts and develop it"
            : "Growing — \(seedling.massSummary). Click to peek at its thoughts")
    }

    private func loadCollision() async {
        let everywhere = (try? await SeedlingRepository.shared.fetchGrowingEverywhere(conceptKey: seedling.conceptKey)) ?? []
        alsoGrowingIn = nil
        for row in everywhere where row.uuid != seedling.uuid {
            guard let scope = row.scopeDeepDiveUUID else { continue }
            if let dive = try? await AtomRepository.shared.fetch(uuid: scope),
               !dive.isDeleted, let title = dive.title, !title.isEmpty {
                alsoGrowingIn = title
                break
            }
        }
        // The bookshelf whisper: matching Readwise highlights are
        // inspiration waiting for develop-time — threshold-gated, so the
        // count only appears when the concept's own words appear in them.
        relatedHighlightCount = await ReadwiseEvidenceMatcher.evidence(
            conceptName: seedling.name,
            aliases: seedling.aliases,
            limit: 12
        ).count
    }

    private var rowContent: some View {
        HStack(spacing: DS.space12) {
            Image(systemName: seedling.isRipe ? "leaf.fill" : "leaf")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(seedling.isRipe ? DS.accent : DS.textMuted)
                .frame(width: 14)
                .accessibilityHidden(true)

            titleColumn
            Spacer(minLength: DS.space12)
            trailingArea
        }
        .padding(.horizontal, DS.space16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .background(isHovered ? DS.glassSectionFill : .clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
                .padding(.leading, DS.space16 + 14 + DS.space12)
        }
        .opacity(isDeveloping ? 0.55 : 1)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(seedling.name)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Text(massLine)
                .font(DS.caption)
                .foregroundStyle(seedling.isRipe ? DS.accent : DS.textMuted)
                .monospacedDigit()
        }
    }

    private var massLine: String {
        var line = seedling.isRipe ? "Ripe · \(seedling.massSummary)" : seedling.massSummary
        // The concept's future home ("Philosophy") — where the page lands
        // once developed. Muted metadata, never an accent.
        if let home = seedling.affinityClusterName ?? seedling.affinityThinkspaceName {
            line += " · \(home)"
        }
        if let alsoGrowingIn {
            line += " · also in \(alsoGrowingIn)"
        }
        if relatedHighlightCount > 0 {
            line += " · \(relatedHighlightCount) highlight\(relatedHighlightCount == 1 ? "" : "s")"
        }
        return line
    }

    @ViewBuilder
    private var trailingArea: some View {
        if isHovered {
            HStack(spacing: DS.space6) {
                if rootTargetUUID != nil {
                    Button(action: root) {
                        Text("Root here")
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, DS.space10)
                            .padding(.vertical, DS.space6)
                            .background(DS.glassSectionFill, in: .capsule)
                            .overlay(Capsule().strokeBorder(DS.borderSubtle, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Adopt into this dive's seedbed — it joins the SEEDLINGS row and map")
                    .accessibilityLabel("Root \(seedling.name) in this dive")
                }
                Button(action: develop) {
                    Text(seedling.isRipe ? "Develop" : "Develop now")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(seedling.isRipe ? DS.textOnAccent : DS.textSecondary)
                        .padding(.horizontal, DS.space10)
                        .padding(.vertical, DS.space6)
                        .background(seedling.isRipe ? AnyShapeStyle(DS.accent) : AnyShapeStyle(DS.glassSectionFill), in: .capsule)
                        .overlay(Capsule().strokeBorder(DS.borderSubtle, lineWidth: seedling.isRipe ? 0 : 0.5))
                }
                .buttonStyle(.plain)
                .help("Develop into a Concept page now")
                .accessibilityLabel("Develop \(seedling.name) now")
            }
        } else if seedling.pinnedAt != nil {
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.gilt)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Develop into a page") { develop() }
        if let rootTargetTitle, rootTargetUUID != nil {
            Button("Root in \(rootTargetTitle)") { root() }
        }
        Button(seedling.pinnedAt == nil ? "Pin (always ripe)" : "Unpin") {
            Task {
                try? await SeedlingRepository.shared.setPinned(
                    uuid: seedling.uuid,
                    pinned: seedling.pinnedAt == nil
                )
            }
        }
        Divider()
        Button("Fold away", role: .destructive) {
            let folded = seedling
            Task {
                try? await SeedlingRepository.shared.setStatus(uuid: folded.uuid, status: .folded)
                CosmoUndoManager.shared.register(
                    InlineUndoAction(actionDescription: "Fold Seedling") {
                        try? await SeedlingRepository.shared.setStatus(uuid: folded.uuid, status: .growing)
                    } redo: {
                        try? await SeedlingRepository.shared.setStatus(uuid: folded.uuid, status: .folded)
                    }
                )
            }
        }
    }

    /// Develop = the page is born from the seedling's own thoughts and opens
    /// in the connection workspace, where the concept collaborator refines it
    /// with the user. The seedling settles as developed.
    private func develop() {
        guard !isDeveloping else { return }
        isDeveloping = true
        Task {
            defer { isDeveloping = false }
            guard let connectionUUID = await SeedlingDevelopService.shared.develop(seedlingUUID: seedling.uuid) else { return }
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": connectionUUID]
            )
        }
    }

    /// Root here = the seedling adopts this dive's seedbed. It leaves the
    /// unrooted shelf and appears in the dive's SEEDLINGS row and map, mass
    /// intact. Undoable — rooting is a home decision, not a commitment.
    private func root() {
        guard let diveUUID = rootTargetUUID else { return }
        let target = seedling
        Task {
            _ = try? await SeedlingRepository.shared.mutate(uuid: target.uuid) { row in
                guard row.scopeDeepDiveUUID == nil else { return false }
                row.scopeDeepDiveUUID = diveUUID
                row.lastTouchedAt = ISO8601.string(from: Date())
                return true
            }
            postSeedbedChanged(diveUUID)
            CosmoUndoManager.shared.register(
                InlineUndoAction(actionDescription: "Root Seedling") {
                    _ = try? await SeedlingRepository.shared.mutate(uuid: target.uuid) { row in
                        guard row.scopeDeepDiveUUID == diveUUID else { return false }
                        row.scopeDeepDiveUUID = nil
                        return true
                    }
                    await MainActor.run { postSeedbedChanged(diveUUID) }
                } redo: {
                    _ = try? await SeedlingRepository.shared.mutate(uuid: target.uuid) { row in
                        guard row.scopeDeepDiveUUID == nil else { return false }
                        row.scopeDeepDiveUUID = diveUUID
                        return true
                    }
                    await MainActor.run { postSeedbedChanged(diveUUID) }
                }
            )
        }
    }

    private func postSeedbedChanged(_ diveUUID: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.seedbedChanged,
            object: nil,
            userInfo: ["deepDiveUUID": diveUUID]
        )
    }
}

// MARK: - The peek

/// What's inside a growing concept — the accrued thoughts, why it is (or
/// isn't) ripe, and the one deliberate exit: Develop. The Mac twin of the
/// iPhone's SeedlingDetailSheet, spoken as a popover.
private struct SeedlingPeekView: View {
    let seedling: Seedling
    let alsoGrowingIn: String?
    let relatedHighlightCount: Int
    let onDevelop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header
            Text(ripenessLine)
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            thoughtLedger
            footer
        }
        .padding(DS.space16)
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(seedling.name)
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .lineLimit(2)
            Text(metaLine)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()
        }
    }

    private var metaLine: String {
        var parts = [seedling.massSummary]
        if let home = seedling.affinityClusterName ?? seedling.affinityThinkspaceName {
            parts.append(home)
        }
        if let alsoGrowingIn {
            parts.append("also in \(alsoGrowingIn)")
        }
        if relatedHighlightCount > 0 {
            parts.append("\(relatedHighlightCount) highlight\(relatedHighlightCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private var ripenessLine: String {
        if seedling.isRipe {
            return "Ready to become a Concept — develop it in a short conversation. The page is born from these thoughts."
        }
        let needed = max(0, 4 - seedling.pendingThoughts.count)
        if needed > 0 {
            return "\(needed) more thought\(needed == 1 ? "" : "s") and it's ready to develop. Pin it to ripen it now."
        }
        return "Thoughts from one sitting so far — another day's capture ripens it. Pin it to ripen it now."
    }

    private var thoughtLedger: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(seedling.pendingThoughts.reversed()) { thought in
                    SeedlingPeekThoughtRow(thought: thought)
                }
            }
        }
        .frame(maxHeight: 280)
        .background(DS.glassSectionFill, in: .rect(cornerRadius: 10))
    }

    private var footer: some View {
        Button(action: onDevelop) {
            Label("Develop", systemImage: "leaf.fill")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(DS.accent, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("The page is born from these thoughts and opens in the concept workspace")
    }
}

private struct SeedlingPeekThoughtRow: View {
    let thought: SeedlingThought

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(thought.text)
                .font(DS.subheadline)
                .foregroundStyle(DS.text.opacity(0.85))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(metaLine)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 0.5)
                .padding(.leading, DS.space12)
        }
    }

    private var metaLine: String {
        let source: String
        switch thought.sourceKind {
        case .inbox: source = "Inbox"
        case .lane: source = "Lane"
        case .manual: source = "Typed"
        case .study: source = "Study"
        case .mint: source = "Spotted while developing"
        }
        guard let date = ISO8601.date(from: thought.capturedAt) else { return source }
        return "\(source) · \(date.cosmoCompactAge)"
    }
}
