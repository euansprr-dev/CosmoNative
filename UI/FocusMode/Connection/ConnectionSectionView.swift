// CosmoOS/UI/FocusMode/Connection/ConnectionSectionView.swift
// Section component for Connection Focus Mode
// Displays items list with ghost suggestions
// December 2025 - Premium design matching Sanctuary aesthetic

import SwiftUI

// MARK: - Connection Section View

/// A section component displaying items and ghost suggestions for a Connection
struct ConnectionSectionView: View {
    // MARK: - Properties

    /// The section data
    @Binding var section: ConnectionSection

    /// Callback when item is added
    let onAddItem: (String) -> Void

    /// Callback when item is edited
    let onEditItem: (ConnectionItem) -> Void

    /// Callback when item is deleted
    let onDeleteItem: (UUID) -> Void

    /// Callback when source is tapped
    let onSourceTap: (String) -> Void

    /// Callback when ghost is accepted
    let onAcceptGhost: (GhostSuggestion) -> Void

    /// Callback when ghost is dismissed
    let onDismissGhost: (UUID) -> Void

    // MARK: - State

    @State private var isHovered = false
    @State private var isAddingItem = false
    @State private var newItemText = ""
    @FocusState private var isNewItemFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            sectionHeader

            // Content (when expanded)
            if section.isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Existing items
                    ForEach(section.items) { item in
                        ConnectionItemRow(
                            item: item,
                            accentColor: section.type.accentColor,
                            onEdit: { onEditItem(item) },
                            onDelete: { onDeleteItem(item.id) },
                            onSourceTap: onSourceTap
                        )
                    }

                    // Ghost suggestions
                    if section.showGhostSuggestions {
                        ForEach(section.ghostSuggestions) { ghost in
                            GhostSuggestionRow(
                                suggestion: ghost,
                                accentColor: section.type.accentColor,
                                onAccept: { onAcceptGhost(ghost) },
                                onDismiss: { onDismissGhost(ghost.id) },
                                onSourceTap: { onSourceTap(ghost.sourceAtomUUID) }
                            )
                        }
                    }

                    // Add item input
                    if isAddingItem {
                        addItemInput
                    } else {
                        addItemButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovered ? section.type.accentColor.opacity(0.3) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                section.isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: section.type.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(section.type.accentColor)
                    .frame(width: 24, height: 24)
                    .background(section.type.accentColor.opacity(0.15), in: Circle())

                // Title and prompt
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.type.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(section.type.promptQuestion)
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.5))
                }

                Spacer()

                // Item count
                if section.itemCount > 0 {
                    Text("\(section.itemCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(section.type.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(section.type.accentColor.opacity(0.15), in: Capsule())
                }

                // Ghost count
                if section.ghostSuggestions.count > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("\(section.ghostSuggestions.count)")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color.white.opacity(0.4))
                }

                // Expand/collapse chevron
                Image(systemName: section.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Item Button

    private var addItemButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                isAddingItem = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNewItemFocused = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                Text("Add item")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(section.type.accentColor.opacity(0.7))
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Item Input

    private var addItemInput: some View {
        HStack(spacing: 8) {
            TextField("Add item...", text: $newItemText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($isNewItemFocused)
                .lineLimit(1...3)
                .onSubmit {
                    submitNewItem()
                }

            // Cancel button
            Button {
                cancelNewItem()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Submit button
            Button {
                submitNewItem()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(section.type.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(newItemText.isEmpty)
            .opacity(newItemText.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private var sectionBackground: some View {
        ZStack {
            Color(hex: "#1A1A25")

            // Subtle accent gradient when expanded
            if section.isExpanded {
                LinearGradient(
                    colors: [
                        section.type.accentColor.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func submitNewItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onAddItem(trimmed)
        }
        cancelNewItem()
    }

    private func cancelNewItem() {
        withAnimation(ProMotionSprings.snappy) {
            isAddingItem = false
            newItemText = ""
        }
    }
}

// MARK: - Connection Item Row

/// A single item within a Connection section
struct ConnectionItemRow: View {
    let item: ConnectionItem
    let accentColor: Color
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSourceTap: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Bullet
            Circle()
                .fill(accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // Source attribution
                if item.hasSource {
                    Button {
                        if let sourceUUID = item.sourceAtomUUID {
                            onSourceTap(sourceUUID)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                            Text("Source")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(accentColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Actions (on hover)
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Color.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.03) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Ghost Suggestion Row

/// A ghost suggestion that can be accepted or dismissed
struct GhostSuggestionRow: View {
    let suggestion: GhostSuggestion
    let accentColor: Color
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onSourceTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Ghost icon
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundColor(accentColor.opacity(0.5))
                .padding(.top, 4)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.content)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .italic()
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // Source info
                Button(action: onSourceTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text(suggestion.sourceAtomTitle)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundColor(accentColor.opacity(0.6))
                }
                .buttonStyle(.plain)

                // Actions
                HStack(spacing: 12) {
                    // Accept button
                    Button(action: onAccept) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Accept")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)

                    // Dismiss button
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10))
                            Text("Dismiss")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Confidence
                    Text("\(suggestion.confidencePercent)% match")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accentColor.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .foregroundColor(accentColor.opacity(0.2))
                )
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ConnectionSectionPreviewWrapper(type: .goal)
                ConnectionSectionPreviewWrapper(type: .problems)
            }
            .padding(40)
        }
        .frame(width: 500, height: 600)
    }

    struct ConnectionSectionPreviewWrapper: View {
        let type: ConnectionSectionType

        @State private var section: ConnectionSection

        init(type: ConnectionSectionType) {
            self.type = type
            self._section = State(initialValue: ConnectionSection(
                type: type,
                items: [
                    ConnectionItem(content: "First item in this section"),
                    ConnectionItem(
                        content: "Second item with a source reference",
                        sourceAtomUUID: "source-uuid"
                    )
                ],
                ghostSuggestions: [
                    GhostSuggestion(
                        content: "Suggested content from related research",
                        sourceAtomUUID: "research-uuid",
                        sourceAtomTitle: "Research: Morning Routines",
                        sourceSnippet: "Studies show that morning routines...",
                        targetSectionType: type,
                        confidence: 0.85
                    )
                ]
            ))
        }

        var body: some View {
            ConnectionSectionView(
                section: $section,
                onAddItem: { print("Add: \($0)") },
                onEditItem: { print("Edit: \($0.content)") },
                onDeleteItem: { print("Delete: \($0)") },
                onSourceTap: { print("Source: \($0)") },
                onAcceptGhost: { print("Accept: \($0.content)") },
                onDismissGhost: { print("Dismiss: \($0)") }
            )
        }
    }
}
#endif
