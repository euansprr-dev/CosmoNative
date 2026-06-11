import Foundation

@MainActor
struct CommandKActionRegistry {
    func actions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        var actions: [CommandKContextualAction] = []
        actions.append(contentsOf: universalActions(for: context))
        actions.append(contentsOf: swipeActions(for: context))
        actions.append(contentsOf: inquiryActions(for: context))
        actions.append(contentsOf: commandCenterActions(for: context))
        actions.append(contentsOf: workspaceActions(for: context))
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

        for place in ThinkspaceManager.shared.currentPlaces.prefix(9) {
            actions.append(CommandKContextualAction(
                id: .jumpToPlace,
                category: .workspace,
                title: place.name,
                subtitle: "Place in this thinkspace",
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
        return CommandKActionCategory.allCases.compactMap { category in
            let section = allActions.filter { $0.category == category }
            return section.isEmpty ? nil : (category, section)
        }
    }

    private func universalActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        guard let uuid = context.selectedAtomUUID else { return [] }
        return [
            CommandKContextualAction(
                id: .openFocusMode,
                category: .primary,
                title: "Open in Focus Mode",
                subtitle: nil,
                systemImage: "arrow.up.left.and.arrow.down.right",
                shortcut: .returnKey,
                role: .normal,
                availability: .enabled,
                intent: .openAtom(uuid: uuid)
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
                id: .addToCanvas,
                category: .object,
                title: "Add to Canvas",
                subtitle: nil,
                systemImage: "plus.rectangle.on.rectangle",
                shortcut: nil,
                role: .normal,
                availability: .enabled,
                intent: .addToCanvas(uuid: uuid)
            ),
            CommandKContextualAction(
                id: .goToObject,
                category: .object,
                title: "Go to Object",
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
