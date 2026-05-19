import SwiftUI

struct MentionMenu: View {
    let position: CGPoint
    let searchQuery: String
    let onSelect: (MentionEntity) -> Void
    let onDismiss: () -> Void
    var darkMode: Bool = false

    @State private var entities: [MentionEntity] = []
    @State private var selectedIndex = 0
    @State private var isLoading = true
    @State private var appearedRows: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    private let provider = MentionSearchProvider.shared
    private let menuWidth: CGFloat = 280
    private let menuHeight: CGFloat = 320

    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.65) : DS.documentTextSecondary }
    private var textMuted: Color { darkMode ? Color.white.opacity(0.45) : DS.textMuted }

    var body: some View {
        VStack(spacing: 0) {
            header

            CosmoGradientDivider()

            content

            CosmoKeyboardFooter(darkMode: darkMode)
        }
        .frame(width: menuWidth, height: menuHeight, alignment: .top)
        .cosmoMenuChrome(cornerRadius: 18, darkMode: darkMode)
        .position(x: position.x + (menuWidth / 2), y: position.y + (menuHeight / 2))
        .onAppear {
            loadEntities()
        }
        .onChange(of: searchQuery) { _, _ in
            appearedRows.removeAll()
            loadEntities()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onKeyPress(.upArrow) { handleUpArrow() }
        .onKeyPress(.downArrow) { handleDownArrow() }
        .onKeyPress(.return) { handleReturn() }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.delete) { handleDelete() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 30, height: 30)

                Image(systemName: "at")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Link Item")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textPrimary)

                Text(searchQuery.isEmpty ? "Recent and relevant items" : "Results for @\(searchQuery)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !isLoading {
                Text("\(entities.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DS.accentSoft, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if entities.isEmpty {
            emptyView
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(entities.enumerated()), id: \.element.id) { index, entity in
                        mentionRowView(index: index, entity: entity)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .background(darkMode ? DS.bg : Color.clear)
        }
    }

    @ViewBuilder
    private func mentionRowView(index: Int, entity: MentionEntity) -> some View {
        MentionRow(
            entity: entity,
            isSelected: index == selectedIndex,
            hasAppeared: appearedRows.contains(entity.id),
            darkMode: darkMode
        )
        .id(index)
        .onTapGesture {
            CosmicHaptics.shared.play(.selection)
            onSelect(entity)
        }
        .onHover { hovering in
            if hovering {
                selectedIndex = index
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.015)) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    _ = appearedRows.insert(entity.id)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    CosmicShimmer(entityColor: DS.accent, cornerRadius: 10)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 6) {
                        CosmicShimmer(entityColor: DS.accent, cornerRadius: 4)
                            .frame(width: 140, height: 14)
                        CosmicShimmer(entityColor: DS.accent, cornerRadius: 4)
                            .frame(width: 80, height: 10)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 14)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(textMuted)

            Text("No items found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textPrimary)

            Text("Try a different name or keyword.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadEntities() {
        searchTask?.cancel()
        isLoading = true
        selectedIndex = 0

        searchTask = Task {
            let results = await provider.search(query: searchQuery)
            let mapped = results.map { result in
                MentionEntity(
                    entityID: result.atomID,
                    uuid: result.atomUUID,
                    type: result.entityType,
                    title: result.title,
                    subtitle: result.subtitle,
                    typeLabel: result.typeLabel,
                    updatedAt: result.updatedAt
                )
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                entities = mapped
                isLoading = false
            }
        }
    }

    private func handleUpArrow() -> KeyPress.Result {
        selectedIndex = max(0, selectedIndex - 1)
        CosmicHaptics.shared.play(.threshold)
        return .handled
    }

    private func handleDownArrow() -> KeyPress.Result {
        selectedIndex = min(max(0, entities.count - 1), selectedIndex + 1)
        CosmicHaptics.shared.play(.threshold)
        return .handled
    }

    private func handleReturn() -> KeyPress.Result {
        guard let entity = entities[safe: selectedIndex] else { return .handled }
        CosmicHaptics.shared.play(.selection)
        onSelect(entity)
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        CosmicHaptics.shared.play(.selection)
        onDismiss()
        return .handled
    }

    private func handleDelete() -> KeyPress.Result {
        if searchQuery.isEmpty {
            onDismiss()
            return .handled
        }
        return .ignored
    }
}

struct MentionRow: View {
    let entity: MentionEntity
    let isSelected: Bool
    let hasAppeared: Bool
    var darkMode: Bool = false

    private var entityColor: Color {
        CosmoMentionColors.color(for: entity.type)
    }

    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.65) : DS.documentTextSecondary }
    private var rowFill: Color {
        isSelected ? entityColor.opacity(darkMode ? 0.18 : 0.12) : .clear
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(entityColor.opacity(isSelected ? 0.16 : 0.12))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: entity.type.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(entityColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(entity.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)

                if let subtitle = entity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(entity.typeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(textSecondary)
                .lineLimit(1)

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entityColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? entityColor.opacity(0.22) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -12)
        .blur(radius: hasAppeared ? 0 : 2)
        .scaleEffect(x: hasAppeared ? 1 : 0.98, y: 1, anchor: .leading)
    }
}
