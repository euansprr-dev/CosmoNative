// CosmoOS/UI/AtomWindow/AtomSearchOverlay.swift
// Search overlay for the floating atom viewer — FTS5 search with type filtering

import SwiftUI

struct AtomSearchOverlay: View {
    @Bindable var viewModel: AtomWindowViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            filterChips
            Divider().foregroundStyle(DS.glassBorder.opacity(0.68))
            resultsList
        }
        .cosmoGlassPanel(role: .globalSidebar, cornerRadius: 28)
        .padding(DS.space20)
        .frame(maxHeight: AtomWindowMetrics.searchOverlayMaxHeight)
        .onAppear { isSearchFocused = true }
        .onKeyPress(.escape) {
            viewModel.isSearchVisible = false
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSearchSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.moveSearchSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            Task { await viewModel.openSearchResult(at: viewModel.selectedSearchIndex) }
            return .handled
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.textMuted)

            TextField("Search atoms…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onChange(of: viewModel.searchQuery) {
                    viewModel.performSearch()
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.space12)
        .frame(height: AtomWindowMetrics.searchFieldHeight)
        .dsGlassInput(isFocused: isSearchFocused, cornerRadius: 16)
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space8)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space6) {
                filterChip(label: "All", icon: "square.grid.2x2", type: nil)
                filterChip(label: "Ideas", icon: AtomType.idea.iconName, type: .idea)
                filterChip(label: "Research", icon: AtomType.research.iconName, type: .research)
                filterChip(label: "Content", icon: AtomType.content.iconName, type: .content)
                filterChip(label: "Concepts", icon: AtomType.connection.iconName, type: .connection)
                filterChip(label: "Notes", icon: AtomType.note.iconName, type: .note)
                filterChip(label: "Tasks", icon: AtomType.task.iconName, type: .task)
            }
            .padding(.horizontal, DS.space12)
        }
        .frame(height: AtomWindowMetrics.filterChipHeight)
        .padding(.bottom, DS.space8)
    }

    private func filterChip(label: String, icon: String, type: AtomType?) -> some View {
        let isActive = viewModel.selectedTypeFilter == type
        return Button {
            viewModel.selectedTypeFilter = type
            viewModel.performSearch()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(DS.caption)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .background(isActive ? DS.accentSoft.opacity(0.86) : DS.glassCardFill.opacity(0.52), in: Capsule())
            .foregroundStyle(isActive ? DS.accent : DS.textSecondary)
            .overlay(Capsule().stroke(isActive ? DS.accent.opacity(0.3) : DS.glassBorder.opacity(0.72), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.searchQuery.isEmpty {
                    emptySearchContent
                } else if viewModel.searchResults.isEmpty {
                    noResultsView
                } else {
                    searchResultRows
                }
            }
        }
    }

    @ViewBuilder
    private var emptySearchContent: some View {
        if !viewModel.bookmarkedUUIDs.isEmpty {
            sectionHeader("Bookmarks")
        }

        if !viewModel.recentAtoms.isEmpty {
            sectionHeader("Recent")
            ForEach(viewModel.recentAtoms) { atom in
                atomRow(atom: atom, isSelected: false)
            }
        }
    }

    private var noResultsView: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(DS.textMuted)
            Text("No results found")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private var searchResultRows: some View {
        ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, result in
            atomRow(
                atom: result.atom,
                snippet: result.snippet,
                isSelected: index == viewModel.selectedSearchIndex
            )
        }
    }

    // MARK: - Shared Components

    private func atomRow(atom: Atom, snippet: String? = nil, isSelected: Bool) -> some View {
        Button {
            Task { await viewModel.navigate(to: atom.uuid) }
            viewModel.isSearchVisible = false
            viewModel.searchQuery = ""
            viewModel.searchResults = []
        } label: {
            HStack(spacing: DS.space10) {
                typeIcon(for: atom.type)

                VStack(alignment: .leading, spacing: 2) {
                    Text(atom.title ?? "Untitled")
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    if let snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(DS.subheadline)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    } else if let body = atom.body, !body.isEmpty {
                        Text(body.prefix(80))
                            .font(DS.subheadline)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Text(relativeDate(atom.updatedAt))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space12)
            .frame(height: AtomWindowMetrics.searchResultRowHeight)
            .background(isSelected ? DS.glassInputFillFocused.opacity(0.72) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func typeIcon(for type: AtomType) -> some View {
        Image(cosmo: type.cosmoIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AtomWindowViewModel.entityColor(for: type))
            .frame(width: 28, height: 28)
            .background(AtomWindowViewModel.entityColor(for: type).opacity(0.12), in: .rect(cornerRadius: 6))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space12)
            .padding(.top, DS.space10)
            .padding(.bottom, DS.space4)
    }

    // MARK: - Helpers

    private func relativeDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return "" }

        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }
}
