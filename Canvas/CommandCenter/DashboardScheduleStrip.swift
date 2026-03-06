// Canvas/CommandCenter/DashboardScheduleStrip.swift
// Visual vertical timeline showing tracked sessions + calendar events as colored blocks
// Timery-style day view
// March 2026

import SwiftUI

struct DashboardScheduleStrip: View {

    @ObservedObject var viewModel: CommandCenterDashboardViewModel

    private let hourHeight: CGFloat = 50
    private let startHour: Int = 7
    private let endHour: Int = 23

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Hour grid lines
                        hourGrid

                        // Calendar events
                        ForEach(viewModel.todayEvents) { event in
                            calendarEventBlock(event)
                        }

                        // Deep work sessions
                        ForEach(viewModel.todaySessions) { session in
                            sessionBlock(session)
                        }

                        // Now marker
                        if viewModel.isViewingToday {
                            nowMarker
                                .id("nowMarker")
                        }
                    }
                    .frame(height: CGFloat(endHour - startHour) * hourHeight)
                }
                .frame(maxHeight: 400)
                .onAppear {
                    if viewModel.isViewingToday {
                        proxy.scrollTo("nowMarker", anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textMuted)

            Text("TIMELINE")
                .dsSectionLabel()

            Spacer()

            if !viewModel.todaySessions.isEmpty {
                Text("\(viewModel.todaySessions.count) sessions")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }
        }
    }

    // MARK: - Hour Grid

    private var hourGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    // Hour label
                    Text(hourLabel(hour))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 32, alignment: .trailing)

                    // Grid line
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(DS.borderSubtle)
                            .frame(height: 0.5)
                        Spacer()
                    }
                }
                .frame(height: hourHeight)
            }
        }
    }

    // MARK: - Calendar Event Block

    @ViewBuilder
    private func calendarEventBlock(_ event: CalendarEvent) -> some View {
        let yOffset = yPosition(for: event.startDate)
        let height = max(blockHeight(from: event.startDate, to: event.endDate), 16)
        let isPast = event.endDate < Date()

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendarColor))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isPast ? DS.textMuted : DS.text)
                    .lineLimit(1)

                if height > 24 {
                    Text(timeRange(event.startDate, event.endDate))
                        .font(.system(size: 8))
                        .foregroundColor(DS.textMuted)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
        }
        .padding(.vertical, 2)
        .frame(height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: event.calendarColor).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: event.calendarColor).opacity(0.2), lineWidth: 0.5)
        )
        .opacity(isPast ? 0.6 : 1.0)
        .offset(x: 40, y: yOffset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }

    // MARK: - Session Block

    @ViewBuilder
    private func sessionBlock(_ session: SessionTimelineEntry) -> some View {
        let yOffset = yPosition(for: session.startTime)
        let height = max(blockHeight(from: session.startTime, to: session.endTime), 20)

        HStack(spacing: 6) {
            Image(systemName: session.intent.iconName)
                .font(.system(size: 8))
                .foregroundColor(.white)

            Text(session.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 2)

            // Duration
            Text(sessionDuration(session))
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            // Focus score dot
            Circle()
                .fill(focusColor(session.focusScore))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(height: height, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(session.intent.color.opacity(0.85))
        )
        .offset(x: 40, y: yOffset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }

    // MARK: - Now Marker

    private var nowMarker: some View {
        let yOffset = yPosition(for: Date())

        return HStack(spacing: 0) {
            Circle()
                .fill(PlannerumColors.nowMarker)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(PlannerumColors.nowMarker)
                .frame(height: 1.5)
        }
        .offset(x: 28, y: yOffset)
    }

    // MARK: - Positioning Helpers

    private func yPosition(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let fractionalHour = Double(hour - startHour) + Double(minute) / 60.0
        return max(0, CGFloat(fractionalHour) * hourHeight)
    }

    private func blockHeight(from start: Date, to end: Date) -> CGFloat {
        let duration = end.timeIntervalSince(start) / 3600.0
        return CGFloat(duration) * hourHeight
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 || hour == 12 { return hour == 0 ? "12a" : "12p" }
        if hour < 12 { return "\(hour)a" }
        return "\(hour - 12)p"
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm"
        return "\(fmt.string(from: start))-\(fmt.string(from: end))"
    }

    private func sessionDuration(_ session: SessionTimelineEntry) -> String {
        let mins = Int(session.endTime.timeIntervalSince(session.startTime) / 60)
        if mins >= 60 {
            return "\(mins / 60)h\(mins % 60)m"
        }
        return "\(mins)m"
    }

    private func focusColor(_ score: Double) -> Color {
        if score >= 80 { return .white }
        if score >= 50 { return .yellow }
        return .red
    }
}
