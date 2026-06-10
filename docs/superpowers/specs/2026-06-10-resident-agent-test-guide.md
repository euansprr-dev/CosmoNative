# Resident Agent — Manual Test Guide

Companion to `2026-06-10-cosmo-resident-agent-master-plan.md`. Run top to bottom after a fresh launch; the speed tests are meaningful only with the OpenRouter key configured and the embeddings daemon running.

## 1. Speed & streaming
1. **Pre-warm**: launch, open a note, hover the orb. Console should print `[AGENT-PERF] prewarm prefix=…`. Within 4 minutes, submit an edit — the first `📦 [LLM Cache]` line should show `read=` > 0 on the very first request.
2. **Cache compounding**: submit 3–4 edits on the same note within a few minutes. Rolling `readRatio` in the cache log lines should climb (healthy ≥ 0.85 after a few same-surface requests). If it stays 0, a byte-level invalidator regressed — check the prompt-split tests first.
3. **Streaming answers**: ask a question (answer route, e.g. "what's the weakest part of this draft?"). The pane answer must type out progressively, not appear all at once, and must NOT duplicate when it finalizes.
4. **Thinking states**: watch the orb during a request — sparkle (idle) → sparkles pulse (planning) → magnifier (gathering, with verb-first lines like "Checking Ben's profile") → pencil (drafting) → green check (reviewing).

## 2. Diffs everywhere
5. **Note**: open a note, "tighten the second paragraph" — in-editor red/green diff replaces the editor; accept applies; reject restores.
6. **Content draft**: same flow in a content focus mode.
7. **Idea body**: open an idea, "punch up the angle in my context" — diff renders in the manuscript (serif). Accept persists.
8. **Idea hooks**: "rewrite my second hook to be more contrarian" — hook updates via the hooks list (structured op), not the body.
9. **Canvas sticky**: select a sticky note on canvas (no focus mode), "make this sticky punchier" — proposal appears; accept persists and the block refreshes via GRDB observation.
10. **Synthesis**: lasso-select blocks → synthesis workspace → "tighten the argument" — diff replaces the argument editor.
11. **Locator resilience**: stage an edit, then manually change a nearby word before accepting → accept should still locate (fuzzy) or mark conflicted with the orange "text moved" notice — never apply to the wrong line.
12. **Cross-surface append**: from anywhere, "add 'test learning XYZ' to my <note title> note" — proposal stages; accept writes into the (closed) note. Open the note to verify.

## 3. Skills
13. **Slash menu**: type `/` — all built-ins listed incl. **New Skill** and **Synthesize**; bottom rows: /clear, Create Skill…, **Assistant Studio…**.
14. **Ghost chip routing**: with a custom skill saved (or use a built-in like Voice Variations), type a matching request *without* the slash (e.g. "give me a few versions of this in Ben's voice") — a dashed ghost chip should appear; Tab accepts it; explicit `/` always wins; ambiguous prompts show nothing.
15. **Skill builder**: `/New Skill` → it interviews (≤4 questions, one per turn) → asks for an example → drafts the spec → **dry-runs on the live surface** → "save it" calls create_inline_skill → new skill appears in the slash menu immediately and persists across relaunch (GRDB).
16. **Examples & verification**: edit a custom skill in the Studio, add a verification rule like "no invented metrics" — subsequent runs should refuse to fill numbers without sources.
17. **Sticky sessions**: invoke `/Concept`, give short answers ("because it compounds") — must stay in Concept mode; `/clear` exits.
18. **Skill learning**: accept/reject a few skill-produced diffs, then check the Studio skills tab — accept percentages appear per skill.

## 4. Studio
19. **Open**: `/` → Assistant Studio. Three tabs render.
20. **Skills tab**: toggle a custom skill off → it vanishes from the slash menu; duplicate a built-in → editable copy appears; edit fields and save; delete works.
21. **Personality tab**: add a distinctive rule (e.g. "always end with a one-word verdict"), save, run an answer-route request — the voice should change. Reset to default restores. (Each save = one cache rewrite; the next request shows `write=` then reads resume.)
22. **Metrics tab**: after a few requests, check cache read ratio, avg first-token ms, accept rate, conflict rate populate.

## 5. Recall, chips, navigation
23. **Recall**: ask "what have I saved about <topic you have notes on>?" — watch "Recalling …" status; the answer should cite real titles.
24. **Context chips**: that same answer should show a "Sources" chip row; clicking a chip opens the atom as a pane.
25. **Ambient pack**: open a note that relates to other saved atoms, wait a beat, then ask "what else do I have related to this?" — it should answer **without** a recall round-trip (no "Recalling…" status) using the prefetched digest.
26. **open_atom**: "open my <note title> note" — focus mode opens.
27. **Camera glide**: on a thinkspace with blocks, ask "where's my block about <topic>?" — answer + the canvas glides to the block and selects it.
28. **go_to_area**: "take me to the command center" — navigates.

## 6. Synthesis flagship
29. `/Synthesize a newsletter from my research on <topic>` with a note open as the target: it should (a) list gathered sources in the pane, (b) propose an outline and wait for a nod, (c) then stage sections **one diff at a time**, each rationale citing source titles, (d) chips on the pane messages link back to the sources.
30. Reject one section mid-run — it should adjust rather than barrel on.

## 7. Pane UI polish
34. **Hierarchy**: answers render as plain prose (no card chrome) with a reading measure; your prompts are compact green-washed chips; system titles are small-caps labels. The answer is unmistakably the hero.
35. **Thinking row**: during a request the pane shows one quiet row — phase symbol (magnifier → pencil → check, morphing via symbol replace) in a soft green circle + the verb-first status line. No "Working..." card.
36. **Auto-scroll**: ask something while scrolled up — the pane follows new messages and streaming growth to the bottom.
37. **Empty state**: shows three starter chips (Review this draft / Search my brain / Synthesize); clicking one fills the composer.
38. **Proposal card**: title + monospaced +N/−N counts; "Review" expands the diff with a spring; a decision bar offers **Accept all / Reject all** when changes are pending; "Undo" appears after applying.
39. **Manners**: every chip/button has hover feedback + a tooltip; Esc closes the pane; Return sends from the composer (⌘⏎ also works); the composer shows the focus ring when active; answer text is selectable.

## 8. Regression sentinels
31. `/clear` resets the session, working context, and conversation memory.
32. Telegram capture fast-paths still work (unchanged Gemini pre-routing).
33. Existing automated suites: `CosmoInlineAssistant*`, `CosmoInlineDiffLocatorHardeningTests`, `LLMPartialToolArgumentsTests`, `ConceptSkillRoutingTests`, `CosmoEditableSurfaceRegistryTests` — all green.
