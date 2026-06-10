// CosmoOS/Automation/TemplateEngine.swift
// Core engine for Smart Templatable Blocks — CRUD, instantiation, button execution, spawn trigger binding

import Foundation
import SwiftUI

@MainActor
class TemplateEngine: ObservableObject {
    static let shared = TemplateEngine()

    /// In-memory cache of template definitions (templateUUID → metadata)
    private var templateCache: [String: BlockTemplateMetadata] = [:]

    private init() {}

    // MARK: - Template CRUD

    /// Create a new block template
    @discardableResult
    func createTemplate(
        name: String,
        icon: String = "rectangle.3.group.fill",
        accentColor: String = "#6366F1",
        fields: [TemplateFieldDefinition] = [],
        buttons: [TemplateButtonDefinition] = [],
        layoutMode: TemplateLayoutMode = .form,
        spawnTriggers: [TemplateSpawnTrigger] = [],
        description: String? = nil
    ) async throws -> Atom {
        var metadata = BlockTemplateMetadata.new(icon: icon, accentColorHex: accentColor)
        metadata.fields = fields
        metadata.buttons = buttons
        metadata.layoutMode = layoutMode
        metadata.spawnTriggers = spawnTriggers
        metadata.description = description

        let metadataJson = try String(data: JSONEncoder().encode(metadata), encoding: .utf8)

        let atom = try await AtomRepository.shared.create(
            type: .blockTemplate,
            title: name,
            metadata: metadataJson
        )

        // Cache it
        templateCache[atom.uuid] = metadata

        // Bind spawn triggers if any
        if !spawnTriggers.isEmpty {
            try await bindSpawnTriggers(for: atom.uuid, triggers: spawnTriggers)
        }

        print("📐 [TemplateEngine] Created template '\(name)' (\(atom.uuid))")
        return atom
    }

    /// Update an existing template's metadata
    @discardableResult
    func updateTemplate(_ templateUUID: String, metadata: BlockTemplateMetadata) async throws -> Atom {
        guard var atom = try await AtomRepository.shared.fetch(uuid: templateUUID) else {
            throw TemplateError.templateNotFound(templateUUID)
        }

        atom = atom.withBlockTemplateMetadata(metadata)
        atom = try await AtomRepository.shared.update(atom)

        // Update cache
        templateCache[templateUUID] = metadata

        print("📐 [TemplateEngine] Updated template '\(atom.title ?? "")' (\(templateUUID))")
        return atom
    }

    /// Soft-delete a template (instances remain functional)
    func deleteTemplate(_ templateUUID: String) async throws {
        // Unbind spawn triggers first
        try await unbindSpawnTriggers(for: templateUUID)

        try await AtomRepository.shared.delete(uuid: templateUUID)
        templateCache.removeValue(forKey: templateUUID)

        print("📐 [TemplateEngine] Deleted template (\(templateUUID))")
    }

    /// Duplicate a template with a new name
    @discardableResult
    func duplicateTemplate(_ templateUUID: String) async throws -> Atom {
        guard let original = try await AtomRepository.shared.fetch(uuid: templateUUID),
              var metadata = original.blockTemplateMetadata else {
            throw TemplateError.templateNotFound(templateUUID)
        }

        // Reset counters and triggers for the copy
        metadata.instanceCount = 0
        metadata.lastInstantiatedAt = nil
        metadata.spawnTriggers = []

        let copy = try await createTemplate(
            name: "\(original.title ?? "Template") (Copy)",
            icon: metadata.icon,
            accentColor: metadata.accentColorHex,
            fields: metadata.fields,
            buttons: metadata.buttons,
            layoutMode: metadata.layoutMode,
            description: metadata.description
        )

        return copy
    }

    // MARK: - Instantiation

    /// Instantiate a template — creates a new .templateInstance atom
    @discardableResult
    func instantiate(
        templateUUID: String,
        fieldOverrides: [String: ConditionValue]? = nil,
        triggeringAtom: Atom? = nil,
        targetThinkspaceId: String? = nil,
        targetPosition: CGPoint? = nil,
        autoFill: Bool = false
    ) async throws -> Atom {
        // 1. Resolve template
        guard let templateAtom = try await AtomRepository.shared.fetch(uuid: templateUUID),
              let templateMeta = templateAtom.blockTemplateMetadata else {
            throw TemplateError.templateNotFound(templateUUID)
        }

        // 2. Build instance title
        let dateStr = DateFormatter.shortDate.string(from: Date())
        let instanceTitle = "\(templateAtom.title ?? "Template") — \(dateStr)"

        // 3. Build field values from defaults
        var fieldValues: [String: ConditionValue] = [:]
        for field in templateMeta.fields {
            if let defaultValue = field.defaultValue {
                fieldValues[field.key] = .string(defaultValue)
            }
            // Auto-populate from context
            if let autoFrom = field.autoPopulateFrom {
                if let value = resolveAutoPopulate(autoFrom, triggeringAtom: triggeringAtom) {
                    fieldValues[field.key] = value
                }
            }
        }

        // 4. Apply overrides
        if let overrides = fieldOverrides {
            for (key, value) in overrides {
                fieldValues[key] = value
            }
        }

        // 5. Build structured data
        var instanceData = TemplateInstanceStructured.new(
            templateUUID: templateUUID,
            schemaVersion: templateMeta.schemaVersion
        )
        instanceData.fieldValues = fieldValues
        if let triggeringAtom {
            instanceData.spawnContext = "Triggered by \(triggeringAtom.type.displayName): \(triggeringAtom.title ?? triggeringAtom.uuid)"
        }

        let structuredData = try JSONEncoder().encode(instanceData)
        guard let structuredJson = String(data: structuredData, encoding: .utf8) else {
            print("📐 [TemplateEngine] ERROR: Failed to encode structured JSON")
            throw TemplateError.templateNotFound(templateUUID)
        }

        // 6. Build links
        let links: [AtomLink] = [
            AtomLink(type: AtomLinkType.templateDefinition.rawValue, uuid: templateUUID, entityType: AtomType.blockTemplate.rawValue, metadata: nil)
        ]

        // 7. Persist
        let instanceAtom = try await AtomRepository.shared.create(
            type: .templateInstance,
            title: instanceTitle,
            structured: structuredJson,
            links: links
        )

        // 8. Update template instance count
        var updatedMeta = templateMeta
        updatedMeta.instanceCount += 1
        updatedMeta.lastInstantiatedAt = ISO8601.string(from: Date())
        try? await updateTemplate(templateUUID, metadata: updatedMeta)

        // 9. Place on canvas if position given
        if targetPosition != nil || targetThinkspaceId != nil {
            NotificationCenter.default.post(
                name: CosmoNotification.Canvas.placeEntityOnCanvas,
                object: nil,
                userInfo: [
                    "atomUUID": instanceAtom.uuid,
                    "entityType": EntityType.template.rawValue,
                    "thinkspaceId": targetThinkspaceId as Any
                ]
            )
        }

        // 10. Post notification
        NotificationCenter.default.post(
            name: CosmoNotification.Template.instantiated,
            object: nil,
            userInfo: [
                "instanceUUID": instanceAtom.uuid,
                "templateUUID": templateUUID,
                "templateName": templateAtom.title ?? ""
            ]
        )

        print("📐 [TemplateEngine] Instantiated '\(instanceTitle)' from template '\(templateAtom.title ?? "")'")
        return instanceAtom
    }

    // MARK: - Button Execution

    /// Execute a template button's action chain
    func executeButton(buttonId: String, instanceUUID: String) async throws {
        // 1. Fetch instance
        guard var instanceAtom = try await AtomRepository.shared.fetch(uuid: instanceUUID),
              var instanceData = instanceAtom.templateInstanceData else {
            throw TemplateError.instanceNotFound(instanceUUID)
        }

        // 2. Fetch template to get button definition
        guard let templateAtom = try await AtomRepository.shared.fetch(uuid: instanceData.templateUUID),
              let templateMeta = templateAtom.blockTemplateMetadata else {
            throw TemplateError.templateNotFound(instanceData.templateUUID)
        }

        guard let button = templateMeta.buttons.first(where: { $0.id == buttonId }) else {
            throw TemplateError.buttonNotFound(buttonId)
        }

        // 3. Build automation context from instance atom
        let event = AutomationEvent(
            triggerType: .atomUpdated,
            atomUUID: instanceUUID,
            isFromSync: false
        )
        let context = await AutomationContextBuilder.build(
            event: event,
            atom: instanceAtom,
            thinkspaceId: nil
        )

        // 4. Execute action chain
        let executor = AutomationActionExecutor()
        await executor.execute(
            actions: button.actions,
            context: context,
            ruleName: "Template button: \(button.label)"
        )

        // 5. Mark button as completed
        if !instanceData.completedButtons.contains(buttonId) {
            instanceData.completedButtons.append(buttonId)
        }
        instanceAtom = instanceAtom.withTemplateInstanceData(instanceData)
        _ = try await AtomRepository.shared.update(instanceAtom)

        // 6. Post notification
        NotificationCenter.default.post(
            name: CosmoNotification.Template.buttonPressed,
            object: nil,
            userInfo: [
                "instanceUUID": instanceUUID,
                "buttonId": buttonId,
                "buttonLabel": button.label
            ]
        )

        print("📐 [TemplateEngine] Executed button '\(button.label)' on instance \(instanceUUID)")
    }

    // MARK: - Queries

    /// Fetch all template definitions
    func allTemplates() async throws -> [Atom] {
        try await AtomRepository.shared.fetchAll(type: .blockTemplate)
    }

    /// Fetch all instances of a specific template
    func instancesOf(templateUUID: String) async throws -> [Atom] {
        let all = try await AtomRepository.shared.fetchAll(type: .templateInstance)
        return all.filter { atom in
            atom.templateInstanceData?.templateUUID == templateUUID
        }
    }

    /// Fetch the template definition for a given instance
    func templateFor(instanceUUID: String) async throws -> Atom? {
        guard let instance = try await AtomRepository.shared.fetch(uuid: instanceUUID),
              let templateUUID = instance.templateDefinitionUUID else {
            return nil
        }
        return try await AtomRepository.shared.fetch(uuid: templateUUID)
    }

    /// Get cached or fetch template metadata
    func cachedTemplateMetadata(for templateUUID: String) async -> BlockTemplateMetadata? {
        if let cached = templateCache[templateUUID] {
            return cached
        }
        guard let atom = try? await AtomRepository.shared.fetch(uuid: templateUUID),
              let meta = atom.blockTemplateMetadata else {
            return nil
        }
        templateCache[templateUUID] = meta
        return meta
    }

    // MARK: - Spawn Trigger Binding

    /// Bind spawn triggers to a template by creating automation rules
    func bindSpawnTriggers(for templateUUID: String, triggers: [TemplateSpawnTrigger]) async throws {
        // First unbind existing triggers
        try await unbindSpawnTriggers(for: templateUUID)

        guard let templateAtom = try await AtomRepository.shared.fetch(uuid: templateUUID),
              var templateMeta = templateAtom.blockTemplateMetadata else {
            throw TemplateError.templateNotFound(templateUUID)
        }

        var updatedTriggers: [TemplateSpawnTrigger] = []

        for trigger in triggers {
            // Create an automation rule for this trigger
            let action = AutomationAction(
                type: .instantiateTemplate,
                config: [
                    "templateUUID": .string(templateUUID),
                    "autoFill": .string(trigger.autoFill ? "true" : "false")
                ],
                label: "Spawn \(templateAtom.title ?? "template")"
            )

            if let thinkspaceId = trigger.targetThinkspaceId {
                var actionWithThinkspace = action
                actionWithThinkspace.config["thinkspaceId"] = .string(thinkspaceId)
            }

            let triggerConfigJson = try String(data: JSONEncoder().encode(trigger.triggerConfig), encoding: .utf8) ?? "{}"
            let conditionsJson = try String(data: JSONEncoder().encode(trigger.conditions), encoding: .utf8) ?? "[]"
            let actionsJson = try String(data: JSONEncoder().encode([action]), encoding: .utf8) ?? "[]"
            let now = ISO8601.string(from: Date())

            let rule = AutomationRule(
                uuid: UUID().uuidString,
                name: "Auto-spawn: \(templateAtom.title ?? "template")",
                isEnabled: true,
                scope: .global,
                scopeId: trigger.targetThinkspaceId,
                triggerType: trigger.triggerType,
                triggerConfig: triggerConfigJson,
                conditions: conditionsJson,
                conditionLogic: .all,
                actions: actionsJson,
                priority: 50,
                cooldownSeconds: 60,
                lastFiredAt: nil,
                fireCount: 0,
                maxFires: nil,
                isBuiltIn: false,
                createdAt: now,
                updatedAt: now
            )

            // Save rule to database
            try await AutomationDispatcher.shared.createRule(rule)

            // Track the bound rule UUID
            var boundTrigger = trigger
            boundTrigger.boundRuleUUID = rule.uuid
            updatedTriggers.append(boundTrigger)

            print("📐 [TemplateEngine] Bound spawn trigger (\(trigger.triggerType.rawValue)) → rule \(rule.uuid)")
        }

        // Update template metadata with bound rule UUIDs
        templateMeta.spawnTriggers = updatedTriggers
        try await updateTemplate(templateUUID, metadata: templateMeta)
    }

    /// Unbind all spawn triggers for a template
    func unbindSpawnTriggers(for templateUUID: String) async throws {
        guard let templateAtom = try await AtomRepository.shared.fetch(uuid: templateUUID),
              let templateMeta = templateAtom.blockTemplateMetadata else {
            return
        }

        for trigger in templateMeta.spawnTriggers {
            if let ruleUUID = trigger.boundRuleUUID {
                try? await AutomationDispatcher.shared.deleteRule(uuid: ruleUUID)
                print("📐 [TemplateEngine] Unbound spawn trigger rule \(ruleUUID)")
            }
        }
    }

    // MARK: - Field Updates

    /// Update a single field value on a template instance
    func updateFieldValue(instanceUUID: String, fieldKey: String, value: ConditionValue) async throws {
        guard var atom = try await AtomRepository.shared.fetch(uuid: instanceUUID),
              var instanceData = atom.templateInstanceData else {
            throw TemplateError.instanceNotFound(instanceUUID)
        }

        instanceData.fieldValues[fieldKey] = value
        atom = atom.withTemplateInstanceData(instanceData)
        _ = try await AtomRepository.shared.update(atom)

        NotificationCenter.default.post(
            name: CosmoNotification.Template.fieldUpdated,
            object: nil,
            userInfo: [
                "instanceUUID": instanceUUID,
                "fieldKey": fieldKey
            ]
        )
    }

    // MARK: - Private Helpers

    /// Resolve auto-populate expressions like "atom.title", "date.today"
    private func resolveAutoPopulate(_ expression: String, triggeringAtom: Atom?) -> ConditionValue? {
        switch expression {
        case "date.today":
            return .string(DateFormatter.shortDate.string(from: Date()))
        case "date.now":
            return .string(ISO8601.string(from: Date()))
        case "atom.title":
            return triggeringAtom?.title.map { .string($0) }
        case "atom.uuid":
            return triggeringAtom.map { .string($0.uuid) }
        case "atom.body":
            return triggeringAtom?.body.map { .string($0) }
        case "atom.type":
            return triggeringAtom.map { .string($0.type.displayName) }
        default:
            return nil
        }
    }
}

// MARK: - Template Errors

enum TemplateError: LocalizedError {
    case templateNotFound(String)
    case instanceNotFound(String)
    case buttonNotFound(String)

    var errorDescription: String? {
        switch self {
        case .templateNotFound(let uuid): return "Template not found: \(uuid)"
        case .instanceNotFound(let uuid): return "Template instance not found: \(uuid)"
        case .buttonNotFound(let id): return "Button not found: \(id)"
        }
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
