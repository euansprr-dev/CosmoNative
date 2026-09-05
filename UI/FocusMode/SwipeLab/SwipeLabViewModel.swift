import Foundation
import SwiftUI
import AVKit

@MainActor
@Observable
final class SwipeLabViewModel {
    let sessionID: String
    var state: SwipeLabSessionState
    private(set) var sources: [SwipeLabSource] = []
    private(set) var clients: [Atom] = []
    private(set) var isLoading = true
    private(set) var isRunning = false
    private(set) var coverage = SwipeLabCoverage()
    private(set) var activity = "Opening study"
    private(set) var error: String?
    private(set) var hasUpdates = false
    private(set) var promptModules: [SwipeLabPromptModule] = []
    private(set) var readerModel: SwipeStudyModel?
    var sourceQuery = ""
    var showSources = true
    var showConversation = true
    var showSettings = false
    var showComparisonPicker = false
    var showExperimentEditor = false
    var editingFinding: SwipeLabFinding?
    var selectedFindingID: String?
    var activePracticeID: String?
    var selectedAnchorID: String?
    var outcomeContent: [Atom] = []
    var outcomeSnapshots: [String: [ContentPerfSnapshot]] = [:]
    var experimentFinding: SwipeLabFinding?
    var experimentTitle = ""
    var experimentHypothesis = ""
    var experimentChange = ""
    var experimentCounterPrediction = ""
    var experimentDays = 7
    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?
    @ObservationIgnored private var previousPositions: [SwipeLabPosition] = []
    @ObservationIgnored private var latestSources: [SwipeLabSource] = []
    @ObservationIgnored private var validSession: Bool

    init(atom: Atom) {
        sessionID = atom.uuid
        validSession = atom.swipeLabState?.schemaVersion == 1
        state = atom.swipeLabState ?? .init(scope: .init(kind: .library, title: "Swipe Lab"))
        if !validSession { error = SwipeLabError.damagedSession.localizedDescription }
    }

    var selectedSource: SwipeLabSource? { sources.first { $0.id == state.position?.sourceID } }
    var selectedUnit: SwipeLabUnit? { selectedSource?.units.first { $0.id == selectedAnchorID } }
    var comparisonSource: SwipeLabSource? { sources.first { $0.id == state.comparisonSourceID } }
    var visibleSources: [SwipeLabSource] {
        let query = sourceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? sources : sources.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.creator.localizedCaseInsensitiveContains(query) }
    }
    var missingSources: [SwipeLabSourceManifest] {
        let present = Set(sources.map(\.id))
        return state.snapshots.last?.sources.filter { !present.contains($0.sourceID) } ?? []
    }
    var visibleFindings: [SwipeLabFinding] { state.findings.filter { $0.status != .archived && $0.status != .rejected } }
    var clientName: String {
        guard let id = state.targetClientID else { return "Any client" }
        return clients.first { $0.uuid == id }?.title ?? "Client unavailable"
    }
    var activePractice: SwipeLabPractice? { state.practices.first { $0.id == activePracticeID } }
    var canGoBack: Bool { !previousPositions.isEmpty }
    var selectedJob: String { selectedUnit.map { state.observedJobs[$0.id] ?? $0.job.lowercased() } ?? "opening" }
    var matchingComparisonUnits: [SwipeLabUnit] {
        let matches = comparisonSource?.units.filter { (state.observedJobs[$0.id] ?? $0.job.lowercased()) == selectedJob } ?? []
        return matches
    }
    var currentSnapshotLabel: String {
        guard let snapshot = state.snapshots.last else { return "No sources yet" }
        return "\(snapshot.sources.count) posts · \(snapshot.capturedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    func start() async {
        guard validSession else { isLoading = false; return }
        do {
            clients = try await AtomRepository.shared.fetchAll(type: .clientProfile)
            let primary = try await SwipeLabCorpus.resolve(state.scope)
            let comparison = try await state.comparisonScope.mapAsync { try await SwipeLabCorpus.resolve($0, comparison: true) } ?? []
            latestSources = combine(primary, comparison)
            if let frozen = state.snapshots.last {
                let atoms = try await AtomRepository.shared.fetchBatch(uuids: frozen.sources.map(\.sourceID))
                let perf = await ContentPerfStore.latestByContentPlatform()
                let built = await Task.detached(priority: .userInitiated) {
                    SwipeLabCorpus.build(atoms: atoms, scope: .selection(atoms.map(\.uuid)), performance: perf)
                }.value
                let byID = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0) })
                sources = frozen.sources.compactMap { manifest in
                    guard var source = byID[manifest.sourceID] else { return nil }
                    source.isComparison = manifest.isComparison
                    return source
                }
                hasUpdates = SwipeLabSnapshot(sources: latestSources.map(\.manifest)).fingerprint != frozen.fingerprint
            } else {
                sources = latestSources
                state.snapshots.append(.init(sources: sources.map(\.manifest)))
            }
            let selected = state.position?.sourceID ?? sources.first?.id
            if let selected { selectSource(selected, remember: false) }
            coverage = state.turns.last(where: { $0.role == .assistant })?.coverage ?? .init(total: sources.count, readable: sources.filter(\.isReadable).count)
            activePracticeID = state.practices.last(where: { $0.completedAt == nil })?.id
            isLoading = false
            activity = "Ready to study"
            await persist()
        } catch { fail(error); isLoading = false }
    }

    func stop() {
        capturePosition()
        readerModel?.stop()
        readerModel = nil
        runningTask?.cancel()
        saveTask?.cancel()
        freshnessTask?.cancel()
        guard validSession else { return }
        let snapshot = state
        let id = sessionID
        Task { try? await SwipeLabStore.shared.save(sessionID: id, state: snapshot) }
    }

    func scheduleSave() {
        guard validSession else { return }
        state.updatedAt = Date()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)); await self?.persist() }
            catch { }
        }
    }

    func scheduleFreshnessCheck() {
        guard validSession, !isLoading, !isRunning else { return }
        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(800))
                guard let self, let snapshot = self.state.snapshots.last else { return }
                let primary = try await SwipeLabCorpus.resolve(self.state.scope)
                let comparison = try await self.state.comparisonScope.mapAsync { try await SwipeLabCorpus.resolve($0, comparison: true) } ?? []
                try Task.checkCancellation()
                self.latestSources = self.combine(primary, comparison)
                self.hasUpdates = SwipeLabSnapshot(sources: self.latestSources.map(\.manifest)).fingerprint != snapshot.fingerprint
            } catch { /* Refresh checks never replace a readable saved study. */ }
        }
    }

    func persist() async {
        guard validSession else { return }
        state.updatedAt = Date()
        do { _ = try await SwipeLabStore.shared.save(sessionID: sessionID, state: state) }
        catch { fail(error) }
    }

    func selectSource(_ id: String, remember: Bool = true) {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        if state.position?.sourceID != id {
            capturePosition()
            if remember, let position = state.position { previousPositions.append(position) }
            readerModel?.stop()
            readerModel = nil
        }
        let position = state.positions[id] ?? SwipeLabPosition(sourceID: id, anchorID: source.units.first?.id)
        state.position = position
        selectedAnchorID = position.anchorID ?? source.units.first?.id
        if readerModel == nil && source.atom.isSwipeFileAtom {
            let model = SwipeStudyModel(atom: source.atom, onClose: {})
            model.contextPublishingEnabled = false
            model.start()
            model.currentTimestamp = position.timestamp
            readerModel = model
        }
        if state.comparisonSourceID == nil || state.comparisonSourceID == id {
            state.comparisonSourceID = sources.filter { $0.id != id && $0.duplicateOf == nil }
                .max { SwipeLabStatistics.candidateScore($0, relativeTo: source) < SwipeLabStatistics.candidateScore($1, relativeTo: source) }?.id
        }
        scheduleSave()
    }

    func selectUnit(_ unit: SwipeLabUnit) {
        if let current = state.position, current.anchorID != unit.id { previousPositions.append(current) }
        selectedAnchorID = unit.id
        state.position = .init(sourceID: unit.anchor.sourceID, anchorID: unit.id, timestamp: unit.anchor.startSeconds ?? readerModel?.currentTimestamp ?? 0)
        if let slide = unit.anchor.slideNumber { readerModel?.carouselCurrentIndex = max(0, slide - 1) }
        if unit.anchor.kind == .artifact { readerModel?.focusedArtifactUnitID = unit.anchor.unitID }
        if let time = unit.anchor.startSeconds {
            readerModel?.currentTimestamp = time
            readerModel?.igPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        }
        state.positions[unit.anchor.sourceID] = state.position
        scheduleSave()
    }

    func open(_ anchor: SwipeLabAnchor) {
        guard let source = sources.first(where: { $0.id == anchor.sourceID }), source.contentHash == anchor.sourceHash,
              let unit = source.units.first(where: { $0.id == anchor.id }) else { fail(SwipeLabError.sourceChanged); return }
        selectSource(source.id)
        selectUnit(unit)
        state.mode = .study
    }

    func step(_ offset: Int) {
        guard let id = selectedSource?.id, let index = sources.firstIndex(where: { $0.id == id }), sources.indices.contains(index + offset) else { return }
        selectSource(sources[index + offset].id)
    }

    func backToPassage() {
        guard let previous = previousPositions.popLast() else { return }
        state.positions[previous.sourceID] = previous
        selectSource(previous.sourceID, remember: false)
        selectedAnchorID = previous.anchorID
    }

    func capturePosition() {
        guard var position = state.position else { return }
        position.timestamp = readerModel?.currentTimestamp ?? position.timestamp
        position.anchorID = selectedAnchorID
        state.position = position
        state.positions[position.sourceID] = position
    }

    func setMode(_ mode: SwipeLabMode) {
        state.mode = mode
        if mode == .practise && activePractice == nil { beginPractice() }
        if mode == .compare { showSources = false }
        if mode == .outcomes { Task { await loadOutcomes() } }
        scheduleSave()
    }

    func updateStudy(scope: SwipeLabScope? = nil) async {
        guard !isRunning else { return }
        do {
            let primary = try await SwipeLabCorpus.resolve(scope ?? state.scope)
            let comparison = try await state.comparisonScope.mapAsync { try await SwipeLabCorpus.resolve($0, comparison: true) } ?? []
            if let scope { state.scope = scope }
            capturePosition()
            readerModel?.stop(); readerModel = nil
            sources = combine(primary, comparison)
            latestSources = sources
            state.snapshots.append(.init(sources: sources.map(\.manifest)))
            state.observedJobs = [:]
            hasUpdates = false
            if let id = sources.first(where: { $0.id == state.position?.sourceID })?.id ?? sources.first?.id { selectSource(id, remember: false) }
            await persist()
        } catch { fail(error) }
    }

    func addComparison(_ scope: SwipeLabScope?) async {
        guard !isRunning else { return }
        // Resolve first; a failed fetch must not relabel the old corpus as a
        // newly selected comparison population.
        do { _ = try await scope.mapAsync { try await SwipeLabCorpus.resolve($0, comparison: true) } }
        catch { fail(error); return }
        state.comparisonScope = scope
        showComparisonPicker = false
        await updateStudy()
        state.mode = .compare
    }

    func ask(_ question: String? = nil) {
        let text = (question ?? state.draftQuestion).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !text.isEmpty else { return }
        guard sources.contains(where: \.isReadable) else { fail(SwipeLabError.noSources); return }
        // Changed originals are an explicit new snapshot before new reasoning;
        // old citations retain the old hash and are never silently reassigned.
        if let current = state.snapshots.last,
           current.fingerprint != SwipeLabSnapshot(sources: sources.map(\.manifest)).fingerprint {
            let presentIDs = Set(sources.map(\.id))
            let unavailable = current.sources.filter { !presentIDs.contains($0.sourceID) }
            state.snapshots.append(.init(sources: sources.map(\.manifest) + unavailable))
        }
        error = nil; isRunning = true; activity = "Preparing the study method"
        let pending = state.turns.last
        let turn = pending?.role == .user && pending?.text == text && pending?.snapshotID == state.snapshots.last?.id
            ? pending! : SwipeLabTurn(role: .user, text: text, snapshotID: state.snapshots.last?.id)
        if !state.turns.contains(where: { $0.id == turn.id }) { state.turns.append(turn) }
        state.draftQuestion = ""
        let runState = state
        let runSources = sources
        runningTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.runningTask = nil }
            do {
                if let index = self.state.turns.firstIndex(where: { $0.id == turn.id }) {
                    self.state.turns[index].questionID = try await SwipeLabStore.shared.saveQuestion(text, sessionID: self.sessionID, id: turn.id)
                }
                await self.persist()
                let pack = try await SwipeLabPromptCatalog.assemble(state: runState, sources: runSources)
                self.promptModules = pack.modules
                let result = try await SwipeLabEngine.analyze(question: text, state: runState, sources: runSources, pack: pack) { [weak self] coverage, label in
                    self?.coverage = coverage; self?.activity = label
                }
                try Task.checkCancellation()
                self.state.findings += result.findings
                self.state.observedJobs.merge(result.jobs) { _, new in new }
                self.coverage = result.coverage
                self.state.turns.append(.init(role: .assistant, text: result.answer,
                    snapshotID: runState.snapshots.last?.id, coverage: result.coverage,
                    findingIDs: result.findings.map(\.id),
                    anchors: Array(Set(result.findings.flatMap { $0.support + $0.counterevidence })), promptHash: pack.hash))
                self.activity = "Study saved"
                await self.persist()
            } catch is CancellationError {
                self.activity = "Study paused · completed source readings are cached"
                self.state.draftQuestion = text
                await self.persist()
            } catch { self.state.draftQuestion = text; self.fail(error); await self.persist() }
        }
    }

    func cancel() { runningTask?.cancel() }
    func dismissError() { error = nil }
    func fail(_ error: Error) { self.error = error.localizedDescription }

    func accept(_ finding: SwipeLabFinding) async {
        do {
            let accepted = try await SwipeLabStore.shared.savePrinciple(finding, sessionID: sessionID)
            if let index = state.findings.firstIndex(where: { $0.id == finding.id }) { state.findings[index] = accepted }
            await persist()
        } catch { fail(error) }
    }

    func saveEditedFinding(_ finding: SwipeLabFinding) async {
        var updated = finding; updated.updatedAt = Date()
        do {
            try await SwipeLabStore.shared.updatePrinciple(updated)
            if let index = state.findings.firstIndex(where: { $0.id == updated.id }) { state.findings[index] = updated }
            editingFinding = nil
            await persist()
        } catch { fail(error) }
    }

    func archive(_ finding: SwipeLabFinding) async {
        var updated = finding; updated.status = .archived
        await saveEditedFinding(updated)
    }

    func beginPractice() {
        let recent = Set(state.practices.suffix(5).map(\.sourceID))
        let candidates = sources.filter { $0.isReadable && !recent.contains($0.id) }
        guard let source = candidates.first ?? sources.first(where: \.isReadable), let unit = source.units.first else { return }
        selectSource(source.id)
        let due = state.findings.first { finding in
            finding.status == .accepted && !state.practices.contains { $0.principleID == finding.id && ($0.completedAt ?? .distantPast) > Date().addingTimeInterval(-3 * 86_400) }
        }
        let question = due.map { "Does ‘\($0.title)’ explain this opening? Describe the evidence and one condition where it could fail." }
            ?? "What does this opening make the reader expect? Explain the specific words that create that expectation, then predict the next beat."
        let practice = SwipeLabPractice(sourceID: source.id, anchor: unit.anchor, question: question, principleID: due?.id)
        state.practices.append(practice); activePracticeID = practice.id
        state.mode = .practise
        scheduleSave()
    }

    func updatePractice(answer: String? = nil, application: String? = nil) {
        guard let index = state.practices.firstIndex(where: { $0.id == activePracticeID }) else { return }
        if let answer { state.practices[index].answer = answer }
        if let application { state.practices[index].application = application }
        state.practices[index].updatedAt = Date()
        scheduleSave()
    }

    func reviewPractice() {
        guard !isRunning, let practice = activePractice, !practice.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let source = sources.first(where: { $0.id == practice.sourceID }) else { return }
        guard source.contentHash == practice.anchor.sourceHash else { fail(SwipeLabError.sourceChanged); return }
        isRunning = true; activity = "Reading your explanation against the source"
        runningTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.runningTask = nil }
            do {
                let pack = try await SwipeLabPromptCatalog.assemble(state: self.state, sources: [source])
                let prompt = """
                    Give focused feedback on this study exercise. Identify what the learner noticed accurately, what the evidence doesn't support, and a useful next observation. No mastery score or invented performance claims. Under 220 words.
                    Exercise: \(practice.question)
                    User's explanation: \(practice.answer)
                    Their client application: \(practice.application)
                    Client context: \(pack.client)
                    Original opening: \(practice.anchor.quote)
                    Next original beat: \(source.units.dropFirst().first?.text ?? "No next passage available")
                    """
                let opening = source.units.filter { $0.id == practice.anchor.id }
                let images = await SwipeLabVisualLoader.load(source: source, units: opening)
                if practice.anchor.quote.isEmpty && images.isEmpty { throw SwipeLabError.sourceChanged }
                let feedback = images.isEmpty ? try await SwipeLabEngine.liveCompletion(prompt: prompt, system: pack.system, maxTokens: 1600)
                    : try await SwipeLabEngine.visualCompletion(prompt: prompt, system: pack.system, maxTokens: 1600, images: images)
                try Task.checkCancellation()
                if let index = self.state.practices.firstIndex(where: { $0.id == practice.id }) {
                    self.state.practices[index].feedback = feedback
                    self.state.practices[index].completedAt = Date()
                    self.state.practices[index].updatedAt = Date()
                }
                await self.persist()
            } catch is CancellationError { self.activity = "Practice paused" }
            catch { self.fail(error) }
        }
    }

    func prepareExperiment(_ finding: SwipeLabFinding) {
        experimentFinding = finding
        experimentTitle = finding.title
        experimentHypothesis = finding.mechanism
        experimentChange = finding.transfer
        experimentCounterPrediction = "The chosen outcome does not improve against comparable client posts."
        experimentDays = 7; showExperimentEditor = true
    }

    func createIdea() async {
        guard let finding = experimentFinding, !experimentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let accepted = finding.status == .accepted ? finding : try await SwipeLabStore.shared.savePrinciple(finding, sessionID: sessionID)
            if let index = state.findings.firstIndex(where: { $0.id == accepted.id }) { state.findings[index] = accepted }
            let experimentID = UUID().uuidString
            var idea = Atom.new(type: .idea, title: experimentTitle, body: """
                Hypothesis: \(experimentHypothesis)
                Deliberate creative change: \(experimentChange)
                What would challenge this: \(experimentCounterPrediction)
                Measure: \(state.metric.title), \(experimentDays) days after publishing.
                Supply the client's own verified details and phrasing.
                """, links: [AtomLink(linkType: .outputFromInquiry, uuid: sessionID, entityType: .inquirySession)])
            idea = idea.withUpdatedIdeaMetadata { metadata in
                metadata.linkedSwipeIds = Array(Set(accepted.support.map(\.sourceID)))
                metadata.linkedConnectionIds = accepted.connectionID.map { [$0] } ?? []
                metadata.clientUUID = accepted.clientID
                metadata.clientName = accepted.clientID == nil ? nil : clientName
                metadata.context = SwipeLabStore.principleText(accepted)
            }
            let created = try await AtomRepository.shared.create(idea)
            state.experiments.append(.init(id: experimentID, principleID: accepted.id, ideaID: created.uuid,
                clientID: accepted.clientID, hypothesis: experimentHypothesis, deliberateChange: experimentChange,
                counterPrediction: experimentCounterPrediction, metric: state.metric, observationDays: max(1, experimentDays)))
            showExperimentEditor = false
            await persist()
            if let id = created.id {
                NotificationCenter.default.post(name: .enterFocusMode, object: nil, userInfo: ["type": EntityType.idea, "id": id])
            }
        } catch { fail(error) }
    }

    func loadOutcomes() async {
        do {
            outcomeContent = try await AtomRepository.shared.fetchAll(type: .content)
            for experiment in state.experiments {
                if let content = linkedContent(for: experiment) {
                    outcomeSnapshots[content.uuid] = await ContentPerfStore.snapshots(forContent: content.uuid)
                }
            }
        } catch { fail(error) }
    }

    func linkedContent(for experiment: SwipeLabExperiment) -> Atom? {
        outcomeContent.first { content in
            if let linkedID = experiment.contentID { return content.uuid == linkedID }
            if let data = content.metadata?.data(using: .utf8),
               let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               metadata["sourceIdeaUUID"] as? String == experiment.ideaID { return true }
            return content.linksList.contains { $0.uuid == experiment.ideaID && ["parent_idea", "origin_idea"].contains($0.type) }
        }
    }

    func linkContent(_ contentID: String, experimentID: String) async {
        guard let index = state.experiments.firstIndex(where: { $0.id == experimentID }) else { return }
        state.experiments[index].contentID = contentID
        state.experiments[index].updatedAt = Date()
        await persist(); await loadOutcomes()
    }

    func reviewOutcome(_ experiment: SwipeLabExperiment) {
        guard !isRunning, let content = linkedContent(for: experiment),
              let snapshots = outcomeSnapshots[content.uuid], !snapshots.isEmpty else { return }
        isRunning = true; activity = "Reviewing the experiment's observed results"
        runningTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.runningTask = nil }
            do {
                let source = SwipeLabCorpus.source(content, performance: snapshots)
                var reviewState = self.state
                reviewState.targetClientID = experiment.clientID
                let pack = try await SwipeLabPromptCatalog.assemble(state: reviewState, sources: [source])
                let result = try await SwipeLabEngine.liveCompletion(prompt: """
                    Review this creative experiment in fewer than 220 words. Separate measured results from explanations. These are observational results; do not claim the mechanism caused the outcome. If the requested observation window is absent, say that plainly. Suggest whether the lesson needs a narrower scope; do not rewrite accepted knowledge.
                    Hypothesis: \(experiment.hypothesis)
                    Change: \(experiment.deliberateChange)
                    Disconfirming result: \(experiment.counterPrediction)
                    Target: \(experiment.metric.title) at day \(experiment.observationDays)
                    Notes: \(experiment.resultNote)
                    Observations: \(source.metrics.filter { $0.metric == experiment.metric }.map { "\($0.value) \($0.metric.title) on \($0.platform); age hours \($0.ageHours.map { String($0) } ?? "unknown"); captured \($0.capturedAt.map { ISO8601.string(from: $0) } ?? "unknown")" }.joined(separator: "\n"))
                    No controlled comparison or counterfactual result has been supplied.
                    """, system: pack.system, maxTokens: 1600)
                try Task.checkCancellation()
                if let index = self.state.experiments.firstIndex(where: { $0.id == experiment.id }) {
                    self.state.experiments[index].review = result
                    self.state.experiments[index].updatedAt = Date()
                }
                await self.persist()
            } catch is CancellationError { self.activity = "Review paused" }
            catch { self.fail(error) }
        }
    }

    private func combine(_ primary: [SwipeLabSource], _ comparison: [SwipeLabSource]) -> [SwipeLabSource] {
        var seen = Set<String>(); var hashes: [String: String] = [:]
        return (primary + comparison).compactMap { input in
            guard seen.insert(input.id).inserted else { return nil }
            var source = input
            let text = source.units.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !text.isEmpty {
                let hash = SwipeLabHash.string(text)
                source.duplicateOf = hashes[hash]
                if hashes[hash] == nil { hashes[hash] = source.id }
            }
            return source
        }
    }
}

private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
