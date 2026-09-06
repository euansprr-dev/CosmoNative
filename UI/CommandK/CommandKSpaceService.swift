import Foundation

enum CommandKOpenPresentation: Equatable {
    case workspace
    case focusMode

    var paletteDismissalNotification: Notification.Name {
        self == .focusMode ? CosmoNotification.NodeGraph.hideCommandK : CosmoNotification.NodeGraph.closeCommandK
    }
}

/// Adapts Command-K verbs to the existing Space writers and navigation stores.
/// It owns no documents, membership cache, canvas engine or persistence schema.
@MainActor
enum CommandKSpaceService {
    static let willOpenWorkspace = Notification.Name("com.cosmo.commandK.willOpenWorkspace")

    private static func leaveFocusForWorkspace() {
        NotificationCenter.default.post(name: willOpenWorkspace, object: nil)
        FocusNavigationCoordinator.shared.close()
    }

    static func validate(_ destination: CommandKSpaceContext) async throws -> SpaceCompositionSnapshot {
        let snapshot = try await SpaceCompositionService.load(in: destination.spaceID)
        if let uuid = destination.containerUUID {
            guard let atom = snapshot.atomsByUUID[uuid], atom.spaceCompositionKind == destination.containerKind else {
                throw CommandKSpaceError.destinationUnavailable
            }
        }
        try Task.checkCancellation()
        return snapshot
    }

    static func destinations(in root: CommandKSpaceContext) async throws -> [CommandKSpaceContext] {
        let snapshot = try await validate(root.root)
        return [root.root] + snapshot.atomsByUUID.values
            .filter { $0.spaceCompositionKind != nil }
            .map { context(for: $0, in: root.root, snapshot: snapshot) }
            .sorted { $0.breadcrumb.localizedStandardCompare($1.breadcrumb) == .orderedAscending }
    }

    static func context(for atom: Atom, in root: CommandKSpaceContext,
                        snapshot: SpaceCompositionSnapshot) -> CommandKSpaceContext {
        let path = navigationPath(to: atom.uuid, in: snapshot)
        return .init(spaceID: root.spaceID, spaceTitle: root.spaceTitle,
            containerUUID: atom.uuid, containerTitle: atom.title ?? "Untitled",
            containerKind: atom.spaceCompositionKind,
            path: path.map { $0.title ?? "Untitled" })
    }

    /// Authored parents take precedence; a retained Group member also gets a
    /// navigable path when it has no direct placement of its own.
    static func navigationPath(to uuid: String, in snapshot: SpaceCompositionSnapshot) -> [Atom] {
        var visited = Set<String>()
        func visit(_ id: String) -> [Atom] {
            guard visited.insert(id).inserted, let atom = snapshot.atomsByUUID[id] else { return [] }
            if let parent = snapshot.metadataByUUID[id]?.parentUUID, snapshot.atomsByUUID[parent] != nil {
                return visit(parent) + [atom]
            }
            let group = snapshot.atomsByUUID.values.filter {
                $0.uuid != id && snapshot.metadataByUUID[$0.uuid]?.kind == .group &&
                    snapshot.metadataByUUID[$0.uuid]?.memberUUIDs.contains(id) == true
            }.sorted { $0.uuid < $1.uuid }.first
            return (group.map { visit($0.uuid) } ?? []) + [atom]
        }
        return visit(uuid)
    }

    static func searchInfo(for atom: Atom, preferredSpaceID: String?,
                           locations supplied: [SpaceSearchLocation]? = nil) async throws -> CommandKSpaceSearchInfo {
        let locations: [SpaceSearchLocation]
        if let supplied { locations = supplied }
        else { locations = try await AtomRepository.shared.searchSpaceLocations(for: [atom.uuid])[atom.uuid] ?? [] }
        let ordered = locations.sorted { lhs, rhs in
            if lhs.spaceID == preferredSpaceID { return true }
            if rhs.spaceID == preferredSpaceID { return false }
            return lhs.spaceTitle.localizedStandardCompare(rhs.spaceTitle) == .orderedAscending
        }
        return .init(kind: atom.spaceCompositionKind, locations: ordered.map {
            .init(spaceID: $0.spaceID, spaceTitle: $0.spaceTitle, path: Array($0.path.dropFirst()))
        })
    }

    static func create(kind: SpaceCompositionKind, title: String, body: String,
                       destination: CommandKSpaceContext?) async throws -> Atom {
        guard let destination else {
            guard kind == .page else { throw CommandKSpaceError.chooseSpace }
            return try await AtomRepository.shared.create(Atom.new(type: .note, title: title, body: body))
        }
        guard destination.supportsCreation(kind) else { throw CommandKSpaceError.invalidDestination }
        _ = try await validate(destination)
        let group = destination.containerKind == .group ? destination.containerUUID : nil
        if kind == .book || kind == .course || kind == .guide {
            return try await SpaceCompositionService.createStarter(kind, title: title,
                in: destination.spaceID, groupUUID: group)
        }
        let parent = destination.containerKind?.isAuthored == true ? destination.containerUUID : nil
        return try await SpaceCompositionService.create(kind: kind, title: title, in: destination.spaceID,
            parentUUID: parent, body: body, groupUUID: group)
    }

    static func addOriginals(_ uuids: [String], to destination: CommandKSpaceContext) async throws {
        let ids = Array(Set(uuids)).sorted()
        guard !ids.isEmpty else { return }
        let snapshot = try await validate(destination)
        let originals = try await AtomRepository.shared.fetchBatch(uuids: ids)
        guard originals.count == ids.count, originals.allSatisfy({
            !$0.isDeleted && $0.uuid != destination.spaceID &&
                ![AtomType.thinkspace, .deepDive, .inquirySession].contains($0.type)
        }) else { throw CommandKSpaceError.originalUnavailable }
        if let target = destination.containerUUID {
            if destination.containerKind == .group {
                try await SpaceCompositionService.addMembers(ids, to: target, in: destination.spaceID)
            } else {
                let existing = snapshot.metadataByUUID[target]?.references ?? []
                let references = ids.filter { id in
                    !existing.contains { $0.id == "source:\(target):\(id)" ||
                        ($0.sourceUUID == id && $0.excerpt == nil && $0.anchor == nil) }
                }.map { SpaceCompositionReference(id: "source:\(target):\($0)", sourceUUID: $0) }
                try await SpaceCompositionService.attachReferences(references, to: target,
                    in: destination.spaceID, expectedKind: destination.containerKind, preserveExisting: true)
            }
        } else {
            try await SpaceCompositionService.addOriginals(ids, in: destination.spaceID)
        }
        await SpaceWorkspaceStore.shared.load(destination.spaceID)
    }

    static func openSpace(_ spaceID: String, map: Bool = false) async throws {
        _ = try await switchSpace(spaceID)
        leaveFocusForWorkspace()
        if map { SpaceMapNavigation.open(in: spaceID) }
        else { SpaceWorkspaceStore.shared.showRoot(.canvas, in: spaceID) }
        postSpaceNavigation(spaceID)
    }

    /// An explicit result location must remain exact. A palette origin is only
    /// a preference among reachable Spaces; opening never adds membership.
    @discardableResult
    static func openAtom(_ uuid: String, exactSpaceID: String? = nil, preferredSpaceID: String? = nil,
                         revealLocation: Bool = false, landingBlockID: UUID? = nil) async throws -> CommandKOpenPresentation {
        guard let atom = try await AtomRepository.shared.fetch(uuid: uuid), !atom.isDeleted else {
            throw CommandKSpaceError.originalUnavailable
        }
        if atom.type == .thinkspace { try await openSpace(atom.uuid); return .workspace }
        let shouldResolveSpace = atom.spaceCompositionKind != nil || exactSpaceID != nil || revealLocation
        let locations = shouldResolveSpace ? try await AtomRepository.shared.searchSpaceLocations(for: [uuid])[uuid] ?? [] : []
        let memberships = locations.map(\.spaceID)
        if let exactSpaceID, !memberships.contains(exactSpaceID) { throw CommandKSpaceError.destinationUnavailable }
        let destination = PageOpenLocationPolicy.destination(exactSpaceID: exactSpaceID,
            preferredSpaceID: preferredSpaceID, reachableSpaceIDs: memberships,
            compositionKind: atom.spaceCompositionKind)
        if PageOpenLocationPolicy.requiresSpace(for: atom.spaceCompositionKind), destination == nil {
            throw CommandKSpaceError.destinationUnavailable
        }
        if let destination {
            let snapshot = try await SpaceCompositionService.load(in: destination)
            guard snapshot.atomsByUUID[uuid] != nil else { throw CommandKSpaceError.destinationUnavailable }
            _ = try await switchSpace(destination)
            let store = SpaceWorkspaceStore.shared
            await store.load(destination)
            // Loading may yield after another result supersedes this request.
            // Never publish that stale result's workspace location or trail.
            try Task.checkCancellation()
            guard store.snapshots[destination]?.atomsByUUID[uuid] != nil else { throw CommandKSpaceError.destinationUnavailable }
            if atom.spaceCompositionKind != nil {
                leaveFocusForWorkspace()
                // Rebuild the ancestry rather than inheriting a previous object's
                // unrelated navigation path from the saved workspace location.
                store.leaveObject(in: destination)
                let ancestors = locations.first { $0.spaceID == destination }?.ancestorUUIDs ?? []
                for parent in ancestors.compactMap({ snapshot.atomsByUUID[$0] }) { store.open(parent, in: destination) }
                store.open(atom, in: destination, landingBlockID: landingBlockID)
                postSpaceNavigation(destination)
                return .workspace
            }
            // Native originals retain their reader, with the containing Space
            // behind it. A retained Group member stays selected in that Group.
            if let parentID = locations.first(where: { $0.spaceID == destination })?.ancestorUUIDs.last,
               let parent = snapshot.atomsByUUID[parentID] {
                store.open(parent, in: destination); store.select(uuid, in: destination)
            }
            postSpaceNavigation(destination)
        }
        try Task.checkCancellation()
        FocusNavigationCoordinator.shared.open(atomUUID: uuid, landingBlockID: landingBlockID)
        return .focusMode
    }

    private static func switchSpace(_ id: String) async throws -> Thinkspace {
        guard let atom = try await AtomRepository.shared.fetch(uuid: id), atom.type == .thinkspace, !atom.isDeleted else {
            throw CommandKSpaceError.destinationUnavailable
        }
        let manager = ThinkspaceManager.shared
        if !manager.thinkspaces.contains(where: { $0.id == id }) { await manager.loadThinkspaces() }
        guard let space = manager.thinkspaces.first(where: { $0.id == id }) else { throw CommandKSpaceError.destinationUnavailable }
        try Task.checkCancellation()
        if manager.currentThinkspace?.id != id { await manager.switchTo(space) }
        try Task.checkCancellation()
        return space
    }

    private static func postSpaceNavigation(_ id: String) {
        NotificationCenter.default.post(name: CosmoNotification.Navigation.navigateToThinkspaceById,
            object: nil, userInfo: CosmoNotification.Navigation.ThinkspacePayload(thinkspaceId: id).userInfo)
    }
}
