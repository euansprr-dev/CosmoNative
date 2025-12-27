// CosmoOS/Canvas/IdeaBlockView.swift
// Premium Idea block with tags, related ideas, and expansion support
// Warm amber glow aesthetic for creativity and inspiration

import SwiftUI
import GRDB

struct IdeaBlockView: View {
    let block: CanvasBlock

    @State private var idea: Idea?
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var isLoading = true
    @State private var relatedIdeas: [Idea] = []

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    private let database = CosmoDatabase.shared

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: CosmoMentionColors.idea,
            icon: "lightbulb.fill",
            title: idea?.title ?? block.title,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            contentView
        }
        .onAppear {
            loadIdea()
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                loadRelatedIdeas()
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if block.entityId > 0 {
            IdeaEditorView(ideaId: block.entityId, presentation: .embedded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            loadingView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Idea Content

    @ViewBuilder
    private func ideaContent(_ idea: Idea) -> some View {
        // Main content
        Text(idea.content)
            .font(CosmoTypography.body)
            .foregroundColor(CosmoColors.textPrimary)
            .lineLimit(isExpanded ? nil : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(BlockAnimations.contentFade, value: isExpanded)

        // Tags
        if !idea.tagsList.isEmpty {
            TagPillsView(tags: idea.tagsList, accentColor: CosmoMentionColors.idea)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        // Priority indicator
        PriorityIndicator(priority: idea.priority)

        // Expanded content
        if isExpanded {
            Divider()
                .background(CosmoMentionColors.idea.opacity(0.3))
                .padding(.vertical, 4)

            // Metadata
            IdeaMetadataView(idea: idea)

            // Related ideas
            if !relatedIdeas.isEmpty {
                RelatedIdeasSection(ideas: relatedIdeas) { relatedIdea in
                    openRelatedIdea(relatedIdea)
                }
            }
        }

        Spacer(minLength: 0)

        // Footer
        IdeaFooter(idea: idea, isExpanded: isExpanded)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading idea...")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 32))
                .foregroundColor(CosmoColors.textTertiary)
            Text("Idea not found")
                .font(CosmoTypography.body)
                .foregroundColor(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadIdea() {
        Task {
            idea = try? await database.asyncRead { db in
                guard let atom = try Atom
                    .filter(Column("id") == block.entityId)
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .fetchOne(db) else { return nil }
                return IdeaWrapper(atom: atom)
            }
            isLoading = false
        }
    }

    private func loadRelatedIdeas() {
        guard let currentIdea = idea else { return }

        Task {
            // Simple related ideas: same tags or same project
            let related = try? await database.asyncRead { db -> [Idea] in
                // Get ideas with matching tags or project
                let allAtoms = try Atom
                    .filter(Column("type") == AtomType.idea.rawValue)
                    .filter(Column("id") != currentIdea.id ?? -1)
                    .filter(Column("is_deleted") == false)
                    .limit(5)
                    .fetchAll(db)

                let allIdeas = allAtoms.map { IdeaWrapper(atom: $0) }

                // Filter by tag overlap
                let currentTags = Set(currentIdea.tagsList)
                if currentTags.isEmpty {
                    return Array(allIdeas.prefix(3))
                }

                return allIdeas.filter { idea in
                    !Set(idea.tagsList).isDisjoint(with: currentTags)
                }.prefix(3).map { $0 }
            }

            await MainActor.run {
                relatedIdeas = related ?? []
            }
        }
    }

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.idea, "id": idea?.id ?? block.entityId]
        )
    }

    private func openRelatedIdea(_ idea: Idea) {
        guard let id = idea.id else { return }
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: ["type": EntityType.idea, "id": id]
        )
    }
}

// MARK: - Tag Pills View

struct TagPillsView: View {
    let tags: [String]
    var accentColor: Color = CosmoMentionColors.idea
    var maxVisible: Int = 5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(tags.prefix(maxVisible).enumerated()), id: \.offset) { index, tag in
                    TagPill(tag: tag, color: accentColor, delay: Double(index) * 0.05)
                }

                // Overflow indicator
                if tags.count > maxVisible {
                    Text("+\(tags.count - maxVisible)")
                        .font(CosmoTypography.caption)
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
                }
            }
        }
    }
}

struct TagPill: View {
    let tag: String
    let color: Color
    let delay: Double

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8))
            Text(tag)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(BlockAnimations.staggered(index: Int(delay / 0.05))) {
                appeared = true
            }
        }
    }
}

// MARK: - Priority Indicator

struct PriorityIndicator: View {
    let priority: String

    private var priorityColor: Color {
        switch priority.lowercased() {
        case "high": return CosmoColors.coral
        case "medium": return CosmoColors.lavender
        case "low": return CosmoColors.emerald
        default: return CosmoColors.glassGrey
        }
    }

    private var priorityIcon: String {
        switch priority.lowercased() {
        case "high": return "flame.fill"
        case "medium": return "circle.fill"
        case "low": return "leaf.fill"
        default: return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: priorityIcon)
                .font(.system(size: 10))
            Text(priority)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(priorityColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(priorityColor.opacity(0.1), in: Capsule())
    }
}

// MARK: - Idea Metadata View

struct IdeaMetadataView: View {
    let idea: Idea

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            HStack(spacing: 16) {
                MetadataItem(icon: "calendar", label: "Created", value: formatDate(idea.createdAt))
                MetadataItem(icon: "pencil", label: "Updated", value: formatDate(idea.updatedAt))
            }

            if idea.isPinned {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                    Text("Pinned")
                        .font(CosmoTypography.caption)
                }
                .foregroundColor(CosmoMentionColors.idea)
            }
        }
        .padding(12)
        .background(CosmoColors.mistGrey.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none
        return displayFormatter.string(from: date)
    }
}

struct MetadataItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(CosmoColors.textTertiary)

            Text(value)
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textSecondary)
        }
    }
}

// MARK: - Related Ideas Section

struct RelatedIdeasSection: View {
    let ideas: [Idea]
    let onSelect: (Idea) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                Text("Related Ideas")
                    .font(CosmoTypography.label)
            }
            .foregroundColor(CosmoColors.textSecondary)

            VStack(spacing: 6) {
                ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                    RelatedIdeaRow(idea: idea, delay: Double(index) * 0.08)
                        .onTapGesture {
                            onSelect(idea)
                        }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct RelatedIdeaRow: View {
    let idea: Idea
    let delay: Double

    @State private var appeared = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 12))
                .foregroundColor(CosmoMentionColors.idea)

            Text(idea.title ?? "Untitled")
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textPrimary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
                .opacity(isHovered ? 1 : 0.5)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? CosmoMentionColors.idea.opacity(0.1) : CosmoColors.glassGrey.opacity(0.2))
        )
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(BlockAnimations.staggered(index: Int(delay / 0.08))) {
                appeared = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Idea Footer

struct IdeaFooter: View {
    let idea: Idea
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Timestamp
            Text(timeAgo(from: idea.updatedAt))
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            // Actions (visible when expanded)
            if isExpanded {
                Button(action: copyContent) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(CosmoColors.textSecondary)
                }
                .buttonStyle(.plain)

                Button(action: shareIdea) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                        .foregroundColor(CosmoColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return ""
        }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(idea.content, forType: .string)
    }

    private func shareIdea() {
        // Future: implement share functionality
    }
}
