// CosmoOS/UI/FocusMode/Content/ContentOutlineSidebarContent.swift
// Content for the UniversalFocusSidebar when in content focus mode
// Core idea, hooks list, outline checklist — extracted from ContentBrainstormView
// February 2026

import SwiftUI

// MARK: - Content Outline Sidebar Content

/// Provides the content for the left universal sidebar in Content Focus Mode.
/// Shows core idea (editable), hooks (editable + add), and outline (draggable + checkmarks).
struct ContentOutlineSidebarContent: View {
    @Binding var state: ContentFocusModeState
    let atom: Atom
    var writingEngine: UnifiedWritingEngine?

    @State private var newHookText = ""
    @State private var newOutlineText = ""
    @State private var isGeneratingOpusOutline = false
    @State private var opusOutlineError: String?
    @FocusState private var coreIdeaFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                coreIdeaSection
                hooksSection
                outlineSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Core Idea Section

    private var coreIdeaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CORE IDEA")
                .font(DS.sectionLabel)
                .foregroundColor(DS.textMuted)
                .tracking(0.88)

            TextEditor(text: $state.coreIdea)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(DS.text)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .focused($coreIdeaFocused)
                .frame(minHeight: 48, maxHeight: 100)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .stroke(
                                    coreIdeaFocused ? DS.borderActive : DS.border,
                                    lineWidth: 1
                                )
                        )
                )
                .onChange(of: state.coreIdea) { _, _ in
                    state.lastModified = Date()
                    state.save()
                }
        }
    }

    // MARK: - Hooks Section

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("HOOKS")
                    .font(DS.sectionLabel)
                    .foregroundColor(DS.textMuted)
                    .tracking(0.88)

                Spacer()

                if !state.hooks.isEmpty {
                    Text("\(state.hooks.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DS.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.accent.opacity(0.15), in: Capsule())
                }
            }

            // Existing hooks
            ForEach(Array(state.hooks.enumerated()), id: \.offset) { index, hook in
                SidebarHookRow(
                    hook: hook,
                    index: index,
                    onUpdate: { newText in
                        state.hooks[index] = newText
                        state.lastModified = Date()
                        state.save()
                    },
                    onDelete: {
                        withAnimation(ProMotionSprings.snappy) {
                            state.hooks.remove(at: index)
                            state.lastModified = Date()
                            state.save()
                        }
                    }
                )
            }

            // Add new hook
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(DS.accent.opacity(0.5))

                TextField("Add a hook...", text: $newHookText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.text)
                    .onSubmit { addHook() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    private func addHook() {
        let trimmed = newHookText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            state.hooks.append(trimmed)
            newHookText = ""
            state.lastModified = Date()
            state.save()
        }
    }

    // MARK: - Outline Section

    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("OUTLINE")
                    .font(DS.sectionLabel)
                    .foregroundColor(DS.textMuted)
                    .tracking(0.88)

                if state.outline.isEmpty {
                    generateOutlineButton
                }

                Spacer()

                if !state.outline.isEmpty {
                    Text("\(state.completedOutlineCount)/\(state.outline.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DS.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.accent.opacity(0.15), in: Capsule())
                }
            }

            // AI-suggested badge
            if state.isAISuggestedOutline && !state.outline.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                    Text("AI-suggested")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(DS.accent.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.accent.opacity(0.1), in: Capsule())
            }

            // Outline items as checklist
            VStack(spacing: 2) {
                ForEach(state.sortedOutline) { item in
                    SidebarOutlineRow(
                        item: item,
                        onToggle: {
                            withAnimation(ProMotionSprings.snappy) {
                                state.toggleOutlineItem(id: item.id)
                                state.save()
                            }
                        },
                        onUpdateTitle: { title in
                            state.updateOutlineItem(id: item.id, title: title)
                            state.save()
                        },
                        onDelete: {
                            withAnimation(ProMotionSprings.snappy) {
                                state.removeOutlineItem(id: item.id)
                                state.save()
                            }
                        }
                    )
                }
                .onMove { source, destination in
                    state.moveOutlineItem(from: source, to: destination)
                    state.save()
                }
            }

            // Add new outline item
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(DS.accent.opacity(0.5))

                TextField("Add outline point...", text: $newOutlineText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.text)
                    .onSubmit { addOutlineItem() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var generateOutlineButton: some View {
        if isGeneratingOpusOutline {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(DS.accent)
                Text("Generating...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.accent)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: generateOpusOutline) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .medium))
                        Text("Generate")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)

                if let error = opusOutlineError {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundColor(.orange.opacity(0.8))
                }
            }
        }
    }

    private func generateOpusOutline() {
        isGeneratingOpusOutline = true
        opusOutlineError = nil
        Task {
            if let engine = writingEngine {
                await engine.suggestOutline()
                await MainActor.run {
                    if let error = engine.error {
                        opusOutlineError = "Failed: \(error)"
                    }
                    isGeneratingOpusOutline = false
                }
            } else {
                await MainActor.run {
                    opusOutlineError = "Engine not initialized"
                    isGeneratingOpusOutline = false
                }
            }
        }
    }

    private func addOutlineItem() {
        let trimmed = newOutlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            state.addOutlineItem(trimmed)
            newOutlineText = ""
            state.save()
        }
    }
}

// MARK: - Sidebar Hook Row

private struct SidebarHookRow: View {
    let hook: String
    let index: Int
    let onUpdate: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index + 1).")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textMuted)
                .frame(width: 16, alignment: .trailing)

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .focused($isFocused)
                    .onSubmit { commitEdit() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(hook)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(2)
                    .onTapGesture(count: 2) {
                        editText = hook
                        isEditing = true
                        isFocused = true
                    }
            }

            Spacer(minLength: 2)

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onUpdate(trimmed) }
        isEditing = false
    }
}

// MARK: - Sidebar Outline Row

private struct SidebarOutlineRow: View {
    let item: OutlineItem
    let onToggle: () -> Void
    let onUpdateTitle: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(item.isCompleted ? DS.accent : DS.textMuted)
            }
            .buttonStyle(.plain)

            // Title
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.text)
                    .focused($isFocused)
                    .onSubmit { commitEdit() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundColor(item.isCompleted ? DS.textMuted : DS.textSecondary)
                    .strikethrough(item.isCompleted, color: DS.textMuted)
                    .lineLimit(2)
                    .onTapGesture(count: 2) {
                        editTitle = item.title
                        isEditing = true
                        isFocused = true
                    }
            }

            Spacer(minLength: 2)

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private func commitEdit() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onUpdateTitle(trimmed) }
        isEditing = false
    }
}
