// CosmoOS/UI/Codex/CodexNavigationView.swift
// Top-level Codex browser — searchable grid of all Content Physics elements and walkthroughs.
// April 2026 — WP3 Codex Navigation

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
                headerBar
                Divider()
                categoryTabBar
                Divider()
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

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: DS.space16) {
            Text("Content Physics Codex")
                .font(DS.pageTitle)
                .foregroundStyle(DS.text)

            Spacer()

            searchField

            // Re-import button
            Button {
                importCodex()
            } label: {
                HStack(spacing: 4) {
                    if isImporting {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text(isImporting ? "Importing..." : "Import")
                }
                .font(DS.caption)
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.accent.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isImporting)

            countBadge

            gridListToggle
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(DS.textMuted)
            TextField("Search elements...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(DS.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 1)
        )
        .frame(width: 260)
    }

    private var countBadge: some View {
        Text("\(filteredElements.count) elements")
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.surface, in: Capsule())
    }

    private var gridListToggle: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { showGrid.toggle() }
        } label: {
            Image(systemName: showGrid ? "square.grid.2x2" : "list.bullet")
                .font(.system(size: 14))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 32, height: 32)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showGrid ? "Switch to list view" : "Switch to grid view")
    }

    // MARK: - Category Tabs

    private var categoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryTab(label: "All", category: nil)

                ForEach(sortedCategories) { cat in
                    categoryTab(label: cat.displayName, category: cat)
                }
            }
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space8)
        }
    }

    private var sortedCategories: [CodexElementCategory] {
        CodexElementCategory.allCases.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func categoryTab(label: String, category: CodexElementCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(ProMotionSprings.snappy) { selectedCategory = category }
        } label: {
            categoryTabLabel(label: label, isSelected: isSelected, color: category?.color ?? DS.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func categoryTabLabel(label: String, isSelected: Bool, color: Color) -> some View {
        Text(label)
            .font(DS.caption)
            .foregroundStyle(isSelected ? .white : DS.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                isSelected ? AnyShapeStyle(color) : AnyShapeStyle(DS.surface),
                in: Capsule()
            )
            .overlay(
                isSelected ? nil : Capsule().stroke(DS.border, lineWidth: 1)
            )
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
                if !filteredElements.isEmpty { elementGridSection }
                if !filteredWalkthroughs.isEmpty { walkthroughSection }
            }
            .padding(DS.space24)
        }
        .scrollIndicators(.hidden)
    }

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
        VStack(spacing: DS.space16) {
            Image(systemName: "atom")
                .font(.system(size: 40))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            if !searchQuery.isEmpty {
                Text("No elements found")
                    .font(DS.title3)
                    .foregroundStyle(DS.textSecondary)
                Text("Try a different search term")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
            } else {
                Text("Codex not imported yet")
                    .font(DS.title3)
                    .foregroundStyle(DS.textSecondary)
                Text("Import the Exemplar Codex to populate the periodic table with 200+ content physics elements.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                if isImporting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Importing codex elements...")
                            .font(DS.callout)
                            .foregroundStyle(DS.accent)
                    }
                } else {
                    Button {
                        importCodex()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
                // Reload data
                await loadData()
            } catch {
                importResult = "Error: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    // MARK: - Element Grid

    private var elementGridSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("ELEMENTS")
                .dsSectionLabel()

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

    // MARK: - Element Navigation Handler

    private func handleElementNavigation(_ notification: Notification) {
        guard let name = notification.userInfo?["canonicalName"] as? String else { return }
        if let entry = elements.first(where: {
            $0.element.canonicalName.lowercased() == name.lowercased()
        }) {
            navigationPath.append(CodexRoute.element(entry))
        }
    }
}

// MARK: - Element Card

struct CodexElementCardView: View {
    let entry: CodexElementEntry
    let index: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .animation(
            ProMotionSprings.staggered(index: index),
            value: entry.element.canonicalName
        )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            cardHeader
            frequencyLabel
            definitionText
        }
        .padding(DS.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var cardHeader: some View {
        HStack {
            Text(entry.element.canonicalName)
                .font(DS.title3)
                .fontWeight(.bold)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            Text(entry.element.category.displayName)
                .font(DS.caption2)
                .foregroundStyle(entry.element.category.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(entry.element.category.color.opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private var frequencyLabel: some View {
        if let freq = entry.element.frequency {
            Text(freq)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var definitionText: some View {
        Text(entry.element.definition)
            .font(DS.callout)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(2)
    }
}

// MARK: - Walkthrough Card

struct CodexWalkthroughCardView: View {
    let entry: CodexWalkthroughEntry
    let index: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            walkthroughContent
        }
        .buttonStyle(.plain)
        .animation(
            ProMotionSprings.staggered(index: index),
            value: entry.walkthrough.postReference
        )
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
        .dsCard()
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
