// CosmoOS/Agent/Bridges/TelegramCaptureRouter.swift
// Custom Capture Lanes router. Saves raw capture first, then applies deterministic routing.

import Foundation

struct TelegramCapturedMedia: Equatable, Sendable {
    var kind: MediaAttachmentKind
    var fileId: String
    var fileUniqueId: String?
    var filename: String?
    var mimeType: String?
    var fileSize: Int64?
    var caption: String?
}

enum TelegramCaptureRouterOutcome: Equatable, Sendable {
    case handled(reply: String, capturedItemId: String)
    case notCaptureCommand
}

@MainActor
final class TelegramCaptureRouter {
    static let shared = TelegramCaptureRouter()

    private let destinations = CaptureDestinationRepository.shared
    private let capturedItems = CapturedItemRepository.shared
    private let mediaAttachments = MediaAttachmentRepository.shared
    private let inbox = InboxRepository.shared
    private let atoms = AtomRepository.shared

    private init() {}

    func routeTelegramCapture(
        text rawText: String?,
        media: [TelegramCapturedMedia] = [],
        chatId: String,
        messageId: String?,
        mediaGroupId: String? = nil,
        sender: String? = nil
    ) async -> TelegramCaptureRouterOutcome {
        let text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMedia = !media.isEmpty
        let command = text.flatMap { TelegramCaptureCommandParser.parse($0, allowsEmptyBody: hasMedia) }

        guard command != nil || hasMedia else {
            return .notCaptureCommand
        }

        do {
            let captured = try await createCapturedItem(
                text: text,
                media: media,
                chatId: chatId,
                messageId: messageId,
                mediaGroupId: mediaGroupId,
                sender: sender
            )
            let attachments = try await createMediaAttachments(for: captured.uuid, media: media)

            if let command {
                return try await routeCommand(command, captured: captured, attachments: attachments)
            }

            try await saveToGlobalInbox(captured: captured, reason: "Unprefixed media capture")
            return .handled(reply: defaultMediaReply(for: attachments), capturedItemId: captured.uuid)
        } catch {
            print("[TelegramCaptureRouter] capture failed: \(error)")
            return .handled(reply: "I saved this to Inbox, but routing failed. You can review it in Cosmo.", capturedItemId: "")
        }
    }

    private func createCapturedItem(
        text: String?,
        media: [TelegramCapturedMedia],
        chatId: String,
        messageId: String?,
        mediaGroupId: String?,
        sender: String?
    ) async throws -> CapturedItem {
        let caption = media.first?.caption
        let metadata = try? encodeJSON([
            "mediaCount": "\(media.count)",
            "hasMedia": media.isEmpty ? "false" : "true"
        ])
        return try await capturedItems.create(
            .makeTelegram(
                rawText: text,
                caption: caption,
                chatId: chatId,
                messageId: messageId,
                mediaGroupId: mediaGroupId,
                sender: sender,
                metadata: metadata
            )
        )
    }

    private func createMediaAttachments(for capturedItemId: String, media: [TelegramCapturedMedia]) async throws -> [MediaAttachment] {
        var saved: [MediaAttachment] = []
        for item in media {
            let attachment = MediaAttachment.makeTelegram(
                capturedItemId: capturedItemId,
                kind: item.kind,
                fileId: item.fileId,
                fileUniqueId: item.fileUniqueId,
                filename: item.filename,
                mimeType: item.mimeType,
                fileSize: item.fileSize,
                metadata: item.caption.flatMap { try? encodeJSON(["caption": $0]) }
            )
            saved.append(try await mediaAttachments.create(attachment))
        }
        if !saved.isEmpty {
            try await capturedItems.attachMedia(capturedItemId: capturedItemId, mediaIds: saved.map(\.uuid))
        }
        return saved
    }

    private func routeCommand(
        _ command: TelegramCaptureCommand,
        captured: CapturedItem,
        attachments: [MediaAttachment]
    ) async throws -> TelegramCaptureRouterOutcome {
        switch command.kind {
        case .createLane:
            let destination = try await destinations.createLane(
                named: command.destinationName,
                type: command.requestedLaneType
            )
            let objectIds = try await applyCustomLane(destination, command: command, captured: captured, attachments: attachments)
            try await capturedItems.updateRouting(
                uuid: captured.uuid,
                destinationId: destination.uuid,
                parsedCommand: command.commandText,
                parsedIntent: "create_lane",
                confidence: 1.0,
                status: .routed,
                createdObjectIds: objectIds
            )
            await destinations.markUsed(uuid: destination.uuid)
            postCaptureAdded(destinationId: destination.uuid)
            if attachments.isEmpty, command.body.isEmpty {
                return .handled(reply: "Created “\(destination.name).”", capturedItemId: captured.uuid)
            }
            return .handled(reply: createdLaneReply(destination: destination, attachments: attachments), capturedItemId: captured.uuid)

        case .route:
            if isCurrentInquiryCommand(command.destinationName) {
                if let session = try await applyCurrentInquiryRoute(command: command, captured: captured, attachments: attachments) {
                    try await capturedItems.updateRouting(
                        uuid: captured.uuid,
                        destinationId: nil,
                        parsedCommand: command.commandText,
                        parsedIntent: "current_inquiry",
                        confidence: 1.0,
                        status: .routed,
                        parentInquirySessionId: session.uuid
                    )
                    return .handled(reply: currentInquiryReply(attachments: attachments), capturedItemId: captured.uuid)
                }
                try await saveToGlobalInbox(captured: captured, reason: "No active inquiry session")
                return .handled(reply: "No current Inquiry is active. Saved to Inbox.", capturedItemId: captured.uuid)
            }

            if let destination = try await destinations.resolveCommand(command.destinationName) {
                let objectIds = try await applyCustomLane(destination, command: command, captured: captured, attachments: attachments)
                try await capturedItems.updateRouting(
                    uuid: captured.uuid,
                    destinationId: destination.uuid,
                    parsedCommand: command.commandText,
                    parsedIntent: command.subroute.rawValue,
                    confidence: 1.0,
                    status: .routed,
                    createdObjectIds: objectIds
                )
                await destinations.markUsed(uuid: destination.uuid)
                postCaptureAdded(destinationId: destination.uuid)
                return .handled(reply: routedReply(destination: destination, command: command, attachments: attachments), capturedItemId: captured.uuid)
            }

            if let deepDiveUUID = await DeepDiveAliasRegistry.shared.deepDiveUUID(forAlias: command.destinationName) {
                let objectIds = try await applyDeepDiveRoute(deepDiveUUID: deepDiveUUID, command: command, captured: captured, attachments: attachments)
                try await capturedItems.updateRouting(
                    uuid: captured.uuid,
                    destinationId: nil,
                    parsedCommand: command.commandText,
                    parsedIntent: command.subroute.rawValue,
                    confidence: 1.0,
                    status: .routed,
                    createdObjectIds: objectIds,
                    parentDeepDiveId: deepDiveUUID
                )
                return .handled(reply: deepDiveReply(command: command, attachments: attachments), capturedItemId: captured.uuid)
            }

            try await saveToGlobalInbox(captured: captured, reason: "Unknown capture destination: \(command.destinationName)")
            if let suggestion = await destinations.closestAlias(to: command.destinationName) {
                return .handled(reply: "I don’t have “\(command.destinationName).” Did you mean “\(suggestion)”? Saved to Inbox for review.", capturedItemId: captured.uuid)
            }
            return .handled(reply: "I don’t have “\(command.destinationName)” yet. Saved to Inbox.", capturedItemId: captured.uuid)
        }
    }

    private func applyCustomLane(
        _ destination: CaptureDestination,
        command: TelegramCaptureCommand,
        captured: CapturedItem,
        attachments: [MediaAttachment]
    ) async throws -> [String] {
        let text = preferredText(command: command, captured: captured)
        var objectIds: [String] = []

        switch destination.type {
        case .taskLane:
            if !text.isEmpty {
                let task = try await atoms.createTask(title: text)
                objectIds.append(task.uuid)
            }
        case .mediaSwipeLane:
            if !attachments.isEmpty {
                let source = try await createMediaSource(title: text.isEmpty ? "\(destination.name) capture" : text, captured: captured, attachments: attachments, isSwipe: true)
                objectIds.append(source.uuid)
            }
        case .researchLane, .sourceLane:
            if !attachments.isEmpty || looksLikeURL(text) {
                let source = try await createMediaSource(title: text.isEmpty ? "\(destination.name) source" : text, captured: captured, attachments: attachments, isSwipe: false)
                objectIds.append(source.uuid)
            }
        case .projectLane, .contentLane:
            if !text.isEmpty {
                let idea = try await atoms.createIdea(title: text, content: "")
                objectIds.append(idea.uuid)
            }
        case .journalLane:
            if !text.isEmpty {
                let journal = try await atoms.create(type: .journalEntry, title: String(text.prefix(60)), body: text)
                objectIds.append(journal.uuid)
            }
        case .listLane, .deepDiveLane, .structuredLane:
            break
        }

        return objectIds
    }

    private func applyCurrentInquiryRoute(command: TelegramCaptureCommand, captured: CapturedItem, attachments: [MediaAttachment]) async throws -> Atom? {
        let sessions = try await atoms.fetchAll(type: .inquirySession)
        guard var session = sessions
            .filter({ $0.inquirySessionMetadata?.status == .active })
            .sorted(by: {
                ($0.inquirySessionMetadata?.lastActiveAt ?? $0.updatedAt) > ($1.inquirySessionMetadata?.lastActiveAt ?? $1.updatedAt)
            })
            .first,
            var structured = session.inquirySessionStructured else {
            return nil
        }

        let text = preferredText(command: command, captured: captured)
        structured.sessionCaptures.append(
            SessionCapture(
                body: text.isEmpty ? mediaOnlyBody(attachments: attachments) : text,
                source: .telegram,
                suggestedKind: suggestedKind(for: command.subroute),
                attachedQuestionId: session.inquirySessionMetadata?.mainQuestionUUID,
                attachedSourceTabId: nil,
                status: .pending,
                promotedToAtomUUID: nil
            )
        )
        session = try await InquiryRepository.shared.saveSession(session, metadata: session.inquirySessionMetadata, structured: structured)
        return session
    }

    private func applyDeepDiveRoute(
        deepDiveUUID: String,
        command: TelegramCaptureCommand,
        captured: CapturedItem,
        attachments: [MediaAttachment]
    ) async throws -> [String] {
        guard let deepDive = try await atoms.fetch(uuid: deepDiveUUID) else { return [] }
        let text = preferredText(command: command, captured: captured)
        var objectIds: [String] = []

        switch command.subroute {
        case .question:
            if !text.isEmpty {
                let question = try await InquiryRepository.shared.createQuestion(
                    title: text,
                    parentDeepDiveUUID: deepDive.uuid,
                    originSessionUUID: nil,
                    parentQuestionUUID: nil,
                    originExtractUUID: nil
                )
                objectIds.append(question.uuid)
            }
        case .source, .file:
            let source: Atom
            if attachments.isEmpty, looksLikeURL(text) {
                source = try await InquiryRepository.shared.createOrFindURLSource(
                    urlString: text,
                    title: URL(string: text)?.host ?? text
                )
            } else {
                source = try await createMediaSource(title: text.isEmpty ? "\(deepDive.title ?? "Deep Dive") source" : text, captured: captured, attachments: attachments, isSwipe: false)
            }
            objectIds.append(source.uuid)
            var copy = deepDive
            copy = copy.appendingLink(AtomLink(type: AtomLinkType.deepDiveSource.rawValue, uuid: source.uuid, entityType: AtomType.research.rawValue))
            _ = try? await atoms.update(copy)
        case .evidence, .counterevidence, .claim, .practice, .term, .output, .note, .image, .task, .general:
            let kind: ExtractKind = {
                switch command.subroute {
                case .evidence: return .evidence
                case .counterevidence: return .counterevidence
                case .claim: return .claim
                case .practice: return .practice
                case .term: return .term
                case .output: return .outputIdea
                case .question: return .question
                default: return .note
                }
            }()
            let body = text.isEmpty ? mediaOnlyBody(attachments: attachments) : text
            let extract = try await InquiryRepository.shared.createExtract(
                body: body,
                kind: kind,
                sourceUUID: nil,
                selectionRange: nil,
                sessionUUID: nil,
                questionUUID: nil,
                deepDiveUUID: deepDive.uuid,
                branchNodeId: nil,
                sourceTabId: nil,
                userNote: nil,
                originType: "telegram",
                citation: nil
            )
            objectIds.append(extract.uuid)
        }

        return objectIds
    }

    private func saveToGlobalInbox(captured: CapturedItem, reason: String) async throws {
        let raw = captured.cleanText?.isEmpty == false ? captured.cleanText! : "Telegram media capture"
        let metadata = try? encodeJSON([
            "capturedItemUuid": captured.uuid,
            "reason": reason
        ])
        // The ingest service owns dedupe, the consumed-capture rule, and queued
        // classification — this path previously created items that were never
        // classified, leaving them stuck in "Needs your judgment" forever.
        _ = await InboxIngestService.shared.ingest(
            .init(source: .telegramText, rawText: raw, metadata: metadata)
        )
        try await capturedItems.updateRouting(
            uuid: captured.uuid,
            destinationId: nil,
            parsedCommand: nil,
            parsedIntent: "global_inbox",
            confidence: 0.2,
            status: .needsReview
        )
    }

    private func postCaptureAdded(destinationId: String?) {
        let userInfo: [AnyHashable: Any]? = destinationId.map { ["captureDestinationId": $0] }
        NotificationCenter.default.post(
            name: CosmoNotification.Inbox.itemAdded,
            object: nil,
            userInfo: userInfo
        )
    }

    private func createMediaSource(title: String, captured: CapturedItem, attachments: [MediaAttachment], isSwipe: Bool) async throws -> Atom {
        var metadata = ResearchMetadata()
        metadata.researchType = attachments.first?.kind.rawValue ?? "telegram_capture"
        metadata.processingStatus = "captured"
        metadata.tags = ["telegram", "capture"]
        metadata.isSwipeFile = isSwipe ? true : nil
        metadata.contentSource = isSwipe ? "telegram_media" : "telegram"
        metadata.personalNotes = captured.caption ?? captured.rawText

        let attachmentIds = attachments.map(\.uuid).joined(separator: ",")
        let body = attachments.compactMap(\.localStoragePath).joined(separator: "\n")
        let source = try await atoms.create(
            type: .research,
            title: title,
            body: body.isEmpty ? nil : body,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8),
            links: nil
        )
        _ = attachmentIds
        return source
    }

    private func preferredText(command: TelegramCaptureCommand, captured: CapturedItem) -> String {
        if !command.body.isEmpty { return command.body }
        if let caption = captured.caption, !caption.isEmpty { return caption }
        if let clean = captured.cleanText, !clean.isEmpty { return clean }
        return ""
    }

    private func routedReply(destination: CaptureDestination, command: TelegramCaptureCommand, attachments: [MediaAttachment]) -> String {
        if !attachments.isEmpty {
            if attachments.count == 1 {
                return "Saved \(attachments[0].kind.displayName.lowercased()) to \(destination.name)."
            }
            return "Saved \(attachments.count) files to \(destination.name)."
        }
        if command.subroute != .general {
            return "Saved to \(destination.name) -> \(command.subroute.rawValue)."
        }
        return "Saved to \(destination.name)."
    }

    private func createdLaneReply(destination: CaptureDestination, attachments: [MediaAttachment]) -> String {
        if let first = attachments.first {
            return "Created “\(destination.name).” Saved \(first.kind.displayName.lowercased()) there."
        }
        return "Created “\(destination.name).” Saved it there."
    }

    private func deepDiveReply(command: TelegramCaptureCommand, attachments: [MediaAttachment]) -> String {
        let target = command.subroute == .general ? "Topic Inbox" : command.subroute.rawValue.capitalized
        if let first = attachments.first {
            return "Saved \(first.kind.displayName.lowercased()) to \(command.destinationName) -> \(target)."
        }
        return "Saved to \(command.destinationName) -> \(target)."
    }

    private func defaultMediaReply(for attachments: [MediaAttachment]) -> String {
        if attachments.isEmpty { return "Saved to Inbox." }
        if attachments.count == 1 {
            return "Saved \(attachments[0].kind.displayName.lowercased()) to Inbox."
        }
        return "Saved \(attachments.count) files to Inbox."
    }

    private func mediaOnlyBody(attachments: [MediaAttachment]) -> String {
        guard !attachments.isEmpty else { return "Telegram capture" }
        if attachments.count == 1 {
            return "Telegram \(attachments[0].kind.displayName.lowercased()) capture"
        }
        return "Telegram media capture (\(attachments.count) files)"
    }

    private func currentInquiryReply(attachments: [MediaAttachment]) -> String {
        if let first = attachments.first {
            if first.kind == .audio {
                return "Saved voice note to current Inquiry. Transcription is processing."
            }
            return "Saved \(first.kind.displayName.lowercased()) to current Inquiry."
        }
        return "Saved to current Inquiry."
    }

    private func isCurrentInquiryCommand(_ raw: String) -> Bool {
        let normalized = CaptureDestination.normalizeAlias(raw)
        return normalized == "current inquiry" || normalized == "inquiry" || normalized == "current"
    }

    private func suggestedKind(for subroute: TelegramCaptureSubroute) -> ExtractKind? {
        switch subroute {
        case .question: return .question
        case .evidence: return .evidence
        case .counterevidence: return .counterevidence
        case .claim: return .claim
        case .practice: return .practice
        case .term: return .term
        case .output: return .outputIdea
        case .source, .file, .image: return .reference
        case .task: return nil
        case .note, .general: return .note
        }
    }

    private func looksLikeURL(_ text: String) -> Bool {
        text.range(of: #"https?://[^\s]+"#, options: .regularExpression) != nil
    }

    private func encodeJSON(_ object: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
