# Inline Assistant Skill System Design

## Purpose

Cosmo's inline assistant already has the start of a skill system: prompts are routed into workflow modes like fact fill, inline edit, voice variations, content review, research answer, canvas organize, and idea strategy. The next version should turn this into a user-visible, customizable, model-aware system that can be selected with slash commands, created through an AI-guided builder, and reused across notes, content drafts, ideas, and canvases.

The goal is not to make a generic prompt-template library. The goal is to make repeatable creative workflows feel first-class: "fill facts from Josh's profile", "review this in Ben's voice", "turn this into a step-by-step carousel", "research current stats and patch slide 1", "organize this canvas", or "give me five variations in this creator's voice".

## Current System

The current implementation is functional but hardcoded.

The inline workflow layer lives mainly in `UI/InlineAssistant/CosmoInlineAssistantModels.swift`. `CosmoInlineAssistantSkill` defines the current skill contract: `id`, `name`, `description`, `route`, `requiredContext`, `toolBundles`, `outputContract`, `instructions`, `tokenBudget`, and `requiresReviewedDiff`. `CosmoInlineAssistantSkillRuntime.plan` selects a built-in skill from keyword heuristics and returns a `CosmoInlineAssistantSkillPlan`.

The inline session layer lives in `UI/InlineAssistant/CosmoInlineAssistantStore.swift`. It stores composer text, selected `@` context atoms, pane messages, proposals, pending route, `/clear`, and per-surface persistence.

The request assembly layer lives in `UI/CosmoWindow/CosmoWindowViewModel.swift`. `prepareInlineAssistantAgentRequest` takes the skill plan, resolves compact context, builds the inline system prompt, chooses forced tool bundles, and sets the model tier. Today the tier is selected as `modelOverride ?? activeProfile?.preferredModelTier ?? .sensor`.

The UI layer lives mostly in `UI/InlineAssistant/CosmoInlineAssistantBar.swift`. The bar already has the right architecture for inline command menus: `MentionComposerTextView` detects an active `@` mention and the bar presents a searchable menu. The slash menu should reuse this approach instead of replacing the composer.

There are two related systems:

- Custom agents in `UI/CosmoWindow/CollaboratorModels.swift`: persisted profiles with prompt, tool bundles, context scopes, seed prompts, and preferred model tier.
- Learned skills/lessons in `AgentContextAssembler` and lesson tools: saved rules such as voice, structure, hooks, and methodology injected into agent prompts.

The user-facing design should feel unified, but the internal model should keep these concepts separate.

## Design Principles

1. A skill is an operating mode, not just a prompt.

A skill should declare what it does, when it applies, what context it needs, which tools it can use, what model it prefers, and what kind of output it produces.

2. Explicit slash selection beats heuristic routing.

If the user selects `/Fact Fill`, the system should not second-guess it. Natural-language routing remains useful when no slash skill is selected.

3. Model choice belongs in the skill, but manual override wins.

The user should be able to say "this skill uses Haiku because it is fast" or "this skill uses GPT Chat Latest because it needs taste". The existing model picker remains the highest-priority override.

4. Context should be pre-resolved where possible.

Skills already declare `requiredContext`. The resolver should use that contract to inject compact, relevant context before the model call. Heavy tools should be escape hatches, not the default path.

5. Skill creation should be conversational.

Most users should not edit JSON or fill out a giant form. They should describe the workflow they want, answer a few targeted questions, test it, then save it.

6. Learned rules and workflow skills should not be confused.

"Always avoid corporate AI phrasing in Ben's content" is a learned rule. "Review this carousel in Ben's voice and stage fixes" is a workflow skill.

## Proposed Concepts

### Workflow Skill

A workflow skill is a reusable inline assistant mode. It can answer, stage diffs, or do both.

Proposed shape:

```swift
struct CosmoInlineSkillDefinition {
    var id: String
    var name: String
    var icon: String
    var summary: String
    var triggerPhrases: [String]
    var route: CosmoInlineAssistantRoute
    var preferredModelTier: AgentModelTier?
    var requiredContext: Set<CosmoInlineAssistantSkillContext>
    var toolBundles: Set<AgentToolBundle>
    var instructions: [String]
    var outputContract: String
    var tokenBudget: Int
    var requiresReviewedDiff: Bool
    var panePolicy: CosmoInlineSkillPanePolicy
    var isBuiltin: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

`CosmoInlineAssistantSkillID` can stay for built-in compatibility, but the runtime should move toward string IDs so custom skills do not require enum changes.

### Skill Pane Policy

Skill behavior should explicitly define whether the pane opens.

Proposed values:

```swift
enum CosmoInlineSkillPanePolicy: String, Codable {
    case neverForAction
    case openForAnswer
    case openForResearchBackedAction
    case alwaysOpenWithResult
}
```

Examples:

- Fact Fill: `neverForAction`
- Content Review: `openForAnswer`
- Web Research Patch: `openForResearchBackedAction`
- Strategy Advisor: `openForAnswer`
- Skill Builder: `alwaysOpenWithResult`

### Skill Model Policy

The request should choose model tier using this order:

```swift
manual modelOverride
    ?? selectedSlashSkill.preferredModelTier
    ?? routedSkill.preferredModelTier
    ?? activeProfile?.preferredModelTier
    ?? .sensor
```

Recommended defaults:

- Fact Fill: `.sensor`
- Plain Inline Edit: `.sensor`
- Profile-backed Slide Expansion: `.strategist`
- Voice Variations: `.strategist` by default, optional `.gptChatLatest`
- Content Review: `.strategist`
- Research Answer: `.strategist`
- Research-backed Edit: `.strategist`
- Canvas Organize: `.strategist`
- Premium Creative Rewrite: `.gptChatLatest` or `.writer`

This keeps fast factual edits fast while letting high-taste and high-context workflows use stronger models.

## Storage

Create a dedicated table for inline workflow skills rather than overloading `custom_agent_profiles`.

Proposed table: `inline_assistant_skills`

Columns:

- `id TEXT PRIMARY KEY`
- `name TEXT NOT NULL`
- `icon TEXT NOT NULL`
- `summary TEXT NOT NULL`
- `trigger_phrases TEXT NOT NULL`
- `route TEXT NOT NULL`
- `preferred_model_tier TEXT`
- `required_context TEXT NOT NULL`
- `tool_bundles TEXT NOT NULL`
- `instructions TEXT NOT NULL`
- `output_contract TEXT NOT NULL`
- `token_budget INTEGER NOT NULL`
- `requires_reviewed_diff INTEGER NOT NULL`
- `pane_policy TEXT NOT NULL`
- `is_enabled INTEGER NOT NULL DEFAULT 1`
- `is_builtin INTEGER NOT NULL DEFAULT 0`
- `created_at TEXT NOT NULL`
- `updated_at TEXT NOT NULL`
- `is_deleted INTEGER NOT NULL DEFAULT 0`
- sync metadata fields matching existing app patterns

Built-ins should be seeded through a store, similar to `CustomAgentProfileStore.ensureDefaultProfiles`.

## Runtime Architecture

### `CosmoInlineSkillStore`

Responsibilities:

- Load built-in and custom skills.
- Persist user-created skills.
- Enable, disable, update, and delete custom skills.
- Expose `enabledSkills`.
- Seed built-ins idempotently.

### `CosmoInlineSkillRegistry`

Responsibilities:

- Provide a single list of available skill definitions.
- Resolve a skill by ID.
- Merge built-ins and custom definitions.
- Give the slash menu display metadata.

This can be the same object as the store if the first implementation stays simple.

### `CosmoInlineSkillRouter`

Responsibilities:

- If `selectedSkillID` exists, return that skill.
- If the prompt starts with a slash command, parse it.
- Otherwise rank enabled skills by trigger phrases, route hints, surface kind, and existing heuristic rules.
- Fall back to the current built-in heuristic behavior.

The current `CosmoInlineAssistantSkillRuntime.plan` should become a thin wrapper around the router.

### `CosmoInlineSkillContextResolver`

This already exists but should be expanded.

Implemented now:

- `.clientProfile`
- `.activeSurface`

Needed next:

- `.clientMemory`: compact preferences and recent client-specific rules.
- `.voiceLessons`: relevant learned lessons scoped by client and intent.
- `.swipes`: selected `@` swipes and/or skill-triggered search summaries.
- `.bestPerformingContent`: compact top examples, not full transcript dumps.
- `.researchEvidence`: web/current facts when explicitly required.
- `.canvasState`: compact current thinkspace structure.

The resolver should return blocks tagged by context kind so the prompt can say exactly what is available.

## Slash Command Menu

Typing `/` in the inline assistant should open a skill menu. This should work like the existing `@` menu:

- The menu appears when the caret is in an active slash token.
- It filters as the user types.
- It supports keyboard selection.
- Selecting a skill inserts a pill-style token into the composer.
- The store records `selectedSkillID`.
- Submitting strips the slash token from the prompt before sending but passes the selected skill to the router.

Example tokens:

- `/Fact Fill`
- `/Review Content`
- `/Voice Variations`
- `/Research Patch`
- `/Canvas Organize`
- `/Create Skill`

The menu should include:

- Built-in skills first.
- User skills next.
- A final "Create Skill..." row.
- Model badge when a skill has an explicit model.
- Small route badge: `edit`, `answer`, or `edit + explain`.
- Context badges: profile, swipes, web, canvas, memory.

`/clear` should remain a command, not a skill. It should appear in the menu as a command row and keep its current session-reset behavior.

## Skill Builder

The Skill Builder should be an AI-guided creation flow in the assistant pane. It should feel like a short interview, not a settings form.

### Entry Points

- Slash menu row: `/Create Skill`
- Pane action: "New Skill"
- Natural language: "make me a skill for reviewing Ben's carousel drafts"

### Builder Flow

1. Classify what the user is trying to create.

The builder should decide between:

- workflow skill
- learned rule
- custom agent

If the user wants a repeatable inline operation, create a workflow skill. If they want a small preference or craft rule remembered, save a learned lesson. If they want a broad persona with many workflows, suggest a custom agent.

2. Ask only missing questions.

Core questions:

- What should this skill do?
- Should it edit, answer, or both?
- What context should it use?
- What model should it use: fast, balanced, premium, or explicit?
- When should it trigger automatically?
- What should it never do?

The builder should infer defaults aggressively and ask fewer questions for obvious cases.

3. Generate a draft skill.

The draft should show:

- name
- icon
- summary
- model
- route
- context
- tools
- instructions
- output contract
- trigger phrases

4. Test before save.

The builder should offer a "Try on current draft" or "Run dry test" path. A dry test should show the routed skill, prompt layer, context requirements, and expected output behavior without mutating the workspace.

5. Save.

Saving persists the skill and makes it immediately available in the slash menu.

## User-Facing Skill Management

There should be a compact skill management surface, likely reachable from the assistant pane.

Needed actions:

- Create skill
- Edit skill
- Duplicate skill
- Disable skill
- Delete custom skill
- Reset built-in skill to default
- Change model
- Change trigger phrases
- Change context/tool access
- View recent runs

Avoid building a huge settings page first. The slash menu plus builder covers most use. The management surface can be a pane sheet using the same visual language as Custom Agents.

## Interaction Examples

### Fast Fact Fill

User types:

```text
/Fact Fill replace the placeholders in slide 1 with Josh's duplex details
```

Expected behavior:

- Skill: Fact Fill
- Model: Haiku unless manually overridden
- Context: compact Josh profile, active slide text
- Pane: closed
- Output: reviewed inline diff only

### Voice Variations

User types:

```text
/Voice Variations give me five versions of this sentence in Ben's voice
```

Expected behavior:

- Skill: Voice Variations
- Model: Sonnet or configured model
- Context: active sentence, Ben profile, voice lessons, selected swipes
- Pane: open
- Output: labeled options, with option to stage one

### Research Patch

User types:

```text
/Research Patch find the current foreclosure stat and fill slide 1
```

Expected behavior:

- Skill: Research-backed Edit
- Model: Sonnet
- Context: active slide, web search evidence
- Pane: opens with short source explanation
- Output: reviewed diff plus explanation

### Custom Skill

User creates:

```text
Ben Carousel Expansion
```

Expected behavior:

- Trigger phrases include "Ben", "best performing", "step by step", "carousel".
- Required context includes client profile, swipes, best-performing content, active surface.
- Model defaults to Sonnet.
- It stages slide expansions and does not ask for angle unless context is missing.

## Error Handling

If a selected skill requires context that cannot be resolved:

- For edit-only skills, do not silently answer in the pane.
- Show a small pane or inline message explaining the missing context.
- Offer one-click fixes: add `@` context, pick client, search swipes, switch model.

If a custom skill has invalid configuration:

- Disable it from routing.
- Show it in the menu with a warning state.
- Let the user repair it through Skill Builder.

If a model is unavailable:

- Use the existing failover chain.
- Record the actual model in response metadata when possible.
- Never silently upgrade from cheap to premium unless the selected failover chain already allows it.

## Testing Strategy

Tests should cover:

- Built-in skills load from registry.
- Custom skills persist and appear in enabled skill list.
- Slash parser detects active slash token without breaking `@`.
- `/clear` remains a command.
- Selecting a slash skill pins `selectedSkillID`.
- Explicit slash skill beats heuristic route.
- Skill preferred model is used when no manual model override exists.
- Manual model override beats skill model.
- Required context drives resolver behavior.
- Edit-only skills do not open the pane.
- Research-backed edit skills open pane with explanation.
- Disabled custom skills do not route.
- Skill Builder classifies workflow skill vs learned rule vs custom agent.

## Implementation Phases

### Phase 1: Skill Registry and Model-Aware Routing

Add persisted skill definitions, seed built-ins, route through registry, and add `preferredModelTier` to inline skill plans. This phase should not change visible UI except better model routing.

### Phase 2: Slash Menu

Add slash token parser, selected skill state, skill pill rendering, and the slash menu UI. Reuse the `@` menu pattern and visual design.

### Phase 3: Skill Context Expansion

Expand resolver support for swipes, best-performing content, voice lessons, client memory, research evidence, and canvas state.

### Phase 4: Skill Builder

Add the conversational builder in the pane, with classification into workflow skill, learned rule, or custom agent.

### Phase 5: Skill Management

Add editing, duplication, disabling, deletion, model changes, and run history.

## Recommendation

Build this as a dedicated inline workflow skill system that interoperates with the existing custom agent and learned lesson systems.

Do not merge workflow skills into custom agents. Custom agents are broad collaborators. Inline skills are task-level operating modes. Do not merge workflow skills into learned lessons either. Lessons are rules; skills are workflows.

The slash menu should be the control surface, the skill registry should be the source of truth, and the AI Skill Builder should be the creation path. Model-specific skill routing should be added early because it is low-risk and immediately improves quality/cost balance.

