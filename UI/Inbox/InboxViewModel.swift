// CosmoOS/UI/Inbox/InboxViewModel.swift
// State management for the Smart Triage Inbox
// March 2026

import SwiftUI
import Combine

@MainActor
class InboxViewModel: ObservableObject {
    @Published var items: [InboxItem] = []
    @Published var isLoading = false
    @Published var processingItemId: String?

    // Override sheet state
    @Published var overrideItem: InboxItem?
    @Published var showOverrideSheet = false

    // Search for override merge targets
    @Published var overrideSearchQuery = ""
    @Published var overrideSearchResults: [HybridSearchEngine.SearchResult] = []

    private let inboxRepo = InboxRepository.shared
    private let classifier = InboxClassificationEngine.shared
    private let executor = InboxActionExecutor.shared
    private var cancellables = Set<AnyCancellable>()

    var thinkspaces: [Thinkspace] {
        ThinkspaceManager.shared.thinkspaces
    }

    init() {
        startObserving()
    }

    // MARK: - Observation

    private func startObserving() {
        inboxRepo.$items
            .receive(on: DispatchQueue.main)
            .assign(to: &$items)
    }

    // MARK: - Actions

    func acceptSuggestion(for item: InboxItem) async {
        processingItemId = item.uuid
        defer { processingItemId = nil }

        do {
            switch item.classification {
            case .merge:
                guard let targetUuid = item.mergeTargetUuid else { return }
                _ = try await executor.executeMerge(item: item, targetAtomUuid: targetUuid)

            case .place:
                guard let thinkspaceId = item.placeThinkspaceId else { return }
                let atomType = AtomType(rawValue: item.placeAtomType ?? "connection") ?? .connection
                _ = try await executor.executePlace(item: item, thinkspaceId: thinkspaceId, atomType: atomType)

            case .new:
                let atomType = AtomType(rawValue: item.placeAtomType ?? "connection") ?? .connection
                _ = try await executor.executeNew(item: item, atomType: atomType)

            case .none:
                // Not yet classified — treat as new
                _ = try await executor.executeNew(item: item, atomType: .connection)
            }
        } catch {
            print("⚠️ [InboxVM] Action failed: \(error)")
        }
    }

    func dismiss(item: InboxItem) async {
        do {
            try await inboxRepo.dismiss(uuid: item.uuid)
        } catch {
            print("⚠️ [InboxVM] Dismiss failed: \(error)")
        }
    }

    func showOverride(for item: InboxItem) {
        overrideItem = item
        overrideSearchQuery = ""
        overrideSearchResults = []
        showOverrideSheet = true
    }

    // MARK: - Override Actions

    func overrideMerge(item: InboxItem, targetUuid: String) async {
        processingItemId = item.uuid
        defer { processingItemId = nil }

        do {
            _ = try await executor.executeMerge(item: item, targetAtomUuid: targetUuid)
            showOverrideSheet = false
        } catch {
            print("⚠️ [InboxVM] Override merge failed: \(error)")
        }
    }

    func overridePlace(item: InboxItem, thinkspaceId: String, atomType: AtomType) async {
        processingItemId = item.uuid
        defer { processingItemId = nil }

        do {
            _ = try await executor.executePlace(item: item, thinkspaceId: thinkspaceId, atomType: atomType)
            showOverrideSheet = false
        } catch {
            print("⚠️ [InboxVM] Override place failed: \(error)")
        }
    }

    func overrideNew(item: InboxItem, atomType: AtomType) async {
        processingItemId = item.uuid
        defer { processingItemId = nil }

        do {
            _ = try await executor.executeNew(item: item, atomType: atomType)
            showOverrideSheet = false
        } catch {
            print("⚠️ [InboxVM] Override new failed: \(error)")
        }
    }

    // MARK: - Search for Override Targets

    func searchAtoms(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            overrideSearchResults = []
            return
        }
        do {
            overrideSearchResults = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 8
            )
        } catch {
            overrideSearchResults = []
        }
    }
}
