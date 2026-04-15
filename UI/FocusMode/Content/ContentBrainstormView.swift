// CosmoOS/UI/FocusMode/Content/ContentBrainstormView.swift
// Step 1 of Content Focus Mode - Core idea + outline + AI Collaborator
// February 2026 — Enhanced with Brainstorm AI Collaborator replacing Related panel

import SwiftUI

struct ContentBrainstormView: View {
    @Binding var state: ContentFocusModeState
    let atom: Atom
    var writingEngine: UnifiedWritingEngine?
    let onNext: () -> Void

    @State private var newOutlineText = ""
    @State private var newHookText = ""
    @State private var contentAppeared = false
    @State private var showContextSidebar = true
    @State private var isGeneratingOpusOutline = false
    @State private var opusOutlineError: String?
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showContextSidebar {
                BrainstormContextSidebar(
                    atom: atom,
                    state: $state,
                    isVisible: $showContextSidebar
                )
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .zIndex(20)
            }
        }
        .background(DS.bg)
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance) {
                contentAppeared = true
            }
        }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section: Hooks
                hooksSection

                // Divider
                Rectangle()
                    .fill(DS.border)
                    .frame(height: 1)

                // Section: Description
                descriptionSection

                // Divider
                Rectangle()
                    .fill(DS.border)
                    .frame(height: 1)

                // Section: Outline
                outlineSection
            }
            .padding(32)
        }
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 12)
    }

    // MARK: - Hooks Section

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Hooks")
                    .dsSmallCapsLabel()

                Spacer()

                if !state.hooks.isEmpty {
                    Text("\(state.hooks.count) hooks")
                        .font(DS.timestamp)
                        .foregroundStyle(DS.textMuted)
                }

                if !showContextSidebar {
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            showContextSidebar = true
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(DS.buttonText)
                            .foregroundStyle(DS.textMuted)
                            .padding(5)
                            .background(DS.border, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            Text("Opening lines that grab attention")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)

            // Existing hooks
            ForEach(Array(state.hooks.enumerated()), id: \.offset) { index, hook in
                HookItemRow(
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
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(DS.title3)
                    .foregroundStyle(DS.accent.opacity(0.6))

                TextField("Add a hook...", text: $newHookText)
                    .textFieldStyle(.plain)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .onSubmit {
                        addHook()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .dsSmallCapsLabel()

            Text("Context, theme, or background for the content")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)

            TextEditor(text: $state.contentDescription)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(15 * 0.7)
                .scrollContentBackground(.hidden)
                .focused($descriptionFocused)
                .frame(minHeight: 80)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .fill(DS.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radiusMedium)
                                    .stroke(
                                        descriptionFocused ? DS.borderActive : DS.border,
                                        lineWidth: 1
                                    )
                            )

                    }
                )
                .onChange(of: state.contentDescription) { _, _ in
                    state.lastModified = Date()
                    state.save()
                }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("OUTLINE")
                    .dsSectionLabel()

                if state.outline.isEmpty {
                    opusOutlineButton
                }

                Spacer()
                if !state.outline.isEmpty {
                    outlineCountLabel
                }
            }

            Text("Build out the structure of your content")
                .font(DS.sectionDesc)
                .foregroundStyle(DS.textSecondary)

            // AI-suggested label
            if state.isAISuggestedOutline && !state.outline.isEmpty {
                aiSuggestedBadge
            }

            // Outline items list
            VStack(spacing: 4) {
                ForEach(state.sortedOutline) { item in
                    ExpandableOutlineItemRow(
                        item: item,
                        onUpdateTitle: { title in
                            state.updateOutlineItem(id: item.id, title: title)
                            state.save()
                        },
                        onUpdateReasoning: { reasoning in
                            state.updateOutlineItemReasoning(id: item.id, reasoning: reasoning)
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
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(DS.title3)
                    .foregroundStyle(DS.accent.opacity(0.6))

                TextField("Add outline point...", text: $newOutlineText)
                    .textFieldStyle(.plain)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .onSubmit {
                        addOutlineItem()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
    private var outlineCountLabel: some View {
        HStack(spacing: 4) {
            Text("\(state.outline.count) items")
                .font(DS.timestamp)
                .foregroundStyle(DS.textMuted)
            if totalEstimatedSeconds > 0 {
                Text("~\(formattedDuration(totalEstimatedSeconds))")
                    .font(DS.timestamp)
                    .foregroundStyle(DS.accent.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var aiSuggestedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(DS.caption2)
            Text("AI-suggested outline")
                .font(DS.caption)
            Text("Click to expand details")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
        }
        .foregroundStyle(DS.accent.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DS.accent.opacity(0.1), in: Capsule())
    }

    private var totalEstimatedSeconds: Int {
        state.outline.compactMap(\.estimatedSeconds).reduce(0, +)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        }
        return "\(seconds)s"
    }


    // MARK: - Opus Outline Button

    @ViewBuilder
    private var opusOutlineButton: some View {
        if isGeneratingOpusOutline {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(DS.accent)
                Text("Generating...")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.accent)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { generateOpusOutline() }) {
                    opusOutlineButtonLabel
                }
                .buttonStyle(.plain)

                if let error = opusOutlineError {
                    Text(error)
                        .font(DS.footnote)
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
        }
    }

    @ViewBuilder
    private var opusOutlineButtonLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(DS.caption2)
            Text("Generate with Opus")
                .font(DS.buttonText)
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.accentSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func generateOpusOutline() {
        isGeneratingOpusOutline = true
        opusOutlineError = nil

        Task {
            if let engine = writingEngine {
                // Use unified engine — outline arrives via .unifiedEngineOutlineUpdate notification
                await engine.suggestOutline()
                await MainActor.run {
                    if let error = engine.error {
                        opusOutlineError = "Outline generation failed: \(error)"
                    }
                    isGeneratingOpusOutline = false
                }
            } else {
                await MainActor.run {
                    opusOutlineError = "Writing engine not initialized"
                    isGeneratingOpusOutline = false
                }
            }
        }
    }

    // MARK: - Actions

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


// MARK: - Expandable Outline Item Row

private struct ExpandableOutlineItemRow: View {
    let item: OutlineItem
    let onUpdateTitle: (String) -> Void
    let onUpdateReasoning: (String) -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isEditingTitle = false
    @State private var isEditingReasoning = false
    @State private var editTitle: String = ""
    @State private var editReasoning: String = ""
    @State private var isHovered = false
    @FocusState private var titleFocused: Bool
    @FocusState private var reasoningFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed row — always visible
            collapsedRow

            // Expanded reasoning section
            if isExpanded {
                expandedSection
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(
                            isExpanded ? DS.borderActive : DS.border,
                            lineWidth: 1
                        )
                )
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Collapsed Row

    @ViewBuilder
    private var collapsedRow: some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)

            // Number
            Text("\(item.sortOrder + 1).")
                .font(DS.timestamp)
                .foregroundStyle(DS.textMuted)
                .frame(width: 20, alignment: .trailing)

            // Title (editable on double-click)
            titleView

            Spacer(minLength: 4)

            // Duration badge
            if let seconds = item.estimatedSeconds, seconds > 0 {
                durationBadge(seconds)
            }

            // Expand chevron
            expandChevron

            // Controls (visible on hover)
            if isHovered {
                controlButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingTitle {
                withAnimation(ProMotionSprings.snappy) {
                    isExpanded.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("", text: $editTitle)
                .textFieldStyle(.plain)
                .font(DS.navTitle)
                .foregroundStyle(DS.text)
                .focused($titleFocused)
                .onSubmit { commitTitleEdit() }
                .onChange(of: titleFocused) { _, focused in
                    if !focused { commitTitleEdit() }
                }
        } else {
            Text(item.title)
                .font(DS.navTitle)
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    editTitle = item.title
                    isEditingTitle = true
                    titleFocused = true
                }
        }
    }

    @ViewBuilder
    private func durationBadge(_ seconds: Int) -> some View {
        Text("~\(formattedDuration(seconds))")
            .font(DS.caption2)
            .foregroundStyle(DS.accent.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(DS.accent.opacity(0.1))
            )
    }

    @ViewBuilder
    private var expandChevron: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
            .frame(width: 16)
    }

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: 2) {
            Button(action: {
                editTitle = item.title
                isEditingTitle = true
                titleFocused = true
            }) {
                Image(systemName: "pencil")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
    }

    // MARK: - Expanded Section

    @ViewBuilder
    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(DS.borderSubtle)
                .frame(height: 1)
                .padding(.horizontal, 12)

            if isEditingReasoning {
                reasoningEditor
            } else {
                reasoningDisplay
            }
        }
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var reasoningDisplay: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.reasoning.isEmpty {
                emptyReasoningPlaceholder
            } else {
                Text(item.reasoning)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) {
                        editReasoning = item.reasoning
                        isEditingReasoning = true
                        reasoningFocused = true
                    }
            }
        }
        .padding(.horizontal, 44) // aligned with title (drag handle + number width)
    }

    @ViewBuilder
    private var emptyReasoningPlaceholder: some View {
        Button(action: {
            editReasoning = ""
            isEditingReasoning = true
            reasoningFocused = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(DS.caption2)
                Text("Add notes, reasoning, or shooting details...")
                    .font(DS.footnote)
            }
            .foregroundStyle(DS.textMuted)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var reasoningEditor: some View {
        TextEditor(text: $editReasoning)
            .font(DS.subheadline)
            .foregroundStyle(DS.textSecondary)
            .scrollContentBackground(.hidden)
            .focused($reasoningFocused)
            .frame(minHeight: 60, maxHeight: 120)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.borderSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 44)
            .onChange(of: reasoningFocused) { _, focused in
                if !focused { commitReasoningEdit() }
            }
    }

    // MARK: - Helpers

    private func commitTitleEdit() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onUpdateTitle(trimmed)
        }
        isEditingTitle = false
    }

    private func commitReasoningEdit() {
        onUpdateReasoning(editReasoning)
        isEditingReasoning = false
    }

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        }
        return "\(seconds)s"
    }
}

// MARK: - Hook Item Row

private struct HookItemRow: View {
    let hook: String
    let index: Int
    let onUpdate: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Hook number
            Text("\(index + 1).")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, isEditing ? 4 : 0)

            if isEditing {
                MultilineHookEditor(
                    text: $editText,
                    isFocused: $isFocused,
                    fontSize: 14,
                    onCommit: { commitEdit() }
                )
            } else {
                Text(hook)
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) {
                        editText = hook
                        isEditing = true
                        isFocused = true
                    }
            }

            Spacer(minLength: 4)

            if isHovered {
                Button(action: {
                    editText = hook
                    isEditing = true
                    isFocused = true
                }) {
                    Image(systemName: "pencil")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        if !trimmed.isEmpty {
            onUpdate(trimmed)
        }
        isEditing = false
    }
}
