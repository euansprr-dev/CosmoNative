// Canvas/CommandCenter/SessionTimelineEntry.swift
// Data model for timeline entries (tracked deep work sessions)
// March 2026

import Foundation

struct SessionTimelineEntry: Identifiable {
    let id: String
    let title: String
    let intent: TaskIntent
    let startTime: Date
    let endTime: Date
    let focusScore: Double
    let taskUUID: String?
}
