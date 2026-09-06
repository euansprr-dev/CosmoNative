import Combine
import Foundation
import Observation

/// Owns assistant presence for a Page host; the shared editor session remains
/// the sole writer of the Page's draft and persistence state.
@MainActor @Observable
final class UnifiedPageAssistant {
    private(set) var reviewProposal: CosmoAssistantProposal?
    @ObservationIgnored private let session: SpacePageEditorSession
    @ObservationIgnored private let selectionBox = NoteSelectionBox()
    @ObservationIgnored private var provider: NoteContextProvider?
    @ObservationIgnored private var proposalsSubscription: AnyCancellable?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isPresent = false
    @ObservationIgnored private var isContextOwner = false

    init(session: SpacePageEditorSession) {
        self.session = session
        let surfaceID = "note:" + session.atom.uuid
        proposalsSubscription = CosmoInlineAssistantStore.shared.$proposals.sink { [weak self] proposals in
            self?.reviewProposal = proposals.last { $0.surfaceID == surfaceID && $0.hasReviewableOperations }
        }
    }

    func activate(isContextOwner: Bool = true) {
        let provider = contextProvider()
        let shouldPromote = !isPresent || (!self.isContextOwner && isContextOwner)
        isPresent = true
        self.isContextOwner = isContextOwner
        CosmoEditableSurfaceRegistry.shared.registerPresence(provider)
        if isContextOwner && shouldPromote { CosmoWindowViewModel.shared.updateContext(provider: provider) }
    }

    func deactivate() {
        refreshTask?.cancel(); refreshTask = nil
        isPresent = false; isContextOwner = false
        selectionBox.selectedText = ""
        guard let provider else { return }
        // Both calls are instance-guarded, so an outgoing host cannot remove
        // the same Page's provider in a new host.
        CosmoEditableSurfaceRegistry.shared.unregister(provider)
        CosmoWindowViewModel.shared.releaseContext(provider: provider)
    }

    func reportSelection(_ snapshot: EditorSelectionSnapshot) {
        let previous = selectionBox.selectedText
        selectionBox.selectedText = snapshot.text
        guard isPresent, previous != snapshot.text else { return }
        if isContextOwner, let provider { CosmoEditableSurfaceRegistry.shared.activateIfNeeded(provider) }
        let text = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        CosmoInlineAssistantStore.shared.reportSelection(
            text.isEmpty ? nil : CosmoEditableSelection(text: text, containingLine: nil),
            forSurfaceID: "note:" + session.atom.uuid
        )
        refresh()
    }

    func refresh() {
        guard isPresent else { return }
        if isContextOwner, let provider { CosmoEditableSurfaceRegistry.shared.activateIfNeeded(provider) }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard let self, self.isPresent, !Task.isCancelled else { return }
            CosmoWindowViewModel.shared.refreshContextIfCurrentAtomMatches(atomUUID: self.session.atom.uuid)
        }
    }

    func openAssistant() {
        activate(isContextOwner: true)
        let provider = contextProvider()
        CosmoWindowViewModel.shared.updateContext(provider: provider)
        CosmoInlineAssistantStore.shared.openPane(forSurfaceID: provider.surfaceID)
    }

    private func contextProvider() -> NoteContextProvider {
        if let provider { return provider }
        let session = session, selection = selectionBox
        let next = NoteContextProvider(
            atom: session.atom,
            titleRef: { session.title },
            contentRef: { session.document.plainText },
            tagsRef: { session.tags },
            selectedTextRef: { selection.selectedText },
            applyBodyEdit: { [weak self] operation in
                guard let self else {
                    return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Page editor is unavailable")
                }
                return try self.apply(operation)
            }
        )
        provider = next
        return next
    }

    private func apply(_ operation: CosmoAssistantProposalOperation) throws -> CosmoEditableOperationResult {
        guard operation.targetID == NoteContextProvider.targetID(for: session.atom.uuid), !session.isDeleted else {
            throw UnifiedPageRichTextEdit.Failure.missingTarget
        }
        let edited = try UnifiedPageRichTextEdit.applying(operation, to: session.document)
        session.edit(edited)
        refresh()
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }
}
