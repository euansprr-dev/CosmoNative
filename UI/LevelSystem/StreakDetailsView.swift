import SwiftUI

// MARK: - Streak Details View

/// Comprehensive view for streak tracking across all dimensions
/// Shows active streaks, at-risk streaks, records, and calendar visualization
public struct StreakDetailsView: View {
    @ObservedObject var levelService: LevelSystemService
    @State private var selectedStreak: UIStreakType?
    @State private var showingCalendar = false

    public init(levelService: LevelSystemService) {
        self.levelService = levelService
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DS.space24) {
                overallStreakHero
                activeStreaksSection
                atRiskStreaksSection
                streakRecordsSection
                streakCalendarSection
                streakMultipliersSection
                streakHistorySection
            }
            .padding(DS.space16)
        }
        .background(DS.surface)
        .navigationTitle("Streaks")
    }

    // MARK: - Overall Streak Hero

    private var overallStreakHero: some View {
        VStack(spacing: DS.space16) {
            StreakHeroRing()

            VStack(spacing: DS.space8) {
                Text("Overall Consistency Streak")
                    .font(DS.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.text)

                HStack(spacing: DS.space16) {
                    StreakInfoPill(label: "1.35x", subtitle: "XP Multiplier")
                    StreakInfoPill(label: "13 days", subtitle: "To 60-day badge")
                }
            }
        }
        .padding(.vertical, DS.space8)
    }

    // MARK: - Active Streaks Section

    private var activeStreaksSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Active Streaks")
                .dsSmallCapsLabel()

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DS.space12) {
                StreakCard(type: .deepWork, title: "Deep Work", icon: "brain.head.profile", color: DS.entityContent, currentStreak: 32, bestStreak: 89, multiplier: 1.2)
                StreakCard(type: .writing, title: "Writing", icon: "pencil.line", color: DS.entityConnection, currentStreak: 47, bestStreak: 124, multiplier: 1.35)
                StreakCard(type: .journal, title: "Journal", icon: "book.fill", color: DS.entityIdea, currentStreak: 21, bestStreak: 45, multiplier: 1.1)
                StreakCard(type: .hrv, title: "HRV Check", icon: "heart.fill", color: DS.red, currentStreak: 15, bestStreak: 30, multiplier: 1.1)
                StreakCard(type: .sleep, title: "Sleep Target", icon: "moon.fill", color: DS.entityImage, currentStreak: 8, bestStreak: 22, multiplier: 1.1)
                StreakCard(type: .routine, title: "Morning Routine", icon: "sunrise.fill", color: DS.orange, currentStreak: 12, bestStreak: 34, multiplier: 1.1)
            }
        }
    }

    // MARK: - At-Risk Streaks Section

    private var atRiskStreaksSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.entityStickyNote)

                Text("At Risk Today")
                    .dsSmallCapsLabel()
            }

            VStack(spacing: DS.space8) {
                AtRiskStreakRow(title: "Sleep Target", currentStreak: 8, timeRemaining: "4 hours left", action: "Hit 7+ hours tonight")
                AtRiskStreakRow(title: "Morning Routine", currentStreak: 12, timeRemaining: "Complete by 10 AM", action: "Finish deep work block")
            }
        }
        .padding(DS.space16)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .fill(DS.orangeSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusLarge)
                        .strokeBorder(DS.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Streak Records Section

    private var streakRecordsSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Personal Records")
                .dsSmallCapsLabel()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space12) {
                    RecordCard(title: "Longest Ever", value: "124", unit: "days", type: "Writing", date: "Aug 2025", icon: "crown.fill", color: DS.entityStickyNote)
                    RecordCard(title: "Deep Focus", value: "89", unit: "days", type: "Deep Work", date: "Jun 2025", icon: "brain.head.profile", color: DS.entityContent)
                    RecordCard(title: "Reflection", value: "45", unit: "days", type: "Journal", date: "Oct 2025", icon: "book.fill", color: DS.entityIdea)
                }
            }
        }
    }

    // MARK: - Streak Calendar Section

    private var streakCalendarSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Text("Streak Calendar")
                    .dsSmallCapsLabel()

                Spacer()

                Button("Full View") {
                    showingCalendar = true
                }
                .font(DS.buttonText)
                .foregroundStyle(DS.accent)
            }

            StreakCalendarView()
                .padding(DS.space16)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusLarge)
                        .fill(DS.surfaceCard)
                )
                .dsRestingShadow()
        }
    }

    // MARK: - Streak Multipliers Section

    private var streakMultipliersSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("XP Multipliers")
                .dsSmallCapsLabel()

            VStack(spacing: 0) {
                MultiplierRow(days: 7, multiplier: 1.1, isUnlocked: true, isCurrent: false)
                Divider().padding(.horizontal, DS.space16)
                MultiplierRow(days: 14, multiplier: 1.2, isUnlocked: true, isCurrent: false)
                Divider().padding(.horizontal, DS.space16)
                MultiplierRow(days: 30, multiplier: 1.35, isUnlocked: true, isCurrent: true)
                Divider().padding(.horizontal, DS.space16)
                MultiplierRow(days: 60, multiplier: 1.5, isUnlocked: false, isCurrent: false)
                Divider().padding(.horizontal, DS.space16)
                MultiplierRow(days: 90, multiplier: 1.75, isUnlocked: false, isCurrent: false)
                Divider().padding(.horizontal, DS.space16)
                MultiplierRow(days: 180, multiplier: 2.0, isUnlocked: false, isCurrent: false)
                Divider().padding(.horizontal, DS.space16)
                MultiplierRow(days: 365, multiplier: 2.5, isUnlocked: false, isCurrent: false)
            }
            .background(
                RoundedRectangle(cornerRadius: DS.radiusLarge)
                    .fill(DS.surfaceCard)
            )
            .dsRestingShadow()
        }
    }

    // MARK: - Streak History Section

    private var streakHistorySection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("Streak History")
                .dsSmallCapsLabel()

            VStack(spacing: DS.space8) {
                StreakHistoryRow(type: "Writing", length: 124, startDate: "Apr 12, 2025", endDate: "Aug 14, 2025", endReason: "Vacation")
                StreakHistoryRow(type: "Deep Work", length: 89, startDate: "Mar 1, 2025", endDate: "May 28, 2025", endReason: "Illness")
                StreakHistoryRow(type: "Overall", length: 67, startDate: "Feb 1, 2025", endDate: "Apr 8, 2025", endReason: "Travel")
            }
        }
    }
}

// MARK: - UI Streak Type Enum

fileprivate enum UIStreakType: String, CaseIterable {
    case overall, deepWork, writing, journal, hrv, sleep, routine, workout
}

// MARK: - Streak Hero Ring

struct StreakHeroRing: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [DS.orange.opacity(0.3), DS.orange.opacity(0.1), Color.clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)

            Circle()
                .stroke(DS.borderSubtle, lineWidth: 8)
                .frame(width: 140, height: 140)

            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(
                    LinearGradient(colors: [DS.orange, DS.red], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(-90))

            VStack(spacing: DS.space4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DS.orange)

                Text("47")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text)

                Text("Days")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.textSecondary)
            }
        }
    }
}

// MARK: - Streak Info Pill

struct StreakInfoPill: View {
    let label: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DS.space2) {
            Text(label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.orange)

            Text(subtitle)
                .font(DS.footnote)
                .fontWeight(.medium)
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }
}

// MARK: - Streak Card

fileprivate struct StreakCard: View {
    let type: UIStreakType
    let title: String
    let icon: String
    let color: Color
    let currentStreak: Int
    let bestStreak: Int
    let multiplier: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            streakCardHeader
            streakCardTitle
            streakCardValue
            streakCardProgress
        }
        .padding(DS.space16)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }

    private var streakCardHeader: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)

            Spacer()

            if multiplier > 1.0 {
                Text("\(multiplier, specifier: "%.2f")x")
                    .font(DS.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(DS.orange)
                    .padding(.horizontal, DS.space6)
                    .padding(.vertical, DS.space2)
                    .background(DS.orangeSoft)
                    .clipShape(.rect(cornerRadius: DS.radiusXSmall))
            }
        }
    }

    private var streakCardTitle: some View {
        Text(title)
            .font(DS.callout)
            .fontWeight(.semibold)
            .foregroundStyle(DS.text)
    }

    private var streakCardValue: some View {
        HStack(alignment: .bottom, spacing: DS.space4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14))
                .foregroundStyle(currentStreak > 0 ? DS.orange : DS.textMuted)

            Text("\(currentStreak)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(currentStreak > 0 ? DS.text : DS.textSecondary)
        }
    }

    private var streakCardProgress: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.borderSubtle)
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(
                            width: geometry.size.width * min(Double(currentStreak) / Double(bestStreak), 1.0),
                            height: 4
                        )
                }
            }
            .frame(height: 4)

            Text("Best: \(bestStreak)")
                .font(DS.caption2)
                .fontWeight(.medium)
                .foregroundStyle(DS.textSecondary)
        }
    }
}

// MARK: - At-Risk Streak Row

struct AtRiskStreakRow: View {
    let title: String
    let currentStreak: Int
    let timeRemaining: String
    let action: String

    var body: some View {
        HStack(spacing: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space4) {
                HStack(spacing: DS.space6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.orange)

                    Text("\(currentStreak) day streak")
                        .font(DS.navTitle)
                        .foregroundStyle(DS.text)
                }

                Text(title)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DS.space4) {
                Text(timeRemaining)
                    .font(DS.buttonText)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.orange)

                Text(action)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .padding(DS.space12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
    }
}

// MARK: - Record Card

struct RecordCard: View {
    let title: String
    let value: String
    let unit: String
    let type: String
    let date: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: DS.space2) {
                HStack(alignment: .bottom, spacing: DS.space4) {
                    Text(value)
                        .font(DS.display)
                        .fontDesign(.rounded)
                        .foregroundStyle(DS.text)

                    Text(unit)
                        .font(DS.navTitle)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.bottom, DS.space4)
                }

                Text(type)
                    .font(DS.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.text)

                Text(date)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .padding(DS.space16)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }
}

// MARK: - Streak Calendar View

struct StreakCalendarView: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: DS.space8) {
            HStack {
                Text("December 2025")
                    .font(DS.navTitle)
                    .foregroundStyle(DS.text)
                Spacer()
            }

            HStack(spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(DS.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<1, id: \.self) { _ in
                    Color.clear.frame(height: 32)
                }
                ForEach(1...21, id: \.self) { day in
                    CalendarDayView(day: day, hasStreak: day <= 21, isToday: day == 21)
                }
                ForEach(22...31, id: \.self) { day in
                    CalendarDayView(day: day, hasStreak: false, isToday: false, isFuture: true)
                }
            }

            HStack(spacing: DS.space16) {
                calendarLegendItem(color: DS.orange, label: "Streak day")
                calendarLegendItem(color: DS.borderSubtle, label: "Missed")
            }
            .padding(.top, DS.space8)
        }
    }

    private func calendarLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: DS.space4) {
            RoundedRectangle(cornerRadius: DS.radiusXSmall)
                .fill(color)
                .frame(width: 12, height: 12)

            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textSecondary)
        }
    }
}

struct CalendarDayView: View {
    let day: Int
    let hasStreak: Bool
    let isToday: Bool
    var isFuture: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.space6)
                .fill(backgroundColor)
                .frame(height: 32)

            Text("\(day)")
                .font(DS.buttonText)
                .fontWeight(isToday ? .bold : .medium)
                .foregroundStyle(textColor)
        }
        .overlay(
            isToday
                ? RoundedRectangle(cornerRadius: DS.space6)
                    .strokeBorder(DS.accent, lineWidth: 2)
                : nil
        )
    }

    private var backgroundColor: Color {
        if isFuture { DS.surface }
        else { hasStreak ? DS.orange : DS.borderSubtle }
    }

    private var textColor: Color {
        if isFuture { DS.textMuted }
        else { hasStreak ? DS.textOnAccent : DS.textSecondary }
    }
}

// MARK: - Multiplier Row

struct MultiplierRow: View {
    let days: Int
    let multiplier: Double
    let isUnlocked: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: DS.space12) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? DS.green : DS.borderSubtle)
                    .frame(width: 24, height: 24)

                if isUnlocked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.textOnAccent)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.textMuted)
                }
            }

            VStack(alignment: .leading, spacing: DS.space2) {
                Text("\(days)-day streak")
                    .font(DS.navTitle)
                    .foregroundStyle(isUnlocked ? DS.text : DS.textSecondary)

                if isCurrent {
                    Text("Current milestone")
                        .font(DS.footnote)
                        .foregroundStyle(DS.green)
                }
            }

            Spacer()

            Text("\(multiplier, specifier: "%.2f")x XP")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isUnlocked ? DS.orange : DS.textSecondary)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
        .background(isCurrent ? DS.greenSoft : Color.clear)
    }
}

// MARK: - Streak History Row

struct StreakHistoryRow: View {
    let type: String
    let length: Int
    let startDate: String
    let endDate: String
    let endReason: String

    var body: some View {
        HStack(spacing: DS.space12) {
            VStack(alignment: .leading, spacing: DS.space4) {
                HStack(spacing: DS.space6) {
                    Text("\(length) days")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.text)

                    Text("\u{2022}")
                        .foregroundStyle(DS.textSecondary)

                    Text(type)
                        .font(DS.navTitle)
                        .foregroundStyle(DS.textSecondary)
                }

                Text("\(startDate) \u{2192} \(endDate)")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textSecondary)
            }

            Spacer()

            Text(endReason)
                .font(DS.footnote)
                .fontWeight(.medium)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(DS.borderSubtle)
                .clipShape(.rect(cornerRadius: DS.space6))
        }
        .padding(DS.space12)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.surfaceCard)
        )
        .dsRestingShadow()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StreakDetailsView(levelService: LevelSystemService(database: CosmoDatabase.shared.dbQueue!))
    }
}
