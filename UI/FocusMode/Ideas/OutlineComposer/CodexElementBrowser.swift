// CosmoOS/UI/FocusMode/Ideas/OutlineComposer/CodexElementBrowser.swift
// Browsable, filterable list of codex elements for dragging into outline slides.

import SwiftUI
import UniformTypeIdentifiers

struct CodexElementBrowser: View {
    @State private var selectedCategory: CodexElementCategory? = nil
    @State private var searchQuery = ""
    @State private var elements: [(Atom, CodexElement)] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            searchField
            categoryTabs
            Divider().background(DS.border)
            elementList
        }
        .background(DS.surface)
        .task { await loadElements() }
    }
}

// MARK: - Search

extension CodexElementBrowser {
    private var searchField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            TextField("Search elements...", text: $searchQuery)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
    }
}

// MARK: - Category Tabs

extension CodexElementBrowser {
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryButton("All", nil)
                ForEach(CodexElementCategory.allCases) { cat in
                    categoryButton(cat.displayName, cat)
                }
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
        }
    }

    private func categoryButton(_ title: String, _ category: CodexElementCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(ProMotionSprings.snappy) { selectedCategory = category }
        } label: {
            categoryButtonLabel(title, isSelected: isSelected, color: category?.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) category filter")
    }

    private func categoryButtonLabel(_ title: String, isSelected: Bool, color: Color?) -> some View {
        Text(title)
            .font(DS.caption2)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? (color ?? DS.accent) : DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? (color ?? DS.accent).opacity(DS.opacitySubtle)
                    : Color.clear,
                in: Capsule()
            )
    }
}

// MARK: - Element List

extension CodexElementBrowser {
    @ViewBuilder
    private var elementList: some View {
        if isLoading {
            Spacer()
            ProgressView()
                .frame(maxWidth: .infinity)
            Spacer()
        } else if filteredElements.isEmpty {
            emptyState
        } else {
            populatedList
        }
    }

    private var populatedList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredElements, id: \.0.uuid) { _, element in
                    elementRow(element)
                }
            }
            .padding(.vertical, DS.space6)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("No matching elements")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func elementRow(_ element: CodexElement) -> some View {
        HStack(spacing: 8) {
            Text(element.canonicalName)
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Text(element.category.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(element.category.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(element.category.color.opacity(0.12), in: Capsule())

            Spacer()

            if let freq = element.frequency, !freq.isEmpty {
                Text(freq)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.surfaceElevated.opacity(0.01))
        .contentShape(Rectangle())
        .draggable(
            CodexDragItem(
                canonicalName: element.canonicalName,
                category: element.category
            )
        )
        .accessibilityLabel("\(element.canonicalName), \(element.category.displayName)")
    }
}

// MARK: - Filtering

extension CodexElementBrowser {
    private var filteredElements: [(Atom, CodexElement)] {
        elements.filter { _, el in
            let matchesCategory = selectedCategory == nil || el.category == selectedCategory
            let matchesSearch = searchQuery.isEmpty
                || el.canonicalName.localizedCaseInsensitiveContains(searchQuery)
                || el.definition.localizedCaseInsensitiveContains(searchQuery)
            return matchesCategory && matchesSearch
        }
    }
}

// MARK: - Data Loading

extension CodexElementBrowser {
    private func loadElements() async {
        do {
            try await CodexRepository.shared.loadIfNeeded()
            elements = try await CodexRepository.shared.fetchAllElements()
        } catch {}
        isLoading = false
    }
}
