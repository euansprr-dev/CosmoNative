// Canvas/CommandCenter/TaskTitleMentionField.swift
// Mention-aware title input: type "@" to search and insert colored atom references
// March 2026

import SwiftUI

struct TaskTitleMentionField: View {

    @Binding var title: String
    @Binding var mentions: [RichMention]
    var onSubmit: () -> Void

    @State private var showMentionSearch = false
    @State private var mentionQuery = ""
    @State private var mentionResults: [MentionSearchResult] = []
    @State private var mentionInsertionPoint: String.Index?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title with colored mentions rendered inline
            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.text)
                .focused($isFocused)
                .onSubmit { onSubmit() }
                .onChange(of: title) {
                    detectMentionTrigger()
                }

            // Mention search popup
            if showMentionSearch {
                mentionSearchOverlay
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showMentionSearch)
    }

    // MARK: - Mention Search Overlay

    private var mentionSearchOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "at")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.accent)

                Text("Link an item")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textMuted)

                Spacer()

                Button {
                    cancelMention()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }

            if mentionResults.isEmpty && !mentionQuery.isEmpty {
                Text("No results for \"\(mentionQuery)\"")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
                    .padding(.vertical, 4)
            } else {
                ForEach(mentionResults.prefix(5)) { result in
                    mentionResultRow(result)
                }
            }
        }
        .padding(8)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.borderSubtle, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }

    @ViewBuilder
    private func mentionResultRow(_ result: MentionSearchResult) -> some View {
        let color = CosmoMentionColors.color(for: result.entityType)

        Button {
            insertMention(result)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: result.entityType.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 14)

                Text(result.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer()

                Text(result.typeLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(CosmoMentionColors.pillBackground(for: result.entityType), in: Capsule())
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mention Detection

    private func detectMentionTrigger() {
        // Find the last "@" in the title that isn't already a completed mention
        guard let atIndex = title.lastIndex(of: "@") else {
            if showMentionSearch { cancelMention() }
            return
        }

        // Check if this "@" is part of an existing mention
        let afterAt = title[title.index(after: atIndex)...]
        for mention in mentions {
            if afterAt.hasPrefix(mention.titleSnapshot) {
                // This "@" is already a completed mention, ignore
                return
            }
        }

        // Extract the query text after "@"
        let query = String(afterAt)

        // If query has a space and is long, it's probably not a mention trigger
        if query.count > 30 {
            cancelMention()
            return
        }

        mentionInsertionPoint = atIndex
        mentionQuery = query
        showMentionSearch = true

        Task {
            let results = await MentionSearchProvider.shared.search(query: query, limit: 5)
            await MainActor.run {
                mentionResults = results
            }
        }
    }

    private func insertMention(_ result: MentionSearchResult) {
        guard let atIndex = mentionInsertionPoint else { return }

        // Replace "@query" with "@Title"
        let endOfQuery = title.endIndex
        let rangeToReplace = atIndex..<endOfQuery

        // Build the mention text
        let mentionText = "@\(result.title)"

        // Replace in the title
        title.replaceSubrange(rangeToReplace, with: mentionText)

        // Add to mentions array
        let mention = result.mention
        if !mentions.contains(where: { $0.entityUUID == mention.entityUUID }) {
            mentions.append(mention)
        }

        // Clean up
        cancelMention()
    }

    private func cancelMention() {
        showMentionSearch = false
        mentionQuery = ""
        mentionResults = []
        mentionInsertionPoint = nil
    }
}

// MARK: - Task Title Renderer (for task rows)

/// Renders a task title with colored mention spans as tappable buttons
struct TaskTitleWithMentions: View {

    let title: String
    let mentions: [RichMention]
    var font: Font = .system(size: 13)
    var onMentionTap: ((RichMention) -> Void)?

    var body: some View {
        if mentions.isEmpty {
            Text(title)
                .font(font)
                .foregroundStyle(DS.text)
                .lineLimit(1)
        } else {
            titleWithMentions
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var titleWithMentions: some View {
        let segments = parseTitleSegments()

        HStack(spacing: 0) {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                switch segment {
                case .text(let text):
                    Text(text)
                        .font(font)
                        .foregroundStyle(DS.text)
                case .mention(let text, let mention):
                    Button {
                        onMentionTap?(mention)
                    } label: {
                        Text(text)
                            .font(font.weight(.semibold))
                            .foregroundStyle(CosmoMentionColors.color(for: mention.entityType))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(mention.titleSnapshot)")
                }
            }
        }
    }

    private enum TitleSegment {
        case text(String)
        case mention(String, RichMention)
    }

    private func parseTitleSegments() -> [TitleSegment] {
        var segments: [TitleSegment] = []
        var remaining = title

        // Sort mentions by their position in the title (first occurrence)
        let sortedMentions = mentions.sorted { m1, m2 in
            let pos1 = remaining.range(of: "@\(m1.titleSnapshot)")?.lowerBound ?? remaining.endIndex
            let pos2 = remaining.range(of: "@\(m2.titleSnapshot)")?.lowerBound ?? remaining.endIndex
            return pos1 < pos2
        }

        for mention in sortedMentions {
            let mentionText = "@\(mention.titleSnapshot)"
            guard let range = remaining.range(of: mentionText) else { continue }

            // Text before the mention
            let before = String(remaining[remaining.startIndex..<range.lowerBound])
            if !before.isEmpty {
                segments.append(.text(before))
            }

            // The mention itself
            segments.append(.mention(mentionText, mention))

            // Continue with the rest
            remaining = String(remaining[range.upperBound...])
        }

        // Any remaining text after last mention
        if !remaining.isEmpty {
            segments.append(.text(remaining))
        }

        return segments
    }
}
