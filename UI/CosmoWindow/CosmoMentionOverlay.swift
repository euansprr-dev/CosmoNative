// CosmoOS/UI/CosmoWindow/CosmoMentionOverlay.swift
// @mention overlay for injecting atoms as context into Cosmo AI chat
// Appears above the input bar when user types "@"
// February 2026

import SwiftUI

// MARK: - Cosmo Mention Overlay

/// An overlay that appears above the Cosmo chat input bar when the user types `@`.
/// Shows category capsules for filtering, then live search results from the atom database.
///
/// Flow:
/// 1. User types `@` -> overlay slides up
/// 2. Before typing: horizontal row of category capsules (Content, Research, Idea, etc.)
/// 3. While typing after `@`: live search via AtomRepository with 200ms debounce
/// 4. Category selected first: filters results to that AtomType
/// 5. User taps a result -> atom added as context chip, `@query` text removed
/// 6. Escape dismisses the overlay
struct CosmoMentionOverlay: View {

    // MARK: - Bindings

    @Binding var isVisible: Bool
    @Binding var searchText: String
    var onSelect: (Atom) -> Void
    var onDismiss: () -> Void

    // MARK: - Internal State

    @State private var selectedCategory: AtomType? = nil
    @State private var results: [Atom] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var hoveredResultId: String? = nil

    // MARK: - Category Definitions

    private let categories: [(type: AtomType, label: String, icon: String)] = [
        (.content, "Content", "doc.richtext"),
        (.research, "Research", "magnifyingglass"),
        (.idea, "Idea", "lightbulb"),
        (.connection, "Connection", "link"),
        (.task, "Task", "checkmark.circle"),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Category capsules row
            categoryRow
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()
                .background(DS.border)

            // Results area
            if results.isEmpty && !searchText.isEmpty && !isSearching {
                emptyState
            } else if results.isEmpty && searchText.isEmpty {
                promptState
            } else {
                resultsList
            }
        }
        .frame(maxHeight: 300)
        .background(DS.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 16, y: -4)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .onChange(of: searchText) { newValue in
            performSearch(newValue)
        }
        .onChange(of: selectedCategory) { _ in
            performSearch(searchText)
        }
        .onExitCommand {
            onDismiss()
        }
    }

    // MARK: - Category Row

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.type) { category in
                    categoryCapsule(category)
                }
            }
        }
    }

    private func categoryCapsule(_ category: (type: AtomType, label: String, icon: String)) -> some View {
        let entityType = EntityType(rawValue: category.type.rawValue) ?? .idea
        let isSelected = selectedCategory == category.type
        let pillColor = CosmoMentionColors.color(for: entityType)
        let pillBg = CosmoMentionColors.pillBackground(for: entityType)

        return Button {
            withAnimation(ProMotionSprings.snappy) {
                if selectedCategory == category.type {
                    selectedCategory = nil
                } else {
                    selectedCategory = category.type
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(category.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? DS.surfaceElevated : pillColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? pillColor : pillBg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results, id: \.uuid) { atom in
                    resultRow(atom: atom)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 240)
    }

    private func resultRow(atom: Atom) -> some View {
        let entityType = EntityType(rawValue: atom.type.rawValue) ?? .idea
        let isHovered = hoveredResultId == atom.uuid

        return Button {
            onSelect(atom)
        } label: {
            HStack(spacing: 10) {
                // Type icon with color
                Image(systemName: atom.type.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CosmoMentionColors.color(for: entityType))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(atom.title ?? "Untitled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(1)

                    if let body = atom.body, !body.isEmpty {
                        Text(String(body.prefix(60)))
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Type badge
                Text(atom.type.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CosmoMentionColors.color(for: entityType))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CosmoMentionColors.pillBackground(for: entityType))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? DS.border : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredResultId = hovering ? atom.uuid : nil
        }
    }

    // MARK: - Empty & Prompt States

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(DS.textMuted)

            Text("No results")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Text("Try a different search term")
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var promptState: some View {
        VStack(spacing: 8) {
            Image(systemName: "at")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(DS.textMuted)

            Text("Type to search...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Text("Search your ideas, content, research, and more")
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Search Logic

    private func performSearch(_ query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            // 200ms debounce
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            let atoms: [Atom]
            if let category = selectedCategory {
                atoms = (try? await AtomRepository.shared.search(query: query, types: [category])) ?? []
            } else {
                atoms = (try? await AtomRepository.shared.search(query: query, limit: 15)) ?? []
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.results = Array(atoms.prefix(15))
                self.isSearching = false
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CosmoMentionOverlay_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isVisible = true
        @State private var searchText = ""

        var body: some View {
            ZStack {
                DS.bg.ignoresSafeArea()

                VStack {
                    Spacer()
                    CosmoMentionOverlay(
                        isVisible: $isVisible,
                        searchText: $searchText,
                        onSelect: { _ in },
                        onDismiss: { }
                    )
                }
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .frame(width: 400, height: 500)
    }
}
#endif
