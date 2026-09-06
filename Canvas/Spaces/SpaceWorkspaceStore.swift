import SwiftUI
import Combine

struct SpaceWorkspaceLocation: Codable, Equatable {
    var itemUUID: String?
    var view: SpaceCompositionView = .canvas
    var selectedUUID: String?
    var sourcesVisible = false
    var landingBlockID: UUID?
    var navigationPath: [String]?
}

extension SpaceCompositionView {
    var title: String { rawValue.capitalized }
}

/// Navigation is local to this device. Documents, order and references remain
/// in atoms; changing a view never writes or clones their content.
@MainActor @Observable
final class SpaceWorkspaceStore {
    static let shared = SpaceWorkspaceStore()
    private(set) var snapshots: [String: SpaceCompositionSnapshot] = [:]
    private(set) var locations: [String: SpaceWorkspaceLocation] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var busy: Set<String> = []
    @ObservationIgnored private var reloads: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []
    @ObservationIgnored private var mutationTails: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var mutationTokens: [String: UUID] = [:]
    @ObservationIgnored private var loadTokens: [String: UUID] = [:]

    init() {
        let names = [SpaceCompositionService.didChange, CosmoNotification.Entity.updated, CosmoNotification.Entity.created,
                     CosmoNotification.Sync.atomsPulled, Notification.Name("com.cosmo.canvasBlocksChanged")]
        for name in names {
            NotificationCenter.default.publisher(for: name)
                .debounce(for: .milliseconds(180), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        for id in snapshots.keys { scheduleReload(id) }
                    }
                }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: SpaceCompositionService.didFailUndo)
            .sink { [weak self] notification in
                let message = notification.userInfo?["message"] as? String ?? "The item changed elsewhere. Refresh before undoing."
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for id in snapshots.keys { errors[id] = message }
                }
            }.store(in: &subscriptions)
    }

    func location(_ spaceID: String) -> SpaceWorkspaceLocation {
        if let location = locations[spaceID] { return location }
        guard let data = UserDefaults.standard.data(forKey: key(spaceID)),
              let location = try? JSONDecoder().decode(SpaceWorkspaceLocation.self, from: data) else {
            return SpaceWorkspaceLocation()
        }
        return location
    }
    func selectedItem(in spaceID: String) -> Atom? {
        guard let id = location(spaceID).itemUUID else { return nil }
        return snapshots[spaceID]?.atomsByUUID[id]
    }
    func isPresenting(in spaceID: String) -> Bool { location(spaceID).itemUUID != nil }

    func open(_ atom: Atom, in spaceID: String, landingBlockID: UUID? = nil) {
        let previous = location(spaceID)
        let kind = atom.spaceCompositionKind
        let options = views(for: atom, in: spaceID)
        let preferred = atom.spaceComposition?.preferredView
        let view: SpaceCompositionView = preferred.flatMap { options.contains($0) ? $0 : nil } ??
            (kind == .group ? .grid : options.contains(.outline) ? .canvas : .write)
        let saved = UserDefaults.standard.data(forKey: itemKey(atom.uuid, in: spaceID))
            .flatMap { try? JSONDecoder().decode(SpaceWorkspaceLocation.self, from: $0) }
        var next = previous.itemUUID == atom.uuid ? previous : saved ?? .init(itemUUID: atom.uuid, view: view)
        next.itemUUID = atom.uuid
        next.landingBlockID = landingBlockID
        if landingBlockID != nil && options.contains(.write) { next.view = .write }
        var path = previous.navigationPath ?? []
        if let index = path.firstIndex(of: atom.uuid) { path = Array(path.prefix(index)) }
        else if let id = previous.itemUUID, id != atom.uuid { path.append(id) }
        next.navigationPath = path
        setLocation(next, in: spaceID)
        SpaceViewStore.shared.select(.canvas, for: spaceID)
        NavigationTrail.shared.recordArrival(.spaceItem(thinkspaceId: spaceID, itemUUID: atom.uuid),
            title: atom.title ?? "Untitled", glyph: atom.spaceCompositionKind?.symbol ?? "doc.text")
    }
    func showRoot(_ view: SpaceView, in spaceID: String) {
        leaveObject(in: spaceID)
        SpaceViewStore.shared.select(view, for: spaceID)
    }
    func leaveObject(in spaceID: String) { setLocation(SpaceWorkspaceLocation(), in: spaceID) }

    /// Following a reference never silently files its original into this Space.
    func openOriginal(_ atom: Atom, from spaceID: String, landingBlockID: UUID? = nil) async throws {
        if snapshots[spaceID]?.atomsByUUID[atom.uuid] != nil {
            open(atom, in: spaceID, landingBlockID: landingBlockID); return
        }
        // Try the known source first. Pages elsewhere can open independently;
        // containers need their reachable workspace to retain their contents.
        await load(spaceID)
        if snapshots[spaceID]?.atomsByUUID[atom.uuid] != nil {
            open(atom, in: spaceID, landingBlockID: landingBlockID); return
        }
        if PageOpenLocationPolicy.requiresSpace(for: atom.spaceCompositionKind) {
            try await CommandKSpaceService.openAtom(atom.uuid, preferredSpaceID: spaceID,
                landingBlockID: landingBlockID)
            return
        }
        if atom.type == .note {
            FocusNavigationCoordinator.shared.open(atomUUID: atom.uuid, landingBlockID: landingBlockID)
            return
        }
        throw SpaceCompositionError.notFound
    }
    func selectView(_ view: SpaceCompositionView, in spaceID: String) {
        var current = location(spaceID)
        guard current.view != view else { return }
        current.view = view; setLocation(current, in: spaceID)
    }
    func select(_ uuid: String?, in spaceID: String) {
        if let uuid, !validSelectionIDs(in: spaceID).contains(uuid) { return }
        var current = location(spaceID); current.selectedUUID = uuid; setLocation(current, in: spaceID)
    }
    private func validSelectionIDs(in spaceID: String) -> Set<String> {
        guard let container = selectedItem(in: spaceID), let snapshot = snapshots[spaceID] else { return [] }
        let items = container.spaceCompositionKind == .group ? snapshot.members(of: container.uuid) :
            snapshot.orderedSections(of: container.uuid, includedOnly: false).map(\.atom)
        return Set(items.map(\.uuid)).union([container.uuid])
    }
    func toggleSources(in spaceID: String) {
        var current = location(spaceID); current.sourcesVisible.toggle(); setLocation(current, in: spaceID)
    }
    func views(for atom: Atom, in spaceID: String) -> [SpaceCompositionView] {
        if atom.spaceCompositionKind == .group { return [.canvas, .grid, .list] }
        guard atom.spaceCompositionKind?.isAuthored == true else { return [] }
        if atom.spaceCompositionKind != .page || !(snapshots[spaceID]?.children(of: atom.uuid).isEmpty ?? true) {
            return [.canvas, .outline, .write]
        }
        return [.write]
    }
    func items(in atom: Atom, spaceID: String) -> [Atom] {
        guard let snapshot = snapshots[spaceID] else { return [] }
        return atom.spaceCompositionKind == .group ? snapshot.members(of: atom.uuid) : snapshot.children(of: atom.uuid)
    }
    func sourceTarget(in spaceID: String) -> Atom? {
        let current = location(spaceID)
        if let id = current.selectedUUID, let atom = snapshots[spaceID]?.atomsByUUID[id], atom.spaceCompositionKind != nil { return atom }
        return selectedItem(in: spaceID)
    }
    func inquirySources(in spaceID: String) -> [String] {
        if let id = location(spaceID).selectedUUID, let selected = snapshots[spaceID]?.atomsByUUID[id], selected.spaceCompositionKind == nil { return [id] }
        guard let atom = sourceTarget(in: spaceID) else { return [] }
        return [atom.uuid] + (atom.spaceComposition?.references.map(\.sourceUUID) ?? [])
    }
    func load(_ spaceID: String) async {
        let token = UUID(); loadTokens[spaceID] = token
        do {
            let snapshot = try await SpaceCompositionService.load(in: spaceID)
            guard !Task.isCancelled, loadTokens[spaceID] == token else { return }
            snapshots[spaceID] = snapshot; errors[spaceID] = nil
            if let id = location(spaceID).itemUUID, snapshot.atomsByUUID[id] == nil {
                setLocation(SpaceWorkspaceLocation(), in: spaceID)
            }
            if let atom = selectedItem(in: spaceID) {
                var current = location(spaceID)
                let available = views(for: atom, in: spaceID)
                if !available.contains(current.view), let view = available.first { current.view = view }
                if let id = current.selectedUUID, !validSelectionIDs(in: spaceID).contains(id) { current.selectedUUID = nil }
                if current != location(spaceID) { setLocation(current, in: spaceID) }
            }
            // Keep a bounded working set. Restored navigation stays in preferences.
            if snapshots.count > 8, let victim = snapshots.keys.sorted().first(where: { $0 != spaceID }) {
                snapshots[victim] = nil
            }
        } catch { if !Task.isCancelled && loadTokens[spaceID] == token { errors[spaceID] = error.localizedDescription } }
    }
    func perform(in spaceID: String, _ operation: @escaping @MainActor () async throws -> Void) {
        let previous = mutationTails[spaceID]
        let token = UUID()
        mutationTokens[spaceID] = token
        busy.insert(spaceID)
        mutationTails[spaceID] = Task { @MainActor in
            await previous?.value
            defer {
                if mutationTokens[spaceID] == token {
                    busy.remove(spaceID); mutationTails[spaceID] = nil; mutationTokens[spaceID] = nil
                }
            }
            do { try await operation(); await load(spaceID) }
            catch { errors[spaceID] = error.localizedDescription }
        }
    }
    func report(_ error: Error, in spaceID: String) { errors[spaceID] = error.localizedDescription }
    private func scheduleReload(_ id: String) {
        reloads[id]?.cancel()
        reloads[id] = Task { [weak self] in await self?.load(id) }
    }
    private func key(_ id: String) -> String { "cosmo.space.workspace.mac.\(id)" }
    private func itemKey(_ uuid: String, in spaceID: String) -> String { key(spaceID) + ".item." + uuid }
    private func setLocation(_ location: SpaceWorkspaceLocation, in spaceID: String) {
        locations[spaceID] = location
        if let data = try? JSONEncoder().encode(location) {
            UserDefaults.standard.set(data, forKey: key(spaceID))
            if let uuid = location.itemUUID { UserDefaults.standard.set(data, forKey: itemKey(uuid, in: spaceID)) }
        }
    }
}
