// CosmoOS/Scheduler/Shared/ContextDrawerView.swift
// Context drawer for viewing and managing semantic links
//
// Design Philosophy:
// - Slide-in panel from the right edge
// - Shows block details and all semantic connections
// - Quick actions for editing and linking
// - AI-suggested related items surface here

import SwiftUI

// MARK: - Context Drawer View

/// Right-side drawer showing block details and semantic links
public struct ContextDrawerView: View {

    // MARK: - State

    @ObservedObject var engine: SchedulerEngine
    let block: ScheduleBlock

    @State private var animateIn: Bool = false
    @State private var isEditingTitle: Bool = false
    @State private var editedTitle: String = ""

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            drawerHeader

            Divider()
                .background(CosmoColors.glassGrey.opacity(0.3))

            // Scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Block details section
                    detailsSection

                    // Quick actions
                    quickActionsSection

                    // Semantic links section
                    if let links = block.semanticLinks, !links.isEmpty {
                        semanticLinksSection(links: links)
                    }

                    // AI suggestions section
                    suggestionsSection

                    // Notes section
                    notesSection

                    // Danger zone
                    dangerZone
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SchedulerColors.drawerBackground)
        .onAppear {
            editedTitle = block.title
            withAnimation(SchedulerSprings.expand.delay(0.1)) {
                animateIn = true
            }
        }
    }

    // MARK: - Header

    private var drawerHeader: some View {
        HStack(spacing: 12) {
            // Block type icon
            ZStack {
                Circle()
                    .fill(SchedulerColors.color(for: block.blockType).opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: block.blockType.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(SchedulerColors.color(for: block.blockType))
            }

            // Title (editable on tap)
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: saveTitle)
                    .font(CosmoTypography.titleSmall)
                    .textFieldStyle(.plain)
                    .onSubmit { saveTitle() }
            } else {
                Text(block.title)
                    .font(CosmoTypography.titleSmall)
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(2)
                    .onTapGesture {
                        isEditingTitle = true
                    }
            }

            Spacer()

            // Close button
            Button {
                engine.closeDrawer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CosmoColors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(CosmoColors.glassGrey.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerSectionHeader(title: "Details", systemImage: "info.circle")

            // Time
            if block.isScheduled {
                DetailRow(
                    label: "Time",
                    value: block.formattedTimeRange,
                    systemImage: "clock"
                )
            }

            // Duration
            DetailRow(
                label: "Duration",
                value: block.formattedDuration,
                systemImage: "timer"
            )

            // Priority
            DetailRow(
                label: "Priority",
                value: block.priority.displayName,
                systemImage: "flag",
                valueColor: SchedulerColors.color(for: block.priority)
            )

            // Status (for completable types)
            if let status = block.status {
                DetailRow(
                    label: "Status",
                    value: status.displayName,
                    systemImage: statusIcon(for: status),
                    valueColor: SchedulerColors.color(for: status)
                )
            }

            // Origin
            if let origin = block.originType {
                DetailRow(
                    label: "Created via",
                    value: originDisplayName(origin),
                    systemImage: originIcon(origin)
                )
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(SchedulerSprings.staggered(index: 0), value: animateIn)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerSectionHeader(title: "Quick Actions", systemImage: "bolt")

            HStack(spacing: 10) {
                // Edit
                QuickActionButton(
                    label: "Edit",
                    systemImage: "pencil",
                    color: CosmoColors.lavender
                ) {
                    engine.openEditor(for: block)
                }

                // Complete/Undo
                if block.blockType.supportsCompletion {
                    QuickActionButton(
                        label: block.isCompleted ? "Undo" : "Done",
                        systemImage: block.isCompleted ? "arrow.uturn.backward" : "checkmark",
                        color: CosmoColors.emerald
                    ) {
                        Task {
                            try? await engine.toggleCompletion(for: block)
                        }
                    }
                }

                // Reschedule
                QuickActionButton(
                    label: "Move",
                    systemImage: "calendar.badge.clock",
                    color: CosmoColors.skyBlue
                ) {
                    // TODO: Open date picker
                }
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(SchedulerSprings.staggered(index: 1), value: animateIn)
    }

    // MARK: - Semantic Links Section

    private func semanticLinksSection(links: ScheduleSemanticLinks) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerSectionHeader(title: "Linked Items", systemImage: "link")

            VStack(spacing: 8) {
                // Ideas
                if let ideas = links.ideas, !ideas.isEmpty {
                    ForEach(ideas, id: \.self) { ideaUuid in
                        LinkedItemRow(
                            uuid: ideaUuid,
                            entityType: .idea,
                            onTap: {
                                // TODO: Navigate to idea
                            }
                        )
                    }
                }

                // Research
                if let research = links.research, !research.isEmpty {
                    ForEach(research, id: \.self) { researchUuid in
                        LinkedItemRow(
                            uuid: researchUuid,
                            entityType: .research,
                            onTap: {
                                // TODO: Navigate to research
                            }
                        )
                    }
                }

                // Connections
                if let connections = links.connections, !connections.isEmpty {
                    ForEach(connections, id: \.self) { connectionUuid in
                        LinkedItemRow(
                            uuid: connectionUuid,
                            entityType: .connection,
                            onTap: {
                                // TODO: Navigate to connection
                            }
                        )
                    }
                }
            }

            // Add link button
            Button {
                // TODO: Open link picker
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                    Text("Add Link")
                        .font(CosmoTypography.label)
                }
                .foregroundColor(CosmoColors.lavender)
            }
            .buttonStyle(.plain)
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(SchedulerSprings.staggered(index: 2), value: animateIn)
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerSectionHeader(title: "Suggested", systemImage: "sparkles")

            // Placeholder for AI suggestions
            VStack(spacing: 8) {
                DrawerSuggestionRow(
                    title: "Related idea might help",
                    subtitle: "Based on semantic similarity",
                    systemImage: "lightbulb",
                    color: CosmoColors.idea
                )

                DrawerSuggestionRow(
                    title: "Consider scheduling earlier",
                    subtitle: "You're usually more productive in mornings",
                    systemImage: "clock.arrow.circlepath",
                    color: CosmoColors.skyBlue
                )
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(SchedulerSprings.staggered(index: 3), value: animateIn)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawerSectionHeader(title: "Notes", systemImage: "note.text")

            if let notes = block.notes, !notes.isEmpty {
                Text(notes)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CosmoColors.glassGrey.opacity(0.2))
                    )
            } else {
                Button {
                    engine.openEditor(for: block)
                } label: {
                    Text("Add notes...")
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(CosmoColors.glassGrey.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(SchedulerSprings.staggered(index: 4), value: animateIn)
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(role: .destructive) {
                Task {
                    try? await engine.deleteBlock(block)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("Delete Block")
                        .font(CosmoTypography.label)
                }
                .foregroundColor(CosmoColors.softRed)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CosmoColors.softRed.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(SchedulerSprings.staggered(index: 5), value: animateIn)
    }

    // MARK: - Helpers

    private func saveTitle() {
        guard editedTitle != block.title, !editedTitle.isEmpty else {
            isEditingTitle = false
            return
        }

        var updatedBlock = block
        updatedBlock.title = editedTitle

        Task {
            try? await engine.updateBlock(updatedBlock)
        }

        isEditingTitle = false
    }

    private func statusIcon(for status: ScheduleBlockStatus) -> String {
        switch status {
        case .todo: return "circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .deferred: return "clock.arrow.circlepath"
        }
    }

    private func originDisplayName(_ origin: ScheduleBlockOrigin) -> String {
        switch origin {
        case .idea: return "Idea"
        case .voice: return "Voice Command"
        case .manual: return "Manual"
        case .recurring: return "Recurring"
        case .imported: return "Imported"
        case .quickCapture: return "Quick Capture"
        case .template: return "Template"
        }
    }

    private func originIcon(_ origin: ScheduleBlockOrigin) -> String {
        switch origin {
        case .idea: return "lightbulb"
        case .voice: return "mic"
        case .manual: return "hand.tap"
        case .recurring: return "repeat"
        case .imported: return "square.and.arrow.down"
        case .quickCapture: return "bolt"
        case .template: return "doc.on.doc"
        }
    }
}

// MARK: - Section Header

private struct DrawerSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CosmoColors.textTertiary)

            Text(title)
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String
    let systemImage: String
    var valueColor: Color = CosmoColors.textPrimary

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundColor(CosmoColors.textTertiary)
                    .frame(width: 16)

                Text(label)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textSecondary)
            }

            Spacer()

            Text(value)
                .font(CosmoTypography.body)
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)

                Text(label)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? color.opacity(0.15) : color.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
    }
}

// MARK: - Linked Item Row

private struct LinkedItemRow: View {
    let uuid: String
    let entityType: EntityType
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    // Would fetch actual title from database - placeholder for now
    private var title: String { "Linked \(entityType.rawValue)" }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Entity type indicator
                Circle()
                    .fill(CosmoMentionColors.color(for: entityType).opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: entityTypeIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(CosmoMentionColors.color(for: entityType))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textPrimary)
                        .lineLimit(1)

                    Text(entityType.rawValue.capitalized)
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CosmoColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? CosmoColors.glassGrey.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
    }

    private var entityTypeIcon: String {
        switch entityType {
        case .idea: return "lightbulb"
        case .content: return "doc.text"
        case .task: return "checkmark.circle"
        case .research: return "magnifyingglass"
        case .connection: return "person.2"
        case .note: return "note.text"
        case .project: return "folder"
        default: return "circle"
        }
    }
}

// MARK: - Suggestion Row

private struct DrawerSuggestionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? CosmoColors.glassGrey.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CosmoColors.glassGrey.opacity(0.2), lineWidth: 1)
                )
        )
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
    }
}

// MARK: - Preview

#if DEBUG
struct ContextDrawerView_Previews: PreviewProvider {
    static var previews: some View {
        let engine = SchedulerEngine()
        var block = ScheduleBlock.task(title: "Review design specs")
        block.semanticLinks = ScheduleSemanticLinks()
        block.semanticLinks?.ideas = ["idea-1", "idea-2"]

        return ContextDrawerView(engine: engine, block: block)
            .frame(width: SchedulerDimensions.drawerWidth, height: 700)
    }
}
#endif
