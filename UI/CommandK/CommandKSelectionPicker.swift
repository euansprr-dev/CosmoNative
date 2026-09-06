import SwiftUI

enum CommandKPickerPurpose: Sendable {
    case addOriginals, attachReferences, placeOnCanvas
}

enum CommandKPickerScope: String, CaseIterable {
    case thisSpace = "This Space"
    case entireLibrary = "Entire Library"
}

/// UUIDs and callbacks belong to the invocation, never to whichever workspace
/// happens to be visible after an asynchronous search or confirmation.
struct CommandKPickerRequest: Identifiable {
    let id = UUID()
    let spaceID: String
    let targetUUID: String?
    let purpose: CommandKPickerPurpose
    var alreadyIncludedUUIDs: Set<String> = []
    var onConfirm: (@MainActor ([String]) async throws -> Void)? = nil
    var onComplete: (@MainActor () -> Void)? = nil
}

@MainActor
enum CommandKPickerPresentation {
    static let notification = Notification.Name("com.cosmo.commandKSelectionPicker")

    static func present(spaceID: String, targetUUID: String? = nil,
                        purpose: CommandKPickerPurpose = .addOriginals,
                        alreadyIncludedUUIDs: Set<String> = [],
                        onConfirm: (@MainActor ([String]) async throws -> Void)? = nil,
                        onComplete: (@MainActor () -> Void)? = nil) {
        let request = CommandKPickerRequest(spaceID: spaceID, targetUUID: targetUUID, purpose: purpose,
            alreadyIncludedUUIDs: alreadyIncludedUUIDs, onConfirm: onConfirm, onComplete: onComplete)
        NotificationCenter.default.post(name: notification, object: request)
    }
}

struct CommandKPickerSession {
    let request: CommandKPickerRequest
    var destination: CommandKSpaceContext?
    var scope: CommandKPickerScope = .entireLibrary
    var spaceUUIDs: Set<String> = []
    var includedUUIDs: Set<String> = []
    var selection: [String] = []
    var isLoading = true
    var isConfirming = false
    var error: String?

    var canConfirm: Bool { destination != nil && !isLoading && !isConfirming && !selection.isEmpty }
    var actionVerb: String { request.purpose == .attachReferences ? "Attach" : "Add" }
    var title: String { "\(actionVerb) to \(destination?.breadcrumb ?? "destination…")" }

    func canSelect(_ uuid: String) -> Bool {
        !isLoading && !isConfirming && uuid != request.spaceID && uuid != request.targetUUID && !includedUUIDs.contains(uuid)
    }

    mutating func toggle(_ uuid: String) {
        guard canSelect(uuid) else { return }
        if selection.contains(uuid) { selection.removeAll { $0 == uuid } }
        else { selection.append(uuid) }
        error = nil
    }

    func includesInScope(_ uuid: String) -> Bool { scope == .entireLibrary || spaceUUIDs.contains(uuid) }
}

@MainActor
extension CommandKViewModel {
    var isSelectionPicker: Bool { selectionPicker != nil }

    func beginSelectionPicker(_ request: CommandKPickerRequest) {
        clear()
        spaceContext = nil
        selectionPicker = .init(request: request, scope: request.targetUUID == nil ? .entireLibrary : .thisSpace)
        initialExpandedTab = .database
        transitionToExpanded(.database, loadDataImmediately: false)
        selectionPickerTask = Task { @MainActor in
            do {
                let loaded = try await CommandKSelectionPickerService.load(request)
                guard !Task.isCancelled, selectionPicker?.request.id == request.id else { return }
                selectionPicker?.destination = loaded.destination
                selectionPicker?.spaceUUIDs = loaded.spaceUUIDs
                selectionPicker?.includedUUIDs = loaded.includedUUIDs
                selectionPicker?.isLoading = false
                spaceContext = loaded.destination
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await performSearch(query: query)
                }
            } catch {
                guard !Task.isCancelled, selectionPicker?.request.id == request.id else { return }
                selectionPicker?.isLoading = false
                selectionPicker?.error = error.localizedDescription
            }
        }
    }

    func togglePickerSelection(_ uuid: String) { selectionPicker?.toggle(uuid) }

    func toggleCurrentPickerSelection() {
        guard let uuid = selectedNodeId,
              expandedDomainOpenTargets[uuid] != nil || unifiedFlatResults.contains(where: { $0.atomUUID == uuid }) else { return }
        togglePickerSelection(uuid)
    }

    func setPickerScope(_ scope: CommandKPickerScope) {
        selectionPicker?.scope = scope
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { @MainActor in await performSearch(query: query) }
    }

    func cancelSelectionPicker() {
        guard selectionPicker?.isConfirming != true else { return }
        selectionPickerTask?.cancel()
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    func confirmPickerSelection() {
        guard let session = selectionPicker, session.canConfirm, let destination = session.destination else { return }
        selectionPicker?.isConfirming = true
        selectionPicker?.error = nil
        selectionPickerTask = Task { @MainActor in
            do {
                // Re-read both membership and the captured kind. The service's
                // writer repeats structural validation inside its transaction.
                let loaded = try await CommandKSelectionPickerService.load(session.request)
                guard loaded.destination.containerKind == destination.containerKind else {
                    throw CommandKSpaceError.destinationUnavailable
                }
                let ids = session.selection.filter { !loaded.includedUUIDs.contains($0) }
                guard !Task.isCancelled, selectionPicker?.request.id == session.request.id else { return }
                if !ids.isEmpty {
                    if let confirm = session.request.onConfirm { try await confirm(ids) }
                    else { try await CommandKSpaceService.addOriginals(ids, to: destination) }
                }
                guard selectionPicker?.request.id == session.request.id else { return }
                selectionPicker?.isConfirming = false
                session.request.onComplete?()
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            } catch {
                guard selectionPicker?.request.id == session.request.id else { return }
                selectionPicker?.isConfirming = false
                selectionPicker?.error = error.localizedDescription
            }
        }
    }
}

@MainActor
enum CommandKSelectionPickerService {
    struct Loaded {
        let destination: CommandKSpaceContext
        let spaceUUIDs: Set<String>
        let includedUUIDs: Set<String>
    }

    static func load(_ request: CommandKPickerRequest) async throws -> Loaded {
        guard let space = try await AtomRepository.shared.fetch(uuid: request.spaceID),
              space.type == .thinkspace, !space.isDeleted else { throw CommandKSpaceError.destinationUnavailable }
        // Opening a selector must not run the workspace's legacy migration.
        let snapshot = try await CosmoDatabase.shared.asyncRead { db in
            try SpaceCompositionService.captureSnapshot(in: request.spaceID, db: db)
        }
        let root = CommandKSpaceContext(spaceID: request.spaceID, spaceTitle: space.title ?? "Untitled Space")
        let destination: CommandKSpaceContext
        var included = request.alreadyIncludedUUIDs
        if let uuid = request.targetUUID {
            guard let atom = snapshot.atomsByUUID[uuid], let kind = atom.spaceCompositionKind else {
                throw CommandKSpaceError.destinationUnavailable
            }
            if request.purpose == .attachReferences, !kind.isAuthored { throw CommandKSpaceError.invalidDestination }
            destination = CommandKSpaceService.context(for: atom, in: root, snapshot: snapshot)
            if request.purpose != .placeOnCanvas {
                let metadata = snapshot.metadataByUUID[uuid]
                if kind == .group { included.formUnion(metadata?.memberUUIDs ?? []) }
                else { included.formUnion((metadata?.references ?? []).map(\.sourceUUID)) }
            }
        } else {
            guard request.purpose != .attachReferences else { throw CommandKSpaceError.invalidDestination }
            destination = root
            if request.purpose != .placeOnCanvas { included.formUnion(snapshot.atomsByUUID.keys) }
        }
        if request.purpose == .placeOnCanvas, request.onConfirm == nil { throw CommandKSpaceError.invalidDestination }
        return .init(destination: destination, spaceUUIDs: Set(snapshot.atomsByUUID.keys), includedUUIDs: included)
    }
}

struct CommandKPickerHeader: View {
    var viewModel: CommandKViewModel

    var body: some View {
        if let session = viewModel.selectionPicker {
            HStack(spacing: DS.space12) {
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(session.title).font(DS.callout.weight(.semibold)).lineLimit(1).help(session.title)
                    Text("Preview any item, then select the originals to include.")
                        .font(DS.caption).foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: DS.space12)
                Picker("Search scope", selection: Binding(
                    get: { viewModel.selectionPicker?.scope ?? .entireLibrary },
                    set: { viewModel.setPickerScope($0) }
                )) {
                    ForEach(CommandKPickerScope.allCases, id: \.self) { scope in Text(scope.rawValue).tag(scope) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .disabled(session.isConfirming)
            }
            .padding(.horizontal, DS.space20).padding(.vertical, DS.space12)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.commandChromeSeparatorStrong).frame(height: 0.5) }
        }
    }
}

struct CommandKPickerFooter: View {
    var viewModel: CommandKViewModel

    var body: some View {
        if let session = viewModel.selectionPicker {
            VStack(alignment: .leading, spacing: DS.space8) {
                if let error = session.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(DS.caption).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Could not add items. \(error)")
                }
                HStack(spacing: DS.space12) {
                    Text(session.isLoading ? "Loading destination…" : "\(session.selection.count) selected")
                        .font(DS.caption).foregroundStyle(DS.textSecondary)
                    Spacer()
                    Text("↵ Select").font(DS.caption2).foregroundStyle(DS.textMuted)
                    Button("Cancel") { viewModel.cancelSelectionPicker() }
                        .buttonStyle(.borderless).disabled(session.isConfirming)
                    Button { viewModel.confirmPickerSelection() } label: {
                        HStack(spacing: DS.space6) {
                            if session.isConfirming { ProgressView().controlSize(.small) }
                            Text(session.isConfirming ? "Adding…" : "\(session.actionVerb) \(session.selection.count)")
                            Text("⌘↵").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(DS.accent)
                    .disabled(!session.canConfirm)
                    .accessibilityLabel("\(session.actionVerb) \(session.selection.count) selected items")
                }
            }
            .padding(.horizontal, DS.space20).padding(.vertical, DS.space12)
            .overlay(alignment: .top) { Rectangle().fill(DS.commandChromeSeparatorStrong).frame(height: 0.5) }
        }
    }
}
