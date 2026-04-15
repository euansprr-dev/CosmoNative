// CosmoOS/Editor/SlashCommandMenu.swift
// Beautiful slash command popover with search and keyboard navigation
// Premium "Cosmic Glass" styling from Cosmo design system
// December 2025 - Staggered animations, symbol effects, haptic feedback

import SwiftUI

struct SlashCommandMenu: View {
    let position: CGPoint
    let onSelect: (SlashCommand) -> Void
    let onDismiss: () -> Void
    var darkMode: Bool = false  // Dark glass mode for Thinkspace blocks

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var appearedRows: Set<UUID> = []
    @State private var menuAppeared = false
    @FocusState private var isSearchFocused: Bool

    // MARK: - Theme-Aware Colors
    private var bgColor: Color { DS.vellum }
    private var textPrimary: Color { DS.text }
    private var textSecondary: Color { DS.textSecondary }
    private var textTertiary: Color { DS.textMuted }
    private var accentColor: Color { DS.accent }
    private var borderColor: Color { DS.sepiaBorder }
    private var shadowColor: Color { .black.opacity(0.10) }

    private var filteredCommands: [SlashCommand] {
        if searchText.isEmpty {
            return SlashCommand.all
        }
        return SlashCommand.all.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let menuWidth: CGFloat = 280
    private let menuHeight: CGFloat = 340

    var body: some View {
        menuContent
            .frame(width: menuWidth, height: menuHeight, alignment: .top)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(menuBorder)
            .dsFloatingShadow()
            .scaleEffect(menuAppeared ? 1 : 0.95)
            .opacity(menuAppeared ? 1 : 0)
            .blur(radius: menuAppeared ? 0 : 4)
            .position(x: position.x + (menuWidth / 2), y: position.y + (menuHeight / 2))
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

            TextField("Search commands...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(textPrimary)
                .focused($isSearchFocused)
                .onSubmit {
                    if let command = filteredCommands[safe: selectedIndex] {
                        CosmicHaptics.shared.play(.selection)
                        onSelect(command)
                    }
                }
        }
        .padding(12)
        .background(bgColor)
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
        .background(bgColor)
        .onChange(of: selectedIndex) { _, _ in
            CosmicHaptics.shared.play(.threshold)
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
            onSelect(command)
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
        CosmoKeyboardFooter()
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
        selectedIndex = min(filteredCommands.count - 1, selectedIndex + 1)
        return .handled
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
    private var textPrimary: Color { darkMode ? .white : CosmoColors.textPrimary }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.6) : CosmoColors.textSecondary }
    private var textTertiary: Color { darkMode ? Color.white.opacity(0.4) : CosmoColors.textTertiary }
    private var accentColor: Color { darkMode ? CosmoColors.thinkspacePurple : CosmoColors.lavender }

    var body: some View {
        HStack(spacing: 12) {
            // Icon - Cosmo lavender/purple accent with symbol effect
            Image(systemName: command.icon)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? .white : accentColor)
                .symbolEffect(.bounce, value: iconBounce)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? accentColor : accentColor.opacity(0.15))
                        .shadow(
                            color: accentColor.opacity(isSelected ? 0.3 : 0),
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
                    .background(darkMode ? Color.white.opacity(0.1) : CosmoColors.glassGrey.opacity(0.4))
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
                .fill(isSelected ? accentColor.opacity(0.12) : Color.clear)
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

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
