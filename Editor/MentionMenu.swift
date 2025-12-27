// CosmoOS/Editor/MentionMenu.swift
// @mention autocomplete with entity search
// Premium "Cosmic Glass" styling from Cosmo design system
// December 2025 - Staggered animations, symbol effects, haptic feedback

import SwiftUI
import GRDB

struct MentionMenu: View {
    let position: CGPoint
    let searchQuery: String
    let onSelect: (MentionEntity) -> Void
    let onDismiss: () -> Void
    var darkMode: Bool = false  // Dark glass mode for Thinkspace blocks

    @State private var entities: [MentionEntity] = []
    @State private var selectedIndex = 0
    @State private var isLoading = true
    @State private var appearedRows: Set<Int64> = []
    @State private var menuAppeared = false
    @State private var headerIconBounce = false

    private let database = CosmoDatabase.shared
    private let menuWidth: CGFloat = 300
    private let menuHeight: CGFloat = 290

    // MARK: - Dark Mode Colors
    private var bgColor: Color { darkMode ? CosmoColors.thinkspaceTertiary : CosmoColors.softWhite }
    private var textPrimary: Color { darkMode ? .white : CosmoColors.textPrimary }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.6) : CosmoColors.textSecondary }
    private var textTertiary: Color { darkMode ? Color.white.opacity(0.4) : CosmoColors.textTertiary }
    private var accentColor: Color { darkMode ? CosmoColors.thinkspacePurple : CosmoColors.skyBlue }
    private var borderColor: Color { darkMode ? Color.white.opacity(0.1) : CosmoColors.glassGrey.opacity(0.5) }
    private var shadowColor: Color { darkMode ? CosmoColors.thinkspacePurple.opacity(0.3) : .black.opacity(0.10) }

    var body: some View {
        menuContent
            .frame(width: menuWidth, height: menuHeight, alignment: .top)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(menuBorder)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            .shadow(color: shadowColor, radius: 16, y: 6)
            .shadow(color: accentColor.opacity(0.15), radius: 24, y: 8)
            .withAccentSeam(accentColor, position: .leading)
            .scaleEffect(menuAppeared ? 1 : 0.95)
            .opacity(menuAppeared ? 1 : 0)
            .blur(radius: menuAppeared ? 0 : 4)
            .position(x: position.x + (menuWidth / 2), y: position.y + (menuHeight / 2))
            .onAppear(perform: handleAppear)
            .onChange(of: searchQuery) { handleSearchChange() }
            .onKeyPress(.upArrow) { handleUpArrow() }
            .onKeyPress(.downArrow) { handleDownArrow() }
            .onKeyPress(.return) { handleReturn() }
            .onKeyPress(.escape) { handleEscape() }
            .onKeyPress(.delete) { handleDelete() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var menuContent: some View {
        VStack(spacing: 0) {
            headerView
            dividerView
            contentView
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Image(systemName: "at")
                .foregroundColor(accentColor)
                .symbolEffect(.bounce, value: headerIconBounce)

            Text(searchQuery.isEmpty ? "Search entities..." : "Results for \"\(searchQuery)\"")
                .font(.system(size: 13))
                .foregroundColor(textSecondary)

            Spacer()

            if !isLoading && !entities.isEmpty {
                resultCountBadge
            }
        }
        .padding(12)
        .background(bgColor)
    }

    private var resultCountBadge: some View {
        Text("\(entities.count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accentColor.opacity(0.12))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
    }

    private var dividerView: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [accentColor.opacity(0.4), borderColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            loadingView
        } else if entities.isEmpty {
            emptyView
        } else {
            entityListView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                shimmerRow
            }
        }
        .frame(maxWidth: .infinity)
        .background(bgColor)
    }

    private var shimmerRow: some View {
        HStack(spacing: 12) {
            CosmicShimmer(entityColor: accentColor, cornerRadius: 8)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                CosmicShimmer(entityColor: accentColor, cornerRadius: 4)
                    .frame(height: 14)
                    .frame(maxWidth: 120)
                CosmicShimmer(entityColor: accentColor, cornerRadius: 4)
                    .frame(height: 10)
                    .frame(maxWidth: 80)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(textTertiary)
                .symbolEffect(.pulse)
            Text("No entities found")
                .font(.system(size: 13))
                .foregroundColor(textSecondary)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .background(bgColor)
    }

    private var entityListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entities.enumerated()), id: \.element.id) { index, entity in
                        entityRow(entity: entity, index: index)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 250)
            .background(bgColor)
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(ProMotionSprings.snappy) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
                CosmicHaptics.shared.play(.threshold)
            }
        }
    }

    private func entityRow(entity: MentionEntity, index: Int) -> some View {
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
        .onHover { isHovered in
            if isHovered {
                if selectedIndex != index {
                    CosmicHaptics.shared.play(.threshold)
                }
                selectedIndex = index
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.03) {
                withAnimation(ProMotionSprings.cardEntrance) {
                    _ = appearedRows.insert(entity.id)
                }
            }
        }
    }

    private var menuBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(
                LinearGradient(
                    colors: [accentColor.opacity(0.4), borderColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    // MARK: - Event Handlers

    private func handleAppear() {
        CosmicHaptics.shared.play(.menuAppear)
        withAnimation(ProMotionSprings.bouncy) {
            menuAppeared = true
            headerIconBounce.toggle()
        }
        loadEntities()
    }

    private func handleSearchChange() {
        appearedRows.removeAll()
        loadEntities()
    }

    private func handleUpArrow() -> KeyPress.Result {
        selectedIndex = max(0, selectedIndex - 1)
        return .handled
    }

    private func handleDownArrow() -> KeyPress.Result {
        selectedIndex = min(entities.count - 1, selectedIndex + 1)
        return .handled
    }

    private func handleReturn() -> KeyPress.Result {
        if let entity = entities[safe: selectedIndex] {
            CosmicHaptics.shared.play(.selection)
            onSelect(entity)
        }
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

    // MARK: - Load Entities
    private func loadEntities() {
        isLoading = true
        selectedIndex = 0

        Task {
            var results: [MentionEntity] = []

            // Search ideas
            let ideas = try? await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(
                        searchQuery.isEmpty ? Column("id") > 0 :
                        Column("title").like("%\(searchQuery)%") ||
                        Column("body").like("%\(searchQuery)%")
                    )
                    .order(Column("updated_at").desc)
                    .limit(5)
                    .fetchAll(db)
                    .map { IdeaWrapper(atom: $0) }
            }

            results += (ideas ?? []).map { idea in
                MentionEntity(
                    id: idea.id ?? -1,
                    uuid: idea.uuid,
                    type: .idea,
                    title: idea.title ?? "Untitled",
                    subtitle: String(idea.content.prefix(50))
                )
            }

            // Search tasks
            let tasks = try? await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.task.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(
                        searchQuery.isEmpty ? Column("id") > 0 :
                        Column("title").like("%\(searchQuery)%")
                    )
                    .order(Column("updated_at").desc)
                    .limit(3)
                    .fetchAll(db)
                    .map { TaskWrapper(atom: $0) }
            }

            results += (tasks ?? []).map { task in
                MentionEntity(
                    id: task.id ?? -1,
                    uuid: task.uuid,
                    type: .task,
                    title: task.title ?? "Untitled",
                    subtitle: task.status
                )
            }

            // Search content
            let content = try? await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.content.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(
                        searchQuery.isEmpty ? Column("id") > 0 :
                        Column("title").like("%\(searchQuery)%")
                    )
                    .order(Column("updated_at").desc)
                    .limit(3)
                    .fetchAll(db)
                    .map { ContentWrapper(atom: $0) }
            }

            results += (content ?? []).map { item in
                MentionEntity(
                    id: item.id ?? -1,
                    uuid: item.uuid,
                    type: .content,
                    title: item.title ?? "Untitled",
                    subtitle: item.status
                )
            }

            // Search projects
            let projects = try? await database.asyncRead { db in
                try Atom
                    .filter(Column("type") == AtomType.project.rawValue)
                    .filter(Column("is_deleted") == false)
                    .filter(
                        searchQuery.isEmpty ? Column("id") > 0 :
                        Column("title").like("%\(searchQuery)%")
                    )
                    .order(Column("updated_at").desc)
                    .limit(2)
                    .fetchAll(db)
                    .map { ProjectWrapper(atom: $0) }
            }

            results += (projects ?? []).map { project in
                MentionEntity(
                    id: project.id ?? -1,
                    uuid: project.uuid,
                    type: .project,
                    title: project.title ?? "Untitled",
                    subtitle: project.status
                )
            }

            await MainActor.run {
                entities = results
                isLoading = false
            }
        }
    }
}

// MARK: - Mention Row
/// Premium row with staggered entrance and symbol effects
struct MentionRow: View {
    let entity: MentionEntity
    let isSelected: Bool
    let hasAppeared: Bool
    var darkMode: Bool = false

    @State private var iconBounce = false

    // Get entity color from CosmoMentionColors for proper contrast
    private var entityColor: Color {
        CosmoMentionColors.color(for: entity.type)
    }

    // Dark mode colors
    private var textPrimary: Color { darkMode ? .white : CosmoColors.textPrimary }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.6) : CosmoColors.textSecondary }

    var body: some View {
        HStack(spacing: 12) {
            // Entity type icon - uses entity-specific color with symbol effect
            Image(systemName: entity.type.icon)
                .font(.system(size: 16))
                .foregroundColor(entityColor)
                .symbolEffect(.bounce, value: iconBounce)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(entityColor.opacity(isSelected ? 0.2 : 0.12))
                        .shadow(
                            color: entityColor.opacity(isSelected ? 0.3 : 0),
                            radius: isSelected ? 6 : 0,
                            y: isSelected ? 2 : 0
                        )
                )

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(textPrimary)
                    .lineLimit(1)

                if let subtitle = entity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Type badge with entity color
            Text(entity.type.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(entityColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entityColor.opacity(0.12))
                .cornerRadius(4)

            // Selection indicator
            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(entityColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? entityColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        // Staggered entrance animation
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -12)
        .blur(radius: hasAppeared ? 0 : 2)
        .scaleEffect(x: hasAppeared ? 1 : 0.98, y: 1, anchor: .leading)
        .animation(ProMotionSprings.snappy, value: isSelected)
        .onChange(of: isSelected) { _, selected in
            if selected {
                iconBounce.toggle()
            }
        }
    }
}
