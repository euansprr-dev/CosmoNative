# Pages Are Born Ripe — Rethinking the Inquiry → Concept Loop

*July 15, 2026. Design plan, no code yet.*

---

## 1. The diagnosis: why crystallization feels scattered

The complaint is "seven concepts with a few inputs each, and now what?" That is a symptom. The disease is deeper, and it has five parts:

### 1.1 Crystallization automates the exact step where learning happens

Everything we know about learning says the same thing: **you learn what you generate, not what you collect.** Retrieval practice, elaboration, the Feynman technique, the generation effect — all of them locate learning at the moment you articulate an idea in your own words and discover the gaps.

The concept collaborator feels magical because it puts *you* in the generator seat: it asks, you answer, it organizes what you said. The crystallize pipeline inverts the roles: `ConceptResolver` assigns, `ConnectionRoutingEngine` drafts, `ConceptComposerEngine` polishes, and you review checkboxes. The machine does the articulation; you do the filing. The output is accurate but *dead*, because the understanding never passed through your head. Seven machine-written pages is not knowledge, it is a very well-organized inbox.

### 1.2 Pages are born at the wrong moment

A Connection page today is created at session end, when material is thinnest and your energy is lowest. The resolver's granularity rubric ("0–3 new pages per session") slows fragmentation but can't fix the timing: even a *correct* new page with 3 bullets is a liability. It sits on the canvas looking like a finished thing while actually being a to-do item with no due date.

The concept collaborator shows the right birth moment: a page born from a conversation arrives already developed — named, typed, sectioned, with claims you actually believe. **Pages should be born ripe, not planted as empty seed packets.**

### 1.3 The workflow has a cliff

After "Promote N Concepts," the session ends and nothing tells you what to do next. There is no queue, no ritual, no "this one is ready." The user's own words: "Do I just go into each one separately and start a concept collaborator, and then just go one by one?" The system knows the answer (it knows material counts, recency, centrality) but never says it.

### 1.4 Two AIs with two philosophies run in parallel instead of in series

- The **composer pipeline** writes pages *for* you (organize captured text, no user in the loop).
- The **collaborator** develops pages *with* you (socratic, one question at a time, organize-don't-author).

The second one is the product's identity — it's the thing Euan explicitly loves. The first should be *feeding* the second, not competing with it as an alternate route to the same artifact.

### 1.5 The session's deliverable is misdefined

An inquiry session belongs to a **question**. Its natural deliverable is *progress on that question* — an updated answer in your own voice — plus some concepts that got heavier. Today the deliverable is "N concept pages + a machine summary," which is why finishing a session feels like being handed homework instead of a result.

---

## 2. What must not change

These are the crown jewels; the plan builds around them, not over them:

- **The gathering machinery.** Sources rail, Deep Scout, the YouTube reader with timestamped transcript capture, web reader, selection → extract with provenance. This is genuinely best-in-class collecting. Untouched.
- **The live router.** Captures splitting/placing under questions in real time, concept tags at capture time. Untouched (its tags become even more useful below).
- **Durable concept-first pages + merge-not-replace.** `ConnectionPromotionService.mergedSections`, cross-session idempotency, provenance (`sourceSnippet`), tombstone/revision safety. All kept.
- **The concept collaborator.** Socratic turns, capture-as-you-go, board-native ghost-row staging, organize-don't-author, `propose_inquiry_question` (concept → research). This becomes the *center* of the system.
- **The map.** Kept, and upgraded into the primary "state of my knowledge" view.
- **The Gardener.** Question lifecycle tending stays; the same tending grammar extends to concepts.

---

## 3. Design principles

1. **The user is the author; the AI is the interviewer and the librarian.** Nothing enters a durable page unless the user said it, or explicitly accepted a cited piece of evidence.
2. **Pages are born ripe.** A concept earns a page through a development conversation, never through a checkbox.
3. **Gathering and digesting are one rhythm.** Inhale (watch, read, capture) → exhale (articulate, connect, commit). A session that only inhales is fine — the material waits — but the system always offers the exhale.
4. **Every bullet keeps provenance.** Claim → evidence → source → timestamp, forever.
5. **The system always knows what's next.** Ripeness is computed, visible, and one click from action.
6. **Knowledge consolidates through returns.** The system schedules re-encounters; it never assumes one session made something permanent.

---

## 4. The options space (what was considered)

Breadth first, then the converged pick. Grouped by family:

### A. Change what crystallize produces
- **A1 — The Debrief (teach-back interview).** Session ends with a conversation, not a sheet: the AI interviews *you* about what you learned, using your own captures as probes, and everything durable is built from your answers. → **Adopted as the spine.**
- **A2 — Session field report.** Crystallize writes one narrative artifact (machine voice) and merely *tags* concepts. → Rejected as primary: still machine-authored. The narrative already exists (`UnderstandingNarrativeRevision`); keep it as the quiet record.
- **A3 — Synthesis freewrite.** Session ends with a 5-minute unstructured brain-dump from the user; AI organizes it. → Not the spine (no probing, no gap-finding), but adopted as an *opening move inside* the Debrief for users in flow.

### B. Change when concepts get pages (lifecycle)
- **B1 — Concept lifecycle: mention → seedling → page.** Material accrues under concept names *inside the Deep Dive* without creating atoms; a page is born only through development. → **Adopted (the Seedbed).**
- **B2 — Ripeness queue.** The overview ranks concepts ready for development; one click opens the collaborator preloaded. → **Adopted.**
- **B3 — Thin pages with maturity badges.** Keep creating pages but mark them "seed" and nag. → Rejected: canvas clutter is the complaint; a badge doesn't un-scatter seven cards.

### C. Merge the two loops
- **C1 — In-session ripening nudges.** When a concept crosses a material threshold mid-session, the Study offers "develop it now" without leaving. → **Adopted (light-touch).**
- **C2 — Research-aware collaborator.** Inside any concept conversation, the AI can pull the dive's extracts/quotes/timestamps as evidence probes. → **Adopted.**
- **C3 — Hard two-phase sessions (mandatory gather → digest).** → Rejected as mandatory; adopted as invitation. Forced ritual kills the tool on low-energy days.

### D. Reframe the unit of output
- **D1 — The question's answer is the deliverable.** Debrief step one updates the question's understanding in the user's voice. → **Adopted.**
- **D2 — Claims register.** Atomic claims with belief-status (believed / tested / contradicted), concepts as views over claims. → Rejected as a remodel (too big, wrong altitude for now), but claim-status chips on Evidence items is a worthy later garnish.

### E. Consolidation over time
- **E1 — The Return.** Spaced re-encounters: recall prompt first, then the material. Surfaced via Daily Brief + overview. → **Adopted (last phase).**
- **E2 — Decay/heat on the map.** Nodes fade without returns, glow when ripe. → **Adopted as map styling, no gamification.**

### F. Wilder cards (kept on file, not in plan)
- **Sparring mode:** AI argues the strongest objection from your own sources against a developed concept. Great future collaborator *move*, not architecture.
- **Oral exam mode:** periodic cross-dive quizzes. Overlaps with The Return; revisit later.
- **Cross-dive collisions:** when a seedling matches a concept in another Deep Dive, propose a link. Cheap once the Seedbed exists (concept keys are already normalized); listed as a Phase-4 stretch.

---

## 5. The converged design

Four pieces, one loop: **Seedbed → Debrief → Development → Return.**

### 5.1 The Seedbed (concept incubator) — kills the seven-thin-pages problem

Concepts stop becoming atoms at crystallize time. Instead, the existing pipeline (`ConceptResolver` → `ConnectionRoutingEngine` → `ConceptComposerEngine`, all kept as-is) writes its output into a **nursery on the Deep Dive**:

- `DeepDiveStructured.conceptSeedbed: [IncubatingConcept]`
  - `conceptKey`, `name`, `aliases`, `parentConceptName`, `relatedConceptNames`
  - `stagedItems: [StagedConceptItem]` — cleaned bullet + `rawSnippet` + `sourceExtractUUID` + proposed section + session UUID + date (exactly today's `ConnectionSectionItemDraft` payload, persisted instead of promoted)
  - ripeness signals: material count, distinct sessions touched, last touched, centrality (is it the parent of other seedlings? does the home concept reference it?)
  - `status: incubating | developed(connectionUUID) | dismissed`
- **Merge-into-existing-page assignments change too:** instead of writing items directly into a developed page, they land as **pending ghost rows** (`ConnectionPendingInsert` — the exact staging grammar the collaborator already uses). One staging grammar everywhere: dashed accent row, ✓/✗, sweep-all. A page you shaped by hand is never silently edited by a pipeline; you sweep new material in on your next visit, seeing exactly what arrived.
- Idempotency: staged items key on `sourceExtractUUID` + content key (the split-safe dedup from `mergedSections` reused); `markExtractsPromoted` semantics move to "marked staged."

**Ripeness** is deterministic and legible (Gardener philosophy — signals, not vibes): ripe when `stagedItems ≥ 4` **and** touched in ≥ 2 sessions, **or** user-pinned, **or** material ≥ 7 in one session (a genuine deep dive into one thing). Show the reason on the card: "6 captures across 2 sessions."

**Where you see it:** a **SEEDLINGS** section on the Deep Dive overview (name, material count, ripeness reason, two actions: *Develop* / *fold into…*), and on the map as small seed-glyph nodes orbiting their parent concept — visible mass, zero canvas clutter. Ripe seedlings glow.

### 5.2 The Debrief — the session's exhale (replaces the crystallize sheet as the primary flow)

One button, same place Crystallize lives today. But instead of a review sheet, it opens a **conversation in the Study's thinking bar** (the machinery already exists: inline-assistant skill runtime, pane, staging). Three movements, strictly time-boxed in feel, all skippable:

**Movement 1 — Teach-back (the learning moment).**
> "Before I show you anything: what do you understand now that you didn't when you opened this session?"

The user answers in their own words. The AI probes 1–3 turns, Feynman-style, using *their own captures as instruments*: "You captured 'slow exhales raise vagal tone' from the Huberman video, but you didn't capture *why*. Do you know the mechanism, or should that become a question?" Genuine gaps get staged via the existing `propose_inquiry_question` tool. This movement is where the session's learning actually consolidates.

**Movement 2 — The question's answer (the deliverable).**
From the teach-back (not from the extracts), the AI drafts an update to the question's understanding — organize-don't-author, staged as a reviewed diff on Current Understanding exactly like model updates today. The difference: the "after" text is built from what *you just said*, so the living model of the Deep Dive is written in your voice, session over session. Machine summary still lands quietly in `narrativeHistory` as the archival record.

**Movement 3 — Ripen what's ready (the bridge to development).**
The Debrief looks at the Seedbed and offers at most **one or two** ripe concepts:
> "Vagus nerve ripened this session — 6 captures across 2 sessions. Want to develop it now? About three minutes."

Saying yes starts a **concept development conversation seeded from the Seedbed**: the collaborator opens with the gathered material as probes ("You've collected three claims about vagal tone. In your own words, what's the core thing this concept *is*?"), the user articulates, bullets stage board-native, evidence attaches beneath claims with provenance, the page gets a Type and a name — and only then is the Connection atom created, placed on the canvas, and marked `developed`. **A page is born ripe or not at all.** Saying no is completely fine: everything stays incubating and the ripeness queue catches it.

Lexicon candidates and new questions become quick inline confirms inside the Debrief (chips, one tap), not a separate sheet. The `InquiryCrystallizationReviewV2` sheet is retired once parity lands.

**The fast path stays.** A "Quick close" affordance: skip the Debrief entirely, everything incubates, narrative written, zero pages created. Low-energy sessions must never be punished — the material just waits, visibly.

### 5.3 The evidence-aware collaborator — research superpowers for /concept

New tool for the concept skill: `pull_evidence` — given the working concept, returns staged Seedbed items plus matching extracts across the Deep Dive (body match on concept key/aliases, capture-time tags), each with source title, URL, and timestamp.

What this changes:

- **In Debrief-born development** it's the seed material (5.2).
- **In any ordinary /concept conversation**, the collaborator can now do what a great thought partner does: *bring receipts.* "You claimed X — you actually captured a Huberman quote in March that supports this. Want it under Evidence?" Accepted evidence stages as a cited bullet (quote + source + timestamp link). The organize-don't-author line holds: the AI never asserts evidence into the page; it offers, you accept.
- **The loop becomes symmetric.** Concept → research already exists (`propose_inquiry_question`). Research → concept now exists (Seedbed → development). Development ↔ evidence closes the middle. One continuous circle: wonder → gather → articulate → gap → wonder.

### 5.4 In-session ripening nudge (light touch)

When the live router's concept tags push a seedling over the ripeness line *mid-session*, the Study surfaces one quiet receipt-style capsule: "Vagus nerve is ripening — develop after this video?" Tapping defers it to the Debrief's Movement 3 (pre-selected). Never a modal, never interrupts a video. Some of the best development happens while the source is still hot; this catches that without forcing it.

### 5.5 The Return — consolidation over time

- **Ripeness queue** on the Deep Dive overview (SEEDLINGS section) and a single line in the Daily Brief: "2 concepts ripe in Breathwork." One click → development conversation.
- **Recall-first returns:** when you open a developed page you haven't touched in ~a week and it has pending ghost rows or new evidence, the collaborator's opening move is retrieval, not display: "Before you look — what did you say the mechanism was?" Then the page, then the sweep of pending material. (This is spaced repetition applied to synthesis, without flashcards, without streaks, no gamification.)
- **Map as garden:** seed glyphs (incubating) → glowing (ripe) → solid nodes (developed) → slowly cooling tint on pages that haven't been returned to. The Gardener's TENDING section gains concept entries alongside question entries: "Vagus nerve is ripe," "Box breathing hasn't been touched in 3 weeks and has 4 unswept captures."
- **Stretch:** cross-dive collisions — a seedling whose `conceptKey` matches a concept in another Deep Dive proposes a link, not a merge.

---

## 6. A day in the life (after)

1. Open the "How does breathwork change the nervous system?" question, resume its session.
2. Watch a Huberman video in the Study reader; capture six things off the transcript; the live router places them and tags two with "Vagus nerve." A quiet capsule notes Vagus nerve is ripening. Keep watching.
3. Hit **Close & Debrief**. Cosmo asks what you understand now that you didn't an hour ago. You ramble for two turns; it catches that you can't explain *why* exhale length matters and stages that as a sub-question with your confirmation.
4. It shows a two-line diff to the question's understanding built from what you just said. Accept.
5. "Vagus nerve is ripe — develop it? ~3 min." Yes. Three socratic turns later there's a named, typed page with your claims on top and three cited quotes (with timestamps) beneath them. It lands on the canvas — the only new card from the whole session.
6. Five other concept fragments? Still in the Seedbed, visible on the map as seeds, counted, waiting. Nothing scattered, nothing lost, nothing demanding.
7. Tomorrow's Daily Brief: "1 concept ripe in Breathwork." Or not — it can wait.

The "now what?" question never appears, because every piece of material is either *in a developed page you authored* or *visibly ripening toward one conversation*.

---

## 7. Build phases + reuse map

Ordered so each phase ships value alone and nothing regresses if we stop.

### Phase 1 — The Seedbed (stop the bleeding)
- `IncubatingConcept` / `StagedConceptItem` on `DeepDiveStructured` (hand-written `init(from:)` — optional fields, back-compat decode; same discipline as `InquirySessionStructured`).
- Crystallize pipeline retargeted: resolver/composer output → Seedbed writes + pending ghost rows on existing pages (via `ConnectionPendingInsert` persistence — today it's ephemeral view-state, so pending inserts need a persisted home on the connection's focus state or metadata).
- SEEDLINGS section on Deep Dive overview + seed nodes on the map. Manual "Develop" opens /concept on a new page seeded with staged material (interim: pre-Debrief, this is plain collaborator + seeds).
- Retire auto page creation. `ConnectionPromotionService` keeps `applyAcceptedCandidates` for the development-commit path (one candidate at a time now).

### Phase 2 — The Debrief
- New built-in skill (`.debrief`) on the inline-assistant runtime, Sonnet 5, scoped to inquiry surfaces; three-movement instruction set with the concept skill's hard lines (organize-don't-author, no em dashes, one question per turn); reuse the go-deeper backstop pattern from the agent bridge.
- Study: Crystallize button → "Close & Debrief" + "Quick close." Thinking bar hosts the conversation; receipts grammar for confirms (lexicon chips, question chips).
- Movement 2 writes through the existing model-update apply path; Movement 3 hands off into the Phase-1 development flow with the Seedbed payload.
- Retire `InquiryCrystallizationReviewV2` after parity (lexicon/questions/model-update confirms all live in-Debrief).

### Phase 3 — Evidence-aware collaborator
- `pull_evidence` tool (AgentToolRegistry/Executor) — Seedbed items + tag/key-matched extracts with source + timestamp.
- Concept skill instructions gain the evidence-probe move + cited-bullet staging format (quote + source link; timestamps via the existing `url&t=Ns` contract).
- In-session ripening capsule (5.4).

### Phase 4 — The Return
- Recall-first opening move for stale developed pages with pending material.
- Daily Brief line + Gardener TENDING entries for concepts.
- Map heat styling. Stretch: cross-dive collision proposals.

**Reused wholesale:** ConceptResolver, ConceptComposerEngine, ConnectionRoutingEngine (+ their tests), mergedSections dedup, ConnectionPendingInsert ghost rows, inline-assistant skill runtime + staging + backstop, propose_inquiry_question, Gardener signal style, model-update apply path, narrativeHistory, provenance fields (`rawSnippet`/`sourceSnippet`).

**Deleted/demoted:** auto page creation at crystallize; the checkbox review sheet; silent direct merges into developed pages.

---

## 8. Success criteria

- Zero Connection pages created without a development conversation.
- Every new page has ≥ 3 user-authored claims before it touches the canvas.
- "What do I do next?" is always answered on the overview (ripe count + one-click develop).
- Median time from session close to *something durable in the user's voice* < 5 minutes (Debrief Movements 1–2).
- Seedbed drains: seedlings either develop or fold within ~3 sessions (watch for hoarding; if seedlings pile past ~10 per dive, the Gardener proposes folds).

## 9. Open decisions (recommendations inline)

1. **Ghost rows on developed pages vs. silent merge.** Recommend ghost rows (one grammar, no silent edits), with a "sweep all" and Return-surfacing so they can't rot. If sweeping ever feels like chores, fall back to silent merge for *machine-born* sections only.
2. **Debrief scope for multi-question sessions.** Recommend: teach-back anchored on the session's most-active question; Movement 2 offers one diff per question that gained ≥ 3 extracts, capped at 2.
3. **Naming.** "Seedbed/Seedlings" fits the Greenhouse identity and the Gardener's TENDING language. Neutral fallback: "Emerging concepts."
4. **Does Quick close still run the resolver/composer?** Recommend yes (cheap, async, material lands staged and tagged), so the Seedbed is always current even when the user skips the ritual.
