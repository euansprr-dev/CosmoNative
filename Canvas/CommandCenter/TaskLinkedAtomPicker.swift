// Canvas/CommandCenter/TaskLinkedAtomPicker.swift
// Search popover for linking atoms/thinkspaces to tasks (max 3)
// Reuses MentionSearchProvider for search
// March 2026

import SwiftUI

struct TaskLinkedAtomPicker: View {

    @Binding var linkedAtoms: [TaskLinkedAtom]
    var onUpdate: () -> Void

    @State private var searchQuery = ""
    @State private var searchResults: [MentionSearchResult] = []
    @State private var showSearch = false
    @FocusState private var isSearchFocused: Bool

    private let maxLinkedAtoms = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                    Text("Connected")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                }

                Spacer()

                if linkedAtoms.count < maxLinkedAtoms {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showSearch.toggle()
                            if showSearch {
                                isSearchFocused = true
                                Task { await loadRecent() }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(DS.caption2)
                            Text("Link")
                                .font(DS.caption2)
                        }
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Max 3")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
            }

            // Linked atom rows
            ForEach(linkedAtoms) { linked in
                linkedAtomRow(linked)
            }

            // Search field + results
            if showSearch {
                searchSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Linked Atom Row

    @ViewBuilder
    private func linkedAtomRow(_ linked: TaskLinkedAtom) -> some View {
        let entityType = EntityType(rawValue: linked.atomType)
        let color = entityType.map { CosmoMentionColors.color(for: $0) } ?? DS.textMuted
        let icon = entityType?.icon ?? "link"

        HStack(spacing: 8) {
            // Entity icon
            Image(systemName: icon)
                .font(DS.caption2)
                .foregroundStyle(color)
                .frame(width: 16)

            // Title
            Text(linked.titleSnapshot)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            // Type badge
            Text(entityType?.rawValue.capitalized ?? "Atom")
                .font(DS.caption2)
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.1), in: Capsule())

            // Primary star
            Button {
                setPrimary(linked.id)
            } label: {
                Image(systemName: linked.isPrimary ? "star.fill" : "star")
                    .font(DS.caption2)
                    .foregroundStyle(linked.isPrimary ? DS.orange : DS.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(linked.isPrimary ? "Primary link" : "Set as primary")

            // Remove
            Button {
                removeLinkedAtom(linked.id)
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove link")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            linked.isPrimary ? DS.orange.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Search input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)

                TextField("Search atoms, thinkspaces...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(DS.footnote)
                    .foregroundStyle(DS.text)
                    .focused($isSearchFocused)
                    .onChange(of: searchQuery) {
                        Task { await performSearch() }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.borderSubtle, lineWidth: 1))

            // Results
            if !searchResults.isEmpty {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(searchResults) { result in
                            searchResultRow(result)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 150)
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(_ result: MentionSearchResult) -> some View {
        let color = CosmoMentionColors.color(for: result.entityType)
        let alreadyLinked = linkedAtoms.contains { $0.atomUUID == result.atomUUID }

        Button {
            guard !alreadyLinked else { return }
            addLinkedAtom(from: result)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: result.entityType.icon)
                    .font(DS.caption2)
                    .foregroundStyle(color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(DS.caption)
                        .foregroundStyle(alreadyLinked ? DS.textMuted : DS.text)
                        .lineLimit(1)

                    if let subtitle = result.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(result.typeLabel)
                    .font(DS.caption2)
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(CosmoMentionColors.pillBackground(for: result.entityType), in: Capsule())

                if alreadyLinked {
                    Image(systemName: "checkmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(alreadyLinked)
    }

    // MARK: - Actions

    private func addLinkedAtom(from result: MentionSearchResult) {
        guard linkedAtoms.count < maxLinkedAtoms else { return }
        guard !linkedAtoms.contains(where: { $0.atomUUID == result.atomUUID }) else { return }

        let newAtom = TaskLinkedAtom(
            atomUUID: result.atomUUID,
            atomType: result.atomType.rawValue,
            titleSnapshot: result.title,
            isPrimary: linkedAtoms.isEmpty  // First linked atom is auto-primary
        )
        linkedAtoms.append(newAtom)
        onUpdate()

        // Clear search
        searchQuery = ""
        searchResults = []
        if linkedAtoms.count >= maxLinkedAtoms {
            showSearch = false
        }
    }

    private func removeLinkedAtom(_ id: String) {
        let wasPrimary = linkedAtoms.first(where: { $0.id == id })?.isPrimary ?? false
        linkedAtoms.removeAll { $0.id == id }

        // If removed atom was primary, make first remaining atom primary
        if wasPrimary, !linkedAtoms.isEmpty {
            linkedAtoms[0].isPrimary = true
        }
        onUpdate()
    }

    private func setPrimary(_ id: String) {
        for i in linkedAtoms.indices {
            linkedAtoms[i].isPrimary = (linkedAtoms[i].id == id)
        }
        onUpdate()
    }

    private func performSearch() async {
        let results = await MentionSearchProvider.shared.search(query: searchQuery, limit: 8)
        await MainActor.run {
            searchResults = results
        }
    }

    private func loadRecent() async {
        let results = await MentionSearchProvider.shared.search(query: "", limit: 8)
        await MainActor.run {
            searchResults = results
        }
    }
}
