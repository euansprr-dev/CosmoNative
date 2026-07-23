// CosmoOS/Automation/AutomationActionExecutor.swift
// Executes automation actions against the CosmoOS data layer

import Foundation
import SwiftUI

@MainActor
class AutomationActionExecutor {

    /// UUIDs recently modified by automation — suppressed from re-automation for 5 minutes
    private var recentlyAutomated: [String: Date] = [:]

    /// Deferred spatial actions from sync catch-up (thinkspaceId → actions)
    private(set) var deferredActions: [(action: AutomationAction, atomUUID: String, thinkspaceId: String)] = []

    /// Check if an atom was recently automated (user override protection)
    func isRecentlyAutomated(_ atomUUID: String) -> Bool {
        guard let lastTime = recentlyAutomated[atomUUID] else { return false }
        if Date().timeIntervalSince(lastTime) > 300 { // 5 min expiry
            recentlyAutomated.removeValue(forKey: atomUUID)
            return false
        }
        return true
    }

    /// Mark an atom as recently automated
    private func markAutomated(_ atomUUID: String) {
        recentlyAutomated[atomUUID] = Date()
    }

    /// Clear override for an atom (called when user manually changes it)
    func clearOverride(for atomUUID: String) {
        recentlyAutomated.removeValue(forKey: atomUUID)
    }

    /// Execute all actions for a rule in sequence
    func execute(
        actions: [AutomationAction],
        context: AutomationContext,
        ruleName: String
    ) async {
        for action in actions {
            do {
                // Defer spatial actions during sync catch-up
                if context.isFromSync && action.type.isSpatialAction {
                    if let tsId = context.thinkspaceId ?? action.configString("thinkspaceId") {
                        deferredActions.append((action: action, atomUUID: context.atom.uuid, thinkspaceId: tsId))
                        print("⚡ [Automation] Deferred spatial action \(action.type.rawValue) for \(context.atom.uuid) on thinkspace \(tsId)")
                    }
                    continue
                }

                try await executeAction(action, context: context)
                markAutomated(context.atom.uuid)

            } catch {
                print("⚡ [Automation] Action \(action.type.rawValue) failed for rule '\(ruleName)': \(error.localizedDescription)")
                break // Stop chain on failure
            }
        }
    }

    /// Execute deferred spatial actions for a specific thinkspace (called when user navigates to it)
    func executeDeferredActions(for thinkspaceId: String) async -> Int {
        let matching = deferredActions.filter { $0.thinkspaceId == thinkspaceId }
        guard !matching.isEmpty else { return 0 }

        var executed = 0
        for deferred in matching {
            // Build a minimal context for deferred execution
            guard let atom = try? await AtomRepository.shared.fetch(uuid: deferred.atomUUID) else { continue }

            let context = await AutomationContextBuilder.build(
                event: AutomationEvent(triggerType: .atomCreated, atomUUID: deferred.atomUUID, isFromSync: true),
                atom: atom,
                thinkspaceId: thinkspaceId
            )

            do {
                try await executeAction(deferred.action, context: context)
                executed += 1
            } catch {
                print("⚡ [Automation] Deferred action failed: \(error.localizedDescription)")
            }
        }

        // Remove executed deferred actions
        deferredActions.removeAll { $0.thinkspaceId == thinkspaceId }

        if executed > 0 {
            NotificationCenter.default.post(
                name: CosmoNotification.Automation.deferredActionsReady,
                object: nil,
                userInfo: ["thinkspaceId": thinkspaceId, "count": executed]
            )
        }

        return executed
    }

    // MARK: - Flow Actions (Living Workflows)

    /// Run a canvas Flow headlessly. The output is staged as a proposal on
    /// the flow's line — autonomous runs never place blocks unapproved.
    private func handleRunFlow(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let flowUUID = action.config["flowUUID"]?.stringValue,
              let thinkspaceId = action.config["thinkspaceId"]?.stringValue else { return }
        await FlowEngine.runHeadless(flowUUID: flowUUID, thinkspaceId: thinkspaceId)
    }

    // MARK: - Action Handlers

    private func executeAction(_ action: AutomationAction, context: AutomationContext) async throws {
        switch action.type {
        case .runFlow:
            try await handleRunFlow(action, context: context)

        case .setStatus:
            try await handleSetStatus(action, context: context)

        case .setField:
            try await handleSetField(action, context: context)

        case .addTag:
            try await handleAddTag(action, context: context)

        case .removeTag:
            try await handleRemoveTag(action, context: context)

        case .moveToCluster:
            try await handleMoveToCluster(action, context: context)

        case .removeFromCluster:
            try await handleRemoveFromCluster(action, context: context)

        case .placeOnCanvas:
            try await handlePlaceOnCanvas(action, context: context)

        case .moveToThinkspace:
            break

        case .advancePipeline:
            try await handleAdvancePipeline(action, context: context)

        case .generateOutline:
            try await handleGenerateOutline(action, context: context)

        case .assignToClient:
            try await handleAssignToClient(action, context: context)

        case .archiveAtom:
            try await handleArchiveAtom(action, context: context)

        case .awardXP:
            handleAwardXP(action, context: context)

        case .createLink:
            try await handleCreateLink(action, context: context)

        case .removeLink:
            try await handleRemoveLink(action, context: context)

        case .createAtom:
            try await handleCreateAtom(action, context: context)

        case .createTask:
            try await handleCreateTask(action, context: context)

        case .duplicateAtom:
            break

        case .showNotification:
            handleShowNotification(action, context: context)

        case .sendTelegram:
            // Telegram bridge removed — legacy rules with this action are a no-op.
            // The enum case stays so persisted rules keep decoding.
            break

        case .runAnalysis:
            try await handleRunAnalysis(action, context: context)

        case .askCosmo:
            // Deferred to WP6
            break

        case .instantiateTemplate:
            try await handleInstantiateTemplate(action, context: context)

        case .highlightCluster:
            handleHighlightCluster(action, context: context)

        case .pulseBlock:
            handlePulseBlock(action, context: context)

        @unknown default:
            break
        }
    }

    // MARK: - Status Mutations

    private func handleSetStatus(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let newStatus = action.configString("status") else { return }
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        var metaDict = Self.parseMetadata(atom.metadata)

        switch atom.type {
        case .idea:
            metaDict["ideaStatus"] = newStatus
        case .content:
            metaDict["contentPhase"] = newStatus
            metaDict["content_phase"] = newStatus
        case .task:
            metaDict["status"] = newStatus
        default:
            metaDict["status"] = newStatus
        }

        atom.metadata = Self.encodeMetadata(metaDict)
        let _ = try await AtomRepository.shared.update(atom)

        print("⚡ [Automation] Set status to '\(newStatus)' for atom \(context.atom.uuid)")
    }

    private func handleSetField(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let field = action.configString("field"),
              let value = action.configString("value") else { return }
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        var metaDict = Self.parseMetadata(atom.metadata)
        metaDict[field] = value
        atom.metadata = Self.encodeMetadata(metaDict)
        let _ = try await AtomRepository.shared.update(atom)

        print("⚡ [Automation] Set field '\(field)' to '\(value)' for atom \(context.atom.uuid)")
    }

    private func handleAddTag(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let tag = action.configString("tag") else { return }
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        var metaDict = Self.parseMetadata(atom.metadata)
        var tags = (metaDict["tags"] as? String)?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if !tags.contains(where: { $0.lowercased() == tag.lowercased() }) {
            tags.append(tag)
            metaDict["tags"] = tags.joined(separator: ", ")
            atom.metadata = Self.encodeMetadata(metaDict)
            let _ = try await AtomRepository.shared.update(atom)
        }
    }

    private func handleRemoveTag(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let tag = action.configString("tag") else { return }
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        var metaDict = Self.parseMetadata(atom.metadata)
        var tags = (metaDict["tags"] as? String)?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        tags.removeAll { $0.lowercased() == tag.lowercased() }
        metaDict["tags"] = tags.joined(separator: ", ")
        atom.metadata = Self.encodeMetadata(metaDict)
        let _ = try await AtomRepository.shared.update(atom)
    }

    // MARK: - Spatial Actions

    private func handleMoveToCluster(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let clusterIdString = action.configString("clusterId")
                ?? action.configString("clusterName") else { return }

        // Post notification for CanvasView to handle the spatial move
        NotificationCenter.default.post(
            name: CosmoNotification.Automation.ruleFired,
            object: nil,
            userInfo: [
                "action": "moveToCluster",
                "atomUUID": context.atom.uuid,
                "clusterId": clusterIdString
            ]
        )

        print("⚡ [Automation] Requested move to cluster '\(clusterIdString)' for atom \(context.atom.uuid)")
    }

    private func handleRemoveFromCluster(_ action: AutomationAction, context: AutomationContext) async throws {
        NotificationCenter.default.post(
            name: CosmoNotification.Automation.ruleFired,
            object: nil,
            userInfo: [
                "action": "removeFromCluster",
                "atomUUID": context.atom.uuid
            ]
        )
    }

    private func handlePlaceOnCanvas(_ action: AutomationAction, context: AutomationContext) async throws {
        let thinkspaceId = action.configString("thinkspaceId") ?? context.thinkspaceId

        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.placeEntityOnCanvas,
            object: nil,
            userInfo: [
                "atomUUID": context.atom.uuid,
                "atomType": context.atom.type,
                "thinkspaceId": thinkspaceId as Any
            ]
        )

        print("⚡ [Automation] Placed atom \(context.atom.uuid) on canvas")
    }

    // MARK: - Link Actions

    private func handleCreateLink(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let targetUUID = action.configString("targetUUID"),
              let linkType = action.configString("linkType") else { return }
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        var links = atom.linksList
        let newLink = AtomLink(type: linkType, uuid: targetUUID)
        if !links.contains(where: { $0.uuid == targetUUID && $0.type == linkType }) {
            links.append(newLink)
            atom.links = Self.encodeLinks(links)
            let _ = try await AtomRepository.shared.update(atom)
        }

        // Post notification for graph update
        NotificationCenter.default.post(
            name: CosmoNotification.Entity.linkEntities,
            object: nil,
            userInfo: [
                "sourceUUID": context.atom.uuid,
                "targetUUID": targetUUID,
                "linkType": linkType
            ]
        )

        print("⚡ [Automation] Created \(linkType) link from \(context.atom.uuid) to \(targetUUID)")
    }

    private func handleRemoveLink(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let targetUUID = action.configString("targetUUID") else { return }
        let linkType = action.configString("linkType")
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        var links = atom.linksList
        links.removeAll { link in
            link.uuid == targetUUID && (linkType == nil || link.type == linkType)
        }
        atom.links = Self.encodeLinks(links)
        let _ = try await AtomRepository.shared.update(atom)
    }

    // MARK: - Creation Actions

    private func handleCreateAtom(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let typeString = action.configString("atomType"),
              let atomType = AtomType(rawValue: typeString) else { return }

        let title = interpolateTemplate(action.configString("title") ?? "", context: context)
        let body = interpolateTemplate(action.configString("body") ?? "", context: context)

        let _ = try await AtomRepository.shared.create(
            type: atomType,
            title: title.isEmpty ? nil : title,
            body: body.isEmpty ? nil : body
        )

        print("⚡ [Automation] Created \(typeString) atom")
    }

    // MARK: - Notification Actions

    private func handleShowNotification(_ action: AutomationAction, context: AutomationContext) {
        let message = interpolateTemplate(
            action.configString("message") ?? "Automation fired",
            context: context
        )

        // Post an in-app notification (CanvasView or MainView will display it)
        NotificationCenter.default.post(
            name: CosmoNotification.Automation.ruleFired,
            object: nil,
            userInfo: [
                "action": "showNotification",
                "message": message,
                "atomUUID": context.atom.uuid
            ]
        )
    }

    // MARK: - AI Actions

    private func handleRunAnalysis(_ action: AutomationAction, context: AutomationContext) async throws {
        let analysisType = action.configString("analysisType") ?? "quickEnrich"

        switch analysisType {
        case "quickEnrich":
            // Trigger idea enrichment notification
            NotificationCenter.default.post(
                name: CosmoNotification.Entity.triggerAutoLink,
                object: nil,
                userInfo: ["atomUUID": context.atom.uuid]
            )
        default:
            break
        }

        print("⚡ [Automation] Triggered \(analysisType) for atom \(context.atom.uuid)")
    }

    // MARK: - Visual Actions

    private func handleHighlightCluster(_ action: AutomationAction, context: AutomationContext) {
        let clusterId = action.configString("clusterId") ?? context.clusterMembership.first ?? ""

        NotificationCenter.default.post(
            name: CosmoNotification.Automation.ruleFired,
            object: nil,
            userInfo: [
                "action": "highlightCluster",
                "clusterId": clusterId
            ]
        )
    }

    private func handlePulseBlock(_ action: AutomationAction, context: AutomationContext) {
        NotificationCenter.default.post(
            name: CosmoNotification.Automation.ruleFired,
            object: nil,
            userInfo: [
                "action": "pulseBlock",
                "atomUUID": context.atom.uuid
            ]
        )
    }

    // MARK: - Pipeline Actions

    private func handleAdvancePipeline(_ action: AutomationAction, context: AutomationContext) async throws {
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }
        guard atom.type == .content else { return }

        var metaDict = Self.parseMetadata(atom.metadata)
        let currentPhase = metaDict["contentPhase"] as? String ?? metaDict["content_phase"] as? String ?? "ideation"

        let phases = ["ideation", "brainstorm", "draft", "polish", "scheduled", "published", "analyzing", "archived"]
        guard let currentIdx = phases.firstIndex(of: currentPhase),
              currentIdx + 1 < phases.count else { return }

        let nextPhase = phases[currentIdx + 1]
        metaDict["contentPhase"] = nextPhase
        metaDict["content_phase"] = nextPhase
        atom.metadata = Self.encodeMetadata(metaDict)
        let _ = try await AtomRepository.shared.update(atom)

        print("⚡ [Automation] Advanced pipeline: \(currentPhase) → \(nextPhase) for \(context.atom.uuid)")
    }

    private func handleGenerateOutline(_ action: AutomationAction, context: AutomationContext) async throws {
        // Post notification for the agent to generate an outline
        NotificationCenter.default.post(
            name: CosmoNotification.Automation.ruleFired,
            object: nil,
            userInfo: [
                "action": "generateOutline",
                "atomUUID": context.atom.uuid,
                "contentUUID": context.atom.uuid
            ]
        )
        print("⚡ [Automation] Triggered outline generation for \(context.atom.uuid)")
    }

    private func handleAssignToClient(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let clientUUID = action.configString("clientUUID")
                ?? action.configString("clientName") else { return }
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        // If clientName provided, try to resolve UUID
        var resolvedUUID = clientUUID
        if clientUUID.count < 30 { // Likely a name, not UUID
            if let client = try? await AtomRepository.shared.search(query: clientUUID, limit: 1).first,
               client.type == .clientProfile {
                resolvedUUID = client.uuid
            }
        }

        var metaDict = Self.parseMetadata(atom.metadata)
        metaDict["clientUUID"] = resolvedUUID
        atom.metadata = Self.encodeMetadata(metaDict)

        // Add client link
        var links = atom.linksList
        let newLink = AtomLink(type: AtomLinkType.ideaToClient.rawValue, uuid: resolvedUUID)
        if !links.contains(where: { $0.uuid == resolvedUUID }) {
            links.append(newLink)
            atom.links = Self.encodeLinks(links)
        }

        let _ = try await AtomRepository.shared.update(atom)
        print("⚡ [Automation] Assigned \(context.atom.uuid) to client \(resolvedUUID)")
    }

    private func handleArchiveAtom(_ action: AutomationAction, context: AutomationContext) async throws {
        guard var atom = try await AtomRepository.shared.fetch(uuid: context.atom.uuid) else { return }

        var metaDict = Self.parseMetadata(atom.metadata)
        metaDict["status"] = "archived"
        if atom.type == .idea {
            metaDict["ideaStatus"] = "archived"
        }
        if atom.type == .content {
            metaDict["contentPhase"] = "archived"
            metaDict["content_phase"] = "archived"
        }
        atom.metadata = Self.encodeMetadata(metaDict)
        let _ = try await AtomRepository.shared.update(atom)

        print("⚡ [Automation] Archived atom \(context.atom.uuid)")
    }

    // MARK: - Task Creation

    private func handleCreateTask(_ action: AutomationAction, context: AutomationContext) async throws {
        let titleTemplate = action.configString("title") ?? "Review {{atom.title}}"
        let title = interpolateTemplate(titleTemplate, context: context)

        let _ = try await AtomRepository.shared.create(
            type: .task,
            title: title,
            body: nil,
            metadata: "{\"status\": \"todo\"}",
            links: [AtomLink(type: AtomLinkType.related.rawValue, uuid: context.atom.uuid)]
        )

        print("⚡ [Automation] Created task: \(title)")
    }

    // MARK: - Gamification

    /// The XP system was retired; the `awardXP` action case remains for
    /// persisted-rule decode compatibility but is now a no-op.
    private func handleAwardXP(_ action: AutomationAction, context: AutomationContext) {
        print("⚡ [Automation] awardXP action ignored (XP system retired) for \(context.atom.uuid)")
    }

    // MARK: - Template Interpolation

    /// Replace {{variable}} placeholders with context values
    private func interpolateTemplate(_ template: String, context: AutomationContext) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{{atom.title}}", with: context.atom.title)
        result = result.replacingOccurrences(of: "{{atom.type}}", with: context.atom.type)
        result = result.replacingOccurrences(of: "{{atom.status}}", with: context.atom.status ?? "")
        result = result.replacingOccurrences(of: "{{atom.clientUUID}}", with: context.atom.clientUUID ?? "")
        result = result.replacingOccurrences(of: "{{atom.uuid}}", with: context.atom.uuid)
        result = result.replacingOccurrences(of: "{{trigger.oldValue}}", with: context.event.previousValue ?? "")
        result = result.replacingOccurrences(of: "{{trigger.newValue}}", with: context.event.newValue ?? "")
        return result
    }

    // MARK: - JSON Helpers

    private static func parseMetadata(_ metadata: String?) -> [String: Any] {
        guard let json = metadata,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func encodeMetadata(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func encodeLinks(_ links: [AtomLink]) -> String {
        guard let data = try? JSONEncoder().encode(links),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Template Instantiation

    private func handleInstantiateTemplate(_ action: AutomationAction, context: AutomationContext) async throws {
        guard let templateUUID = action.configString("templateUUID") else {
            print("⚡ [Automation] instantiateTemplate: missing templateUUID in config")
            return
        }

        let thinkspaceId = action.configString("thinkspaceId") ?? context.thinkspaceId
        let autoFill = action.configString("autoFill") != "false"

        // Fetch triggering atom for context-aware auto-fill
        let triggeringAtom = try? await AtomRepository.shared.fetch(uuid: context.atom.uuid)

        try await TemplateEngine.shared.instantiate(
            templateUUID: templateUUID,
            fieldOverrides: nil,
            triggeringAtom: triggeringAtom,
            targetThinkspaceId: thinkspaceId,
            targetPosition: nil,
            autoFill: autoFill
        )

        print("⚡ [Automation] Instantiated template \(templateUUID) for atom \(context.atom.uuid)")
    }
}
