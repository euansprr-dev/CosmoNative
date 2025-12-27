// CosmoOS/UI/Plannerum/WeekArcView.swift
// Plannerium Week Arc - Constellation-style week visualization
// Destiny-inspired spatial map with day orbs on curved trajectory

import SwiftUI
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - WEEK ARC VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// The Week view in Plannerium - a constellation of day orbs on a curved arc.
///
/// Visual Identity:
/// ```
///                         ┌───┐
///                   ┌───┐ │Thu│ ┌───┐
///             ┌───┐ │Wed│ └───┘ │Fri│ ┌───┐
///       ┌───┐ │Tue│ └───┘       └───┘ │Sat│ ┌───┐
///       │Mon│ └───┘                   └───┘ │Sun│
///       └───┘                               └───┘
///             ════════════════════════════════
///                       Week Arc Path
///
///   Week Summary:  12 blocks · 28.5h · 67% done · +1.2K XP
/// ```
public struct WeekArcView: View {

    // MARK: - Properties

    let centerDate: Date
    let onDaySelect: (Date) -> Void

    // MARK: - State

    @StateObject private var viewModel = WeekArcViewModel()
    @State private var hoveredDayIndex: Int?
    @State private var animationPhase: Double = 0
    @State private var timerCancellable: AnyCancellable?

    // MARK: - Layout

    private enum Layout {
        static let arcHeight: CGFloat = PlannerumLayout.arcHeight
        static let dayOrbSize: CGFloat = PlannerumLayout.dayOrbSize
        static let dayOrbSizeHovered: CGFloat = PlannerumLayout.dayOrbSizeHover
    }

    // MARK: - Computed

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: centerDate))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var todayIndex: Int? {
        weekDates.firstIndex { Calendar.current.isDateInToday($0) }
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // NO Background - floats on realm atmosphere
                Color.clear

                // Arc path (subtle guide line)
                arcPath(in: geometry)

                // Day orbs positioned on arc
                ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                    let position = orbPosition(for: index, in: geometry)
                    let dayData = viewModel.dayData[Calendar.current.startOfDay(for: date)] ?? DayData.empty

                    DayOrbView(
                        date: date,
                        dayData: dayData,
                        isToday: todayIndex == index,
                        isHovered: hoveredDayIndex == index,
                        size: hoveredDayIndex == index ? Layout.dayOrbSizeHovered : Layout.dayOrbSize,
                        animationPhase: animationPhase
                    )
                    .position(position)
                    .onHover { hovering in
                        withAnimation(PlannerumSprings.hover) {
                            hoveredDayIndex = hovering ? index : nil
                        }
                    }
                    .onTapGesture {
                        onDaySelect(date)
                    }
                }

                // Week header
                weekHeader
                    .position(x: geometry.size.width / 2, y: 48)

                // Week navigation arrows
                navigationArrows(in: geometry)

                // Week summary footer
                weekSummary
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 60)
            }
        }
        .onAppear {
            Task { await viewModel.loadWeekData(for: weekDates) }
            startAnimationTimer()
        }
        .onDisappear {
            timerCancellable?.cancel()
        }
        .onChange(of: centerDate) { _, _ in
            Task { await viewModel.loadWeekData(for: weekDates) }
        }
    }

    // MARK: - Arc Path

    private func arcPath(in geometry: GeometryProxy) -> some View {
        Path { path in
            let startX = geometry.size.width * 0.06
            let endX = geometry.size.width * 0.94
            let centerY = geometry.size.height * 0.45
            let arcPeak = centerY - Layout.arcHeight

            path.move(to: CGPoint(x: startX, y: centerY))
            path.addQuadCurve(
                to: CGPoint(x: endX, y: centerY),
                control: CGPoint(x: geometry.size.width / 2, y: arcPeak)
            )
        }
        .stroke(
            LinearGradient(
                colors: [
                    PlannerumColors.primary.opacity(0.05),
                    PlannerumColors.primary.opacity(0.2),
                    PlannerumColors.primary.opacity(0.05)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 4])
        )
    }

    // MARK: - Orb Positioning

    private func orbPosition(for index: Int, in geometry: GeometryProxy) -> CGPoint {
        let startX = geometry.size.width * 0.06
        let endX = geometry.size.width * 0.94
        let centerY = geometry.size.height * 0.45
        let arcPeak = centerY - Layout.arcHeight

        let t = CGFloat(index) / 6.0

        let x = pow(1 - t, 2) * startX + 2 * (1 - t) * t * (geometry.size.width / 2) + pow(t, 2) * endX
        let y = pow(1 - t, 2) * centerY + 2 * (1 - t) * t * arcPeak + pow(t, 2) * centerY

        return CGPoint(x: x, y: y)
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        VStack(spacing: 4) {
            Text("WEEK OF")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(PlannerumColors.textMuted)
                .tracking(2)

            Text(PlannerumFormatters.weekRange.string(from: weekDates.first ?? Date()).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(PlannerumColors.textSecondary)
                .tracking(1)
        }
    }

    // MARK: - Navigation Arrows

    private func navigationArrows(in geometry: GeometryProxy) -> some View {
        HStack {
            Button(action: navigatePrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(PlannerumColors.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(PlannerumColors.glassPrimary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: navigateNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(PlannerumColors.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(PlannerumColors.glassPrimary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.45)
    }

    // MARK: - Week Summary

    private var weekSummary: some View {
        HStack(spacing: PlannerumLayout.spacingXL) {
            // Total blocks
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12))
                Text("\(viewModel.totalBlocks)")
                    .font(.system(size: 13, weight: .semibold))
                Text("blocks")
                    .font(.system(size: 12))
            }
            .foregroundColor(PlannerumColors.textTertiary)

            // Total hours
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                Text(viewModel.totalDuration)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(PlannerumColors.textTertiary)

            // Completion rate
            if viewModel.completionRate > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("\(Int(viewModel.completionRate * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                    Text("done")
                        .font(.system(size: 12))
                }
                .foregroundColor(PlannerumColors.nowMarker)
            }

            // XP Forecast
            if viewModel.forecastXP > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                    Text("+\(PlannerumXP.formatXP(viewModel.forecastXP))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text("XP")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(PlannerumColors.xpGold)
            }
        }
        .padding(.horizontal, PlannerumLayout.spacingXL)
        .padding(.vertical, PlannerumLayout.spacingMD)
        .background(
            Capsule()
                .fill(PlannerumColors.glassPrimary)
                .overlay(
                    Capsule()
                        .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Navigation

    private func navigatePrevious() {
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: centerDate) {
            onDaySelect(newDate)
        }
    }

    private func navigateNext() {
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: centerDate) {
            onDaySelect(newDate)
        }
    }

    // MARK: - Animation

    private func startAnimationTimer() {
        timerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                animationPhase += 0.02
            }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DAY ORB VIEW
// ═══════════════════════════════════════════════════════════════════════════════

/// A single day orb on the week arc
public struct DayOrbView: View {

    let date: Date
    let dayData: DayData
    let isToday: Bool
    let isHovered: Bool
    let size: CGFloat
    let animationPhase: Double

    private var dayName: String {
        PlannerumFormatters.dayNameShort.string(from: date).uppercased()
    }

    private var dayNumber: String {
        PlannerumFormatters.dayNumber.string(from: date)
    }

    private var densityLevel: Double {
        min(dayData.totalHours / 8.0, 1.0)
    }

    private var glowColor: Color {
        isToday ? PlannerumColors.nowMarker : PlannerumColors.primary
    }

    private var isPast: Bool {
        Calendar.current.compare(date, to: Date(), toGranularity: .day) == .orderedAscending
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Day label
            Text(dayName)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(
                    isToday ? PlannerumColors.nowMarker
                        : (isPast ? PlannerumColors.textMuted : PlannerumColors.textTertiary)
                )
                .tracking(1)

            // Main orb
            ZStack {
                // Outer glow
                Circle()
                    .fill(glowColor.opacity(isHovered ? 0.25 : 0.1))
                    .frame(width: size + 20, height: size + 20)
                    .blur(radius: 10)

                // Density gradient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                glowColor.opacity(densityLevel * 0.4),
                                glowColor.opacity(densityLevel * 0.1)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )
                    .frame(width: size, height: size)

                // Glass surface
                Circle()
                    .fill(PlannerumColors.glassPrimary.opacity(0.6))
                    .frame(width: size, height: size)

                // Border
                Circle()
                    .strokeBorder(
                        isToday ? glowColor.opacity(0.6)
                            : (isHovered ? glowColor.opacity(0.4) : PlannerumColors.glassBorder),
                        lineWidth: isToday ? 2 : 1
                    )
                    .frame(width: size, height: size)

                // Day number
                Text(dayNumber)
                    .font(.system(size: size * 0.35, weight: isToday ? .bold : .semibold, design: .rounded))
                    .foregroundColor(
                        isToday ? PlannerumColors.nowMarker
                            : (isPast ? PlannerumColors.textMuted : PlannerumColors.textPrimary)
                    )

                // Block count badge
                if dayData.blockCount > 0 {
                    Text("\(dayData.blockCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(glowColor).shadow(color: glowColor.opacity(0.5), radius: 4))
                        .offset(x: size * 0.4, y: -size * 0.4)
                }

                // Today pulse
                if isToday {
                    Circle()
                        .strokeBorder(glowColor, lineWidth: 1)
                        .frame(width: size + 10, height: size + 10)
                        .opacity(0.4 + 0.3 * sin(animationPhase * 2))
                        .scaleEffect(1.0 + 0.06 * sin(animationPhase * 2))
                }

                // Completed overlay
                if isPast && dayData.completionRate >= 1.0 {
                    ZStack {
                        Circle().fill(PlannerumColors.nowMarker.opacity(0.15))
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.25, weight: .bold))
                            .foregroundColor(PlannerumColors.nowMarker)
                    }
                    .frame(width: size, height: size)
                }
            }

            // Block type indicators
            if dayData.blockCount > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<min(dayData.blockCount, 6), id: \.self) { i in
                        let type = dayData.blockTypes.indices.contains(i) ? dayData.blockTypes[i] : .deepWork
                        Circle().fill(type.color).frame(width: 6, height: 6)
                    }
                    if dayData.blockCount > 6 {
                        Text("+\(dayData.blockCount - 6)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(PlannerumColors.textMuted)
                    }
                }
            }

            // Hours label
            if dayData.totalHours > 0 {
                Text(String(format: "%.1fh", dayData.totalHours))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)
            }
        }
        .animation(PlannerumSprings.hover, value: isHovered)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - WEEK ARC VIEW MODEL
// ═══════════════════════════════════════════════════════════════════════════════

@MainActor
public class WeekArcViewModel: ObservableObject {

    @Published public var dayData: [Date: DayData] = [:]
    @Published public var isLoading = false

    public var totalBlocks: Int {
        dayData.values.reduce(0) { $0 + $1.blockCount }
    }

    public var totalDuration: String {
        let hours = dayData.values.reduce(0.0) { $0 + $1.totalHours }
        return PlannerumTimeUtils.formatDuration(hours * 3600)
    }

    public var completionRate: Double {
        let total = dayData.values.reduce(0) { $0 + $1.blockCount }
        let completed = dayData.values.reduce(0) { $0 + $1.completedCount }
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var forecastXP: Int {
        var total = 0
        for data in dayData.values {
            for blockType in data.blockTypes {
                total += PlannerumXP.estimateXP(blockType: blockType, durationMinutes: 60)
            }
        }
        return total
    }

    public func loadWeekData(for dates: [Date]) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .scheduleBlock)
                .filter { !$0.isDeleted }

            let calendar = Calendar.current
            var result: [Date: DayData] = [:]

            for date in dates {
                let dayStart = calendar.startOfDay(for: date)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                let dayBlocks = atoms.compactMap { atom -> (TimeBlockType, TimeInterval, Bool)? in
                    guard let metadata = atom.metadataValue(as: ScheduleBlockMetadata.self),
                          let startStr = metadata.startTime,
                          let endStr = metadata.endTime,
                          let start = PlannerumFormatters.iso8601.date(from: startStr),
                          let end = PlannerumFormatters.iso8601.date(from: endStr),
                          start >= dayStart && start < dayEnd
                    else { return nil }

                    let type: TimeBlockType = {
                        switch metadata.blockType?.lowercased() {
                        case "deepwork", "deep_work": return .deepWork
                        case "creative": return .creative
                        case "output": return .output
                        case "planning": return .planning
                        case "training": return .training
                        case "rest": return .rest
                        case "admin", "administrative": return .administrative
                        case "meeting": return .meeting
                        case "review": return .review
                        default: return .deepWork
                        }
                    }()

                    return (type, end.timeIntervalSince(start), metadata.isCompleted ?? false)
                }

                result[dayStart] = DayData(
                    blockCount: dayBlocks.count,
                    totalHours: dayBlocks.reduce(0.0) { $0 + $1.1 / 3600.0 },
                    completedCount: dayBlocks.filter { $0.2 }.count,
                    blockTypes: dayBlocks.map { $0.0 }
                )
            }

            dayData = result

        } catch {
            print("❌ WeekArcViewModel: Failed to load - \(error)")
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - PREVIEW
// ═══════════════════════════════════════════════════════════════════════════════

#if DEBUG
struct WeekArcView_Previews: PreviewProvider {
    static var previews: some View {
        WeekArcView(centerDate: Date(), onDaySelect: { _ in })
            .frame(width: 900, height: 500)
            .preferredColorScheme(.dark)
    }
}
#endif
