import Foundation
import SwiftUI
import AppKit

@MainActor
final class CosmoEditableSurfaceRegistry {
    static let shared = CosmoEditableSurfaceRegistry()

    private var providers: [String: WeakEditableSurfaceProvider] = [:]
    private var activationOrder: [String] = []

    var activeSurface: (any CosmoEditableSurfaceProvider)? {
        cleanupReleasedProviders()
        return activationOrder.reversed().compactMap { providers[$0]?.provider }.first
    }

    func provider(surfaceID: String) -> (any CosmoEditableSurfaceProvider)? {
        cleanupReleasedProviders()
        return providers[surfaceID]?.provider
    }

    func register(_ provider: any CosmoEditableSurfaceProvider) {
        providers[provider.surfaceID] = WeakEditableSurfaceProvider(provider)
        activationOrder.removeAll { $0 == provider.surfaceID }
        activationOrder.append(provider.surfaceID)
        // An editable surface coming alive is the strongest signal an inline edit
        // is coming — warm the prompt-cache prefix and prefetch ambient context
        // in the background, so the first request needs zero tool round-trips.
        let snapshot = provider.editableSnapshot()
        CosmoInlineAssistantCacheWarmer.warmIfNeeded()
        CosmoInlineAmbientContextPack.shared.prefetch(for: snapshot)
        CosmoInlineSkillAutoRunner.shared.surfaceActivated(snapshot: snapshot)
    }

    func activate(surfaceID: String) {
        guard providers[surfaceID]?.provider != nil else { return }
        activationOrder.removeAll { $0 == surfaceID }
        activationOrder.append(surfaceID)
    }

    /// Hot-path activation (typing, focus events): no-op when the surface is
    /// already frontmost, so per-keystroke callers cost two array reads.
    func activateIfNeeded(surfaceID: String) {
        guard activationOrder.last != surfaceID else { return }
        activate(surfaceID: surfaceID)
    }

    func unregister(surfaceID: String) {
        providers.removeValue(forKey: surfaceID)
        activationOrder.removeAll { $0 == surfaceID }
    }

    private func cleanupReleasedProviders() {
        let released = providers.compactMap { key, value in
            value.provider == nil ? key : nil
        }
        for key in released {
            providers.removeValue(forKey: key)
            activationOrder.removeAll { $0 == key }
        }
    }
}

private final class WeakEditableSurfaceProvider {
    weak var provider: (any CosmoEditableSurfaceProvider)?

    init(_ provider: any CosmoEditableSurfaceProvider) {
        self.provider = provider
    }
}

// MARK: - Key-Window Activation

/// Re-activates a surface whenever the window hosting it becomes key — the
/// missing signal that made multi-window context go stale (activation order
/// previously only changed on `onAppear`, so switching back to an atom window
/// never told the registry "this document is what the user is looking at").
struct CosmoSurfaceKeyWindowActivation: ViewModifier {
    let surfaceID: String

    func body(content: Content) -> some View {
        content.background(KeyWindowProbe(surfaceID: surfaceID))
    }

    private struct KeyWindowProbe: NSViewRepresentable {
        let surfaceID: String

        func makeNSView(context: Context) -> ProbeView {
            let view = ProbeView()
            view.surfaceID = surfaceID
            return view
        }

        func updateNSView(_ nsView: ProbeView, context: Context) {
            nsView.surfaceID = surfaceID
        }

        final class ProbeView: NSView {
            var surfaceID: String = ""
            private var observer: NSObjectProtocol?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                guard window != nil else { return }
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    MainActor.assumeIsolated {
                        guard let self,
                              let keyWindow = notification.object as? NSWindow,
                              keyWindow === self.window,
                              !self.surfaceID.isEmpty else { return }
                        CosmoEditableSurfaceRegistry.shared.activateIfNeeded(surfaceID: self.surfaceID)
                    }
                }
            }

            deinit {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
}

extension View {
    /// Attach at a focus-mode root: whenever this view's window becomes key,
    /// its surface becomes the assistant's active surface.
    func cosmoSurfaceKeyWindowActivation(surfaceID: String) -> some View {
        modifier(CosmoSurfaceKeyWindowActivation(surfaceID: surfaceID))
    }
}

// MARK: - Ambient Context Pack

/// Prefetched "sight": when a surface activates, a background task assembles
/// related-work context (hybrid search seeded from the surface's own text plus
/// the atom's links) so the common inline request answers with ZERO tool
/// round-trips. The pack is a compact digest injected into the volatile prompt
/// layer — never the cached prefix.
@MainActor
final class CosmoInlineAmbientContextPack {
    static let shared = CosmoInlineAmbientContextPack()

    struct Pack {
        let surfaceID: String
        let digest: String
        let sourceRefs: [CosmoAssistantSourceRef]
        let createdAt: Date

        var sourceUUIDs: [String] { sourceRefs.map(\.uuid) }
    }

    private var packs: [String: Pack] = [:]
    private var inFlightSurfaceIDs: Set<String> = []
    private let timeToLive: TimeInterval = 600

    /// The fresh digest for a surface, or nil when none was prefetched yet —
    /// callers degrade gracefully (the agent still has its tools).
    func digest(forSurfaceID surfaceID: String?) -> String? {
        guard let surfaceID,
              let pack = packs[surfaceID],
              Date().timeIntervalSince(pack.createdAt) < timeToLive else {
            return nil
        }
        return pack.digest
    }

    func prefetch(for snapshot: CosmoEditableSourceSnapshot) {
        let surfaceID = snapshot.surfaceID
        if let existing = packs[surfaceID],
           Date().timeIntervalSince(existing.createdAt) < timeToLive {
            return
        }
        guard !inFlightSurfaceIDs.contains(surfaceID) else { return }
        inFlightSurfaceIDs.insert(surfaceID)

        let seedQuery = Self.seedQuery(for: snapshot)
        let excludedUUID = Self.atomUUID(fromSurfaceID: surfaceID)

        Task(priority: .utility) { [weak self] in
            let results = (try? await HybridSearchEngine.shared.search(
                query: seedQuery,
                limit: 5,
                excludedEntityUUIDs: excludedUUID.map { [$0] } ?? []
            )) ?? []

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlightSurfaceIDs.remove(surfaceID)
                guard !results.isEmpty else { return }
                self.packs[surfaceID] = Pack(
                    surfaceID: surfaceID,
                    digest: Self.digest(from: results),
                    sourceRefs: results.compactMap { result in
                        guard let uuid = result.entityUUID else { return nil }
                        return CosmoAssistantSourceRef(
                            uuid: uuid,
                            title: result.title,
                            kind: result.entityType.rawValue
                        )
                    },
                    createdAt: Date()
                )
            }
        }
    }

    /// Source refs from a fresh pack — merged with tool-read refs for the
    /// answer's context chips.
    func sourceRefs(forSurfaceID surfaceID: String?) -> [CosmoAssistantSourceRef] {
        guard let surfaceID,
              let pack = packs[surfaceID],
              Date().timeIntervalSince(pack.createdAt) < timeToLive else {
            return []
        }
        return pack.sourceRefs
    }

    func invalidate(surfaceID: String) {
        packs.removeValue(forKey: surfaceID)
    }

    private static func seedQuery(for snapshot: CosmoEditableSourceSnapshot) -> String {
        let bodyLead = String(snapshot.text.prefix(300))
        return [snapshot.title, bodyLead]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }

    private static func atomUUID(fromSurfaceID surfaceID: String) -> String? {
        let parts = surfaceID.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? parts[1] : nil
    }

    private static func digest(from results: [HybridSearchEngine.SearchResult]) -> String {
        let lines = results.map { result -> String in
            var line = "- \(result.title) (\(result.entityType.rawValue)"
            if let uuid = result.entityUUID {
                line += ", uuid: \(uuid)"
            }
            line += "): \(String(result.preview.prefix(160)))"
            return line
        }
        return """
        ## Ambient Related Work (prefetched)
        Atoms related to the active surface, already retrieved — reference them directly, \
        cite their titles when you use them, and pass a uuid to open_atom if the user \
        wants to see one. Call recall only for something NOT covered here.
        \(lines.joined(separator: "\n"))
        """
    }
}

// MARK: - Atom-Backed Fallback Surface

/// Applies reviewed edits straight to an atom's body when no live view has the
/// surface registered — e.g. "append this to my swipe-learnings note" while the
/// note isn't open. Uses the same surfaceID/targetID conventions as the focus-mode
/// providers, so a proposal staged against an open note still applies after it
/// closes, and vice versa.
@MainActor
final class CosmoAtomBackedEditableSurface: CosmoEditableSurfaceProvider {
    let surfaceID: String
    private let atomUUID: String
    private let targetID: String
    private let title: String
    private var loadedText: String

    /// Resolves a surfaceID like "note:<uuid>" or "idea:<uuid>" to an atom-backed
    /// surface. Returns nil for surface kinds that need a live view to apply
    /// (structured connection fields, canvas plans, transient synthesis sessions).
    static func load(surfaceID: String) async -> CosmoAtomBackedEditableSurface? {
        let parts = surfaceID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, ["note", "idea"].contains(parts[0]) else { return nil }
        let atomUUID = parts[1]
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else { return nil }
        return CosmoAtomBackedEditableSurface(surfaceID: surfaceID, atom: atom)
    }

    private init(surfaceID: String, atom: Atom) {
        self.surfaceID = surfaceID
        self.atomUUID = atom.uuid
        self.targetID = "\(surfaceID):body"
        self.title = atom.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.loadedText = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        ).plainText
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: title.isEmpty ? "Untitled" : title,
            text: loadedText,
            sourceHash: CosmoEditableSurfaceHasher.hash(loadedText),
            anchors: [
                .init(id: "body", label: "Body", utf16Start: 0, utf16Length: loadedText.utf16.count)
            ]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard operation.targetID == targetID else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Target changed"
            )
        }
        guard let atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "The atom is no longer available"
            )
        }

        let document = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: atom.metadata,
            fallbackPlainText: atom.body
        )

        let nextDocument: RichDocument
        if operation.kind == .formatMarks {
            guard let mark = operation.formatMark,
                  let formatted = CosmoInlineFormatMarksApplier.apply(
                    mark: mark,
                    originalText: operation.originalText,
                    to: document
                  ) else {
                return CosmoEditableOperationResult(
                    operationID: operation.id, status: .rejected, message: "Couldn't find that text anymore — skipped"
                )
            }
            nextDocument = formatted
        } else {
            var bodyText = document.plainText
            guard let placement = CosmoInlineTextEditResolver.placement(for: operation, in: bodyText) else {
                return CosmoEditableOperationResult(
                    operationID: operation.id, status: .conflicted, message: "Original text not found"
                )
            }
            bodyText.replaceSubrange(placement.range, with: placement.replacementText)
            nextDocument = RichDocument.migrateLegacy(bodyText)
        }

        let written = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: atom.metadata,
            bodyDocument: nextDocument
        )
        var updated = atom
        updated.body = written.body
        updated.metadata = written.metadata
        _ = try await AtomRepository.shared.update(updated)

        loadedText = nextDocument.plainText
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
