import SwiftUI

struct CommandKActionPanel: View {
    private static let menuWidth: CGFloat = 280
    private static let menuHeight: CGFloat = 340

    let title: String
    let groups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])]
    let errorMessage: String?
    let execute: (CommandKContextualAction) -> Void
    let dismiss: () -> Void

    @Binding var searchQuery: String
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    @State private var searchFocusTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            CosmoGradientDivider()
            results
            footer
        }
        .frame(width: Self.menuWidth, height: Self.menuHeight, alignment: .top)
        .cosmoMenuChrome(cornerRadius: 18)
        .onAppear {
            clampSelection()
            requestSearchFocus()
        }
        .onDisappear { searchFocusTask?.cancel() }
        .onChange(of: searchQuery) { _, _ in clampSelection() }
        .onChange(of: flattenedActions.count) { _, _ in clampSelection() }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.return) { executeSelected(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .accessibilityLabel(title)
    }

    private var searchField: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.textMuted)

            TextField("Search actions…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.return) { executeSelected(); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close actions")
        }
        .padding(DS.space12)
        .background(DS.glassInputFill.opacity(0.34))
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space4) {
                    if filteredGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredGroups, id: \.category.rawValue) { group in
                            CommandKSectionLabel(label: group.category.rawValue.uppercased())
                            ForEach(group.actions, id: \.uniqueActionId) { action in
                                CommandKActionPanelRow(
                                    action: action,
                                    isSelected: selectedAction?.id == action.id,
                                    perform: { executeIfEnabled(action) }
                                )
                                .id(action.id.rawValue)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.space10)
                .padding(.vertical, DS.space8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedIndex) { _, _ in
                guard let id = selectedAction?.id.rawValue else { return }
                withAnimation(ProMotionSprings.snappy) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.space8) {
            if let errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.red)
                Text(errorMessage)
                    .lineLimit(1)
                    .foregroundStyle(DS.red)
            } else {
                CortexKeycap(symbol: "return")
                Text("Run")
                CortexKeycap(symbol: "arrow.up")
                CortexKeycap(symbol: "arrow.down")
                Text("Move")
                Spacer()
                Text("\(flattenedActions.count) actions")
                    .foregroundStyle(DS.textMuted)
            }
        }
        .font(DS.caption)
        .foregroundStyle(DS.inkFaded)
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space8)
        .background(DS.glassInputFill.opacity(0.24))
        .overlay(alignment: .top) {
            Rectangle().fill(DS.commandChromeSeparatorStrong).frame(height: 0.5)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.giltMuted)
            Text("No matching actions")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private var filteredGroups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let actions = group.actions.filter { actionMatches($0, query: query, category: group.category) }
            return actions.isEmpty ? nil : (group.category, actions)
        }
    }

    private var flattenedActions: [CommandKContextualAction] {
        filteredGroups.flatMap(\.actions)
    }

    private var selectedAction: CommandKContextualAction? {
        flattenedActions[safe: selectedIndex]
    }

    private func actionMatches(
        _ action: CommandKContextualAction,
        query: String,
        category: CommandKActionCategory
    ) -> Bool {
        action.title.lowercased().contains(query)
            || (action.subtitle?.lowercased().contains(query) ?? false)
            || category.rawValue.lowercased().contains(query)
    }

    private func moveSelection(_ delta: Int) {
        guard !flattenedActions.isEmpty else { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex + delta, 0), flattenedActions.count - 1)
    }

    private func executeSelected() {
        guard let action = selectedAction else { return }
        executeIfEnabled(action)
    }

    private func executeIfEnabled(_ action: CommandKContextualAction) {
        guard action.availability.isEnabled else { return }
        execute(action)
    }

    private func clampSelection() {
        let maxIndex = max(flattenedActions.count - 1, 0)
        selectedIndex = min(max(selectedIndex, 0), maxIndex)
    }

    /// The panel is inserted with an animated transition, which can drop the
    /// first FocusState write before the field is attached — leaving arrow/return
    /// keys with the main search field instead of this panel.
    private func requestSearchFocus() {
        searchFocusTask?.cancel()
        isSearchFocused = true
        searchFocusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            isSearchFocused = true

            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            isSearchFocused = true
        }
    }
}
