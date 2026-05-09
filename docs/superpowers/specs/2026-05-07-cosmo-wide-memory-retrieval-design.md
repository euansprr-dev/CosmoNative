# Cosmo-Wide Memory and Retrieval Substrate Design

Date: 2026-05-07
Status: Design approved for implementation planning
Scope: Shared substrate for Option+A, custom agents, Writing Mode, focus panels, CommandK, voice, and future automations

## Goal

Build a shared Cosmo-wide context substrate so every AI surface can reliably use the same pinned documents, client profiles, swipes, conversation memory, and long-term learned preferences. The system should feel like ChatGPT Projects or Claude Projects/Cowork: once a source is attached to a working session, Cosmo can keep using it across turns without reloading it, losing it to truncation, or answering from stale conversation state.

The immediate product target is the Option+A normal agent quality problem, but the architecture must not be Option+A-specific. Option+A should become one consumer of the same context and memory system that Writing Mode, focus-mode copilots, CommandK, and background agents use.

## Current Context

Cosmo already has several useful primitives:

- `Cosmo/HybridSearchEngine.swift` provides hybrid keyword and vector search over atoms.
- `Data/Search/AtomSearchEngine.swift` and `atoms_fts` provide BM25-style full-text search.
- `AI/VectorDatabase.swift` stores local Nomic embeddings through `DaemonXPCClient`.
- `Agent/Memory/ConversationMemoryService.swift` persists conversations and includes early semantic search over conversation summaries.
- `Agent/Core/AgentContextAssembler.swift` assembles static prompt, dynamic live context, conversation summaries, and linked atom context.
- `UI/CosmoWindow/CosmoWindowViewModel.swift` tracks `linkedAtomUUIDs` from `@` mentions.
- `MentionContextHelper` can expand mentioned atoms inline, currently with full bodies by default.

The missing pieces are at the substrate level:

- `@` mentions are expanded into one message but are not modeled as durable session sources with their own retrieval policy.
- Linked atom context is truncated to small prefixes in later turns, so details later in a document can disappear.
- Retrieval is atom-level, not chunk-level, so exact facts inside long docs are fragile.
- Conversation memory can be overwritten or polluted by visible UI messages unless persistence treats the agent transcript as canonical.
- Tool results are a history artifact, not a first-class reusable memory layer.
- Different AI surfaces build context independently, so improvements in one path do not automatically improve others.

## Frontier Patterns To Adopt

### Contextual Hybrid Retrieval

Use Anthropic-style Contextual Retrieval: chunks should be indexed with short generated context headers that explain what the chunk is, where it came from, and why it matters inside the full source. Index the contextualized text in both semantic embeddings and BM25. This protects chunks from losing meaning when separated from the full document.

References:

- https://www.anthropic.com/research/contextual-retrieval
- https://developers.openai.com/api/docs/guides/retrieval
- https://developers.openai.com/api/docs/guides/tools-file-search

### Memory Hierarchy

Use a MemGPT/Letta-style memory hierarchy:

- Core memory: always-visible durable facts about the user, assistant behavior, active project, and important constraints.
- Working memory: session-local state such as pinned sources, current task, decisions, active client, and active artifact.
- Recall memory: full conversation and tool transcript search.
- Archival memory: long-term extracted facts, preferences, client rules, voice quirks, lessons, and source-derived claims.

The model should not passively hope the right context remains in recent messages. It should have tools and system policy for searching and updating the right layer.

References:

- https://docs.letta.com/guides/agents/architectures/memgpt
- https://arxiv.org/abs/2310.08560

### Sensemaking Index

Use graph and tree summary layers for knowledge work that is not a simple fact lookup:

- RAPTOR-style summary trees for long documents and multi-document brief sets.
- GraphRAG-style entity, relationship, and community summaries for clients, offers, swipes, objections, stories, proof, tasks, and content artifacts.

This lets Cosmo handle both local questions such as "where does the doc mention locks on doors?" and global questions such as "what are the core themes, contradictions, and opportunities across this project?"

References:

- https://arxiv.org/abs/2401.18059
- https://www.microsoft.com/en-us/research/publication/from-local-to-global-a-graph-rag-approach-to-query-focused-summarization/

## Selected Architecture

Create a shared `CosmoContext` subsystem under `Agent/Context/`. It owns source pinning, chunking, indexing, retrieval, memory consolidation, and context-pack assembly. All AI surfaces call into this subsystem instead of assembling doc/profile/swipe context directly.

The central API is `CosmoContextService.buildContextPack(request:)`.

Inputs:

- user query
- conversation ID
- surface ID, such as `cosmoWindow`, `writingMode`, `focusPanel`, `commandK`, `voice`, or `automation`
- active atom UUID, if any
- pinned source UUIDs
- selected client/profile, if any
- retrieval purpose, such as fact lookup, brainstorm, writing, memory, or global synthesis
- token budget

Output:

- `AgentContextPack`, containing pinned source summaries, retrieved chunks, memory blocks, conversation recall snippets, provenance, token estimates, and user-facing trace rows.

The context pack is then injected by `AgentContextAssembler` and made available to tools. Writing Mode and other systems can consume the same pack directly.

## Core Units

### `ContextSource`

Represents a durable source the AI can use. Sources include atoms, client profiles, swipe analyses, generated drafts, files, conversation transcripts, web captures, and future connector docs.

Fields:

- source ID
- source kind
- atom UUID or external ID
- title
- body hash
- metadata hash
- owner surface
- client UUID
- timestamps
- pin state
- indexing state

### `ContextSession`

Represents the working set for a conversation or surface. It stores pinned sources, active atom, active client, recent decisions, and retrieval preferences. Option+A `linkedAtomUUIDs` becomes a compatibility view over `ContextSession.pinnedSourceIDs`.

### `ContextChunk`

Represents a retrievable slice of a source.

Fields:

- chunk ID
- source ID
- ordinal
- raw text
- contextual header
- searchable text
- token count
- anchor path
- exact line or block range where available
- body hash
- embedding status

### `ContextIndexStore`

Stores chunk metadata, BM25 text, and vector references. It should reuse GRDB and the local embedding daemon. The first version can store embeddings in `VectorDatabase` using entity type `contextChunk` or a compatible metadata table.

### `CosmoRetrievalService`

Runs retrieval over the active session and optional wider scopes.

Default retrieval pipeline:

1. Normalize the user query.
2. Decide query class.
3. Run exact phrase and BM25 search over pinned chunks.
4. Run semantic search over pinned chunks.
5. Optionally search broader Cosmo memory or all atoms.
6. Merge with reciprocal rank fusion.
7. Rerank top candidates with a cheap model or deterministic scorer.
8. Return the smallest evidence pack that can answer the question.

### `CosmoMemoryService`

Owns core, working, recall, and archival memory.

Responsibilities:

- promote important facts into core or archival memory
- keep conversation and tool transcripts searchable
- summarize stale working memory without deleting full source access
- expose memory search and memory update tools to agents
- keep user-editable memory records as `.userPreference` or `.systemEvent` atoms with explicit scope metadata

### `ContextPackAssembler`

Builds the final prompt-ready pack. It prioritizes:

1. safety and source boundary rules
2. active user request
3. pinned source evidence for the current request
4. core and working memory
5. recent messages
6. recall snippets
7. global summaries only when needed

Long documents should appear near the top of long-context prompts when they are intentionally included in full. Retrieval snippets should appear near the user query with explicit provenance.

## Query Policy

The retrieval policy is as important as the index.

### Fact Lookup

Example: "Does this doc mention locks on doors?"

Behavior:

- Search pinned sources first.
- Use exact and lexical search heavily.
- Return quoted evidence and source title.
- If no evidence is found, say what was searched.
- Do not answer from memory alone.

### Brainstorm

Example: "Help me think through this offer."

Behavior:

- Retrieve active brief, client profile, relevant swipes, and user preferences.
- Prefer diverse evidence over near duplicates.
- Include enough grounding to make ideas specific.

### Writing

Example: "Draft slide 4 from this brief."

Behavior:

- Retrieve client voice, active doc, swipe mechanics, and previous draft decisions.
- Send the same context pack to writing tools and inline chat.
- Avoid duplicating or contradicting writing-engine context.

### Memory Question

Example: "What did we decide last time?"

Behavior:

- Search recall memory and working memory.
- Include timestamps and conversation/source titles.
- Separate decisions from suggestions.

### Global Synthesis

Example: "What are the themes across this project?"

Behavior:

- Use RAPTOR summaries and GraphRAG community summaries.
- Retrieve representative chunks only after identifying candidate themes.
- Return synthesis with provenance.

## Integration Points

### Option+A Cosmo Window

- On `@` mention, pin source to the `ContextSession`.
- Preserve full agent transcript and visible message archive separately.
- Every turn asks `CosmoContextService` for a context pack.
- Tool activity should show source retrieval rows such as "Searching pinned doc: Walking Beam brief" and "Found: locks on doors".

### Custom Agents

- Custom profiles keep their existing tool bundle and prompt behavior.
- They consume the same context pack, filtered by their permissions.
- A custom agent can request narrower context but cannot bypass source truth rules.

### Writing Mode

- Writing tools receive context source UUIDs and context-pack snippets.
- Large writing tasks use active content, client profile, source docs, swipe analyses, and prior decisions from the shared substrate.
- Revision tools search the same memory layers for previous feedback and client voice quirks.

### Focus Panels

- Focus panels create short-lived context sessions scoped to the active atom.
- If the global Option+A window opens inside a focus mode, it can inherit the focus session.

### CommandK

- CommandK keeps its fast search UI, but can optionally use the chunk index for document-level and passage-level results.
- Selecting a result can pin either the full atom or a specific chunk anchor to the active session.

### Voice and Automations

- Voice commands use the same memory search and source pinning, but default to lower token budgets.
- Automations run with explicit project/session scopes so they do not leak context across workspaces.

## Cost Strategy

- Index chunks asynchronously after source creation or update.
- Use local Nomic embeddings through `DaemonXPCClient` by default.
- Use contextual chunk headers lazily for high-value sources first: pinned docs, client profiles, swipes, and active content.
- Cache context packs per conversation turn when the query, pinned sources, and source hashes are unchanged.
- Use exact/BM25 retrieval before semantic retrieval for obvious phrase searches.
- Use reranking only on the top 20 to 40 candidates.
- Use premium models only for memory consolidation, contextual chunk annotation, and global synthesis where cheaper methods fail.

## Privacy and Safety

- Retrieval must respect source scope: session-pinned, active project, client, all local atoms, or external connector.
- Context packs should include source provenance and scope labels.
- Memory writes require clear evidence. The agent should not turn speculative brainstorming into durable user preferences.
- Sensitive fields can be marked non-archival and excluded from long-term memory.
- The user must be able to inspect, edit, and delete core and archival memories.

## Testing Strategy

The current repository has a test harness issue:

- `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test` reports that the scheme has no test action.
- `swift test --list-tests` fails because the package target includes mixed-language source files.

The implementation plan must first establish a reliable test path. After that, coverage should include:

- chunking preserves exact phrases in later chunks
- pinned sources survive across turns
- exact phrase retrieval beats semantic-only retrieval for literal questions
- retrieved chunks include source title and anchor
- context packs do not append stale visible user messages after final assistant replies
- memory consolidation distinguishes decisions, preferences, source facts, and suggestions
- Option+A, Writing Mode, and focus panels consume the same context pack API
- degraded mode works when embeddings are unavailable

## Non-Goals

- Do not replace every existing search UI in the first pass.
- Do not build a cloud-only vector database.
- Do not force every query through expensive LLM reranking.
- Do not let custom agents define their own private memory substrate.
- Do not auto-save every assistant guess as memory.

## Rollout

Phase 1: Reliability foundation

- test harness
- context source/session models
- chunk-level indexing for atoms
- exact and hybrid retrieval over pinned sources
- Option+A integration

Phase 2: Shared adoption

- Writing Mode integration
- focus panel integration
- CommandK passage results
- retrieval tools for all agents

Phase 3: Memory hierarchy

- core memory
- working memory
- recall transcript search
- archival memory extraction and user-edit UI hooks

Phase 4: Sensemaking

- RAPTOR summaries for long docs
- GraphRAG entity and relationship summaries
- global synthesis policy

Phase 5: Quality and cost tuning

- reranking
- eval datasets
- latency/cost instrumentation
- memory write review flows

## Spec Self-Review

- Template-marker scan: no unfinished markers remain.
- Internal consistency: the design keeps one shared substrate and makes Option+A a consumer rather than a special case.
- Scope check: the work is intentionally large, so the implementation plan must be phased. Phase 1 must deliver user-visible reliability before GraphRAG and long-term memory work.
- Ambiguity check: "remember once read" means durable source access plus retrieval, not stuffing every document into every prompt forever.
