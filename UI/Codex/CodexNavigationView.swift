// CosmoOS/UI/Codex/CodexNavigationView.swift
// Top-level Codex browser — searchable grid of all Content Physics elements and walkthroughs.
// April 2026 — WP3 Codex Navigation + Premium Redesign

import SwiftUI

// MARK: - Navigation Wrapper Types

struct CodexElementEntry: Identifiable, Hashable {
    let atom: Atom
    let element: CodexElement
    var id: String { element.canonicalName }

    func hash(into hasher: inout Hasher) { hasher.combine(atom.uuid) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.atom.uuid == rhs.atom.uuid }
}

struct CodexWalkthroughEntry: Identifiable, Hashable {
    let atom: Atom
    let walkthrough: CodexWalkthrough
    var id: String { walkthrough.postReference }

    func hash(into hasher: inout Hasher) { hasher.combine(atom.uuid) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.atom.uuid == rhs.atom.uuid }
}

enum CodexRoute: Hashable {
    case element(CodexElementEntry)
    case walkthrough(CodexWalkthroughEntry)
}

// MARK: - Navigation View

struct CodexNavigationView: View {
    @State private var searchQuery = ""
    @State private var selectedCategory: CodexElementCategory? = nil
    @State private var elements: [CodexElementEntry] = []
    @State private var walkthroughs: [CodexWalkthroughEntry] = []
    @State private var isLoading = true
    @State private var showGrid = true
    @State private var navigationPath = NavigationPath()
    @State private var isImporting = false
    @State private var importResult: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                CodexHeroHeader(
                    searchQuery: $searchQuery,
                    elementCount: filteredElements.count,
                    categoryCount: CodexElementCategory.allCases.count,
                    isImporting: isImporting,
                    onImport: importCodex,
                    showGrid: $showGrid
                )
                CodexCategoryDivider()
                categoryTabBar
                contentArea
            }
            .background(DS.bg)
            .navigationDestination(for: CodexRoute.self) { route in
                routeDestination(route)
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCodexElement)) { notification in
            handleElementNavigation(notification)
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: CodexRoute) -> some View {
        switch route {
        case .element(let entry):
            CodexElementDetailView(atom: entry.atom, element: entry.element)
        case .walkthrough(let entry):
            CodexWalkthroughDetailView(atom: entry.atom, walkthrough: entry.walkthrough)
        }
    }

    // MARK: - Category Tabs

    private var categoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryTab(label: "All", icon: "square.grid.3x3", category: nil, count: elements.count)
                ForEach(sortedCategories) { cat in
                    categoryTab(label: cat.displayName, icon: cat.icon, category: cat, count: countForCategory(cat))
                }
            }
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space8)
        }
        .background(DS.bg)
    }

    private var sortedCategories: [CodexElementCategory] {
        CodexElementCategory.allCases.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func countForCategory(_ cat: CodexElementCategory) -> Int {
        elements.filter { $0.element.category == cat }.count
    }

    private func categoryTab(label: String, icon: String, category: CodexElementCategory?, count: Int) -> some View {
        let isSelected = selectedCategory == category
        let color = category?.color ?? DS.accent
        return Button {
            withAnimation(ProMotionSprings.snappy) { selectedCategory = category }
        } label: {
            CodexCategoryTabLabel(label: label, icon: icon, count: count, isSelected: isSelected, color: color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count) elements")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            loadingPlaceholder
        } else if filteredElements.isEmpty && filteredWalkthroughs.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                if selectedCategory == nil && searchQuery.isEmpty {
                    groupedElementSections
                } else {
                    flatElementGrid
                }
                if !filteredWalkthroughs.isEmpty { walkthroughSection }
            }
            .padding(DS.space24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Grouped Layout

    private var groupedElementSections: some View {
        ForEach(sortedCategories) { category in
            let categoryElements = filteredElements.filter { $0.element.category == category }
            if !categoryElements.isEmpty {
                VStack(alignment: .leading, spacing: DS.space12) {
                    CodexCategorySectionHeader(category: category, count: categoryElements.count)
                    CodexCategorySectionDivider(color: category.color)
                    categoryElementGrid(categoryElements)
                }
            }
        }
    }

    private func categoryElementGrid(_ entries: [CodexElementEntry]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DS.space16)],
            spacing: DS.space16
        ) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                CodexElementCardView(entry: entry, index: index) {
                    navigationPath.append(CodexRoute.element(entry))
                }
            }
        }
    }

    // MARK: - Flat Grid (filtered)

    private var flatElementGrid: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            if let cat = selectedCategory {
                CodexCategorySectionHeader(category: cat, count: filteredElements.count)
                CodexCategorySectionDivider(color: cat.color)
            } else {
                Text("SEARCH RESULTS")
                    .dsSectionLabel()
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DS.space16)],
                spacing: DS.space16
            ) {
                ForEach(Array(filteredElements.enumerated()), id: \.element.id) { index, entry in
                    CodexElementCardView(entry: entry, index: index) {
                        navigationPath.append(CodexRoute.element(entry))
                    }
                }
            }
        }
    }

    // MARK: - Walkthrough Section

    private var walkthroughSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("WALKTHROUGHS")
                .dsSectionLabel()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: DS.space16)],
                spacing: DS.space16
            ) {
                ForEach(Array(filteredWalkthroughs.enumerated()), id: \.element.id) { index, entry in
                    CodexWalkthroughCardView(entry: entry, index: index) {
                        navigationPath.append(CodexRoute.walkthrough(entry))
                    }
                }
            }
        }
    }

    // MARK: - Loading & Empty

    private var loadingPlaceholder: some View {
        VStack(spacing: DS.space12) {
            ProgressView()
            Text("Loading Codex...")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        CodexEmptyState(
            searchQuery: searchQuery,
            isImporting: isImporting,
            importResult: importResult,
            onImport: importCodex
        )
    }

    // MARK: - Import

    private func importCodex() {
        isImporting = true
        importResult = nil
        Task {
            do {
                let importer = CodexImporter()
                let result = try await importer.importCodex()
                var parts: [String] = []
                if result.cleaned > 0 { parts.append("\(result.cleaned) cleaned") }
                if result.elementsCreated > 0 { parts.append("\(result.elementsCreated) elements") }
                if result.walkthroughsCreated > 0 { parts.append("\(result.walkthroughsCreated) walkthroughs") }
                if result.skipped > 0 { parts.append("\(result.skipped) skipped") }
                importResult = parts.joined(separator: ", ")
                await loadData()
            } catch {
                importResult = "Error: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    // MARK: - Filtering

    private var filteredElements: [CodexElementEntry] {
        var result = elements
        if let cat = selectedCategory {
            result = result.filter { $0.element.category == cat }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { entry in
                entry.element.canonicalName.lowercased().contains(q)
                || entry.element.definition.lowercased().contains(q)
                || entry.element.variants.contains { $0.lowercased().contains(q) }
            }
        }
        return result.sorted { $0.element.category.sortOrder < $1.element.category.sortOrder }
    }

    private var filteredWalkthroughs: [CodexWalkthroughEntry] {
        guard selectedCategory == nil else { return [] }
        if searchQuery.isEmpty { return walkthroughs }
        let q = searchQuery.lowercased()
        return walkthroughs.filter { entry in
            entry.walkthrough.postTitle.lowercased().contains(q)
            || (entry.walkthrough.creatorName?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let repo = CodexRepository.shared
        do {
            try await repo.loadIfNeeded()
            let rawElements = try await repo.fetchAllElements()
            elements = rawElements.map { CodexElementEntry(atom: $0.0, element: $0.1) }
            let rawWalkthroughs = try await repo.fetchAllWalkthroughs()
            walkthroughs = rawWalkthroughs.map { CodexWalkthroughEntry(atom: $0.0, walkthrough: $0.1) }
        } catch {
            print("CodexNavigationView: failed to load codex data: \(error)")
        }
        isLoading = false
    }

    private func handleElementNavigation(_ notification: Notification) {
        guard let name = notification.userInfo?["canonicalName"] as? String else { return }
        if let entry = elements.first(where: {
            $0.element.canonicalName.lowercased() == name.lowercased()
        }) {
            navigationPath.append(CodexRoute.element(entry))
        }
    }
}

// MARK: - Category Tab Label

private struct CodexCategoryTabLabel: View {
    let label: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let color: Color
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(label)
                .font(DS.caption)
            Text("\(count)")
                .font(DS.caption2)
                .foregroundStyle(isSelected ? .white.opacity(0.7) : DS.textMuted)
        }
        .foregroundStyle(isSelected ? .white : (isHovered ? color : DS.textSecondary))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(tabBackgroundColor, in: Capsule())
        .overlay {
            if !isSelected {
                Capsule().stroke(isHovered ? color.opacity(0.2) : DS.border, lineWidth: 1)
            }
        }
        .scaleEffect(isHovered && !isSelected ? 1.03 : 1.0)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var tabBackgroundColor: Color {
        if isSelected { return color }
        if isHovered { return color.opacity(0.08) }
        return DS.surface
    }
}

// MARK: - Element Card

struct CodexElementCardView: View {
    let entry: CodexElementEntry
    let index: Int
    let onTap: () -> Void
    @State private var appeared = false

    private var categoryColor: Color { entry.element.category.color }

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(CodexCardButtonStyle())
        .codexHover(accent: categoryColor)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(ProMotionSprings.staggered(index: index)) {
                appeared = true
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            cardHeader
            CodexFrequencyIndicator(frequency: entry.element.frequency, color: categoryColor, mode: .compact)
            definitionText
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .overlay(alignment: .leading) { categoryAccentBar }
    }

    private var cardHeader: some View {
        HStack {
            Text(entry.element.canonicalName)
                .font(DS.title3)
                .fontWeight(.bold)
                .foregroundStyle(DS.text)
                .lineLimit(1)
            Spacer()
            categoryBadge
        }
    }

    private var categoryBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: entry.element.category.icon)
                .font(.system(size: 9))
                .accessibilityHidden(true)
            Text(entry.element.category.displayName)
                .font(DS.caption2)
        }
        .foregroundStyle(categoryColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(categoryColor.opacity(0.12), in: Capsule())
    }

    private var definitionText: some View {
        Text(entry.element.definition)
            .font(DS.callout)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(2)
    }

    private var cardBackground: some View {
        ZStack {
            DS.surfaceElevated
            LinearGradient(
                colors: [categoryColor.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private var categoryAccentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(categoryColor)
            .frame(width: 3)
            .padding(.vertical, 8)
            .padding(.leading, 1)
    }
}

// MARK: - Card Button Style

private struct CodexCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(ProMotionSprings.press, value: configuration.isPressed)
    }
}

// MARK: - Walkthrough Card

struct CodexWalkthroughCardView: View {
    let entry: CodexWalkthroughEntry
    let index: Int
    let onTap: () -> Void
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            walkthroughContent
        }
        .buttonStyle(CodexCardButtonStyle())
        .codexHover(accent: CodexElementCategory.dominantFrame.color)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(ProMotionSprings.staggered(index: index)) {
                appeared = true
            }
        }
    }

    private var walkthroughContent: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            titleRow
            creatorRow
            tagRow
            slideCount
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CodexElementCategory.dominantFrame.color)
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 1)
        }
    }

    private var titleRow: some View {
        Text(entry.walkthrough.postTitle)
            .font(DS.title3)
            .fontWeight(.bold)
            .foregroundStyle(DS.text)
            .lineLimit(1)
    }

    @ViewBuilder
    private var creatorRow: some View {
        if let creator = entry.walkthrough.creatorName {
            Text(creator)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var tagRow: some View {
        HStack(spacing: 6) {
            if let frame = entry.walkthrough.dominantFrame {
                CodexConceptTag(name: frame, color: CodexElementCategory.dominantFrame.color)
            }
            if let arc = entry.walkthrough.arcShape {
                CodexConceptTag(name: arc, color: CodexElementCategory.arcShape.color)
            }
        }
    }

    private var slideCount: some View {
        Text("\(entry.walkthrough.slides.count) slides")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
    }
}

// MARK: - Empty State

private struct CodexEmptyState: View {
    let searchQuery: String
    let isImporting: Bool
    let importResult: String?
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: DS.space16) {
            emptyIcon
            if !searchQuery.isEmpty {
                searchEmptyContent
            } else {
                importEmptyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: some View {
        Image(systemName: "atom")
            .font(.system(size: 40))
            .foregroundStyle(DS.textMuted)
            .accessibilityHidden(true)
    }

    private var searchEmptyContent: some View {
        VStack(spacing: DS.space4) {
            Text("No elements found")
                .font(DS.title3)
                .foregroundStyle(DS.textSecondary)
            Text("Try a different search term")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var importEmptyContent: some View {
        VStack(spacing: DS.space12) {
            Text("Codex not imported yet")
                .font(DS.title3)
                .foregroundStyle(DS.textSecondary)
            Text("Import the Exemplar Codex to populate the periodic table with 200+ content physics elements.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            importActionArea
        }
    }

    @ViewBuilder
    private var importActionArea: some View {
        if isImporting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Importing codex elements...")
                    .font(DS.callout)
                    .foregroundStyle(DS.accent)
            }
        } else {
            Button(action: onImport) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .accessibilityHidden(true)
                    Text("Import Codex")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(DS.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }

        if let result = importResult {
            Text(result)
                .font(DS.caption)
                .foregroundStyle(result.contains("Error") ? DS.red : DS.green)
                .padding(.top, 4)
        }
    }
}
