import SwiftUI

struct CommandKActionPanel: View {
    let title: String
    let groups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])]
    let errorMessage: String?
    let execute: (CommandKContextualAction) -> Void
    let dismiss: () -> Void

    @Binding var searchQuery: String
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            results
            footer
        }
        .frame(width: 540, height: 520)
        .background(DS.vellum.opacity(0.96), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DS.sepiaBorder, lineWidth: 0.8)
        }
        .shadow(color: DS.inkWash.opacity(0.16), radius: 28, x: 0, y: 18)
        .onAppear {
            clampSelection()
            isSearchFocused = true
        }
        .onChange(of: searchQuery) { _, _ in clampSelection() }
        .onChange(of: flattenedActions.count) { _, _ in clampSelection() }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.return) { executeSelected(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .accessibilityLabel(title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space10) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.gilt)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DS.smallCaps)
                        .tracking(1.4)
                        .foregroundStyle(DS.giltMuted)
                    Text("Search actions for the current selection")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }

                Spacer()

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close actions")
            }

            HStack(spacing: DS.space10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                TextField("Search actions...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(DS.body)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, DS.space12)
            .frame(height: 40)
            .background(DS.vellumDeep.opacity(0.86), in: .rect(cornerRadius: DS.radiusSmall))
            .overlay {
                RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                    .strokeBorder(DS.sepiaSubtle, lineWidth: 0.6)
            }
        }
        .padding(DS.space16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.sepiaBorder).frame(height: 0.5)
        }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space10) {
                    if filteredGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredGroups, id: \.category.rawValue) { group in
                            AtelierOrnamentalSectionLabel(label: group.category.rawValue.uppercased())
                            ForEach(group.actions) { action in
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
                .padding(DS.space16)
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
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.sepiaBorder).frame(height: 0.5)
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
}
