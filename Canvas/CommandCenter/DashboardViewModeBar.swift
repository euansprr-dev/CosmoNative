// Canvas/CommandCenter/DashboardViewModeBar.swift
// Todoist-style view mode tabs: Today / Upcoming / Completed
// March 2026

import SwiftUI

/// The two faces of Upcoming: the week schedule (tasks, time blocks,
/// external events) and the content calendar (posts on a month grid with
/// the idea/draft shelf in the rail).
/// `.content` is RETIRED (September 2026): the month calendar lives in
/// Studio › Pipeline. The case stays so persisted rawValues decode and old
/// jump targets redirect; the switcher no longer offers it.
enum UpcomingLens: String, CaseIterable {
    case schedule
    case content

    var label: String {
        switch self {
        case .schedule: return "Schedule"
        case .content: return "Content"
        }
    }

    var help: String {
        switch self {
        case .schedule: return "Tasks and time blocks, week by week"
        case .content: return "Posts and ideas on a month calendar"
        }
    }
}

/// What the right rail shows on Upcoming's schedule lens. The Shelf is where
/// unscheduled ideas wait to be dragged onto a day; the inspector is the
/// existing habits/reports/details stack.
enum UpcomingRailFace: String {
    case shelf
    case inspector
}

enum DashboardViewMode: String, CaseIterable {
    case today
    case upcoming
    case anytime
    case someday
    case logbook
    case habits
    case reports
    case queue
    case project       // Viewing a specific project
    case area          // Viewing all tasks in an area

    /// Smart list modes shown in sidebar navigation
    static var smartLists: [DashboardViewMode] {
        [.today, .upcoming, .anytime, .someday, .logbook]
    }

    /// Planning modes shown in sidebar navigation. The queue page retired
    /// July 2026 — content planning lives in Upcoming's Content lens, and
    /// `.queue` survives only as a redirect for old jump targets.
    static var planningLists: [DashboardViewMode] {
        [.habits, .reports]
    }

    var showsTaskList: Bool {
        switch self {
        case .today, .upcoming, .anytime, .someday, .logbook, .project, .area:
            return true
        case .habits, .reports, .queue:
            return false
        }
    }

    var isFullPlanningPage: Bool {
        switch self {
        case .habits, .reports, .queue:
            return true
        case .today, .upcoming, .anytime, .someday, .logbook, .project, .area:
            return false
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .anytime: return "Anytime"
        case .someday: return "Someday"
        case .logbook: return "Logbook"
        case .habits: return "Habits"
        case .reports: return "Reports"
        case .queue: return "Content Calendar"
        case .project: return "Project"
        case .area: return "Area"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .anytime: return "tray.full"
        case .someday: return "archivebox"
        case .logbook: return "book.closed"
        case .habits: return "repeat"
        case .reports: return "chart.bar"
        case .queue: return "paperplane"
        case .project: return "folder.fill"
        case .area: return "square.stack.fill"
        }
    }

    var activeTint: Color {
        switch self {
        case .today: return DS.orange
        case .upcoming: return DS.info
        case .anytime: return DS.entityIdea
        case .someday: return DS.entityConnection
        case .logbook: return DS.green
        case .habits: return DS.entityIdea
        case .reports: return DS.info
        case .queue: return DS.entityContent
        case .project, .area: return DS.accent
        }
    }
}

// DashboardViewModeBar (the Todoist-style tab strip) was deleted July 2026:
// never instantiated since the Things-style sidebar took over navigation.
// The DashboardViewMode enum above is the live part of this file.
