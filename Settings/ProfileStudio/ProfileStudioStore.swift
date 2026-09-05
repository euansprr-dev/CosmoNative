// CosmoOS/Settings/ProfileStudio/ProfileStudioStore.swift
// Draft state + persistence for the Profile Studio.
//
// Save contract: the studio never rebuilds ClientProfileMetadata from scratch.
// It encodes ONLY the fields it owns (ProfileStudioOverlay) and merges them
// over the existing metadata JSON via Atom.mergingMetadataKeys, so fields
// written elsewhere (performance stats, intelligence overrides, legacy keys)
// survive every save. Cleared fields encode explicit nulls so a deletion
// actually deletes.

import SwiftUI

@MainActor
@Observable
final class ProfileStudioStore {

    // MARK: - Draft fields (studio-owned)

    var name: String = "" { didSet { fieldChanged(oldValue != name) } }
    var handle: String = "" { didSet { fieldChanged(oldValue != handle) } }
    var primaryPlatform: SocialPlatform = .instagram { didSet { fieldChanged(oldValue != primaryPlatform) } }
    var documents: [ProfileDocument] = [] { didSet { fieldChanged(true) } }
    var targetAudience: String = "" { didSet { fieldChanged(oldValue != targetAudience) } }
    var niche: String = "" { didSet { fieldChanged(oldValue != niche) } }
    var uniqueAngle: String = "" { didSet { fieldChanged(oldValue != uniqueAngle) } }
    var signaturePhrases: [String] = [] { didSet { fieldChanged(oldValue != signaturePhrases) } }
    var coreBeliefs: [String] = [] { didSet { fieldChanged(oldValue != coreBeliefs) } }
    var notes: String = "" { didSet { fieldChanged(oldValue != notes) } }
    /// Pinned identity swatch (6-digit hex, no "#"); nil = automatic hash colour.
    var colorHex: String? = nil { didSet { fieldChanged(oldValue != colorHex) } }
    /// Free-text cadence ("3x/week") — `ClientCadence.parse` turns it into a quota.
    var postingFrequency: String = "" { didSet { fieldChanged(oldValue != postingFrequency) } }

    // MARK: - Read-only state

    private(set) var atom: Atom?
    /// Settable so the inline IntelligenceModelView can edit overrides;
    /// persist via `persistIntelligenceEdits()`.
    var intelligenceModel: ClientIntelligenceModel?
    private(set) var isLoading = false
    private(set) var saveState: SaveState = .idle
    private(set) var isGenerating = false
    var generationError: String?
    private(set) var isSuggestingContext = false
    /// Context fields drafted by the background extraction, not yet touched by
    /// the user. UI marks these "suggested — tap to edit".
    private(set) var suggestedFields: Set<SuggestedField> = []

    enum SaveState: Equatable { case idle, saving, saved }
    enum SuggestedField: String { case targetAudience, niche, uniqueAngle, signaturePhrases }

    var isNewProfile: Bool { createdInSession }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// A draft is empty when nothing meaningful was ever entered — safe to discard.
    var isEmptyDraft: Bool {
        trimmedName.isEmpty && documents.isEmpty
            && targetAudience.isEmpty && niche.isEmpty && uniqueAngle.isEmpty
            && signaturePhrases.isEmpty && coreBeliefs.isEmpty && notes.isEmpty
    }

    // MARK: - Private

    private var createdInSession = false
    private var isHydrating = false
    private var saveTask: Task<Void, Never>?
    private var savedPulseTask: Task<Void, Never>?
    private let onProfileListChanged: () -> Void
    /// Fired exactly once, when a brand-new draft first materializes as an atom.
    var onProfileCreated: ((Atom) -> Void)?

    init(onProfileListChanged: @escaping () -> Void = {}) {
        self.onProfileListChanged = onProfileListChanged
    }

    // MARK: - Load

    func load(atomUUID: String?) async {
        isLoading = true
        defer { isLoading = false }

        guard let atomUUID else {
            hydrate(from: nil)
            return
        }
        let fetched = try? await AtomRepository.shared.fetch(uuid: atomUUID)
        hydrate(from: fetched)
    }

    private func hydrate(from atom: Atom?) {
        isHydrating = true
        defer { isHydrating = false }

        self.atom = atom
        createdInSession = (atom == nil)
        guard let atom else { return }

        name = atom.title ?? ""
        guard let meta = atom.metadataValue(as: ClientProfileMetadata.self) else { return }

        handle = meta.handle ?? ""
        primaryPlatform = meta.primaryPlatform ?? meta.platforms.first ?? .instagram
        documents = meta.documents ?? Self.legacyDocuments(from: meta)
        targetAudience = meta.targetAudience ?? ""
        niche = meta.niche ?? ""
        uniqueAngle = meta.uniqueAngle ?? ""
        signaturePhrases = meta.signaturePhrases ?? []
        coreBeliefs = meta.coreBeliefs ?? []
        notes = meta.notes ?? ""
        colorHex = ClientColorResolver.normalizedHex(meta.colorHex)
        postingFrequency = meta.postingFrequency ?? ""
        intelligenceModel = meta.intelligenceModel
    }

    /// Reconstruct a document library from pre-documents profiles (same
    /// migration the old wizard performed, so those profiles open intact).
    private static func legacyDocuments(from meta: ClientProfileMetadata) -> [ProfileDocument] {
        var docs: [ProfileDocument] = []
        if let story = meta.brandStory, !story.isEmpty {
            docs.append(ProfileDocument(category: .story, title: "Brand Story", content: story))
        }
        if let voice = meta.voiceNotes, !voice.isEmpty {
            docs.append(ProfileDocument(category: .voiceGuide, title: "Voice Notes", content: voice))
        }
        for post in meta.topPerformingPosts ?? [] {
            let content = post.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let category: ProfileDocumentCategory = post.platform == "thread" ? .thread : .reel
            docs.append(ProfileDocument(
                category: category,
                title: "\(category == .reel ? "Reel" : "Thread")",
                content: post.transcript,
                platform: post.platform,
                likes: post.likes,
                shares: post.shares
            ))
        }
        return docs
    }

    // MARK: - Document mutations

    func addDocument(_ doc: ProfileDocument) {
        documents.append(doc)
    }

    func replaceDocument(id: UUID, with doc: ProfileDocument) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index] = doc
    }

    func updateDocumentContent(id: UUID, content: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].content = content
        if documents[index].title.isEmpty || documents[index].title == "Transcribing..." {
            documents[index].title = String(content.prefix(60))
        }
    }

    func removeDocument(id: UUID) {
        documents.removeAll { $0.id == id }
    }

    func documentCount(in category: ProfileDocumentCategory) -> Int {
        documents.count { $0.category == category }
    }

    // MARK: - Context edits

    /// The user touched a suggested field — it's theirs now.
    func clearSuggestion(_ field: SuggestedField) {
        suggestedFields.remove(field)
    }

    // MARK: - Autosave

    private func fieldChanged(_ actuallyChanged: Bool) {
        guard actuallyChanged, !isHydrating else { return }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    /// Persist the draft. Creates the atom lazily on first meaningful input;
    /// merges studio-owned keys over existing metadata (never replaces).
    func saveNow() async {
        saveTask?.cancel()
        guard !isEmptyDraft else { return }

        saveState = .saving
        let overlay = buildOverlay()

        do {
            if var existing = atom {
                existing.title = trimmedName.isEmpty ? existing.title : trimmedName
                existing = existing.mergingMetadataKeys(overlay)
                atom = try await AtomRepository.shared.update(existing)
            } else {
                var created = Atom.new(type: .clientProfile, title: trimmedName, body: nil)
                created = created.mergingMetadataKeys(overlay)
                let saved = try await AtomRepository.shared.create(created)
                atom = saved
                onProfileCreated?(saved)
            }
            // The colour map is app-wide; re-read it before the list repaints.
            await ClientColorResolver.shared.refresh()
            onProfileListChanged()
            pulseSaved()
            suggestContextIfNeeded()
        } catch {
            saveState = .idle
            print("ProfileStudioStore: save failed: \(error.localizedDescription)")
        }
    }

    private func pulseSaved() {
        saveState = .saved
        savedPulseTask?.cancel()
        savedPulseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveState = .idle
        }
    }

    /// Choke point on exit: an untouched new draft leaves nothing behind.
    /// Returns true when there is a profile to show in the list.
    @discardableResult
    func finalizeOnExit() async -> Bool {
        saveTask?.cancel()
        if isEmptyDraft {
            if createdInSession, let atom {
                try? await AtomRepository.shared.delete(uuid: atom.uuid)
                self.atom = nil
                onProfileListChanged()
            }
            return atom != nil
        }
        await saveNow()
        return atom != nil
    }

    private func buildOverlay() -> ProfileStudioOverlay {
        // Legacy-compat projections, same as the old wizard wrote them, so
        // downstream engines that still read brandStory/voiceNotes/topPosts
        // keep working.
        let brandStory = documents.filter { $0.category == .story }
            .map(\.content).joined(separator: "\n\n")
        let voiceNotes = documents.filter { $0.category == .voiceGuide }
            .map(\.content).joined(separator: "\n\n")
        let topPosts: [TopPost] = documents
            .filter { $0.category.isHighPerformer && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { TopPost(transcript: $0.content, platform: $0.platform ?? $0.category.platformTag ?? "") }

        return ProfileStudioOverlay(
            clientId: atom?.metadataValue(as: ClientProfileMetadata.self)?.clientId ?? UUID().uuidString,
            clientName: trimmedName,
            activeStatus: true,
            handle: handle.trimmingCharacters(in: .whitespaces),
            platforms: [primaryPlatform],
            primaryPlatform: primaryPlatform,
            documents: documents,
            targetAudience: targetAudience,
            niche: niche,
            uniqueAngle: uniqueAngle,
            signaturePhrases: signaturePhrases,
            coreBeliefs: coreBeliefs,
            notes: notes,
            brandStory: brandStory,
            voiceNotes: voiceNotes,
            topPerformingPosts: topPosts,
            colorHex: colorHex ?? "",
            postingFrequency: postingFrequency.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Intelligence (optional, background)

    var canGenerate: Bool { !documents.isEmpty && !isGenerating }

    func generateIntelligence() {
        guard canGenerate else { return }
        isGenerating = true
        generationError = nil

        Task { [weak self] in
            guard let self else { return }
            await self.saveNow()
            guard let atom = self.atom else {
                self.isGenerating = false
                return
            }
            do {
                let model = try await ClientIntelligenceEngine.shared.generateModel(profile: atom)
                self.intelligenceModel = model
                await self.persistIntelligenceModel(model)
            } catch {
                self.generationError = error.localizedDescription
            }
            self.isGenerating = false
        }
    }

    private func persistIntelligenceModel(_ model: ClientIntelligenceModel) async {
        guard var existing = atom else { return }
        existing = existing.mergingMetadataKeys(["intelligenceModel": model])
        atom = try? await AtomRepository.shared.update(existing)
        onProfileListChanged()
    }

    /// Persist user overrides edited through the inline model view.
    func persistIntelligenceEdits() {
        guard let model = intelligenceModel else { return }
        Task { await persistIntelligenceModel(model) }
    }

    // MARK: - Light context extraction (suggested fields)

    /// One cheap background call that drafts audience/niche/angle/phrases from
    /// the documents when the user hasn't filled them in. State-based trigger:
    /// documents exist AND both audience and niche are empty.
    func suggestContextIfNeeded() {
        guard !isSuggestingContext,
              !documents.isEmpty,
              targetAudience.isEmpty, niche.isEmpty else { return }
        isSuggestingContext = true

        let corpus = documents
            .map { "## \($0.category.displayName): \($0.title)\n\($0.content.prefix(4000))" }
            .joined(separator: "\n\n")

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSuggestingContext = false }
            do {
                let response = try await ResearchService.shared.analyze(
                    prompt: """
                    Read this creator's brand documents and content, then return a JSON object:
                    {"targetAudience": "<one sentence describing who this content serves>",
                     "niche": "<3-6 word niche label>",
                     "uniqueAngle": "<one sentence on what makes this voice different>",
                     "signaturePhrases": ["<up to 5 recurring phrases, verbatim from the content>"]}
                    Return ONLY the JSON object. Base every value on evidence in the documents — no generic filler.

                    \(corpus)
                    """,
                    systemPrompt: "You extract precise brand context from creator documents. Be concrete and specific; never invent facts absent from the text."
                )
                self.applyContextSuggestions(response)
            } catch {
                // Suggestions are best-effort; silence is fine.
            }
        }
    }

    private func applyContextSuggestions(_ response: String) {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if targetAudience.isEmpty, let value = json["targetAudience"] as? String, !value.isEmpty {
            targetAudience = value
            suggestedFields.insert(.targetAudience)
        }
        if niche.isEmpty, let value = json["niche"] as? String, !value.isEmpty {
            niche = value
            suggestedFields.insert(.niche)
        }
        if uniqueAngle.isEmpty, let value = json["uniqueAngle"] as? String, !value.isEmpty {
            uniqueAngle = value
            suggestedFields.insert(.uniqueAngle)
        }
        if signaturePhrases.isEmpty, let value = json["signaturePhrases"] as? [String], !value.isEmpty {
            signaturePhrases = Array(value.prefix(5))
            suggestedFields.insert(.signaturePhrases)
        }
    }
}

// MARK: - Overlay (studio-owned metadata keys)

/// The exact set of metadata keys the studio writes. Encoded with explicit
/// nulls for cleared optionals so deletions persist through the key merge.
struct ProfileStudioOverlay: Encodable {
    let clientId: String
    let clientName: String
    let activeStatus: Bool
    let handle: String
    let platforms: [SocialPlatform]
    let primaryPlatform: SocialPlatform
    let documents: [ProfileDocument]
    let targetAudience: String
    let niche: String
    let uniqueAngle: String
    let signaturePhrases: [String]
    let coreBeliefs: [String]
    let notes: String
    let brandStory: String
    let voiceNotes: String
    let topPerformingPosts: [TopPost]
    /// Empty = automatic (encodes null so a cleared swatch really clears).
    var colorHex: String = ""
    /// Empty = no cadence (encodes null so a cleared cadence really clears).
    var postingFrequency: String = ""

    enum CodingKeys: String, CodingKey {
        case clientId, clientName, activeStatus, handle, platforms, primaryPlatform
        case documents, targetAudience, niche, uniqueAngle, signaturePhrases
        case coreBeliefs, notes, brandStory, voiceNotes, topPerformingPosts
        case colorHex, postingFrequency
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientId, forKey: .clientId)
        try container.encode(clientName, forKey: .clientName)
        try container.encode(activeStatus, forKey: .activeStatus)
        try container.encode(platforms, forKey: .platforms)
        try container.encode(primaryPlatform, forKey: .primaryPlatform)
        try container.encode(documents, forKey: .documents)
        try encodeOrNull(handle, forKey: .handle, in: &container)
        try encodeOrNull(targetAudience, forKey: .targetAudience, in: &container)
        try encodeOrNull(niche, forKey: .niche, in: &container)
        try encodeOrNull(uniqueAngle, forKey: .uniqueAngle, in: &container)
        try encodeOrNull(notes, forKey: .notes, in: &container)
        try encodeOrNull(brandStory, forKey: .brandStory, in: &container)
        try encodeOrNull(voiceNotes, forKey: .voiceNotes, in: &container)
        try encodeOrNull(colorHex, forKey: .colorHex, in: &container)
        try encodeOrNull(postingFrequency, forKey: .postingFrequency, in: &container)
        try encodeListOrNull(signaturePhrases, forKey: .signaturePhrases, in: &container)
        try encodeListOrNull(coreBeliefs, forKey: .coreBeliefs, in: &container)
        if topPerformingPosts.isEmpty {
            try container.encodeNil(forKey: .topPerformingPosts)
        } else {
            try container.encode(topPerformingPosts, forKey: .topPerformingPosts)
        }
    }

    private func encodeOrNull(_ value: String, forKey key: CodingKeys, in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        if value.isEmpty {
            try container.encodeNil(forKey: key)
        } else {
            try container.encode(value, forKey: key)
        }
    }

    private func encodeListOrNull(_ value: [String], forKey key: CodingKeys, in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        if value.isEmpty {
            try container.encodeNil(forKey: key)
        } else {
            try container.encode(value, forKey: key)
        }
    }
}
