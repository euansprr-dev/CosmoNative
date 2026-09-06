import Foundation

@MainActor
struct CommandKActionRegistry {
    func actions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        var actions: [CommandKContextualAction] = []
        actions.append(contentsOf: universalActions(for: context))
        actions.append(contentsOf: spaceActions(for: context))
        actions.append(contentsOf: swipeActions(for: context))
        actions.append(contentsOf: inquiryActions(for: context))
        actions.append(contentsOf: commandCenterActions(for: context))
        actions.append(contentsOf: workspaceActions(for: context))
        return Self.orderedActions(actions)
    }

    /// Stable partition shared by the keyboard panel and native context menus.
    /// Domain actions may append in any order; destructive actions always trail.
    static func orderedActions(_ actions: [CommandKContextualAction]) -> [CommandKContextualAction] {
        actions.filter { $0.role != .destructive && $0.id != .deleteObject }
            + actions.filter { $0.role == .destructive && $0.id != .deleteObject }
            + actions.filter { $0.id == .deleteObject }
    }

    private func spaceActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        var actions: [CommandKContextualAction] = []
        if context.selectionKind == .thinkspace, let id = context.selectedSpaceID {
            actions.append(.init(id: .openFocusMode, category: .primary, title: "Open Space", subtitle: nil,
                systemImage: "folder", shortcut: .returnKey, role: .normal, availability: .enabled,
                intent: .openSpace(spaceID: id, map: false)))
            actions.append(.init(id: .openAsPane, category: .object, title: "Open as Pane", subtitle: nil,
                systemImage: "rectangle.split.2x1", shortcut: .commandReturn, role: .normal, availability: .enabled,
                intent: .postNotification(name: CosmoNotification.Navigation.openAsPane, userInfo: ["thinkspaceId": id])))
        }
        if let id = context.selectedSpaceID ?? context.spaceContext?.spaceID {
            actions.append(.init(id: .openSpaceMap, category: .workspace, title: "Open Space map",
                subtitle: context.selectedSpaceInfo?.location?.spaceTitle ?? context.spaceContext?.spaceTitle,
                systemImage: "point.3.connected.trianglepath.dotted", shortcut: nil, role: .normal,
                availability: .enabled, intent: .openSpace(spaceID: id, map: true)))
        }
        guard context.canAddOriginal else { return actions }
        if let destination = context.spaceContext {
            let isSelf = context.originalUUIDs.contains(destination.containerUUID ?? destination.spaceID)
            actions.append(.init(id: .addToComposition, category: .object, title: destination.addTitle,
                subtitle: destination.addExplanation, systemImage: destination.containerKind?.isAuthored == true ? "link.badge.plus" : "plus.rectangle.on.rectangle",
                shortcut: .optionReturn, role: .normal,
                availability: isSelf ? .disabled(reason: "An item cannot contain itself") : .enabled,
                intent: .addOriginals(uuids: context.originalUUIDs, destination: destination)))
        }
        actions.append(.init(id: .addToSpace, category: .object, title: "Add to Space…",
            subtitle: "Choose a Space, Group, or Page", systemImage: "folder.badge.plus", shortcut: context.spaceContext == nil ? .optionReturn : nil,
            role: .normal, availability: .enabled, intent: .pickSpaceDestination(uuids: context.originalUUIDs)))
        return actions
    }

    // MARK: - Workspace (benches + places)

    /// Workbenches and the current thinkspace's Places, as one action each.
    private func workspaceActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        var actions: [CommandKContextualAction] = []

        for bench in WorkbenchStore.shared.workbenches.prefix(9) {
            actions.append(CommandKContextualAction(
                id: .applyWorkbench,
                category: .workspace,
                title: bench.name,
                subtitle: "Workbench",
                systemImage: bench.glyph,
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .postNotification(
                    name: CosmoNotification.Navigation.applyWorkbench,
                    userInfo: ["uuid": bench.uuid]
                ),
                payloadKey: bench.uuid
            ))
        }

        for place in (context.spaceContext?.containerUUID == nil && context.spaceContext?.spaceID == ThinkspaceManager.shared.currentThinkspace?.id
            ? ThinkspaceManager.shared.currentPlaces : []).prefix(9) {
            actions.append(CommandKContextualAction(
                id: .jumpToPlace,
                category: .workspace,
                title: place.name,
                subtitle: "Place in this Space",
                systemImage: "mappin.and.ellipse",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .postNotification(
                    name: CosmoNotification.Navigation.jumpToPlace,
                    userInfo: ["placeUUID": place.uuid]
                ),
                payloadKey: place.uuid
            ))
        }

        return actions
    }

    func groupedActions(for context: CommandKActionContext) -> [(category: CommandKActionCategory, actions: [CommandKContextualAction])] {
        let allActions = actions(for: context)
        var groups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])] = CommandKActionCategory.allCases.compactMap { category in
            let section = allActions.filter { $0.category == category && $0.role != .destructive && $0.id != .deleteObject }
            return section.isEmpty ? nil : (category, section)
        }
        let destructive = allActions.filter { $0.role == .destructive || $0.id == .deleteObject }
        if !destructive.isEmpty { groups.append((.destructive, destructive)) }
        return groups
    }

    private func universalActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        guard let uuid = context.selectedAtomUUID, context.selectionKind != .thinkspace else { return [] }
        return [
            CommandKContextualAction(
                id: .openFocusMode,
                category: .primary,
                title: context.selectedSpaceID == nil ? "Open" : "Open in Space",
                subtitle: nil,
                systemImage: "arrow.up.left.and.arrow.down.right",
                shortcut: .returnKey,
                role: .normal,
                availability: .enabled,
                intent: context.selectedSpaceID.map { .openSpaceItem(uuid: uuid, spaceID: $0) } ?? .openAtom(uuid: uuid)
            ),
            CommandKContextualAction(
                id: .openAsPane,
                category: .object,
                title: "Open as Pane",
                subtitle: nil,
                systemImage: "rectangle.split.2x1",
                shortcut: .commandReturn,
                role: .normal,
                availability: .enabled,
                intent: .openAsPane(uuid: uuid)
            ),
            CommandKContextualAction(
                id: .peekObject,
                category: .object,
                title: "Peek",
                subtitle: "Quick look without opening",
                systemImage: "eye",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .postNotification(
                    name: CosmoNotification.Navigation.peekEntity,
                    userInfo: ["uuid": uuid]
                )
            ),
            CommandKContextualAction(
                id: .goToObject,
                category: .object,
                title: "Go to containing Space",
                subtitle: nil,
                systemImage: "scope",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .goToObject(uuid: uuid)
            ),
            CommandKContextualAction(
                id: .copyCosmoLink,
                category: .object,
                title: "Copy Cosmo Link",
                subtitle: nil,
                systemImage: "link",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .copyCosmoLink(uuid: uuid)
            ),
            CommandKContextualAction(
                id: .deleteObject,
                category: .destructive,
                title: "Delete",
                subtitle: nil,
                systemImage: "trash",
                shortcut: nil,
                role: .destructive,
                availability: .enabled,
                intent: .deleteAtom(uuid: uuid)
            )
        ]
    }

    private func swipeActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        var actions: [CommandKContextualAction] = []

        if case .expandedDomain(.swipeGallery) = context.mode {
            actions.append(
                CommandKContextualAction(
                    id: .openSwipeGallery,
                    category: .primary,
                    title: "Open Swipe Gallery",
                    subtitle: "Open All Swipes full screen",
                    systemImage: "rectangle.stack.fill",
                    shortcut: nil,
                    role: .normal,
                    availability: .enabled,
                    intent: .postNotification(
                        name: CosmoNotification.Navigation.openSwipeGallery,
                        userInfo: [:]
                    )
                )
            )
            actions.append(
                CommandKContextualAction(
                    id: .openAsPane,
                    category: .object,
                    title: "Open as Pane",
                    subtitle: "Open All Swipes beside your workspace",
                    systemImage: "rectangle.split.2x1",
                    shortcut: .commandReturn,
                    role: .normal,
                    availability: .enabled,
                    intent: .openSwipeGalleryAsPane
                )
            )
        }

        guard case .swipe = context.selectionKind,
              let uuid = context.selectedAtomUUID else {
            return actions
        }

        let draftAvailability: CommandKActionAvailability = context.hasActiveContentDraft
            ? .enabled
            : .disabled(reason: "No active content draft")

        actions.append(contentsOf: [
            CommandKContextualAction(
                id: .openSwipeStudy,
                category: .swipe,
                title: "Open Swipe Study",
                subtitle: nil,
                systemImage: "bolt.fill",
                shortcut: .commandS,
                role: .normal,
                availability: .enabled,
                intent: .openAtom(uuid: uuid)
            ),
            CommandKContextualAction(
                id: .analyzeSwipeHook,
                category: .swipe,
                title: "Analyze Hook",
                subtitle: nil,
                systemImage: "wand.and.stars",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: "get_swipe_analysis", arguments: ["uuid": uuid])
            ),
            CommandKContextualAction(
                id: .attachSwipeToCurrentDraft,
                category: .swipe,
                title: "Attach to Current Draft",
                subtitle: nil,
                systemImage: "paperclip",
                shortcut: nil,
                role: .normal,
                availability: draftAvailability,
                intent: .executeTool(name: "attach_swipe_to_current_draft", arguments: ["uuid": uuid])
            ),
            CommandKContextualAction(
                id: .useSwipeAsBlueprint,
                category: .swipe,
                title: "Use as Blueprint",
                subtitle: nil,
                systemImage: "rectangle.stack.badge.plus",
                shortcut: nil,
                role: .normal,
                availability: draftAvailability,
                intent: .executeTool(name: "use_swipe_as_blueprint", arguments: ["uuid": uuid])
            ),
            CommandKContextualAction(
                id: .createIdeaFromSwipe,
                category: .swipe,
                title: "Create Idea from Swipe",
                subtitle: nil,
                systemImage: "lightbulb.fill",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: "create_idea_from_swipe", arguments: ["uuid": uuid])
            ),
            CommandKContextualAction(
                id: .findSimilarSwipes,
                category: .swipe,
                title: "Find Similar Swipes",
                subtitle: nil,
                systemImage: "point.3.connected.trianglepath.dotted",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: "find_similar_swipes", arguments: ["uuid": uuid])
            ),
            CommandKContextualAction(
                id: .batchReprocessSwipeMedia,
                category: .swipe,
                title: "Reprocess Swipe Media",
                subtitle: nil,
                systemImage: "arrow.triangle.2.circlepath",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .postNotification(
                    name: CosmoNotification.SwipeFile.batchSwipeAnalysisTriggered,
                    userInfo: ["atomUUID": uuid]
                )
            )
        ])

        return actions
    }

    private func inquiryActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        var actions: [CommandKContextualAction] = []

        if let uuid = context.selectedAtomUUID {
            let attachAvailability: CommandKActionAvailability = context.hasActiveInquirySession
                ? .enabled
                : .disabled(reason: "No active inquiry session")

            actions.append(
                CommandKContextualAction(
                    id: .addToActiveInquiry,
                    category: .inquiry,
                    title: "Add to Active Inquiry",
                    subtitle: nil,
                    systemImage: "tray.and.arrow.down.fill",
                    shortcut: nil,
                    role: .normal,
                    availability: attachAvailability,
                    intent: .executeTool(name: "add_to_active_inquiry", arguments: ["uuid": uuid])
                )
            )
            actions.append(
                CommandKContextualAction(
                    id: .startInquiryOnSelection,
                    category: .inquiry,
                    title: "Start Inquiry on This",
                    subtitle: nil,
                    systemImage: "sparkle.magnifyingglass",
                    shortcut: .commandI,
                    role: .normal,
                    availability: .enabled,
                    intent: .startInquiry(anchorUUID: uuid, anchorType: context.subject.typeLabel)
                )
            )
        }

        guard context.hasActiveInquirySession else { return actions }

        actions.append(
            CommandKContextualAction(
                id: .refreshInquirySources,
                category: .inquiry,
                title: "Refresh Inquiry Sources",
                subtitle: nil,
                systemImage: "arrow.clockwise",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .postNotification(name: CosmoNotification.Inquiry.refreshSources, userInfo: [:])
            )
        )
        actions.append(
            CommandKContextualAction(
                id: .crystallizeInquiry,
                category: .inquiry,
                title: "Crystallize Inquiry",
                subtitle: nil,
                systemImage: "seal.fill",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .postNotification(name: CosmoNotification.Inquiry.crystallizeActive, userInfo: [:])
            )
        )

        return actions
    }

    private func commandCenterActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        guard let uuid = context.selectedAtomUUID else { return [] }
        var actions = [
            CommandKContextualAction(
                id: .createTaskFromSelection,
                category: .commandCenter,
                title: "Create Review Task",
                subtitle: nil,
                systemImage: "checkmark.circle.fill",
                shortcut: .commandT,
                role: .normal,
                availability: .enabled,
                intent: .commandCenter(.createReviewTask(sourceUUID: uuid))
            )
        ]

        if case .atom(.task) = context.selectionKind {
            actions.append(
                CommandKContextualAction(
                    id: .startFocusTask,
                    category: .commandCenter,
                    title: "Start Focus",
                    subtitle: nil,
                    systemImage: "play.circle.fill",
                    shortcut: nil,
                    role: .normal,
                    availability: .enabled,
                    intent: .commandCenter(.startFocus(taskUUID: uuid))
                )
            )
            actions.append(
                CommandKContextualAction(
                    id: .markTaskDone,
                    category: .commandCenter,
                    title: "Mark Done",
                    subtitle: nil,
                    systemImage: "checkmark.seal.fill",
                    shortcut: nil,
                    role: .normal,
                    availability: .enabled,
                    intent: .commandCenter(.markDone(taskUUID: uuid))
                )
            )
            actions.append(
                CommandKContextualAction(
                    id: .deferTask,
                    category: .commandCenter,
                    title: "Defer One Day",
                    subtitle: nil,
                    systemImage: "calendar.badge.clock",
                    shortcut: nil,
                    role: .normal,
                    availability: .enabled,
                    intent: .commandCenter(.deferTask(taskUUID: uuid, days: 1))
                )
            )
            actions.append(
                CommandKContextualAction(
                    id: .scheduleTaskTomorrow,
                    category: .commandCenter,
                    title: "Schedule Tomorrow",
                    subtitle: nil,
                    systemImage: "calendar.badge.plus",
                    shortcut: nil,
                    role: .normal,
                    availability: .enabled,
                    intent: .commandCenter(.scheduleTomorrow(taskUUID: uuid))
                )
            )
        }

        return actions
    }
}
