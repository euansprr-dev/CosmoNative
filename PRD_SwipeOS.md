# CosmoOS SwipeOS: The Living Swipe Intelligence System

## Product Requirements Document
### Version 1.0 — February 2026

---

## I. EXECUTIVE VISION

Every creator on earth keeps a swipe file. None of them have a system that truly *works*.

Current swipe file tools are screenshot graveyards — collections of bookmarks that grow stale, offer no insight, and never connect back to the creative work they were meant to inspire. The gap between *saving* content and *becoming a better creator* remains a chasm.

**SwipeOS** closes that chasm. It transforms CosmoOS from a knowledge management system into the first **living creative intelligence platform** — where every piece of consumed content becomes a learning artifact that connects to your creative output, reveals patterns you can't see, and actively makes you a better creator over time.

This is not a feature. It is a new dimension of CosmoOS.

### The Core Thesis

> A swipe file should not be a place you put things. It should be a system that teaches you, connects to your work, and compounds your creative ability over time.

### What Makes This Unprecedented

| Every Other Tool | SwipeOS |
|-----------------|---------|
| Saves content | Understands content |
| Organizes by folder/tag | Connects by semantic meaning |
| Static collection | Living intelligence that evolves |
| Separate from creation | Embedded in the creation workflow |
| Passive storage | Active learning engine |
| Cloud-dependent AI | On-device Apple Silicon intelligence |
| One-dimensional (just ads, just copy) | Universal (video, copy, design, structure, audio) |
| Collection grows, value stays flat | Collection grows, value compounds exponentially |

---

## II. INTEGRATION ARCHITECTURE

SwipeOS is not a new screen. It permeates five existing surfaces of CosmoOS:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SWIPEOS INTEGRATION MAP                      │
│                                                                     │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │ CAPTURE  │───→│  SWIPE ATOM  │───→│   KNOWLEDGE GRAPH        │  │
│  │ Layer    │    │  (enriched)  │    │   (technique edges,      │  │
│  └──────────┘    └──────┬───────┘    │    pattern clusters)     │  │
│                         │            └────────────┬─────────────┘  │
│                         │                         │                │
│           ┌─────────────┼─────────────┐           │                │
│           ▼             ▼             ▼           ▼                │
│    ┌────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐     │
│    │  1. SWIPE  │ │ 2. SWIPE │ │ 3. WRITE │ │ 4. SWIPE     │     │
│    │  STUDY     │ │ GALLERY  │ │ WITH     │ │ INTELLIGENCE │     │
│    │  MODE      │ │ (Canvas) │ │ SWIPES   │ │ (Sanctuary)  │     │
│    └────────────┘ └──────────┘ └──────────┘ └──────────────┘     │
│                                                    │               │
│                                              ┌─────▼─────────┐    │
│                                              │ 5. PRACTICE   │    │
│                                              │    ENGINE     │    │
│                                              └───────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Integration Points with Existing Systems

| Existing System | SwipeOS Integration |
|----------------|-------------------|
| **Atom Model** | Research atoms gain `SwipeAnalysis` structured data (auto-generated teardown) |
| **Knowledge Graph** | New edge types: `techniqueMatch`, `structuralSibling`, `hookPattern`, `emotionalArc` |
| **Canvas (Thinkspace)** | Swipe Gallery block type; swipe atoms appear with technique badges |
| **Content Focus Mode** | "Reference Rail" sidebar surfaces relevant swipes during writing |
| **Research Focus Mode** | "Teardown Mode" toggle for deep swipe analysis |
| **Connection Focus Mode** | Swipe atoms linkable as evidence/examples in mental models |
| **Cosmo AI** | New "Study" mode analyzes swipe patterns; "Create" mode references swipes |
| **Command-K** | Technique-aware search ("find urgency hooks", "show PAS examples") |
| **Sanctuary** | New "Creative" dimension tracks swipe study XP and pattern mastery |
| **Plannerum** | "Study Block" schedule type for deliberate swipe practice |
| **Voice Pipeline** | "Swipe this" voice command for hands-free capture with spoken hook annotation |

---

## III. THE FIVE PILLARS

---

### PILLAR 1: SWIPE STUDY MODE

*A focus mode for deep content analysis — the heart of SwipeOS.*

#### Concept

When a user opens a swipe atom in focus mode, they enter **Swipe Study Mode** — a dedicated workspace designed for deliberate deconstruction. This is the Gary Halbert method digitized and supercharged with on-device AI.

#### Visual Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ← Back    "Why This Hook Works: MrBeast's $1 vs $1M"     ⚡ Teardown  │
│─────────────────────────────────────────────────────────────────────────│
│                                                                        │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐  │
│  │                             │  │  TEARDOWN PANEL                 │  │
│  │     ORIGINAL CONTENT        │  │                                 │  │
│  │                             │  │  ┌─────────────────────────┐    │  │
│  │  [YouTube player /          │  │  │ ⚡ HOOK                  │    │  │
│  │   Article text /            │  │  │ "I Spent $1 vs $1,000,000│    │  │
│  │   Instagram embed /         │  │  │  on a Vacation"          │    │  │
│  │   Tweet card]               │  │  │                          │    │  │
│  │                             │  │  │ Type: Contrast Gap       │    │  │
│  │                             │  │  │ Emotion: Curiosity       │    │  │
│  │                             │  │  │ Score: 9.2/10            │    │  │
│  │                             │  │  └─────────────────────────┘    │  │
│  │                             │  │                                 │  │
│  │                             │  │  ┌─────────────────────────┐    │  │
│  │                             │  │  │ 🏗️ STRUCTURE             │    │  │
│  │                             │  │  │                          │    │  │
│  │                             │  │  │ Framework: Escalation    │    │  │
│  │                             │  │  │ Arc                      │    │  │
│  │                             │  │  │                          │    │  │
│  │                             │  │  │ ┌──┐┌──┐┌──┐┌──┐┌──┐   │    │  │
│  │                             │  │  │ │H ││E ││P ││C ││R │   │    │  │
│  │                             │  │  │ │o ││s ││a ││l ││e │   │    │  │
│  │                             │  │  │ │o ││c ││y ││i ││v │   │    │  │
│  │                             │  │  │ │k ││a ││o ││m ││e │   │    │  │
│  │                             │  │  │ │  ││l ││f ││a ││a │   │    │  │
│  │                             │  │  │ │  ││a ││f ││x ││l │   │    │  │
│  │                             │  │  │ └──┘└──┘└──┘└──┘└──┘   │    │  │
│  │                             │  │  │ Visual structure map     │    │  │
│  │                             │  │  └─────────────────────────┘    │  │
│  │                             │  │                                 │  │
│  │                             │  │  ┌─────────────────────────┐    │  │
│  │                             │  │  │ 🎭 EMOTIONAL ARC         │    │  │
│  │                             │  │  │                          │    │  │
│  │                             │  │  │  1.0 ╭─╮                │    │  │
│  │                             │  │  │      │ │   ╭─╮          │    │  │
│  │                             │  │  │  0.5 │ ╰───╯ │  ╭──╮   │    │  │
│  │                             │  │  │      │       ╰──╯  │   │    │  │
│  │                             │  │  │  0.0 ╰─────────────╯   │    │  │
│  │                             │  │  │  Curiosity→Awe→Tension  │    │  │
│  │                             │  │  │  →Relief→Aspiration     │    │  │
│  │                             │  │  └─────────────────────────┘    │  │
│  └─────────────────────────────┘  │                                 │  │
│                                   │  ┌─────────────────────────┐    │  │
│  ┌─────────────────────────────┐  │  │ 🧲 PERSUASION STACK     │    │  │
│  │  TRANSCRIPT / COPY          │  │  │                          │    │  │
│  │  (highlighted by technique) │  │  │  ● Social Proof    ████ │    │  │
│  │                             │  │  │  ● Curiosity Gap   ███  │    │  │
│  │  "I gave someone $1 to plan │  │  │  ● Contrast Effect ██   │    │  │
│  │   █████████████████████████ │  │  │  ● Authority       █    │    │  │
│  │   the cheapest vacation     │  │  │  ● Scarcity        ▪    │    │  │
│  │   possible, and I gave      │  │  └─────────────────────────┘    │  │
│  │   someone else $1,000,000   │  │                                 │  │
│  │   ████████████████████████" │  │  ┌─────────────────────────┐    │  │
│  │   to plan the most          │  │  │ 🔗 SIMILAR IN COLLECTION│    │  │
│  │   expensive..."             │  │  │                          │    │  │
│  │                             │  │  │  • "I Tried Every..."   │    │  │
│  │  Legend:                    │  │  │    (Escalation Arc, 8.7) │    │  │
│  │  ███ Curiosity Gap          │  │  │  • "$1 vs $100 Date"    │    │  │
│  │  ███ Social Proof           │  │  │    (Contrast Gap, 9.0)  │    │  │
│  │  ███ Escalation             │  │  │  • "Cheapest to Most.." │    │  │
│  │                             │  │  │    (Escalation Arc, 8.4) │    │  │
│  └─────────────────────────────┘  └──┴─────────────────────────┴──┘  │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────────┐│
│  │  YOUR NOTES                                                        ││
│  │  ┌─────────────────────────────────────────────────────────────┐  ││
│  │  │ The genius is the contrast WITHIN the hook — not just       │  ││
│  │  │ $1 vs $1M, but "vacation" makes it relatable. Everyone     │  ││
│  │  │ wants a vacation. The extreme range creates curiosity       │  ││
│  │  │ about what both extremes look like.                         │  ││
│  │  └─────────────────────────────────────────────────────────────┘  ││
│  │  + Add note    🏷️ Tag: #contrast #scale #relatable               ││
│  └────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

#### Teardown Panel Components

**1. Hook Analysis Card**
- Extracted hook text displayed prominently
- AI-classified hook type (Curiosity Gap, Bold Claim, Question, Story, Statistic, Controversy, Contrast, How-To, List, Challenge)
- Dominant emotion tag (NaturalLanguage sentiment + custom classifier)
- Hook effectiveness score (0-10, based on pattern matching against high-performing hooks in collection)
- "Adapt This Hook" button → opens template generator

**2. Structure Map**
- Visual block diagram showing content sections
- Each block is labeled (Hook, Escalation, Payoff, Climax, Reveal, CTA, etc.)
- Block heights represent relative duration/word count
- Color-coded by function (setup = blue, tension = amber, payoff = green, CTA = coral)
- Framework label (AIDA, PAS, BAB, Escalation Arc, Story Loop, etc.)
- Tap any block to jump to that section in the transcript/copy

**3. Emotional Arc Chart**
- Line graph showing emotional intensity over time/position
- Generated by NaturalLanguage framework sentiment analysis on each segment
- Labeled emotion transitions (Curiosity → Awe → Tension → Relief → Aspiration)
- Tap any point to see the corresponding text
- Compare button: overlay arcs from similar swipes

**4. Persuasion Stack**
- Bar chart showing which persuasion techniques are present and how heavily used
- Techniques: Social Proof, Curiosity Gap, Contrast Effect, Authority, Scarcity, Urgency, Reciprocity, Storytelling, Loss Aversion, Exclusivity
- Each bar is tappable → highlights the specific text passages using that technique
- NaturalLanguage + on-device classifier powered

**5. Similar in Collection**
- Semantic search against all other swipe atoms
- Shows swipes using similar hooks, structures, or techniques
- Each result shows: title, primary technique, hook score
- Tap to open side-by-side comparison

**6. Your Notes Section**
- Rich text note area with auto-linking to CosmoOS entities
- Tag system for personal categorization
- Linked to the swipe atom's `personalNotes` metadata field

#### On-Device AI Pipeline (Apple Silicon)

```
Content Captured
      │
      ▼
┌─────────────────────────────────────────────────┐
│  STAGE 1: Content Extraction (< 100ms)          │
│  • Vision OCR for screenshots                    │
│  • NaturalLanguage tokenization for text         │
│  • YouTube/social API for structured data         │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  STAGE 2: On-Device Analysis (< 500ms)          │
│  Neural Engine + NaturalLanguage Framework       │
│                                                  │
│  • Sentiment analysis per sentence/segment       │
│  • Named entity recognition (brands, people)     │
│  • Word embedding generation (768-dim)           │
│  • Readability scoring (Flesch-Kincaid, Fog)     │
│  • Sentence rhythm analysis (lengths, variety)   │
│  • Passive voice detection                       │
│  • Emotional valence mapping                     │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  STAGE 3: Technique Classification (< 200ms)    │
│  Core ML Custom Models (trained on swipe data)   │
│                                                  │
│  • Hook type classifier (10 categories)          │
│  • Framework detector (8 frameworks)             │
│  • Persuasion technique identifier (multi-label) │
│  • Structure segmenter (section boundaries)      │
│  • Emotion arc generator (temporal sentiment)    │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  STAGE 4: Deep Analysis (< 2s, async)           │
│  On-device LLM (FineTunedQwen or Hermes)         │
│  OR OpenRouter Gemini for complex teardowns       │
│                                                  │
│  • Full teardown narrative generation            │
│  • Hook adaptation templates                     │
│  • Cross-reference with existing collection       │
│  • Pattern cluster assignment                    │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  STAGE 5: Graph Integration (< 100ms)           │
│  NodeGraphEngine + VectorDatabase                │
│                                                  │
│  • Create/update GraphNode                       │
│  • Generate semantic edges to similar swipes     │
│  • Create technique edges (same hook type)       │
│  • Update pattern cluster assignments            │
│  • Index in vector database for retrieval        │
└─────────────────────────────────────────────────┘
```

**Total time from capture to full analysis: < 3 seconds on Apple Silicon.**

All stages 1-3 run entirely on-device via Neural Engine. Stage 4 uses on-device LLM when possible, falls back to cloud API for complex teardowns. Stage 5 is pure local database operations.

---

### PILLAR 2: SWIPE GALLERY (Canvas Integration)

*Your swipe collection as a spatial constellation on the Thinkspace canvas.*

#### Concept

Swipe atoms appear on the canvas as visually distinct blocks with technique badges. A new **Swipe Gallery** canvas view mode transforms the Thinkspace into a filterable, sortable visual library of all swipe atoms — organized spatially by technique, emotion, or platform.

#### Swipe Block Design (Canvas)

```
┌────────────────────────────────────────┐
│ ┌──────────────────────────────────┐   │
│ │                                  │   │
│ │    [Thumbnail / Preview]         │   │
│ │                                  │   │
│ │         ▶ 12:34                  │   │
│ └──────────────────────────────────┘   │
│                                        │
│  "I Spent $1 vs $1,000,000 on a       │
│   Vacation"                            │
│                                        │
│  MrBeast · YouTube · 2 days ago        │
│                                        │
│  ┌──────────┐ ┌───────────┐ ┌──────┐  │
│  │⚡Contrast │ │🎭Curiosity│ │ 9.2  │  │
│  │   Gap    │ │   Gap     │ │ /10  │  │
│  └──────────┘ └───────────┘ └──────┘  │
│                                        │
│  ━━━━━━━━━━━━━━━━━━━━━━ Emotional Arc  │
│  ╭─╮   ╭─╮                            │
│  │ ╰───╯ ╰──╮  ╭──╮                   │
│  ╰───────────╰──╯  ╰─                 │
└────────────────────────────────────────┘
```

**Block Size**: 340 x 380 (slightly larger than research blocks to accommodate technique badges)

**Visual Differentiation from Research Blocks**:
- **Accent color**: Gold (#FFD700) border glow instead of green
- **Technique badges**: Pill-shaped tags below the title showing classified techniques
- **Hook score**: Circular score badge (0-10) in the bottom-right of the technique row
- **Mini emotional arc**: Sparkline-style emotional arc at the very bottom
- **Swipe icon**: Small lightning bolt (⚡) in the top-left corner of the thumbnail

#### Swipe Gallery View Mode

When activated from the canvas toolbar, the Thinkspace reorganizes into a gallery layout:

```
┌──────────────────────────────────────────────────────────────────────┐
│  SWIPE GALLERY                                        ☰ Canvas Mode │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ All │ Hooks │ Structure │ Emotion │ Platform │ Score │ Recent │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  🔍 "urgency hooks in fitness"                    [Sort: Score ▼]   │
│                                                                      │
│  ┌─── CURIOSITY GAP (23 swipes) ─────────────────────────────────┐  │
│  │                                                                │  │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  │  │
│  │  │  🎬    │  │  📱    │  │  🐦    │  │  🎬    │  │  📱    │  │  │
│  │  │        │  │        │  │        │  │        │  │        │  │  │
│  │  │ "I Sp..│  │ "The ..│  │ "Nobo..│  │ "What..│  │ "Stop..│  │  │
│  │  │  9.2   │  │  8.8   │  │  8.5   │  │  8.3   │  │  8.1   │  │  │
│  │  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─── CONTRAST EFFECT (18 swipes) ───────────────────────────────┐  │
│  │                                                                │  │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐              │  │
│  │  │  🎬    │  │  📱    │  │  📝    │  │  🎬    │   + 14 more  │  │
│  │  │        │  │        │  │        │  │        │              │  │
│  │  │ "$1 vs.│  │ "Rich..│  │ "Befo..│  │ "Free..│              │  │
│  │  │  9.0   │  │  8.7   │  │  8.4   │  │  8.2   │              │  │
│  │  └────────┘  └────────┘  └────────┘  └────────┘              │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─── STORYTELLING (15 swipes) ──────────────────────────────────┐  │
│  │  ...                                                           │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

**Filter Tabs**:
- **All**: Every swipe, sorted by score or recency
- **Hooks**: Grouped by hook type (Curiosity Gap, Contrast, Bold Claim, Question, etc.)
- **Structure**: Grouped by framework (AIDA, PAS, Escalation, Story Loop, etc.)
- **Emotion**: Grouped by dominant emotion (Curiosity, Urgency, Aspiration, etc.)
- **Platform**: Grouped by source (YouTube, Instagram, X, Threads, Website, etc.)
- **Score**: Ranked by hook effectiveness score
- **Recent**: Chronological, newest first

**Semantic Search**: The search bar uses embedding-based search. "urgency hooks in fitness" finds relevant swipes even if those exact words don't appear. Powered by on-device NaturalLanguage word embeddings + VectorDatabase.

---

### PILLAR 3: WRITE WITH SWIPES (Content Focus Mode Integration)

*Your swipe file becomes your co-pilot during content creation.*

#### Concept

When a user enters Content Focus Mode to write, a new **Reference Rail** appears as an optional sidebar. It surfaces swipe atoms that are relevant to what they're currently writing — intelligently, contextually, and non-intrusively.

#### Visual Layout — Content Draft View with Reference Rail

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ← Back    "10 Lessons From Building in Public"    Step 2: Draft   ⚡   │
│─────────────────────────────────────────────────────────────────────────│
│                                                                          │
│  ┌───── OUTLINE ─────┐  ┌──────── EDITOR ────────┐  ┌─ REFERENCE ──┐  │
│  │                    │  │                         │  │   RAIL       │  │
│  │  1. Introduction   │  │  Building in public     │  │              │  │
│  │  ► 2. Why Most     │  │  changed everything     │  │ ┌──────────┐│  │
│  │     People Fail    │  │  about how I approach    │  │ │ RELEVANT ││  │
│  │  3. The Daily      │  │  content creation.       │  │ │ SWIPES   ││  │
│  │     Practice       │  │                         │  │ │          ││  │
│  │  4. What I'd Do    │  │  But here's the thing   │  │ │ ⚡ "Build ││  │
│  │     Differently    │  │  nobody talks about:     │  │ │ in Publi.││  │
│  │  5. Conclusion     │  │  most people who try     │  │ │ @levelsio││  │
│  │                    │  │  building in public      │  │ │ Hook: 8.9││  │
│  │                    │  │  quit within 30 days.    │  │ │          ││  │
│  │                    │  │                         │  │ │ ⚡ "Why I ││  │
│  │                    │  │  [cursor here]           │  │ │ Share My ││  │
│  │                    │  │  ▌                       │  │ │ Revenue" ││  │
│  │                    │  │                         │  │ │ Hook: 8.2││  │
│  │                    │  │                         │  │ └──────────┘│  │
│  │                    │  │                         │  │              │  │
│  │                    │  │                         │  │ ┌──────────┐│  │
│  │                    │  │                         │  │ │ TECHNIQUE││  │
│  │                    │  │                         │  │ │ SUGGEST  ││  │
│  │                    │  │                         │  │ │          ││  │
│  │                    │  │                         │  │ │ Your     ││  │
│  │                    │  │                         │  │ │ section  ││  │
│  │                    │  │                         │  │ │ could use││  │
│  │                    │  │                         │  │ │ a Story  ││  │
│  │                    │  │                         │  │ │ Loop.    ││  │
│  │                    │  │                         │  │ │ See 3    ││  │
│  │                    │  │                         │  │ │ examples ││  │
│  │                    │  │                         │  │ │ →        ││  │
│  │                    │  │                         │  │ └──────────┘│  │
│  └────────────────────┘  └─────────────────────────┘  └─────────────┘  │
│                                                                          │
│  Word count: 847    Reading time: ~4 min    ████████░░ 80% of target    │
└──────────────────────────────────────────────────────────────────────────┘
```

#### Reference Rail Behavior

**Contextual Surfacing (Automatic)**:
- As the user writes, the Reference Rail updates every 5 seconds (debounced)
- It analyzes the current paragraph/section being written
- Uses semantic search to find relevant swipes from their collection
- Surfaces swipes that match by topic, technique, or structure
- Results update non-intrusively (no layout jumps, smooth fade transitions)

**Technique Suggestions (Proactive)**:
- AI analyzes the current section's structure and emotional trajectory
- Suggests techniques from the user's swipe collection that could strengthen the writing
- Example: "Your opening uses a bold claim. Your swipe file has 7 examples of bold-claim openers that transition into storytelling. See examples →"
- Tapping "→" opens a mini-gallery of relevant swipes in a slide-over panel

**Manual Pull (On-Demand)**:
- User can type `/swipe` in the editor to search their swipe collection inline
- Autocomplete dropdown shows matching swipes with preview
- Selecting a swipe inserts it as a collapsible reference block in the editor margin
- The reference block shows: hook, source, technique tags, and a "View Full" link

#### How It Works Under the Hood

```
User Types in Editor
        │
        ▼ (debounced 5s)
┌───────────────────────────┐
│ Extract current context:  │
│ • Current paragraph text  │
│ • Section heading         │
│ • Content atom's topic    │
│ • Connected atom context  │
└───────────┬───────────────┘
            │
            ▼
┌───────────────────────────┐
│ Generate query embedding  │
│ (NaturalLanguage, on-     │
│ device, < 10ms)           │
└───────────┬───────────────┘
            │
            ▼
┌───────────────────────────┐
│ Vector search across      │
│ swipe atoms only          │
│ (VectorDatabase, < 50ms)  │
│                           │
│ Filter: isSwipeFile=true  │
│ Boost: connected atoms    │
│ Boost: same project       │
└───────────┬───────────────┘
            │
            ▼
┌───────────────────────────┐
│ Rank by relevance:        │
│ • Semantic similarity     │
│ • Graph distance          │
│ • Technique match         │
│ • Recency                 │
│ Return top 5              │
└───────────┬───────────────┘
            │
            ▼
  Update Reference Rail UI
  (fade animation, 300ms)
```

**Performance Target**: < 100ms from context extraction to UI update. All on-device.

---

### PILLAR 4: SWIPE INTELLIGENCE (Pattern Recognition)

*Your collection becomes smarter than you.*

#### Concept

As a user's swipe collection grows, SwipeOS surfaces meta-patterns, trends, and gaps that would be invisible to manual review. This intelligence lives in the **Sanctuary** dashboard (creative dimension) and as proactive suggestions throughout the app.

#### Sanctuary Creative Dimension — Swipe Intelligence Dashboard

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     CREATIVE INTELLIGENCE                                │
│                     Level 7 · 2,340 XP                                   │
│─────────────────────────────────────────────────────────────────────────│
│                                                                          │
│  ┌─────────────────────────────────┐  ┌──────────────────────────────┐  │
│  │  TECHNIQUE MASTERY              │  │  COLLECTION HEALTH           │  │
│  │                                 │  │                              │  │
│  │  Curiosity Gap    ████████░ 82% │  │  Total Swipes: 247           │  │
│  │  Storytelling     ██████░░░ 65% │  │  Studied: 189 (77%)          │  │
│  │  Social Proof     █████░░░░ 55% │  │  With Notes: 142 (58%)       │  │
│  │  Contrast Effect  ████░░░░░ 45% │  │  Avg Hook Score: 7.8         │  │
│  │  PAS Framework    ███░░░░░░ 35% │  │                              │  │
│  │  Scarcity         ██░░░░░░░ 22% │  │  Platforms:                  │  │
│  │  Loss Aversion    █░░░░░░░░ 12% │  │  YouTube ████████░░ 78       │  │
│  │                                 │  │  Instagram ██████░░░ 62      │  │
│  │  ⚠️ Gap: You have almost no     │  │  X/Twitter ████░░░░░ 41      │  │
│  │  examples of Loss Aversion.     │  │  Threads ███░░░░░░░ 34       │  │
│  │  This is one of the most        │  │  Articles ██░░░░░░░ 22       │  │
│  │  powerful persuasion tools.     │  │  Clipboard █░░░░░░░░ 10      │  │
│  │  → Find examples                │  │                              │  │
│  └─────────────────────────────────┘  └──────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  PATTERN INSIGHTS                                                 │  │
│  │                                                                   │  │
│  │  📊 "89% of your top-scoring hooks (8+) use exactly 8-12 words"   │  │
│  │                                                                   │  │
│  │  📊 "Your YouTube swipes cluster into 3 hook patterns:            │  │
│  │      Contrast (34%), Question (28%), Bold Claim (22%)"            │  │
│  │                                                                   │  │
│  │  📊 "Swipes with Escalation Arc structure average 1.4 points      │  │
│  │      higher hook score than Linear structure"                     │  │
│  │                                                                   │  │
│  │  🔥 "Trending: 12 swipes this week use 'I tried X so you don't   │  │
│  │      have to' hook pattern (up 300% from last month)"             │  │
│  │                                                                   │  │
│  │  💡 "Cross-domain opportunity: Your Instagram carousel hooks      │  │
│  │      could work as YouTube titles. 4 examples →"                  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  TECHNIQUE CONSTELLATION                                          │  │
│  │                                                                   │  │
│  │         Curiosity Gap ●                                           │  │
│  │        ╱    │    ╲                                                │  │
│  │   Bold ●   │    ● Story                                          │  │
│  │   Claim    │      Loop                                           │  │
│  │        ╲   │    ╱                                                │  │
│  │     Social ● Proof                                               │  │
│  │            │                                                      │  │
│  │        Contrast ●                                                 │  │
│  │                                                                   │  │
│  │  Node size = # of swipes using technique                          │  │
│  │  Edge thickness = frequency of co-occurrence                      │  │
│  │  Hover to see technique breakdown                                 │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

#### Intelligence Features

**1. Technique Mastery Tracking**
- Tracks which techniques the user has studied via swipe files
- Mastery is based on: number of swipes studied, notes written, techniques applied in own content, and practice exercises completed
- Progress bars show mastery percentage per technique
- Gap analysis highlights underrepresented techniques

**2. Pattern Insights (Auto-Generated)**
- AI analyzes the entire collection weekly (background, on-device)
- Generates natural-language insights about patterns
- Example categories:
  - **Length patterns**: Hook word counts, paragraph lengths, total content lengths
  - **Technique clusters**: Which techniques co-occur most frequently
  - **Score correlations**: What factors predict higher hook scores
  - **Trending patterns**: New techniques appearing in recent captures
  - **Cross-domain opportunities**: Techniques that work in one platform adapted to another

**3. Technique Constellation**
- Knowledge graph visualization showing technique relationships
- Uses existing `KnowledgePulseLineView` rendering engine
- Nodes = techniques, sized by frequency
- Edges = co-occurrence frequency (how often two techniques appear together)
- Clusters emerge naturally (e.g., "urgency techniques" cluster together)

**4. Collection Health Score**
- Aggregated metrics: total swipes, study rate, note coverage, platform diversity
- Gamified with XP system (contributes to Creative dimension in Sanctuary)
- Weekly goals: "Study 5 new swipes" / "Write notes on 3 swipes" / "Practice 1 teardown"

---

### PILLAR 5: THE PRACTICE ENGINE

*The Gary Halbert method, digitized and personalized.*

#### Concept

The Practice Engine transforms passive collection into active skill development. It implements three practice modalities inspired by the masters of copywriting education.

#### Practice Modality 1: Guided Teardown

```
┌──────────────────────────────────────────────────────────────────────┐
│  PRACTICE SESSION: Guided Teardown                    3 of 5 today  │
│─────────────────────────────────────────────────────────────────────│
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                                                                │  │
│  │  "Nobody wants to read your Twitter thread. Here's why they   │  │
│  │   will anyway."                                                │  │
│  │                                                                │  │
│  │   — @SahilBloom · X/Twitter · 847K impressions                │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  QUESTION 1 of 4                                              │    │
│  │                                                               │    │
│  │  What hook type is this?                                      │    │
│  │                                                               │    │
│  │  ○ Curiosity Gap                                              │    │
│  │  ○ Bold Claim                                                 │    │
│  │  ● Contrarian + Curiosity Gap                                 │    │
│  │  ○ Question                                                   │    │
│  │                                                               │    │
│  │                                          [Check Answer →]     │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  Progress: ██████████░░░░░░░░░░ 50%    Streak: 🔥 7 days           │
└──────────────────────────────────────────────────────────────────────┘
```

The AI generates multiple-choice and open-ended questions about randomly selected swipes:
- "What hook type is this?"
- "Which emotional trigger is dominant?"
- "What framework does this follow?"
- "How would you adapt this hook for [user's current project]?"

Uses spaced repetition: swipes the user gets wrong come back more often.

#### Practice Modality 2: Adaptation Workshop

```
┌──────────────────────────────────────────────────────────────────────┐
│  PRACTICE SESSION: Adapt This Hook                                   │
│─────────────────────────────────────────────────────────────────────│
│                                                                      │
│  ORIGINAL (MrBeast · YouTube):                                       │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  "I Spent $1 vs $1,000,000 on a Vacation"                     │  │
│  │   Technique: Contrast Gap · Framework: Escalation Arc          │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  YOUR CURRENT PROJECT: "10 Lessons From Building in Public"          │
│  Platform: Twitter/X Thread                                          │
│                                                                      │
│  Adapt the Contrast Gap technique for YOUR content:                  │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                                                                │  │
│  │  "I built in public with 0 followers vs 100K followers.       │  │
│  │   Here's what actually changed."                               │  │
│  │                                                                │  │
│  │                                                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │  AI FEEDBACK                                                │     │
│  │                                                             │     │
│  │  ✓ Strong contrast between extremes (0 vs 100K)            │     │
│  │  ✓ "Actually" adds curiosity — implies counter-intuitive   │     │
│  │  △ Consider: the contrast could be sharper. MrBeast uses   │     │
│  │    a 1,000,000x difference. Try a more extreme range.      │     │
│  │  → Try: "Building in public for 1 day vs 1,000 days..."    │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  [Save as Hook Draft]    [Try Another]    [Use in Content →]         │
└──────────────────────────────────────────────────────────────────────┘
```

- Selects a swipe from the user's collection
- Shows the original content + its classified technique
- Asks the user to adapt the technique for their current project
- AI provides feedback on the adaptation
- "Use in Content →" directly applies the adapted hook to the active content piece

#### Practice Modality 3: Pattern Recognition Drill

```
┌──────────────────────────────────────────────────────────────────────┐
│  PATTERN DRILL: Spot the Technique                                   │
│─────────────────────────────────────────────────────────────────────│
│                                                                      │
│  Which of these hooks uses the SAME technique?                       │
│                                                                      │
│  ┌──────────────────────────────────┐ ┌────────────────────────────┐│
│  │ A                                │ │ B                          ││
│  │ "I asked 100 millionaires their  │ │ "Stop using Notion. Here's ││
│  │  #1 money habit"                 │ │  what I switched to."      ││
│  │                                  │ │                            ││
│  │               ○                  │ │              ○             ││
│  └──────────────────────────────────┘ └────────────────────────────┘│
│                                                                      │
│  ┌──────────────────────────────────┐ ┌────────────────────────────┐│
│  │ C                                │ │ D                          ││
│  │ "The morning routine that saved  │ │ "Nobody talks about this   ││
│  │  my startup"                     │ │  $0 marketing strategy"    ││
│  │                                  │ │                            ││
│  │               ○                  │ │              ●             ││
│  └──────────────────────────────────┘ └────────────────────────────┘│
│                                                                      │
│  Reference hook:                                                     │
│  "Everyone is sleeping on this free AI tool"                         │
│  Technique: Hidden Gem + Urgency                                     │
│                                                                      │
│  [Submit →]                                                          │
└──────────────────────────────────────────────────────────────────────┘
```

- Shows 4 hooks from the user's collection
- Asks which one uses the same technique as a reference hook
- Trains pattern recognition across formats and platforms
- Difficulty scales with mastery level

#### XP & Progression

| Practice Action | XP Earned |
|----------------|-----------|
| Complete a Guided Teardown | 15 XP |
| Write an Adaptation | 25 XP |
| Pass a Pattern Drill | 10 XP |
| Study a swipe (read teardown) | 5 XP |
| Write notes on a swipe | 10 XP |
| Apply a swipe technique in content | 30 XP |
| Maintain daily streak | 5 XP bonus |

All XP contributes to the **Creative** dimension in Sanctuary, feeding into the existing level system with badges:

| Badge | Requirement |
|-------|-------------|
| First Swipe | Save your first swipe file |
| Collection Started | 25 swipes |
| Swipe Scholar | Study 50 teardowns |
| Pattern Spotter | Pass 25 pattern drills |
| Adaptation Artist | Write 25 adaptations |
| Technique Master: [X] | 90%+ mastery in any technique |
| Cross-Pollinator | Apply technique from one platform on another |
| The Halbert | 30-day study streak |

---

## IV. DATA MODEL EXTENSIONS

### New Structured Data: SwipeAnalysis

Stored in the Research atom's `structured` JSON field alongside existing `ResearchRichContent`:

```swift
struct SwipeAnalysis: Codable {
    // Hook Analysis
    var hookText: String?                    // Extracted hook
    var hookType: SwipeHookType?             // Classified type
    var hookScore: Double?                   // 0.0-10.0
    var hookWordCount: Int?

    // Structure Analysis
    var frameworkType: SwipeFrameworkType?    // AIDA, PAS, etc.
    var sections: [SwipeSection]?            // Labeled content sections
    var structureComplexity: Double?         // 0.0-1.0

    // Emotional Analysis
    var dominantEmotion: SwipeEmotion?       // Primary emotion
    var emotionalArc: [EmotionDataPoint]?    // Time-series emotion data
    var sentimentScore: Double?              // -1.0 to 1.0

    // Persuasion Analysis
    var persuasionTechniques: [PersuasionTechnique]? // Identified techniques
    var persuasionStack: [String: Double]?   // Technique → intensity

    // Meta
    var analysisVersion: Int                 // For re-analysis on model updates
    var analyzedAt: String?                  // ISO8601
    var isFullyAnalyzed: Bool               // All stages complete

    // Practice State
    var studiedAt: String?                   // When user studied this
    var practiceAttempts: Int?               // Times used in practice
    var userHookScore: Double?              // User's manual scoring
}

enum SwipeHookType: String, Codable {
    case curiosityGap, boldClaim, question, story, statistic
    case controversy, contrast, howTo, list, challenge
    case hiddenGem, contrarian, personal, transformation
}

enum SwipeFrameworkType: String, Codable {
    case aida, pas, bab, escalationArc, storyLoop
    case listicle, tutorial, caseStudy, interview
    case beforeAfter, mythBusting, dayInLife
}

enum SwipeEmotion: String, Codable {
    case curiosity, urgency, aspiration, fear, desire
    case awe, frustration, relief, belonging, exclusivity
}

struct SwipeSection: Codable {
    var label: String           // "Hook", "Escalation", "Payoff", etc.
    var startIndex: Int         // Character/segment start
    var endIndex: Int           // Character/segment end
    var purpose: String         // Brief description
    var emotion: SwipeEmotion?  // Dominant emotion in section
}

struct EmotionDataPoint: Codable {
    var position: Double        // 0.0-1.0 (normalized position)
    var intensity: Double       // 0.0-1.0
    var emotion: SwipeEmotion
}

struct PersuasionTechnique: Codable {
    var type: PersuasionType
    var intensity: Double       // 0.0-1.0
    var textRanges: [TextRange]? // Where it appears
}

enum PersuasionType: String, Codable {
    case socialProof, curiosityGap, contrastEffect, authority
    case scarcity, urgency, reciprocity, storytelling
    case lossAversion, exclusivity, anchoring, framing
}
```

### New Graph Edge Types

```swift
// In AtomLinkType (extend existing enum)
case techniqueMatch     // Same hook type
case structuralSibling  // Same framework
case hookPattern        // Similar hook pattern
case emotionalArc       // Similar emotional trajectory
case swipeReference     // Swipe referenced during content creation
```

### New Graph Edge Weights for Swipe Relationships

| Edge Type | Base Weight | Coefficient |
|-----------|-------------|-------------|
| techniqueMatch | 0.7 | Boosted by hook score similarity |
| structuralSibling | 0.6 | Boosted by section count similarity |
| hookPattern | 0.8 | Highest — direct creative inspiration |
| emotionalArc | 0.5 | Based on arc correlation score |
| swipeReference | 0.9 | User explicitly referenced during writing |

---

## V. APPLE SILICON OPTIMIZATION

### Neural Engine Pipeline

| Stage | Framework | Hardware | Latency |
|-------|-----------|----------|---------|
| Text tokenization | NaturalLanguage | CPU | < 5ms |
| Sentiment per sentence | NaturalLanguage | Neural Engine | < 10ms |
| Entity recognition | NaturalLanguage | Neural Engine | < 15ms |
| Word embeddings (768d) | NaturalLanguage | Neural Engine | < 10ms |
| Screenshot OCR | Vision (VNRecognizeTextRequest) | Neural Engine | < 200ms |
| Hook type classification | Core ML (custom) | Neural Engine | < 20ms |
| Framework detection | Core ML (custom) | Neural Engine | < 20ms |
| Persuasion multi-label | Core ML (custom) | Neural Engine | < 25ms |
| Vector similarity search | Accelerate (vDSP) | GPU (Metal) | < 5ms |
| Emotional arc rendering | Metal 4 | GPU | 120fps |
| Technique constellation | Metal 4 | GPU | 120fps |

**Total on-device analysis time: < 300ms** for the full pipeline (stages 1-3).

### Metal 4 Rendering

The Technique Constellation, Emotional Arc charts, and Knowledge Pulse Lines between swipe atoms all leverage Metal 4 for:
- 120Hz ProMotion-aware rendering via `TimelineView(.animation)`
- Anti-aliased bezier curves with glow effects
- GPU-accelerated gradient fills for emotional arc visualization
- Particle effects for XP gain animations

### Unified Memory Architecture

Apple Silicon's unified memory means:
- No data copying between CPU/GPU/Neural Engine for analysis pipeline
- Entire swipe collection (10,000+ atoms) can be analyzed in a single pass
- Vector database stays in memory for instant retrieval
- Large language model inference runs alongside UI rendering without frame drops

### Background Processing

When the Mac is idle or charging:
- **Re-analysis**: Re-run analysis pipeline on older swipes when models are updated
- **Pattern mining**: Batch compute collection-wide patterns and insights
- **Embedding updates**: Regenerate embeddings when new, better models become available
- **Graph maintenance**: Recompute technique/structural edges with updated weights

Uses `BGTaskScheduler` for energy-efficient background processing with Apple Silicon power management.

---

## VI. ENHANCED CAPTURE FLOW

### Current State: Cmd+Shift+S → SwipeFileEngine

The existing capture flow is functional but minimal. SwipeOS enhances it:

### Enhanced Capture Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  User copies URL / selects text / takes screenshot               │
│                          │                                       │
│                          ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Cmd+Shift+S  (or "Hey Cosmo, swipe this")              │   │
│  └──────────────────────────────────┬───────────────────────┘   │
│                                     │                            │
│                                     ▼                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  QUICK CAPTURE TOAST (bottom-right, 320x180)             │   │
│  │                                                          │   │
│  │  ⚡ Swiped!                                              │   │
│  │                                                          │   │
│  │  "I Spent $1 vs $1,000,000..."                          │   │
│  │  MrBeast · YouTube                                       │   │
│  │                                                          │   │
│  │  Hook: [auto-filled, editable]                           │   │
│  │  ┌──────────────────────────────────────────┐            │   │
│  │  │ I Spent $1 vs $1,000,000 on a Vacation  │            │   │
│  │  └──────────────────────────────────────────┘            │   │
│  │                                                          │   │
│  │  Why it caught you: [optional note]                      │   │
│  │  ┌──────────────────────────────────────────┐            │   │
│  │  │                                          │            │   │
│  │  └──────────────────────────────────────────┘            │   │
│  │                                                          │   │
│  │  [Save ⌘↩]           [Save & Study →]                   │   │
│  │                                                          │   │
│  │  ● Analyzing...  ██████░░░░ 60%                         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Analysis runs in background. Atom created immediately.          │
│  Toast auto-dismisses after 5s if no interaction.                │
│  "Save & Study →" opens Swipe Study Mode for deep teardown.     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Key Improvements over Current Flow**:
1. **Instant creation**: Atom created immediately, analysis runs async
2. **Auto-filled hook**: AI extracts hook from title/opening line automatically
3. **"Why it caught you" prompt**: Encourages the annotation habit at capture time
4. **Progress indicator**: Shows analysis pipeline progress in real-time
5. **"Save & Study"**: One-tap path to deep teardown for high-value swipes
6. **Voice capture**: "Hey Cosmo, swipe this" — captures clipboard + records spoken hook annotation
7. **Toast auto-dismiss**: Doesn't block workflow if user wants quick capture

---

## VII. COMMAND-K INTEGRATION

### Technique-Aware Search

Command-K gains new search capabilities when the user is working with swipe files:

**Natural Language Technique Queries**:
- "urgency hooks" → finds swipes classified with urgency/scarcity techniques
- "storytelling openers for YouTube" → filters by technique + platform
- "high-scoring contrast examples" → filters by technique + sorts by hook score
- "PAS framework emails" → finds swipes with PAS structure from email sources
- "hooks like MrBeast" → finds swipes from or similar to MrBeast's style

**Implementation**: Extends `CommandKViewModel` with swipe-specific intent detection. When query contains technique keywords, it routes through `SwipeAnalysis` metadata filters before falling back to general semantic search.

---

## VIII. DESIGN SPECIFICATIONS

### Color System

| Element | Color | Hex |
|---------|-------|-----|
| Swipe accent (primary) | Gold | #FFD700 |
| Swipe accent (secondary) | Warm amber | #F59E0B |
| Hook score high (8+) | Emerald | #10B981 |
| Hook score medium (5-7) | Blue | #3B82F6 |
| Hook score low (<5) | Slate | #64748B |
| Teardown panel background | Deep void | #0D0D14 |
| Technique badge background | White 8% | rgba(255,255,255,0.08) |
| Emotional arc line | Gradient (emotion-dependent) | varies |
| Practice correct | Green | #22C55E |
| Practice incorrect | Soft red | #EF4444 |
| Streak fire | Orange-red gradient | #FF6B35 → #FF4444 |

### Typography

| Element | Spec |
|---------|------|
| Hook text (Study Mode) | 20pt, semibold, tracking -0.3 |
| Teardown section headers | 13pt, bold, all-caps, tracking 1.2 |
| Technique badges | 11pt, medium |
| Hook score number | 18pt, bold, monospaced |
| Pattern insight text | 15pt, regular |
| Practice question | 17pt, medium |
| Practice option | 15pt, regular |

### Animation

| Interaction | Animation |
|------------|-----------|
| Capture toast appear | Spring, response 0.3, damping 0.8, from bottom |
| Analysis progress | Linear fill with shimmer overlay |
| Hook score reveal | Scale from 0 + number count-up (0.6s) |
| Emotional arc draw | Stroke from left to right (1.2s, ease-in-out) |
| Technique badge appear | Staggered spring, 50ms delay per badge |
| Practice answer reveal | Flip transition (correct = green glow, wrong = subtle shake) |
| XP gain | Float-up with fade + particle burst |
| Streak counter | Fire particle effect on increment |
| Gallery filter | Matched geometry + fade for reorganization |
| Reference Rail update | Crossfade with 300ms duration |

---

## IX. TECHNICAL IMPLEMENTATION PLAN

### Phase 1: Foundation (Core Data & Analysis)
- Extend `Atom.swift` with `SwipeAnalysis` structured data model
- Create `SwipeAnalyzer.swift` — on-device analysis pipeline using NaturalLanguage framework
- Create `SwipeHookClassifier.mlmodel` — Core ML model for hook type classification
- Extend `GraphQueryEngine` with technique-based edge queries
- Extend `NodeGraphEngine` to create technique/structural edges on swipe analysis
- Add new `AtomLinkType` cases for swipe relationships

### Phase 2: Swipe Study Mode
- Create `SwipeStudyFocusModeView.swift` — the teardown workspace
- Create `TeardownPanelView.swift` — hook analysis, structure map, emotional arc, persuasion stack
- Create `EmotionalArcView.swift` — Metal-rendered sentiment timeline
- Create `StructureMapView.swift` — visual section diagram
- Create `PersuasionStackView.swift` — technique bar chart
- Integrate with existing `ResearchFocusModeView` (toggle between research and study modes)

### Phase 3: Gallery & Canvas Integration
- Create `SwipeGalleryView.swift` — filterable gallery layout
- Extend `CanvasBlock` with swipe-specific block design (gold accent, technique badges, mini-arc)
- Add Swipe Gallery toggle to canvas toolbar
- Extend `CommandKViewModel` with technique-aware search

### Phase 4: Write With Swipes
- Create `ReferenceRailView.swift` — contextual swipe sidebar for Content Focus Mode
- Create `SwipeReferenceEngine.swift` — real-time semantic matching during writing
- Extend `ContentDraftView` with Reference Rail integration
- Add `/swipe` inline command to editor

### Phase 5: Intelligence & Practice
- Create `SwipeIntelligenceEngine.swift` — collection-wide pattern mining
- Extend Sanctuary with Creative dimension dashboard
- Create `PracticeEngineView.swift` — guided teardown, adaptation, pattern drill UIs
- Create `SwipePracticeSession.swift` — session management with spaced repetition
- Extend XP system with swipe-related actions and badges
- Add "Study Block" to Plannerum schedule types

### Phase 6: Enhanced Capture
- Redesign capture toast with hook auto-fill and "Why it caught you" prompt
- Add voice capture: "Hey Cosmo, swipe this"
- Add Share Sheet extension for system-wide capture
- Add screenshot-based capture with Vision OCR

---

## X. SUCCESS METRICS

| Metric | Target | Measurement |
|--------|--------|-------------|
| Swipes captured per week | 10+ after onboarding | AtomRepository count by type |
| Swipes studied (teardown opened) | 60%+ of captures | studiedAt field population |
| Notes written per swipe | 40%+ have notes | personalNotes field population |
| Practice sessions per week | 3+ | Practice session atoms |
| Swipe referenced during writing | 25%+ of content pieces | swipeReference edge count |
| Time from capture to full analysis | < 3 seconds | Performance telemetry |
| Search latency (technique queries) | < 100ms | Query timing |
| User retention improvement | +20% weekly retention | Analytics |

---

## XI. WHY THIS HAS NEVER EXISTED

1. **No tool connects swipe files to content creation.** SwipeOS makes the swipe file a living part of the writing workflow through the Reference Rail.

2. **No tool analyzes content on-device.** Every competitor uses cloud APIs. SwipeOS runs the full analysis pipeline on Apple Silicon's Neural Engine in < 300ms, privately, offline, with zero API costs.

3. **No tool teaches you.** Swipe file tools are passive storage. SwipeOS's Practice Engine with spaced repetition, guided teardowns, and adaptation workshops actively builds creative skill.

4. **No tool reveals collection-wide patterns.** SwipeOS's Intelligence Engine surfaces meta-patterns across hundreds of swipes that no human could spot manually.

5. **No tool uses a knowledge graph for swipe files.** CosmoOS's existing graph infrastructure enables semantic connections between swipes, content, ideas, and connections — creating a living web of creative intelligence.

6. **No tool integrates swipe files into a full second-brain system.** CosmoOS already handles ideas, tasks, research, connections, content, journaling, scheduling, and AI. SwipeOS makes the swipe file a first-class citizen in this ecosystem rather than a siloed feature.

7. **No tool leverages 120Hz ProMotion rendering for swipe file visualization.** The emotional arc charts, technique constellations, and knowledge pulse lines render at native 120fps with Metal 4.

This is not a feature. This is a new category of creative tool — and it can only exist inside CosmoOS.

---

*SwipeOS: Your collection doesn't just grow. Your ability grows with it.*
