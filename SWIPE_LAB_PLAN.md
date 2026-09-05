# Swipe Lab — from collected examples to transferable judgment

Product and implementation proposal · macOS · 5 September 2026

Status: the macOS implementation is now in the working tree. Swipe File → Lab opens a persistent study; board menus, single-swipe Focus Mode and client rows also provide entry points. The original interactive concept remains illustrative; the native app runs the existing AI service against actual selected sources. Implementation and verification notes follow at the end of this document.

## Product decision

Build **Swipe Lab** as a persistent study workspace entered from a board, a selection of swipes, or a client. Keep **Study** as the action in Swipe. Single-post Focus Mode remains the close-reading view inside the same experience.

The emotional arc: “I can tell these posts are good, but I cannot explain why” becomes “I can recognize the mechanism, explain its limits, and use it deliberately in this client's voice.”

The core loop is **observe → compare → explain → challenge → practise → apply → review outcomes**. A saved principle, with evidence and boundaries, is the durable output. Conversation helps the user reach it.

The promising distinction is the continuity of this loop inside CosmoOS: the source, the interpretation, the user's practice, the client adaptation, and the eventual published result stay connected. This is a product thesis, not a claim that no other product has any of these features.

## 1. The experience

### Entry and scope

Add `Study board` to a board's header and context menu. Add `Study selection` to Swipe multiselect. Add a quiet `Study swipes` action to the client hub. A single swipe offers `Study with related swipes`, returning to its originating board when available.

Opening a lab does not require creating a Deep Dive, filling in a questionnaire, or saving a board first. Existing boards reuse their recent lab; a selection creates an autosaved session. An optional question can be entered immediately. Start with one inline scope summary:

> Founder stories · 24 posts · Apply to: Studio North

**Study population and adaptation client are separate.** A board may contain several creators. Choosing a client means “help me transfer this learning to this client,” not “assume this client authored all these posts.” Support a separate explicitly labeled population of the client's own published posts. Never silently combine those populations.

Scope records include board/selection identity, included source UUIDs, comparison population, format, platform, publication range, target client, analysis coverage, and the metric definition when performance is involved. The whole library can be the explicit scope; it must not become the silent fallback for a board question.

### First useful screen

Display cached content immediately. Offer three concrete starts: `Find recurring moves`, `Compare with other posts`, and `Guide a study`. Show a short board brief when ready: up to three useful patterns, one exception worth reading, and one unanswered question. Each opens its evidence. Do not require the brief before the user can read or ask something.

The central source reader remains the hero. The default workspace has:

- A leading outline: the board's sources and saved findings in a consistent grouped list.
- A central reading surface: original media, slides or transcript, and a compact structural annotation track.
- A trailing study conversation: the current question, concise answer, exact references, and contextual actions.

Saved findings have an outline section and can also open as a central notebook page; they do not require a fourth persistent panel.

### The defining interaction: claim to evidence

The user asks, “What do these posts have in common?” The answer identifies a specific move such as **showing evidence before explaining the lesson**. It includes:

1. An observation and its denominator, such as “Appears in 7 of the 10 readable carousels.”
2. Clickable source fragments: `Post A · slide 2`, `Post B · 00:08–00:13`.
3. A proposed mechanism: how the move may change what the reader understands or expects.
4. An exception or counterexample, with its own source.
5. A boundary: where this interpretation might not transfer.
6. A useful next action: compare the exceptions, save a principle, or practise it.

Counts in this document are examples, not measured results. In the product, counts come from the analysis ledger, not generated prose.

Clicking a reference opens that exact slide, time range, page region, or text passage in the centre. The answer remains visible. A “Back to previous passage” action restores source, playback position, selection, and scroll. Reading another post does not discard the conversation or change the board-wide scope.

Selecting a passage supports `Explain this move`, `Find the same move`, and `Challenge this interpretation`. The selected passage appears as explicit context in the composer. Board context, selected sources, and the active passage have distinct roles.

### Compare by function

Offer a two-source comparison within the central workspace. Align **hook with hook, proof with proof, payoff with payoff**; posts of different lengths need semantic beat alignment rather than synchronised slide numbers. Selecting a beat focuses both originals and their relevant text. Allow imperfect or missing matches and show them honestly.

The comparison can answer different questions:

| Comparison | What it can teach |
|---|---|
| Two successful posts with different surface styles | The mechanism they share beneath different wording |
| Same creator, similar topic and format, different outcomes | A more informative candidate explanation for the outcome difference |
| Two posts sharing a mechanism but different outcomes | The conditions under which that mechanism may be insufficient |
| Reference post and client's draft | Whether the underlying move survived adaptation |

The visual comparison is two columns with a shared beat selector, original excerpts, and plain-language interpretation. Add an optional structural alignment view after the reading interaction works. Avoid making a network graph the default way to read sequential content.

## 2. A specialist study method

Use one specialist assistant with a consistent vocabulary and typed tools. Tasks can use different internal passes without exposing a cast of separate bots.

The method should take each example through six levels:

| Level | Questions the assistant must be able to answer |
|---|---|
| Observation | What exactly is said, shown, heard, or omitted? Where? |
| Reader state | What does the reader know, want, expect, or doubt at this moment? |
| Sequence | What job does this beat do, and why does the next beat follow? |
| Mechanism | How might this change attention, comprehension, belief, or willingness to act? |
| Alternative explanation | Could audience familiarity, distribution, topic, timing, production, or other differences explain the result? |
| Transfer | Which part can this client use honestly, and which part depends on the original creator? |

Hook, format, structure, voice, pacing, visual composition, editing, proof, payoff, and CTA are selectable lenses. Defaults should follow the material: layout for a carousel, spoken/on-screen interaction for video, subject/opening/argument for email. A transcript-only example cannot support claims about visual editing or delivery.

Treat “open loop,” “pattern interrupt,” and named frameworks as explanatory tools. The answer must explain their operation in the actual example. Avoid converting emotional language into unsupported claims about specific hormones or audience brain states.

Include absence analysis: what was deliberately left out, delayed, or compressed? Include a counterfactual exercise: what changes if we remove the proof, reveal the answer earlier, or replace a concrete detail with a generic statement? Clearly label generated variants as thought experiments, not observed posts or evidence of performance.

### Prompt composition and access

Introduce a shared `StudyPromptCatalog` adapter over existing prompt sources. It exposes module IDs, content, versions/hashes, supported tasks, scope, enabled state, and provenance. The lab has access to relevant registered guidance without inserting every app prompt into every request.

Compose a request in this order:

1. **Study contract:** evidence standards, truthfulness, task limits, tool rules, and the observation/hypothesis distinction.
2. **Method:** the reusable rhythm/jobs/absences reading procedure and comparison procedure.
3. **Selected guidance:** user-enabled craft modules, applicable format/genre guidance, and explicit study instructions.
4. **Client context:** the selected client's factual dossier, voice examples, audience, offers, and accepted lessons when relevant.
5. **Study evidence:** frozen population, computed coverage, source fragments, metric snapshots, and previously accepted findings.
6. **Current turn:** the question, explicit selections, conversation summary, and working hypotheses.

Use precise module IDs and dependency rules rather than concatenating writer, editor, and general-agent role prompts. Record the assembled module versions with each result. User-edited guidance flows through, and a change invalidates relevant cached analysis. A diagnostics disclosure can show which guidance was used; raw implementation details stay out of the normal study flow.

Guidance can be a user preference or a testable craft heuristic. Neither converts an unverified performance explanation into a fact. When evidence contradicts a preferred rule, the assistant should show the discrepancy and ask whether it is a useful exception. Source posts, transcripts, and imported text are evidence, never instructions capable of changing the assistant's rules.

### Reuse carefully

`CraftStudyMethod` is particularly useful: rhythm, jobs, absences, and comparison of equivalent beats. However, it currently contains claims of having read every library transcript, includes raw reach in its rhetoric about evidence, and includes format prescriptions that can conflict with user modules. Extract the sound procedures into shared components; do not import that whole role verbatim into Lab.

Resolve conflicts explicitly: hard source facts and content modality first; user instructions and client-specific constraints next; empirical craft heuristics after that. Format rules should be qualified by the source and client rather than forcing every successful example into a single structure.

## 3. Make performance reasoning credible

“Why are these going viral?” has two different answer modes:

- **Winners only:** describe recurring moves and plausible mechanisms; state that the saved set cannot establish what distinguishes winners from ordinary posts.
- **With comparables:** analyse an explicitly selected comparison population and report observed differences, while retaining alternative explanations.

Offer a natural action: `Add comparison posts`. Users can choose another board, a same-creator subset, or their client's published work. Candidate retrieval can suggest matches by creator, platform, format, topic, publication period, and post age. Show matching quality; relax criteria visibly. Missing matching factors should weaken the interpretation.

Do not treat the existing AI hook score as measured success. A “high score” swipe can be a good study example without having known reach or engagement.

Represent metrics as observations with value, unit, denominator, source, capture date, publish date, observation age, and paid/organic status when known. Distinguish unavailable from zero. Different platforms' engagement definitions are not interchangeable. Select the outcome explicitly: reach, shares, saves, follows, replies, or conversion when available. Successful reach does not establish successful sales.

A useful descriptive measure, when data permits, is views relative to a creator's median for the same format and a comparable observation window. Show the baseline's sample size and quality. A current view count with no historical snapshot cannot honestly be described as seven-day performance.

Deduplicate reposts and copied content; report creator concentration. Repeating one creator's formula twenty times is less diverse evidence than observing it across several creators. Broad “what works now” answers must state publication window and freshness. Existing stored content does not constitute live trend monitoring.

Findings use labels such as **Observed**, **Working explanation**, **Mixed evidence**, and **Tested in client work**, each accompanied by its basis. Avoid numerical confidence meters that imply statistical calibration. A causal claim requires evidence from an appropriate test, not a high-confidence model response.

## 4. Make learning durable

### Principles

`Save principle` opens a compact editable statement, with suggested scope and linked evidence already attached. Confirmation here is the user's ordinary save action, not an additional approval ceremony.

A principle contains:

- Statement: the transferable move in plain language.
- Mechanism: the proposed explanation, distinguished from observation.
- Supporting passages, exceptions, and the population that produced it.
- Conditions: audience, format, topic, client, and when it may fail.
- Adaptation: what to preserve and what must be original to the client.
- Origin and version: human/AI authorship, edits, source hashes, and method versions.
- Uses and outcomes: linked practice, ideas, content, and subsequent observations.

Default to the current client when saving a client-specific lesson. Global scope must be intentional. The assistant may suggest principles but must not silently overwrite the client's voice guidance or turn every answer into permanent knowledge. Users can edit, reject, archive, or contradict a saved principle.

The existing Connection system can hold accepted principles; extracts hold the evidence. A Lab notebook is a curated view of those objects rather than another isolated knowledge database.

### Daily practice

`Guide a study` offers a short suggested session, approximately ten minutes, with no timer obligation:

1. Read a new example with its analysis initially hidden.
2. Explain what the opening makes the reader expect, or predict the next beat.
3. Reveal the actual structure and compare it to the user's interpretation.
4. Read one contrasting example that tests the proposed rule.
5. Apply the mechanism to a fresh client idea in a few lines.
6. Save one principle or refine a previous one.

Offer both `Show explanation` and `Let me try`; guided questions must not obstruct normal reading or direct answers. Prefer specific feedback on the user's explanation over an arbitrary mastery score. Future sessions can revisit a saved principle after a delay using an unseen post; repeating the same answer is weak evidence of transfer.

Retrieval practice improved learning in Karpicke and Blunt's study. Using recall and explanation here is a design inference that needs testing with content professionals; that paper does not establish that Swipe Lab improves content outcomes. [Original study](https://pubmed.ncbi.nlm.nih.gov/21252317/).

### Apply and learn from publishing

`Use in idea` sends the principle, the source links, the target client, and a suggested experiment into the existing Idea workflow. The creator supplies their own facts, story, offer, and voice. Track the inherited mechanism separately from borrowed wording.

An optional experiment brief records a hypothesis, the deliberate creative change, the chosen metric and observation window, and the result that would count against the hypothesis. Published performance snapshots can then inform a review. Most everyday posting comparisons remain observational; avoid pretending they are controlled experiments.

Return a short, evidence-backed update: “This is still promising for this client,” “The results are mixed,” or “This lesson needs a narrower scope.” Let the user review changes to accepted knowledge. No automatic publishing is part of this feature.

## 5. macOS design specification

Use the existing warm parchment and forest accent. The post or comparison is the largest visual element. Chrome is sans serif; reading uses the established content typography and a 620–700 pt maximum reading measure when space allows. Docked source/assistant panels use the existing quiet Study inspector surface. Native Liquid Glass is reserved for floating toolbar and transient controls, consistent with [Apple's material guidance](https://developer.apple.com/videos/play/wwdc2025/219/).

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│ ‹ Founder stories     Swipe Lab      [Study | Compare | Practise]    Studio North │
├────────────────┬────────────────────────────────────────┬────────────────────────┤
│ SOURCES     24 │ Post 07 · carousel                     │ COSMO · Board study    │
│                │                                        │                        │
│ Selected post  │     ORIGINAL SLIDE / VIDEO             │ Why does proof come    │
│ Next post      │                                        │ before the lesson?     │
│ Another post   │     One clear reading surface          │                        │
│                │                                        │ Observation            │
│ FINDINGS     3 │ Hook → tension → proof → payoff         │ Interpretation         │
│ Proof first    │                                        │ [A · 2] [B · 00:08]    │
│ Delayed lesson │ Transcript / selected passage          │ Exception              │
│ One exception  │                                        │                        │
│                │                                        │ [Save principle]       │
│                │                                        │ Ask about this board…  │
└────────────────┴────────────────────────────────────────┴────────────────────────┘
```

Provisional geometry: source outline 200–240 pt; conversation 300–360 pt; centre takes remaining width. Reuse `StudyBreakpoint`: at ≥1180 pt the layout may displace content if minimum readable widths are met; at 760–1179 pt one inspector opens over the reader; below 760 pt chrome condenses and inspectors are mutually exclusive overlays. Compare collapses the source outline first and uses the centre's full available width. At insufficient width, switch between the two examples at the same selected beat. Never shrink two readable posts into illegible thumbnails.

Spatial continuity matters more than ornament. Board to Lab preserves the selected swipe and scroll position. Clicking evidence focuses that passage with one restrained highlight. Selecting Compare preserves the current source as one side. Saving a principle inserts a row into Findings. Use existing `ProMotionSprings`, stable identities, and Reduce Motion support; do not animate transcript layout while reading.

Every control has hover feedback, an accessibility label, a tooltip where useful, and a keyboard path. Preserve existing swipe navigation shortcuts, with session-owned navigation rather than a process-wide pointer. Use local mode shortcuts only after checking window/menu conflicts. Escape closes the topmost transient surface before exiting the lab. Text selection and copy work across the transcript; video playback does not restart on a chat update. VoiceOver order follows sources → reading → conversation, with concise announcements for completed answers.

State sketches:

```text
Empty board:      Add posts to study a pattern. [Add swipes]
One post:         Read this post. Add another to compare. [Choose comparison]
Preparing:        18 of 24 posts ready · 6 still processing. [Read available posts]
Missing metrics:  Structure is ready to study. Performance data is unavailable.
Failed source:    Transcript unavailable for this post. [Retry] [Edit transcript]
Changed board:    3 posts added since this study. [Update study]
Offline:          Saved posts and findings available. AI resumes when connected.
```

No summary or progress message claims complete coverage while sources are missing. Source failures remain visible rows. Preserve typed questions on failure and offer an idempotent retry. A deleted source makes its citation unavailable; do not silently redirect it to a different passage.

## 6. Current foundations and actual gaps

| Existing code | What it supplies | Lab work required |
|---|---|---|
| `Data/Models/SwipeBoard.swift`, `Data/Repositories/SwipeBoardStore.swift` | Board definitions; membership on swipe atoms | Typed scope resolver, optional default client, saved Lab association; no duplicate membership list as source of truth |
| `UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift` | Media, transcript, structure and patterns in a WorkbenchShell | Extract reusable reader pieces and add a board-aware host |
| `UI/FocusMode/SwipeStudy/SwipeStudySession.swift` | In-memory singleton of row IDs and next/previous position | Durable session identity, UUID-based source snapshot, independent windows, restore state |
| `SwipeStudyContextProvider` in `SwipeStudyModel.swift` | Current swipe context with a transcript prefix of 1,000 characters | Whole-scope evidence tools and precise passage context; this provider alone cannot fulfil “read the board” |
| `SwipeFile/SwipeAnalysis.swift`, `SwipeInsightEngine.swift` | Hooks, beats, signatures, voice markers, transcripts, some metrics | Validated source anchors, provenance separation, visual coverage, and versioned board synthesis |
| `SwipeFile/Patterns/SwipePatternStore.swift` | Recurring moves with members and evidence text | Treat as candidate discovery; current four-member “confirmed” flag does not mean performance is validated. Store is local JSON, not a synced Lab knowledge store |
| `AI/Recall/RecallDocument.swift`, `RecallEngine.swift` | Hybrid retrieval and source-unit indexing | Board/client allowlists in both candidate generators before top-k; multimodal anchors throughout hit hydration |
| `AI/Craft/CraftStudyMethod.swift`, `Services/PromptTemplateStore.swift` | Deep reading method and editable craft modules | Shared, versioned study catalog; remove inappropriate role claims and resolve conflicting guidance |
| `Data/Models/InquiryWorkspaceModels.swift` | Inquiry sessions, questions, evidence/counterevidence/principle extracts | Optional Lab metadata and richer evidence locators; reuse durable objects without requiring the generic research UI |
| `AI/WritingContextAssembler.swift`, `AI/KnowledgeContextAssembler.swift` | Client and Connection context pathways | Explicit inclusion of accepted, correctly scoped Lab principles with source links |
| `Data/Models/ContentPerfSnapshot.swift` | Dated performance records for published content | Comparable metric observations for swipes; one explicit metric contract across different existing definitions |

This is an integration and evidence-quality project as much as a new screen. The current working tree has other active changes, so implementation should use an isolated branch/worktree and recheck these interfaces at its start.

## 7. Data and AI architecture

### Durable objects

Prefer a backward-compatible optional `swipeLab` payload on an existing inquiry-session atom, with its own `schemaVersion`. Include `StudyScope`, source manifest reference/hash, current question, comparison selection, target client, selected view/beat, source positions, analysis run IDs, and conversation reference. Keep large media and transcripts on their source atoms.

Use existing question/extract/Connection identities for questions, evidence and accepted principles. Add typed extensions rather than encoding important contracts in display strings. A board UUID is not an atom UUID: resolve it through a typed scope enum rather than treating every parent object as an Atom.

New logical records:

- `StudySourceSnapshot`: included UUIDs, source content hashes, publication/metric snapshot references, availability and modality, immutable scope version.
- `StudyEvidenceAnchor`: source UUID, source hash, locator kind, unit/slide/segment ID, text range or time range, short captured quotation, source modality and extraction provenance. Text ranges specify their indexing convention and never rely only on Swift `hashValue` or array position.
- `StudyFinding`: statement, observation vs explanation, support and counterevidence anchor IDs, eligible population and missing counts, scope/version, limitations, generation provenance, acceptance state.
- `StudyPracticeAttempt`: exercise version, unseen source/beat, user's answer, feedback, principle links, timestamps. Can use a compact session attachment initially.
- `StudyExperimentLink`: principle and idea/content UUIDs, hypothesis, planned observation window/metric, result references; no parallel content pipeline.

Decide storage layout in the first implementation phase: atom metadata for compact structured state and existing conversation storage for turns; a dedicated table is justified for large indexed run ledgers if measured payload size requires it. Reuse atoms' sync semantics where possible. Board schema changes require coordinated sync payloads/migrations; optional additions must preserve unknown sibling metadata on older clients.

### Corpus-aware execution

1. **Resolve:** enumerate the complete selected population from the database, not only loaded or visible gallery rows. Deduplicate and freeze a source manifest for the run.
2. **Prepare:** reuse valid analysis; process missing or changed material with bounded concurrency, cancellation and retry. Maintain per-source status and separate original content from model interpretation.
3. **Analyse:** for “across this board,” examine every eligible source through a per-source pass. Reduce validated per-source observations into board counts. Search can locate evidence for focused questions; a handful of top-k hits cannot establish board-wide prevalence.
4. **Challenge:** inspect exceptions and matched comparison sources; check exact supporting fragments against original content. Avoid repeatedly reusing model summaries as independent evidence.
5. **Respond:** build a structured answer, validate anchors and computed values, then render prose and interactive citations. Unsupported claims must be revised or explicitly qualified before display as findings.
6. **Retain:** save the conversation automatically, but promote only selected findings to durable principles.

For large boards, compact signatures discover candidate patterns, structured per-source records calculate scope statistics, and original units supply the evidence. If a fresh question needs a feature not previously analysed, perform a new bounded sweep and report coverage. Never label sampling as having read all sources.

Cache by source content hash, extraction/analysis version, prompt-module hash, scope-manifest hash, client-context version, and selected metrics where relevant. Changing a post invalidates affected findings; changing board membership offers a new snapshot without rewriting prior answers. A later answer must identify whether it belongs to the original or refreshed study.

### Tool boundary

Proposed internal tool capabilities: resolve/list scoped sources; read original units; search within scope; align beats; calculate cohorts; retrieve client guidance; retrieve prompt modules; prepare a finding; save a user-selected principle; prepare an idea handoff. All return typed IDs and provenance.

Apply scope restrictions before ranking in vector and keyword retrieval and again at hydration. Current `RecallQuery` has type filters and exclusions but lacks a positive source allowlist. Adding an allowlist only after retrieval would both lose relevant board results and risk accidental scope broadening. Include scope and client in every cache/session key and test concurrent windows.

Use existing provider and model-routing abstractions. Keep deterministic aggregation out of model prompts; use cheaper extraction where quality allows and stronger reasoning for synthesis. Choose actual model tiers with evals, not a promise attached to a model brand. Background AI runs must have bounded work and costs; opening a large board must not repeatedly reanalyse the whole library.

## 8. Delivery sequence and acceptance gates

### Phase 1 — The defining experience

Implement scope resolution, persistent session ownership, source anchors, prompt composition, board-wide evidence coverage, a Lab host using the current reader, grounded conversation, a basic two-post comparison, and saving a principle. Initial parity: carousel, text post/thread, and reel transcript/time anchors where available; visual claims require captured visual evidence.

Entry points: Study board and Study selection, plus single-swipe continuation. Client targeting is supported in the scope even before adding more client-hub navigation. Put a basic comparison and principle handoff in this first slice so it demonstrates the intended loop.

Proposed implementation homes: `UI/FocusMode/SwipeLab/`, `AI/SwipeLab/`, `Data/Models/SwipeLabModels.swift`, and a scoped persistence service, with focused extensions to existing Inquiry, Recall and Swipe components. Names are a proposal, not existing files.

**Gate:** With a real board, a user asks one cross-post question, opens accurate evidence in at least two sources, inspects one exception, saves a useful principle, closes the app, and resumes at the same place. No answer can claim more coverage than its ledger supports.

### Phase 2 — Comparisons and performance

Add matched comparison populations, per-metric provenance, creator-relative baselines when valid, outcome selection, and a richer structure alignment view. Expand to other Swipe artifact types using their actual source units.

**Gate:** A winners-only dataset produces a properly limited explanation. A dataset with valid comparables produces reproducible statistics with visible denominators and observation windows. Missing data, duplicated posts and conflicting metrics do not become invented results.

### Phase 3 — Daily learning and creation

Add guided practice, unseen examples, principle review, client notebook views, and linked idea/experiment creation. Feed only accepted, scoped lessons into writing and review.

**Gate:** Users can explain the mechanism in a new example and apply it to a fresh brief in their client's voice. Evaluate this against a baseline rather than inferring learning from session time or swipes opened.

### Phase 4 — Learning from outcomes and refinement

Connect published observations to experiment reviews, support newly added posts and recent-period comparisons, and surface meaningful changes to earlier principles. Polish large-board behaviour, multiwindow use, accessibility, failure states and navigation continuity throughout every phase.

**Gate:** A published result can be traced back to its intended principle, relevant source evidence and measurement window. The system can retain contradictory outcomes without automatically turning them into universal rules.

Calendar estimates should follow the Phase 1 integration spike. The largest uncertainties are exact media anchors, source/metric completeness, scoped retrieval changes, and existing Inquiry/session persistence compatibility.

## 9. Verification and success criteria

Build a curated evaluation set covering a small winners-only board, a board with matched ordinary performers, a mixed-format board, a large board, a client voice transfer, bad OCR/missing video, duplicate posts, conflicting instructions, changed/deleted sources, and two open clients. Source content includes an adversarial instruction to verify it stays evidence.

Measure:

- **Evidence correctness:** every displayed citation resolves; sampled factual statements are supported by the referenced original, not just by another AI summary.
- **Scope correctness:** no out-of-scope source or client leaks; complete-board claims reconcile with the full manifest and exact denominators.
- **Numerical correctness:** metric definitions, units, capture windows and cohort calculations match deterministic fixtures.
- **Learning:** unseen-example explanation and application quality under a human rubric; delayed review where feasible. Do not use confident self-ratings as the main measure.
- **Usefulness:** accepted principles actually used in ideas/content, and the fraction retained after outcome review. Track rejected or corrected findings as quality signals.
- **Native quality:** cached first content and interaction latency, responsive reading during streaming, no playback resets, no scroll jumps, correct keyboard/VoiceOver paths, light/dark and reduced-motion/transparency inspection.

Provisional engineering targets, to validate on a representative Mac: cached workspace content within 300 ms, local source/beat selection within 100 ms, and no main-thread analysis or database scans during scrolling. AI completion time is measured separately and never disguised as UI latency. Test source sets of 10, 100 and 1,000 items with partial failures and cancellation.

Run targeted model/persistence/retrieval tests and UI interaction checks, then the macOS `xcodebuild` gate and seeded screenshot review when implementing. A native build and UI quality claim are not part of this planning deliverable.

## The recommendation

Build the evidence-to-principle interaction first. It makes the larger vision concrete: a post teaches a mechanism, a comparison gives it boundaries, practice makes it usable, and client outcomes let the lesson evolve. The user gains a body of tested judgment that remains connected to the work from which it came.

## Implementation record — 5 September 2026

The native workspace now includes Study, Compare, Practise, Principles and Outcomes. Entry points cover a board, the whole library, filtered posts, a chosen selection, a single swipe (its board when available), and a client's published content. Source population, comparison population and adaptation client remain separate. Source changes raise an update notice while the existing reader stays in place.

The implementation uses inquiry-session atoms with typed Lab metadata, original-source anchors, versioned source manifests, persisted questions and conversation, per-source reading positions, practice records and experiment links. Accepted principles become Connection atoms with original evidence extracts. They feed the existing Craft and writing context through an explicit acceptance/client filter. Ideas carry source and principle links into the existing promotion pipeline; outcome review uses recorded publication and performance snapshots.

The specialist prompt catalog draws from editable craft modules, methodology, platform constraints, writing-system references and custom skills. Reading runs use two concurrent workers, bounded passage batches, hierarchical board summaries, a coverage ledger, deterministic reference validation and a final check against original passages. A single repair attempt can correct an unverified response. Completed source readings are cached for retries; every new question is evaluated against its explicit population. Text, speech segments, carousel slides and artifact copy remain distinct. Available original still images are inspected directly; video movement and audio delivery are not inferred from a transcript or thumbnail.

Verification completed:

- macOS Debug build passed with `xcodebuild` using `/tmp/cosmo-swipe-lab-build`.
- 17 focused `SwipeLabTests` passed. These cover original-text precedence, JSON transcripts, Unicode anchors, long-source partitioning, deduplication, missing metrics, population/client separation, friendly platform filters, empty retrieval scopes, evidence allowlists, concurrent history merge, cancellation, bounded reading concurrency, partial failures and unavailable sources, version identity and serialization.
- Native UI checks covered board entry, session reopening after an app restart, full-width and compact layouts, practice, settings, the preserved question after failure, and the experiment preparation sheet. The title-bar overlap found during this pass was corrected. The library header also adapts to narrower windows.
- A live study of the existing B-Roll Ideas board read all eight passages in its one available post and returned three findings. Opening the closing-passage citation selected slide 8, scrolled to its text and sought to approximately 20.02 seconds. The idea handoff displayed the hypothesis, deliberate change, disconfirming result, metric and seven-day window. No test idea or accepted principle was added to the user's creation workflow.

The learning gains, long-term usefulness and 1,000-source latency targets above remain product evaluation goals, not results claimed by the implementation. Performance comparisons are observational and depend on the supplied metric dates; unknown capture times remain unknown. AI network/provider failures remain recoverable through the preserved question and reading cache.
