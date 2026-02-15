// CosmoOS/UI/FocusMode/Content/ContentFocusModeView.swift
// Main Content Focus Mode container - 3-step workflow (Brainstorm → Draft → Polish)
// February 2026

import SwiftUI
import Combine
import GRDB

// MARK: - Content Focus Mode View

/// Main container for Content Focus Mode.
/// Routes between 3 workflow steps with a persistent step indicator in the top bar.
struct ContentFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var viewModel: ContentFocusModeViewModel
    @State private var isContextPanelVisible = true

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: ContentFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            // Step content + context panel
            VStack(spacing: 0) {
                // Top bar spacer
                Spacer().frame(height: 56)

                HStack(spacing: 0) {
                    // Step views
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Divider
                    if isContextPanelVisible {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                    }

                    // Context panel
                    ContentContextPanel(
                        atom: atom,
                        state: $viewModel.state,
                        isVisible: isContextPanelVisible
                    )
                }

                // Unified bottom navigation bar (fixed position)
                unifiedBottomBar
            }

            // Top bar overlay (fixed)
            VStack {
                topBar
                Spacer()
            }

            // XP award animation overlay
            if let xp = viewModel.xpAwarded {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("+\(xp) XP")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "#22C55E"))
                            .shadow(color: Color(hex: "#22C55E").opacity(0.5), radius: 8)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                        Spacer()
                    }
                    .padding(.bottom, 80)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.xpAwarded)
                .zIndex(200)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.xpAwarded)
        .onAppear {
            viewModel.loadState()
            viewModel.startObservingState()
            Task {
                await viewModel.searchRelatedAtoms()
            }
        }
        .onDisappear {
            // Force immediate save — don't lose any pending edits
            viewModel.saveOnClose()
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        if ContentFocusModeState.stepForPhase(viewModel.displayPhase) != nil {
            // Creation phase -- use existing step routing
            creationStepContent
        } else {
            // Post-creation phase
            PostCreationPhaseView(
                phase: viewModel.displayPhase,
                atom: atom,
                state: $viewModel.state,
                onAdvancePhase: { phase in
                    viewModel.goToPhase(phase)
                }
            )
        }
    }

    @ViewBuilder
    private var creationStepContent: some View {
        switch viewModel.state.currentStep {
        case .brainstorm:
            ContentBrainstormView(
                state: $viewModel.state,
                atom: atom,
                onNext: {
                    viewModel.goToStep(.draft)
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        case .draft:
            ContentDraftView(
                state: $viewModel.state,
                atom: atom,
                onBack: {
                    viewModel.goToStep(.brainstorm)
                },
                onNext: {
                    viewModel.goToStep(.polish)
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        case .polish:
            ContentPolishView(
                state: $viewModel.state,
                atom: atom,
                onBack: {
                    viewModel.goToStep(.draft)
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    // MARK: - Unified Bottom Navigation Bar

    private var unifiedBottomBar: some View {
        HStack {
            // Left: Back button (hidden on first phase)
            if let prevPhase = viewModel.displayPhase.previousPhase {
                Button {
                    viewModel.goToPhase(prevPhase)
                } label: {
                    backButtonLabel(prevPhase)
                }
                .buttonStyle(.plain)
            } else {
                // Spacer to keep layout stable
                Color.clear.frame(width: 120, height: 1)
            }

            Spacer()

            // Right: Next button (shows "Archive" on last creation phase)
            if let nextPhase = viewModel.displayPhase.nextPhase {
                Button {
                    viewModel.goToPhase(nextPhase)
                } label: {
                    nextButtonLabel(nextPhase)
                }
                .buttonStyle(.plain)
            } else {
                // On the last phase (archived), no forward button
                Color.clear.frame(width: 120, height: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(CosmoColors.thinkspaceVoid)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
        )
    }

    @ViewBuilder
    private func backButtonLabel(_ phase: ContentPhase) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left")
                .font(.system(size: 12, weight: .medium))
            Text(phase.displayName)
                .font(CosmoTypography.label)
        }
        .foregroundColor(.white.opacity(0.6))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private func nextButtonLabel(_ phase: ContentPhase) -> some View {
        HStack(spacing: 6) {
            Text(phase.displayName)
                .font(CosmoTypography.label)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.blockContent)
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Back button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            // Title
            Text(atom.title ?? "Content")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            // Type badge
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                Text("CONTENT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundColor(CosmoColors.blockContent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CosmoColors.blockContent.opacity(0.15), in: Capsule())

            Spacer()

            // Pipeline bar
            ContentPipelineBar(
                currentPhase: viewModel.displayPhase,
                reachedPhase: viewModel.currentPhase,
                phaseEnteredAt: viewModel.phaseEnteredAt,
                onPhaseSelected: { phase in
                    viewModel.goToPhase(phase)
                }
            )

            Spacer()

            // Context panel toggle
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    isContextPanelVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(isContextPanelVisible ? 0.7 : 0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    CosmoColors.thinkspaceVoid.opacity(0.95),
                    CosmoColors.thinkspaceVoid.opacity(0.8),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

}

// MARK: - Content Focus Mode ViewModel

@MainActor
class ContentFocusModeViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: ContentFocusModeState
    @Published var xpAwarded: Int? = nil  // Set briefly to show XP animation
    @Published var displayPhase: ContentPhase = .ideation  // Currently displayed phase (UI-driven)

    // MARK: - Properties

    private var atom: Atom
    private var autoSaveTask: Task<Void, Never>?
    private let autoSaveDelay: TimeInterval = 1.5
    private var saveNotificationCancellable: AnyCancellable?
    private(set) var isInitialLoad = true
    private var writeSequence: Int = 0
    private var isClosed = false

    // MARK: - Initialization

    init(atom: Atom) {
        self.atom = atom
        self.state = ContentFocusModeState(atomUUID: atom.uuid)
    }

    private var phaseChangeCancellable: AnyCancellable?

    deinit {
        autoSaveTask?.cancel()
        saveNotificationCancellable?.cancel()
        phaseChangeCancellable?.cancel()
    }

    // MARK: - State Observation

    /// Listen for save notifications from child views.
    /// Every child view calls state.save() which posts .contentFocusStateSaved.
    /// We debounce and write to the atom in the database.
    func startObservingState() {
        let atomUUID = atom.uuid
        saveNotificationCancellable = NotificationCenter.default
            .publisher(for: .contentFocusStateSaved)
            .filter { notification in
                notification.userInfo?["atomUUID"] as? String == atomUUID
            }
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isInitialLoad else {
                    print("💾 Content focus: debounced save skipped (isInitialLoad=\(self?.isInitialLoad ?? true))")
                    return
                }
                print("💾 Content focus: debounced save firing")
                self.writeToAtom()
            }

        // Observe phase changes from PostCreationPhaseView actions
        phaseChangeCancellable = NotificationCenter.default
            .publisher(for: .contentPhaseChanged)
            .filter { $0.userInfo?["atomUUID"] as? String == atomUUID }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    if let freshAtom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                        self.atom = freshAtom
                        self.objectWillChange.send()
                    }
                }
            }
    }

    // MARK: - State Management

    /// Load state directly from the atom's body + metadata fields.
    func loadState() {
        isInitialLoad = true
        print("📖 Content focus: loadState for atom \(atom.uuid) (id: \(atom.id ?? -1))")

        // Read state from atom metadata (the single source of truth)
        if let savedState = ContentFocusModeState.from(atom: atom) {
            print("📖 Content focus: restored state (step: \(savedState.currentStep.rawValue), coreIdea: \(savedState.coreIdea.prefix(30)), outline: \(savedState.outline.count) items)")
            state = savedState
        } else {
            // No saved focus state yet — initialize from atom fields
            if let body = atom.body, !body.isEmpty {
                state.draftContent = body
            }
            if let metadata = atom.metadata,
               let data = metadata.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let coreIdea = dict["coreIdea"] as? String {
                state.coreIdea = coreIdea
            }
        }

        // Initialize displayPhase from atom metadata (the persisted pipeline phase)
        displayPhase = currentPhase

        // Mark initial load complete after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isInitialLoad = false
        }
    }

    /// Write current state directly to the atom in the database.
    /// This is the ONLY save path — no UserDefaults.
    /// Uses a write sequence number so stale writes (from debounced handlers
    /// that fire after a step transition) are discarded.
    func writeToAtom() {
        state.lastModified = Date()
        let stateCopy = state
        let atomUUID = atom.uuid
        writeSequence += 1
        let mySequence = writeSequence

        print("💾 Content focus: writing to atom \(atomUUID) (step: \(stateCopy.currentStep.rawValue), seq: \(mySequence), coreIdea: \(stateCopy.coreIdea.prefix(30)), outline: \(stateCopy.outline.count) items)")

        Task {
            // Check if a newer write has been queued — if so, skip this one
            guard mySequence == self.writeSequence else {
                print("💾 Content focus: skipping stale write seq \(mySequence) (latest: \(self.writeSequence))")
                return
            }

            do {
                try await CosmoDatabase.shared.asyncWrite { db in
                    // Read existing metadata to preserve non-focus-state keys
                    var existingMetadata: String? = nil
                    if let row = try Row.fetchOne(db, sql: "SELECT metadata FROM atoms WHERE uuid = ?", arguments: [atomUUID]),
                       let existing: String = row["metadata"] {
                        existingMetadata = existing
                    }

                    let fields = stateCopy.toAtomFields(existingMetadata: existingMetadata)

                    try db.execute(
                        sql: """
                        UPDATE atoms
                        SET body = ?,
                            metadata = COALESCE(?, metadata),
                            updated_at = ?,
                            _local_version = _local_version + 1
                        WHERE uuid = ?
                        """,
                        arguments: [
                            fields.body,
                            fields.metadata,
                            ISO8601DateFormatter().string(from: Date()),
                            atomUUID
                        ]
                    )
                    print("💾 Content focus: wrote to atom \(atomUUID) seq \(mySequence), rows affected: \(db.changesCount)")
                }
            } catch {
                print("❌ Content focus: failed to write to atom: \(error)")
            }
        }
    }

    /// Called when view disappears — force immediate save
    func saveOnClose() {
        print("💾 Content focus: saveOnClose for atom \(atom.uuid)")
        isClosed = true
        autoSaveTask?.cancel()
        // Cancel debounced notification subscription to prevent stale writes after close
        saveNotificationCancellable?.cancel()
        saveNotificationCancellable = nil
        writeToAtom()
    }

    // MARK: - Phase Accessors

    var currentPhase: ContentPhase {
        // Read from atom metadata, default to mapping from ContentStep
        if let metadata = atom.metadataValue(as: ContentAtomMetadata.self) {
            return metadata.phase
        }
        return stepToPhase(state.currentStep)
    }

    var phaseEnteredAt: Date? {
        if let metadata = atom.metadataValue(as: ContentAtomMetadata.self),
           let dateStr = metadata.phaseEnteredAt {
            return ISO8601DateFormatter().date(from: dateStr)
        }
        return nil
    }

    func goToPhase(_ phase: ContentPhase) {
        let currentIdx = ContentPhase.allCases.firstIndex(of: displayPhase) ?? 0
        let targetIdx = ContentPhase.allCases.firstIndex(of: phase) ?? 0

        if targetIdx > currentIdx {
            // Moving forward — call advancePhase() to award XP
            advanceToPhase(phase)
        } else {
            // Moving backward — update display phase and step if applicable
            withAnimation(ProMotionSprings.focusTransition) {
                displayPhase = phase
            }
            if let step = ContentFocusModeState.stepForPhase(phase) {
                goToStep(step)
            }
        }
    }

    /// Advance forward through phases, calling ContentPipelineService for each step.
    private func advanceToPhase(_ targetPhase: ContentPhase) {
        Task {
            let pipelineService = ContentPipelineService()
            var currentIdx = ContentPhase.allCases.firstIndex(of: displayPhase) ?? 0
            let targetIdx = ContentPhase.allCases.firstIndex(of: targetPhase) ?? 0

            while currentIdx < targetIdx {
                do {
                    _ = try await pipelineService.advancePhase(contentUUID: atom.uuid)
                    let xp = ContentPhase.allCases[currentIdx + 1].completionXP
                    if xp > 0 {
                        xpAwarded = xp
                        // Clear after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.xpAwarded = nil
                        }
                    }
                    currentIdx += 1
                    print("Content focus: advanced to \(ContentPhase.allCases[currentIdx].displayName), XP: \(xp)")

                    // Refresh atom from DB to get updated metadata
                    if let freshAtom = try? await AtomRepository.shared.fetch(uuid: atom.uuid) {
                        atom = freshAtom
                    }
                } catch {
                    print("Content focus: advancePhase failed: \(error)")
                    break
                }
            }

            // Update displayPhase to the target
            withAnimation(ProMotionSprings.focusTransition) {
                displayPhase = targetPhase
            }

            // Update the step UI to match
            if let step = ContentFocusModeState.stepForPhase(targetPhase) {
                goToStep(step)
            } else {
                // Post-creation phase — just notify the UI to refresh
                objectWillChange.send()
            }
        }
    }

    private func stepToPhase(_ step: ContentStep) -> ContentPhase {
        switch step {
        case .brainstorm: return .ideation
        case .draft: return .draft
        case .polish: return .polish
        }
    }

    // MARK: - Navigation

    func goToStep(_ step: ContentStep) {
        print("📝 Content focus: goToStep → \(step.rawValue)")

        // Cancel any pending debounced writes from the PREVIOUS step
        // to prevent stale state from overwriting the new step
        saveNotificationCancellable?.cancel()
        saveNotificationCancellable = nil

        withAnimation(ProMotionSprings.focusTransition) {
            state.currentStep = step
        }
        writeToAtom()

        // Re-subscribe to save notifications for the new step
        startObservingState()
    }

    // MARK: - Related Atoms Search

    func searchRelatedAtoms() async {
        let query = [atom.title ?? "", state.coreIdea]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !query.isEmpty else { return }

        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 10
            )

            // Don't update state if the view has been closed
            guard !isClosed else { return }

            // Convert to RelatedAtomRef, excluding the current atom
            let refs = results
                .filter { $0.entityUUID != atom.uuid }
                .prefix(8)
                .map { result in
                    RelatedAtomRef(
                        atomUUID: result.entityUUID ?? "",
                        title: result.title,
                        type: AtomType(rawValue: result.entityType.rawValue) ?? .idea,
                        relevanceScore: result.combinedScore,
                        preview: result.preview
                    )
                }

            state.relatedAtoms = Array(refs)
            // Use notification-based save instead of direct writeToAtom()
            // to avoid racing with step transitions
            state.save()
        } catch {
            print("❌ Content focus: related atoms search failed: \(error)")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ContentFocusModeView_Previews: PreviewProvider {
    static var previews: some View {
        ContentFocusModeView(
            atom: Atom.new(
                type: .content,
                title: "How to Build a Second Brain",
                body: ""
            ),
            onClose: { print("Close") }
        )
        .frame(width: 1200, height: 800)
    }
}
#endif
