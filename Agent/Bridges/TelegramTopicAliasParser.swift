// CosmoOS/Agent/Bridges/TelegramTopicAliasParser.swift
// Parses Telegram captures of the form `<alias>: <body>` or `<alias>/<sub>: <body>`.
// Sub-routes: source, q (or question), idea, output, term, principle, objection, practice, connection.
// Plan §14.

import Foundation

enum TelegramTopicSubRoute: String {
    case general
    case source
    case question        // alias: q, question
    case idea
    case output
    case term
    case principle
    case objection
    case practice
    case connection

    static func parse(_ raw: String) -> TelegramTopicSubRoute? {
        switch raw.lowercased() {
        case "": return nil
        case "source", "src": return .source
        case "q", "question": return .question
        case "idea": return .idea
        case "output", "out": return .output
        case "term": return .term
        case "principle": return .principle
        case "objection": return .objection
        case "practice": return .practice
        case "connection", "concept": return .connection
        default: return nil
        }
    }
}

struct TelegramTopicCapture: Equatable {
    let alias: String
    let subRoute: TelegramTopicSubRoute
    let body: String
}

enum TelegramTopicAliasParser {

    /// Parse `breathwork: ...` or `bw/source: ...`. Returns nil if no prefix detected.
    static func parse(_ text: String) -> TelegramTopicCapture? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find first colon
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }
        let prefix = String(trimmed[..<colonIndex])
        // Body must not be empty
        let bodyStart = trimmed.index(after: colonIndex)
        let body = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        // Prefix must be a single-token alias (or alias/sub) with no spaces
        guard !prefix.contains(" ") else { return nil }
        // Skip URL-like prefixes (http: / https: / mailto:) — they are not aliases
        let lowerPrefix = prefix.lowercased()
        let urlSchemes = ["http", "https", "ftp", "mailto", "tel", "file"]
        if urlSchemes.contains(lowerPrefix) { return nil }
        // Reject pure-numeric prefixes
        if Int(prefix) != nil { return nil }
        // Length sanity
        guard prefix.count >= 2 && prefix.count <= 32 else { return nil }

        if let slashIndex = prefix.firstIndex(of: "/") {
            let alias = String(prefix[..<slashIndex])
            let subRaw = String(prefix[prefix.index(after: slashIndex)...])
            guard let sub = TelegramTopicSubRoute.parse(subRaw) else { return nil }
            return TelegramTopicCapture(alias: alias, subRoute: sub, body: body)
        } else {
            return TelegramTopicCapture(alias: prefix, subRoute: .general, body: body)
        }
    }
}

/// Routes a parsed `TelegramTopicCapture` to the right Cosmo destination.
@MainActor
enum TelegramTopicRouter {
    enum Outcome {
        case routed(destination: String, atomUUID: String?)
        case unknownAlias(alias: String, suggestion: String?)
        case failed(reason: String)
    }

    static func route(_ capture: TelegramTopicCapture) async -> Outcome {
        // Resolve alias
        guard let deepDiveUUID = await DeepDiveAliasRegistry.shared.deepDiveUUID(forAlias: capture.alias) else {
            let suggestion = closestAlias(to: capture.alias)
            return .unknownAlias(alias: capture.alias, suggestion: suggestion)
        }
        guard let deepDive = try? await AtomRepository.shared.fetch(uuid: deepDiveUUID) else {
            return .failed(reason: "Deep Dive lookup failed.")
        }

        switch capture.subRoute {
        case .general:
            return await routeAsTopicInbox(capture, deepDive: deepDive)
        case .question:
            return await routeAsQuestion(capture, deepDive: deepDive)
        case .source:
            return await routeAsSource(capture, deepDive: deepDive)
        case .idea, .output:
            return await routeAsIdea(capture, deepDive: deepDive, kind: capture.subRoute == .idea ? "idea" : "output")
        case .term:
            return await routeAsLexicon(capture, deepDive: deepDive)
        case .principle, .objection, .practice:
            return await routeAsExtract(capture, deepDive: deepDive)
        case .connection:
            return await routeAsTopicInbox(capture, deepDive: deepDive)
        }
    }

    // MARK: - Subroutes

    private static func routeAsTopicInbox(_ capture: TelegramTopicCapture, deepDive: Atom) async -> Outcome {
        // Phase 6 V1: persist as InboxItem with placeThinkspaceId = deepDive.uuid so it shows in Topic Inbox.
        do {
            var item = InboxItem.new(source: .telegramText, rawText: capture.body)
            item.placeThinkspaceId = deepDive.uuid
            item.placeThinkspaceName = deepDive.title
            item.classification = .place
            item.confidence = 1.0
            item.status = .classified
            try await CosmoDatabase.shared.asyncWrite { db in
                try item.insert(db)
            }
            NotificationCenter.default.post(
                name: CosmoNotification.Inbox.itemAdded,
                object: nil
            )
            return .routed(destination: "\(deepDive.title ?? "Deep Dive") → Topic Inbox", atomUUID: nil)
        } catch {
            return .failed(reason: "Inbox insert failed: \(error.localizedDescription)")
        }
    }

    private static func routeAsQuestion(_ capture: TelegramTopicCapture, deepDive: Atom) async -> Outcome {
        do {
            let question = try await InquiryRepository.shared.createQuestion(
                title: capture.body,
                parentDeepDiveUUID: deepDive.uuid,
                originSessionUUID: nil,
                parentQuestionUUID: nil,
                originExtractUUID: nil
            )
            // Touch Deep Dive: link + bump maturity
            var ddCopy = deepDive
            ddCopy = ddCopy.appendingLink(AtomLink(
                type: AtomLinkType.deepDiveQuestion.rawValue,
                uuid: question.uuid,
                entityType: AtomType.question.rawValue
            ))
            _ = try? await AtomRepository.shared.update(ddCopy)
            return .routed(destination: "\(deepDive.title ?? "Deep Dive") → Questions", atomUUID: question.uuid)
        } catch {
            return .failed(reason: "Question create failed: \(error.localizedDescription)")
        }
    }

    private static func routeAsSource(_ capture: TelegramTopicCapture, deepDive: Atom) async -> Outcome {
        // Body is typically a URL. Persist as `.research` atom (existing source kind) and link.
        do {
            let url = capture.body
            let title = url.contains("://") ? (URL(string: url)?.host ?? url) : url
            let research = try await AtomRepository.shared.createResearch(
                title: title,
                url: url.contains("://") ? url : "",
                summary: nil
            )
            var ddCopy = deepDive
            ddCopy = ddCopy.appendingLink(AtomLink(
                type: AtomLinkType.deepDiveSource.rawValue,
                uuid: research.uuid,
                entityType: AtomType.research.rawValue
            ))
            _ = try? await AtomRepository.shared.update(ddCopy)
            return .routed(destination: "\(deepDive.title ?? "Deep Dive") → Sources", atomUUID: research.uuid)
        } catch {
            return .failed(reason: "Source create failed: \(error.localizedDescription)")
        }
    }

    private static func routeAsIdea(_ capture: TelegramTopicCapture, deepDive: Atom, kind: String) async -> Outcome {
        do {
            let idea = try await AtomRepository.shared.createIdea(title: capture.body, content: "")
            var ddCopy = deepDive
            ddCopy = ddCopy.appendingLink(AtomLink(
                type: AtomLinkType.contentFromDeepDive.rawValue,
                uuid: idea.uuid,
                entityType: AtomType.idea.rawValue
            ))
            _ = try? await AtomRepository.shared.update(ddCopy)
            return .routed(destination: "\(deepDive.title ?? "Deep Dive") → \(kind.capitalized)s", atomUUID: idea.uuid)
        } catch {
            return .failed(reason: "Idea create failed: \(error.localizedDescription)")
        }
    }

    private static func routeAsLexicon(_ capture: TelegramTopicCapture, deepDive: Atom) async -> Outcome {
        // Treat the body as a term. Empty definition (user defines later).
        do {
            let entry = try await InquiryRepository.shared.createLexiconEntry(
                term: capture.body,
                definition: "",
                parentDeepDiveUUID: deepDive.uuid,
                maturity: .entry
            )
            return .routed(destination: "\(deepDive.title ?? "Deep Dive") → Lexicon", atomUUID: entry.uuid)
        } catch {
            return .failed(reason: "Lexicon create failed: \(error.localizedDescription)")
        }
    }

    private static func routeAsExtract(_ capture: TelegramTopicCapture, deepDive: Atom) async -> Outcome {
        let kind: ExtractKind
        switch capture.subRoute {
        case .principle: kind = .principle
        case .objection: kind = .objection
        case .practice: kind = .practice
        default: kind = .note
        }
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: capture.body,
                kind: kind,
                sourceUUID: nil,
                selectionRange: nil,
                sessionUUID: nil,
                questionUUID: nil,
                deepDiveUUID: deepDive.uuid,
                branchNodeId: nil,
                sourceTabId: nil,
                userNote: nil,
                originType: "telegram",
                citation: nil
            )
            var ddCopy = deepDive
            ddCopy = ddCopy.appendingLink(AtomLink(
                type: AtomLinkType.deepDiveExtract.rawValue,
                uuid: extract.uuid,
                entityType: AtomType.extract.rawValue
            ))
            _ = try? await AtomRepository.shared.update(ddCopy)
            return .routed(destination: "\(deepDive.title ?? "Deep Dive") → \(kind.displayName)s", atomUUID: extract.uuid)
        } catch {
            return .failed(reason: "Extract create failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func closestAlias(to term: String) -> String? {
        let candidates = DeepDiveAliasRegistry.shared.allAliases()
        let target = term.lowercased()
        let scored = candidates.map { ($0, levenshtein($0, target)) }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        // Only suggest if reasonably close (≤2 edits)
        return best.1 <= 2 ? best.0 : nil
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var prev = Array(0...bChars.count)
        var curr = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...max(aChars.count, 1) {
            curr[0] = i
            for j in 1...max(bChars.count, 1) {
                let cost = (i <= aChars.count && j <= bChars.count && aChars[i-1] == bChars[j-1]) ? 0 : 1
                curr[j] = Swift.min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
            }
            prev = curr
        }
        return prev[bChars.count]
    }
}
