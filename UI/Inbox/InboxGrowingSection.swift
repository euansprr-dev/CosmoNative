// CosmoOS/UI/Inbox/InboxGrowingSection.swift
// The Growing section — the global Seedbed under the triage queue. Thought
// captures routed "grow" accrue here as named proto-concepts; a ripe seedling
// is one click from a development conversation (the page is born from the
// user's own thoughts, in the connection workspace). Ledger grammar: rows on
// DS.bg, hairline separators, hover verbs, no cards.
// July 2026 — the global Seedbed.

import SwiftUI

/// Rendered INSIDE the queue's pinned LazyVStack so the "GROWING" header
/// pins exactly like the temporal sections above it.
struct InboxGrowingSection: View {
    @ObservedObject private var seedlings = SeedlingRepository.shared

    var body: some View {
        if !seedlings.growing.isEmpty {
            Section {
                ForEach(seedlings.growing) { seedling in
                    InboxSeedlingRow(seedling: seedling)
                }
            } header: {
                InboxSectionHeader(title: "Growing", itemCount: seedlings.growing.count)
            }
        }
    }
}

// MARK: - One seedling in the ledger

private struct InboxSeedlingRow: View {
    let seedling: Seedling

    @State private var isHovered = false
    @State private var isDeveloping = false
    /// Where else this concept is growing (a research dive) — a link worth
    /// proposing, never an automatic merge.
    @State private var alsoGrowingIn: String?
    /// Matching Readwise highlights — inspiration visible while it ripens.
    @State private var relatedHighlightCount = 0

    var body: some View {
        Button(action: develop) {
            rowContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .contextMenu { menu }
        .task(id: seedling.conceptKey) { await loadCollision() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seedling.name), \(seedling.massSummary)\(seedling.isRipe ? ", ripe" : "")")
        .help(seedling.isRipe
            ? "Develop this seedling into a Concept page"
            : "Growing — \(seedling.massSummary). Click to develop it now")
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
            Text(seedling.isRipe ? "Develop" : "Develop now")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(seedling.isRipe ? DS.textOnAccent : DS.textSecondary)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space6)
                .background(seedling.isRipe ? AnyShapeStyle(DS.accent) : AnyShapeStyle(DS.glassSectionFill), in: .capsule)
                .overlay(Capsule().strokeBorder(DS.borderSubtle, lineWidth: seedling.isRipe ? 0 : 0.5))
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
}
