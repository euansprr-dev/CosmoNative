// CosmoOS/Canvas/ContentBlockView.swift
// Blue-accented Content block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Thinkspace revamp

import SwiftUI

struct ContentBlockView: View {
    let block: CanvasBlock

    @State private var contentTitle: String = ""
    @State private var contentBody: String = ""
    @State private var isExpanded = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool

    // Auto-save debouncing
    @State private var autoSaveTask: Task<Void, Never>?

    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Blue accent for content
    private let accentColor = CosmoMentionColors.content

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "doc.text.fill",
            title: displayTitle,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            contentView
        }
        .onAppear {
            loadContent()
        }
    }

    // MARK: - Display Title

    private var displayTitle: String {
        // Use title field, or fall back to first line of content
        if !contentTitle.isEmpty {
            return String(contentTitle.prefix(40))
        }
        if let firstLine = contentBody.components(separatedBy: .newlines).first,
           !firstLine.isEmpty {
            return String(firstLine.prefix(40))
        }
        return "Untitled Content"
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        // Always use editableContentView for canvas blocks
        // Content is stored in metadata like Note blocks
        editableContentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editable Content View (for new blocks)

    private var editableContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title field
            ZStack(alignment: .topLeading) {
                // Placeholder
                if contentTitle.isEmpty {
                    Text("Heading")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .italic()
                        .foregroundColor(Color.white.opacity(0.35))
                        .allowsHitTesting(false)
                }

                // Title text field
                TextField("", text: $contentTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundColor(.white)
                    .focused($isTitleFocused)
                    .onSubmit {
                        isBodyFocused = true
                    }
            }

            // Body text editor
            ZStack(alignment: .topLeading) {
                // Placeholder
                if contentBody.isEmpty && !isBodyFocused {
                    Text("Press / for commands...")
                        .font(.system(size: 15))
                        .foregroundColor(Color.white.opacity(0.35))
                        .allowsHitTesting(false)
                }

                // Body text editor
                TextEditor(text: $contentBody)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isBodyFocused)
            }
            .frame(maxHeight: .infinity)

            // Timestamp at bottom
            if let timestamp = block.metadata["created"] {
                HStack {
                    Spacer()
                    Text(formatTimestamp(timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.3))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: contentTitle) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: contentBody) { _, _ in
            scheduleAutoSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .blurAllBlocks)) { _ in
            isTitleFocused = false
            isBodyFocused = false
        }
    }

    // MARK: - Auto-save

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    saveContent()
                }
            }
        }
    }

    private func saveContent() {
        NotificationCenter.default.post(
            name: .updateBlockContent,
            object: nil,
            userInfo: [
                "blockId": block.id,
                "title": contentTitle,
                "content": contentBody
            ]
        )
    }

    // MARK: - Load Content

    private func loadContent() {
        if let title = block.metadata["title"] {
            contentTitle = title
        }
        if let content = block.metadata["content"] {
            contentBody = content
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.content,
                "id": block.entityId,
                "blockId": block.id,
                "content": contentBody
            ]
        )
    }

    // MARK: - Helpers

    private func formatTimestamp(_ timestamp: String) -> String {
        if let date = ISO8601DateFormatter().date(from: timestamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }
}

// MARK: - Content Stats Bar

struct ContentStatsBar: View {
    let wordCount: Int
    let readingTime: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            // Word count
            HStack(spacing: 4) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 10))
                Text("\(wordCount) words")
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(CosmoColors.textTertiary)

            // Reading time
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(readingTime)
                    .font(CosmoTypography.caption)
            }
            .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            // Status badge
            StatusBadge(status: status)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String

    private var statusColor: Color {
        switch status.lowercased() {
        case "published", "complete": return CosmoColors.emerald
        case "draft": return CosmoColors.glassGrey
        case "review", "editing": return CosmoColors.lavender
        case "archived": return CosmoColors.textTertiary
        default: return CosmoColors.glassGrey
        }
    }

    private var statusIcon: String {
        switch status.lowercased() {
        case "published", "complete": return "checkmark.circle.fill"
        case "draft": return "doc.text"
        case "review", "editing": return "pencil.circle"
        case "archived": return "archivebox"
        default: return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 10))
            Text(status.capitalized)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
    }
}

// MARK: - Content Type Badge

struct ContentTypeBadge: View {
    let type: String

    private var typeColor: Color {
        switch type.lowercased() {
        case "article", "blog": return CosmoMentionColors.content
        case "script", "video": return CosmoColors.coral
        case "newsletter", "email": return CosmoColors.lavender
        case "social", "post": return CosmoColors.skyBlue
        default: return CosmoColors.glassGrey
        }
    }

    private var typeIcon: String {
        switch type.lowercased() {
        case "article", "blog": return "doc.richtext"
        case "script", "video": return "film"
        case "newsletter", "email": return "envelope"
        case "social", "post": return "bubble.left"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: typeIcon)
                .font(.system(size: 10))
            Text(type.capitalized)
                .font(CosmoTypography.caption)
        }
        .foregroundColor(typeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(typeColor.opacity(0.1), in: Capsule())
    }
}

// MARK: - Content Detailed Stats

struct ContentDetailedStats: View {
    let wordCount: Int
    let characterCount: Int
    let paragraphCount: Int

    var body: some View {
        HStack(spacing: 16) {
            StatItem(value: "\(wordCount)", label: "Words", icon: "text.word.spacing")
            StatItem(value: "\(characterCount)", label: "Characters", icon: "character")
            StatItem(value: "\(paragraphCount)", label: "Paragraphs", icon: "text.alignleft")
        }
        .padding(12)
        .background(CosmoMentionColors.content.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(value)
                    .font(CosmoTypography.titleSmall)
            }
            .foregroundColor(CosmoMentionColors.content)

            Text(label)
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
        }
    }
}

// MARK: - Content Metadata View

struct ContentMetadataView: View {
    let content: ContentWrapper

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                MetadataRow(icon: "calendar", label: "Created", value: formatDate(content.createdAt))
                MetadataRow(icon: "pencil", label: "Updated", value: formatDate(content.updatedAt))

                if let lastOpened = content.lastOpenedAt {
                    MetadataRow(icon: "eye", label: "Last opened", value: formatDate(lastOpened))
                }

                if let scheduledAt = content.scheduledAt {
                    MetadataRow(icon: "calendar.badge.clock", label: "Scheduled", value: formatDate(scheduledAt))
                }
            }
        }
        .padding(12)
        .background(CosmoColors.mistGrey.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
                .frame(width: 16)

            Text(label)
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            Text(value)
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)
        }
    }
}

// MARK: - Content Footer

struct ContentFooter: View {
    let content: ContentWrapper
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Last updated
            Text(timeAgo(from: content.updatedAt))
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)

            Spacer()

            // Actions (visible when expanded)
            if isExpanded {
                Button(action: copyContent) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy")
                            .font(CosmoTypography.caption)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: exportContent) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Export")
                            .font(CosmoTypography.caption)
                    }
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
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
        guard let body = content.body else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
    }

    private func exportContent() {
        // Future: implement export functionality
    }
}
