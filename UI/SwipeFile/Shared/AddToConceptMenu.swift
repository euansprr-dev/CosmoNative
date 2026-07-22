// CosmoOS/UI/SwipeFile/Shared/AddToConceptMenu.swift
// "Add to concept…" — the swipe-side door onto concept boards. Lists recent
// concept pages; picking one attaches this swipe's media ref through
// ConceptMediaAttachService (idempotent, merge-safe, notifies open
// workspaces). Mirrors the add-to-board menu grammar.
// July 2026

import SwiftUI

struct AddToConceptMenu: View {
    /// The swipe/research atom to attach.
    let atomUUID: String

    @State private var concepts: [Atom] = []
    @State private var justAttachedUUID: String?
    @State private var hovering = false

    var body: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: justAttachedUUID == nil ? "lightbulb" : "checkmark")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(hovering ? DS.text : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? DS.glassInputFill : Color.clear))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { value in withAnimation(ProMotionSprings.hover) { hovering = value } }
        .help("Add to concept")
        .accessibilityLabel("Add to concept")
        .task { concepts = await ConceptMediaAttachService.recentConcepts() }
    }

    @ViewBuilder
    private var menuContent: some View {
        if concepts.isEmpty {
            Text("No concept pages yet")
        } else {
            ForEach(concepts, id: \.uuid) { concept in
                Button {
                    attach(to: concept)
                } label: {
                    if justAttachedUUID == concept.uuid {
                        Label(conceptTitle(concept), systemImage: "checkmark")
                    } else {
                        Text(conceptTitle(concept))
                    }
                }
            }
        }
    }

    private func conceptTitle(_ concept: Atom) -> String {
        let title = concept.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled Concept" : title
    }

    private func attach(to concept: Atom) {
        Task {
            let ok = await ConceptMediaAttachService.attach(
                sourceAtomUUID: atomUUID,
                toConcept: concept.uuid
            )
            guard ok else { return }
            withAnimation(ProMotionSprings.gentle) { justAttachedUUID = concept.uuid }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(ProMotionSprings.gentle) { justAttachedUUID = nil }
        }
    }
}

// MARK: - Back-links

/// "In concepts" chips for a swipe: every concept page whose board carries
/// this atom (graph edges written at attach time). Tap opens the concept as
/// a pane so the swipe stays visible.
struct SwipeConceptBacklinks: View {
    let atomUUID: String

    @State private var concepts: [Atom] = []

    var body: some View {
        Group {
            if !concepts.isEmpty {
                HStack(spacing: DS.space6) {
                    Image(systemName: "lightbulb")
                        .font(.caption2)
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                    Text("In concepts:")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                    ForEach(concepts.prefix(3), id: \.uuid) { concept in
                        Button {
                            open(concept)
                        } label: {
                            Text(concept.title?.isEmpty == false ? concept.title! : "Untitled")
                                .font(DS.caption.weight(.medium))
                                .foregroundStyle(DS.accent)
                                .lineLimit(1)
                                .padding(.horizontal, DS.space6)
                                .padding(.vertical, 2)
                                .background(DS.glassSectionFill, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Open \(concept.title ?? "concept") beside this swipe")
                        .accessibilityLabel("Open concept \(concept.title ?? "Untitled")")
                    }
                    if concepts.count > 3 {
                        Text("+\(concepts.count - 3)")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .task(id: atomUUID) { await load() }
    }

    private func load() async {
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
            concepts = []
            return
        }
        var found: [Atom] = []
        for link in atom.linksList where link.entityType == AtomType.connection.rawValue {
            guard let concept = try? await AtomRepository.shared.fetch(uuid: link.uuid),
                  !concept.isDeleted, concept.type == .connection else { continue }
            // Only count boards that actually carry this atom as media.
            let media = concept.structured.flatMap(ConnectionStructuredData.fromJSON)?.media ?? []
            guard media.contains(where: { $0.atomUUID == atomUUID }) else { continue }
            found.append(concept)
        }
        concepts = found
    }

    private func open(_ concept: Atom) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": concept.uuid, "asPane": true]
        )
    }
}
