// CosmoOS/Agent/Bridges/TelegramCaptureCommandParser.swift
// Deterministic grammar for custom capture lanes and media-aware Telegram commands.

import Foundation

enum TelegramCaptureSubroute: String, Equatable, Sendable {
    case general
    case source
    case question
    case evidence
    case counterevidence
    case claim
    case practice
    case term
    case output
    case image
    case file
    case note
    case task

    static func parse(_ raw: String?) -> TelegramCaptureSubroute {
        guard let raw, !raw.isEmpty else { return .general }
        switch raw.lowercased() {
        case "source", "src", "sources": return .source
        case "question", "q", "questions": return .question
        case "evidence", "ev": return .evidence
        case "counterevidence", "counter", "counter-evidence": return .counterevidence
        case "claim", "claims": return .claim
        case "practice", "protocol": return .practice
        case "term", "terms": return .term
        case "output", "out": return .output
        case "image", "img", "screenshot", "screen": return .image
        case "file", "doc", "document", "pdf": return .file
        case "note", "notes": return .note
        case "task", "todo", "to-do": return .task
        default: return .general
        }
    }
}

struct TelegramCaptureCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case route
        case createLane
    }

    var kind: Kind
    var commandText: String
    var destinationName: String
    var subroute: TelegramCaptureSubroute
    var body: String
    var requestedLaneType: CaptureDestinationType?
    var shouldCaptureRemainder: Bool
}

enum TelegramCaptureCommandParser {
    static func parse(_ rawText: String, allowsEmptyBody: Bool = false) -> TelegramCaptureCommand? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let creation = parseCreateLane(text, allowsEmptyBody: allowsEmptyBody) {
            return creation
        }

        return parsePrefix(text, allowsEmptyBody: allowsEmptyBody)
    }

    static func parsePrefix(_ text: String, allowsEmptyBody: Bool = false) -> TelegramCaptureCommand? {
        guard let colonIndex = text.firstIndex(of: ":") else { return nil }
        let prefix = String(text[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyStart = text.index(after: colonIndex)
        let body = String(text[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard allowsEmptyBody || !body.isEmpty else { return nil }
        guard isValidPrefix(prefix) else { return nil }

        let parts = prefix.split(separator: "/", maxSplits: 1).map(String.init)
        let destination = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !destination.isEmpty else { return nil }
        let subroute = TelegramCaptureSubroute.parse(parts.count > 1 ? parts[1] : nil)

        return TelegramCaptureCommand(
            kind: .route,
            commandText: prefix,
            destinationName: destination,
            subroute: subroute,
            body: body,
            requestedLaneType: nil,
            shouldCaptureRemainder: true
        )
    }

    static func parseCreateLane(_ text: String, allowsEmptyBody: Bool = false) -> TelegramCaptureCommand? {
        let patterns = [
            #"(?i)^create\s+(?:a\s+)?new\s+(inbox|lane|media lane|task lane|research lane)\s+named\s+[“"]([^”"]+)[”"](?:\s+and\s+(?:capture|save)\s+this:?)?\s*(.*)$"#,
            #"(?i)^create\s+(?:a\s+)?(?:new\s+)?(inbox|lane|media lane|task lane|research lane)\s+called\s+[“"]([^”"]+)[”"](?:\s+(?:for\s+([a-z ]+))?)?(?:\s+and\s+(?:capture|save)\s+this\s*(?:file|image|pdf)?:?)?\s*(.*)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range) else { continue }

            let laneKind = capture(match, in: text, at: 1)
            let name = capture(match, in: text, at: 2)
            let purpose = capture(match, in: text, at: 3)
            let body = capture(match, in: text, at: 4)
            let resolvedBody = body.isEmpty ? purpose : body

            guard !name.isEmpty else { continue }
            guard allowsEmptyBody || !resolvedBody.isEmpty || text.localizedCaseInsensitiveContains("capture this") || text.localizedCaseInsensitiveContains("save this") else {
                return TelegramCaptureCommand(
                    kind: .createLane,
                    commandText: "create lane",
                    destinationName: name,
                    subroute: .general,
                    body: "",
                    requestedLaneType: typeFromCreationKind(laneKind, purpose: purpose, name: name),
                    shouldCaptureRemainder: false
                )
            }

            return TelegramCaptureCommand(
                kind: .createLane,
                commandText: "create lane",
                destinationName: name,
                subroute: .general,
                body: resolvedBody.trimmingCharacters(in: .whitespacesAndNewlines),
                requestedLaneType: typeFromCreationKind(laneKind, purpose: purpose, name: name),
                shouldCaptureRemainder: !resolvedBody.isEmpty || text.localizedCaseInsensitiveContains("capture this") || text.localizedCaseInsensitiveContains("save this")
            )
        }

        return nil
    }

    private static func isValidPrefix(_ prefix: String) -> Bool {
        guard prefix.count >= 2, prefix.count <= 64 else { return false }
        let lower = prefix.lowercased()
        let urlSchemes = ["http", "https", "ftp", "mailto", "tel", "file"]
        guard !urlSchemes.contains(lower) else { return false }
        guard Int(prefix) == nil else { return false }
        if prefix.contains("/") {
            return prefix.split(separator: "/").count == 2
        }
        return true
    }

    private static func capture(_ match: NSTextCheckingResult, in text: String, at index: Int) -> String {
        guard index < match.numberOfRanges else { return "" }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func typeFromCreationKind(_ kind: String, purpose: String, name: String) -> CaptureDestinationType {
        let joined = "\(kind) \(purpose) \(name)".lowercased()
        if joined.contains("media") || joined.contains("swipe") || joined.contains("image") || joined.contains("inspiration") {
            return .mediaSwipeLane
        }
        if joined.contains("task") || joined.contains("todo") || joined.contains("admin") {
            return .taskLane
        }
        if joined.contains("research") || joined.contains("source") {
            return .researchLane
        }
        return CaptureDestination.inferType(from: name)
    }
}
