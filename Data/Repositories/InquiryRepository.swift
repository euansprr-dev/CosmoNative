// CosmoOS/Data/Repositories/InquiryRepository.swift
// Factory + load helpers for Inquiry Workspace primitives:
// Deep Dive, Inquiry Session, Question, Extract, Lexicon Entry.

import Foundation

enum InquiryRepositoryError: Error, LocalizedError {
    case thinkspaceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .thinkspaceNotFound(let uuid):
            return "Thinkspace not found: \(uuid)"
        }
    }
}

@MainActor
final class InquiryRepository {
    static let shared = InquiryRepository()

    private let atoms = AtomRepository.shared
    private init() {}

    // MARK: - Deep Dive

    /// Create a new Deep Dive parented to one or more Thinkspaces.
    /// Pass `parentThinkspaceUUIDs` (preferred — primary first) or leave empty for an unparented spark.
    @discardableResult
    func createDeepDive(
        title: String,
        about: String = "",
        parentThinkspaceUUIDs: [String] = [],
        aliases: [String] = []
    ) async throws -> Atom {
        let metadata = DeepDiveMetadata(
            aliases: aliases.isEmpty ? nil : aliases,
            parentThinkspaceUUIDs: parentThinkspaceUUIDs.isEmpty ? nil : parentThinkspaceUUIDs,
            primaryThinkspaceUUID: parentThinkspaceUUIDs.first,
            maturity: .spark,
            lastInquiryAt: nil
        )
        let structured = DeepDiveStructured()

        let metadataJSON = try jsonString(metadata)
        let structuredJSON = try jsonString(structured)

        var links: [AtomLink] = []
        for ts in parentThinkspaceUUIDs {
            links.append(AtomLink(type: AtomLinkType.deepDiveParent.rawValue, uuid: ts, entityType: AtomType.thinkspace.rawValue))
        }

        return try await atoms.create(
            type: .deepDive,
            title: title,
            body: about.isEmpty ? nil : about,
            structured: structuredJSON,
            metadata: metadataJSON,
            links: links.isEmpty ? nil : links
        )
    }

    /// Update Deep Dive metadata + structured fields atomically.
    @discardableResult
    func saveDeepDive(_ atom: Atom, metadata: DeepDiveMetadata?, structured: DeepDiveStructured?) async throws -> Atom {
        var copy = atom
        if let metadata { copy = copy.withMetadata(metadata) }
        if let structured { copy = copy.withStructured(structured) }
        return try await atoms.update(copy)
    }

    /// All Deep Dives. Sorted by lastInquiryAt (recent first), then updated.
    func fetchAllDeepDives() async throws -> [Atom] {
        let liveThinkspaceUUIDs = Set((try await atoms.fetchAll(type: .thinkspace)).map(\.uuid))
        let list = try await atoms.fetchAll(type: .deepDive)
            .filter { deepDiveIsVisible($0, liveThinkspaceUUIDs: liveThinkspaceUUIDs) }
        return list.sorted { lhs, rhs in
            let lhsTime = lhs.deepDiveMetadata?.lastInquiryAt ?? lhs.updatedAt
            let rhsTime = rhs.deepDiveMetadata?.lastInquiryAt ?? rhs.updatedAt
            return lhsTime > rhsTime
        }
    }

    /// Deep Dives parented to a particular Thinkspace.
    func fetchDeepDives(in thinkspaceUUID: String) async throws -> [Atom] {
        let all = try await fetchAllDeepDives()
        return all.filter { atom in
            let metadata = atom.deepDiveMetadata
            return metadata?.primaryThinkspaceUUID == thinkspaceUUID
                || metadata?.parentThinkspaceUUIDs?.contains(thinkspaceUUID) == true
        }
    }

    /// Resolve the one-to-one DeepDiveProfile backing a Thinkspace.
    /// This preserves old Deep Dive atoms by selecting an existing parented Deep Dive
    /// before creating a new profile.
    @discardableResult
    func resolveDeepDiveProfile(forThinkspace thinkspaceUUID: String, title: String) async throws -> Atom {
        guard var thinkspaceAtom = try await atoms.fetch(uuid: thinkspaceUUID) else {
            throw InquiryRepositoryError.thinkspaceNotFound(thinkspaceUUID)
        }

        var thinkspaceMetadata = thinkspaceAtom.metadataValue(as: ThinkspaceMetadata.self)
            ?? ThinkspaceMetadata(name: title)

        if let profileUUID = thinkspaceMetadata.deepDiveProfileUUID,
           var existing = try await atoms.fetch(uuid: profileUUID),
           existing.type == .deepDive,
           !existing.isDeleted {
            existing = try await ensureProfile(existing, isPrimaryFor: thinkspaceUUID)
            return existing
        }

        let candidates = try await fetchDeepDives(in: thinkspaceUUID)
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                let lhsTime = lhs.deepDiveMetadata?.lastInquiryAt ?? lhs.updatedAt
                let rhsTime = rhs.deepDiveMetadata?.lastInquiryAt ?? rhs.updatedAt
                return lhsTime > rhsTime
            }

        let profile: Atom
        if let selected = candidates.first {
            profile = try await ensureProfile(selected, isPrimaryFor: thinkspaceUUID, relatedProfiles: Array(candidates.dropFirst()))
        } else {
            let created = try await createDeepDive(
                title: title,
                about: "",
                parentThinkspaceUUIDs: [thinkspaceUUID],
                aliases: []
            )
            profile = try await ensureProfile(created, isPrimaryFor: thinkspaceUUID)
        }

        thinkspaceMetadata.name = title
        thinkspaceMetadata.deepDiveProfileUUID = profile.uuid
        thinkspaceAtom = thinkspaceAtom.withMetadata(thinkspaceMetadata)
        if thinkspaceAtom.title == nil || thinkspaceAtom.title?.isEmpty == true {
            thinkspaceAtom.title = title
        }
        _ = try await atoms.update(thinkspaceAtom)
        return profile
    }

    private func ensureProfile(_ atom: Atom, isPrimaryFor thinkspaceUUID: String, relatedProfiles: [Atom] = []) async throws -> Atom {
        var copy = atom
        var metadata = copy.deepDiveMetadata ?? DeepDiveMetadata()
        metadata.primaryThinkspaceUUID = thinkspaceUUID
        var parents = metadata.parentThinkspaceUUIDs ?? []
        if !parents.contains(thinkspaceUUID) {
            parents.insert(thinkspaceUUID, at: 0)
        } else if parents.first != thinkspaceUUID {
            parents.removeAll { $0 == thinkspaceUUID }
            parents.insert(thinkspaceUUID, at: 0)
        }
        metadata.parentThinkspaceUUIDs = parents

        let related = relatedProfiles.map(\.uuid)
        if !related.isEmpty {
            metadata.relatedDeepDiveUUIDs = Array(Set((metadata.relatedDeepDiveUUIDs ?? []) + related))
        }

        copy = copy.withMetadata(metadata)
        let hasParentLink = copy.linksOfType(.deepDiveParent).contains { $0.uuid == thinkspaceUUID }
        if !hasParentLink {
            copy = copy.appendingLink(
                AtomLink(type: AtomLinkType.deepDiveParent.rawValue, uuid: thinkspaceUUID, entityType: AtomType.thinkspace.rawValue)
            )
        }
        return try await atoms.update(copy)
    }

    /// Hide or detach DeepDiveProfiles whose Thinkspace home was deleted.
    /// Research child atoms are preserved; only the profile atom/link is updated so
    /// deleted Thinkspaces do not keep appearing as selectable Deep Dives.
    func handleThinkspaceDeleted(_ thinkspaceUUID: String) async throws {
        let deepDives = try await atoms.fetchAll(type: .deepDive)

        for deepDive in deepDives {
            guard var metadata = deepDive.deepDiveMetadata else { continue }
            let parentUUIDs = metadata.parentThinkspaceUUIDs ?? []
            let isPrimary = metadata.primaryThinkspaceUUID == thinkspaceUUID
            let isParented = parentUUIDs.contains(thinkspaceUUID)
            let hasParentLink = deepDive.linksOfType(.deepDiveParent).contains { $0.uuid == thinkspaceUUID }
            guard isPrimary || isParented || hasParentLink else { continue }

            var copy = deepDive.removingLink(ofType: .deepDiveParent, toUUID: thinkspaceUUID)
            let remainingParents = parentUUIDs.filter { $0 != thinkspaceUUID }
            metadata.parentThinkspaceUUIDs = remainingParents.isEmpty ? nil : remainingParents

            if isPrimary {
                metadata.primaryThinkspaceUUID = remainingParents.first
            }

            copy = copy.withMetadata(metadata)
            copy.updatedAt = ISO8601.string(from: Date())

            if metadata.primaryThinkspaceUUID == nil && remainingParents.isEmpty {
                copy.isDeleted = true
            }

            _ = try await atoms.update(copy)
        }
    }

    private func deepDiveIsVisible(_ deepDive: Atom, liveThinkspaceUUIDs: Set<String>) -> Bool {
        let metadata = deepDive.deepDiveMetadata
        let parentUUIDs = metadata?.parentThinkspaceUUIDs ?? []

        if let primary = metadata?.primaryThinkspaceUUID {
            return liveThinkspaceUUIDs.contains(primary)
                || parentUUIDs.contains { liveThinkspaceUUIDs.contains($0) }
        }

        if !parentUUIDs.isEmpty {
            return parentUUIDs.contains { liveThinkspaceUUIDs.contains($0) }
        }

        return true
    }

    // MARK: - Linked atoms (Topic Inbox / Questions / Sources / Lexicon / Connections / Sessions)

    /// All Question atoms whose metadata.parentDeepDiveUUID matches.
    func fetchQuestions(forDeepDive uuid: String) async throws -> [Atom] {
        let list = try await atoms.fetchAll(type: .question)
        return list.filter { $0.questionMetadata?.parentDeepDiveUUID == uuid }
    }

    /// Lexicon entries scoped to a Deep Dive.
    func fetchLexicon(forDeepDive uuid: String) async throws -> [Atom] {
        let list = try await atoms.fetchAll(type: .lexiconEntry)
        return list.filter { $0.lexiconMetadata?.parentDeepDiveUUID == uuid }
    }

    /// Inquiry Sessions scoped to a Deep Dive.
    func fetchSessions(forDeepDive uuid: String) async throws -> [Atom] {
        let list = try await atoms.fetchAll(type: .inquirySession)
        return list.filter { $0.inquirySessionMetadata?.parentDeepDiveUUID == uuid }
            .sorted { ($0.inquirySessionMetadata?.lastActiveAt ?? "") > ($1.inquirySessionMetadata?.lastActiveAt ?? "") }
    }

    /// Extracts captured during sessions of a Deep Dive.
    func fetchExtracts(forDeepDive uuid: String) async throws -> [Atom] {
        let list = try await atoms.fetchAll(type: .extract)
        return list.filter { $0.extractMetadata?.parentDeepDiveUUID == uuid }
    }

    /// Sources linked to the Deep Dive (research/note/swipe atoms surfaced by deepDiveSource links).
    func fetchSources(forDeepDive deepDive: Atom) async throws -> [Atom] {
        let sourceUUIDs = deepDive.linksOfType(.deepDiveSource).compactMap { $0.uuid }
        guard !sourceUUIDs.isEmpty else { return [] }
        var atomsLoaded: [Atom] = []
        for uuid in sourceUUIDs {
            if let atom = try await atoms.fetch(uuid: uuid) {
                atomsLoaded.append(atom)
            }
        }
        return atomsLoaded
    }

    /// Create or find a durable research atom for a URL. Source tabs are views; this atom is the source object.
    @discardableResult
    func createOrFindURLSource(urlString: String, title: String, sourceType: String = "webpage") async throws -> Atom {
        let canonical = canonicalURL(urlString)
        if let existing = try await fetchSource(canonicalURL: canonical) {
            var copy = existing
            if (copy.title ?? "").isEmpty {
                copy.title = title
            }
            var meta = copy.researchMetadata ?? ResearchMetadata()
            meta.url = canonical
            meta.researchType = meta.researchType ?? sourceType
            meta.processingStatus = InquirySourceStatus.viewed.rawValue
            meta.tags = Array(Set((meta.tags ?? []) + ["inquiry-source"]))
            copy.metadata = try jsonString(meta)
            return try await atoms.update(copy)
        }

        var metadata = ResearchMetadata()
        metadata.url = canonical
        metadata.researchType = sourceType
        metadata.processingStatus = InquirySourceStatus.viewed.rawValue
        metadata.tags = ["inquiry-source"]

        return try await atoms.create(
            type: .research,
            title: title,
            body: nil,
            structured: nil,
            metadata: try jsonString(metadata),
            links: nil
        )
    }

    func fetchSource(canonicalURL: String) async throws -> Atom? {
        let all = try await atoms.fetchAll(type: .research)
        return all.first { atom in
            guard let url = atom.researchMetadata?.url else { return false }
            return self.canonicalURL(url) == canonicalURL
        }
    }

    func canonicalURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme) else { return withScheme }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" { components.path = "" }
        return components.string ?? withScheme
    }

    /// Connections crystallized within this Deep Dive.
    func fetchConnections(forDeepDive deepDive: Atom) async throws -> [Atom] {
        let uuids = deepDive.linksOfType(.deepDiveConnection).compactMap { $0.uuid }
        guard !uuids.isEmpty else { return [] }
        var atomsLoaded: [Atom] = []
        for uuid in uuids {
            if let atom = try await atoms.fetch(uuid: uuid) {
                atomsLoaded.append(atom)
            }
        }
        return atomsLoaded
    }

    // MARK: - Inquiry Session

    /// Start (or resume) an Inquiry Session anchored to a Deep Dive.
    /// If `mainQuestionTitle` is provided, also creates a root Question atom and seeds the research tree.
    @discardableResult
    func startSession(
        deepDive: Atom,
        title: String? = nil,
        mainQuestionTitle: String? = nil,
        existingRootQuestion: Atom? = nil,
        anchorObjectUUID: String? = nil,
        anchorObjectType: String? = nil
    ) async throws -> (session: Atom, rootQuestion: Atom?) {
        // 1. Create root question (optional)
        var rootQuestionAtom: Atom? = existingRootQuestion
        if rootQuestionAtom == nil, let qTitle = mainQuestionTitle, !qTitle.isEmpty {
            rootQuestionAtom = try await createQuestion(
                title: qTitle,
                parentDeepDiveUUID: deepDive.uuid,
                originSessionUUID: nil,
                parentQuestionUUID: nil,
                originExtractUUID: nil
            )
        }

        // 2. Build session metadata + structured (with research tree seeded)
        let sessionTitle = title ?? rootQuestionAtom?.title ?? mainQuestionTitle ?? "\(deepDive.title ?? "Inquiry") · \(shortDateLabel())"
        let metadata = InquirySessionMetadata(
            parentDeepDiveUUID: deepDive.uuid,
            parentObjectUUID: anchorObjectUUID,
            parentObjectType: anchorObjectType,
            mainQuestionUUID: rootQuestionAtom?.uuid,
            status: .active,
            lastActiveAt: ISO8601.string(from: Date()),
            layoutMode: .research
        )
        var tree = ResearchTreeDocument.bootstrap(rootQuestionAtomUUID: rootQuestionAtom?.uuid)
        if let rootTitle = rootQuestionAtom?.title ?? mainQuestionTitle,
           var root = tree.nodes[tree.rootNodeId] {
            root.meta.label = rootTitle
            tree.nodes[root.id] = root
        }
        let structured = InquirySessionStructured(researchTree: tree)

        // 3. Build links
        var links: [AtomLink] = [
            AtomLink(type: AtomLinkType.inquiryParentDeepDive.rawValue, uuid: deepDive.uuid, entityType: AtomType.deepDive.rawValue)
        ]
        if let q = rootQuestionAtom {
            links.append(AtomLink(type: AtomLinkType.inquiryRootQuestion.rawValue, uuid: q.uuid, entityType: AtomType.question.rawValue))
        }
        if let anchorUUID = anchorObjectUUID {
            links.append(AtomLink(type: AtomLinkType.inquiryParentObject.rawValue, uuid: anchorUUID, entityType: anchorObjectType))
        }

        let session = try await atoms.create(
            type: .inquirySession,
            title: sessionTitle,
            body: nil,
            structured: try jsonString(structured),
            metadata: try jsonString(metadata),
            links: links.isEmpty ? nil : links
        )

        // 4. Touch Deep Dive: link it to the new session, update lastInquiryAt
        var deepDiveCopy = deepDive
        var ddMeta = deepDiveCopy.deepDiveMetadata ?? DeepDiveMetadata()
        ddMeta.lastInquiryAt = ISO8601.string(from: Date())
        if (ddMeta.maturity ?? .spark) == .spark {
            ddMeta.maturity = .exploring
        }
        deepDiveCopy = deepDiveCopy.withMetadata(ddMeta)
        deepDiveCopy = deepDiveCopy.appendingLink(
            AtomLink(type: AtomLinkType.deepDiveSession.rawValue, uuid: session.uuid, entityType: AtomType.inquirySession.rawValue)
        )
        if let q = rootQuestionAtom {
            deepDiveCopy = deepDiveCopy.appendingLink(
                AtomLink(type: AtomLinkType.deepDiveQuestion.rawValue, uuid: q.uuid, entityType: AtomType.question.rawValue)
            )
        }
        _ = try await atoms.update(deepDiveCopy)

        return (session, rootQuestionAtom)
    }

    /// Save the session's metadata/structured (called frequently — debounce externally).
    @discardableResult
    func saveSession(_ atom: Atom, metadata: InquirySessionMetadata?, structured: InquirySessionStructured?) async throws -> Atom {
        var copy = atom
        if let metadata { copy = copy.withMetadata(metadata) }
        if let structured { copy = copy.withStructured(structured) }
        return try await atoms.update(copy)
    }

    /// Mark a session paused.
    @discardableResult
    func pauseSession(_ atom: Atom) async throws -> Atom {
        guard var meta = atom.inquirySessionMetadata else { return atom }
        meta.status = .paused
        meta.lastActiveAt = ISO8601.string(from: Date())
        let copy = atom.withMetadata(meta)
        return try await atoms.update(copy)
    }

    /// Mark a session crystallized and persist crystallization output.
    @discardableResult
    func completeCrystallization(_ atom: Atom, output: CrystallizationOutput, summary: String) async throws -> Atom {
        guard var meta = atom.inquirySessionMetadata,
              var structured = atom.inquirySessionStructured else { return atom }
        meta.status = .crystallized
        meta.crystallizedAt = ISO8601.string(from: Date())
        structured.crystallizationResult = output
        var copy = atom.withMetadata(meta).withStructured(structured)
        copy.body = summary
        return try await atoms.update(copy)
    }

    // MARK: - Question

    @discardableResult
    func createQuestion(
        title: String,
        parentDeepDiveUUID: String?,
        originSessionUUID: String?,
        parentQuestionUUID: String?,
        originExtractUUID: String?,
        questionRole: InquiryNodeType? = nil,
        relationshipToParent: InquiryRelationshipType? = nil,
        placementOrigin: String? = nil,
        placementConfidence: InquiryPlacementConfidence? = nil,
        placementExplanation: String? = nil,
        sourceQuestionUUID: String? = nil,
        sourceExtractUUID: String? = nil
    ) async throws -> Atom {
        let metadata = QuestionMetadata(
            parentDeepDiveUUID: parentDeepDiveUUID,
            parentQuestionUUID: parentQuestionUUID,
            originSessionUUID: originSessionUUID,
            originExtractUUID: originExtractUUID,
            status: .open,
            questionRole: questionRole ?? (parentQuestionUUID == nil ? .rootQuestion : .branchQuestion),
            relationshipToParent: relationshipToParent ?? (parentQuestionUUID == nil ? .rootUnderTopic : .childOf),
            placementOrigin: placementOrigin,
            placementConfidence: placementConfidence,
            placementExplanation: placementExplanation,
            sourceQuestionUUID: sourceQuestionUUID,
            sourceExtractUUID: sourceExtractUUID ?? originExtractUUID
        )
        let structured = QuestionStructured()
        var links: [AtomLink] = []
        if let dd = parentDeepDiveUUID {
            links.append(AtomLink(type: AtomLinkType.questionParentDeepDive.rawValue, uuid: dd, entityType: AtomType.deepDive.rawValue))
        }
        if let parentQ = parentQuestionUUID {
            links.append(AtomLink(type: AtomLinkType.questionBranch.rawValue, uuid: parentQ, entityType: AtomType.question.rawValue))
        }
        return try await atoms.create(
            type: .question,
            title: title,
            body: nil,
            structured: try jsonString(structured),
            metadata: try jsonString(metadata),
            links: links.isEmpty ? nil : links
        )
    }

    // MARK: - Extract

    @discardableResult
    func createExtract(
        body: String,
        kind: ExtractKind,
        sourceUUID: String?,
        selectionRange: ExtractTextRange?,
        sessionUUID: String?,
        questionUUID: String?,
        deepDiveUUID: String?,
        branchNodeId: String?,
        sourceTabId: String?,
        userNote: String?,
        originType: String?,
        citation: String?
    ) async throws -> Atom {
        let metadata = ExtractMetadata(
            kind: kind,
            sourceUUID: sourceUUID,
            selectionRange: selectionRange,
            parentSessionUUID: sessionUUID,
            parentQuestionUUID: questionUUID,
            parentDeepDiveUUID: deepDiveUUID,
            parentBranchNodeId: branchNodeId,
            sourceTabId: sourceTabId,
            userNote: userNote,
            status: .committed,
            originType: originType,
            citation: citation
        )
        let structured = ExtractStructured()
        var links: [AtomLink] = []
        if let s = sourceUUID {
            links.append(AtomLink(type: AtomLinkType.extractFromSource.rawValue, uuid: s))
        }
        if let q = questionUUID {
            links.append(AtomLink(type: AtomLinkType.extractInQuestion.rawValue, uuid: q, entityType: AtomType.question.rawValue))
        }
        if let s = sessionUUID {
            links.append(AtomLink(type: AtomLinkType.extractInSession.rawValue, uuid: s, entityType: AtomType.inquirySession.rawValue))
        }
        let title = makeExtractTitle(from: body)
        return try await atoms.create(
            type: .extract,
            title: title,
            body: body,
            structured: try jsonString(structured),
            metadata: try jsonString(metadata),
            links: links.isEmpty ? nil : links
        )
    }

    // MARK: - Lexicon

    @discardableResult
    func createLexiconEntry(
        term: String,
        definition: String,
        parentDeepDiveUUID: String,
        maturity: LexiconMaturity = .entry
    ) async throws -> Atom {
        let metadata = LexiconMetadata(
            parentDeepDiveUUID: parentDeepDiveUUID,
            aliases: [],
            maturity: maturity,
            mentionCount: 1
        )
        let structured = LexiconStructured()
        let links = [AtomLink(type: AtomLinkType.lexiconParentDeepDive.rawValue, uuid: parentDeepDiveUUID, entityType: AtomType.deepDive.rawValue)]
        return try await atoms.create(
            type: .lexiconEntry,
            title: term,
            body: definition,
            structured: try jsonString(structured),
            metadata: try jsonString(metadata),
            links: links
        )
    }

    // MARK: - Helpers

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func shortDateLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }

    private func makeExtractTitle(from body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 { return trimmed }
        let prefix = trimmed.prefix(60)
        return String(prefix) + "…"
    }
}

// MARK: - Atom link helpers

extension Atom {
    /// All AtomLinks whose `type` rawValue matches `linkType`.
    func linksOfType(_ linkType: AtomLinkType) -> [AtomLink] {
        let raw = linkType.rawValue
        guard let json = links,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([AtomLink].self, from: data) else {
            return []
        }
        return arr.filter { $0.type == raw }
    }

    /// Append an AtomLink (no dedup; callers should avoid duplicates).
    func appendingLink(_ link: AtomLink) -> Atom {
        var existing: [AtomLink] = []
        if let json = links, let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([AtomLink].self, from: data) {
            existing = decoded
        }
        // Single-value links replace any existing of the same type
        if let kind = AtomLinkType(rawValue: link.type), kind.isSingleValue {
            existing.removeAll { $0.type == link.type }
        }
        existing.append(link)
        var copy = self
        copy.links = (try? JSONEncoder().encode(existing)).flatMap { String(data: $0, encoding: .utf8) }
        return copy
    }
}
