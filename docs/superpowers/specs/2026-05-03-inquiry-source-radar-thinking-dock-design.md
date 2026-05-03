# Inquiry Source Radar and Thinking Dock Design

Date: 2026-05-03
Status: Approved direction, awaiting written-spec review
Primary surface: `UI/FocusMode/Inquiry`

## Goal

Turn the Inquiry Workspace into a branch-aware research and learning cockpit where every question can recommend the best next sources, every user thought can be captured through one input, and every note, source, highlight, claim, and branch has visible routing and provenance.

The first implementation slice is intentionally focused:

- A branch-specific Source Radar in the source pane.
- A single Thinking Dock that replaces the split "note editor vs. copilot prompt" mental model.
- A source recommendation model and ranker that can combine local library matches with external academic providers.
- A premium macOS UI pass that makes the current workspace feel calmer, more direct, and more satisfying without rebuilding the entire app.

## Current System Context

The codebase already contains most of the primitives this design needs:

- `Data/Models/InquiryWorkspaceModels.swift` defines Deep Dive, Inquiry Session, Question, Extract, source refs, routing cards, source tabs, source tasks, research tree nodes, and current understanding models.
- `UI/FocusMode/Inquiry/InquiryWorkspaceViewModel.swift` owns active branch context, source refs, source tabs, notes, extracts, operational tasks, routing cards, and AI interactions.
- `UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift` already opens URL sources, attaches sources to questions, saves highlights as extracts, and proposes branches from selections.
- `UI/FocusMode/Inquiry/Panes/InquiryNotebookPane.swift` currently contains the main note editor.
- `UI/FocusMode/Inquiry/Panes/InquiryCopilotPane.swift` currently contains the AI thread, routing cards, active question inspector, answer forming panel, map forming panel, and copilot input.
- `AI/InquiryPlacementEngine.swift` and `AI/InquiryThoughtRouter.swift` already separate conceptual branches from source search tasks, evidence audits, claims, mechanisms, assumptions, terms, and source-quality warnings.
- `Cosmo/ResearchService.swift`, `Agent/Services/GeminiGroundedSearch.swift`, `Cosmo/SemanticSearchEngine.swift`, `Cosmo/HybridSearchEngine.swift`, `Cosmo/YouTubeProcessor.swift`, `SwipeFile/YouTubeTranscriptFetcher.swift`, and `Data/Services/ReadwiseService.swift` provide useful search, AI, transcript, and library infrastructure.

The design should extend these primitives rather than creating a parallel research system.

## Product Principles

1. One thinking surface.
   The user should not have to decide whether a thought belongs in "notes" or "chat." They type into one dock. Cosmo routes the thought and shows what happened.

2. Branches are first-class research contexts.
   The root question gets recommendations, and each deeper branch gets its own recommendations using the branch title, ancestor questions, claims, gaps, notes, and existing sources.

3. Source results must explain why they are useful.
   A source card is not a search result. It should explain its role: foundational, current, counterevidence, mechanism, practice, local library match, video explainer, or weak-source warning.

4. Provenance is always visible.
   Every note, highlight, imported source, source recommendation, AI reply, and route decision should show its session, question, source, and route destination.

5. The UI should feel like a native macOS product.
   The workspace should use restrained surfaces, native density, strong typography hierarchy, crisp hover states, semantic icons, keyboard paths, and calm motion. It should not look like a generic analytics dashboard.

## User Experience

### Moment

The user arrives with a messy question and leaves with a living research map: what to read next, why it matters, what it supports, what it challenges, and how their understanding changed.

### Primary Layout

```text
+-----------------------------------------------------------------------------+
| Breathwork > Body Effects        Research  Read  Write  Map  Review   *     |
+---------------+-------------------------------------------+-----------------+
| BRANCH RAIL   | SOURCE RADAR / READER                     | INQUIRY THREAD  |
|               |                                           |                 |
| o Root Q      |  Top Sources for this branch              | Route preview   |
|  |- child Q   |  [ Paper ] [ Review ] [ Video ] [ Local ] | Claim / Branch  |
|  |- child Q   |  score    why it helps  evidence role     | / Source task   |
|  `- child Q   |                                           |                 |
|               |  Lanes: Foundational / Current /          | Answer forming  |
| gap badges    |  Counterevidence / Practical / Your lib   | Map forming     |
| confidence    |                                           | Recent actions  |
+---------------+-------------------------------------------+-----------------+
| Thinking Dock: "type anything..."  route chips  @branch  source:  claim: up |
+-----------------------------------------------------------------------------+
```

The exact pane proportions remain mode-dependent, but the mental model changes:

- Left: branch and current understanding context.
- Center: source discovery and reading.
- Right: route previews, answer forming, map forming, and activity.
- Bottom: the single place to think out loud.

### Research Mode

Research mode prioritizes the Source Radar.

- The source pane shows recommendations before any URL is opened.
- The first row is "Top Sources for this branch."
- Cards are grouped into lanes:
  - Foundational
  - Recent
  - Review or meta-analysis
  - Counterevidence
  - Mechanism
  - Practical or instructional
  - Your Library
  - Video
- Each card has actions:
  - Open
  - Import
  - Queue
  - Attach to active question
  - Find similar
  - Find contradiction
  - Dismiss

### Read Mode

Read mode prioritizes the active source.

- The source reader becomes wider.
- The Thinking Dock remains visible at the bottom.
- Highlights show a compact floating route menu:
  - Save
  - Ask
  - Deepen
  - Evidence
  - Counter
  - Term
- The route preview explains where the highlight will land before commit when confidence is medium or low.

### Write Mode

Write mode prioritizes current understanding.

- The old large note editor is replaced by the Thinking Dock plus current-understanding panels.
- The user can type normally, use prefixes, or dictate.
- Route receipts show "Saved as note under X", "Suggested child branch Y", "Created source task", or "Added evidence to Answer Forming."

### Map Mode

Map mode makes branch structure and evidence gaps visible.

- Branch nodes show source counts, evidence counts, open tasks, and recommended-source freshness.
- Source search and evidence audit tasks stay visually attached to questions but do not become branch nodes unless promoted.

### Review Mode

Review mode becomes a crystallization diff.

- What changed in current understanding.
- What evidence supports the change.
- What contradicts it.
- Which branches remain open.
- Which sources were strong, weak, or unused.
- What to research next.

## Thinking Dock

### Behavior

The Thinking Dock is the only primary input for inquiry thinking.

It accepts:

- Natural language notes.
- Questions.
- URLs.
- Source search requests.
- Claims and speculative claims.
- Evidence and counterevidence.
- Terms.
- Practice notes.
- Output ideas.
- Commands and prefixes.

The dock should route with a two-level confidence model:

- High confidence: commit immediately and show a route receipt with undo.
- Medium or low confidence: show a route preview card before committing.

### Manual Prefixes

The dock supports explicit routing prefixes:

- `q:` creates or proposes a question.
- `root:` creates or proposes a root question.
- `branch:` creates or proposes a child branch under the active question.
- `note:` saves a plain note.
- `claim:` saves a claim.
- `maybe:` saves a speculative claim.
- `evidence:` saves evidence.
- `counter:` saves counterevidence.
- `source:` creates a source search task or opens a URL if a URL is present.
- `term:` saves a lexicon term.
- `practice:` saves a practice note.
- `output:` saves an output idea.
- `@branch name` routes to a named branch when matched.
- `/challenge` creates or runs an evidence challenge.
- `/summarize` summarizes the active source.
- `/sources` refreshes Source Radar for the active branch.

The prefix system is an override, not a requirement.

### Route Receipt

After commit, the dock shows a compact receipt:

```text
Saved as speculative claim - Breathwork > Body Effects
Also suggested: Evidence audit - Find stronger sources
Undo
```

Receipts should be short, calm, and actionable. They should not read like logs.

## Source Radar

### Candidate Model

Add a normalized candidate model that can represent a paper, article, video, book, local note, local research atom, or web result.

Required fields:

- `id`
- `provider`
- `sourceKind`
- `title`
- `subtitle`
- `authors`
- `publishedDate`
- `year`
- `url`
- `doi`
- `pmid`
- `pmcid`
- `arxivId`
- `semanticScholarId`
- `openAlexId`
- `abstract`
- `snippet`
- `venue`
- `publisher`
- `thumbnailURL`
- `isOpenAccess`
- `pdfURL`
- `citationCount`
- `influentialCitationCount`
- `retractionStatus`
- `sourceQualitySignals`
- `evidenceRole`
- `relevanceScore`
- `qualityScore`
- `noveltyScore`
- `diversityScore`
- `contradictionPotential`
- `localLibraryScore`
- `finalScore`
- `whyThisHelps`
- `limitations`
- `matchedQuestionUUID`
- `matchedBranchNodeId`
- `existingAtomUUID`
- `importStatus`

### Evidence Roles

The ranker assigns one primary role and optional secondary roles:

- foundational
- recent
- review
- metaAnalysis
- randomizedTrial
- mechanism
- counterevidence
- sourceQuality
- practicalGuide
- videoExplainer
- localLibrary
- webContext

### Recommendation Batch

Each active branch can have a recommendation batch:

- `id`
- `questionUUID`
- `branchNodeId`
- `query`
- `generatedAt`
- `providerStatuses`
- `candidates`
- `acceptedCandidateIds`
- `dismissedCandidateIds`
- `queuedCandidateIds`

Store batches inside `InquirySessionStructured` first. Promote durable imported candidates to `.research` atoms and `InquirySourceRef`s.

### Ranking Formula

V1 scoring:

```text
finalScore =
  0.34 * relevanceScore +
  0.22 * qualityScore +
  0.14 * diversityScore +
  0.12 * noveltyScore +
  0.10 * localLibraryScore +
  0.08 * contradictionPotential
```

Quality signals:

- Peer-reviewed journal or reputable venue.
- Review or meta-analysis when the branch asks for synthesis.
- DOI, PMID, PMCID, or arXiv identifier present.
- Citation count and influential citation count when available.
- Open access or PDF availability.
- Explicit caution for retraction, editorial, preprint-only, non-peer-reviewed, and low-evidence sources.

Relevance signals:

- Title and abstract match active question.
- Match ancestor questions.
- Match claims and evidence gaps.
- Match missing evidence roles for the branch.
- Avoid duplicate titles and already-imported sources unless the source is a canonical match.

### Empty, Loading, Error States

Empty:

```text
No recommendations yet.
Search this branch, paste a URL, or type /sources.
```

Loading:

- Skeleton source cards, not a spinner.
- Provider chips show local, OpenAlex, Crossref, Semantic Scholar, PubMed, arXiv, YouTube, web.

Error:

- Provider-specific errors remain local to a lane or chip.
- One failed provider does not block the whole radar.
- Missing API keys show setup actions in Settings.

## Provider Strategy

Use structured scholarly APIs before generic web search.

### V1 Providers

1. Local library provider.
   Searches `.research`, extracts, Readwise books/highlights, source refs, and existing source tabs using `HybridSearchEngine` and `SemanticSearchEngine`.

2. OpenAlex provider.
   Primary academic discovery source for works, authors, venues, institutions, topics, and open-access metadata. API keys are free. Official docs: https://developers.openalex.org/api-reference/introduction

3. Crossref provider.
   DOI and journal metadata normalization, publication metadata, funders, licenses, abstracts where available, and post-publication update metadata. Official docs: https://www.crossref.org/documentation/retrieve-metadata/rest-api/

4. Semantic Scholar provider.
   Paper metadata, citation graph, influential citation counts, similar paper recommendations, and embeddings when available. Official docs: https://www.semanticscholar.org/product/api?hsLang=en

### V1.5 Providers

5. PubMed or NCBI E-utilities provider.
   Use for biomedical, physiology, psychology, and clinical branches. Official docs: https://www.ncbi.nlm.nih.gov/home/develop/api/

6. arXiv provider.
   Use for preprints and technical fields. Official docs: https://info.arxiv.org/help/api/basics.html

7. YouTube provider.
   Search video metadata, then use existing transcript processing when possible. Official docs: https://developers.google.cn/youtube/v3/docs/search/list?hl=en

8. Brave or Exa web provider.
   Use for broad web discovery, current events, and high-quality non-academic context. Official docs: https://brave.com/search/api/ and https://exa.ai/docs/reference/search

### API Key Handling

Use the existing Keychain-backed `APIKeys` pattern and Settings UI style.

Add keys only when a provider requires them:

- OpenAlex API key.
- Semantic Scholar API key if rate limits require it.
- YouTube API key.
- Brave or Exa API key.

Crossref, PubMed, and arXiv should start without required keys where their terms allow, while still honoring polite usage, mailto/tool parameters, and backoff headers where appropriate.

## Data Flow

### Refresh Recommendations

1. User selects a question branch or types `/sources`.
2. `InquiryWorkspaceViewModel` builds a `BranchResearchProfile`.
3. `InquirySourceRecommendationEngine` checks cached recommendation batch freshness.
4. Local provider runs first and returns immediate matches.
5. External providers run concurrently with cancellation tied to the active branch.
6. `SourceCandidateNormalizer` dedupes by DOI, PMID, arXiv ID, OpenAlex ID, Semantic Scholar ID, normalized URL, and normalized title.
7. `SourceCandidateRanker` scores and assigns lanes.
8. Source Radar renders ranked lanes.
9. User imports, opens, queues, dismisses, or asks for similar/contradicting sources.
10. Imported candidates become `.research` atoms and `InquirySourceRef`s attached to the active question.

### Dock Commit

1. User submits text in the Thinking Dock.
2. Prefix parser extracts explicit route override if present.
3. Existing `InquiryPlacementEngine` classifies natural language content.
4. High-confidence route commits immediately.
5. Medium or low confidence creates a route preview in the right pane.
6. Commit creates notes, extracts, operational tasks, source refs, source tabs, or questions using existing repository methods where possible.
7. Route receipt appears with undo.

### Highlight Commit

1. User highlights in Web, internal source, PDF, or transcript viewer.
2. Mini menu offers Save, Ask, Deepen, Evidence, Counter, Term.
3. The selected route creates an extract with source, question, branch, source tab, citation, and selection metadata.
4. If the highlight looks like a claim or evidence gap, route preview suggests a branch, evidence audit, or source search task.

## UI Components

Create focused SwiftUI components instead of growing existing panes:

- `InquiryThinkingDock`
- `InquiryRouteReceiptView`
- `InquiryRoutePreviewCard`
- `InquirySourceRadarView`
- `InquirySourceLaneView`
- `InquirySourceCandidateCard`
- `InquiryProviderStatusStrip`
- `InquiryBranchRailView`
- `InquirySourceQualityBadge`
- `InquiryEvidenceRolePill`

Existing panes should become composition roots:

- `InquiryWorkspaceView` owns top-level layout and bottom dock placement.
- `InquiryNotebookPane` loses the large primary note editor and becomes branch/current-understanding context.
- `InquirySourcePane` hosts Source Radar and source reader states.
- `InquiryCopilotPane` hosts route previews, answer forming, map forming, and activity.

## Native macOS Design Direction

The visual treatment should follow CosmoOS Greenhouse and native macOS patterns:

- Use `DS.*`, `CosmoColors`, and existing typography.
- Use semantic icons and compact icon buttons.
- Keep cards at small radii.
- Avoid nested cards.
- Avoid decorative gradients, blobs, and marketing-style panels.
- Prefer system density, light borders, and sparse shadows.
- Use skeleton cards for loading.
- Use `foregroundStyle()` and `clipShape(.rect(cornerRadius:))`.
- Use `@Observable` for new reference state.
- Use small view files with explicit inputs.
- Keep route and source actions keyboard reachable.

### Motion

- Route receipt enters with a short fade and 0.98 -> 1.0 scale spring.
- Source cards appear with subtle stagger, max four visible staggered cards.
- Provider chips pulse only while actively loading.
- Branch changes crossfade and preserve scroll position per branch when possible.
- Respect reduce motion.

## Accessibility and Keyboard

Keyboard:

- `Cmd+1...5` keeps existing layout mode switching.
- `Cmd+L` focuses the Thinking Dock.
- `Cmd+R` refreshes Source Radar for the active branch.
- `Cmd+Option+S` opens source search filters.
- `Cmd+Shift+B` creates a branch from the current dock text or selection.
- `Cmd+Z` undoes the last dock route receipt when available.

Accessibility:

- All icon-only buttons need labels.
- Source cards should combine title, type, evidence role, score, and action state.
- Loading skeletons should not spam VoiceOver.
- Route receipts should announce the committed destination.
- The dock should expose current route context.

## Error Handling

- Missing API keys show provider-specific setup prompts, not global failure.
- Rate limits mark a provider chip as limited and keep other providers active.
- Provider timeouts return partial results.
- Bad source metadata still produces a candidate if title and URL are usable.
- Import failures leave the candidate visible with retry.
- Deduped candidates show "already in library" and open the existing atom.
- If active branch changes mid-request, stale results are discarded.

## Testing Strategy

Unit tests:

- Prefix parsing routes each supported prefix correctly.
- Natural language routing still creates notes, claims, source tasks, and branch previews through `InquiryPlacementEngine`.
- Candidate normalization dedupes DOI, PMID, arXiv ID, URL, and normalized titles.
- Ranker prioritizes relevance, quality, and role diversity.
- Provider errors produce partial recommendation batches.
- Importing a candidate creates a `.research` atom and `InquirySourceRef`.

View model tests:

- Source Radar refresh stores a batch for the active branch.
- Switching branches shows branch-specific cached recommendations.
- Dismissing a candidate keeps it dismissed for that branch only.
- Queuing a candidate preserves it across session reload.
- Dock commit creates route receipts and undoable operations.

UI validation:

- Research mode with no sources.
- Research mode with local and external recommendations.
- Read mode with active source and highlight menu.
- Write mode with dock and route receipts.
- Map mode with source and evidence counts.
- Missing API key state.
- Loading state.
- Provider partial failure state.

## Acceptance Criteria

1. A user can select any question branch and see recommended sources specific to that branch.
2. Recommended sources explain why they help and which evidence role they serve.
3. A user can type one thought into one dock and have it routed to notes, claims, evidence, source tasks, branch suggestions, or terms.
4. High-confidence routes commit with receipts and undo.
5. Medium and low confidence routes appear as preview cards before commit.
6. Highlights from a source can be saved with explicit evidence role and branch provenance.
7. Imported source candidates become existing Cosmo research/source entities, not a separate data silo.
8. Missing or failing providers do not block local recommendations.
9. The UI feels calmer and more native than the current split note/chat/source layout.
10. The implementation does not regress current inquiry session persistence, question creation, source opening, or crystallization review.

## Scope Boundaries

In scope for the first build:

- Source candidate data model.
- Branch profile and recommendation batch storage.
- Local provider.
- OpenAlex provider.
- Crossref provider.
- Semantic Scholar provider if API access is available through a key or unauthenticated quota.
- Source Radar UI.
- Thinking Dock UI.
- Prefix parser.
- Route receipt and undo for dock-created operations.
- Existing source reader and web source integration.
- Focused UI polish pass for Inquiry Workspace only.

Out of scope for the first build:

- Full Zotero sync.
- Full PDF annotation system beyond existing source extraction hooks.
- Full YouTube transcript reader redesign.
- Citation graph visualization.
- Multiplayer collaboration.
- Automated background research while the app is closed.
- Replacing the existing Atom storage model.

## Risks

1. The scope can become too large if every provider ships at once.
   Mitigation: implement provider protocol, local provider, and one academic provider first; add the others behind the same interface.

2. One dock can feel magical in a bad way if routes are silent.
   Mitigation: route receipts, undo, explicit prefixes, and preview cards.

3. Source recommendations can become noisy.
   Mitigation: role lanes, dedupe, dismissal, local caching, and branch-specific ranking.

4. Existing panes can grow too large.
   Mitigation: create dedicated small components and keep panes as composition roots.

5. API rate limits can make testing brittle.
   Mitigation: provider clients use protocols and fixtures; ranker and normalization tests do not require network.

## Implementation Sequence

1. Add Source Candidate models, recommendation batch models, and codable storage in `InquirySessionStructured`.
2. Add prefix parser and dock route intent model.
3. Add ranker and normalizer with unit tests.
4. Add local provider and tests.
5. Add Source Radar view using local fixtures.
6. Add Thinking Dock and route receipts.
7. Wire dock submission into existing `InquiryPlacementEngine` and repository methods.
8. Add OpenAlex provider.
9. Add Crossref provider.
10. Add Semantic Scholar provider if API access is configured.
11. Add import actions that create `.research` atoms and `InquirySourceRef`s.
12. Refine the Inquiry layout and remove the duplicate primary note input.
13. Run unit tests and build the app.
14. Review the running UI in each inquiry mode.

## Open Decisions Before Implementation Plan

The following decisions are made for V1:

- The first build targets the existing Inquiry Workspace, not a new workspace.
- Source recommendations are branch-specific.
- The Thinking Dock becomes the only primary input.
- The existing AI thread remains, but it becomes a route and insight panel rather than a second primary input.
- Imported recommendations become normal Cosmo research/source atoms.
- External providers are optional and partial failure is acceptable.
- Provider secrets use existing Keychain-backed API key patterns.

No unresolved product decisions block the implementation plan.
