// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantContextMenu.swift
// The @-mention context picker: search, category filters, and selected-context
// management. Extracted from the bar so the pane composer shares it verbatim.
// June 2026

import SwiftUI

struct CosmoInlineAssistantContextMenu: View {
    let searchText: String
    let selectedAtoms: [Atom]
    let onSelect: (Atom) -> Void
    let onRemove: (Atom) -> Void
    let onDismiss: () -> Void

    @State private var selectedCategory: AtomType?
    @State private var results: [Atom] = []
    @State private var isSearching = false
    @State private var hoveredAtomUUID: String?
    @State private var searchTask: Task<Void, Never>?

    private static let swipeCategory = AtomType.creator

    private let categories: [(type: AtomType, title: String, systemImage: String)] = [
        (.content, "Content", "doc.richtext"),
        (.clientProfile, "Profiles", "person.crop.circle"),
        (swipeCategory, "Swipes", "bookmark.fill"),
        (.idea, "Ideas", "lightbulb"),
        (.research, "Research", "magnifyingglass"),
        (.note, "Notes", "note.text")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.glassBorder)
            filterStrip
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            queryRow
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            resultsSection
        }
        .background(DS.surfaceCard.opacity(0.98), in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.glassBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 24, x: 0, y: 14)
        .onAppear {
            performSearch(searchText)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onChange(of: searchText) { _, value in
            performSearch(value)
        }
        .onChange(of: selectedCategory) { _, _ in
            performSearch(searchText)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "at")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.accent)
                .frame(width: 30, height: 30)
                .background(DS.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Context")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !selectedAtoms.isEmpty {
                Button("Clear") {
                    selectedAtoms.forEach(onRemove)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .buttonStyle(.plain)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(DS.glassInputFill, in: Circle())
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close context menu")
        }
        .padding(14)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CosmoInlineContextFilterChip(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    isSelected: selectedCategory == nil,
                    tint: DS.accent
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        selectedCategory = nil
                    }
                }

                ForEach(categories, id: \.type) { category in
                    CosmoInlineContextFilterChip(
                        title: category.title,
                        systemImage: category.systemImage,
                        isSelected: selectedCategory == category.type,
                        tint: tint(for: category.type)
                    ) {
                        withAnimation(ProMotionSprings.snappy) {
                            selectedCategory = selectedCategory == category.type ? nil : category.type
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var queryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textMuted)
            Text(queryLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(searchText.isEmpty ? DS.textMuted : DS.text)
                .lineLimit(1)
            if isSearching {
                Spacer(minLength: 0)
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(DS.glassInputFill, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(searchText.isEmpty ? DS.glassBorder : DS.accent.opacity(0.34), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var resultsSection: some View {
        if results.isEmpty && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptState
        } else if results.isEmpty && !isSearching {
            emptyState
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !selectedAtoms.isEmpty {
                    selectedSection
                }

                ForEach(results, id: \.uuid) { atom in
                    resultRow(atom)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 278)
        .background(DS.glassInputFill.opacity(0.34))
    }

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.textMuted)
                .tracking(0.7)
            ForEach(selectedAtoms, id: \.uuid) { atom in
                resultRow(atom)
            }
        }
    }

    private func resultRow(_ atom: Atom) -> some View {
        let selected = isSelected(atom)
        let hovered = hoveredAtomUUID == atom.uuid
        let accent = tint(for: atom.type, isSwipe: atom.isSwipeFileAtom)
        let title = atom.title ?? "Untitled"
        let detail = atom.body?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(84)

        return Button {
            onSelect(atom)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: atom.isSwipeFileAtom ? "bookmark.fill" : atom.type.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(DS.palette.isDark ? 0.20 : 0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(detailText(detail))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? DS.accent : (hovered ? accent : DS.textMuted))
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .background(rowFill(selected: selected, hovered: hovered), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(rowStroke(selected: selected, hovered: hovered, accent: accent), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredAtomUUID = hovering ? atom.uuid : nil
        }
    }

    private var promptState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep typing after @ to search, then choose the context Cosmo should keep in mind.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(["Josh", "profile", "top reel", "deck"], id: \.self) { example in
                    Text("@\(example)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(DS.accentSoft, in: Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.glassInputFill.opacity(0.34))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.textMuted)
            Text("No matching context")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.text)
            Text("Try another phrase or switch the filter.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(DS.glassInputFill.opacity(0.34))
    }

    private var subtitle: String {
        if selectedAtoms.isEmpty {
            return "Add profiles, swipes, ideas, notes, or research"
        }
        return "\(selectedAtoms.count) selected for this session"
    }

    private var queryLabel: String {
        if searchText.isEmpty {
            return "Type after @ to search context"
        }
        return "@\(searchText)"
    }

    private func performSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            let atoms = await searchAtoms(query: trimmed)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                results = atoms
                isSearching = false
            }
        }
    }

    private func searchAtoms(query: String) async -> [Atom] {
        let raw: [Atom]
        if let selectedCategory {
            if selectedCategory == Self.swipeCategory {
                raw = ((try? await AtomRepository.shared.search(query: query, types: [.research])) ?? [])
                    .filter(\.isSwipeFileAtom)
            } else if selectedCategory == .research {
                raw = ((try? await AtomRepository.shared.search(query: query, types: [.research])) ?? [])
                    .filter { !$0.isSwipeFileAtom }
            } else {
                raw = (try? await AtomRepository.shared.search(query: query, types: [selectedCategory])) ?? []
            }
        } else {
            raw = (try? await AtomRepository.shared.search(query: query, limit: 18)) ?? []
        }

        return Array(raw.prefix(18))
    }

    private func isSelected(_ atom: Atom) -> Bool {
        selectedAtoms.contains { $0.uuid == atom.uuid }
    }

    private func detailText(_ detail: String.SubSequence?) -> String {
        guard let detail, !detail.isEmpty else {
            return "Add as inline session context"
        }
        return String(detail)
    }

    private func rowFill(selected: Bool, hovered: Bool) -> Color {
        if selected { return DS.accentSoft.opacity(0.72) }
        return hovered ? DS.glassInputFillFocused : DS.surfaceCard.opacity(0.70)
    }

    private func rowStroke(selected: Bool, hovered: Bool, accent: Color) -> Color {
        if selected { return DS.accent.opacity(0.32) }
        return hovered ? accent.opacity(0.22) : DS.glassBorder
    }

    private func tint(for type: AtomType, isSwipe: Bool = false) -> Color {
        let entity: EntityType
        if isSwipe {
            entity = .swipeFile
        } else if type == .clientProfile {
            entity = .connection
        } else {
            entity = EntityType(rawValue: type.rawValue) ?? .note
        }
        return CosmoMentionColors.color(for: entity)
    }
}

struct CosmoInlineContextFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(DS.footnote.weight(.semibold))
                Text(title)
                    .font(DS.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : (isHovered ? DS.textSecondary : DS.textMuted))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(chipFill, in: Capsule())
            .overlay(Capsule().strokeBorder(chipStroke, lineWidth: isSelected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.snappy, value: isSelected)
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var chipFill: Color {
        if isSelected { return tint.opacity(DS.palette.isDark ? 0.22 : 0.14) }
        return isHovered ? DS.glassInputFillFocused : DS.glassInputFill
    }

    private var chipStroke: Color {
        if isSelected { return tint.opacity(0.42) }
        return isHovered ? DS.glassBorderFocused : DS.glassBorder
    }
}
