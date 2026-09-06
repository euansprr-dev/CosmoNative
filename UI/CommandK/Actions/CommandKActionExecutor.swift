import AppKit
import Foundation

@MainActor
struct CommandKActionExecutor {
    func execute(_ intent: CommandKActionIntent) async throws {
        switch intent {
        case .openSpaceItem(let uuid, let spaceID):
            let presentation = try await CommandKSpaceService.openAtom(uuid, exactSpaceID: spaceID)
            NotificationCenter.default.post(name: presentation.paletteDismissalNotification, object: nil)

        case .openSpace(let spaceID, let map):
            try await CommandKSpaceService.openSpace(spaceID, map: map)
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)

        case .addOriginals(let uuids, let destination):
            try await CommandKSpaceService.addOriginals(uuids, to: destination)

        case .chooseSpaceDestination, .browseSpaceDestinations, .pickSpaceDestination, .backToSpaces:
            // These change the existing palette's action rows. The view model
            // handles them so query and composer edits remain intact.
            break

        case .openAtom(let uuid):
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )

        case .openAsPane(let uuid):
            try await openAsPane(uuid: uuid)

        case .openSwipeGalleryAsPane:
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["swipeGallery": true]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)

        case .addToCanvas(let uuid):
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.addToCanvas,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )

        case .goToObject(let uuid):
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.goToObjectFromCommandK,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )

        case .deleteAtom(let uuid):
            try await AtomRepository.shared.delete(uuid: uuid)
            await MainActor.run {
                CosmoUndoManager.shared.registerAtomDeletion(
                    uuid: uuid, actionDescription: "Delete Item"
                )
            }

        case .copyCosmoLink(let uuid):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("cosmo://atom/\(uuid)", forType: .string)

        case .executeTool(let name, let arguments):
            try await executeTool(name: name, arguments: arguments)

        case .postNotification(let name, let userInfo):
            // These intents hand off to another surface (Peek, places, workbenches,
            // gallery, inquiry) — the palette's job is done once the post is out.
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)

        case .startInquiry(let anchorUUID, let anchorType):
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.startInquiry,
                object: nil,
                userInfo: ["anchorUUID": anchorUUID, "anchorType": anchorType]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)

        case .commandCenter(let commandCenterIntent):
            try await executeCommandCenter(commandCenterIntent)

        case .userCommand, .recipe:
            break
        }
    }

    private func openAsPane(uuid: String) async throws {
        guard let atom = try await AtomRepository.shared.fetch(uuid: uuid) else {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            return
        }

        if let entityType = EntityType(rawValue: atom.type.rawValue),
           let entityId = atom.id,
           entityId > 0 {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["type": entityType, "id": entityId]
            )
        } else {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )
        }
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    private func executeTool(name: String, arguments: [String: String]) async throws {
        switch name {
        case "add_to_active_inquiry":
            if let uuid = arguments["uuid"] {
                NotificationCenter.default.post(
                    name: CosmoNotification.Inquiry.addExtractToInquiry,
                    object: nil,
                    userInfo: ["extractUUID": uuid]
                )
            }
        case "attach_swipe_to_current_draft", "use_swipe_as_blueprint", "create_idea_from_swipe":
            _ = try await AgentToolExecutor.shared.execute(toolName: name, arguments: arguments)
        case "capture_swipe":
            guard let url = arguments["url"] else { return }
            _ = try await CommandKInstantSwipeCapture().capture(url: url, hook: arguments["hook"])
        case "scan_with_iphone":
            // The relay: a synced request row + an APNs push at the phone.
            // The pages come back as a normal inbox capture from its side.
            let request = try await CaptureRequestRepository.shared.create(
                .new(kind: .inboxScan, scanSessionId: UUID().uuidString)
            )
            try await PushSenderService.shared.sendScanRequest(request)
        case "upload_scan_images":
            // Command-K closes; the open panel takes over, then the shared
            // scan pipeline digitizes into ONE inbox capture.
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = true
            panel.message = "Choose page images to digitize into your Inbox"
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            guard panel.runModal() == .OK else { return }
            let images = panel.urls.compactMap { try? Data(contentsOf: $0) }
            _ = await InboxScanIngestService.shared.ingest(images: images)
        default:
            _ = try await AgentToolExecutor.shared.execute(toolName: name, arguments: arguments)
        }
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    private func executeCommandCenter(_ intent: CommandKCommandCenterIntent) async throws {
        switch intent {
        case .createReviewTask(let sourceUUID):
            try await createReviewTask(sourceUUID: sourceUUID)
        case .startFocus(let taskUUID):
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.enterFocusMode,
                object: nil,
                userInfo: ["atomUUID": taskUUID]
            )
        case .markDone(let taskUUID):
            try await completeTask(uuid: taskUUID)
        case .deferTask(let taskUUID, let days):
            try await scheduleTask(uuid: taskUUID, daysFromToday: days)
        case .scheduleTomorrow(let taskUUID):
            try await scheduleTask(uuid: taskUUID, daysFromToday: 1)
        }
        NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
    }

    private func createReviewTask(sourceUUID: String) async throws {
        let source = try await AtomRepository.shared.fetch(uuid: sourceUUID)
        var metadata = TaskMetadata()
        metadata.priority = "medium"
        metadata.intent = TaskIntent.review.rawValue
        metadata.linkedAtomUUID = sourceUUID
        metadata.isUnscheduled = true

        let sourceTitle = source?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewTarget = (sourceTitle?.isEmpty == false) ? (sourceTitle ?? "source") : "source"
        let title = "Review \(reviewTarget)"
        let task = try await AtomRepository.shared.create(
            type: .task,
            title: title,
            metadata: encodeMetadata(metadata),
            links: [AtomLink.linksTo(sourceUUID, entityType: source?.type)]
        )

        NotificationCenter.default.post(
            name: CosmoNotification.Entity.created,
            object: nil,
            userInfo: ["atom": task, "uuid": task.uuid, "type": "task"]
        )
    }

    private func completeTask(uuid: String) async throws {
        guard let atom = try await AtomRepository.shared.fetch(uuid: uuid) else { return }

        // Recurring series template → log today's occurrence in the completion log instead
        // of flagging the template itself completed (which would freeze the whole series).
        if let meta = atom.metadataValue(as: TaskMetadata.self),
           meta.recurrence != nil, meta.recurrenceParentUUID == nil {
            let today = Date()
            let occurrenceDay: Date
            if let snapshot = RecurringSeriesEngine.makeSnapshot(from: atom),
               let liveDay = RecurringSeriesEngine.liveOccurrenceDay(for: snapshot, asOf: today) {
                occurrenceDay = liveDay
            } else {
                occurrenceDay = Calendar.current.startOfDay(for: today)
            }
            // Habit credit only for a fresh completion — re-invoking Mark Done on an
            // already-logged occurrence must not double-credit (the dashboard contract).
            let occurrenceKey = RecurringSeriesEngine.dayKey(for: occurrenceDay)
            let alreadyLogged = (meta.completedOccurrences ?? []).contains { $0.day == occurrenceKey }
            try await RecurringSeriesEngine.shared.complete(templateUUID: uuid, occurrenceDay: occurrenceDay)
            if !alreadyLogged {
                await CommandCenterHabitEngine.shared.recordTaskCompletion(taskUUID: uuid)
            }

            NotificationCenter.default.post(
                name: CosmoNotification.Gamification.taskCompleted,
                object: nil,
                userInfo: ["taskUUID": uuid]
            )
            NotificationCenter.default.post(
                name: CosmoNotification.Entity.updated,
                object: nil,
                userInfo: ["uuid": uuid, "type": "task"]
            )
            return
        }

        let completedAt = PlannerumFormatters.iso8601.string(from: Date())
        var applied = false
        guard let task = try await AtomRepository.shared.update(uuid: uuid, updates: { atom in
            guard var metadata = taskMetadataForCommandKWrite(atom, context: "CommandK.completeTask") else { return }
            guard metadata.isCompleted != true else { return }
            metadata.isCompleted = true
            metadata.completedAt = completedAt
            guard let merged = atom.mergingTaskMetadata(metadata, context: "CommandK.completeTask(\(uuid.prefix(8)))") else { return }
            atom = merged
            applied = true
        }), applied else { return }

        // Habit credit only after the completion actually persisted (dashboard contract).
        await CommandCenterHabitEngine.shared.recordTaskCompletion(taskUUID: uuid)

        NotificationCenter.default.post(
            name: CosmoNotification.Gamification.taskCompleted,
            object: nil,
            userInfo: ["taskUUID": uuid]
        )
        NotificationCenter.default.post(
            name: CosmoNotification.Entity.updated,
            object: nil,
            userInfo: ["atom": task, "uuid": task.uuid, "type": "task"]
        )
    }

    private func scheduleTask(uuid: String, daysFromToday: Int) async throws {
        let targetDate = Calendar.current.date(
            byAdding: .day,
            value: daysFromToday,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let dateString = PlannerumFormatters.iso8601.string(from: targetDate)
        var applied = false
        guard let task = try await AtomRepository.shared.update(uuid: uuid, updates: { atom in
            guard var metadata = taskMetadataForCommandKWrite(atom, context: "CommandK.scheduleTask") else { return }
            metadata.dueDate = dateString
            metadata.focusDate = dateString
            metadata.whenDate = dateString
            metadata.schedulingState = nil
            metadata.isUnscheduled = false
            if metadata.recurrence != nil, metadata.recurrenceParentUUID == nil {
                // Deliberate template move: keep the timezone-safe anchor day in step.
                metadata.seriesAnchorDay = RecurringSeriesEngine.dayKey(for: targetDate)
            }
            guard let merged = atom.mergingTaskMetadata(metadata, context: "CommandK.scheduleTask(\(uuid.prefix(8)))") else { return }
            atom = merged
            applied = true
        }), applied else { return }

        NotificationCenter.default.post(
            name: CosmoNotification.Entity.updated,
            object: nil,
            userInfo: ["atom": task, "uuid": task.uuid, "type": "task"]
        )
    }

    private func encodeMetadata<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Decode-state guard for Command-K task writes: absent → fresh metadata, corrupt → nil
/// (reported via PersistenceHealth). Callers must bail out of the write when this returns
/// nil so a corrupt column is never overwritten with defaults.
private func taskMetadataForCommandKWrite(_ atom: Atom, context: String) -> TaskMetadata? {
    switch atom.decodedMetadata(as: TaskMetadata.self) {
    case .absent:
        return TaskMetadata()
    case .value(let metadata):
        return metadata
    case .corrupt(let error):
        PersistenceHealth.note(.decodeFailure, context: "\(context)(\(atom.uuid.prefix(8)))", detail: "task metadata undecodable; refusing write (\(error.localizedDescription))")
        return nil
    }
}
