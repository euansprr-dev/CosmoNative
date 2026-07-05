// CosmoOS/UI/InlineAssistant/CosmoInlineInquiryQuestion.swift
// The /concept chat ↔ inquiry loop. When concept conversation hits a genuine
// unknown, the assistant stages a question via the propose_inquiry_question
// tool; the pane renders a confirmation card. On confirm, the question lands
// in the sparking Connection's deep dive — as a root question or a sub-question
// of an existing line of inquiry — and the user jumps straight into the
// inquiry session. Crystallizing that session merges findings back into the
// Connection, closing the loop.

import Foundation

// MARK: - Proposal model

/// A staged "open an inquiry?" card in the assistant pane. Mirrors the shape of
/// `CosmoAssistantProposal` but resolves to navigation, not a diff: confirming
/// creates the Question atom and opens its inquiry session.
struct CosmoAssistantInquiryQuestionProposal: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, Equatable, Sendable {
        case pending
        case started
        case dismissed
    }

    var id = UUID()
    var question: String
    var rationale: String?
    var connectionUUID: String
    var connectionTitle: String
    var deepDiveUUID: String?
    var deepDiveTitle: String?
    /// Set when placement resolved to a sub-question of an existing root question.
    var parentQuestionUUID: String?
    var parentQuestionTitle: String?
    var status: Status = .pending
    var startedSessionUUID: String? = nil
    var createdAt = Date()

    var placementLabel: String {
        if let parentQuestionTitle, !parentQuestionTitle.isEmpty {
            return "Sub-question under “\(parentQuestionTitle)”"
        }
        if let deepDiveTitle, !deepDiveTitle.isEmpty {
            return "New question in “\(deepDiveTitle)”"
        }
        return "New deep dive from “\(connectionTitle)”"
    }
}

// MARK: - Resolution (deep dive home + tree placement)

/// Resolves where a proposed question belongs before the card renders, so the
/// user confirms a concrete destination ("Sub-question under X") rather than a
/// vague promise. Placement uses a fast sensor-tier call with a hard timeout;
/// any failure falls back to a root question — promoting later is cheap,
/// burying an independent question is not.
enum CosmoInlineInquiryQuestionResolver {
    struct Resolution: Sendable {
        var deepDive: Atom?
        var parentQuestion: Atom?
    }

    /// Minimal mirror of ConnectionPromotionService's private metadata — just
    /// the provenance field needed to walk a crystallized Connection home.
    private struct PromotedConnectionOrigin: Codable {
        var originDeepDiveUUID: String?
    }

    private struct PlacementReply: Decodable {
        var placement: String
        var parentQuestionUUID: String?
    }

    static func resolve(question: String, connection: Atom) async -> Resolution {
        guard let deepDive = await resolveDeepDive(for: connection) else {
            return Resolution(deepDive: nil, parentQuestion: nil)
        }
        let parent = await resolveParentQuestion(question: question, deepDive: deepDive)
        return Resolution(deepDive: deepDive, parentQuestion: parent)
    }

    /// The deep dive that owns this Connection: crystallization provenance
    /// first, then any deep dive that links the connection, newest activity
    /// winning. Nil means the confirm step will create one.
    static func resolveDeepDive(for connection: Atom) async -> Atom? {
        if let originUUID = connection.metadataValue(as: PromotedConnectionOrigin.self)?.originDeepDiveUUID,
           let origin = try? await AtomRepository.shared.fetch(uuid: originUUID),
           origin.type == .deepDive {
            return origin
        }
        guard let deepDives = try? await AtomRepository.shared.fetchAll(type: .deepDive) else { return nil }
        return deepDives
            .filter { dd in dd.linksOfType(.deepDiveConnection).contains { $0.uuid == connection.uuid } }
            .max { lhs, rhs in
                (lhs.deepDiveMetadata?.lastInquiryAt ?? "") < (rhs.deepDiveMetadata?.lastInquiryAt ?? "")
            }
    }

    private static func resolveParentQuestion(question: String, deepDive: Atom) async -> Atom? {
        guard let questions = try? await InquiryRepository.shared.fetchQuestions(forDeepDive: deepDive.uuid) else {
            return nil
        }
        let roots = questions.filter { $0.questionMetadata?.parentQuestionUUID == nil }
        guard !roots.isEmpty else { return nil }

        // Already a root question under this deep dive → root placement so
        // findOrCreateQuestion dedups onto it instead of nesting a duplicate.
        let key = ResearchTreeDocument.normalizedQuestionKey(question)
        if roots.contains(where: { ResearchTreeDocument.normalizedQuestionKey($0.title ?? "") == key }) {
            return nil
        }

        let listing = roots
            .compactMap { root in root.title.map { "- \(root.uuid): \($0)" } }
            .joined(separator: "\n")
        let prompt = """
        NEW QUESTION: \(question)

        EXISTING ROOT QUESTIONS in the deep dive "\(deepDive.title ?? "Untitled")":
        \(listing)
        """

        let raw = try? await withTimeout(seconds: 8) {
            try await ResearchService.shared.analyze(
                prompt: prompt,
                systemPrompt: placementSystemPrompt,
                tier: .sensor,
                maxTokens: 200
            )
        }
        guard let raw,
              let reply = parsePlacement(raw),
              reply.placement == "sub",
              let parentUUID = reply.parentQuestionUUID else {
            return nil
        }
        // Never trust an invented UUID — only accept one from the listing.
        return roots.first { $0.uuid == parentUUID }
    }

    private static let placementSystemPrompt = """
    You place a NEW research question into a deep dive's question tree.

    Decide: is the new question a narrower line of inquiry INSIDE one existing root question ("sub"), \
    or its own independent line ("root")?

    HOW TO DECIDE: a sub-question's answer is part of answering its parent — same subject, narrower \
    scope. "How does breathwork affect sleep?" is a sub of "How does breathwork work?". If the new \
    question would still matter after the candidate parent is fully answered, or it pursues a \
    different subject or outcome, it is a root question. When torn, choose root — promoting a root \
    later is cheap; burying an independent question is not.

    Respond with VALID JSON only, no prose:
    {"placement":"root"}
    or
    {"placement":"sub","parentQuestionUUID":"<uuid copied from the list>"}

    Never invent a UUID — only use one that appears in the input list.
    """

    private static func parsePlacement(_ raw: String) -> PlacementReply? {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"),
              start <= end else { return nil }
        return try? JSONDecoder().decode(PlacementReply.self, from: Data(cleaned[start...end].utf8))
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Confirm flow

/// Runs when the user confirms the card: ensure the deep dive home, create the
/// (deduped) Question atom with Connection provenance, graft it into the right
/// session's research tree, and navigate via the app's inquiry plumbing.
@MainActor
enum CosmoInlineInquiryQuestionStarter {
    struct StartResult: Sendable {
        var sessionUUID: String
        var deepDiveUUID: String
        var questionUUID: String
    }

    enum StartError: LocalizedError {
        case connectionMissing

        var errorDescription: String? {
            switch self {
            case .connectionMissing:
                return "The concept that sparked this question no longer exists."
            }
        }
    }

    static func start(_ proposal: CosmoAssistantInquiryQuestionProposal) async throws -> StartResult {
        guard let connection = try await AtomRepository.shared.fetch(uuid: proposal.connectionUUID),
              connection.type == .connection else {
            throw StartError.connectionMissing
        }

        let deepDive = try await ensureDeepDive(for: connection, preferredUUID: proposal.deepDiveUUID)
        let parentQuestion: Atom? = await {
            guard let parentUUID = proposal.parentQuestionUUID else { return nil }
            return try? await AtomRepository.shared.fetch(uuid: parentUUID)
        }()

        let question = try await ensureQuestion(
            proposal: proposal,
            deepDive: deepDive,
            parentQuestion: parentQuestion,
            connection: connection
        )

        // One question = one continuing session: the session anchors the root
        // of the line — the parent for sub-questions, the question itself for roots.
        let rootQuestion = parentQuestion ?? question
        let session = try await ensureSession(
            deepDive: deepDive,
            rootQuestion: rootQuestion,
            connection: connection
        )
        if parentQuestion != nil {
            try await graftBranch(question: question, rootQuestion: rootQuestion, session: session)
        }

        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.startInquiry,
            object: nil,
            userInfo: [
                "anchorUUID": connection.uuid,
                "anchorType": AtomType.connection.rawValue,
                "resumeSessionUUID": session.uuid
            ]
        )

        return StartResult(
            sessionUUID: session.uuid,
            deepDiveUUID: deepDive.uuid,
            questionUUID: question.uuid
        )
    }

    /// Reopen an already-started inquiry from the card.
    static func reopen(sessionUUID: String, connectionUUID: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.startInquiry,
            object: nil,
            userInfo: [
                "anchorUUID": connectionUUID,
                "anchorType": AtomType.connection.rawValue,
                "resumeSessionUUID": sessionUUID
            ]
        )
    }

    // MARK: - Steps

    private static func ensureDeepDive(for connection: Atom, preferredUUID: String?) async throws -> Atom {
        var deepDive: Atom?
        if let preferredUUID,
           let preferred = try? await AtomRepository.shared.fetch(uuid: preferredUUID),
           preferred.type == .deepDive {
            deepDive = preferred
        }
        if deepDive == nil {
            deepDive = await CosmoInlineInquiryQuestionResolver.resolveDeepDive(for: connection)
        }
        var resolved: Atom
        if let deepDive {
            resolved = deepDive
        } else {
            resolved = try await InquiryRepository.shared.createDeepDive(
                title: connection.title ?? "Untitled Deep Dive",
                about: "Opened from Concept: \(connection.title ?? "Untitled")"
            )
        }

        // The sparking Connection must be a deepDiveConnection of its home —
        // that link is what lets crystallization merge new findings back into
        // the page instead of spawning a near-duplicate.
        if !resolved.linksOfType(.deepDiveConnection).contains(where: { $0.uuid == connection.uuid }) {
            resolved = resolved.appendingLink(
                AtomLink(
                    type: AtomLinkType.deepDiveConnection.rawValue,
                    uuid: connection.uuid,
                    entityType: AtomType.connection.rawValue
                )
            )
            resolved = try await AtomRepository.shared.update(resolved)
        }
        return resolved
    }

    private static func ensureQuestion(
        proposal: CosmoAssistantInquiryQuestionProposal,
        deepDive: Atom,
        parentQuestion: Atom?,
        connection: Atom
    ) async throws -> Atom {
        let (question, created) = try await InquiryRepository.shared.findOrCreateQuestion(
            title: proposal.question,
            parentDeepDiveUUID: deepDive.uuid,
            originSessionUUID: nil,
            parentQuestionUUID: parentQuestion?.uuid,
            originExtractUUID: nil
        )
        guard created else { return question }

        // Provenance: the question knows which Connection sparked it, and why.
        var stamped = question
        if var meta = stamped.questionMetadata {
            meta.placementOrigin = "connection-concept-chat"
            meta.placementExplanation = proposal.rationale
            stamped = stamped.withMetadata(meta)
        }
        stamped = stamped.appendingLink(
            AtomLink(
                type: AtomLinkType.connection.rawValue,
                uuid: connection.uuid,
                entityType: AtomType.connection.rawValue
            )
        )
        return try await AtomRepository.shared.update(stamped)
    }

    /// The most recent non-archived session for this root question, or a fresh
    /// session anchored to the sparking Connection. Mirrors
    /// InquirySessionLauncher's resume semantics.
    private static func ensureSession(
        deepDive: Atom,
        rootQuestion: Atom,
        connection: Atom
    ) async throws -> Atom {
        let sessions = (try? await InquiryRepository.shared.fetchSessions(forDeepDive: deepDive.uuid)) ?? []
        let titleKey = ResearchTreeDocument.normalizedQuestionKey(rootQuestion.title ?? "")
        let resumable = sessions
            .filter { session in
                guard let metadata = session.inquirySessionMetadata, metadata.status != .archived else { return false }
                if metadata.mainQuestionUUID == rootQuestion.uuid { return true }
                guard !titleKey.isEmpty, let sessionTitle = session.title else { return false }
                return ResearchTreeDocument.normalizedQuestionKey(sessionTitle) == titleKey
            }
            .max { lhs, rhs in
                (lhs.inquirySessionMetadata?.lastActiveAt ?? "") < (rhs.inquirySessionMetadata?.lastActiveAt ?? "")
            }
        if let resumable { return resumable }

        let result = try await InquiryRepository.shared.startSession(
            deepDive: deepDive,
            title: nil,
            mainQuestionTitle: rootQuestion.title,
            existingRootQuestion: rootQuestion,
            anchorObjectUUID: connection.uuid,
            anchorObjectType: AtomType.connection.rawValue
        )
        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.sessionStarted,
            object: nil,
            userInfo: [
                "sessionUUID": result.session.uuid,
                "deepDiveUUID": deepDive.uuid
            ]
        )
        return result.session
    }

    private static func graftBranch(question: Atom, rootQuestion: Atom, session: Atom) async throws {
        guard var structured = session.inquirySessionStructured else { return }
        var tree = structured.researchTree
        guard !tree.nodes.values.contains(where: { $0.atomUUID == question.uuid }) else { return }

        let parentNodeId = tree.nodes.values.first { $0.atomUUID == rootQuestion.uuid }?.id ?? tree.rootNodeId
        tree.appendChild(
            parentId: parentNodeId,
            kind: .question,
            atomUUID: question.uuid,
            label: question.title,
            nodeType: .branchQuestion,
            relationshipType: .childOf
        )
        structured.researchTree = tree
        _ = try await InquiryRepository.shared.saveSession(session, metadata: nil, structured: structured)
    }
}
