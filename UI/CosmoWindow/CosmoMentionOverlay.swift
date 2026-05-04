// CosmoOS/UI/CosmoWindow/CosmoMentionOverlay.swift
// Premium @mention overlay for injecting atoms as context into Cosmo chat
// March 2026

import SwiftUI

struct CosmoMentionOverlay: View {
    @Binding var isVisible: Bool
    @Binding var searchText: String
    var onSelect: (Atom) -> Void
    var onDismiss: () -> Void

    @State private var selectedCategory: AtomType? = nil
    @State private var results: [Atom] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var hoveredResultId: String? = nil

    private static let swipeFilterTag = AtomType.creator

    private let categories: [(type: AtomType, label: String, icon: String)] = [
        (.content, "Content", "doc.richtext"),
        (.research, "Research", "magnifyingglass"),
        (swipeFilterTag, "Swipe", "bookmark.fill"),
        (.idea, "Idea", "lightbulb"),
        (.connection, "Connection", "link"),
        (.note, "Note", "note.text"),
        (.clientProfile, "Profile", "person.crop.circle"),
        (.task, "Task", "checkmark.circle")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 1)

            categoryRow
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Rectangle()
                .fill(DS.glassBorder)
                .frame(height: 1)

            resultsSection
        }
        .frame(maxHeight: 420)
        .cosmoGlassPanel(
            sceneMaterial: .neutral,
            role: .floatingAssistant,
            cornerRadius: 18
        )
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
        .onChange(of: searchText) { newValue in
            performSearch(newValue)
        }
        .onChange(of: selectedCategory) { _ in
            performSearch(searchText)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onExitCommand {
            onDismiss()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Context")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.text)

                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DS.accent)
                } else if !searchText.isEmpty {
                    Text("\(results.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .cosmoWindowChip(isActive: true)
                }

                Text("Esc")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .cosmoWindowChip()

                Button {
                    isVisible = false
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.glassSectionFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.glassBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.type) { category in
                    categoryCapsule(category)
                }
            }
        }
    }

    private func categoryCapsule(_ category: (type: AtomType, label: String, icon: String)) -> some View {
        let entityType = accentEntityType(for: category.type, isSwipe: category.type == Self.swipeFilterTag)
        let isSelected = selectedCategory == category.type
        let pillColor = CosmoMentionColors.color(for: entityType)
        let pillBg = CosmoMentionColors.pillBackground(for: entityType)

        return Button {
            withAnimation(ProMotionSprings.snappy) {
                selectedCategory = selectedCategory == category.type ? nil : category.type
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 11, weight: .semibold))

                Text(category.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isSelected ? DS.textOnAccent : pillColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? pillColor : pillBg)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? pillColor.opacity(0.06) : pillColor.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultsSection: some View {
        if results.isEmpty && !searchText.isEmpty && !isSearching {
            emptyState
        } else if results.isEmpty && searchText.isEmpty {
            promptState
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(results, id: \.uuid) { atom in
                    resultRow(atom: atom)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 248)
        .background(DS.glassSectionFill.opacity(0.22))
    }

    private func resultRow(atom: Atom) -> some View {
        let isSwipe = atom.isSwipeFileAtom
        let entityType = accentEntityType(for: atom.type, isSwipe: isSwipe)
        let displayLabel = isSwipe ? "Swipe" : atom.type.displayName
        let displayIcon = isSwipe ? "bookmark.fill" : atom.type.iconName
        let accent = CosmoMentionColors.color(for: entityType)
        let accentFill = CosmoMentionColors.pillBackground(for: entityType)
        let isHovered = hoveredResultId == atom.uuid
        let title = atom.title ?? "Untitled"
        let detail = atom.body.flatMap { body in
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(92))
        }

        return Button {
            onSelect(atom)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentFill)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: displayIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accent)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.text)
                            .lineLimit(1)

                        if let updatedAt = relativeDate(for: atom) {
                            Text(updatedAt, style: .relative)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DS.textMuted)
                                .lineLimit(1)
                        }
                    }

                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(DS.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Add this item as live context for the next message.")
                            .font(.system(size: 11))
                            .foregroundColor(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(displayLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(accentFill)
                        )

                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isHovered ? accent : DS.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isHovered ? DS.glassInputFillFocused : DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isHovered ? accent.opacity(0.18) : DS.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredResultId = hovering ? atom.uuid : nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.glassSectionFill)
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.textSecondary)
                )

            Text("No matching context")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.text)

            Text("Try a different search term or switch the category.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(DS.glassSectionFill.opacity(0.22))
    }

    private var promptState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "at")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DS.accent)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Search your library")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text("Type after `@` to attach ideas, notes, profiles, swipes, research, tasks, or content as live context.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Try searching for")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textMuted)

                FlexibleFactRow(items: ["@Josh", "@Airbnb", "@profile", "@note"])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.glassSectionFill.opacity(0.22))
    }

    private var headerSubtitle: String {
        if isSearching {
            return "Searching your library"
        }
        if let selectedCategory {
            return "Filtered to \(label(for: selectedCategory))"
        }
        if searchText.isEmpty {
            return "Choose a category or start typing after @"
        }
        return "\(results.count) results ready to add"
    }

    private func label(for category: AtomType) -> String {
        categories.first(where: { $0.type == category })?.label ?? "Category"
    }

    private func accentEntityType(for atomType: AtomType, isSwipe: Bool) -> EntityType {
        if isSwipe {
            return .swipeFile
        }

        switch atomType {
        case .clientProfile:
            return .connection
        default:
            return EntityType(rawValue: atomType.rawValue) ?? .note
        }
    }

    private func relativeDate(for atom: Atom) -> Date? {
        let formatter = ISO8601DateFormatter()

        if !atom.updatedAt.isEmpty, let date = formatter.date(from: atom.updatedAt) {
            return date
        }
        if !atom.createdAt.isEmpty, let date = formatter.date(from: atom.createdAt) {
            return date
        }
        return nil
    }

    private func performSearch(_ query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            var atoms: [Atom]
            if let category = selectedCategory {
                if category == Self.swipeFilterTag {
                    atoms = (try? await AtomRepository.shared.search(query: query, types: [.research])) ?? []
                    atoms = atoms.filter(\.isSwipeFileAtom)
                } else if category == .research {
                    atoms = (try? await AtomRepository.shared.search(query: query, types: [.research])) ?? []
                    atoms = atoms.filter { !$0.isSwipeFileAtom }
                } else {
                    atoms = (try? await AtomRepository.shared.search(query: query, types: [category])) ?? []
                }
            } else {
                atoms = (try? await AtomRepository.shared.search(query: query, limit: 15)) ?? []
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                results = Array(atoms.prefix(15))
                isSearching = false
            }
        }
    }
}

#if DEBUG
struct CosmoMentionOverlay_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isVisible = true
        @State private var searchText = "airbnb"

        var body: some View {
            ZStack {
                DS.bg.ignoresSafeArea()

                VStack {
                    Spacer()
                    CosmoMentionOverlay(
                        isVisible: $isVisible,
                        searchText: $searchText,
                        onSelect: { _ in },
                        onDismiss: {}
                    )
                    .frame(width: 420)
                }
                .padding()
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
            .frame(width: 480, height: 540)
    }
}
#endif
