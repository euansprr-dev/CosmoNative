// Canvas/CommandCenter/SmartTaskCaptureRow.swift
// Todoist-style smart capture with live natural language parsing
// March 2026

import SwiftUI
import Combine

struct SmartTaskCaptureRow: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    var contextProjectUUID: String? = nil
    var contextHeadingUUID: String? = nil
    var placeholderText: String = "Add task... (try \"Write at 6pm every Tue\")"
    @State private var parsedInput = ParsedTaskInput(title: "")
    @State private var parseDebounce: AnyCancellable?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Input row
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
                        }
                }

                if !viewModel.newTaskTitle.isEmpty {
                    Button {
                        viewModel.newTaskTitle = ""
                        parsedInput = ParsedTaskInput(title: "")
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

            // Parsed metadata chips (only when typing)
            if !viewModel.newTaskTitle.isEmpty && hasAnyMetadata {
                metadataChips
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(ProMotionSprings.snappy, value: hasAnyMetadata)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.cosmo.commandCenter.quickAddTask"))) { _ in
            isFocused = true
        }
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

                if let intent = parsedInput.intent {
                    metadataChip(
                        icon: intent.iconName,
                        label: intent.displayName,
                        color: intent.color
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
        viewModel.newTaskTitle = ""
        parsedInput = ParsedTaskInput(title: "")

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
