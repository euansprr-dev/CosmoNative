# Global Floating Cosmo Window — Implementation Plan

## Executive Summary

Replace the embedded AI Collaborator panel in Content Focus Mode with a **global floating chat window** accessible from anywhere in the app via `Option+A`. Add sub-agent orchestration visibility, context-aware actions across all views, and settings integration.

**Architectural principle**: Build on top of existing infrastructure. The `UnifiedWritingEngine`, `CosmoAgentService`, `AgentToolRegistry` (55+ tools), `AgentContextAssembler`, `ConversationMemoryService`, notification system, and learning pipeline are all already built. This plan adds UI + orchestration visibility + context routing layers.

---

## Feature 1: Global Floating Cosmo Window

### 1.1 New Files

#### `UI/CosmoWindow/CosmoWindowView.swift` (~600 lines)
The main floating chat panel view.

```swift
struct CosmoWindowView: View {
    @StateObject private var viewModel = CosmoWindowViewModel.shared
    @Binding var isVisible: Bool
    @AppStorage("cosmoWindowAnchor") var anchor: CosmoWindowAnchor = .right

    // Body: VStack { headerBar, contextChips, messageList, inputBar }
    // Frame: width 400, full height minus 32px padding top/bottom
    // Background: DS.surface.opacity(0.85) + .ultraThinMaterial blur
    // Transition: .move(edge: anchor == .right ? .trailing : .leading)
    //             .combined(with: .opacity)
    // Animation: ProMotionSprings.snappy
}
```

**Header bar**: "Cosmo" label + context indicator pill (shows current view name) + minimize button + settings gear
**Context chips**: Scrollable horizontal row showing what Cosmo currently sees (e.g., "Ben's Carousel Draft", "3 swipes loaded", "Canvas: 12 blocks"). Populated from `viewModel.activeContext`.
**Message list**: ScrollViewReader with auto-scroll to bottom. Messages from `viewModel.messages`. User messages right-aligned on `DS.accent.opacity(0.15)` background. Cosmo messages left-aligned on `DS.surfaceElevated` background. Sub-agent status cards inline (see Feature 2).
**Input bar**: TextField with placeholder "Ask Cosmo anything..." + send button + voice input button (ties to existing `HotkeyManager`). `@FocusState` for keyboard focus on window open.

#### `UI/CosmoWindow/CosmoWindowViewModel.swift` (~800 lines)
The brain of the global window. Singleton `@MainActor ObservableObject`.

```swift
@MainActor
final class CosmoWindowViewModel: ObservableObject {
    static let shared = CosmoWindowViewModel()

    // MARK: - Published State
    @Published var messages: [CosmoWindowMessage] = []
    @Published var isProcessing: Bool = false
    @Published var activeContext: CosmoActiveContext = .none
    @Published var orchestrationPlan: OrchestrationPlan? = nil
    @Published var activeSubAgentCards: [SubAgentCard] = []
    @Published var inputText: String = ""
    @Published var error: String? = nil

    // MARK: - Dependencies
    private let agentService = CosmoAgentService.shared
    private let contextAssembler = AgentContextAssembler.shared
    private let conversationMemory = ConversationMemoryService.shared
    private let toolRegistry = AgentToolRegistry.shared

    // MARK: - Conversation Persistence
    private var conversationId: String = "cosmo-global"
    private var linkedAtomUUIDs: Set<String> = []

    // MARK: - Context Tracking
    private var contextProvider: (any CosmoContextProvider)? = nil

    // MARK: - Key Methods
    func sendMessage(_ text: String) async { }
    func updateContext(provider: any CosmoContextProvider) { }
    func clearContext() { }
    func loadConversation() async { }
    func clearConversation() async { }
    func cancelCurrentOperation() { }
    func handleUserIntervention(_ text: String) async { }
}
```

**Message routing logic in `sendMessage()`**:
1. Append user message to `messages` array
2. Check if there's an active orchestration that the user is intervening in → call `handleUserIntervention()`
3. Build system prompt: inject `activeContext` as Block 3 dynamic context into `AgentContextAssembler`
4. Detect if this is a writing-specific request on a content atom → route to `UnifiedWritingEngine` (existing per-content engine)
5. Otherwise → route to `CosmoAgentService.shared.processMessage()` with `source: .inApp`
6. Stream responses into `messages` array
7. If tool calls produce UI-visible changes (outline, draft, navigation), post appropriate notifications
8. Persist conversation via `ConversationMemoryService`

#### `UI/CosmoWindow/CosmoWindowMessage.swift` (~120 lines)
Message types for the chat.

```swift
enum CosmoWindowMessageType {
    case user
    case assistant
    case system
    case orchestrationPlan(OrchestrationPlan)
    case subAgentUpdate(SubAgentCard)
    case toolResult(name: String, summary: String, isError: Bool)
    case contextChange(from: String, to: String)
}

struct CosmoWindowMessage: Identifiable, Codable {
    let id: UUID
    let type: CosmoWindowMessageType
    let content: String
    let timestamp: Date
    var isStreaming: Bool = false
}
```

#### `UI/CosmoWindow/CosmoMessageBubble.swift` (~250 lines)
Individual message rendering.

```swift
struct CosmoMessageBubble: View {
    let message: CosmoWindowMessage
    // User: right-aligned, DS.accent.opacity(0.12) background, 12px radius
    // Assistant: left-aligned, DS.surfaceElevated background, subtle left accent bar (2px DS.accent)
    // System: centered, italic, DS.textMuted
    // OrchestrationPlan: structured card (see Feature 2)
    // SubAgentUpdate: compact status card (see Feature 2)
    // ToolResult: collapsible detail row
    // ContextChange: subtle inline divider "Context switched to Research Focus Mode"
}
```

#### `UI/CosmoWindow/CosmoContextProvider.swift` (~80 lines)
Protocol for views to provide context to Cosmo.

```swift
protocol CosmoContextProvider: AnyObject {
    var contextType: CosmoContextType { get }
    var contextSummary: String { get }
    var contextData: CosmoContextData { get }
    var availableActions: [CosmoAction] { get }
}

enum CosmoContextType: String, Codable {
    case contentFocusMode, swipeGallery, swipeStudy, researchFocusMode
    case connectionFocusMode, ideaFocusMode, noteFocusMode
    case library, plannerum, dayTimeline, thinkspaceCanvas
    case sanctuary, cosmoAIFocusMode, none
}

struct CosmoContextData: Codable {
    var currentAtomUUID: String?
    var currentAtomType: String?
    var currentAtomTitle: String?
    var viewSpecificData: [String: String]  // Flexible key-value context
    var visibleItemCount: Int?
    var activeFilters: [String]?
    var selectedText: String?
}

struct CosmoActiveContext {
    let type: CosmoContextType
    let summary: String
    let data: CosmoContextData
    let actions: [CosmoAction]
    static let none = CosmoActiveContext(type: .none, summary: "", data: .init(viewSpecificData: [:]), actions: [])
}
```

#### `UI/CosmoWindow/CosmoAction.swift` (~60 lines)
Action definitions that Cosmo can take on each view.

```swift
struct CosmoAction: Identifiable {
    let id: String
    let name: String
    let description: String
    let modelTier: ActionModelTier
    let handler: @Sendable (String) async throws -> String  // input → result
}

enum ActionModelTier {
    case local      // Gemma — spatial/structural manipulation
    case fast       // Haiku — simple data retrieval, filtering
    case balanced   // Sonnet — synthesis, summarization, analysis
    case creative   // Opus — creative writing, strategic analysis
}
```

### 1.2 Existing Files to Modify

#### `Navigation/MainView.swift`
Add the floating Cosmo window as a ZStack overlay.

```swift
// NEW: Add state
@State private var showCosmoWindow = false
@StateObject private var cosmoViewModel = CosmoWindowViewModel.shared

// NEW: Add to ZStack (zIndex 260 — above most overlays, below loading/error)
if showCosmoWindow {
    CosmoWindowView(isVisible: $showCosmoWindow)
        .zIndex(260)
        .transition(.move(edge: .trailing).combined(with: .opacity))
}

// NEW: Add to setupGlobalKeyMonitor() NSEvent handler
// Option+A toggle (configurable via @AppStorage("cosmoWindowKeybind"))
if event.modifierFlags.contains(.option) && event.charactersIgnoringModifiers == "a" {
    if !isFirstResponderTextField() {
        withAnimation(ProMotionSprings.snappy) {
            showCosmoWindow.toggle()
        }
        return nil  // consume the event
    }
}

// NEW: Add Escape handling (dismiss Cosmo window before other dismissals)
// Insert BEFORE existing escape cascade, after Instagram modal check:
if showCosmoWindow {
    withAnimation(ProMotionSprings.snappy) { showCosmoWindow = false }
    return nil
}

// NEW: Add context tracking — observe focusedEntity changes
.onChange(of: appState.focusedEntity) { newEntity in
    // Update CosmoWindowViewModel.shared.activeContext based on new view
}
.onChange(of: showingSanctuary) { _ in
    CosmoWindowViewModel.shared.updateContext(provider: sanctuaryContextProvider)
}
.onChange(of: showingPlannerum) { _ in
    CosmoWindowViewModel.shared.updateContext(provider: plannerumContextProvider)
}
```

#### `Core/CosmoApp.swift`
Add menu bar command for Cosmo window.

```swift
// In CosmoCommands struct, add:
CommandGroup(after: .toolbar) {
    Button("Toggle Cosmo") {
        NotificationCenter.default.post(name: .toggleCosmoWindow, object: nil)
    }
    .keyboardShortcut("a", modifiers: .option)
}
```

#### `Core/CosmoNotifications.swift`
Add new notification names.

```swift
// In CosmoNotification enum:
enum CosmoWindow {
    static let toggle = Notification.Name("cosmo.window.toggle")
    static let contextChanged = Notification.Name("cosmo.window.contextChanged")
    static let orchestrationUpdate = Notification.Name("cosmo.window.orchestrationUpdate")
    static let subAgentUpdate = Notification.Name("cosmo.window.subAgentUpdate")
}
```

#### `UI/FocusMode/Content/ContentFocusModeView.swift`
Remove the embedded AI Collaborator. Specific deletions:

1. **Delete** `@State private var showAICollaborator = false`
2. **Delete** `@StateObject private var writingEngine = UnifiedWritingEngine()`
3. **Delete** the floating popover ZStack block (lines ~74-94) that creates `ContentAICollaboratorView`
4. **Delete** the AI toggle button from `unifiedBottomBar` (the Button with `sparkles` icon)
5. **Delete** `.keyboardShortcut("j", modifiers: .command)` binding
6. **Delete** the escape handler branch for `showAICollaborator`
7. **Delete** `.task` block that initializes engine with conversation history
8. **Delete** `onDisappear` sync of engine messages
9. **Delete** `onChange(of: viewModel.state.currentStep)` engine notification
10. **Delete** `onChange(of: writingEngine.isProcessing)` conversation persistence
11. **Remove** `writingEngine` parameter from `ContentBrainstormView` and `ContentDraftView` calls
12. **Add** context provider registration: `.onAppear { CosmoWindowViewModel.shared.updateContext(provider: self.contextProvider) }`

#### `UI/FocusMode/Content/ContentDraftView.swift`
Remove `writingEngine` parameter. The inline AI (Expand/Condense/Rephrase via Cmd+Shift+E/C/R) stays as-is since it uses `AIWritingAssistant` (separate from the collaborator). The "Generate Draft with Opus" button should route through `CosmoWindowViewModel.shared` or use `OpusWritingEngine.shared` directly.

#### `UI/FocusMode/Content/ContentBrainstormView.swift`
Remove `writingEngine` parameter. The "Generate with Opus" button already has a fallback to `OpusWritingEngine.shared.generateOutline(for:)` — make that the primary path.

### 1.3 File to Delete

- **`UI/FocusMode/Content/ContentAICollaboratorView.swift`** (1273 lines) — entirely replaced by the global Cosmo window.

### 1.4 Conversation Persistence

**Model**: One global conversation stored as a `.systemEvent` atom in GRDB (via existing `ConversationMemoryService`).

- **Conversation ID**: `"cosmo-global-window"` (single persistent thread)
- **On app launch**: `CosmoWindowViewModel.loadConversation()` loads last conversation from GRDB
- **On each exchange**: Auto-save via `ConversationMemoryService.shared.saveConversation()`
- **On context switch**: Insert a `contextChange` message (not persisted to LLM context, just UI)
- **Token management**: Use existing `ConversationMemoryService.buildContextWindow()` which collapses older tool pairs and summarizes when over limit
- **Per-content writing sessions**: When user is in Content Focus Mode and asks writing questions, the global window creates/resumes a `UnifiedWritingEngine` session for that specific content atom (keyed by atom UUID). Writing engine conversation is SEPARATE from the global chat — it's the "working memory" for that content piece.

### 1.5 Context Awareness System

When the user navigates, the active view registers as the context provider:

| View Change | Context Provider | What's Injected into Block 3 |
|-------------|-----------------|------------------------------|
| Content Focus Mode | `ContentContextProvider` | Content atom title, phase, outline, hooks, draft excerpt, matched swipes, client profile |
| Swipe Study | `SwipeStudyContextProvider` | Swipe transcript, analysis (hook/framework/emotions), creator info |
| Swipe Gallery | `SwipeGalleryContextProvider` | Active filters, visible item count, sort mode |
| Research Focus | `ResearchContextProvider` | Research atom, transcript, annotations, connected atoms |
| Connection Focus | `ConnectionContextProvider` | All sections with items, connected sources, maturity level |
| Idea Focus | `IdeaContextProvider` | Idea title, body, status, format, platform, insight results, linked swipes |
| Note Focus | `NoteContextProvider` | Note title, content, tags |
| Library | `LibraryContextProvider` | Visible items, search query, sort/filter state |
| Plannerum | `PlannerumContextProvider` | View mode, tasks, active session, quests, XP |
| Day Timeline | `DayTimelineContextProvider` | Today's blocks, calendar events, unscheduled tasks |
| Thinkspace Canvas | `CanvasContextProvider` | All blocks with positions, types, titles, connections |
| Sanctuary | `SanctuaryContextProvider` | Dimension scores, cosmo index, active dimension |

Each context provider conforms to `CosmoContextProvider` and is lightweight — just returns current state, no computation.

### 1.6 Window Behavior Specification

- **Size**: 400px wide, full window height minus 32px top/bottom padding
- **Anchor**: Right side (default), toggleable to left via Settings (`@AppStorage("cosmoWindowAnchor")`)
- **Background**: `DS.surface.opacity(0.85)` + `.ultraThinMaterial` for blur-through effect
- **Animation**: Slide in/out from anchored edge using `ProMotionSprings.snappy` (response: 0.3, damping: 0.85)
- **Click-outside**: Does NOT auto-dismiss. Only closes via Option+A, Escape, or close button. Clicking outside the window passes through to the underlying view.
- **Full-screen mode**: Works — the ZStack overlay renders within the full-screen window
- **Multi-display**: Works — tied to the app window, not the screen
- **Open speed**: <100ms — no lazy loading of heavy resources on open. ViewModel is a singleton that's always alive.

---

## Feature 2: Sub-Agent Orchestration Visibility

### 2.1 New Types

#### In `UI/CosmoWindow/CosmoOrchestrationTypes.swift` (~100 lines)

```swift
struct OrchestrationPlan: Identifiable, Codable {
    let id: UUID
    let summary: String
    var steps: [OrchestrationStep]
    var status: OrchestrationStatus
    let createdAt: Date
}

struct OrchestrationStep: Identifiable, Codable {
    let id: UUID
    let agentName: String        // "HookWriter", "BodyWriter", "Scorer", "Researcher", "Refiner"
    let taskDescription: String  // "Writing 3 hook variants for Instagram carousel"
    var status: StepStatus       // .pending, .running, .complete, .failed, .revised
    var score: Double?           // From Scorer (0-10)
    var feedback: String?        // Why Scorer rejected / what Refiner fixed
    var result: String?          // Output summary
    var startedAt: Date?
    var completedAt: Date?
    var duration: TimeInterval? { /* computed */ }
}

enum StepStatus: String, Codable {
    case pending, running, complete, failed, revised

    var icon: String {
        switch self {
        case .pending: "circle"
        case .running: "arrow.trianglehead.2.clockwise"
        case .complete: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .revised: "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: DS.textMuted
        case .running: DS.accent
        case .complete: DS.green
        case .failed: DS.red
        case .revised: DS.orange
        }
    }
}

enum OrchestrationStatus: String, Codable {
    case planning, executing, paused, completed, cancelled
}

struct SubAgentCard: Identifiable, Codable {
    let id: UUID
    let stepId: UUID             // Links to OrchestrationStep
    let agentName: String
    var status: StepStatus
    var statusText: String       // "Searching swipe library...", "Writing hook variant 2/3..."
    var score: Double?
    var feedback: String?
    var isExpanded: Bool = false
}
```

### 2.2 Desktop Rendering — New Views

#### `UI/CosmoWindow/OrchestrationPlanCard.swift` (~150 lines)
Appears in chat when orchestration begins.

```swift
struct OrchestrationPlanCard: View {
    let plan: OrchestrationPlan
    @State private var isExpanded = true

    // Compact: "Cosmo is assembling your carousel draft" + step count + progress bar
    // Expanded: List of OrchestrationStep rows with status icons
    // Background: DS.surfaceElevated with DS.accent.opacity(0.05) left border
    // Cancel button: "Stop" appears on hover
}
```

#### `UI/CosmoWindow/SubAgentStatusCard.swift` (~120 lines)
Compact inline cards in the chat flow.

```swift
struct SubAgentStatusCard: View {
    @Binding var card: SubAgentCard

    // Layout: HStack { statusIcon, VStack { agentName (bold), statusText (secondary) }, score? }
    // Expandable: tap to show full output/feedback
    // Running state: pulsing DS.accent dot animation
    // Revised state: shows feedback text ("Voice drifted — sentences averaging 28 words, target is 18")
    // Complete state: shows score badge if applicable (green >= 7, orange 5-7, red < 5)
    // Size: compact — 60px height collapsed, 120px expanded
}
```

#### `UI/CosmoWindow/OrchestrationSummaryCard.swift` (~100 lines)
Final summary when orchestration completes.

```swift
struct OrchestrationSummaryCard: View {
    let plan: OrchestrationPlan

    // "Draft assembled" header
    // Stats: X sections, Y revisions, Z score
    // "What was caught and fixed" section with revision reasons
    // "View in editor" button → navigates to content focus mode
}
```

### 2.3 Real-Time Updates

**Desktop**: `CosmoWindowViewModel` observes orchestration events via `NotificationCenter`:
- `.cosmoWindow.orchestrationUpdate` — plan created/step status change
- `.cosmoWindow.subAgentUpdate` — individual agent progress

Updates flow: Sub-agent system posts notification → ViewModel updates `activeSubAgentCards` → SwiftUI re-renders cards in message list with animation.

**Streaming**: When a sub-agent is running, its `SubAgentCard.statusText` updates in real-time (e.g., "Writing section 2 of 5..."). Use `@Published` on the card's status text.

### 2.4 User Intervention Mid-Process

When the user types during active orchestration:
1. `CosmoWindowViewModel.sendMessage()` detects `orchestrationPlan?.status == .executing`
2. Pauses the orchestration (`status = .paused`)
3. Sends the user's message to the orchestrator LLM with current plan state as context
4. Orchestrator decides: redirect (modify remaining steps), continue (acknowledge and proceed), or cancel
5. Updated plan reflected in the UI with a system message explaining the change

### 2.5 Telegram Visibility

Modify `Agent/Bridges/TelegramBridgeService.swift` and `TelegramRichMessages.swift`:

**When orchestration starts**: Send plan as structured text:
```
Assembling your carousel draft:
1. Researching swipes for "trust building"
2. Writing 3 hook variants
3. Writing body sections (5 slides)
4. Scoring draft quality
5. Refining weak sections

Reply anytime to redirect.
```

**When sub-agents complete**: Edit the original message (via `editMessage()`) to update step statuses inline, OR send concise update messages:
```
Hook variants ready (scored 8.2/10)
Writing body sections... (2/5 complete)
```

**On revision**: Send explanation:
```
Scorer flagged slide 3: "Voice drifted — too formal for Ben's casual tone." Refiner is rewriting with more conversational phrasing.
```

**On completion**: Send summary with inline keyboard:
```
Draft assembled: 5 slides, 2 revisions, final score 8.7/10.
Caught: slide 3 voice drift (fixed), slide 5 weak CTA (strengthened).
[View Draft] [Request Changes] [Approve]
```

### 2.6 Existing Files to Modify for Orchestration Visibility

- **`Agent/Bridges/TelegramRichMessages.swift`**: Add `formatOrchestrationPlan()`, `formatSubAgentUpdate()`, `formatOrchestrationComplete()` methods
- **`Agent/Bridges/TelegramBridgeService.swift`**: Add orchestration message sending in the tool execution loop. When `AgentToolExecutor` processes writing tools, post orchestration notifications.
- **`Agent/Core/CosmoAgentService.swift`**: In the tool loop, post `.cosmoWindow.orchestrationUpdate` notifications when workflow steps execute. The existing `WorkflowPlan` system can be extended to emit these.

---

## Feature 3: Context-Aware Actions Across All Views

### 3.1 Context Provider Implementations

Each view gets a lightweight context provider. These are NOT new files — they're added as extensions or nested structs within existing view files.

#### Swipe Gallery / Swipe Study
**In `SwipeGalleryTab.swift`** — add `SwipeGalleryContextProvider`:
```swift
class SwipeGalleryContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .swipeGallery }
    var contextSummary: String { "\(filteredItems.count) swipes, sorted by \(sortMode)" }
    var contextData: CosmoContextData { /* filter state, visible items */ }
    var availableActions: [CosmoAction] {
        // setFilter(platform/hookType/narrative/format/niche/creator)
        // changeSortMode
        // openSwipe(uuid)
        // addToCanvas(uuid)
        // deleteSwipe(uuid)
    }
}
```

**In `SwipeStudyFocusModeView.swift`** — add `SwipeStudyContextProvider`:
```swift
class SwipeStudyContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .swipeStudy }
    var contextSummary: String { "Studying: \(atom.title ?? "Untitled") — \(analysis?.hookType?.rawValue ?? "unanalyzed")" }
    var contextData: CosmoContextData { /* transcript, analysis, playback position */ }
    var availableActions: [CosmoAction] {
        // reAnalyze, reclassify, addComment, editTranscript
    }
}
```

#### ThinkSpace Canvas
**In `CanvasView.swift`** — add `CanvasContextProvider`:
```swift
class CanvasContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .thinkspaceCanvas }
    var contextSummary: String { "\(blocks.count) blocks on canvas" }
    var contextData: CosmoContextData { /* all block positions, types, titles, connections */ }
    var availableActions: [CosmoAction] {
        // moveBlocks(positions) — via .moveCanvasBlocks notification
        // arrangeBlocks(layout) — via .arrangeCanvasBlocks notification
        // addConnection(from, to) — via DragToConnectManager
        // createBlock(type, position) — via .createEntityAtPosition
        // deleteBlock(id) — via .deleteSpecificBlock
        // summarizeCanvas — reads all block content
    }
}
```

**Canvas spatial manipulation uses local Gemma** (ActionModelTier.local) for speed:
- "Move research to top right" → parse positions → post `.moveCanvasBlocks`
- "Arrange blocks in a grid" → compute grid layout → post `.arrangeCanvasBlocks`
- "Add a connection between these" → identify blocks → post connection creation

#### Research / Connections
**In `ResearchFocusModeView.swift`** — add `ResearchContextProvider`:
```swift
class ResearchContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .researchFocusMode }
    var contextSummary: String { "Research: \(atom.title ?? "")" }
    var contextData: CosmoContextData { /* transcript, annotations, connected atoms */ }
    var availableActions: [CosmoAction] {
        // runResearchAgent(query) — uses existing viewModel.runResearchAgent()
        // addAnnotation(text, timestamp)
        // extractInsights — uses InsightExtractionEngine
        // crossReference(query) — uses Opus for analytical cross-referencing
    }
}
```

**In `ConnectionFocusModeView.swift`** — add `ConnectionContextProvider`:
```swift
class ConnectionContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .connectionFocusMode }
    var contextSummary: String { "Connection: \(atom.title ?? "")" }
    var contextData: CosmoContextData { /* all sections, items, sources, maturity */ }
    var availableActions: [CosmoAction] {
        // addItem(section, text)
        // generateGhosts — existing viewModel.generateGhostSuggestions()
        // acceptGhost(id)
        // findRelatedResearch(query)
    }
}
```

#### Library
**In `LibraryView.swift`** — add `LibraryContextProvider`:
```swift
class LibraryContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .library }
    var contextSummary: String { "\(displayItems.count) items in Library" }
    var contextData: CosmoContextData { /* search query, filters, visible items */ }
    var availableActions: [CosmoAction] {
        // search(query) — sets searchText
        // filter(type/score/date)
        // openItem(uuid) — posts .enterFocusMode
        // createAtom(type)
        // organizeIntoFolder(items, folder)
    }
}
```

#### Plannerum
**In `PlannerumView.swift`** — add `PlannerumContextProvider`:
```swift
class PlannerumContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .plannerum }
    var contextSummary: String { "Plannerum: \(viewMode.rawValue) view" }
    var contextData: CosmoContextData { /* tasks, session, quests, view mode */ }
    var availableActions: [CosmoAction] {
        // switchView(mode) — changes viewMode
        // addTask(title, intent, date)
        // completeTask(id)
        // startSession(taskId) — starts DeepWorkSessionEngine
        // reorderTasks(order)
        // suggestPlan — AI daily plan based on deadlines/energy
    }
}
```

**In `DayTimelineView.swift`** — add `DayTimelineContextProvider`:
```swift
class DayTimelineContextProvider: CosmoContextProvider {
    var contextType: CosmoContextType { .dayTimeline }
    var contextSummary: String { "Day: \(selectedDate.formatted(.dateTime.weekday().month().day()))" }
    var contextData: CosmoContextData { /* blocks, calendar events, unscheduled tasks */ }
    var availableActions: [CosmoAction] {
        // createBlock(title, start, duration, intent)
        // moveBlock(id, newStart)
        // resizeBlock(id, newDuration)
        // deleteBlock(id)
        // restructureDay(priorities) — reorders blocks
    }
}
```

### 3.2 Model Routing for Actions

All actions specify their `ActionModelTier`. The `CosmoWindowViewModel` routes accordingly:

| Tier | Model | Use Cases | Routing |
|------|-------|-----------|---------|
| `.local` | Gemma (Ollama) | Canvas spatial manipulation, simple structural tasks | `OllamaProvider` |
| `.fast` | Haiku 4.5 | Data retrieval, filtering, search queries | `AgentModelTier.sensor` |
| `.balanced` | Sonnet 4.5 | Synthesis, summarization, analysis, cross-referencing | `AgentModelTier.strategist` |
| `.creative` | Opus 4.6 | Creative writing, strategic analysis, content generation | `AgentModelTier.writer` |

The routing is **transparent to the user** — they never see which model is used. But the transparency panel (context chips) can optionally show "via Opus" or "via Haiku" as a subtle indicator.

### 3.3 How Context Flows

1. User navigates to a view (e.g., Swipe Study)
2. View registers its `CosmoContextProvider` with `CosmoWindowViewModel.shared.updateContext(provider:)`
3. ViewModel stores the provider reference and updates `activeContext`
4. Context chips in the Cosmo window update to show current context
5. When user sends a message, `sendMessage()` calls `contextProvider.contextData` to get fresh state
6. Context data is serialized and injected into the system prompt as Block 3 (dynamic context)
7. The LLM sees what the user sees and can suggest/execute context-appropriate actions
8. Actions post notifications to the underlying view (same notification system already used)

### 3.4 Example Interactions

**Swipe Study**: "How could I adapt this for Ben?"
1. Context: Swipe transcript + analysis loaded from `SwipeStudyContextProvider`
2. Model: Opus (creative analysis)
3. Flow: Agent reads swipe analysis → searches for Ben's client profile via `get_client_profile` tool → cross-references swipe structure with Ben's brand voice → suggests adapted outline
4. Output: Suggested outline in chat + "Create Content Piece" button that calls `create_content` tool

**Canvas**: "Put research blocks on the right side"
1. Context: All block positions + types from `CanvasContextProvider`
2. Model: Gemma (spatial, local, fast)
3. Flow: Identifies research-type blocks → computes right-side positions → posts `.moveCanvasBlocks`
4. Output: "Moved 3 research blocks to the right side" + blocks animate to new positions

**Plannerum**: "What should I focus on today?"
1. Context: Tasks + deadlines + energy (HRV if available) from `PlannerumContextProvider`
2. Model: Sonnet (analysis)
3. Flow: Reads tasks with due dates → checks energy level → prioritizes → suggests order
4. Output: Prioritized task list with reasoning in chat

---

## Feature 4: Settings Integration

### 4.1 Existing File Modifications

#### `Settings/SanctuarySettingsView.swift`
Add "Cosmo Window" section to the existing settings tabs. Place it in the existing "Cosmo Agent" tab or create a dedicated tab.

**New UI elements** (add to CosmoAgentSettingsTab or new section):

```swift
// Keybind Setting
HStack {
    Text("Toggle Cosmo Window")
    Spacer()
    KeybindPicker(
        currentKeybind: $cosmoWindowKeybind,  // @AppStorage("cosmoWindowKeybind") default "⌥A"
        label: "Shortcut"
    )
}

// Window Position
Picker("Window Position", selection: $cosmoWindowAnchor) {
    Text("Right").tag(CosmoWindowAnchor.right)
    Text("Left").tag(CosmoWindowAnchor.left)
}

// Conversation Management
Section("Conversation") {
    Button("Clear History") { CosmoWindowViewModel.shared.clearConversation() }
    Button("Export Conversation") { exportConversation() }
    HStack {
        Text("Token Usage")
        Spacer()
        Text("\(tokenUsage) tokens")
            .foregroundColor(DS.textSecondary)
    }
}
```

### 4.2 Learning Viewer

Add to CosmoAgentSettingsTab:

```swift
// Learning Viewer Section
Section("What Cosmo Has Learned") {
    // Grouped by client profile
    ForEach(clientProfiles) { profile in
        DisclosureGroup(profile.name) {
            // Explicit Rules (from .userPreference atoms)
            ForEach(explicitRules) { rule in
                HStack {
                    Text(rule.text)
                    Spacer()
                    Button("Delete") { deletePreference(rule.id) }
                }
            }

            // Inferred Patterns (from .agentLearning atoms)
            ForEach(inferredPatterns) { pattern in
                HStack {
                    VStack(alignment: .leading) {
                        Text(pattern.description)
                        Text("Confidence: \(pattern.confidence, specifier: "%.0f%%")")
                            .font(DS.cardMeta)
                            .foregroundColor(DS.textSecondary)
                    }
                    Spacer()
                    Button("Edit") { editPattern(pattern) }
                    Button("Delete") { deletePattern(pattern.id) }
                }
            }
        }
    }
}
```

Data source: Query `.userPreference` and `.agentLearning` atoms from GRDB, grouped by client UUID.

### 4.3 New Persistence Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cosmoWindowKeybind` | String | `"⌥A"` | Keyboard shortcut for toggle |
| `cosmoWindowAnchor` | String | `"right"` | Left or right anchor |
| `cosmoWindowWidth` | Double | `400` | Window width (future: resizable) |
| `cosmoWindowEnabled` | Bool | `true` | Feature flag for migration |

---

## Edge Cases

### User switches views mid-generation
- Sub-agents continue running in background (they're async tasks, not view-bound)
- Context chips update to new view, but the generation continues with original context
- When generation completes, results still apply to the original content piece (atom UUID tracked)
- If results involve UI changes (outline update, draft write), notifications still fire and the content state updates in GRDB regardless of current view

### Conversation exceeds context limits
- Existing `ConversationMemoryService.buildContextWindow()` already handles this
- Collapses older tool pairs into summaries
- Summarizes when estimated tokens > 50K or message count > 25
- The global conversation uses the same mechanism

### User contradicts a sub-agent mid-process
- Orchestration pauses → user message sent to orchestrator → orchestrator decides redirect/continue/cancel
- Remaining steps modified or replaced
- Already-completed steps kept unless explicitly undone
- UI shows "Redirected by you" badge on modified steps

### App goes to background mid-orchestration
- Async tasks continue running (they're in-process, not dependent on UI)
- On foreground return, `CosmoWindowViewModel` checks for completed/failed orchestration steps
- Any pending notifications are delivered

### Network failure during sub-agent call
- Individual step marked as `.failed` with error message
- Orchestrator attempts retry once
- If retry fails, orchestration pauses with error message in chat
- User can say "retry" or "skip this step"

### Window behavior in full-screen / windowed / multi-display
- Full-screen: ZStack overlay renders inside the full-screen window, same as CommandKView (zIndex 200)
- Windowed: Same behavior, window resizes include the Cosmo panel
- Multi-display: Cosmo panel is per-window (tied to the WindowGroup), not a separate window
- If the app window is narrow (< 800px), Cosmo panel overlays at full width with a dismiss backdrop

### User closes and reopens window during active orchestration
- ViewModel is a singleton — closing the window doesn't stop processing
- On reopen, all current state (messages, orchestration cards, sub-agent status) is immediately visible
- Scroll position resets to bottom (latest message)

---

## Migration Path

### Phase 1: Feature Flag
- Add `@AppStorage("cosmoWindowEnabled") var cosmoWindowEnabled = false` in MainView
- When `false`: AI Collaborator in Content Focus Mode works as before
- When `true`: AI Collaborator hidden, Cosmo window available via Option+A
- Settings toggle: "Use Global Cosmo Window (Beta)" in Cosmo Agent settings

### Phase 2: Transition (1-2 weeks)
- Default `cosmoWindowEnabled` to `true` for new sessions
- Migrate per-content conversation history to global conversation on first load
- Show one-time onboarding tooltip: "Cosmo is now available everywhere. Press Option+A from any screen."

### Phase 3: Cleanup
- Delete `ContentAICollaboratorView.swift`
- Remove feature flag checks
- Remove `writingEngine` from ContentDraftView and ContentBrainstormView
- Remove conversation history fields from `ContentFocusModeState` (or keep for backward compatibility)

---

## File Summary

### New Files (11)
| File | Lines (est.) | Purpose |
|------|-------------|---------|
| `UI/CosmoWindow/CosmoWindowView.swift` | ~600 | Main floating chat panel |
| `UI/CosmoWindow/CosmoWindowViewModel.swift` | ~800 | Singleton brain, message routing, context tracking |
| `UI/CosmoWindow/CosmoWindowMessage.swift` | ~120 | Message type definitions |
| `UI/CosmoWindow/CosmoMessageBubble.swift` | ~250 | Message rendering |
| `UI/CosmoWindow/CosmoContextProvider.swift` | ~80 | Context protocol + types |
| `UI/CosmoWindow/CosmoAction.swift` | ~60 | Action definitions |
| `UI/CosmoWindow/CosmoOrchestrationTypes.swift` | ~100 | Orchestration plan/step types |
| `UI/CosmoWindow/OrchestrationPlanCard.swift` | ~150 | Plan card view |
| `UI/CosmoWindow/SubAgentStatusCard.swift` | ~120 | Sub-agent status card view |
| `UI/CosmoWindow/OrchestrationSummaryCard.swift` | ~100 | Completion summary card |
| `Settings/CosmoWindowSettingsSection.swift` | ~200 | Settings UI (keybind, position, learning viewer, conversation mgmt) |

### Modified Files (14)
| File | Changes |
|------|---------|
| `Navigation/MainView.swift` | Add CosmoWindow overlay (zIndex 260), Option+A keybind, context tracking onChange handlers |
| `Core/CosmoApp.swift` | Add menu bar command for Cosmo toggle |
| `Core/CosmoNotifications.swift` | Add CosmoWindow notification names |
| `UI/FocusMode/Content/ContentFocusModeView.swift` | Remove AI Collaborator (12 specific deletions), add context provider |
| `UI/FocusMode/Content/ContentDraftView.swift` | Remove writingEngine parameter |
| `UI/FocusMode/Content/ContentBrainstormView.swift` | Remove writingEngine parameter |
| `Agent/Bridges/TelegramRichMessages.swift` | Add orchestration formatting methods |
| `Agent/Bridges/TelegramBridgeService.swift` | Add orchestration message sending |
| `Agent/Core/CosmoAgentService.swift` | Post orchestration notifications in tool loop |
| `Settings/CosmoAgentSettingsTab.swift` | Add Cosmo Window settings section and learning viewer |
| `UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift` | Add context provider registration |
| `Canvas/CanvasView.swift` | Add context provider registration |
| `UI/FocusMode/Research/ResearchFocusModeView.swift` | Add context provider registration |
| `UI/Plannerum/PlannerumView.swift` | Add context provider registration |

### Deleted Files (1)
| File | Reason |
|------|--------|
| `UI/FocusMode/Content/ContentAICollaboratorView.swift` | Replaced by global Cosmo window |

### pbxproj
- Add 11 new files to `CosmoOS.xcodeproj/project.pbxproj` under a new `CosmoWindow` group
- Remove `ContentAICollaboratorView.swift` reference (after migration complete)
- **Use unique pbxproj IDs** — never reuse hex patterns across file references

---

## Implementation Order

1. **CosmoContextProvider protocol + CosmoAction types** — foundation
2. **CosmoWindowMessage + CosmoOrchestrationTypes** — data types
3. **CosmoWindowViewModel** — core logic, message routing, context tracking
4. **CosmoMessageBubble** — message rendering
5. **CosmoWindowView** — main panel UI
6. **MainView integration** — ZStack overlay, keybind, context tracking
7. **Orchestration cards** — OrchestrationPlanCard, SubAgentStatusCard, OrchestrationSummaryCard
8. **Context providers** — add to each view (SwipeStudy, Canvas, Research, Plannerum, etc.)
9. **Settings section** — keybind, position, learning viewer
10. **Telegram orchestration visibility** — TelegramRichMessages extensions
11. **ContentFocusModeView cleanup** — remove AI Collaborator with feature flag
12. **Testing + edge cases** — full-screen, multi-display, mid-generation view switch, network failure
