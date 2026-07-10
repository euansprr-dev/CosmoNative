// Canvas/CommandCenter/SmartTaskCaptureRow.swift
// Todoist-style smart capture with live natural language parsing
// March 2026

import SwiftUI
import Combine

struct SmartTaskCaptureRow: View {

    @Bindable var viewModel: CommandCenterDashboardViewModel
    var contextProjectUUID: String? = nil
    var contextHeadingUUID: String? = nil
    var placeholderText: String = "Add task... (try \"Write at 6pm every Tue\")"
    @State private var parsedInput = ParsedTaskInput(title: "")
    @State private var parseDebounce: AnyCancellable?
    @FocusState private var isFocused: Bool

    // Mention state
    @State private var capturedMentions: [RichMention] = []
    @State private var showMentionSearch = false
    @State private var mentionQuery = ""
    @State private var mentionResults: [MentionSearchResult] = []
    @State private var mentionInsertionPoint: String.Index?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Input row
            inputRow

            // Mention search overlay
            if showMentionSearch {
                mentionSearchOverlay
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Parsed metadata chips (only when typing)
            if !viewModel.newTaskTitle.isEmpty && hasAnyMetadata {
                metadataChips
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(ProMotionSprings.snappy, value: hasAnyMetadata)
        .animation(.easeInOut(duration: 0.15), value: showMentionSearch)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.commandCenter.quickAddTask"))) { _ in
            isFocused = true
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "plus")
                .font(DS.cardMeta)
                .foregroundStyle(isFocused ? DS.accent : DS.textMuted)

            ZStack(alignment: .leading) {
                if viewModel.newTaskTitle.isEmpty {
                    Text(placeholderText)
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                        .allowsHitTesting(false)
                }
                TextField("", text: $viewModel.newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .focused($isFocused)
                    .onSubmit {
                        Task { await submitTask() }
                    }
                    .onChange(of: viewModel.newTaskTitle) { _, newValue in
                        debounceParseInput(newValue)
                        detectMentionTrigger(in: newValue)
                    }
            }

            if !viewModel.newTaskTitle.isEmpty {
                Button {
                    viewModel.newTaskTitle = ""
                    parsedInput = ParsedTaskInput(title: "")
                    capturedMentions = []
                    cancelMention()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.cardMeta)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
    }

    // MARK: - Mention Search Overlay

    private var mentionSearchOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "at")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)

                Text("Link an item")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)

                Spacer()

                if !mentionResults.isEmpty {
                    Text("\(mentionResults.prefix(5).count) results")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }

                Button {
                    cancelMention()
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            }

            if mentionResults.isEmpty && !mentionQuery.isEmpty {
                Text("No results for \"\(mentionQuery)\"")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .padding(.vertical, 4)
            } else {
                ForEach(mentionResults.prefix(5)) { result in
                    mentionResultRow(result)
                }
            }
        }
        .padding(8)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.borderSubtle, lineWidth: 1))
        .padding(.horizontal, DS.space10)
    }

    @ViewBuilder
    private func mentionResultRow(_ result: MentionSearchResult) -> some View {
        let color = CosmoMentionColors.color(for: result.entityType)

        Button {
            insertMention(result)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: result.entityType.icon)
                    .font(DS.caption2)
                    .foregroundStyle(color)
                    .frame(width: 14)

                Text(result.title)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer()

                Text(result.typeLabel)
                    .font(DS.caption2)
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(CosmoMentionColors.pillBackground(for: result.entityType), in: Capsule())
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(.rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mention Logic

    private func detectMentionTrigger(in text: String) {
        guard let atIndex = text.lastIndex(of: "@") else {
            if showMentionSearch { cancelMention() }
            return
        }

        // Check if this "@" is part of an existing mention
        let afterAt = text[text.index(after: atIndex)...]
        for mention in capturedMentions {
            if afterAt.hasPrefix(mention.titleSnapshot) {
                return
            }
        }

        let query = String(afterAt)

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

        let mentionText = "@\(result.title)"
        let endOfQuery = viewModel.newTaskTitle.endIndex
        let rangeToReplace = atIndex..<endOfQuery
        viewModel.newTaskTitle.replaceSubrange(rangeToReplace, with: "\(mentionText) ")

        let mention = result.mention
        if !capturedMentions.contains(where: { $0.entityUUID == mention.entityUUID }) {
            capturedMentions.append(mention)
        }

        cancelMention()
    }

    private func cancelMention() {
        showMentionSearch = false
        mentionQuery = ""
        mentionResults = []
        mentionInsertionPoint = nil
    }

    // MARK: - Metadata Chips

    private var metadataChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if let priority = parsedInput.priority {
                    metadataChip(
                        icon: "flag.fill",
                        label: priority.displayName,
                        color: priority.color
                    ) {
                        // Cycle through priorities
                        parsedInput.priority = cyclePriority(from: priority)
                    }
                }

                if let date = parsedInput.dueDate {
                    metadataChip(
                        icon: "calendar",
                        label: formatChipDate(date),
                        color: DS.accent
                    )
                }

                if let time = parsedInput.scheduledTime {
                    metadataChip(
                        icon: "clock",
                        label: time.formatted(.dateTime.hour().minute()),
                        color: DS.info
                    )
                }

                if parsedInput.intent != nil || parsedInput.intentUUID != nil {
                    let intentPresentation = CommandCenterIntentEngine.shared.resolvedPresentation(
                        intentUUID: parsedInput.intentUUID,
                        legacyIntentRaw: parsedInput.intent?.rawValue
                    )
                    metadataChip(
                        icon: intentPresentation.icon,
                        label: intentPresentation.title,
                        color: intentPresentation.accent
                    )
                }

                if let habitTitle = parsedInput.habitTitle {
                    metadataChip(
                        icon: parsedInput.habitIcon ?? "repeat",
                        label: habitTitle,
                        color: parsedInput.habitColorHex.map(Color.init(hex:)) ?? DS.accent
                    )
                }

                if let recurrenceRule = parsedInput.recurrenceRule {
                    metadataChip(
                        icon: "repeat",
                        label: recurrenceRule.shortDisplayText,
                        color: DS.accent
                    )
                }

                // Things 3 scheduling chips
                if let projectName = parsedInput.projectName {
                    metadataChip(
                        icon: "folder.fill",
                        label: "#\(projectName)",
                        color: DS.accent
                    )
                }

                if let timeOfDay = parsedInput.timeOfDay {
                    metadataChip(
                        icon: timeOfDay == "morning" ? "sun.horizon" : "moon.stars",
                        label: timeOfDay.capitalized,
                        color: timeOfDay == "morning" ? DS.orange : DS.entityIdea
                    )
                }

                if let state = parsedInput.schedulingState {
                    metadataChip(
                        icon: state == "someday" ? "archivebox" : "tray.full",
                        label: state.capitalized,
                        color: DS.entityIdea
                    )
                }

                if let deadline = parsedInput.deadline {
                    metadataChip(
                        icon: "flag.fill",
                        label: "Deadline: \(formatChipDate(deadline))",
                        color: DS.orange
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func metadataChip(icon: String, label: String, color: Color, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: DS.space2) {
                Image(systemName: icon)
                    .font(DS.caption2)

                Text(label)
                    .font(DS.caption2)
            }
            .foregroundStyle(color)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, DS.space4)
            .background(color.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private var hasAnyMetadata: Bool {
        parsedInput.priority != nil
            || parsedInput.dueDate != nil
            || parsedInput.scheduledTime != nil
            || parsedInput.intent != nil
            || parsedInput.habitUUID != nil
            || parsedInput.recurrenceRule != nil
            || parsedInput.projectName != nil
            || parsedInput.timeOfDay != nil
            || parsedInput.schedulingState != nil
            || parsedInput.deadline != nil
    }

    private func debounceParseInput(_ text: String) {
        parseDebounce?.cancel()
        parseDebounce = Just(text)
            .delay(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { value in
                if !value.isEmpty {
                    parsedInput = TaskInputParser.parse(value)
                } else {
                    parsedInput = ParsedTaskInput(title: "")
                }
            }
    }

    private func submitTask() async {
        let title = viewModel.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        var parsed = TaskInputParser.parse(title)
        // Inject context from the current view (project/heading)
        parsed.contextProjectUUID = contextProjectUUID
        parsed.contextHeadingUUID = contextHeadingUUID
        parsed.mentions = capturedMentions
        viewModel.newTaskTitle = ""
        parsedInput = ParsedTaskInput(title: "")
        capturedMentions = []

        // Create task with parsed metadata
        await viewModel.smartAddTask(parsed)

        // Re-focus the text field for rapid entry
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isFocused = true
        }
    }

    private func cyclePriority(from current: TaskPriority) -> TaskPriority {
        switch current {
        case .critical: return .high
        case .high: return .medium
        case .medium: return .low
        case .low: return .critical
        }
    }

    private func formatChipDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
