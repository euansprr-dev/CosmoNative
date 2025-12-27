// CosmoOS/Scheduler/Shared/ScheduleBlockEditor.swift
// Inline floating editor for creating and editing schedule blocks
//
// Design Philosophy:
// - Floating card that appears near interaction point
// - Minimal required fields for quick creation
// - Expandable sections for advanced options
// - Premium spring animations on appear/dismiss

import SwiftUI

// MARK: - Schedule Block Editor

/// Floating card editor for creating and editing blocks
public struct ScheduleBlockEditor: View {

    // MARK: - State

    @ObservedObject var engine: SchedulerEngine
    let state: SchedulerEditorState

    // Form state
    @State private var title: String = ""
    @State private var blockType: ScheduleBlockType = .task
    @State private var startDate: Date = Date()
    @State private var startTime: Date = Date()
    @State private var duration: Int = 60 // minutes
    @State private var priority: ScheduleBlockPriority = .medium
    @State private var notes: String = ""
    @State private var showAdvanced: Bool = false

    // UI state
    @State private var animateIn: Bool = false
    @State private var titleFieldFocused: Bool = true
    @State private var isSaving: Bool = false
    @State private var error: String?

    @FocusState private var focusedField: EditorField?

    private var isEditing: Bool {
        state.existingBlock != nil
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            editorHeader

            Divider()
                .background(CosmoColors.glassGrey.opacity(0.3))

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Title field
                    titleSection

                    // Block type picker
                    blockTypeSection

                    // Time section
                    timeSection

                    // Priority section
                    prioritySection

                    // Advanced options (expandable)
                    if showAdvanced {
                        advancedSection
                    } else {
                        advancedToggle
                    }

                    // Error display
                    if let error = error {
                        errorBanner(message: error)
                    }
                }
                .padding(16)
            }

            Divider()
                .background(CosmoColors.glassGrey.opacity(0.3))

            // Footer actions
            editorFooter
        }
        .frame(width: SchedulerDimensions.editorCardWidth)
        .frame(maxHeight: SchedulerDimensions.editorCardMaxHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .scaleEffect(animateIn ? 1 : 0.95)
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            populateFromState()
            withAnimation(SchedulerSprings.expand) {
                animateIn = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .title
            }
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack {
            Text(isEditing ? "Edit Block" : "New Block")
                .font(CosmoTypography.titleSmall)
                .foregroundColor(CosmoColors.textPrimary)

            Spacer()

            // Close button
            Button {
                dismissEditor()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CosmoColors.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(CosmoColors.glassGrey.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            // Highlighted input with time expression detection
            ZStack(alignment: .leading) {
                // Highlighted overlay
                if title.isEmpty {
                    Text("Meeting at 3pm for 1 hour...")
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textTertiary)
                        .padding(12)
                } else {
                    HighlightedTimeText(text: title)
                        .padding(12)
                }

                // Actual text field (transparent text, visible caret)
                TextField("", text: $title)
                    .font(CosmoTypography.body)
                    .textFieldStyle(.plain)
                    .foregroundColor(.clear)
                    .padding(12)
                    .focused($focusedField, equals: .title)
                    .onChange(of: title) { _, newValue in
                        // Parse time expressions and auto-fill fields
                        parseTimeExpressions(from: newValue)
                    }
                    .onSubmit {
                        // Enter key submits the form
                        if canSave {
                            saveBlock()
                        }
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CosmoColors.glassGrey.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        focusedField == .title ? CosmoColors.lavender.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
    }

    // MARK: - Time Expression Parsing

    private func parseTimeExpressions(from text: String) {
        let lower = text.lowercased()

        // Parse "at Xpm" or "at X:XXam/pm"
        let atTimePattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: atTimePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            if let hourRange = Range(match.range(at: 1), in: lower),
               var hour = Int(lower[hourRange]) {
                var minute = 0
                if match.range(at: 2).location != NSNotFound,
                   let minRange = Range(match.range(at: 2), in: lower) {
                    minute = Int(lower[minRange]) ?? 0
                }
                if match.range(at: 3).location != NSNotFound,
                   let periodRange = Range(match.range(at: 3), in: lower) {
                    let period = String(lower[periodRange])
                    if period.contains("p") && hour < 12 { hour += 12 }
                    if period.contains("a") && hour == 12 { hour = 0 }
                } else if hour >= 1 && hour <= 6 {
                    hour += 12 // Assume PM for 1-6
                }
                // Update time
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: startDate)
                components.hour = hour
                components.minute = minute
                if let newTime = calendar.date(from: components) {
                    startTime = newTime
                }
            }
        }

        // Parse "from Xam/pm to Yam/pm"
        let rangePattern = #"from\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+to\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: rangePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            if let startHourRange = Range(match.range(at: 1), in: lower),
               var startHour = Int(lower[startHourRange]),
               let endHourRange = Range(match.range(at: 4), in: lower),
               var endHour = Int(lower[endHourRange]) {

                var startMinute = 0
                var endMinute = 0

                if match.range(at: 2).location != NSNotFound,
                   let minRange = Range(match.range(at: 2), in: lower) {
                    startMinute = Int(lower[minRange]) ?? 0
                }
                if match.range(at: 5).location != NSNotFound,
                   let minRange = Range(match.range(at: 5), in: lower) {
                    endMinute = Int(lower[minRange]) ?? 0
                }

                // Handle AM/PM
                if match.range(at: 3).location != NSNotFound,
                   let periodRange = Range(match.range(at: 3), in: lower) {
                    let period = String(lower[periodRange])
                    if period.contains("p") && startHour < 12 { startHour += 12 }
                    if period.contains("a") && startHour == 12 { startHour = 0 }
                } else if startHour >= 1 && startHour <= 6 { startHour += 12 }

                if match.range(at: 6).location != NSNotFound,
                   let periodRange = Range(match.range(at: 6), in: lower) {
                    let period = String(lower[periodRange])
                    if period.contains("p") && endHour < 12 { endHour += 12 }
                    if period.contains("a") && endHour == 12 { endHour = 0 }
                } else if endHour >= 1 && endHour <= 6 { endHour += 12 }

                // Calculate duration
                let startTotal = startHour * 60 + startMinute
                let endTotal = endHour * 60 + endMinute
                var durationMins = endTotal - startTotal
                if durationMins < 0 { durationMins += 24 * 60 }
                duration = max(15, durationMins)

                // Update start time
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: startDate)
                components.hour = startHour
                components.minute = startMinute
                if let newTime = calendar.date(from: components) {
                    startTime = newTime
                }
            }
        }

        // Parse "for Xh" or "for X hours" or "for Xm" or "for X minutes"
        let durationPattern = #"for\s+(\d+)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)"#
        if let regex = try? NSRegularExpression(pattern: durationPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            if let valueRange = Range(match.range(at: 1), in: lower),
               let value = Int(lower[valueRange]),
               let unitRange = Range(match.range(at: 2), in: lower) {
                let unit = String(lower[unitRange])
                if unit.starts(with: "h") {
                    duration = value * 60
                } else {
                    duration = value
                }
            }
        }

        // Parse "tomorrow"
        if lower.contains("tomorrow") {
            startDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? startDate
        }
    }

    // MARK: - Block Type Section

    private var blockTypeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            HStack(spacing: 8) {
                ForEach([ScheduleBlockType.task, .timeBlock, .focus], id: \.self) { type in
                    BlockTypeButton(
                        type: type,
                        isSelected: blockType == type,
                        action: {
                            withAnimation(SchedulerSprings.snappy) {
                                blockType = type
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            // Time picker only (date is always today for quick create)
            HStack(spacing: 12) {
                // Time
                DatePicker(
                    "",
                    selection: $startTime,
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(width: 80)

                Spacer()
            }

            // Duration picker
            HStack(spacing: 8) {
                Text("Duration:")
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textSecondary)

                DurationPicker(duration: $duration)
            }
        }
    }

    // MARK: - Priority Section

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Priority")
                .font(CosmoTypography.label)
                .foregroundColor(CosmoColors.textSecondary)

            HStack(spacing: 8) {
                ForEach(ScheduleBlockPriority.allCases, id: \.self) { level in
                    PriorityButton(
                        priority: level,
                        isSelected: priority == level,
                        action: {
                            withAnimation(SchedulerSprings.snappy) {
                                priority = level
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Advanced Toggle

    private var advancedToggle: some View {
        Button {
            withAnimation(SchedulerSprings.expand) {
                showAdvanced = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                Text("More options")
                    .font(CosmoTypography.label)
            }
            .foregroundColor(CosmoColors.textTertiary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Collapse button
            Button {
                withAnimation(SchedulerSprings.expand) {
                    showAdvanced = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .medium))
                    Text("Less options")
                        .font(CosmoTypography.label)
                }
                .foregroundColor(CosmoColors.textTertiary)
            }
            .buttonStyle(.plain)

            // Notes
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(CosmoTypography.label)
                    .foregroundColor(CosmoColors.textSecondary)

                TextEditor(text: $notes)
                    .font(CosmoTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CosmoColors.glassGrey.opacity(0.15))
                    )
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))

            Text(message)
                .font(CosmoTypography.bodySmall)
        }
        .foregroundColor(CosmoColors.softRed)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.softRed.opacity(0.1))
        )
    }

    // MARK: - Footer

    private var editorFooter: some View {
        HStack(spacing: 12) {
            // Cancel
            Button {
                dismissEditor()
            } label: {
                Text("Cancel")
                    .font(CosmoTypography.label)
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Spacer()

            // Save
            Button {
                saveBlock()
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    }
                    Text(isEditing ? "Save" : "Create")
                        .font(CosmoTypography.label)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(canSave ? CosmoColors.lavender : CosmoColors.glassGrey)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
        }
        .padding(16)
    }

    // MARK: - Validation

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func populateFromState() {
        if case .create(let proposedStart, let proposedEnd) = state.mode {
            // New block - always use today as the date
            startDate = Date()
            if let start = proposedStart {
                startTime = start
            } else {
                startTime = Date()
            }
            if let start = proposedStart, let end = proposedEnd {
                duration = Int(end.timeIntervalSince(start) / 60)
            }
        } else if let existing = state.existingBlock {
            // Editing existing block
            title = existing.title
            blockType = existing.blockType
            if let start = existing.startTime {
                startDate = start
                startTime = start
            }
            duration = existing.effectiveDurationMinutes
            priority = existing.priority
            notes = existing.notes ?? ""
        }
    }

    private func saveBlock() {
        guard canSave else { return }

        isSaving = true
        error = nil

        // Combine date and time
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute

        let combinedStart = calendar.date(from: dateComponents) ?? startDate

        Task {
            do {
                if let existing = state.existingBlock {
                    // Update existing
                    var updated = existing
                    updated.title = title.trimmingCharacters(in: .whitespaces)
                    updated.blockType = blockType
                    updated.startTime = combinedStart
                    updated.durationMinutes = duration
                    updated.endTime = combinedStart.addingTimeInterval(TimeInterval(duration * 60))
                    updated.priority = priority
                    updated.notes = notes.isEmpty ? nil : notes

                    try await engine.updateBlock(updated)
                } else {
                    // Create new
                    var newBlock: ScheduleBlock

                    switch blockType {
                    case .task:
                        newBlock = .task(
                            title: title.trimmingCharacters(in: .whitespaces),
                            startTime: combinedStart,
                            durationMinutes: duration,
                            priority: priority
                        )
                    case .timeBlock:
                        newBlock = .timeBlock(
                            title: title.trimmingCharacters(in: .whitespaces),
                            startTime: combinedStart,
                            endTime: combinedStart.addingTimeInterval(TimeInterval(duration * 60))
                        )
                    case .focus:
                        newBlock = .focusSession(
                            title: title.trimmingCharacters(in: .whitespaces),
                            startTime: combinedStart,
                            targetMinutes: duration
                        )
                    default:
                        newBlock = ScheduleBlock(
                            title: title.trimmingCharacters(in: .whitespaces),
                            blockType: blockType,
                            startTime: combinedStart,
                            durationMinutes: duration,
                            priority: priority
                        )
                    }

                    newBlock.notes = notes.isEmpty ? nil : notes
                    newBlock.originType = .manual

                    try await engine.createBlock(newBlock)
                }

                await MainActor.run {
                    engine.closeEditor()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func dismissEditor() {
        withAnimation(SchedulerSprings.expand) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            engine.closeEditor()
        }
    }
}

// MARK: - Editor Field

private enum EditorField: Hashable {
    case title
    case notes
}

// MARK: - Block Type Button

private struct BlockTypeButton: View {
    let type: ScheduleBlockType
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 16, weight: .medium))

                Text(type.displayName)
                    .font(CosmoTypography.labelSmall)
            }
            .foregroundColor(isSelected ? .white : CosmoColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? SchedulerColors.color(for: type) : CosmoColors.glassGrey.opacity(isHovered ? 0.25 : 0.15))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
    }
}

// MARK: - Priority Button

private struct PriorityButton: View {
    let priority: ScheduleBlockPriority
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Text(priority.displayName)
                .font(CosmoTypography.labelSmall)
                .foregroundColor(isSelected ? .white : SchedulerColors.color(for: priority))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? SchedulerColors.color(for: priority) : SchedulerColors.color(for: priority).opacity(isHovered ? 0.2 : 0.1))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
    }
}

// MARK: - Duration Picker

private struct DurationPicker: View {
    @Binding var duration: Int

    private let presets: [Int] = [15, 30, 45, 60, 90, 120]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.self) { minutes in
                Button {
                    withAnimation(SchedulerSprings.snappy) {
                        duration = minutes
                    }
                } label: {
                    Text(formatDuration(minutes))
                        .font(CosmoTypography.labelSmall)
                        .foregroundColor(duration == minutes ? .white : CosmoColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(duration == minutes ? CosmoColors.lavender : CosmoColors.glassGrey.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 {
            return "\(hours)h"
        }
        return "\(hours)h\(mins)m"
    }
}

// MARK: - Highlighted Time Text

/// A view that displays text with time expressions highlighted
private struct HighlightedTimeText: View {
    let text: String

    var body: some View {
        let parts = buildParts()

        // Use a flow layout that wraps text naturally
        HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isHighlighted {
                    Text(part.text)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.softRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(CosmoColors.softRed.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(CosmoColors.softRed.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    Text(part.text)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textPrimary)
                }
            }
        }
    }

    private struct TextPart {
        let text: String
        let isHighlighted: Bool
    }

    private func buildParts() -> [TextPart] {
        let segments = findTimeSegments(in: text)

        if segments.isEmpty {
            return [TextPart(text: text, isHighlighted: false)]
        }

        var parts: [TextPart] = []
        var lastEnd = text.startIndex

        for segment in segments.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            // Add non-highlighted text before this segment
            if segment.range.lowerBound > lastEnd {
                let beforeText = String(text[lastEnd..<segment.range.lowerBound])
                if !beforeText.isEmpty {
                    parts.append(TextPart(text: beforeText, isHighlighted: false))
                }
            }

            // Add highlighted segment
            let highlightedText = String(text[segment.range])
            parts.append(TextPart(text: highlightedText, isHighlighted: true))

            lastEnd = segment.range.upperBound
        }

        // Add remaining text after last segment
        if lastEnd < text.endIndex {
            let afterText = String(text[lastEnd...])
            if !afterText.isEmpty {
                parts.append(TextPart(text: afterText, isHighlighted: false))
            }
        }

        return parts
    }

    private struct TimeSegment {
        let range: Range<String.Index>
        let type: SegmentType

        enum SegmentType {
            case time       // e.g., "3pm", "10:30am"
            case day        // e.g., "Mon", "Tuesday"
            case date       // e.g., "tomorrow", "today"
            case duration   // e.g., "1 hour", "30min"
        }
    }

    private func findTimeSegments(in text: String) -> [TimeSegment] {
        var segments: [TimeSegment] = []

        // Find times with am/pm (e.g., "3pm", "10:30am")
        let timePattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#
        if let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    segments.append(TimeSegment(range: range, type: .time))
                }
            }
        }

        // Find times after "at" without am/pm
        let atTimePattern = #"at\s+(\d{1,2}(?::\d{2})?)"#
        if let regex = try? NSRegularExpression(pattern: atTimePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                // Get the time part only (not "at")
                if match.range(at: 1).location != NSNotFound,
                   let timeRange = Range(match.range(at: 1), in: text) {
                    // Check we haven't already captured this
                    if !segments.contains(where: { $0.range.overlaps(timeRange) }) {
                        segments.append(TimeSegment(range: timeRange, type: .time))
                    }
                }
            }
        }

        // Find day names (Mon, Tuesday, etc.)
        let dayPattern = #"\b(mon|tue|wed|thu|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        if let regex = try? NSRegularExpression(pattern: dayPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    segments.append(TimeSegment(range: range, type: .day))
                }
            }
        }

        // Find relative dates (today, tomorrow)
        let datePattern = #"\b(today|tomorrow)\b"#
        if let regex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    segments.append(TimeSegment(range: range, type: .date))
                }
            }
        }

        // Find duration values (after "for")
        let durationPattern = #"for\s+(\d+\s*(?:h|hr|hrs|hour|hours|m|min|mins|minute|minutes))"#
        if let regex = try? NSRegularExpression(pattern: durationPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                // Get the duration part only (not "for")
                if match.range(at: 1).location != NSNotFound,
                   let durationRange = Range(match.range(at: 1), in: text) {
                    segments.append(TimeSegment(range: durationRange, type: .duration))
                }
            }
        }

        return segments
    }
}

// MARK: - Preview

#if DEBUG
struct ScheduleBlockEditor_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3).ignoresSafeArea()

            ScheduleBlockEditor(
                engine: SchedulerEngine(),
                state: SchedulerEditorState(
                    mode: .create(proposedStart: Date(), proposedEnd: Date().addingTimeInterval(3600)),
                    anchorPoint: nil
                )
            )
        }
        .frame(width: 400, height: 500)
    }
}
#endif
