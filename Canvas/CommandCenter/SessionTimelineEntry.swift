// Canvas/CommandCenter/SessionTimelineEntry.swift
// Data model for timeline entries (tracked deep work sessions)
// March 2026

import Foundation

struct SessionTimelineEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let intent: ResolvedIntentPresentation
    let habitTitle: String?
    let startTime: Date
    let endTime: Date
    let focusScore: Double
    let taskUUID: String?
}
