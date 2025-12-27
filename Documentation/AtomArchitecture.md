# CosmoOS Atom Architecture

> **Single Source of Truth** - All entities in CosmoOS are Atoms. This document defines the architecture and patterns that MUST be followed for all data operations.

---

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [The Atom Model](#the-atom-model)
3. [Entity Types](#entity-types)
4. [Creating New Entities](#creating-new-entities)
5. [Querying Entities](#querying-entities)
6. [Updating Entities](#updating-entities)
7. [Deleting Entities](#deleting-entities)
8. [Relationships & Links](#relationships--links)
9. [Using Typed Wrappers](#using-typed-wrappers)
10. [Search & Discovery](#search--discovery)
11. [Adding New Entity Types](#adding-new-entity-types)
12. [Migration from Legacy Code](#migration-from-legacy-code)
13. [Common Patterns](#common-patterns)
14. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
15. [Complete System Architecture](#complete-system-architecture)
16. [File Reference](#file-reference)
17. [Migration Status](#migration-status)

---

## Core Concepts

### The Problem We Solved

Previously, CosmoOS had **14 separate tables** with different schemas:
- `ideas`, `tasks`, `projects`, `content`, `research`, `connections`, `journal_entries`, `calendar_events`, `schedule_blocks`, `uncommitted_items`, etc.

This caused:
- Duplicated code across repositories
- Inconsistent field naming
- Complex joins for cross-entity queries
- Difficult schema evolution
- LLM tools needed type-specific logic

### The Solution: Unified Atoms

**Everything is an Atom.**

An Atom is a single, normalized record that can represent ANY entity type. The `type` field discriminates between entity types, while flexible JSON columns (`structured`, `metadata`, `links`) store type-specific data.

### Key Principles

1. **UUID is the only identity** - Never use integer IDs for references
2. **One table, many types** - All entities live in `atoms` table
3. **JSON for flexibility** - Type-specific data in `structured`/`metadata`
4. **Relationships via links** - No foreign keys, use `links` JSON array
5. **Soft deletes only** - Set `is_deleted = 1`, never hard delete

---

## The Atom Model

### Database Schema

```sql
CREATE TABLE atoms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,  -- Temporary, for legacy compat
    uuid TEXT UNIQUE NOT NULL,              -- THE primary identifier
    type TEXT NOT NULL,                     -- Entity type discriminator

    title TEXT,                             -- Primary title/name
    body TEXT,                              -- Main content/description

    structured TEXT,                        -- JSON: type-specific data
    metadata TEXT,                          -- JSON: auxiliary data
    links TEXT,                             -- JSON: relationships

    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    is_deleted INTEGER DEFAULT 0,

    _local_version INTEGER DEFAULT 1,
    _server_version INTEGER DEFAULT 0,
    _sync_version INTEGER DEFAULT 0
);
```

### Swift Model

```swift
struct Atom: Codable, FetchableRecord, PersistableRecord, Syncable, Identifiable {
    var id: Int64?           // Temporary - will be removed
    var uuid: String         // THE primary identifier
    var type: AtomType       // Entity type enum
    var title: String?
    var body: String?
    var structured: String?  // JSON
    var metadata: String?    // JSON
    var links: String?       // JSON array of AtomLink
    var createdAt: String
    var updatedAt: String
    var isDeleted: Bool
    var localVersion: Int64
    var serverVersion: Int64
    var syncVersion: Int64
}
```

### Field Purposes

| Field | Purpose | Example |
|-------|---------|---------|
| `uuid` | Canonical unique identifier | `"550e8400-e29b-41d4-a716-446655440000"` |
| `type` | Entity type discriminator | `"idea"`, `"task"`, `"project"` |
| `title` | Primary display name | `"Marketing Strategy Q1"` |
| `body` | Main content (markdown) | `"## Overview\n\nThis project..."` |
| `structured` | Type-specific structured data | Checklist, mental model, theme |
| `metadata` | Auxiliary key-value data | Tags, priority, status, color |
| `links` | Relationships to other atoms | Project link, parent link |

---

## Entity Types

### AtomType Enum

```swift
enum AtomType: String, Codable, CaseIterable {
    case idea
    case task
    case project
    case content
    case research
    case connection
    case journalEntry = "journal_entry"
    case calendarEvent = "calendar_event"
    case scheduleBlock = "schedule_block"
    case uncommittedItem = "uncommitted_item"
}
```

### Type-Specific Schemas

#### Idea
```swift
// metadata
struct IdeaMetadata: Codable {
    var tags: [String]?
    var priority: String?      // "Low", "Medium", "High"
    var isPinned: Bool?
    var pinnedAt: String?
}

// structured
struct FocusBlocksStructured: Codable {
    var focusBlocks: String?   // JSON for focus mode blocks
}

// links
// - project: Parent project UUID
// - parent_idea: Hierarchical parent UUID
// - connection: Linked mental model UUID
```

#### Task
```swift
// metadata
struct TaskMetadata: Codable {
    var status: String?        // "todo", "in_progress", "completed"
    var priority: String?      // "low", "medium", "high"
    var color: String?         // Hex color
    var dueDate: String?       // ISO8601
    var startTime: String?     // ISO8601
    var endTime: String?       // ISO8601
    var durationMinutes: Int?
    var focusDate: String?
    var isUnscheduled: Bool?
    var isCompleted: Bool?
    var completedAt: String?
}

// structured
struct TaskStructured: Codable {
    var checklist: String?     // JSON array
    var recurrence: String?    // JSON recurrence rule
}

// links
// - project: Parent project UUID
// - origin_idea: Idea this task was created from
```

#### Project
```swift
// metadata
struct ProjectMetadata: Codable {
    var color: String?         // Hex color
    var status: String?        // "active", "archived", "completed"
    var priority: String?      // "Low", "Medium", "High"
    var tags: [String]?
}

// Projects don't have links (they ARE the link targets)
```

#### Content
```swift
// metadata
struct ContentMetadata: Codable {
    var contentType: String?
    var status: String?        // "draft", "published", "archived"
    var scheduledAt: String?
    var lastOpenedAt: String?
    var tags: [String]?
}

// structured
struct ContentStructured: Codable {
    var theme: String?         // JSON theme config
    var focusBlocks: String?
}
```

#### Research
```swift
// metadata
struct ResearchMetadata: Codable {
    var url: String?
    var summary: String?
    var researchType: String?
    var processingStatus: String?  // "new", "processing", "complete"
    var thumbnailUrl: String?
    var query: String?
    var findings: String?
    var tags: [String]?
    var hook: String?              // Swipe file
    var emotionTone: String?
    var structureType: String?
    var isSwipeFile: Bool?
    var contentSource: String?
}

// structured
struct ResearchStructured: Codable {
    var autoMetadata: String?      // Rich content JSON
    var focusBlocks: String?
}
```

#### Connection (Mental Model)
```swift
// structured (THE main content for connections)
struct ConnectionStructured: Codable {
    var idea: String?
    var personalBelief: String?
    var goal: String?
    var problems: String?
    var benefit: String?
    var beliefsObjections: String?
    var example: String?
    var process: String?
    var notes: String?
    var referencesData: String?    // JSON array
    var sourceText: String?        // JSON
    var extractionConfidence: Double?
}
```

#### Schedule Block
```swift
// metadata
struct ScheduleBlockMetadata: Codable {
    var blockType: String?         // "task", "event", "focus"
    var status: String?            // "todo", "completed"
    var isCompleted: Bool?
    var completedAt: String?
    var startTime: String?
    var endTime: String?
    var durationMinutes: Int?
    var isAllDay: Bool?
    var priority: String?
    var color: String?
    var tags: [String]?
    var reminderMinutes: Int?
    var location: String?
    var originType: String?
    var originEntityType: String?
}

// structured
struct ScheduleBlockStructured: Codable {
    var notes: String?
    var checklist: String?
    var recurrence: String?
    var focusSession: String?
    var focusSessionData: String?
    var semanticLinks: String?
}

// links
// - project: Parent project
// - origin_entity: Source entity
// - recurrence_parent: Parent recurring block
```

---

## Creating New Entities

### Using AtomRepository (Recommended)

```swift
// Get the shared repository
let repo = AtomRepository.shared

// Create an idea
let idea = try await repo.create(
    type: .idea,
    title: "My New Idea",
    body: "This is the content of my idea...",
    metadata: encodeJson(IdeaMetadata(
        tags: ["marketing", "q1"],
        priority: "High",
        isPinned: false
    )),
    links: [.project("project-uuid-here")]
)

// Create a task
let task = try await repo.create(
    type: .task,
    title: "Complete proposal",
    body: "Write the Q1 proposal document",
    metadata: encodeJson(TaskMetadata(
        status: "todo",
        priority: "high",
        dueDate: "2025-01-15"
    ))
)

// Create a project
let project = try await repo.createProject(
    title: "Q1 Marketing",
    description: "All Q1 marketing initiatives",
    color: "#8B5CF6"
)
```

### Using Atom.new() Factory

```swift
// Create with factory, then save
var atom = Atom.new(
    type: .idea,
    title: "Quick thought",
    body: "Something I want to remember"
)

// Add a project link
atom = atom.addingLink(.project("project-uuid"))

// Save
let saved = try await AtomRepository.shared.create(atom)
```

### Direct Database Write (Low-Level)

```swift
// Only use when AtomRepository is not available
try await database.asyncWrite { db in
    let atom = Atom.new(type: .task, title: "Direct task")
    try atom.insert(db)
}
```

---

## Querying Entities

### Fetch by Type

```swift
// Get all ideas
let ideas = try await repo.fetchAll(type: .idea)

// Get all tasks
let tasks = try await repo.tasks()

// Get multiple types
let items = try await repo.fetchAll(types: [.idea, .task, .research])
```

### Fetch by UUID

```swift
// Single entity by UUID
let atom = try await repo.fetch(uuid: "550e8400-e29b-41d4-a716-446655440000")
```

### Fetch by Project

```swift
// All entities in a project
let projectItems = try await repo.fetchByProject(projectUuid: "project-uuid")
```

### Search

```swift
// Text search across title and body
let results = try await repo.search(query: "marketing", types: [.idea, .content])
```

### Using AtomQueryBuilder

```swift
let atoms = try await database.asyncRead { db in
    try AtomQueryBuilder()
        .type(.task)
        .where("metadata LIKE ?", "%\"status\":\"todo\"%")
        .orderBy("updated_at", ascending: false)
        .limit(20)
        .execute(in: db)
}
```

---

## Updating Entities

### Using AtomRepository

```swift
// Fetch, modify, save
if var atom = try await repo.fetch(uuid: ideaUuid) {
    atom.title = "Updated Title"
    atom.body = "Updated content..."
    atom = try await repo.update(atom)
}

// Or use the convenience method
let updated = try await repo.update(uuid: ideaUuid) { atom in
    atom.title = "Updated Title"
}
```

### Updating Metadata

```swift
// Update metadata using the typed struct
if var atom = try await repo.fetch(uuid: taskUuid) {
    var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
    meta.status = "completed"
    meta.completedAt = ISO8601DateFormatter().string(from: Date())
    atom = atom.withMetadata(meta)
    try await repo.update(atom)
}
```

### Updating Links

```swift
// Add a link
atom = atom.addingLink(.project("new-project-uuid"))

// Remove links of a type
atom = atom.removingLinks(ofType: "project")

// Replace all links
atom = atom.withLinks([
    .project("project-uuid"),
    .parentIdea("parent-uuid")
])
```

---

## Deleting Entities

### Soft Delete (Standard)

```swift
// By UUID
try await repo.delete(uuid: "atom-uuid")

// By Atom
try await repo.delete(atom)

// Batch delete
try await repo.deleteBatch(uuids: ["uuid1", "uuid2", "uuid3"])
```

### Hard Delete (Use with Caution)

```swift
// Permanently removes from database - rarely needed
try await repo.hardDelete(uuid: "atom-uuid")
```

---

## Relationships & Links

### AtomLink Structure

```swift
struct AtomLink: Codable {
    let type: String       // Relationship type
    let uuid: String       // Target atom UUID
    let entityType: String? // Optional: target's AtomType
}
```

### Standard Link Types

| Link Type | Purpose | Single/Multi |
|-----------|---------|--------------|
| `project` | Parent project | Single |
| `parent_idea` | Hierarchical parent | Single |
| `origin_idea` | Task created from idea | Single |
| `connection` | Mental model link | Single |
| `recurrence_parent` | Recurring event parent | Single |
| `promoted_to` | Uncommitted → Entity | Single |
| `semantic_link` | AI-discovered relation | Multi |

### Creating Links

```swift
// Factory methods
AtomLink.project("uuid")
AtomLink.parentIdea("uuid")
AtomLink.originIdea("uuid")
AtomLink.connection("uuid")
AtomLink.promotedTo("uuid", entityType: "idea")
AtomLink.recurrenceParent("uuid")

// Manual
AtomLink(type: "custom_link", uuid: "target-uuid", entityType: "idea")
```

### Querying by Link

```swift
// Find all atoms linked to a project
let projectAtoms = try await repo.fetchByProject(projectUuid: "project-uuid")

// Custom link query
let linked = try await database.asyncRead { db in
    try Atom
        .filter(sql: "links LIKE ?", arguments: ["%\(targetUuid)%"])
        .fetchAll(db)
}
```

---

## Using Typed Wrappers

For **backward compatibility** with existing UI code, use typed wrappers that provide the familiar interface while backed by Atoms.

### Available Wrappers

- `IdeaWrapper` - Wraps idea atoms
- `TaskWrapper` - Wraps task atoms
- `ProjectWrapper` - Wraps project atoms
- `ContentWrapper` - Wraps content atoms
- `ResearchWrapper` - Wraps research atoms
- `ConnectionWrapper` - Wraps connection atoms

### Using Wrappers

```swift
// Convert Atom to wrapper
let atoms = try await repo.fetchAll(type: .idea)
let ideas: [IdeaWrapper] = atoms.asIdeas()

// Or individually
if let atom = try await repo.fetch(uuid: ideaUuid),
   let idea = atom.asIdea() {
    print(idea.title)
    print(idea.content)
    print(idea.tagsList)
}

// Create via wrapper
var idea = IdeaWrapper.new(title: "New Idea", content: "Content here")
idea.setProject("project-uuid")

// Save the underlying atom
try await repo.create(idea.atom)
```

### Wrapper Properties

Wrappers expose the same properties as legacy models:

```swift
// IdeaWrapper
idea.title          // -> atom.title
idea.content        // -> atom.body
idea.tagsList       // -> parsed from atom.metadata
idea.priority       // -> from atom.metadata
idea.isPinned       // -> from atom.metadata
idea.focusBlocks    // -> from atom.structured
idea.projectUuid    // -> from atom.links
idea.parentUuid     // -> from atom.links
```

---

## Search & Discovery

### Full-Text Search (FTS5)

The `atoms_fts` virtual table provides BM25-ranked keyword search:

```swift
let engine = AtomSearchEngine(database: CosmoDatabase.shared)

let results = try await engine.search(
    query: "marketing strategy",
    options: AtomSearchOptions(
        types: [.idea, .content, .research],
        limit: 20
    )
)

for result in results {
    print("\(result.atom.title) - Score: \(result.score)")
}
```

### Exact Match Search

```swift
let results = try await engine.exactSearch(
    query: "Q1",
    field: .title,
    options: AtomSearchOptions(types: [.project])
)
```

### Semantic Search

Use `semantic_chunks` table for vector similarity search (unchanged from before, but now references `entity_uuid` instead of `entity_id`).

---

## Adding New Entity Types

When you need to add a new entity type:

### 1. Add to AtomType Enum

```swift
// In Atom.swift
enum AtomType: String, Codable, CaseIterable {
    // ... existing types ...
    case newType = "new_type"  // Add here

    var displayName: String {
        switch self {
        // ... existing cases ...
        case .newType: return "New Type"
        }
    }
}
```

### 2. Define Metadata Struct

```swift
// In Atom.swift
struct NewTypeMetadata: Codable, Sendable {
    var customField1: String?
    var customField2: Int?
    var status: String?
}
```

### 3. Define Structured Data Struct (if needed)

```swift
struct NewTypeStructured: Codable, Sendable {
    var complexData: String?  // JSON
    var nestedObject: SomeOtherStruct?
}
```

### 4. Create Wrapper (optional, for backward compat)

```swift
// In AtomWrappers.swift
struct NewTypeWrapper: Identifiable, Equatable, Sendable {
    private(set) var atom: Atom

    var id: Int64? { atom.id }
    var uuid: String { atom.uuid }

    // Add computed properties for your fields
    var customField1: String? {
        get { metadataValue?.customField1 }
        set { /* update logic */ }
    }

    private var metadataValue: NewTypeMetadata? {
        atom.metadataValue(as: NewTypeMetadata.self)
    }

    init(atom: Atom) {
        precondition(atom.type == .newType)
        self.atom = atom
    }

    static func new(customField1: String) -> NewTypeWrapper {
        let metadata = NewTypeMetadata(customField1: customField1)
        let atom = Atom.new(
            type: .newType,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
        return NewTypeWrapper(atom: atom)
    }
}
```

### 5. Add Convenience Methods to AtomRepository

```swift
// In AtomRepository.swift
extension AtomRepository {
    func newTypes() async throws -> [Atom] {
        try await fetchAll(type: .newType)
    }

    @discardableResult
    func createNewType(customField1: String) async throws -> Atom {
        let metadata = NewTypeMetadata(customField1: customField1)
        return try await create(
            type: .newType,
            metadata: try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )
    }
}
```

### 6. Update Schema Documentation

Add to `AtomSchemaDescription.generateSchemaDescription()` and `getTypeSchema()` in `AtomSearchEngine.swift`.

---

## Migration from Legacy Code

### Identifying Legacy Code

Legacy code patterns to migrate:

```swift
// OLD - Direct table access
let ideas = try Idea.fetchAll(db)

// NEW - Use AtomRepository
let ideas = try await AtomRepository.shared.ideas()
```

```swift
// OLD - Direct table query
try Idea.filter(Idea.CodingKeys.projectId == projectId).fetchAll(db)

// NEW - Query by project UUID
try await repo.fetchByProject(projectUuid: projectUuid)
```

```swift
// OLD - Foreign key reference
idea.projectId = project.id

// NEW - UUID link
atom = atom.addingLink(.project(project.uuid))
```

### Migration Checklist

For each file using legacy models:

- [ ] Replace `Idea` with `Atom` or `IdeaWrapper`
- [ ] Replace `CosmoTask` with `Atom` or `TaskWrapper`
- [ ] Replace `Project` with `Atom` or `ProjectWrapper`
- [ ] Replace integer ID references with UUID
- [ ] Replace direct table queries with AtomRepository methods
- [ ] Update any `projectId` to `projectUuid` via links

---

## Common Patterns

### Pattern: Create with Project Link

```swift
let projectUuid = "existing-project-uuid"

let idea = try await repo.create(
    type: .idea,
    title: "New Idea",
    body: "Content",
    links: [.project(projectUuid)]
)
```

### Pattern: Update Status

```swift
try await repo.update(uuid: taskUuid) { atom in
    var meta = atom.metadataValue(as: TaskMetadata.self) ?? TaskMetadata()
    meta.status = "completed"
    meta.completedAt = ISO8601DateFormatter().string(from: Date())
    atom = atom.withMetadata(meta)
}
```

### Pattern: Move to Different Project

```swift
try await repo.update(uuid: ideaUuid) { atom in
    atom = atom.removingLinks(ofType: "project")
    atom = atom.addingLink(.project(newProjectUuid))
}
```

### Pattern: Create Task from Idea

```swift
let idea = try await repo.fetch(uuid: ideaUuid)!

let task = try await repo.create(
    type: .task,
    title: idea.title ?? "Task from idea",
    body: idea.body,
    links: [
        .originIdea(ideaUuid),
        idea.link(ofType: "project").map { .project($0.uuid) }
    ].compactMap { $0 }
)
```

### Pattern: Batch Operations

```swift
// Create multiple atoms
let atoms = [
    Atom.new(type: .idea, title: "Idea 1"),
    Atom.new(type: .idea, title: "Idea 2"),
    Atom.new(type: .idea, title: "Idea 3")
]
let created = try await repo.createBatch(atoms)

// Delete multiple
try await repo.deleteBatch(uuids: ["uuid1", "uuid2"])
```

---

## Anti-Patterns to Avoid

### DON'T: Use Integer IDs for References

```swift
// BAD
atom.links = "[{\"type\":\"project\",\"id\":42}]"

// GOOD
atom = atom.addingLink(.project("project-uuid-string"))
```

### DON'T: Query Legacy Tables Directly

```swift
// BAD
let ideas = try Idea.fetchAll(db)

// GOOD
let ideas = try await AtomRepository.shared.ideas()
```

### DON'T: Create New Table-Specific Repositories

```swift
// BAD - Don't create this
class NewEntityRepository {
    func fetchAll() -> [NewEntity] { ... }
}

// GOOD - Use AtomRepository
let items = try await AtomRepository.shared.fetchAll(type: .newEntity)
```

### DON'T: Hard-Code Entity Type Strings

```swift
// BAD
atom.type = "idea"

// GOOD
atom.type = .idea  // Use AtomType enum
```

### DON'T: Mutate Atoms Without Updating Timestamps

```swift
// BAD
atom.title = "New Title"
try atom.update(db)

// GOOD - AtomRepository handles this automatically
try await repo.update(atom)  // Updates updatedAt and localVersion
```

### DON'T: Use Foreign Key Joins

```swift
// BAD - Legacy pattern
SELECT * FROM ideas WHERE project_id = ?

// GOOD - Use links JSON
SELECT * FROM atoms WHERE links LIKE '%"uuid":"project-uuid"%'
```

---

## Complete System Architecture

### Birds-Eye View

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CosmoOS Unified Architecture                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                           USER INTERFACE LAYER                           │    │
│  ├──────────────────┬──────────────────┬─────────────────┬─────────────────┤    │
│  │   Canvas Views   │   Focus Mode     │   Navigation    │   Voice UI      │    │
│  │  CanvasView.swift│ FocusCanvasView  │ InboxViewsMode  │ VoicePillWindow │    │
│  │  DocumentBlocks  │ IdeaEditorView   │ ProjectCreation │ FloatingCards   │    │
│  │  SpatialEngine   │ ContentEditor    │ CommandHub      │ GhostCardView   │    │
│  └──────────────────┴──────────────────┴─────────────────┴─────────────────┘    │
│                                     │                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                           SERVICES LAYER                                 │    │
│  ├─────────────────────────────┬───────────────────────────────────────────┤    │
│  │    UncommittedItemsService  │          ContextDetectionEngine           │    │
│  │    - capture()              │          - detectContext()                 │    │
│  │    - promote()              │          - fuzzy project matching          │    │
│  │    - dismiss()              │          - language cue detection          │    │
│  └─────────────────────────────┴───────────────────────────────────────────┘    │
│                                     │                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        VOICE/LLM PIPELINE (3-Tier)                       │    │
│  ├──────────────────┬──────────────────┬──────────────────┬────────────────┤    │
│  │   Tier 0: Regex  │  Tier 1: 0.5B    │  Tier 2: 1.5B    │  Tier 3: API   │    │
│  │  PatternMatcher  │ FineTunedQwen05B │   Hermes15B      │   GeminiAPI    │    │
│  │    <50ms         │    <300ms        │    <2000ms       │   Generative   │    │
│  │   ~60% handled   │  Project routing │  Brain dumps     │   Synthesis    │    │
│  └──────────────────┴──────────────────┴──────────────────┴────────────────┘    │
│                          VoiceCommandPipeline orchestrates                       │
│                                     │                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        VOICE INPUT MODELS                                │    │
│  ├─────────────────────────────────┬───────────────────────────────────────┤    │
│  │           VoiceAtom             │            ParsedAction               │    │
│  │    - transcript                 │    - action (create/update/delete)    │    │
│  │    - context.section            │    - atomType                         │    │
│  │    - context.currentProjectUuid │    - title, metadata                  │    │
│  │    - confidence                 │    - links (project routing)          │    │
│  └─────────────────────────────────┴───────────────────────────────────────┘    │
│                                     │                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                         DATA LAYER (Unified Atoms)                       │    │
│  ├─────────────────────────────────┬───────────────────────────────────────┤    │
│  │                                 │                                        │    │
│  │  ┌───────────────────────────┐  │  ┌─────────────────────────────────┐  │    │
│  │  │     AtomRepository        │  │  │        AtomSearchEngine         │  │    │
│  │  │  - create/update/delete   │  │  │  - FTS5 search                  │  │    │
│  │  │  - fetchByType            │  │  │  - Semantic search              │  │    │
│  │  │  - fetchByProject         │  │  │  - Query builder                │  │    │
│  │  │  - uncommitted workflow   │  │  │                                 │  │    │
│  │  │  - sync tracking          │  │  │                                 │  │    │
│  │  └───────────────────────────┘  │  └─────────────────────────────────┘  │    │
│  │                                 │                                        │    │
│  │  ┌───────────────────────────┐  │  ┌─────────────────────────────────┐  │    │
│  │  │         Atom.swift        │  │  │       AtomWrappers.swift        │  │    │
│  │  │  - Unified data model     │  │  │  - IdeaAtom, TaskAtom           │  │    │
│  │  │  - 10 AtomTypes           │  │  │  - ProjectAtom, ContentAtom     │  │    │
│  │  │  - JSON metadata/links    │  │  │  - Legacy API compatibility     │  │    │
│  │  └───────────────────────────┘  │  └─────────────────────────────────┘  │    │
│  │                                 │                                        │    │
│  └─────────────────────────────────┴───────────────────────────────────────┘    │
│                                     │                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                           DATABASE LAYER                                 │    │
│  ├─────────────────────────────────┬───────────────────────────────────────┤    │
│  │        CosmoDatabase            │          AtomMigration                │    │
│  │   - GRDB async operations       │   - Legacy table converters          │    │
│  │   - Combine observation         │   - Schema migrations                │    │
│  │   - Change tracking             │                                       │    │
│  └─────────────────────────────────┴───────────────────────────────────────┘    │
│                                     │                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                              SYNC LAYER                                  │    │
│  ├─────────────────────────────────┬───────────────────────────────────────┤    │
│  │         ChangeTracker           │          SyncIntegration              │    │
│  │   - trackInsert/Update/Delete   │   - Automatic sync via AtomRepo       │    │
│  │   - Conflict resolution         │   - Entity-agnostic sync              │    │
│  └─────────────────────────────────┴───────────────────────────────────────┘    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Voice Pipeline Flow

```
Voice Input → VoiceEngine → VoiceAtom
                               │
                    ┌──────────┴──────────┐
                    │  VoiceCommandPipeline │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
     ┌────┴────┐         ┌────┴────┐         ┌────┴────┐
     │ Tier 0  │         │ Tier 1  │         │ Tier 2  │
     │ Pattern │──fail──→│  0.5B   │──fail──→│  1.5B   │
     │ Matcher │         │  Model  │         │  Model  │
     └────┬────┘         └────┬────┘         └────┬────┘
          │                    │                    │
          └────────────────────┼────────────────────┘
                               │
                        ParsedAction
                               │
                    ┌──────────┴──────────┐
                    │    AtomRepository    │
                    │  create/update/delete│
                    └──────────┬──────────┘
                               │
                            Atom
```

---

## File Reference

### Data Layer

| File | Purpose |
|------|---------|
| `Data/Models/Atom.swift` | Core Atom model, AtomType enum, AtomLink, typed metadata structs |
| `Data/Models/AtomWrappers.swift` | IdeaAtom, TaskAtom, ProjectAtom - backward-compatible wrappers |
| `Data/Models/CanvasBlockRecord.swift` | Canvas block persistence model |
| `Data/Models/InboxViewBlock.swift` | Inbox view block model |
| `Data/Repositories/AtomRepository.swift` | **THE** unified repository - all CRUD operations |
| `Data/Search/AtomSearchEngine.swift` | FTS5 search, semantic search, query builder |
| `Data/Database/CosmoDatabase.swift` | GRDB database setup, async operations, Combine observation |
| `Data/Database/AtomMigration.swift` | Legacy table → Atom converters |
| `Data/Database/DatabaseActorCore.swift` | Actor-isolated database operations |
| `Data/ConnectionStore.swift` | Mental model connection storage |

### Voice Layer

| File | Purpose |
|------|---------|
| `Voice/Models/VoiceAtom.swift` | Voice input intermediate model |
| `Voice/Models/ParsedAction.swift` | LLM output model → AtomRepository operations |
| `Voice/Pipeline/PatternMatcher.swift` | Tier 0: Fast regex matching (<50ms) |
| `Voice/Pipeline/VoiceCommandPipeline.swift` | 3-tier orchestrator |
| `Voice/VoiceEngine.swift` | Voice input handling |
| `Voice/AudioCapture.swift` | Audio stream capture |
| `Voice/WhisperEngine.swift` | Whisper transcription |
| `Voice/TieredASR/ASRCoordinator.swift` | ASR coordination |
| `Voice/TieredASR/L1StreamingASR.swift` | Level 1 streaming ASR |
| `Voice/TieredASR/L2WhisperASR.swift` | Level 2 Whisper ASR |
| `Voice/EditingContextTracker.swift` | Track what entity is being edited |
| `Voice/VoiceContextStore.swift` | Voice context persistence |
| `Voice/HotkeyManager.swift` | Keyboard hotkey handling |
| `Voice/VoiceUI/VoicePillWindow.swift` | Voice activation pill UI |
| `Voice/VoiceUI/FloatingCardsController.swift` | Floating card management |
| `Voice/VoiceUI/GhostCardView.swift` | Ghost preview cards |
| `Voice/VoiceUI/MetalWaveformView.swift` | Audio waveform visualization |

### AI Layer

| File | Purpose |
|------|---------|
| `AI/Models/FineTunedQwen05B.swift` | Tier 1: 0.5B fine-tuned model (<300ms) |
| `AI/Models/Hermes15B.swift` | Tier 2: 1.5B model (<2s) for complex commands |
| `AI/Models/GeminiAPI.swift` | Tier 3: Generative synthesis via OpenRouter |
| `AI/IntentClassifier.swift` | Intent classification for voice commands |
| `AI/ContextAssembler.swift` | Context assembly for LLM prompts |
| `AI/TelepathyEngine.swift` | AI telepathy/prediction engine |
| `AI/GeminiSynthesisEngine.swift` | Gemini-based synthesis |
| `AI/VectorDatabase.swift` | Vector storage for semantic search |

### Services Layer

| File | Purpose |
|------|---------|
| `Services/UncommittedItemsService.swift` | Uncommitted items workflow (capture → promote) |
| `Services/ContextDetectionEngine.swift` | Smart project inference from context |

### Sync Layer

| File | Purpose |
|------|---------|
| `Sync/SyncIntegration.swift` | Sync extensions for AtomRepository |
| `Sync/ChangeTracker.swift` | Track local changes for sync |

### Documentation

| File | Purpose |
|------|---------|
| `Documentation/AtomArchitecture.md` | This file - complete architecture guide |
| `Documentation/AtomMigrationPlan.md` | Migration tracking and patterns |
| `Documentation/VoiceLLMUnifiedArchitecture.md` | Voice/LLM pipeline documentation |

---

## Migration Status

### Completed (as of 2025-12-20)

**Legacy files deleted:**
- ✅ `Data/Repositories/IdeasRepository.swift`
- ✅ `Data/Repositories/TasksRepository.swift`
- ✅ `Data/Repositories/ProjectsRepository.swift`
- ✅ `Data/Repositories/ContentRepository.swift`
- ✅ `Data/Repositories/UncommittedItemsRepository.swift`
- ✅ `Data/Models/Idea.swift`
- ✅ `Data/Models/Task.swift`
- ✅ `Data/Models/Project.swift`
- ✅ `Data/Models/Content.swift`
- ✅ `Data/Models/Research.swift`
- ✅ `Data/Models/Connection.swift`
- ✅ `Data/Models/UncommittedItem.swift`
- ✅ 21 legacy AI files
- ✅ 13 legacy Voice files

**Files migrated to AtomRepository:**
- ✅ `Canvas/DocumentBlocksLayer.swift`
- ✅ `Focus/FocusCanvasView.swift`
- ✅ `Services/UncommittedItemsService.swift`
- ✅ `Services/ContextDetectionEngine.swift`
- ✅ `Navigation/InboxViewsMode.swift`
- ✅ `Navigation/ProjectCreationModal.swift`
- ✅ `Sync/SyncIntegration.swift`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-20 | Initial Atom architecture implementation |
| 2.0 | 2025-12-20 | Complete migration - deleted all legacy repos/models, unified Voice/LLM pipeline |

---

## Level System Architecture

The Level System is a comprehensive gamification layer that transforms CosmoOS into a cognitive fitness tracker. It follows the same Atom-first principles—all XP events, badges, streaks, and health measurements are Atoms.

### Two-Tier Leveling

| Tier | Name | Behavior | Purpose |
|------|------|----------|---------|
| **Tier 1** | Cosmo Index (CI) | Never decreases | Permanent identity progression (1-100+) |
| **Tier 2** | Neuro-ELO (NELO) | Can rise and fall | Dynamic performance metric (~800-2400) |

### Six Dimensions

Each dimension tracks a different aspect of cognitive performance:

| Dimension | Measures | Key Atoms |
|-----------|----------|-----------|
| **Cognitive** | Writing, deep work, task completion | `writingSession`, `deepWorkBlock` |
| **Creative** | Content performance, virality, reach | `contentPerformance`, `contentPublish` |
| **Physiological** | HRV, sleep, recovery, readiness | `hrvReading`, `sleepRecord`, `readinessScore` |
| **Behavioral** | Consistency, routine adherence | `streakEvent`, `routineBlock` |
| **Knowledge** | Research, connections, semantic density | `semanticCluster`, `connectionLink` |
| **Reflection** | Journaling, insights, self-awareness | `journalInsight`, `emotionalState` |

### Extended AtomTypes for Level System

```swift
enum AtomType: String, Codable, CaseIterable {
    // ... existing types ...

    // Leveling & Gamification
    case xpEvent              // Every XP gain
    case levelUpdate          // CI or NELO changes
    case streakEvent          // Streak milestones
    case badgeUnlocked        // Achievement unlocks
    case dimensionSnapshot    // Daily dimension scores
    case dailyQuest           // Generated quests

    // Physiology (Apple Watch Ultra 3)
    case hrvReading           // Heart Rate Variability
    case sleepRecord          // Sleep analysis
    case readinessScore       // Daily readiness composite
    case workout              // Exercise sessions
    case restingHR            // Resting heart rate
    case activityRing         // Move/Exercise/Stand

    // Cognitive Output
    case deepWorkBlock        // Focused work sessions
    case writingSession       // Words written tracking
}
```

### Level System Components

#### Core Engine Files

| File | Purpose |
|------|---------|
| `Data/Models/LevelSystem/CosmoLevelSystem.swift` | Core level data model |
| `Data/Models/LevelSystem/XPCalculationEngine.swift` | XP calculation with multipliers |
| `Data/Models/LevelSystem/NELORegressionEngine.swift` | NELO rise/fall mechanics |
| `Data/Models/LevelSystem/DimensionConfigs.swift` | Scientific thresholds per dimension |
| `Data/Models/LevelSystem/DimensionMetricsCalculator.swift` | Daily metrics aggregation |
| `Data/Models/LevelSystem/BadgeDefinitionSystem.swift` | Badge catalog and requirements |
| `Data/Models/LevelSystem/BadgeProgressTracker.swift` | Badge unlock tracking |
| `Data/Models/LevelSystem/StreakTrackingEngine.swift` | Streak mechanics and multipliers |
| `Data/Models/LevelSystem/DailyCronEngine.swift` | Midnight processing pipeline |
| `Data/Models/LevelSystem/LevelSystemService.swift` | Main service facade |
| `Data/Models/LevelSystem/DailyQuestEngine.swift` | Quest generation and tracking |
| `Data/Models/LevelSystem/CelebrationEngine.swift` | Achievement celebrations |

#### HealthKit Integration Files

| File | Purpose |
|------|---------|
| `Data/HealthKit/HealthKitConfiguration.swift` | Permission requests, data types |
| `Data/HealthKit/HealthKitAtomFactory.swift` | Converts HKSamples → Atoms |
| `Data/HealthKit/ReadinessCalculator.swift` | WHOOP-style readiness scoring |
| `Data/HealthKit/HealthKitLevelIntegration.swift` | Bridges health → Physiological dimension |

#### UI Dashboard Files

| File | Purpose |
|------|---------|
| `UI/LevelSystem/LevelDashboardView.swift` | Main dashboard with CI, NELO, dimensions |
| `UI/LevelSystem/WritingStatsView.swift` | Writing performance detail view |
| `UI/LevelSystem/ContentPerformanceView.swift` | Content/virality metrics view |
| `UI/LevelSystem/StreakDetailsView.swift` | Streak tracking and history |
| `UI/LevelSystem/XPSummaryOverlay.swift` | First-boot daily summary |
| `UI/LevelSystem/LevelUpCelebrationView.swift` | Level-up celebration overlay |

### Level System Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        LEVEL SYSTEM ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                        DATA SOURCES                               │   │
│  ├──────────────┬──────────────┬──────────────┬──────────────────────┤   │
│  │ Apple Watch  │  User Input  │  AI Analysis │  External APIs       │   │
│  │ HealthKit    │  Writing     │  Embeddings  │  Social Metrics      │   │
│  │ - HRV        │  - Words     │  - Insights  │  - Reach             │   │
│  │ - Sleep      │  - Tasks     │  - Clusters  │  - Engagement        │   │
│  │ - Workouts   │  - Journal   │  - Clarity   │  - Virality          │   │
│  └──────┬───────┴──────┬───────┴──────┬───────┴──────────┬───────────┘   │
│         │              │              │                   │              │
│         └──────────────┴──────────────┴───────────────────┘              │
│                                 │                                        │
│  ┌──────────────────────────────┴───────────────────────────────────┐   │
│  │                    ATOM FACTORY LAYER                             │   │
│  │  HealthKitAtomFactory → Atoms (.hrvReading, .sleepRecord, etc.)  │   │
│  │  All data normalized to unified Atom model with typed metadata   │   │
│  └──────────────────────────────┬───────────────────────────────────┘   │
│                                 │                                        │
│  ┌──────────────────────────────┴───────────────────────────────────┐   │
│  │                    CALCULATION ENGINES                            │   │
│  ├─────────────────────┬────────────────────────────────────────────┤   │
│  │  DimensionMetrics   │  XPCalculation    │  NELORegression        │   │
│  │  Calculator         │  Engine           │  Engine                │   │
│  │  - Aggregate daily  │  - Base XP        │  - K-factor            │   │
│  │  - Apply thresholds │  - Streak mult.   │  - Regression rules    │   │
│  │  - Level mapping    │  - Variable ratio │  - Trend detection     │   │
│  └─────────────────────┴────────────────────┴────────────────────────┘   │
│                                 │                                        │
│  ┌──────────────────────────────┴───────────────────────────────────┐   │
│  │                    LEVEL SYSTEM SERVICE                           │   │
│  │  - processDailyUpdate()                                          │   │
│  │  - calculateCurrentSnapshot()                                     │   │
│  │  - checkBadgeUnlocks()                                           │   │
│  │  - updateStreaks()                                                │   │
│  │  - generateDailyQuests()                                          │   │
│  └──────────────────────────────┬───────────────────────────────────┘   │
│                                 │                                        │
│  ┌──────────────────────────────┴───────────────────────────────────┐   │
│  │                    OUTPUT: ATOM REPOSITORY                        │   │
│  │  Creates atoms: .xpEvent, .levelUpdate, .streakEvent,            │   │
│  │                 .badgeUnlocked, .dimensionSnapshot, .dailyQuest  │   │
│  └──────────────────────────────┬───────────────────────────────────┘   │
│                                 │                                        │
│  ┌──────────────────────────────┴───────────────────────────────────┐   │
│  │                    PRESENTATION LAYER                             │   │
│  ├────────────────┬─────────────────┬───────────────────────────────┤   │
│  │ Dashboard View │ Detail Views    │ Celebration Views             │   │
│  │ - Hero stats   │ - Writing       │ - XP Summary Overlay          │   │
│  │ - Dimensions   │ - Content       │ - Level Up Celebration        │   │
│  │ - Streaks      │ - Streaks       │ - Badge Unlock                │   │
│  │ - Quests       │ - Badges        │ - Confetti/Haptics            │   │
│  └────────────────┴─────────────────┴───────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### HealthKit to Atom Conversion

```swift
// Example: HRV Sample → Atom
actor HealthKitAtomFactory {
    func convertHRVSample(_ sample: HKQuantitySample) -> Atom {
        let metadata = HRVMeasurementMetadata(
            hrvMs: sample.quantity.doubleValue(for: .init(from: "ms")),
            measurementType: .nighttime,
            confidence: calculateConfidence(sample),
            percentileRank: calculatePercentile(hrvMs)
        )

        return Atom.new(
            type: .hrvReading,
            title: "HRV: \(Int(hrvMs))ms",
            metadata: try? JSONEncoder().encode(metadata)
        )
    }
}
```

### Daily Cron Pipeline

The `DailyCronEngine` runs at midnight and:

1. Fetches all atoms from the past 24 hours
2. Pulls health data from HealthKit → creates Atoms
3. Calculates metrics per dimension
4. Generates XP events (`.xpEvent` Atoms)
5. Updates Cosmo Index and NELO
6. Checks for regressions and triggers warnings
7. Creates dimension snapshot (`.dimensionSnapshot` Atom)
8. Updates streaks (`.streakEvent` Atoms)
9. Checks badge unlocks (`.badgeUnlocked` Atoms)
10. Creates daily summary (`.dailySummary` Atom)
11. Generates quests for the new day (`.dailyQuest` Atoms)

### Gamification Psychology

The Level System implements research-backed engagement mechanics:

| Mechanic | Implementation | Psychology |
|----------|----------------|------------|
| Variable Ratio | Random XP bonuses (1-15% chance) | Slot machine dopamine |
| Loss Aversion | NELO can regress | Kahneman's Prospect Theory |
| Streak Multipliers | 1.0x → 3.0x based on days | Consistency rewards |
| Flow Preservation | Delayed notifications during deep work | Csikszentmihalyi |
| Milestone Celebrations | Level-up animations, haptics | Peak-end rule |

### Quest System

```swift
struct Quest: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let dimension: LevelDimension
    let requirement: QuestRequirement
    let xpReward: Int
    let bonusXP: Int?
    var progress: Double  // 0-1
    var isComplete: Bool
}

enum QuestRequirement: Codable {
    case deepWorkMinutes(target: Int)
    case wordsWritten(target: Int)
    case tasksCompleted(target: Int)
    case journalEntry
    case hrvMeasurement
    case workoutCompleted(minutes: Int)
}
```

---

## Voice Integration for Level System

Phase 5 extends the voice pipeline with Level System queries, deep work controls, and journal routing.

### Voice Query Commands

The PatternMatcher now handles Level System queries in Tier 0 (<50ms):

| Query Type | Example Commands | QueryType Enum |
|------------|------------------|----------------|
| Level Status | "What's my level?", "What's my Cosmo Index?" | `.levelStatus` |
| XP Today | "How much XP today?", "Show XP breakdown" | `.xpToday`, `.xpBreakdown` |
| Streaks | "What's my streak?", "Show all streaks" | `.streakStatus`, `.allStreaks` |
| Badges | "What badges do I have?", "What badge am I close to?" | `.badgesEarned`, `.badgeProgress` |
| Health | "What's my readiness?", "How's my HRV?" | `.readinessScore`, `.hrvStatus` |
| Quests | "What quests are active?", "Quest progress" | `.activeQuests`, `.questProgress` |
| Summary | "Daily summary", "Weekly summary" | `.dailySummary`, `.weeklySummary` |

### Voice Action Flow

```
Voice: "What's my level?"
         │
    ┌────┴────┐
    │ Tier 0  │
    │ Pattern │───match───→ ParsedAction {
    │ Matcher │                action: .query,
    └─────────┘                queryType: .levelStatus
                             }
                                    │
                    ┌───────────────┴───────────────┐
                    │   LevelSystemQueryHandler     │
                    │   - Fetches CosmoLevelState   │
                    │   - Formats response          │
                    └───────────────┬───────────────┘
                                    │
                             QueryResponse {
                               spokenText: "You're at CI level 12...",
                               displayTitle: "Level 12",
                               metrics: [...]
                             }
                                    │
                    ┌───────────────┴───────────────┐
                    │         Voice Output          │
                    │   - TTS speaks response       │
                    │   - UI shows metrics card     │
                    └───────────────────────────────┘
```

### Deep Work Voice Commands

| Command | Action | Metadata |
|---------|--------|----------|
| "Start deep work for 2 hours" | Creates `.scheduleBlock` | `blockType: "focus", durationMinutes: 120` |
| "Stop focus mode" | Updates context block | `status: "completed", endNow: true` |
| "Extend deep work 30 minutes" | Updates current session | `extendMinutes: 30` |
| "Take a break for 15 minutes" | Creates `.scheduleBlock` | `blockType: "break", durationMinutes: 15` |
| "Start pomodoro" | Creates focus block | `pomodoroMode: true, durationMinutes: 25` |

### Workout Logging Commands

| Command | Action | Metadata |
|---------|--------|----------|
| "Log workout" | Creates `.workout` Atom | `source: "voice"` |
| "I just did a 30 minute run" | Creates `.workout` | `workoutType: "run", durationMinutes: 30` |
| "Log 3 sets of squats" | Creates `.workout` | `sets: 3, exercise: "squats"` |

### Journal Routing

The `JournalRouter` classifies freeform voice input into journal categories:

| Entry Type | Example Input | Dimension | XP |
|------------|---------------|-----------|-----|
| Gratitude | "I'm grateful for my team" | behavioral | 20 |
| Mood | "I'm feeling energized today" | reflection | 10 |
| Reflection | "I've been thinking about my goals" | reflection | 25 |
| Learning | "I learned that consistency beats intensity" | knowledge | 35 |
| Goal | "I want to publish my book this year" | cognitive | 30 |
| Challenge | "I'm struggling with focus" | reflection | 25 |

### Insight Extraction

The `InsightExtractor` analyzes journal entries for patterns:

| Insight Type | Example | Trigger |
|--------------|---------|---------|
| Mood Pattern | "You've been positive 70% of entries" | 3+ mood entries in same category |
| Topic Frequency | "You mention 'productivity' often" | Topic appears 3+ times |
| Time Pattern | "You journal most in the evening" | 50%+ entries in same time slot |
| Consistency | "5/7 days journaled this week" | Streak tracking |

### Voice Integration Files

| File | Purpose |
|------|---------|
| `Voice/Pipeline/LevelSystemVoicePatterns.swift` | Tier 0 patterns for level queries |
| `Voice/Pipeline/LevelSystemQueryHandler.swift` | Query execution and response formatting |
| `Voice/Pipeline/DeepWorkVoiceCommands.swift` | Deep work and workout patterns + session handler |
| `Voice/Pipeline/JournalRouter.swift` | Journal classification and entry processing |
| `Voice/Pipeline/InsightExtractor.swift` | Pattern recognition from journal entries |

### Extended ParsedAction

```swift
extension ParsedAction {
    enum ActionType: String, Codable, Sendable {
        case create, update, delete, search, batch, navigate
        case query  // NEW: Level system queries
    }

    enum QueryType: String, Codable, Sendable {
        // Level Queries
        case levelStatus, xpToday, xpBreakdown, dimensionStatus

        // Streak Queries
        case streakStatus, allStreaks, streakHistory

        // Badge Queries
        case badgesEarned, badgeProgress, badgeDetails

        // Quest Queries
        case activeQuests, questProgress

        // Health Queries
        case readinessScore, hrvStatus, sleepScore, todayHealth

        // Summary Queries
        case dailySummary, weeklySummary, monthProgress
    }
}
```

### QueryResponse Model

```swift
struct QueryResponse: Sendable {
    let queryType: ParsedAction.QueryType
    let spokenText: String           // For TTS
    let displayTitle: String         // UI card title
    let displaySubtitle: String?     // Optional context
    let metrics: [QueryMetric]       // Key-value pairs
    let action: QueryAction?         // Optional navigation
}

struct QueryMetric: Sendable {
    let label: String
    let value: String
    let icon: String?                // SF Symbol
    let color: String?               // Theme color
    let trend: MetricTrend?          // up/down/stable
}
```

---

## Content Pipeline (Phase 6)

Phase 6 implements the Content Pipeline with **Performance Matching** - tracking content through creation phases, measuring performance across social platforms, and predicting/comparing content success.

### Core Atom Types

| Atom Type | Purpose | Metadata |
|-----------|---------|----------|
| `.content` | Content pieces in pipeline | phase, platform, wordCount, predictions |
| `.contentDraft` | Draft versions | version, wordCount, diffSummary |
| `.contentPhase` | Phase transitions | fromPhase, toPhase, timeSpent, xpEarned |
| `.contentPublish` | Publish events | platform, postId, postUrl, mediaType |
| `.contentPerformance` | Performance data | impressions, engagement, viralityScore |
| `.clientProfile` | Ghostwriting clients | clientName, platforms, avgEngagementRate |

### Content Pipeline Service

The main orchestration service for content lifecycle management:

```swift
@MainActor
public final class ContentPipelineService: ObservableObject {

    // Create new content
    func createContent(title: String, platform: SocialPlatform?, clientUUID: String?) async throws -> Atom

    // Advance through phases (Ideation → Outline → Draft → Polish → Scheduled → Published)
    func advancePhase(contentUUID: String, notes: String?) async throws -> Atom

    // Record publishing event
    func recordPublish(contentUUID: String, platform: SocialPlatform, postId: String) async throws -> Atom

    // Record performance metrics
    func recordPerformance(
        contentUUID: String,
        platform: SocialPlatform,
        impressions: Int,
        likes: Int,
        comments: Int,
        shares: Int,
        saves: Int
    ) async throws -> Atom
}
```

### Content Analytics Engine

Calculates metrics from performance Atoms:

```swift
actor ContentAnalyticsEngine {
    // Aggregate metrics
    func calculateWeeklyReach() async throws -> Int
    func calculateMonthlyViralCount() async throws -> Int
    func calculateAverageEngagementRate() async throws -> Double

    // Virality calculation
    func calculateViralityScore(impressions: Int, engagementRate: Double, platform: SocialPlatform) -> Double

    // Platform breakdown
    func getPerformanceByPlatform() async throws -> [PlatformPerformance]

    // Creative dimension metrics for Level System
    func calculateCreativeDimensionMetrics() async throws -> CreativeDimensionData
}
```

### Performance Prediction Engine (Performance Matching)

Predicts content performance and tracks prediction accuracy:

```swift
actor PerformancePredictionEngine {
    // Generate predictions
    func predictPerformance(
        platform: SocialPlatform,
        wordCount: Int,
        clientUUID: String?
    ) async -> PerformancePrediction

    // Record results for accuracy tracking
    func recordPredictionResult(contentUUID: String, predicted: Int, actual: Int) async

    // Get overall accuracy
    func getOverallAccuracy() async throws -> PredictionAccuracyReport
}

struct PerformancePrediction: Sendable {
    let reach: Int
    let engagementRate: Double
    let viralProbability: Double
    let confidence: Double
    let factors: PredictionFactors
}
```

### Performance Matching XP Awards

| Condition | XP Award |
|-----------|----------|
| Exceeded prediction by 2x+ | +100 XP |
| Exceeded prediction by 50% | +50 XP |
| Met prediction | +25 XP |
| Viral content | +500 XP |
| Phase completion (varies) | +5 to +25 XP |
| Publishing | +20 XP |

### Content Voice Commands

```swift
// Performance queries
"What's my content performance?" → ContentPerformance query
"How much reach this week?" → TotalReach query
"How many viral posts this month?" → ViralCount query
"What was my best content?" → TopContent query

// Creation commands
"Create a new post for Twitter" → Creates .content Atom
"I just published a thread on Twitter" → Records .contentPublish Atom
"My last post got 50K impressions" → Records .contentPerformance Atom

// Pipeline status
"What's in my content pipeline?" → PipelineStatus query
"How's my creative dimension?" → CreativeDimension query
```

### Creative Dimension Integration

The Content Pipeline feeds the Creative dimension of the Level System:

| Metric | Thresholds (Level 1 → 100) |
|--------|---------------------------|
| Weekly Reach | 1K → 100M |
| Viral Posts/Month | 0 → 20 |
| Engagement Rate | 0.5% → 10% |
| Published/Month | 1 → 100 |

### Content Pipeline Files

| File | Purpose |
|------|---------|
| `ContentPipelineService.swift` | Main orchestration, phase management |
| `ContentAnalyticsEngine.swift` | Metrics calculation from Atoms |
| `PerformancePredictionEngine.swift` | ML-style predictions, accuracy tracking |
| `ContentVoiceCommands.swift` | Voice patterns and query handler |
| `ContentPipelineMetadata.swift` | Metadata structures (existing) |
| `ContentPerformanceView.swift` | UI with live Atom data |

---

## Implementation Phases Status

### Completed Phases

| Phase | Name | Status | Components |
|-------|------|--------|------------|
| 1 | Foundation | ✅ Complete | AtomType extensions, metadata structs, migrations |
| 2 | HealthKit | ✅ Complete | Configuration, AtomFactory, Readiness, Integration |
| 3 | Gamification | ✅ Complete | Badges, Quests, Celebrations |
| 7 | Dashboard | ✅ Complete | All UI views (6 files) |

### Completed Phases (Continued)

| Phase | Name | Status | Components |
|-------|------|--------|------------|
| 4 | Daily Cron & Summaries | ✅ Complete | DailySummaryGenerator, ProactiveNotificationService, MidnightCronScheduler, WeeklySummaryGenerator |
| 5 | Voice Integration | ✅ Complete | Level queries, streaks, badges, XP, health, deep work, journal routing |
| 6 | Content Pipeline | ✅ Complete | ContentPipelineService, ContentAnalyticsEngine, PerformancePredictionEngine, ContentVoiceCommands |
| 7 | The Sanctuary | ✅ Complete | CausalityEngine, SemanticAnalysisEngine, CloudCorrelationAnalyzer, SanctuaryDataProvider, SanctuaryView, HeroOrbView, DimensionOrbView, DimensionDetailView |

### Pending Phases

| Phase | Name | Status | Next Steps |
|-------|------|--------|------------|
| 8 | iOS Sync | ⏳ Pending | CloudKit, companion app |
| 9 | AI Enhancement | ⏳ Pending | Predictions, suggestions |
| 10 | Polish & Launch | ⏳ Pending | Performance, testing |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-20 | Initial Atom architecture implementation |
| 2.0 | 2025-12-20 | Complete migration - deleted all legacy repos/models, unified Voice/LLM pipeline |
| 3.0 | 2025-12-21 | Added Level System Architecture - HealthKit, Gamification, Dashboard UI |
| 4.0 | 2025-12-21 | Phase 4-5 Complete - Daily Cron, Notifications, Voice Integration, Journal Router |
| 5.0 | 2025-12-21 | Phase 6 Complete - Content Pipeline, Performance Matching, Prediction Engine |
| 6.0 | 2025-12-21 | Phase 7 Complete - The Sanctuary: Causality Engine (90-day rolling window), Semantic Analysis, Cloud Model Integration, Neural Dashboard UI |

---

## Phase 7: The Sanctuary - Technical Reference

### New Atom Types

| Type | Purpose | Metadata Schema |
|------|---------|-----------------|
| `correlation_insight` | Discovered cross-metric correlations | `CorrelationInsightMetadata` |
| `causality_computation` | Computation run records | `CausalityComputationMetadata` |
| `semantic_extraction` | Journal topic/emotion extraction | `SemanticExtractionMetadata` |
| `sanctuary_snapshot` | Daily Sanctuary state cache | TBD |

### New Link Types

| Type | From | To | Purpose |
|------|------|-----|---------|
| `correlation_source` | Insight | Metric Atom | Source of correlation |
| `correlation_target` | Insight | Metric Atom | Target of correlation |
| `semantic_source` | Extraction | Journal Entry | Source journal |
| `computation_result` | Computation | Insight | Resulting insights |

### Key Files Created

**Data Layer:**
- `CausalityEngine.swift` - 90-day rolling correlation analysis
- `SemanticAnalysisEngine.swift` - NLP extraction from journals
- `CloudCorrelationAnalyzer.swift` - LLM-powered pattern recognition
- `SanctuaryDataProvider.swift` - Unified data access with caching

**UI Layer:**
- `SanctuaryView.swift` - Main neural dashboard
- `SanctuaryBackgroundView.swift` - Particle field animation
- `HeroOrbView.swift` - Central Cosmo Index orb
- `DimensionOrbView.swift` - Individual dimension orbs
- `DimensionDetailView.swift` - Expanded dimension view
- `SanctuaryHelpers.swift` - Animations, colors, utilities

### Correlation Computation

The Causality Engine runs daily at midnight via `DailyCronEngine`:

1. **Data Collection**: Gathers 90 days of metrics from all Atom types
2. **Correlation Calculation**: Pearson correlation with lag analysis (0-7 days)
3. **Insight Lifecycle**: New insights start as "emerging", validated over time, decay if not revalidated
4. **Cloud Enhancement**: Optional LLM analysis for compound patterns

**Thresholds:**
- Minimum correlation coefficient: 0.3
- Minimum effect size: 10%
- Minimum occurrences for validity: 5
- Decay rate: 2% per day without validation
- Removal threshold: 30% decay

### Semantic Analysis

Extracts from journal entries:
- **Topics**: Main subjects discussed (NLP noun extraction)
- **Emotions**: joy, anxiety, stress, gratitude, etc.
- **Goals**: "I want to...", "planning to..."
- **Fears**: "worried about...", "afraid of..."
- **Gratitude**: "grateful for...", "thankful..."
- **People**: Named entities

### Caching Strategy

| Data | TTL | Trigger |
|------|-----|---------|
| Dimension Levels | 5 min | User activity |
| Correlation Insights | 24 hr | Midnight cron |
| Live Metrics (HRV, XP) | 30 sec | Real-time |
| Trend Data | 1 hr | Background refresh |

---

**Remember: Everything is an Atom. UUID is the only identity. When in doubt, use AtomRepository.**
