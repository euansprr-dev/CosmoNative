// CosmoOS/Data/Models/CaptureDestination.swift
// Custom capture lanes: user-defined command destinations for Telegram/CMD+K capture.

import Foundation
import GRDB
import SwiftUI

enum CaptureDestinationType: String, Codable, CaseIterable, Sendable {
    case listLane = "list_lane"
    case taskLane = "task_lane"
    case researchLane = "research_lane"
    case mediaSwipeLane = "media_swipe_lane"
    case deepDiveLane = "deep_dive_lane"
    case projectLane = "project_lane"
    case contentLane = "content_lane"
    case journalLane = "journal_lane"
    case sourceLane = "source_lane"
    case structuredLane = "structured_lane"

    var displayName: String {
        switch self {
        case .listLane: return "List"
        case .taskLane: return "Tasks"
        case .researchLane: return "Research"
        case .mediaSwipeLane: return "Media"
        case .deepDiveLane: return "Deep Dive"
        case .projectLane: return "Project"
        case .contentLane: return "Content"
        case .journalLane: return "Journal"
        case .sourceLane: return "Sources"
        case .structuredLane: return "Structured"
        }
    }

    var defaultIcon: String {
        switch self {
        case .listLane: return "list.bullet"
        case .taskLane: return "checklist"
        case .researchLane: return "doc.text.magnifyingglass"
        case .mediaSwipeLane: return "rectangle.grid.2x2"
        case .deepDiveLane: return "scope"
        case .projectLane: return "folder"
        case .contentLane: return "paperplane"
        case .journalLane: return "book.closed"
        case .sourceLane: return "doc.richtext"
        case .structuredLane: return "tablecells"
        }
    }

    var defaultObjectType: String {
        switch self {
        case .listLane: return AtomType.note.rawValue
        case .taskLane: return AtomType.task.rawValue
        case .researchLane, .sourceLane: return AtomType.research.rawValue
        case .mediaSwipeLane: return AtomType.research.rawValue
        case .deepDiveLane: return AtomType.extract.rawValue
        case .projectLane: return AtomType.idea.rawValue
        case .contentLane: return AtomType.content.rawValue
        case .journalLane: return AtomType.journalEntry.rawValue
        case .structuredLane: return AtomType.note.rawValue
        }
    }
}

enum CaptureDestinationReviewBehavior: String, Codable, CaseIterable, Sendable {
    case saveOnly = "save_only"
    case createObject = "create_object"
    case needsReview = "needs_review"
    case suggestActions = "suggest_actions"

    var displayName: String {
        switch self {
        case .saveOnly: return "Save Only"
        case .createObject: return "Create Object"
        case .needsReview: return "Review"
        case .suggestActions: return "Suggest"
        }
    }
}

enum CaptureDestinationConflictStatus: String, Codable, Sendable {
    case clear
    case duplicateAlias = "duplicate_alias"
    case deepDiveAliasConflict = "deep_dive_alias_conflict"
    case systemCommandConflict = "system_command_conflict"
}

enum CaptureMediaKind: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case screenshot
    case pdf
    case markdown
    case textFile = "text_file"
    case audio
    case video
    case document

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Images"
        case .screenshot: return "Screenshots"
        case .pdf: return "PDFs"
        case .markdown: return "Markdown"
        case .textFile: return "Text Files"
        case .audio: return "Audio"
        case .video: return "Video"
        case .document: return "Documents"
        }
    }
}

struct CaptureDestination: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "capture_destinations"

    var id: Int64?
    var uuid: String
    var name: String
    var destinationDescription: String?
    var type: CaptureDestinationType
    var aliasesJSON: String
    var icon: String
    var colorAccentToken: String?
    var defaultObjectType: String
    var defaultParentTarget: String?
    var defaultReviewBehavior: CaptureDestinationReviewBehavior
    var telegramCommandPatternsJSON: String?
    var acceptedMediaTypesJSON: String?
    var processingRulesJSON: String?
    var routingRulesJSON: String?
    var isArchived: Bool
    var isEnabled: Bool
    var createdAt: String
    var updatedAt: String
    var lastUsedAt: String?
    var itemCount: Int
    var conflictStatus: CaptureDestinationConflictStatus

    var aliases: [String] {
        decodeStringArray(aliasesJSON)
    }

    var telegramCommandPatterns: [String] {
        decodeStringArray(telegramCommandPatternsJSON)
    }

    var acceptedMediaTypes: [CaptureMediaKind] {
        guard let data = acceptedMediaTypesJSON?.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return [.text, .image, .screenshot, .pdf, .markdown, .textFile, .audio, .document]
        }
        return raw.compactMap(CaptureMediaKind.init(rawValue:))
    }

    static func make(
        name: String,
        description: String? = nil,
        type: CaptureDestinationType? = nil,
        aliases: [String]? = nil,
        defaultParentTarget: String? = nil
    ) -> CaptureDestination {
        let inferredType = type ?? inferType(from: name)
        let normalizedAliases = aliases ?? defaultAliases(for: name)
        let now = ISO8601DateFormatter().string(from: Date())
        return CaptureDestination(
            id: nil,
            uuid: UUID().uuidString,
            name: name,
            destinationDescription: description,
            type: inferredType,
            aliasesJSON: encodeStringArray(normalizedAliases),
            icon: inferredType.defaultIcon,
            colorAccentToken: nil,
            defaultObjectType: inferredType.defaultObjectType,
            defaultParentTarget: defaultParentTarget,
            defaultReviewBehavior: inferredType == .taskLane ? .createObject : .saveOnly,
            telegramCommandPatternsJSON: encodeStringArray(normalizedAliases.map { "\($0):" }),
            acceptedMediaTypesJSON: encodeStringArray(defaultAcceptedMedia(for: inferredType).map(\.rawValue)),
            processingRulesJSON: nil,
            routingRulesJSON: nil,
            isArchived: false,
            isEnabled: true,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil,
            itemCount: 0,
            conflictStatus: .clear
        )
    }

    static func inferType(from rawName: String) -> CaptureDestinationType {
        let name = rawName.lowercased()
        if name.contains("todo") || name.contains("to do") || name.contains("task") || name.contains("admin") {
            return .taskLane
        }
        if name.contains("swipe") || name.contains("inspiration") || name.contains("image") || name.contains("screenshot") || name.contains("cover") {
            return .mediaSwipeLane
        }
        if name.contains("source") || name.contains("paper") || name.contains("pdf") {
            return .sourceLane
        }
        if name.contains("research") || name.contains("inquiry") || name.contains("deep dive") {
            return .researchLane
        }
        if name.contains("idea") || name.contains("project") {
            return .projectLane
        }
        if name.contains("journal") || name.contains("log") {
            return .journalLane
        }
        if name.contains("book") || name.contains("movie") || name.contains("watch") || name.contains("list") {
            return .listLane
        }
        return .listLane
    }

    static func defaultAliases(for name: String) -> [String] {
        let normalized = normalizeAlias(name)
        var aliases: [String] = [normalized]
        let words = normalized.split(separator: " ").map(String.init)
        if words.count > 1 {
            aliases.append(words.joined(separator: ""))
            let initials = words.compactMap(\.first).map(String.init).joined()
            if initials.count >= 2 {
                aliases.append(initials)
            }
        }
        return Array(NSOrderedSet(array: aliases)) as? [String] ?? aliases
    }

    static func normalizeAlias(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[\u{201C}\u{201D}]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultAcceptedMedia(for type: CaptureDestinationType) -> [CaptureMediaKind] {
        switch type {
        case .listLane:
            return [.text, .image, .screenshot]
        case .taskLane:
            return [.text, .image, .screenshot, .pdf, .document, .audio]
        case .researchLane, .deepDiveLane, .sourceLane:
            return [.text, .image, .screenshot, .pdf, .markdown, .textFile, .audio, .document]
        case .mediaSwipeLane:
            return [.text, .image, .screenshot, .video]
        case .projectLane, .contentLane, .journalLane, .structuredLane:
            return [.text, .image, .screenshot, .pdf, .markdown, .textFile, .audio, .document]
        }
    }
}

private func encodeStringArray(_ value: [String]) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "[]" }
    return String(data: data, encoding: .utf8) ?? "[]"
}

private func decodeStringArray(_ value: String?) -> [String] {
    guard let value,
          let data = value.data(using: .utf8),
          let decoded = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return decoded
}
