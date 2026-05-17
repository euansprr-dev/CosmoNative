import AppKit
import Foundation

@MainActor
struct CommandKActionExecutor {
    func execute(_ intent: CommandKActionIntent) async throws {
        switch intent {
        case .openAtom(let uuid):
            NotificationCenter.default.post(
                name: CosmoNotification.NodeGraph.openAtomFromCommandK,
                object: nil,
                userInfo: ["atomUUID": uuid]
            )
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)

        case .openAsPane(let uuid):
            try await openAsPane(uuid: uuid)

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
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)

        case .deleteAtom(let uuid):
            try await AtomRepository.shared.delete(uuid: uuid)

        case .copyCosmoLink(let uuid):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("cosmo://atom/\(uuid)", forType: .string)

        case .executeTool(let name, let arguments):
            try await executeTool(name: name, arguments: arguments)

        case .postNotification(let name, let userInfo):
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)

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
        let completedAt = PlannerumFormatters.iso8601.string(from: Date())
        guard let task = try await AtomRepository.shared.update(uuid: uuid, updates: { atom in
            var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            metadata.isCompleted = true
            metadata.completedAt = completedAt
            atom = atom.withMetadata(metadata)
        }) else { return }

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
        guard let task = try await AtomRepository.shared.update(uuid: uuid, updates: { atom in
            var metadata = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
            metadata.dueDate = dateString
            metadata.focusDate = dateString
            metadata.whenDate = dateString
            metadata.schedulingState = nil
            metadata.isUnscheduled = false
            atom = atom.withMetadata(metadata)
        }) else { return }

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
