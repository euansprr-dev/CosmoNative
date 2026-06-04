// CosmoOS/Canvas/CommandCenter/ZoneContentView.swift
// LOD dispatcher — routes zone type to the appropriate zone view
// Degrades gracefully at extreme zoom levels
// March 2026

import SwiftUI

struct ZoneContentView: View {
    let zoneType: String
    let contentSize: CGSize
    let effectiveScale: CGFloat

    var body: some View {
        if effectiveScale < 0.3 {
            zoneIconView
        } else if effectiveScale < 0.5 {
            zoneSummaryView
        } else {
            zoneFullView
        }
    }

    // MARK: - Full Interactive Content

    @ViewBuilder
    private var zoneFullView: some View {
        switch zoneType {
        case "dashboard":
            CommandCenterDashboard()
        case "welcomeHub", "planningDock", "goalForge", "questBoard":
            // Legacy zones — show migration message
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(DS.textMuted)
                Text("Relaunch to upgrade")
                    .font(DS.cardMeta)
                    .foregroundColor(DS.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            defaultPlaceholder
        }
    }

    // MARK: - Summary View (zoomed out 0.3–0.5)

    @ViewBuilder
    private var zoneSummaryView: some View {
        if let zt = CommandCenterZoneType(rawValue: zoneType) {
            VStack(spacing: 8) {
                Image(systemName: zt.iconName)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(zt.accentColor)

                Text(zt.displayName)
                    .font(DS.headline)
                    .foregroundColor(DS.text)

                Text(zoneSummaryText(for: zt))
                    .font(DS.footnote)
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            defaultPlaceholder
        }
    }

    // MARK: - Icon Only View (zoomed out < 0.3)

    @ViewBuilder
    private var zoneIconView: some View {
        if let zt = CommandCenterZoneType(rawValue: zoneType) {
            VStack(spacing: 4) {
                Image(systemName: zt.iconName)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(zt.accentColor)

                Text(zt.displayName)
                    .font(DS.subheadline).fontWeight(.medium)
                    .foregroundColor(DS.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            defaultPlaceholder
        }
    }

    // MARK: - Helpers

    private var defaultPlaceholder: some View {
        Text(zoneType)
            .font(DS.cardTitle)
            .foregroundColor(DS.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func zoneSummaryText(for type: CommandCenterZoneType) -> String {
        switch type {
        case .dashboard:     return "Tasks · Habits · Focus"
        case .welcomeHub:    return "Greeting & Quick Actions"
        case .planningDock:  return "Today's Schedule"
        case .goalForge:     return "Objectives & Vision"
        case .questBoard:    return "Daily Quests"
        default:             return type.displayName
        }
    }
}
