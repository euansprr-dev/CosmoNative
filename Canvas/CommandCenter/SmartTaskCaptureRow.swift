// Canvas/CommandCenter/SmartTaskCaptureRow.swift
// Todoist-style smart capture with live natural language parsing
// March 2026

import SwiftUI
import Combine

struct SmartTaskCaptureRow: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel
    @State private var parsedInput = ParsedTaskInput(title: "")
    @State private var parseDebounce: AnyCancellable?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Input row
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isFocused ? DS.accent : DS.textMuted)

                ZStack(alignment: .leading) {
                    if viewModel.newTaskTitle.isEmpty {
                        Text("Add task... (try \"Write reels p1 tomorrow 2pm\")")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "767685"))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $viewModel.newTaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "1A1A1F"))
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
                            .font(.system(size: 12))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

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
        ScrollView(.horizontal, showsIndicators: false) {
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
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func metadataChip(icon: String, label: String, color: Color, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))

                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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

        let parsed = TaskInputParser.parse(title)
        viewModel.newTaskTitle = ""
        parsedInput = ParsedTaskInput(title: "")

        // Create task with parsed metadata
        await viewModel.smartAddTask(parsed)

        // Re-focus the text field for rapid entry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
