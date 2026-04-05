// CosmoOS/UI/FocusMode/Ideas/AdvancedElementBrowser.swift
// Compact element browser for the advanced outline workspace.
// Loads codex elements, provides search/filter, drag-to-slot, and hover preview.

import SwiftUI
import UniformTypeIdentifiers

struct AdvancedElementBrowser: View {
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
        .frame(width: 260)
        .background(DS.surface, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.border, lineWidth: 0.5)
        )
        .task { await loadElements() }
    }
}

// MARK: - Search

extension AdvancedElementBrowser {
    private var searchField: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            TextField("Search elements...", text: $searchQuery)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
        .padding(.horizontal, DS.space8)
        .padding(.top, DS.space8)
    }
}

// MARK: - Category Tabs

extension AdvancedElementBrowser {
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                categoryPill("All", nil)
                ForEach(CodexElementCategory.allCases) { cat in
                    categoryPill(cat.displayName, cat)
                }
            }
            .padding(.horizontal, DS.space8)
        }
        .padding(.vertical, 6)
    }

    private func categoryPill(_ title: String, _ category: CodexElementCategory?) -> some View {
        let isSelected = selectedCategory == category
        let pillColor = category?.color ?? DS.accent
        return Button {
            withAnimation(ProMotionSprings.snappy) { selectedCategory = category }
        } label: {
            categoryPillLabel(title, isSelected: isSelected, color: pillColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) filter")
    }

    private func categoryPillLabel(_ title: String, isSelected: Bool, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? color : DS.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isSelected ? color.opacity(0.12) : Color.clear,
                in: Capsule()
            )
    }
}

// MARK: - Element List

extension AdvancedElementBrowser {
    @ViewBuilder
    private var elementList: some View {
        if isLoading {
            loadingPlaceholder
        } else if filteredElements.isEmpty {
            emptyState
        } else {
            populatedList
        }
    }

    private var loadingPlaceholder: some View {
        VStack {
            Spacer()
            ProgressView()
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.space6) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("No matching elements")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var populatedList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredElements, id: \.0.uuid) { _, element in
                    BrowserElementRow(element: element)
                }
            }
            .padding(.vertical, DS.space4)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Filtering

extension AdvancedElementBrowser {
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

extension AdvancedElementBrowser {
    private func loadElements() async {
        do {
            try await CodexRepository.shared.loadIfNeeded()
            elements = try await CodexRepository.shared.fetchAllElements()
        } catch {}
        isLoading = false
    }
}

// MARK: - Element Row with Hover Preview

private struct BrowserElementRow: View {
    let element: CodexElement

    @State private var isHovered = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        rowContent
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovered ? DS.surfaceHover : Color.clear)
            .contentShape(Rectangle())
            .draggable(
                CodexDragItem(
                    canonicalName: element.canonicalName,
                    category: element.category
                )
            )
            .onHover { hovering in
                isHovered = hovering
                hoverTask?.cancel()
                if hovering {
                    // 400ms delay before showing popover
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        showPopover = true
                    }
                } else {
                    showPopover = false
                }
            }
            .popover(isPresented: $showPopover, arrowEdge: .leading) {
                BrowserElementPopover(element: element)
            }
            .accessibilityLabel("\(element.canonicalName), \(element.category.displayName)")
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            elementName
            categoryBadge
            Spacer()
            frequencyLabel
        }
    }

    private var elementName: some View {
        Text(element.canonicalName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DS.text)
            .lineLimit(1)
    }

    private var categoryBadge: some View {
        Text(element.category.displayName)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(element.category.color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(element.category.color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var frequencyLabel: some View {
        if let freq = element.frequency, !freq.isEmpty {
            Text(freq)
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)
                .lineLimit(1)
        }
    }
}

// MARK: - Hover Preview Popover

private struct BrowserElementPopover: View {
    let element: CodexElement

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            popoverHeader
            definitionText
            examplesSection
            seeFullButton
        }
        .padding(DS.space12)
        .frame(width: 260)
    }

    private var popoverHeader: some View {
        HStack(spacing: 6) {
            Text(element.canonicalName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.text)
            Text(element.category.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(element.category.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(element.category.color.opacity(0.12), in: Capsule())
        }
    }

    private var definitionText: some View {
        Text(element.definition)
            .font(DS.callout)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(3)
    }

    @ViewBuilder
    private var examplesSection: some View {
        let topExamples = Array(element.examples.prefix(3))
        if !topExamples.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Examples")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                ForEach(topExamples) { example in
                    exampleRow(example)
                }
            }
        }
    }

    private func exampleRow(_ example: CodexExample) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\"\(example.slideText)\"")
                .font(.system(size: 10))
                .foregroundStyle(DS.text)
                .italic()
                .lineLimit(2)
            Text(example.postReference)
                .font(.system(size: 8))
                .foregroundStyle(DS.textMuted)
        }
    }

    private var seeFullButton: some View {
        Button {
            NotificationCenter.default.post(
                name: .navigateToCodexElement,
                object: element.canonicalName
            )
        } label: {
            HStack(spacing: 3) {
                Text("See Full Entry")
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DS.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See full codex entry for \(element.canonicalName)")
    }
}
