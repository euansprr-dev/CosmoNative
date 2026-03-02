//
//  RecurrencePickerView.swift
//  CosmoOS
//
//  Recurrence picker for task creation/editing.
//  Provides preset frequency options, custom day selection,
//  end condition picker, and stores RecurrenceRule JSON.
//

import SwiftUI

// MARK: - RecurrencePickerView

/// Embeddable recurrence selector for task creation/editing flows.
/// Toggle on to reveal frequency presets, custom day selection, and end condition.
public struct RecurrencePickerView: View {

    // MARK: - Bindings

    /// Whether recurrence is enabled
    @Binding var isEnabled: Bool

    /// The resulting RecurrenceRule JSON string (stored in TaskMetadata.recurrence)
    @Binding var recurrenceJSON: String?

    // MARK: - State

    @State private var selectedFrequency: RecurrenceFrequency = .daily
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var dayOfMonth: Int = 1
    @State private var endConditionType: EndConditionType = .never
    @State private var occurrenceCount: Int = 10
    @State private var endDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    @State private var hoveredFrequency: RecurrenceFrequency?

    private enum EndConditionType: String, CaseIterable {
        case never = "Never"
        case afterCount = "After N times"
        case untilDate = "Until date"
    }

    // MARK: - Init

    public init(isEnabled: Binding<Bool>, recurrenceJSON: Binding<String?>) {
        self._isEnabled = isEnabled
        self._recurrenceJSON = recurrenceJSON
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: PlannerumLayout.spacingSM) {
            // Toggle row
            toggleRow

            if isEnabled {
                // Frequency presets
                frequencyRow

                // Custom day selector (for weekly/custom)
                if selectedFrequency == .weekly || selectedFrequency == .custom || selectedFrequency == .biweekly {
                    daySelector
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Day of month (for monthly)
                if selectedFrequency == .monthly {
                    dayOfMonthSelector
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // End condition
                endConditionRow

                // Summary
                summaryRow
            }
        }
        .animation(PlannerumSprings.select, value: isEnabled)
        .animation(PlannerumSprings.select, value: selectedFrequency)
        .onChange(of: isEnabled) { updateJSON() }
        .onChange(of: selectedFrequency) { updateJSON() }
        .onChange(of: selectedDays) { updateJSON() }
        .onChange(of: dayOfMonth) { updateJSON() }
        .onChange(of: endConditionType) { updateJSON() }
        .onChange(of: occurrenceCount) { updateJSON() }
        .onChange(of: endDate) { updateJSON() }
        .onAppear { parseExistingJSON() }
    }

    // MARK: - Toggle Row

    private var toggleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isEnabled ? PlannerumColors.primary : PlannerumColors.textMuted)

            Text("REPEAT")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(isEnabled ? PlannerumColors.textSecondary : PlannerumColors.textMuted)
                .tracking(PlannerumTypography.trackingWide)

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .labelsHidden()
        }
    }

    // MARK: - Frequency Row

    private var frequencyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FREQUENCY")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(1.5)

            HStack(spacing: 6) {
                ForEach(frequencyOptions, id: \.self) { freq in
                    frequencyButton(freq)
                }
            }
        }
    }

    private var frequencyOptions: [RecurrenceFrequency] {
        [.daily, .weekdays, .weekly, .biweekly, .monthly, .custom]
    }

    private func frequencyButton(_ freq: RecurrenceFrequency) -> some View {
        Button(action: { selectedFrequency = freq }) {
            frequencyButtonLabel(freq)
        }
        .buttonStyle(.plain)
        .onHover { hoveredFrequency = $0 ? freq : nil }
    }

    @ViewBuilder
    private func frequencyButtonLabel(_ freq: RecurrenceFrequency) -> some View {
        let isSelected = selectedFrequency == freq
        let isHovered = hoveredFrequency == freq

        HStack(spacing: 4) {
            Image(systemName: freq.icon)
                .font(.system(size: 10, weight: .semibold))

            Text(freq.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(isSelected ? PlannerumColors.primary : PlannerumColors.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? PlannerumColors.primary.opacity(0.15)
                : isHovered
                    ? Color.white.opacity(0.06)
                    : Color.white.opacity(0.03)
        )
        .clipShape(RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlannerumLayout.cornerRadiusSM, style: .continuous)
                .strokeBorder(
                    isSelected ? PlannerumColors.primary.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Day Selector

    private var daySelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ON DAYS")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(1.5)

            HStack(spacing: 4) {
                ForEach(DayOfWeek.allCases, id: \.self) { day in
                    Button(action: { toggleDay(day) }) {
                        dayButtonLabel(day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func dayButtonLabel(_ day: DayOfWeek) -> some View {
        let isSelected = selectedDays.contains(day)

        Text(day.singleLetter)
            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            .foregroundColor(isSelected ? .white : PlannerumColors.textTertiary)
            .frame(width: 28, height: 28)
            .background(
                isSelected
                    ? PlannerumColors.primary
                    : Color.white.opacity(0.05)
            )
            .clipShape(Circle())
    }

    private func toggleDay(_ day: DayOfWeek) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    // MARK: - Day of Month Selector

    private var dayOfMonthSelector: some View {
        HStack(spacing: 8) {
            Text("ON THE")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(1.5)

            Picker("", selection: $dayOfMonth) {
                ForEach(1...31, id: \.self) { day in
                    Text(ordinal(day)).tag(day)
                }
            }
            .frame(width: 80)
            .labelsHidden()
        }
    }

    // MARK: - End Condition Row

    private var endConditionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENDS")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(1.5)

            HStack(spacing: 8) {
                // End type picker
                Picker("", selection: $endConditionType) {
                    ForEach(EndConditionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(width: 140)
                .labelsHidden()

                // Occurrence count
                if endConditionType == .afterCount {
                    HStack(spacing: 4) {
                        TextField("", value: $occurrenceCount, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(PlannerumColors.textPrimary)
                            .frame(width: 40)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("times")
                            .font(.system(size: 11))
                            .foregroundColor(PlannerumColors.textTertiary)
                    }
                    .transition(.opacity)
                }

                // End date
                if endConditionType == .untilDate {
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .transition(.opacity)
                }
            }
        }
        .animation(PlannerumSprings.select, value: endConditionType)
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        let rule = buildRule()
        return HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundColor(PlannerumColors.textMuted)

            Text(rule.displayText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PlannerumColors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Rule Building

    private func buildRule() -> RecurrenceRule {
        let endCondition: RecurrenceEndCondition
        switch endConditionType {
        case .never:
            endCondition = .never
        case .afterCount:
            endCondition = .afterOccurrences(max(1, occurrenceCount))
        case .untilDate:
            endCondition = .onDate(endDate)
        }

        let days: [DayOfWeek]? = selectedDays.isEmpty ? nil : Array(selectedDays).sorted { $0.rawValue < $1.rawValue }
        let monthDay: Int? = selectedFrequency == .monthly ? dayOfMonth : nil

        return RecurrenceRule(
            frequency: selectedFrequency,
            interval: selectedFrequency == .biweekly ? 2 : 1,
            daysOfWeek: days,
            dayOfMonth: monthDay,
            monthOfYear: nil,
            endCondition: endCondition
        )
    }

    private func updateJSON() {
        if isEnabled {
            recurrenceJSON = buildRule().toJSON()
        } else {
            recurrenceJSON = nil
        }
    }

    private func parseExistingJSON() {
        guard let json = recurrenceJSON,
              let rule = RecurrenceRule.fromJSON(json) else {
            return
        }

        selectedFrequency = rule.frequency
        if let days = rule.daysOfWeek {
            selectedDays = Set(days)
        }
        if let day = rule.dayOfMonth {
            dayOfMonth = day
        }

        switch rule.endCondition {
        case .never:
            endConditionType = .never
        case .afterOccurrences(let count):
            endConditionType = .afterCount
            occurrenceCount = count
        case .onDate(let date):
            endConditionType = .untilDate
            endDate = date
        }

        isEnabled = true
    }

    // MARK: - Helpers

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10
        let tens = (n / 10) % 10

        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Preview

#if DEBUG
struct RecurrencePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            PlannerumColors.voidPrimary.ignoresSafeArea()

            RecurrencePickerView(
                isEnabled: .constant(true),
                recurrenceJSON: .constant(nil)
            )
            .padding(24)
        }
        .frame(width: 500, height: 400)
    }
}
#endif
