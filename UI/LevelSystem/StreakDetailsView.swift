import SwiftUI

// MARK: - Cross-Platform Colors

private extension Color {
    static var streakBackground: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var streakSecondaryBackground: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
}

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
            VStack(spacing: 24) {
                // Overall Streak Hero
                overallStreakHero

                // Active Streaks Grid
                activeStreaksSection

                // At-Risk Streaks Warning
                atRiskStreaksSection

                // Streak Records
                streakRecordsSection

                // Streak Calendar
                streakCalendarSection

                // Streak Multipliers
                streakMultipliersSection

                // Streak History
                streakHistorySection
            }
            .padding()
        }
        .background(Color.streakBackground)
        .navigationTitle("Streaks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Overall Streak Hero

    private var overallStreakHero: some View {
        VStack(spacing: 16) {
            // Main streak display
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(0.3),
                                Color.orange.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 50,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)

                // Progress ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: 0.78) // 78% to next milestone
                    .stroke(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)

                    Text("47")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Days")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Streak info
            VStack(spacing: 8) {
                Text("Overall Consistency Streak")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 16) {
                    streakInfoPill(label: "1.35x", subtitle: "XP Multiplier")
                    streakInfoPill(label: "13 days", subtitle: "To 60-day badge")
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func streakInfoPill(label: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.orange)

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.streakSecondaryBackground)
        )
    }

    // MARK: - Active Streaks Section

    private var activeStreaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE STREAKS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StreakCard(
                    type: .deepWork,
                    title: "Deep Work",
                    icon: "brain.head.profile",
                    color: .blue,
                    currentStreak: 32,
                    bestStreak: 89,
                    multiplier: 1.2
                )

                StreakCard(
                    type: .writing,
                    title: "Writing",
                    icon: "pencil.line",
                    color: .purple,
                    currentStreak: 47,
                    bestStreak: 124,
                    multiplier: 1.35
                )

                StreakCard(
                    type: .journal,
                    title: "Journal",
                    icon: "book.fill",
                    color: .indigo,
                    currentStreak: 21,
                    bestStreak: 45,
                    multiplier: 1.1
                )

                StreakCard(
                    type: .hrv,
                    title: "HRV Check",
                    icon: "heart.fill",
                    color: .red,
                    currentStreak: 15,
                    bestStreak: 30,
                    multiplier: 1.1
                )

                StreakCard(
                    type: .sleep,
                    title: "Sleep Target",
                    icon: "moon.fill",
                    color: .cyan,
                    currentStreak: 8,
                    bestStreak: 22,
                    multiplier: 1.1
                )

                StreakCard(
                    type: .routine,
                    title: "Morning Routine",
                    icon: "sunrise.fill",
                    color: .orange,
                    currentStreak: 12,
                    bestStreak: 34,
                    multiplier: 1.1
                )
            }
        }
    }

    // MARK: - At-Risk Streaks Section

    private var atRiskStreaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)

                Text("AT RISK TODAY")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)
            }

            VStack(spacing: 8) {
                AtRiskStreakRow(
                    title: "Sleep Target",
                    currentStreak: 8,
                    timeRemaining: "4 hours left",
                    action: "Hit 7+ hours tonight"
                )

                AtRiskStreakRow(
                    title: "Morning Routine",
                    currentStreak: 12,
                    timeRemaining: "Complete by 10 AM",
                    action: "Finish deep work block"
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.yellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Streak Records Section

    private var streakRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PERSONAL RECORDS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    RecordCard(
                        title: "Longest Ever",
                        value: "124",
                        unit: "days",
                        type: "Writing",
                        date: "Aug 2025",
                        icon: "crown.fill",
                        color: .yellow
                    )

                    RecordCard(
                        title: "Deep Focus",
                        value: "89",
                        unit: "days",
                        type: "Deep Work",
                        date: "Jun 2025",
                        icon: "brain.head.profile",
                        color: .blue
                    )

                    RecordCard(
                        title: "Reflection",
                        value: "45",
                        unit: "days",
                        type: "Journal",
                        date: "Oct 2025",
                        icon: "book.fill",
                        color: .indigo
                    )
                }
            }
        }
    }

    // MARK: - Streak Calendar Section

    private var streakCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STREAK CALENDAR")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Spacer()

                Button("Full View") {
                    showingCalendar = true
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }

            StreakCalendarView()
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.streakSecondaryBackground)
                )
        }
    }

    // MARK: - Streak Multipliers Section

    private var streakMultipliersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("XP MULTIPLIERS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            VStack(spacing: 0) {
                MultiplierRow(days: 7, multiplier: 1.1, isUnlocked: true, isCurrent: false)
                Divider().padding(.horizontal)
                MultiplierRow(days: 14, multiplier: 1.2, isUnlocked: true, isCurrent: false)
                Divider().padding(.horizontal)
                MultiplierRow(days: 30, multiplier: 1.35, isUnlocked: true, isCurrent: true)
                Divider().padding(.horizontal)
                MultiplierRow(days: 60, multiplier: 1.5, isUnlocked: false, isCurrent: false)
                Divider().padding(.horizontal)
                MultiplierRow(days: 90, multiplier: 1.75, isUnlocked: false, isCurrent: false)
                Divider().padding(.horizontal)
                MultiplierRow(days: 180, multiplier: 2.0, isUnlocked: false, isCurrent: false)
                Divider().padding(.horizontal)
                MultiplierRow(days: 365, multiplier: 2.5, isUnlocked: false, isCurrent: false)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.streakSecondaryBackground)
            )
        }
    }

    // MARK: - Streak History Section

    private var streakHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STREAK HISTORY")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.5)

            VStack(spacing: 8) {
                StreakHistoryRow(
                    type: "Writing",
                    length: 124,
                    startDate: "Apr 12, 2025",
                    endDate: "Aug 14, 2025",
                    endReason: "Vacation"
                )

                StreakHistoryRow(
                    type: "Deep Work",
                    length: 89,
                    startDate: "Mar 1, 2025",
                    endDate: "May 28, 2025",
                    endReason: "Illness"
                )

                StreakHistoryRow(
                    type: "Overall",
                    length: 67,
                    startDate: "Feb 1, 2025",
                    endDate: "Apr 8, 2025",
                    endReason: "Travel"
                )
            }
        }
    }
}

// MARK: - UI Streak Type Enum

fileprivate enum UIStreakType: String, CaseIterable {
    case overall
    case deepWork
    case writing
    case journal
    case hrv
    case sleep
    case routine
    case workout
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)

                Spacer()

                if multiplier > 1.0 {
                    Text("\(multiplier, specifier: "%.2f")x")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            HStack(alignment: .bottom, spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(currentStreak > 0 ? .orange : .gray)

                Text("\(currentStreak)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(currentStreak > 0 ? .primary : .secondary)
            }

            // Progress to best
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.streakSecondaryBackground)
        )
    }
}

// MARK: - At-Risk Streak Row

struct AtRiskStreakRow: View {
    let title: String
    let currentStreak: Int
    let timeRemaining: String
    let action: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)

                    Text("\(currentStreak) day streak")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(timeRemaining)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.yellow)

                Text(action)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.streakBackground)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                Text(type)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(date)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.streakSecondaryBackground)
        )
    }
}

// MARK: - Streak Calendar View

struct StreakCalendarView: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 8) {
            // Month header
            HStack {
                Text("December 2025")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            // Weekday headers
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            LazyVGrid(columns: columns, spacing: 4) {
                // Empty cells for offset (December 2025 starts on Monday)
                ForEach(0..<1, id: \.self) { _ in
                    Color.clear
                        .frame(height: 32)
                }

                // Days of the month
                ForEach(1...21, id: \.self) { day in
                    CalendarDayView(
                        day: day,
                        hasStreak: day <= 21,
                        isToday: day == 21
                    )
                }

                // Future days (grayed out)
                ForEach(22...31, id: \.self) { day in
                    CalendarDayView(
                        day: day,
                        hasStreak: false,
                        isToday: false,
                        isFuture: true
                    )
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .orange, label: "Streak day")
                legendItem(color: .gray.opacity(0.2), label: "Missed")
            }
            .padding(.top, 8)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 12, height: 12)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
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
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .frame(height: 32)

            Text("\(day)")
                .font(.system(size: 12, weight: isToday ? .bold : .medium))
                .foregroundColor(textColor)
        }
        .overlay(
            isToday ?
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.blue, lineWidth: 2)
                : nil
        )
    }

    private var backgroundColor: Color {
        if isFuture {
            return Color.gray.opacity(0.1)
        }
        return hasStreak ? Color.orange : Color.gray.opacity(0.2)
    }

    private var textColor: Color {
        if isFuture {
            return .secondary.opacity(0.5)
        }
        return hasStreak ? .white : .secondary
    }
}

// MARK: - Multiplier Row

struct MultiplierRow: View {
    let days: Int
    let multiplier: Double
    let isUnlocked: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(isUnlocked ? Color.green : Color.gray.opacity(0.2))
                    .frame(width: 24, height: 24)

                if isUnlocked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(days)-day streak")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isUnlocked ? .primary : .secondary)

                if isCurrent {
                    Text("Current milestone")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Text("\(multiplier, specifier: "%.2f")x XP")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(isUnlocked ? .orange : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isCurrent ? Color.green.opacity(0.1) : Color.clear)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(length) days")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(type)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text("\(startDate) → \(endDate)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(endReason)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.streakSecondaryBackground)
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        StreakDetailsView(levelService: LevelSystemService(database: CosmoDatabase.shared.dbQueue!))
    }
}
