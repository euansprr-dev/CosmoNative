import SwiftUI
import GRDB

enum PromptTransformPolicy: String, Codable, Sendable {
    case dockedExistingArtifact
    case connectionExistingArtifact
}

enum CollaboratorEditPolicy: String, Codable, Sendable {
    case insertFirst
}

enum CollaboratorContextSource: String, Codable, Sendable, CaseIterable {
    case activeArtifact
    case linkedContext
    case note
    case profile
    case contextBundle
}

enum AgentToolBundle: String, Codable, Sendable, CaseIterable, Identifiable {
    case workspaceEditing
    case webResearch
    case contentSearch
    case clientProfiles
    case clientMemory
    case swipes
    case writing
    case strategy
    case canvasSpatial
    case scheduling
    case analytics
    case preferences

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .workspaceEditing: return "Workspace Editing"
        case .webResearch: return "Web Research"
        case .contentSearch: return "Content Search"
        case .clientProfiles: return "Client Profiles"
        case .clientMemory: return "Client Memory"
        case .swipes: return "Swipes"
        case .writing: return "Writing"
        case .strategy: return "Strategy"
        case .canvasSpatial: return "Canvas Spatial"
        case .scheduling: return "Scheduling"
        case .analytics: return "Analytics"
        case .preferences: return "Preferences"
        }
    }

    var icon: String {
        switch self {
        case .workspaceEditing: return "text.badge.checkmark"
        case .webResearch: return "globe"
        case .contentSearch: return "doc.text.magnifyingglass"
        case .clientProfiles: return "person.crop.rectangle.stack"
        case .clientMemory: return "person.badge.clock"
        case .swipes: return "rectangle.stack"
        case .writing: return "pencil.and.scribble"
        case .strategy: return "point.3.connected.trianglepath.dotted"
        case .canvasSpatial: return "square.grid.3x3"
        case .scheduling: return "calendar"
        case .analytics: return "chart.bar"
        case .preferences: return "slider.horizontal.3"
        }
    }

    var accessDescription: String {
        switch self {
        case .workspaceEditing:
            return "Lets the agent stage reviewed edits for the active document, focus mode, structured fields, or canvas without directly applying changes."
        case .webResearch:
            return "Lets the agent search the web for current information, sources, stats, market examples, and facts outside your local Cosmo database."
        case .contentSearch:
            return "Lets the agent search, read, create, and update Cosmo ideas, content, captures, and thinkspaces."
        case .clientProfiles:
            return "Lets the agent list and read client profiles, voice notes, brand angles, audience models, and client-tagged work."
        case .clientMemory:
            return "Lets the agent read and update persistent client-specific memory such as preferences, voice quirks, forbidden patterns, and learned rules."
        case .swipes:
            return "Lets the agent search, browse, filter, analyze, score, and adapt your swipe library and hook/framework references."
        case .writing:
            return "Lets the agent use Cosmo writing tools for outlines, drafts, hooks, revisions, and content generation instead of only replying inline."
        case .strategy:
            return "Lets the agent use strategy, intelligence, insight memory, lessons, and module suggestion tools for higher-level planning and synthesis."
        case .canvasSpatial:
            return "Lets the agent inspect the current thinkspace and propose reviewable canvas plans for arranging, placing, creating, moving, and resizing blocks."
        case .scheduling:
            return "Lets the agent read and modify calendar blocks, schedule blocks, tasks, and unscheduled work."
        case .analytics:
            return "Lets the agent access performance, scoring, XP, analytics, and aggregate signals for prioritization and review."
        case .preferences:
            return "Lets the agent read and update global preferences, standing instructions, and long-term behavioral guidance."
        }
    }
}

enum CustomAgentContextScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case activeContext
    case mentions
    case database
    case web
    case clients
    case swipes
    case canvas

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .activeContext: return "Active Context"
        case .mentions: return "Mentions"
        case .database: return "Database"
        case .web: return "Web"
        case .clients: return "Clients"
        case .swipes: return "Swipes"
        case .canvas: return "Canvas"
        }
    }

    var icon: String {
        switch self {
        case .activeContext: return "scope"
        case .mentions: return "at"
        case .database: return "cylinder.split.1x2"
        case .web: return "globe"
        case .clients: return "person.crop.rectangle.stack"
        case .swipes: return "rectangle.stack"
        case .canvas: return "square.grid.3x3"
        }
    }

    var accessDescription: String {
        switch self {
        case .activeContext:
            return "Includes the current Cosmo workspace, focused item, selected text, visible item count, filters, and surface-specific state."
        case .mentions:
            return "Includes atoms explicitly referenced with @ mentions, expanded with title, body, UUID, type, and swipe analysis when available."
        case .database:
            return "Allows the agent to reason across local Cosmo docs, notes, ideas, content, research, tasks, and other database-backed records."
        case .web:
            return "Allows the agent to combine local context with online research when web research tools are also enabled."
        case .clients:
            return "Allows the agent to use client profiles, client-tagged work, and client memory as relevant context."
        case .swipes:
            return "Allows the agent to use swipe analyses, hooks, frameworks, formats, emotions, and structural references as context."
        case .canvas:
            return "Allows the agent to use the current thinkspace/canvas state and propose spatial plans tied to that workspace."
        }
    }
}

struct CollaboratorSessionKey: Hashable, Codable, Sendable {
    let artifactUUID: String
    let presetID: String

    var conversationID: String {
        "cosmo-collaborator-\(presetID)-\(artifactUUID)"
    }
}

enum CollaborationEditOperation: Equatable, Sendable {
    case insertAtSelection(String)
    case insertAfterBlock(String)
    case appendSectionItem(String, String)
    case replaceSelection(String)
    case annotateRange(String)
    case showGhostCursor(String?)
}

enum CosmoProposedEditOperation: String, Codable, Sendable {
    case insertAtCursor
    case appendToDocument
    case replaceSelection
}

enum CosmoProposedEditDiffKind: String, Codable, Sendable {
    case context
    case removed
    case added
}

struct CosmoProposedEditDiffLine: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var kind: CosmoProposedEditDiffKind
    var text: String

    init(id: UUID = UUID(), kind: CosmoProposedEditDiffKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

struct CosmoProposedEdit: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var targetTitle: String
    var targetEditorID: String
    var operation: CosmoProposedEditOperation
    var originalText: String?
    var proposedText: String
    var rationale: String
    var createdAt: Date

    var diffLines: [CosmoProposedEditDiffLine] {
        guard operation == .replaceSelection,
              let originalText,
              !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [.init(kind: .added, text: proposedText)]
        }
        return [
            .init(kind: .removed, text: originalText),
            .init(kind: .added, text: proposedText)
        ]
    }

    static func insertion(
        targetTitle: String,
        targetEditorID: String,
        operation: CosmoProposedEditOperation,
        proposedText: String,
        rationale: String
    ) -> CosmoProposedEdit {
        CosmoProposedEdit(
            id: UUID(),
            targetTitle: targetTitle,
            targetEditorID: targetEditorID,
            operation: operation,
            originalText: nil,
            proposedText: proposedText,
            rationale: rationale,
            createdAt: Date()
        )
    }

    static func replacement(
        targetTitle: String,
        targetEditorID: String,
        originalText: String,
        replacementText: String,
        rationale: String
    ) -> CosmoProposedEdit {
        CosmoProposedEdit(
            id: UUID(),
            targetTitle: targetTitle,
            targetEditorID: targetEditorID,
            operation: .replaceSelection,
            originalText: originalText,
            proposedText: replacementText,
            rationale: rationale,
            createdAt: Date()
        )
    }
}

enum CollaborationTargetSource: Equatable, Codable, Sendable {
    case focusMode
    case pane(paneID: String)
}

struct CollaborationTarget: Equatable, Codable, Sendable {
    let source: CollaborationTargetSource
    let entityID: Int64
    let entityType: EntityType
    let atomUUID: String
    let title: String

    var entitySelection: EntitySelection {
        EntitySelection(id: entityID, type: entityType)
    }

    var paneID: String? {
        guard case .pane(let paneID) = source else { return nil }
        return paneID
    }

    var isPaneTarget: Bool {
        paneID != nil
    }

    var displayTypeLabel: String {
        switch entityType {
        case .connection: return "Connection"
        case .content: return "Content"
        case .idea: return "Idea"
        case .note: return "Note"
        default: return entityType.rawValue.capitalized
        }
    }
}

struct CollaboratorPreset: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let name: String
    let transformPolicy: PromptTransformPolicy
    let sourcePrompt: String
    let runtimePrompt: String
    let compatibleSurfaces: [EntityType]
    let allowedContextSources: [CollaboratorContextSource]
    let defaultEditPolicy: CollaboratorEditPolicy
    let seedPrompts: [String]

    static let deepen = CollaboratorPreset(
        id: "deepen",
        name: "Deepen",
        transformPolicy: .dockedExistingArtifact,
        sourcePrompt: CollaboratorPromptLibrary.sourcePrompt,
        runtimePrompt: CollaboratorPromptLibrary.runtimePrompt(for: .dockedExistingArtifact),
        compatibleSurfaces: [.idea, .note, .connection, .content],
        allowedContextSources: [.activeArtifact, .linkedContext, .note, .profile, .contextBundle],
        defaultEditPolicy: .insertFirst,
        seedPrompts: CollaboratorPromptLibrary.seedPrompts
    )

    static let deepenConnection = CollaboratorPreset(
        id: "deepen.connection",
        name: "Deepen",
        transformPolicy: .connectionExistingArtifact,
        sourcePrompt: CollaboratorPromptLibrary.sourcePrompt,
        runtimePrompt: CollaboratorPromptLibrary.runtimePrompt(for: .connectionExistingArtifact),
        compatibleSurfaces: [.connection],
        allowedContextSources: [.activeArtifact, .linkedContext, .note, .profile, .contextBundle],
        defaultEditPolicy: .insertFirst,
        seedPrompts: CollaboratorPromptLibrary.seedPrompts
    )
}

struct CustomAgentProfile: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var name: String
    var icon: String
    var summary: String
    var runtimePrompt: String
    var seedPrompts: [String]
    var toolBundles: [AgentToolBundle]
    var contextScopes: [CustomAgentContextScope]
    var preferredModelTier: AgentModelTier?
    var isEnabled: Bool
    var isBuiltin: Bool
    var createdAt: Date
    var updatedAt: Date

    var routingPromptLayer: String {
        let bundles = toolBundles.map(\.displayName).joined(separator: ", ")
        let scopes = contextScopes.map(\.displayName).joined(separator: ", ")
        return """
        ## Selected Cosmo Agent: \(name)
        Summary: \(summary)
        Allowed tool bundles: \(bundles.isEmpty ? "None" : bundles)
        Allowed context scopes: \(scopes.isEmpty ? "None" : scopes)

        \(runtimePrompt)
        """
    }

    static var blankCustom: CustomAgentProfile {
        let now = Date()
        return CustomAgentProfile(
            id: UUID().uuidString,
            name: "New Agent",
            icon: "sparkles",
            summary: "A focused Cosmo agent.",
            runtimePrompt: "Help the user with a focused, high-context workflow. Ask only when a decision is genuinely blocked.",
            seedPrompts: [
                "Help me think through this",
                "Summarize what matters here",
                "Turn this into next steps"
            ],
            toolBundles: [.contentSearch, .writing],
            contextScopes: [.activeContext, .mentions, .database],
            preferredModelTier: nil,
            isEnabled: true,
            isBuiltin: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

enum PendingCanvasOperationKind: String, Codable, Sendable, CaseIterable {
    case arrange
    case placeSearch = "place_search"
    case createEntity = "create_entity"
    case placeExistingAtom = "place_existing_atom"
    case moveSelection = "move_selection"
    case resizeSelection = "resize_selection"
    case createAIBlock = "create_ai_block"
    case unsupported

    var displayName: String {
        switch self {
        case .arrange: return "Arrange"
        case .placeSearch: return "Place Results"
        case .createEntity: return "Create Card"
        case .placeExistingAtom: return "Place Existing"
        case .moveSelection: return "Move Selection"
        case .resizeSelection: return "Resize Selection"
        case .createAIBlock: return "Create AI Block"
        case .unsupported: return "Preview Only"
        }
    }
}

struct PendingCanvasOperation: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var kind: PendingCanvasOperationKind
    var summary: String
    var payload: [String: String]

    init(
        id: UUID = UUID(),
        kind: PendingCanvasOperationKind,
        summary: String,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.payload = payload
    }
}

struct PendingCanvasPlan: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var title: String
    var rationale: String
    var operations: [PendingCanvasOperation]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        rationale: String,
        operations: [PendingCanvasOperation],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.operations = operations
        self.createdAt = createdAt
    }

    var affectedObjectCount: Int {
        operations.count
    }
}

enum CollaboratorPromptLibrary {
    static let seedPrompts: [String] = [
        "What specifically about this is interesting to you?",
        "What problem does this solve?",
        "What's the link you're seeing?",
        "What would the better version look like?"
    ]

    static let sourcePrompt = #"""
You are an idea catcher and creative thought partner. When the user has a thought — half-formed, messy, a single sentence, a link, a screenshot — you catch it and put it somewhere it won't die. But you're more than a filing system. You're fresh eyes on their thinking. You spot patterns they can't see, name concepts they use but haven't crystallized, and push half-formed ideas toward breakthrough insights through Socratic questioning.
You operate at two speeds: fast capture (save it, sharpen it, move on) and deep development (dig in, challenge, find what's uniquely theirs). The user controls which mode they're in — most interactions are fast capture, but when they want to develop an idea, you shift into thought partner mode.
### Initialization
```
I'm your idea catcher. Whenever you have a thought — a content idea, a business idea, a random connection, something you want to explore later — just send it to me. It can be messy. One sentence, a link, a half-formed question. Doesn't matter.

I'll capture it, ask you one question to sharpen it, and save it. But here's where it gets interesting — over time I start seeing patterns in your thinking that you can't see yourself. Connections between ideas, themes you keep returning to, concepts you use but haven't named yet. When you want to develop an idea, I'll dig in with you and help you find what's uniquely yours in it.

Two quick things:

1. What kind of ideas do you usually have? Content, business, product, creative, research, all of the above?

2. Do you already organize ideas somewhere, or do they live scattered across notes apps and texts?
```
After they respond:
- Create an Ideas folder in the workspace with Raw, Developing, Ready, and Archived sub-folders if there isn't already a folder system for ideas. Create an Idea Profile (pre-filled) and Idea Themes tracker in the agent's knowledge base.
- After the folder and notes are created, schedule the tasks yourself directly — do not include scheduling inside another task. Schedule a weekly idea review (default: Friday or Sunday) and a monthly ideas report.
- Ask them to send their first idea right now.
### How capture works
When the user sends anything: acknowledge instantly, then ask one sharpening question. Pick the question that pushes the idea one step further:
- If the idea is vague: "What specifically about this is interesting to you?"
- If it's an observation: "What would you do with this?"
- If it's a content topic: "Who is this for and what would they take away?"
- If it's a business/product idea: "What problem does this solve?"
- If it's a question: "What's your instinct on the answer?"
- If it's a connection between things: "What's the link you're seeing?"
- If it's a reaction to something: "What would the better version look like?"
If they say "just save this" or the idea is already sharp, skip the question.
Save as a markdown note in Ideas/Raw with the original input preserved, tags, and a 1-2 sentence "Potential" note on what it could become.
**After saving, check two things:**
1. **Related ideas** — scan the workspace for ideas that connect. If something's related, mention it naturally. Don't force it.
2. **Related projects** — ask if this connects to anything they're actively working on (a newsletter, a video series, a product, a specific project folder in their workspace). If yes, add a backlink to that project folder or item in the idea note so they can find it in context later. This is how raw ideas get connected to real work.
**Then, if the idea has depth worth exploring** — it's counterintuitive, it connects to multiple themes, it challenges conventional thinking, or it hints at something the user hasn't fully articulated — offer to go deeper: "There's something interesting here. Want to dig in and see what's underneath it?" or "This feels like it could be a bigger idea than it looks. Want to explore it?"
Don't offer this for every idea — most captures are quick saves and should stay that way. But when you sense an idea has untapped potential or could lead to an original insight, say so. The user can always say no and you move on.
### How development works (thought partner mode)
When the user says yes to going deeper, or continues adding to the idea or note, or asks "help me develop [idea]" or "let's dig into this," shift into creative thought partner mode. This is where you go deeper than capture — you're mining for what's uniquely theirs.
Use these four drivers:
**Pattern spotting:** Look for gaps between their approach and the standard approach. "I notice you emphasize X while most people in your space focus on Y — tell me more about that choice." Surface what they do differently without realizing it.
**Paradox hunting:** Search for counterintuitive truths in what they're saying. When they get better results by doing the opposite of conventional wisdom, dig in: "It sounds like you get more by doing less here — is that intentional?" Paradoxes are the most powerful insights because they capture what makes someone's thinking genuinely original.
**Naming the unnamed:** When you spot a concept, process, or philosophy they use but haven't crystallized, help them name it. "This seems like it has a name — what do you call this approach?" or "There's a mechanism here you haven't labeled yet." Don't move on until the concept has a name — even a working title.
**Contrast creation:** Find the opposite of their method to highlight what makes it unique. "You do X while everyone else does Y" moments. Help them see why the difference matters.
**Development rules:**
- Ask one question at a time, building on their previous answer
- Challenge generic claims ("I care more about quality") with follow-ups until you find something specific and memorable
- When you sense something counterintuitive, dig deeper immediately — paradoxes are gold
- Don't compliment — observe, challenge, or dig deeper
- When you spot a potential breakthrough concept, test names: "Does '[name]' capture this?"
- Keep it conversational, not like a questionnaire
When development reaches a breakthrough insight, update the idea note with: the core insight, a suggested name, how it makes their thinking different, and what it could become. Move the idea to Ideas/Developing.
### How ideas move through the pipeline
**Raw → Developing:** When an idea has been sharpened or developed through conversation, add what you've uncovered — audience, format, key points, breakthrough insights, named concepts. Move to Developing.
**Developing → Ready:** When the idea is fleshed out enough to act on, add an action plan and suggest where in their workspace it should live. If it connects to a project, include the backlink. Move to Ready. Tell them: "This one's ready to become something."
### Weekly idea review
Review recent captures, surface 2-3 undeveloped ideas worth revisiting (especially ones with untapped potential you noticed during capture), flag ideas that are ready to develop or act on, check for new connections between recent and older ideas, and suggest archiving to keep things clean.
### Monthly ideas report
Themes across ideas, strongest ideas, recurring patterns, named concepts that have emerged, and one recommendation for what to explore further. Pay special attention to patterns the user might not see — themes that keep showing up across seemingly unrelated ideas, or a throughline forming between their best concepts.
### Between captures
"What ideas do I have about [topic]?" → search and surface. "Help me develop [idea]" → shift to thought partner mode. "I want to do something but don't know which idea" → recommend based on momentum and which ideas have the most untapped potential. "I'm in a brainstorm mood" → prompts and provocations based on existing ideas, themes, and paradoxes you've noticed. "What connects to [project]?" → surface all ideas backlinked to that project. "Archive [idea]" → move, no questions.
### Tone
Fast and lightweight during capture — like texting a smart friend. Brief confirmations, one-sentence questions. During development, shift to curious and challenging — you're a thought partner now, not a filing system. Excited about real connections and genuine breakthroughs. Never compliment generically — observe specifically. When something is genuinely original, name what makes it original.
"""#

    static func runtimePrompt(for policy: PromptTransformPolicy) -> String {
        switch policy {
        case .dockedExistingArtifact:
            return sourcePrompt + #"""

### Docked Existing-Artifact Override
The user is already inside an existing note, connection, idea, or content artifact.
- Do not create folders, knowledge-base trackers, scheduled reviews, or workspace notes.
- Do not save markdown notes into Ideas/Raw or move files through Raw / Developing / Ready / Archived.
- Reinterpret "capture" and "save" as preserving and sharpening the thought inside the current artifact.
- Reinterpret "update the idea note" as adding inline edits, insertions, named concepts, structured sections, or action suggestions directly into the current artifact without deleting existing work unless the user explicitly asks for a rewrite.
- Keep the one-question-at-a-time flow, question selection rules, related ideas / related projects behavior, pattern spotting, paradox hunting, naming the unnamed, contrast creation, and tone exactly as described above.
- When the prompt refers to moving something to Developing or Ready, translate that into: enrich the current artifact so it is more developed or action-ready, and suggest the next concrete move.
"""#
        case .connectionExistingArtifact:
            return sourcePrompt + #"""

### Connection Existing-Artifact Override
The user is already inside an existing Connection artifact with named sections.
- Do not create folders, knowledge-base trackers, scheduled reviews, or workspace notes.
- Do not save markdown notes into Ideas/Raw or move files through Raw / Developing / Ready / Archived.
- Reinterpret "capture" and "save" as preserving and sharpening the thought inside the current connection.
- The current connection is the working surface. Additive drafts, named concepts, structured sections, and action-ready next moves belong inside this connection.
- When the connection is blank or barely started, invite the user to send the core idea even if it is messy.
- When the connection already has material, begin from what is already written and any linked sources.
- Ask one question at a time or stage one additive draft for one connection section.
- Do not use canned phrases like "What's the tension?" unless the user used that language first.
- Keep the source prompt's question selection rules, related ideas / related projects behavior, pattern spotting, paradox hunting, naming the unnamed, contrast creation, and tone exactly as described above.
"""#
        }
    }
}

@MainActor
final class CustomAgentProfileStore: ObservableObject {
    static let shared = CustomAgentProfileStore()

    @Published private(set) var profiles: [CustomAgentProfile] = []
    @Published private(set) var error: String?

    var enabledProfiles: [CustomAgentProfile] {
        profiles.filter(\.isEnabled)
    }

    private let isoFormatter = ISO8601DateFormatter()

    private init() {}

    func loadProfiles() async {
        do {
            try await ensureDefaultProfiles()
            profiles = try await fetchProfiles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func save(_ profile: CustomAgentProfile) async {
        var updated = profile
        updated.updatedAt = Date()
        do {
            try await upsert(updated, overwriteExisting: true)
            profiles = try await fetchProfiles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ profile: CustomAgentProfile) async {
        guard !profile.isBuiltin else { return }
        do {
            let updatedAt = isoFormatter.string(from: Date())
            try await CosmoDatabase.shared.asyncWrite { db in
                try db.execute(
                    sql: """
                        UPDATE custom_agent_profiles
                        SET is_deleted = 1, updated_at = ?, _local_pending = 1, _local_version = COALESCE(_local_version, 1) + 1
                        WHERE id = ?
                    """,
                    arguments: [updatedAt, profile.id]
                )
            }
            profiles = try await fetchProfiles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setEnabled(_ isEnabled: Bool, for profile: CustomAgentProfile) async {
        var updated = profile
        updated.isEnabled = isEnabled
        await save(updated)
    }

    private func ensureDefaultProfiles() async throws {
        for profile in Self.defaultProfiles {
            try await upsert(profile, overwriteExisting: false)
        }
    }

    private func fetchProfiles() async throws -> [CustomAgentProfile] {
        try await CosmoDatabase.shared.asyncRead { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM custom_agent_profiles
                    WHERE is_deleted = 0
                    ORDER BY is_builtin DESC, name COLLATE NOCASE ASC
                """
            )
            return rows.compactMap(Self.profile(from:))
        }
    }

    private func upsert(_ profile: CustomAgentProfile, overwriteExisting: Bool) async throws {
        let encoder = JSONEncoder()
        let bundlesData = try encoder.encode(profile.toolBundles.map(\.rawValue))
        let scopesData = try encoder.encode(profile.contextScopes.map(\.rawValue))
        let seedPromptsData = try encoder.encode(profile.seedPrompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let bundlesJSON = String(data: bundlesData, encoding: .utf8) ?? "[]"
        let scopesJSON = String(data: scopesData, encoding: .utf8) ?? "[]"
        let seedPromptsJSON = String(data: seedPromptsData, encoding: .utf8) ?? "[]"
        let createdAt = isoFormatter.string(from: profile.createdAt)
        let updatedAt = isoFormatter.string(from: profile.updatedAt)
        let preferredTier = profile.preferredModelTier?.rawValue

        try await CosmoDatabase.shared.asyncWrite { db in
            if overwriteExisting {
                try db.execute(
                    sql: """
                        INSERT INTO custom_agent_profiles (
                            id, name, icon, summary, runtime_prompt, seed_prompts, tool_bundles, context_scopes,
                            preferred_model_tier, is_enabled, is_builtin, created_at, updated_at, is_deleted, _local_pending
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 1)
                        ON CONFLICT(id) DO UPDATE SET
                            name = excluded.name,
                            icon = excluded.icon,
                            summary = excluded.summary,
                            runtime_prompt = excluded.runtime_prompt,
                            seed_prompts = excluded.seed_prompts,
                            tool_bundles = excluded.tool_bundles,
                            context_scopes = excluded.context_scopes,
                            preferred_model_tier = excluded.preferred_model_tier,
                            is_enabled = excluded.is_enabled,
                            updated_at = excluded.updated_at,
                            is_deleted = 0,
                            _local_pending = 1,
                            _local_version = COALESCE(custom_agent_profiles._local_version, 1) + 1
                    """,
                    arguments: [
                        profile.id, profile.name, profile.icon, profile.summary, profile.runtimePrompt,
                        seedPromptsJSON, bundlesJSON, scopesJSON, preferredTier, profile.isEnabled ? 1 : 0,
                        profile.isBuiltin ? 1 : 0, createdAt, updatedAt
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO custom_agent_profiles (
                            id, name, icon, summary, runtime_prompt, seed_prompts, tool_bundles, context_scopes,
                            preferred_model_tier, is_enabled, is_builtin, created_at, updated_at, is_deleted
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                    arguments: [
                        profile.id, profile.name, profile.icon, profile.summary, profile.runtimePrompt,
                        seedPromptsJSON, bundlesJSON, scopesJSON, preferredTier, profile.isEnabled ? 1 : 0,
                        profile.isBuiltin ? 1 : 0, createdAt, updatedAt
                    ]
                )
            }
        }
    }

    private static func profile(from row: Row) -> CustomAgentProfile? {
        let decoder = JSONDecoder()
        let bundleRaw = decodeStringArray(row["tool_bundles"] as? String, decoder: decoder)
        let scopeRaw = decodeStringArray(row["context_scopes"] as? String, decoder: decoder)
        let storedSeedPrompts = decodeStringArray(row["seed_prompts"] as? String, decoder: decoder)
        let formatter = ISO8601DateFormatter()
        let createdAt = formatter.date(from: row["created_at"] as? String ?? "") ?? Date()
        let updatedAt = formatter.date(from: row["updated_at"] as? String ?? "") ?? createdAt
        let isBuiltin = (row["is_builtin"] as? Int64 ?? 0) != 0

        guard
            let id = row["id"] as? String,
            let name = row["name"] as? String,
            let icon = row["icon"] as? String,
            let summary = row["summary"] as? String,
            let runtimePrompt = row["runtime_prompt"] as? String
        else {
            return nil
        }

        let displayName = isBuiltin && id == "writing-editor" && name == "Writing Editor"
            ? "Writing Mode"
            : name
        let displaySummary = isBuiltin && id == "writing-editor" && summary == "Improves drafts with voice, structure, swipe, and client context."
            ? "Uses Cosmo's dedicated writing engine for drafts, hooks, outlines, and revisions."
            : summary

        return CustomAgentProfile(
            id: id,
            name: displayName,
            icon: icon,
            summary: displaySummary,
            runtimePrompt: runtimePrompt,
            seedPrompts: storedSeedPrompts.isEmpty ? defaultSeedPrompts(for: id) : storedSeedPrompts,
            toolBundles: bundleRaw.compactMap(AgentToolBundle.init(rawValue:)),
            contextScopes: scopeRaw.compactMap(CustomAgentContextScope.init(rawValue:)),
            preferredModelTier: (row["preferred_model_tier"] as? String).flatMap(AgentModelTier.init(rawValue:)),
            isEnabled: (row["is_enabled"] as? Int64 ?? 1) != 0,
            isBuiltin: isBuiltin,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func decodeStringArray(_ json: String?, decoder: JSONDecoder) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? decoder.decode([String].self, from: data)) ?? []
    }

    private static func defaultSeedPrompts(for id: String) -> [String] {
        switch id {
        case "planning-agent":
            return [
                "Help me build this plan",
                "Find the strongest direction",
                "What should this become?"
            ]
        case "idea-collaborator":
            return [
                "Help me develop this idea",
                "Find the strongest angle here",
                "What question should I answer next?"
            ]
        case "researcher":
            return [
                "Research this online and find current stats",
                "Find sources that support or challenge this",
                "Compare this against recent examples"
            ]
        case "canvas-organizer":
            return [
                "Organize this thinkspace",
                "Create a canvas plan from this context",
                "Place the most relevant supporting ideas",
                "Split this note into structured clusters"
            ]
        case "writing-editor":
            return [
                "Start a writing session",
                "Draft with the writing engine",
                "Revise the current draft"
            ]
        default:
            return [
                "Help me think through this",
                "Summarize what matters here",
                "Turn this into next steps"
            ]
        }
    }

    private static var defaultProfiles: [CustomAgentProfile] {
        let now = Date()
        return [
            CustomAgentProfile(
                id: "planning-agent",
                name: "Planning Agent",
                icon: "point.3.connected.trianglepath.dotted",
                summary: "Turns messy goals, brand thoughts, and strategy notes into living plans.",
                runtimePrompt: """
                You are Cosmo's planning partner. Help the user turn messy strategic thinking into clear, living plans for branding, niche, offers, creative direction, systems, and personal operating models.

                Work like the Connection collaborator: start from the active artifact, ask one question at a time when a decision is missing, spot patterns, hunt useful paradoxes, name unnamed mechanisms, and create sharp contrasts between the user's real approach and generic advice.

                When the user has a note, idea, content draft, or connection open, treat that artifact as the working surface. Prefer staging additive edits, section suggestions, or replacements for review instead of only explaining in chat. If replacement is better than appending, say what should be replaced and why so the UI can show a clear red/added diff.

                Keep the voice direct and useful. Do not compliment generically. Preserve decisions the user already approved.
                """,
                seedPrompts: defaultSeedPrompts(for: "planning-agent"),
                toolBundles: [.contentSearch, .strategy, .preferences, .clientProfiles, .swipes],
                contextScopes: [.activeContext, .mentions, .database, .clients, .swipes],
                preferredModelTier: nil,
                isEnabled: true,
                isBuiltin: true,
                createdAt: now,
                updatedAt: now
            ),
            CustomAgentProfile(
                id: "idea-collaborator",
                name: "Idea Collaborator",
                icon: "lightbulb.max",
                summary: "Sharpen raw thoughts, find patterns, and develop ideas inline.",
                runtimePrompt: CollaboratorPromptLibrary.runtimePrompt(for: .dockedExistingArtifact),
                seedPrompts: defaultSeedPrompts(for: "idea-collaborator"),
                toolBundles: [.contentSearch, .swipes, .writing, .strategy, .clientProfiles],
                contextScopes: [.activeContext, .mentions, .database, .swipes, .clients],
                preferredModelTier: .strategist,
                isEnabled: true,
                isBuiltin: true,
                createdAt: now,
                updatedAt: now
            ),
            CustomAgentProfile(
                id: "researcher",
                name: "Researcher",
                icon: "globe.americas",
                summary: "Research online, find stats, and connect sources back to your database.",
                runtimePrompt: """
                You are Cosmo's research specialist. Search externally when the user asks for current facts, stats, market signals, examples, or citations. Cross-check findings against available Cosmo context, keep sourcing explicit, and separate verified facts from inference.
                """,
                seedPrompts: defaultSeedPrompts(for: "researcher"),
                toolBundles: [.webResearch, .contentSearch, .clientProfiles, .swipes, .strategy],
                contextScopes: [.activeContext, .mentions, .database, .web, .clients, .swipes],
                preferredModelTier: .strategist,
                isEnabled: true,
                isBuiltin: true,
                createdAt: now,
                updatedAt: now
            ),
            CustomAgentProfile(
                id: "canvas-organizer",
                name: "Canvas Organizer",
                icon: "square.grid.3x3",
                summary: "Plans spatial changes for the current thinkspace and waits for approval.",
                runtimePrompt: """
                You are Cosmo's thinkspace organizer. Read the current canvas context, infer a clean spatial structure, and propose a pending canvas plan instead of mutating immediately. Group related items, reduce clutter, preserve user intent, and explain the spatial rationale briefly.

                When the user asks to split, structure, cluster, modularize, or organize a long note into a thinkspace:
                - Use inspect_current_thinkspace first when spatial context is needed.
                - Use propose_note_structure_plan for the final proposal.
                - Do not rewrite, summarize, compress, improve, or paraphrase module bodies.
                - Propose UTF-16 source ranges into the active source note body.
                - Titles and cluster names may be concise labels, but module body content must be copied by the app from the source ranges.
                - Keep the original source note visible by default. Only hide or archive it if the user explicitly asks.
                - If the target thinkspace cannot be resolved, ask which thinkspace to use before proposing.
                """,
                seedPrompts: defaultSeedPrompts(for: "canvas-organizer"),
                toolBundles: [.canvasSpatial, .contentSearch, .swipes, .clientProfiles, .strategy],
                contextScopes: [.activeContext, .mentions, .database, .canvas, .clients, .swipes],
                preferredModelTier: .strategist,
                isEnabled: true,
                isBuiltin: true,
                createdAt: now,
                updatedAt: now
            ),
            CustomAgentProfile(
                id: "writing-editor",
                name: "Writing Mode",
                icon: "pencil.and.scribble",
                summary: "Uses Cosmo's dedicated writing engine for drafts, hooks, outlines, and revisions.",
                runtimePrompt: """
                You are Cosmo's dedicated writing mode. Use the writing engine for substantive drafts, hooks, outlines, and revisions. Preserve client voice, apply explicit swipe/context references, and make edits feel native to the user's existing work.
                """,
                seedPrompts: defaultSeedPrompts(for: "writing-editor"),
                toolBundles: [.writing, .swipes, .clientProfiles, .clientMemory, .contentSearch, .strategy],
                contextScopes: [.activeContext, .mentions, .database, .clients, .swipes],
                preferredModelTier: .writer,
                isEnabled: true,
                isBuiltin: true,
                createdAt: now,
                updatedAt: now
            )
        ]
    }

    static func defaultProfileForTests(id: String) -> CustomAgentProfile? {
        defaultProfiles.first { $0.id == id }
    }
}

@MainActor
final class CollaboratorSessionStore: ObservableObject {
    static let shared = CollaboratorSessionStore()

    @Published private(set) var activeKey: CollaboratorSessionKey?
    @Published private(set) var activeTarget: CollaborationTarget?
    @Published private(set) var activePreset: CollaboratorPreset = .deepen

    private var draftsByKey: [CollaboratorSessionKey: String] = [:]

    private init() {}

    func activate(target: CollaborationTarget, preset: CollaboratorPreset) -> CollaboratorSessionKey {
        let key = CollaboratorSessionKey(artifactUUID: target.atomUUID, presetID: preset.id)
        activeKey = key
        activeTarget = target
        activePreset = preset
        return key
    }

    func clearActive() {
        activeKey = nil
        activeTarget = nil
        activePreset = .deepen
    }

    func saveDraft(_ draft: String, for key: CollaboratorSessionKey?) {
        guard let key else { return }
        draftsByKey[key] = draft
    }

    func draft(for key: CollaboratorSessionKey?) -> String {
        guard let key else { return "" }
        return draftsByKey[key] ?? ""
    }
}
