import Foundation

enum CommandKContextualActionID: String, Codable, Hashable, CaseIterable {
    case openFocusMode
    case openAsPane
    case addToCanvas
    case goToObject
    case deleteObject
    case copyCosmoLink
    case openSwipeGallery
    case openSwipeStudy
    case analyzeSwipeHook
    case attachSwipeToCurrentDraft
    case useSwipeAsBlueprint
    case createIdeaFromSwipe
    case findSimilarSwipes
    case batchReprocessSwipeMedia
    case addToActiveInquiry
    case startInquiryOnSelection
    case refreshInquirySources
    case crystallizeInquiry
    case captureSwipe
    case captureResearch
    case createTask
    case createIdea
    case addInquiryExtract
    case createTaskFromSelection
    case startFocusTask
    case markTaskDone
    case deferTask
    case scheduleTaskTomorrow
    case runQuicklink
    case runMemoryClip
    case runSnippet
    case runRecipe
}

enum CommandKActionCategory: String, Codable, Equatable, CaseIterable {
    case primary = "Primary"
    case object = "Object"
    case capture = "Capture"
    case swipe = "Swipe"
    case inquiry = "Inquiry"
    case commandCenter = "Command Center"
    case userCommand = "User Commands"
    case destructive = "Danger"
}

enum CommandKActionAvailability: Equatable {
    case enabled
    case disabled(reason: String)

    var isEnabled: Bool {
        if case .enabled = self {
            return true
        }
        return false
    }
}

enum CommandKActionShortcut: String, Codable, Equatable {
    case returnKey
    case commandReturn
    case commandK
    case commandS
    case commandI
    case commandT
    case shiftCommandP
}

enum CommandKActionRole: String, Codable, Equatable {
    case normal
    case destructive
}

enum CommandKActionIntent: Equatable {
    case openAtom(uuid: String)
    case openAsPane(uuid: String)
    case openSwipeGalleryAsPane
    case addToCanvas(uuid: String)
    case goToObject(uuid: String)
    case deleteAtom(uuid: String)
    case copyCosmoLink(uuid: String)
    case executeTool(name: String, arguments: [String: String])
    case postNotification(name: Notification.Name, userInfo: [String: String])
    case startInquiry(anchorUUID: String, anchorType: String)
    case commandCenter(CommandKCommandCenterIntent)
    case userCommand(id: String)
    case recipe(id: String)
}

enum CommandKCommandCenterIntent: Equatable {
    case createReviewTask(sourceUUID: String)
    case startFocus(taskUUID: String)
    case markDone(taskUUID: String)
    case deferTask(taskUUID: String, days: Int)
    case scheduleTomorrow(taskUUID: String)
}

struct CommandKContextualAction: Identifiable, Equatable {
    let id: CommandKContextualActionID
    let category: CommandKActionCategory
    let title: String
    let subtitle: String?
    let systemImage: String
    let shortcut: CommandKActionShortcut?
    let role: CommandKActionRole
    let availability: CommandKActionAvailability
    let intent: CommandKActionIntent

    func withTitle(_ title: String) -> CommandKContextualAction {
        CommandKContextualAction(
            id: id,
            category: category,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            shortcut: shortcut,
            role: role,
            availability: availability,
            intent: intent
        )
    }
}
