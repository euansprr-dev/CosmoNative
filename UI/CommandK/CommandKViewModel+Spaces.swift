import Foundation

extension CommandKViewModel {
    func captureSpaceContext(_ context: CommandKSpaceContext?) {
        spaceContext = context
        spaceDestinationPicker = nil
        spacePickerTask?.cancel()
    }

    func hydrateSpaceSelection(_ uuid: String?) async {
        selectedSpaceAtom = nil
        selectedSpaceInfo = nil
        guard let uuid, let atom = try? await AtomRepository.shared.fetch(uuid: uuid), !Task.isCancelled else { return }
        let info = try? await CommandKSpaceService.searchInfo(for: atom, preferredSpaceID: spaceContext?.spaceID)
        guard !Task.isCancelled else { return }
        selectedSpaceAtom = atom
        selectedSpaceInfo = info
    }

    func addSelectedOriginals(fallbackUUID uuid: String) {
        let ids = selectedUUIDs.contains(uuid) ? selectedUUIDs.sorted() : [uuid]
        guard let destination = spaceContext else { showSpaceDestinationPicker(.add(ids)); return }
        executeSpaceAction(.addOriginals(uuids: ids, destination: destination))
    }

    func executeSpaceAction(_ intent: CommandKActionIntent) {
        guard !isSelectionPicker, !isExecutingAction else { return }
        switch intent {
        case .pickSpaceDestination(let ids): showSpaceDestinationPicker(.add(ids)); return
        case .browseSpaceDestinations(let root): browseSpaceDestinations(root); return
        case .backToSpaces:
            if let purpose = spaceDestinationPicker?.purpose { showSpaceDestinationPicker(purpose) }
            return
        case .chooseSpaceDestination(let destination):
            chooseSpaceDestination(destination); return
        default: break
        }
        let origin = spaceContext
        isExecutingAction = true
        actionStatusMessage = nil
        Task { @MainActor in
            defer { isExecutingAction = false }
            do {
                switch intent {
                case .openAtom(let uuid):
                    let presentation = try await CommandKSpaceService.openAtom(uuid, preferredSpaceID: origin?.spaceID)
                    NotificationCenter.default.post(name: presentation.paletteDismissalNotification, object: nil)
                case .goToObject(let uuid):
                    let presentation = try await CommandKSpaceService.openAtom(uuid, preferredSpaceID: origin?.spaceID, revealLocation: true)
                    NotificationCenter.default.post(name: presentation.paletteDismissalNotification, object: nil)
                default: try await CommandKActionExecutor().execute(intent)
                }
                if case .addOriginals(_, let destination) = intent {
                    actionStatusMessage = destination.containerKind?.isAuthored == true
                        ? "Source attached to \(destination.title)" : "Added to \(destination.title)"
                }
                isActionPanelPresented = false
                spaceDestinationPicker = nil
            } catch {
                actionStatusMessage = error.localizedDescription
            }
        }
    }

    func addDroppedOriginals(_ uuids: [String], to targetUUID: String, exactSpaceID: String?) {
        guard !isSelectionPicker, !isExecutingAction else { return }
        let origin = spaceContext
        isExecutingAction = true
        actionStatusMessage = nil
        Task { @MainActor in
            defer { isExecutingAction = false }
            do {
                guard let target = try await AtomRepository.shared.fetch(uuid: targetUUID), !target.isDeleted else {
                    throw CommandKSpaceError.destinationUnavailable
                }
                let destination: CommandKSpaceContext
                if target.type == .thinkspace {
                    destination = .init(spaceID: target.uuid, spaceTitle: target.title ?? "Untitled Space")
                } else {
                    guard target.spaceCompositionKind != nil else { throw CommandKSpaceError.invalidDestination }
                    let info = try await CommandKSpaceService.searchInfo(for: target,
                        preferredSpaceID: exactSpaceID ?? origin?.spaceID)
                    guard let root = info.locations.first(where: { exactSpaceID == nil || $0.spaceID == exactSpaceID }) else {
                        throw CommandKSpaceError.destinationUnavailable
                    }
                    let snapshot = try await CommandKSpaceService.validate(root)
                    destination = CommandKSpaceService.context(for: target, in: root, snapshot: snapshot)
                }
                try await CommandKSpaceService.addOriginals(uuids, to: destination)
                actionStatusMessage = destination.containerKind?.isAuthored == true
                    ? "Source attached to \(destination.title)" : "Added to \(destination.title)"
            } catch { actionStatusMessage = error.localizedDescription }
        }
    }

    func showSpaceDestinationPicker(_ purpose: CommandKSpaceDestinationPurpose) {
        spacePickerTask?.cancel()
        actionStatusMessage = nil
        spaceDestinationPicker = .init(purpose: purpose, isLoading: true)
        isActionPanelPresented = true
        spacePickerTask = Task { @MainActor in
            if ThinkspaceManager.shared.thinkspaces.isEmpty { await ThinkspaceManager.shared.loadThinkspaces() }
            guard !Task.isCancelled, spaceDestinationPicker?.purpose == purpose else { return }
            let roots = ThinkspaceManager.shared.sidebarThinkspaces.map {
                CommandKSpaceContext(spaceID: $0.id, spaceTitle: $0.name)
            }.sorted {
                if $0.spaceID == spaceContext?.spaceID { return true }
                if $1.spaceID == spaceContext?.spaceID { return false }
                return $0.spaceTitle.localizedStandardCompare($1.spaceTitle) == .orderedAscending
            }
            spaceDestinationPicker = .init(purpose: purpose, destinations: roots)
            if roots.isEmpty { actionStatusMessage = "Create a Space first, then choose it here." }
        }
    }

    func browseSpaceDestinations(_ root: CommandKSpaceContext) {
        guard let purpose = spaceDestinationPicker?.purpose else { return }
        if purpose == .map || purpose == .open { chooseSpaceDestination(root); return }
        spacePickerTask?.cancel()
        actionStatusMessage = nil
        spaceDestinationPicker = .init(purpose: purpose, root: root, isLoading: true)
        spacePickerTask = Task { @MainActor in
            do {
                let destinations = try await CommandKSpaceService.destinations(in: root)
                guard !Task.isCancelled, spaceDestinationPicker?.root?.spaceID == root.spaceID else { return }
                spaceDestinationPicker = .init(purpose: purpose, root: root,
                    destinations: destinations.filter { destination in
                        switch purpose {
                        case .create(let kind): return destination.supportsCreation(kind)
                        case .add(let ids): return !ids.contains(destination.containerUUID ?? destination.spaceID)
                        case .map, .open: return destination.containerUUID == nil
                        }
                    })
            } catch {
                guard !Task.isCancelled else { return }
                spaceDestinationPicker?.isLoading = false
                actionStatusMessage = error.localizedDescription
            }
        }
    }

    private func chooseSpaceDestination(_ destination: CommandKSpaceContext?) {
        guard let purpose = spaceDestinationPicker?.purpose else { return }
        switch purpose {
        case .create(let kind):
            guard kind == .page || destination != nil else { return }
            composerDraft?.destination = destination
            spaceDestinationPicker = nil
            isActionPanelPresented = false
            actionStatusMessage = nil
        case .add(let ids):
            guard let destination else { return }
            executeSpaceAction(.addOriginals(uuids: ids, destination: destination))
        case .map, .open:
            guard let destination else { return }
            executeSpaceAction(.openSpace(spaceID: destination.spaceID, map: purpose == .map))
        }
    }

    func dismissSpaceDestinationPicker() {
        spacePickerTask?.cancel()
        spaceDestinationPicker = nil
        isActionPanelPresented = false
    }

    var spaceDestinationActions: [(category: CommandKActionCategory, actions: [CommandKContextualAction])] {
        guard let picker = spaceDestinationPicker else { return [] }
        var actions: [CommandKContextualAction] = []
        func action(_ id: CommandKContextualActionID, _ title: String, _ subtitle: String?, _ symbol: String,
                    _ intent: CommandKActionIntent, key: String? = nil) -> CommandKContextualAction {
            .init(id: id, category: .workspace, title: title, subtitle: subtitle, systemImage: symbol,
                  shortcut: nil, role: .normal, availability: isExecutingAction ? .disabled(reason: "Saving…") : .enabled,
                  intent: intent, payloadKey: key)
        }
        if picker.root != nil {
            actions.append(action(.backToSpaces, "Back to Spaces", nil, "chevron.left", .backToSpaces))
        } else if picker.purpose == .create(.page) {
            actions.append(action(.chooseSpaceDestination, "Outside a Space", "Create a Page in your Library", "doc.text",
                .chooseSpaceDestination(nil), key: "library"))
        }
        for destination in picker.destinations {
            let choose = picker.root != nil || picker.purpose == .map || picker.purpose == .open
            let title: String
            if destination.containerUUID == nil, picker.root != nil { title = "\(destination.spaceTitle) · Space root" }
            else { title = destination.title }
            actions.append(action(choose ? .chooseSpaceDestination : .browseSpaceDestinations, title,
                destination.containerUUID == nil ? (choose ? "Space" : "Choose the Space or an item inside it") : destination.breadcrumb,
                destination.symbol, choose ? .chooseSpaceDestination(destination) : .browseSpaceDestinations(destination), key: destination.id))
        }
        return [(.workspace, actions)]
    }

    var spaceDestinationPickerTitle: String {
        guard let purpose = spaceDestinationPicker?.purpose else { return "Choose destination" }
        switch purpose {
        case .create: return "Create in…"
        case .add: return "Add original to…"
        case .map: return "Open Space map"
        case .open: return "Open Space"
        }
    }

    func openCreatedComposition(_ uuid: String, destination: CommandKSpaceContext?) async throws {
        let presentation = try await CommandKSpaceService.openAtom(uuid, exactSpaceID: destination?.spaceID)
        actionStatusMessage = nil
        NotificationCenter.default.post(name: presentation.paletteDismissalNotification, object: nil)
    }
}
