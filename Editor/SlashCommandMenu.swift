// CosmoOS/Editor/SlashCommandMenu.swift
// Beautiful slash command popover with search and keyboard navigation
// Premium "Cosmic Glass" styling from Cosmo design system
// December 2025 - Staggered animations, symbol effects, haptic feedback

import SwiftUI

struct SlashCommandMenu: View {
    let position: CGPoint
    let commands: [SlashCommand]
    let searchCommands: [SlashCommand]
    let elementSubmenuCommands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void
    let onDismiss: () -> Void
    var darkMode: Bool = false  // Dark glass mode for Thinkspace blocks

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var appearedRows: Set<String> = []
    @State private var menuAppeared = false
    @FocusState private var isSearchFocused: Bool

    // MARK: - Theme-Aware Colors
    private var menuFill: Color { darkMode ? Color.white.opacity(0.06) : DS.glassInputFill.opacity(0.34) }
    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var textTertiary: Color { darkMode ? Color.white.opacity(0.45) : DS.textMuted }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredCommands: [SlashCommand] {
        SlashCommandCatalog.filteredCommands(
            matching: searchText,
            commands: isSearching ? searchCommands : commands
        )
    }

    private var shouldShowElementsSubmenu: Bool {
        !isSearching && filteredCommands[safe: selectedIndex]?.type == .elements
    }

    private var elementsSubmenuYOffset: CGFloat {
        guard let index = filteredCommands.firstIndex(where: { $0.type == .elements }) else {
            return 58
        }
        return 58 + CGFloat(index) * 54
    }

    private let menuWidth: CGFloat = 280
    private let menuHeight: CGFloat = 340
    private let elementSubmenuWidth: CGFloat = 240
    private var totalWidth: CGFloat {
        shouldShowElementsSubmenu ? menuWidth + 8 + elementSubmenuWidth : menuWidth
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            menuContent
                .frame(width: menuWidth, height: menuHeight, alignment: .top)
                .cosmoMenuChrome(cornerRadius: 18, darkMode: darkMode)

            if shouldShowElementsSubmenu {
                ElementCommandSubmenu(
                    commands: elementSubmenuCommands,
                    onSelect: handleCommandSelection,
                    darkMode: darkMode
                )
                .frame(width: elementSubmenuWidth)
                .offset(x: menuWidth + 8, y: elementsSubmenuYOffset)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
            }
        }
        .frame(width: totalWidth, height: menuHeight, alignment: .topLeading)
        .position(x: position.x + (totalWidth / 2), y: position.y + (menuHeight / 2))
        .onAppear(perform: handleAppear)
        .onKeyPress(.upArrow) { handleUpArrow() }
        .onKeyPress(.downArrow) { handleDownArrow() }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.delete) { handleDelete() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var menuContent: some View {
        VStack(spacing: 0) {
            searchFieldView
            dividerView
            commandListView
            keyboardHintView
        }
    }

    private var searchFieldView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(textTertiary)
                .symbolEffect(.bounce, value: menuAppeared)

            TextField("Search commands or elements...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(textPrimary)
                .focused($isSearchFocused)
                .onSubmit {
                    if let command = filteredCommands[safe: selectedIndex] {
                        CosmicHaptics.shared.play(.selection)
                        handleCommandSelection(command)
                    }
                }
        }
        .padding(12)
        .background(menuFill)
    }

    private var dividerView: some View {
        CosmoGradientDivider()
    }

    private var commandListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                    commandRow(command: command, index: index)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 300)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.clear)
        .onChange(of: selectedIndex) { _, _ in
            CosmicHaptics.shared.play(.threshold)
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    private func commandRow(command: SlashCommand, index: Int) -> some View {
        SlashCommandRow(
            command: command,
            isSelected: index == selectedIndex,
            index: index,
            hasAppeared: appearedRows.contains(command.id),
            darkMode: darkMode
        )
        .id(index)
        .onTapGesture {
            CosmicHaptics.shared.play(.selection)
            selectedIndex = index
            handleCommandSelection(command)
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
                    _ = appearedRows.insert(command.id)
                }
            }
        }
    }

    private var keyboardHintView: some View {
        CosmoKeyboardFooter(darkMode: darkMode)
    }

    // MARK: - Event Handlers

    private func handleAppear() {
        selectedIndex = 0
        CosmicHaptics.shared.play(.menuAppear)
        withAnimation(ProMotionSprings.bouncy) {
            menuAppeared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }

    private func handleUpArrow() -> KeyPress.Result {
        selectedIndex = max(0, selectedIndex - 1)
        return .handled
    }

    private func handleDownArrow() -> KeyPress.Result {
        selectedIndex = min(max(0, filteredCommands.count - 1), selectedIndex + 1)
        return .handled
    }

    private func handleCommandSelection(_ command: SlashCommand) {
        guard command.type != .elements else { return }
        onSelect(command)
    }

    private func handleEscape() -> KeyPress.Result {
        CosmicHaptics.shared.play(.selection)
        onDismiss()
        return .handled
    }

    private func handleDelete() -> KeyPress.Result {
        if searchText.isEmpty {
            onDismiss()
            return .handled
        }
        return .ignored
    }
}

// MARK: - Slash Command Row
/// Premium row with staggered entrance and symbol effects
struct SlashCommandRow: View {
    let command: SlashCommand
    let isSelected: Bool
    let index: Int
    let hasAppeared: Bool
    var darkMode: Bool = false

    @State private var iconBounce = false

    // Dark mode colors
    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.6) : DS.documentTextSecondary }
    private var textTertiary: Color { darkMode ? Color.white.opacity(0.4) : DS.documentTextMuted }
    private var accentColor: Color { darkMode ? Color.white.opacity(0.76) : DS.accent }

    var body: some View {
        HStack(spacing: 12) {
            // Icon - Cosmo lavender/purple accent with symbol effect
            Image(systemName: DocumentElementSymbol.validName(command.icon))
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? accentColor : accentColor.opacity(0.86))
                .symbolEffect(.bounce, value: iconBounce)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconFill)
                        .shadow(
                            color: DS.sidebarMaterialShadow.opacity(isSelected ? 0.28 : 0),
                            radius: isSelected ? 6 : 0,
                            y: isSelected ? 2 : 0
                        )
                )

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textPrimary)

                Text(command.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Shortcut badge
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(darkMode ? Color.white.opacity(0.10) : DS.glassInputFill.opacity(0.52))
                    .clipShape(.rect(cornerRadius: DS.radiusXSmall))
            }

            // Selection indicator
            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? selectedFill : Color.clear)
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

    private var iconFill: Color {
        if darkMode {
            return isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08)
        }
        return isSelected ? DS.glassInputFillFocused.opacity(0.90) : DS.glassInputFill.opacity(0.54)
    }

    private var selectedFill: Color {
        darkMode ? Color.white.opacity(0.10) : DS.glassInputFillFocused.opacity(0.82)
    }
}

private struct ElementCommandSubmenu: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void
    var darkMode: Bool = false

    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.6) : DS.documentTextSecondary }
    private var accentColor: Color { darkMode ? Color.white.opacity(0.76) : DS.accent }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(commands) { command in
                    Button {
                        CosmicHaptics.shared.play(.selection)
                        onSelect(command)
                    } label: {
                        row(for: command)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 300)
        .scrollBounceBehavior(.basedOnSize)
        .cosmoMenuChrome(cornerRadius: 16, darkMode: darkMode)
    }

    private func row(for command: SlashCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: DocumentElementSymbol.validName(command.icon))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(darkMode ? Color.white.opacity(0.08) : DS.glassInputFill.opacity(0.54))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)

                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - Element Creation Menu
struct ElementCreationMenu: View {
    let position: CGPoint
    let onCreate: (String, String) -> Void
    let onDismiss: () -> Void
    var darkMode: Bool = false

    @State private var title = ""
    @State private var icon = ElementIconPickerCategory.structure.options.first?.systemIcon ?? "square.dashed"
    @State private var selectedCategory: ElementIconPickerCategory = .structure
    @FocusState private var titleFocused: Bool

    private let menuWidth: CGFloat = 330
    private let menuHeight: CGFloat = 364

    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.62) : DS.documentTextSecondary }
    private var fieldFill: Color { darkMode ? Color.white.opacity(0.08) : DS.glassInputFill.opacity(0.46) }
    private var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: sanitizedIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(darkMode ? Color.white.opacity(0.82) : DS.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(fieldFill)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("New Element")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Text("Reusable block")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(textSecondary)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(textSecondary)
            }

            TextField("Element name", text: $title)
                .textFieldStyle(.plain)
                .foregroundStyle(textPrimary)
                .focused($titleFocused)
                .onSubmit { createIfPossible() }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(fieldFill))

            ElementIconPickerGrid(
                selectedIcon: $icon,
                selectedCategory: $selectedCategory,
                darkMode: darkMode,
                onPick: { option in
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = option.defaultTitle
                    }
                }
            )

            HStack {
                Spacer(minLength: 0)
                Button("Create") {
                    createIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(12)
        .frame(width: menuWidth, height: menuHeight, alignment: .top)
        .cosmoMenuChrome(cornerRadius: 18, darkMode: darkMode)
        .position(x: position.x + (menuWidth / 2), y: position.y + (menuHeight / 2))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                titleFocused = true
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private var sanitizedIcon: String {
        DocumentElementSymbol.validName(icon)
    }

    private func createIfPossible() {
        guard canCreate else { return }
        onCreate(title, sanitizedIcon)
    }
}

private struct ElementIconOption: Identifiable, Hashable {
    let defaultTitle: String
    let systemIcon: String

    var id: String { systemIcon }
}

private enum ElementIconPickerCategory: String, CaseIterable, Identifiable {
    case structure = "Structure"
    case people = "People"
    case writing = "Writing"
    case media = "Media"
    case status = "Status"
    case symbols = "Symbols"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .structure: return "square.dashed"
        case .people: return "person.2"
        case .writing: return "pencil.line"
        case .media: return "photo"
        case .status: return "checkmark.circle"
        case .symbols: return "sparkle"
        }
    }

    var options: [ElementIconOption] {
        switch self {
        case .structure:
            return [
                .init(defaultTitle: "Section", systemIcon: "square.dashed"),
                .init(defaultTitle: "Folder", systemIcon: "folder"),
                .init(defaultTitle: "List", systemIcon: "list.bullet.rectangle"),
                .init(defaultTitle: "Grid", systemIcon: "rectangle.grid.2x2"),
                .init(defaultTitle: "Stack", systemIcon: "square.stack.3d.up"),
                .init(defaultTitle: "Map", systemIcon: "map"),
                .init(defaultTitle: "Target", systemIcon: "target"),
                .init(defaultTitle: "Layers", systemIcon: "square.3.stack.3d"),
                .init(defaultTitle: "Tree", systemIcon: "point.3.connected.trianglepath.dotted"),
                .init(defaultTitle: "Pillar", systemIcon: "rectangle.split.3x1"),
                .init(defaultTitle: "Hierarchy", systemIcon: "rectangle.connected.to.line.below"),
                .init(defaultTitle: "Group", systemIcon: "rectangle.3.group")
            ]
        case .people:
            return [
                .init(defaultTitle: "Audience", systemIcon: "person.2"),
                .init(defaultTitle: "Customer", systemIcon: "person.crop.circle"),
                .init(defaultTitle: "Community", systemIcon: "person.3"),
                .init(defaultTitle: "Voice", systemIcon: "bubble.left"),
                .init(defaultTitle: "Interview", systemIcon: "person.wave.2"),
                .init(defaultTitle: "Persona", systemIcon: "face.smiling"),
                .init(defaultTitle: "Team", systemIcon: "person.2.crop.square.stack"),
                .init(defaultTitle: "Profile", systemIcon: "person.text.rectangle"),
                .init(defaultTitle: "Contact", systemIcon: "at"),
                .init(defaultTitle: "Network", systemIcon: "network"),
                .init(defaultTitle: "Conversation", systemIcon: "bubble.left.and.bubble.right"),
                .init(defaultTitle: "Quote", systemIcon: "quote.opening")
            ]
        case .writing:
            return [
                .init(defaultTitle: "Idea", systemIcon: "lightbulb"),
                .init(defaultTitle: "Draft", systemIcon: "doc.text"),
                .init(defaultTitle: "Outline", systemIcon: "list.bullet.indent"),
                .init(defaultTitle: "Hook", systemIcon: "text.quote"),
                .init(defaultTitle: "Script", systemIcon: "text.alignleft"),
                .init(defaultTitle: "Research", systemIcon: "books.vertical"),
                .init(defaultTitle: "Note", systemIcon: "note.text"),
                .init(defaultTitle: "Page", systemIcon: "doc"),
                .init(defaultTitle: "Pen", systemIcon: "pencil.line"),
                .init(defaultTitle: "Highlight", systemIcon: "highlighter"),
                .init(defaultTitle: "Bookmark", systemIcon: "bookmark"),
                .init(defaultTitle: "Tag", systemIcon: "tag")
            ]
        case .media:
            return [
                .init(defaultTitle: "Image", systemIcon: "photo"),
                .init(defaultTitle: "Video", systemIcon: "play.rectangle"),
                .init(defaultTitle: "Audio", systemIcon: "waveform"),
                .init(defaultTitle: "Clip", systemIcon: "film"),
                .init(defaultTitle: "Swipe", systemIcon: "rectangle.on.rectangle"),
                .init(defaultTitle: "Asset", systemIcon: "shippingbox"),
                .init(defaultTitle: "Camera", systemIcon: "camera"),
                .init(defaultTitle: "Music", systemIcon: "music.note"),
                .init(defaultTitle: "Mic", systemIcon: "mic"),
                .init(defaultTitle: "Link", systemIcon: "link"),
                .init(defaultTitle: "Gallery", systemIcon: "photo.on.rectangle.angled"),
                .init(defaultTitle: "Cast", systemIcon: "antenna.radiowaves.left.and.right")
            ]
        case .status:
            return [
                .init(defaultTitle: "Todo", systemIcon: "circle"),
                .init(defaultTitle: "Done", systemIcon: "checkmark.circle"),
                .init(defaultTitle: "Question", systemIcon: "questionmark.circle"),
                .init(defaultTitle: "Warning", systemIcon: "exclamationmark.triangle"),
                .init(defaultTitle: "Insight", systemIcon: "sparkles"),
                .init(defaultTitle: "Priority", systemIcon: "flag"),
                .init(defaultTitle: "Pinned", systemIcon: "pin"),
                .init(defaultTitle: "Locked", systemIcon: "lock"),
                .init(defaultTitle: "Progress", systemIcon: "hourglass"),
                .init(defaultTitle: "Schedule", systemIcon: "calendar"),
                .init(defaultTitle: "Goal", systemIcon: "scope"),
                .init(defaultTitle: "Notice", systemIcon: "bell")
            ]
        case .symbols:
            return [
                .init(defaultTitle: "Spark", systemIcon: "sparkle"),
                .init(defaultTitle: "Star", systemIcon: "star"),
                .init(defaultTitle: "Heart", systemIcon: "heart"),
                .init(defaultTitle: "Compass", systemIcon: "safari"),
                .init(defaultTitle: "Globe", systemIcon: "globe"),
                .init(defaultTitle: "Cube", systemIcon: "cube"),
                .init(defaultTitle: "Brain", systemIcon: "brain"),
                .init(defaultTitle: "Atom", systemIcon: "atom"),
                .init(defaultTitle: "Wand", systemIcon: "wand.and.stars"),
                .init(defaultTitle: "Diamond", systemIcon: "diamond"),
                .init(defaultTitle: "Hexagon", systemIcon: "hexagon"),
                .init(defaultTitle: "Crown", systemIcon: "crown")
            ]
        }
    }
}

private struct ElementIconPickerGrid: View {
    @Binding var selectedIcon: String
    @Binding var selectedCategory: ElementIconPickerCategory

    var darkMode: Bool
    var onPick: (ElementIconOption) -> Void

    private let columns = Array(repeating: GridItem(.fixed(38), spacing: 8), count: 6)

    private var textSecondary: Color { darkMode ? Color.white.opacity(0.62) : DS.documentTextSecondary }
    private var fill: Color { darkMode ? Color.white.opacity(0.08) : DS.glassInputFill.opacity(0.46) }
    private var selectedFill: Color { darkMode ? Color.white.opacity(0.18) : DS.accentSoft }
    private var selectedStroke: Color { darkMode ? Color.white.opacity(0.42) : DS.accent.opacity(0.55) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(ElementIconPickerCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Image(systemName: DocumentElementSymbol.validName(category.icon))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(category == selectedCategory ? DS.accent : textSecondary)
                            .frame(width: 32, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(category == selectedCategory ? selectedFill : fill)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(selectedCategory.options) { option in
                    Button {
                        selectedIcon = DocumentElementSymbol.validName(option.systemIcon)
                        onPick(option)
                    } label: {
                        Image(systemName: DocumentElementSymbol.validName(option.systemIcon))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DocumentElementSymbol.validName(option.systemIcon) == selectedIcon ? DS.accent : textSecondary)
                            .frame(width: 38, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(DocumentElementSymbol.validName(option.systemIcon) == selectedIcon ? selectedFill : fill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DocumentElementSymbol.validName(option.systemIcon) == selectedIcon ? selectedStroke : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(option.defaultTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(darkMode ? Color.white.opacity(0.045) : Color.white.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(darkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
