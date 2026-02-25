# Writing Engine Redesign: Research Findings

> Compiled 2026-02-17 | 15 sources across 6 research topics
> Target: CosmoOS-Swift — macOS content creation app for ghostwriters using Anthropic Claude API

---

## Table of Contents
1. [Multi-Turn Agentic Prompt Architectures](#1-multi-turn-agentic-prompt-architectures)
2. [RAG Best Practices](#2-rag-best-practices)
3. [Few-Shot Example Selection at Inference Time](#3-few-shot-example-selection-at-inference-time)
4. [Constraint-Driven Creative Generation](#4-constraint-driven-creative-generation)
5. [Voice Cloning / Style Transfer in Text](#5-voice-cloning--style-transfer-in-text)
6. [Single-Prompt vs Chain-of-Prompts](#6-single-prompt-vs-chain-of-prompts)

---

## 1. Multi-Turn Agentic Prompt Architectures

### Key Findings

**Anthropic's Three-Layer Tool Architecture (Feb 2026)**
Anthropic's advanced tool use introduces three features that directly solve the context-bloat problem in multi-step writing agents:

1. **Tool Search Tool** — Tools marked `defer_loading: true` are excluded from initial context. Claude receives only a lightweight search tool (~500 tokens), then discovers tools on-demand. Result: **85% reduction in token usage** while maintaining full tool access. ([Source](https://www.anthropic.com/engineering/advanced-tool-use))

2. **Programmatic Tool Calling (PTC)** — Claude writes Python orchestration code rather than invoking tools one-at-a-time. The code runs in a sandbox; intermediate results never enter Claude's context window. Only final `stdout` returns. Result: **37% token reduction**, elimination of redundant inference passes. ([Source](https://www.anthropic.com/engineering/advanced-tool-use))

3. **Tool Use Examples** — `input_examples` arrays added directly to tool definitions demonstrate realistic parameter combinations that schemas alone cannot convey.

**The "Think" Tool vs Extended Thinking**
The "think" tool gives Claude a dedicated space to reason mid-response — distinct from extended thinking which occurs *before* response generation. Key insight: extended thinking reasons over the initial query; the think tool processes newly discovered information mid-execution. Performance: **54% relative improvement** on airline-domain agentic tasks (tau-bench). ([Source](https://www.anthropic.com/engineering/claude-think-tool))

| Scenario | Recommended |
|---|---|
| Complex sequential tool chains | Think tool |
| Policy-heavy environments (format rules, brand voice) | Think tool |
| Simple/parallel tool calls | Extended thinking |
| Math, code generation | Extended thinking |

**Think Tool Schema:**
```json
{
  "name": "think",
  "description": "Use the tool to think about something. It will not obtain new information or change the database, but just append the thought to the log.",
  "input_schema": {
    "type": "object",
    "properties": {
      "thought": { "type": "string", "description": "A thought to think about." }
    },
    "required": ["thought"]
  }
}
```

**LangGraph Plan-and-Execute Pattern**
The plan-and-execute architecture (inspired by Plan-and-Solve paper + Baby-AGI) separates planning from execution:
- **Planner** (large model) generates a multi-step plan
- **Executor(s)** (can be lighter models) execute individual steps with tools
- **Re-planning step** after execution lets the agent modify its plan

Advantages over ReAct-style: faster multi-step execution (sub-tasks don't need the large model), cost savings (small models for sub-tasks), and better task completion rates by forcing explicit planning. ([Source](https://langchain-ai.github.io/langgraph/tutorials/plan-and-execute/plan-and-execute/))

**OpenAI Agents SDK Primitives (2025)**
Three core abstractions: Agents (LLMs + instructions + tools), Handoffs (agent-to-agent delegation), Guardrails (input/output validation). Also includes Sessions (persistent memory within an agent loop) and built-in tracing. ([Source](https://developers.openai.com/tracks/building-agents/))

**Claude Opus 4.6 Capabilities (Feb 2026)**
- 1M input tokens, 128k output tokens
- Adaptive thinking: model decides when to use extended thinking based on task difficulty
- Effort controls: low/medium/high/max — explicit latency vs. reasoning quality dial
- Interleaved thinking: reasons *between* tool calls
([Source](https://www.marktechpost.com/2026/02/05/anthropic-releases-claude-opus-4-6-with-1m-context-agentic-coding-adaptive-reasoning-controls-and-expanded-safety-tooling-capabilities/))

### Recommended Approach for CosmoOS

Use a **plan-then-execute architecture** with Claude as both planner and executor:

1. **Planning phase** (single Claude call with extended thinking): Analyze the content brief, swipe references, voice profile, and format constraints. Output a structured generation plan (sections, beat patterns, word targets per section).

2. **Execution phase** (chained Claude calls): Execute each section of the plan as a separate prompt, passing prior sections as context. Use the think tool between steps so Claude can evaluate consistency with voice profile and format constraints.

3. **Prompt caching**: Cache the static methodology prompt + client voice profile + swipe examples at the system level. These change infrequently and represent the bulk of token cost.

4. **Context layering**: Use `cache_control` breakpoints to create 3 cache layers — methodology (1hr TTL), client profile (1hr TTL), dynamic context like swipes/conversation (5min TTL).

---

## 2. RAG Best Practices

### Key Findings

**Retrieval Architecture**
Production RAG systems in 2025 use a layered retrieval stack:

1. **Hybrid search (vector + keyword)** — Combines semantic understanding with exact-match precision. Organizations report **23% higher precision** vs. basic vector search alone. ([Source](https://neo4j.com/blog/genai/advanced-rag-techniques/))

2. **Re-ranking** — After initial retrieval, a cross-encoder model (monoT5 for balance, RankLLaMA for quality) reorders results by relevance. Critical for ensuring the most useful content surfaces first. ([Source](https://neo4j.com/blog/genai/advanced-rag-techniques/))

3. **Contextual compression** — When retrieved documents exceed context limits, a smaller LLM or heuristic summarizes each to a paragraph. Tools like Recomp support extractive (selecting key sentences) and abstractive (synthesizing across docs) compression. ([Source](https://ragflow.io/blog/rag-review-2025-from-rag-to-context))

**HyDE (Hypothetical Document Embeddings)**
Generate a hypothetical answer first, then embed it and retrieve similar real documents. Improves zero-shot retrieval but adds latency and can mislead if the hypothetical is inaccurate. The newer **HyPE (Hypothetical Prompt Embeddings)** avoids query-time LLM calls entirely and improves precision by up to **42 percentage points**. ([Source](https://www.louisbouchard.ai/top-rag-techniques/))

**Chunking Strategy**
Semantic chunking with contextual headers (document-level + section-level context prepended to each chunk) significantly improves retrieval accuracy. Optimal chunk size: ~200-300 words. ([Source](https://medium.com/@meeran03/building-production-ready-rag-systems-best-practices-and-latest-tools-581cae9518e7))

**"Lost in the Middle" Problem**
Mechanically stuffing lengthy text into an LLM's context window scatters the model's attention, degrading answer quality. This reinforces why RAG with targeted retrieval outperforms brute-force context filling, even with large context windows. ([Source](https://ragflow.io/blog/rag-review-2025-from-rag-to-context))

**Confidence Scoring**
Assigning confidence levels to retrieved documents lets models prioritize high-relevance data while filtering noise. Production systems increasingly use retrieval confidence as a signal for generation quality. ([Source](https://orkes.io/blog/rag-best-practices/))

### Recommended Approach for CosmoOS

Our use case has three retrieval needs: **swipe file examples**, **client voice samples**, and **knowledge base content**. The approach:

1. **Pre-compute embeddings** for all swipe files, client content samples, and knowledge atoms using the existing DaemonXPCClient embedding service.

2. **At generation time**, retrieve top-K swipes by:
   - Embedding similarity to the content brief/idea
   - Metadata filtering (same niche, same format, same platform)
   - BeatPatternService structural similarity (same framework type)

3. **Re-rank** the retrieved swipes using Claude itself (via a lightweight re-ranking prompt) — we already have `SearchReRanker.shared` that does this.

4. **Contextual compression**: For swipe transcripts longer than ~300 words, extract only the hook, key structural beats, and CTA rather than the full transcript. This keeps each swipe example under 400 tokens.

5. **Do NOT use HyDE** — our retrieval is metadata-rich (niche, format, hook type, framework) and similarity-based, so hybrid search with metadata filters will outperform hypothetical document generation. HyDE adds latency we cannot afford in a writing tool.

---

## 3. Few-Shot Example Selection at Inference Time

### Key Findings

**Dynamic vs Static Selection**
Static few-shot (hardcoded examples) is the baseline. Dynamic selection retrieves the most relevant examples at inference time using embedding similarity, dramatically improving performance. Research shows that similarity-based selection (Liu et al.) consistently outperforms random selection. ([Source](https://direct.mit.edu/tacl/article/doi/10.1162/tacl_a_00697/124630/Retrieval-style-In-context-Learning-for-Few-shot))

**Two-Phase Pipeline**
The standard production pattern:
1. **Offline phase**: Embed all candidate examples using a transformer model (e.g., Sentence-BERT / paraphrase-MiniLM-L12-v2). Store embeddings in a vector store.
2. **Online phase**: Embed the incoming query, compute cosine similarity against stored embeddings, select top-K most similar examples.
([Source](https://pubmed.ncbi.nlm.nih.gov/40460022/))

**Diversity-Aware Selection (CVPR 2025)**
Nearest-neighbor retrieval alone can produce redundant examples. COBRA (COmBinatorial Retrieval Augmentation) evaluates *sets* of examples rather than individual samples, modeling interactions between selected examples to avoid redundancy. ([Source](https://openaccess.thecvf.com/content/CVPR2025/papers/Das_COBRA_COmBinatorial_Retrieval_Augmentation_for_Few-Shot_Adaptation_CVPR_2025_paper.pdf))

**CASE: Diverse Reasoning (2025)**
Selects exemplars requiring diverse reasoning capabilities — each example represents a distinct concept, avoiding redundancy found in pure similarity methods. ([Source](https://arxiv.org/pdf/2506.08607))

**Performance-Weighted Selection**
Beyond pure similarity, some systems weight examples by historical performance — examples that previously led to better outputs get higher retrieval priority. This creates a feedback loop where the system improves over time.

**Few-Shot Scaling Behavior**
2-3 examples establish reliable patterns. The LLM distinguishes fixed elements (tone, structure) from flexible ones (specific content details). More examples provide diminishing returns and consume valuable context. ([Source](https://latitude-blog.ghost.io/blog/how-examples-improve-llm-style-consistency/))

### Recommended Approach for CosmoOS

Our "examples" are swipe file transcripts that demonstrate desired writing patterns. The approach:

1. **Use BeatPatternService as the primary selector**: Match by structural fingerprint (framework type, beat sequence) first, then filter by similarity. A carousel about "3 mistakes" should retrieve other "listicle mistake" swipes, not just topically similar ones.

2. **Select 2-3 diverse examples**: One matching the exact format/framework, one from the same niche showing voice style, and optionally one "high-performer" (highest hook score in the category). This mirrors the COBRA/CASE diversity principle.

3. **Embed examples as compressed representations**: For each selected swipe, include: hook text (verbatim), structural beats (from BeatPatternService), key transitions, and CTA — not the full transcript. This keeps few-shot examples compact (~200 tokens each).

4. **Performance-weighted re-ranking**: Track which swipe examples led to accepted vs. rejected drafts (we already have GenerationRecord). Over time, weight recently-successful examples higher.

5. **Cache the example embeddings** in GRDB alongside swipe atoms — no need for a separate vector store since we already have DaemonXPCClient embeddings.

---

## 4. Constraint-Driven Creative Generation

### Key Findings

**The Fundamental Challenge**
LLMs generate tokens autoregressively — each token is sampled independently given context, with no mechanism to enforce global constraints. The model does not "know" it needs to close a brace three tokens from now. Constrained decoding adds that knowledge. ([Source](https://medium.com/@docherty/controlling-your-llm-deep-dive-into-constrained-generation-1e561c736a20))

**Four Categories of Constraints**
1. **Predefined options** — Restrict output to specific choices (e.g., score 1-5)
2. **Regular expressions** — Pattern-matching constraints (JSON schemas, format patterns)
3. **Formal grammars** — Syntactically correct code, structured documents
4. **Templates** — Fill-in-the-blank with LLM-generated placeholders
([Source](https://medium.com/data-from-the-trenches/taming-llm-outputs-59a58ee3246d))

**Structured Output APIs**
OpenAI's Structured Output strict mode, Anthropic's tool use with JSON schemas, and libraries like Outlines, BAML, Guidance, and XGrammar all support constrained decoding — guaranteeing output format at the token level. ([Source](https://www.aidancooper.co.uk/constrained-decoding/))

**Tradeoffs**
- **Guaranteed validity**: All requested fields present, only allowed values, no unexpected fields
- **Robust chaining**: Structured output of one step serves as validated input for the next
- **Quality cost**: Forcing rigid structure can reduce creative quality. Semantic quality may suffer under tight constraints.
([Source](https://medium.com/better-ml/herding-llms-structured-output-with-constraints-ae157ecf5d81))

**User Research (CHI 2024)**
Survey of 51 professionals: constraints operate at two levels — **low-level** (structured format, appropriate length) and **high-level** (semantic/stylistic guidelines, no hallucination). Both are fundamental user needs, not nice-to-haves. ([Source](https://lxieyang.github.io/assets/files/pubs/llm-constraints-2024/llm-constraints-2024.pdf))

**Character/Word Limits**
Length constraints (character, word, or token level) are critical for platform requirements (Instagram caption limits, Twitter, YouTube Shorts descriptions). However, LLMs are notoriously unreliable at counting characters/words during generation. ([Source](https://medium.com/@docherty/controlling-your-llm-deep-dive-into-constrained-generation-1e561c736a20))

### Recommended Approach for CosmoOS

Our constraints include: slide count (carousels), character limits per slide, sentence count per section, and total word count. The approach:

1. **Prompt scaffolding over constrained decoding**: Since we use Claude's API (not local models), we cannot modify logits. Instead, encode constraints as explicit prompt instructions with structural templates:
   ```
   Generate a 10-slide carousel. Each slide MUST be:
   - Slide {N}: [HOOK/BODY/CTA label]
   - Maximum 150 characters
   - Exactly 1-2 sentences

   Output as JSON: {"slides": [{"number": 1, "text": "...", "label": "hook"}]}
   ```

2. **Post-generation validation**: After Claude generates, validate constraints programmatically (character count, slide count, JSON structure). If validation fails, send a correction prompt with the specific violations.

3. **Two-level constraint system**:
   - **Hard constraints** (slide count, character limits): Enforced via JSON schema output + post-validation + retry
   - **Soft constraints** (tone, style, beat pattern): Enforced via few-shot examples + think tool reasoning

4. **Use Claude's tool_use for structured output**: Define a `generate_content` tool with a strict JSON schema that encodes the format constraints. This gives us structured output guarantees without constrained decoding.

5. **Think tool for constraint checking**: Between generation steps, have Claude use the think tool to verify: "Does this slide exceed 150 characters? Does the beat sequence match the target framework?"

---

## 5. Voice Cloning / Style Transfer in Text

### Key Findings

**The Core Problem**
LLMs produce a distinct "LLM-native voice" — outputs cluster more closely with each other than with their supposed target-author corpora. Stylometric analysis shows LLM outputs overuse "we," noun phrases, and symbolic vocabulary; produce longer sentences; and display a neutral, positive, non-accusatory tone. ([Source](https://arxiv.org/html/2509.14543v1))

**What Voice Transfer Requires**
Three dimensions must be captured:
1. **Tone and attitude** — Emotional layer (authoritative vs conversational, skeptical vs confident)
2. **Syntax and rhythm** — Sentence length variation, punctuation patterns, paragraph rhythm
3. **Diction and vocabulary** — Favorite words, jargon, idiosyncratic expressions
([Source](https://business.kanerepublican.com/kanerepublican/article/worldnewswire-2025-11-4-how-to-train-an-ai-to-mimic-your-writing-style-the-end-of-the-generic-voice))

**Style Blueprint Approach**
A concise "Style Blueprint" captures all three dimensions and is injected into every generation request via system prompt or custom instructions. This forces the AI to filter all outputs through the stylistic framework. More effective than vague descriptions like "write casually." ([Source](https://business.kanerepublican.com/kanerepublican/article/worldnewswire-2025-11-4-how-to-train-an-ai-to-mimic-your-writing-style-the-end-of-the-generic-voice))

**Few-Shot Examples Are Key**
2-3 examples establish a reliable template. The AI distinguishes fixed elements (tone, structure) from flexible ones (content details). Examples that closely align with the intended use case provide better results — social media posts for a tech startup should use examples from similar companies, not generic ones. ([Source](https://latitude-blog.ghost.io/blog/how-examples-improve-llm-style-consistency/))

**Fine-Tuning vs Prompting**
Fine-tuning requires 50,000-100,000 words of clean training data — impractical for most clients. Prompt-based style transfer (system prompt + few-shot) is the pragmatic approach for real-time content creation. ([Source](https://business.kanerepublican.com/kanerepublican/article/worldnewswire-2025-11-4-how-to-train-an-ai-to-mimic-your-writing-style-the-end-of-the-generic-voice))

**GhostWriter Architecture (Research)**
Supports mixed-initiative style control: implicit style adaptation (document-scale extraction after every block of writing) + explicit teaching via like/dislike annotations with optional rationales. The system learns and refines its style model over time. ([Source](https://www.emergentmind.com/topics/ghostwriter))

**One-Shot Style Transfer**
LLMs can transfer style from a single example by: (1) taking a neutral version of the content, (2) a styled example as reference, and (3) predicting the styled version of the neutral content. This works because the LLM separates semantic content from stylistic signals. ([Source](https://arxiv.org/html/2510.13302v1))

**Production AI Writing Tools (Jasper, Copy.ai)**
Jasper's "IQ" system analyzes uploaded content samples to create detailed style guides. Organizations report **60-80% reduction in revision cycles** with brand voice features. Copy.ai uses "Brand Voice" + "Infobase" for the same purpose. ([Source](https://aloa.co/ai/comparisons/ai-writing-comparison/jasper-vs-copy-ai/))

### Recommended Approach for CosmoOS

Our voice profile system already has `ClientProfileMetadata` with 13 fields. The approach to actually making it work:

1. **Structured Voice Profile** (cached in system prompt):
   ```
   ## Voice Profile: {clientName}

   ### Tone & Attitude
   - Primary tone: {e.g., "direct and slightly provocative"}
   - Emotional register: {e.g., "confident but relatable, never preachy"}
   - Formality: {1-10 scale}

   ### Syntax & Rhythm
   - Average sentence length: {short/medium/long}
   - Signature patterns: {e.g., "starts paragraphs with one-word sentences", "heavy use of em-dashes"}
   - Paragraph rhythm: {e.g., "short-short-long pattern"}

   ### Diction & Vocabulary
   - Power words: {list of 10-15 signature words/phrases}
   - Banned words: {words this client never uses}
   - Jargon level: {none/light/heavy}

   ### Contrastive Examples
   - GOOD: "{actual excerpt from client's best content}"
   - BAD: "{generic AI version of the same content}"
   - WHY: "{explicit explanation of the difference}"
   ```

2. **Contrastive examples are critical**: Show Claude both a "good" (real client voice) and "bad" (generic AI) version of similar content. This is more effective than positive examples alone because it highlights the specific dimensions of difference.

3. **Dynamic voice sample retrieval**: At generation time, retrieve 2-3 of the client's past content pieces most similar to the current brief (using embedding similarity). Include these as few-shot examples alongside the voice profile.

4. **Voice consistency scoring**: After generation, use a separate Claude call to score voice match (0-100) by comparing the output against the voice profile dimensions. We already have `ContentScorecardEngine` with a `VoiceMatch` criterion — make it use the structured profile.

5. **Cache the voice profile at the 1-hour TTL level** since it changes infrequently. Dynamic examples go at the 5-minute level.

---

## 6. Single-Prompt vs Chain-of-Prompts

### Key Findings

**Research Evidence**
ACL 2024 (Wu et al.) directly compared the approaches on summarization. A chain of draft -> critique -> refine **consistently outperformed** a single "mega prompt" that combined all instructions. Even more striking: initial drafts from chained prompts performed as well as final drafts from stepwise prompts. ([Source](https://www.getmaxim.ai/articles/prompt-chaining-for-ai-engineers-a-practical-guide-to-improving-llm-output-quality/))

**Three Mechanisms Explaining Quality Gains**
1. **Cognitive focus** — Isolating one objective per step makes failures localized
2. **Iterative refinement** — Structured draft-critique-revise loops
3. **Structured handoffs** — Explicit schemas between steps reduce "context bleed"
([Source](https://www.getmaxim.ai/articles/prompt-chaining-for-ai-engineers-a-practical-guide-to-improving-llm-output-quality/))

**Cost: 2-4x Token Increase**
Chain-of-thought prompting typically increases token consumption 2-4x compared to direct answering. However, the chain's value increases with model capability — more advanced models benefit more from chaining. ([Source](https://www.promptingguide.ai/techniques/prompt_chaining))

**Production Pattern for Content Generation**
Recommended chain: Generate summary -> Critique draft -> Verify facts -> Produce refined version. Use deterministic rules (schema, length) + statistical metrics (ROUGE/BLEU) + LLM-as-judge for evaluation at each step. ([Source](https://www.getmaxim.ai/articles/prompt-chaining-for-ai-engineers-a-practical-guide-to-improving-llm-output-quality/))

**When Chaining Adds Little Value**
- Simple, low-complexity tasks
- Hard real-time latency constraints
- Tasks where decomposition provides no clear benefit
([Source](https://www.promptingguide.ai/techniques/prompt_chaining))

**Cost Mitigation Strategies**
- Semantic caching to reduce repeated work
- Parallelize independent steps
- Use faster/cheaper models for non-critical steps; reserve capable models for complex reasoning
([Source](https://www.getmaxim.ai/articles/prompt-chaining-for-ai-engineers-a-practical-guide-to-improving-llm-output-quality/))

**What Production AI Writing Tools Use**
- **Jasper**: Uses "Content Pipelines" — structured end-to-end workflows from idea to publication, with brand voice consistency enforced at each stage
- **Copy.ai**: Uses "Workflows" — prompt chaining with web scraping, data enrichment, and multi-model selection (GPT-4, Claude, Gemini)
- Both use multi-step pipelines, not single prompts, for any non-trivial content
([Source](https://aloa.co/ai/comparisons/ai-writing-comparison/jasper-vs-copy-ai/))

**Prompt Caching Mitigates Chaining Costs**
Anthropic's prompt caching reduces costs by up to **90%** and latency by up to **85%** for long prompts. In multi-step chains, caching the system prompt + methodology + voice profile across all steps dramatically reduces the incremental cost of each chain link. Cache write is 1.25x base; cache read is 0.1x (90% discount). ([Source](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching))

### Recommended Approach for CosmoOS

**Use a 3-4 step chain for all non-trivial content generation:**

1. **Plan** (Claude with extended thinking, Opus-tier):
   - Input: content brief + voice profile + matched swipes + format constraints
   - Output: structured generation plan as JSON (sections, beats, word targets, constraint checklist)
   - Cost tier: High (but cached system prompt makes it affordable)

2. **Draft** (Claude with think tool, Opus or Sonnet-tier):
   - Input: plan + voice profile + 2-3 swipe examples (compressed)
   - Output: full draft text, section by section
   - Think tool used to verify voice consistency between sections
   - Cost tier: Medium (bulk of token usage but system prompt cached)

3. **Score** (Claude, Sonnet-tier):
   - Input: draft + scorecard criteria (hook/copy/CTA/voice match/structural alignment)
   - Output: structured scorecard with per-criterion scores and specific improvement suggestions
   - Cost tier: Low (short prompt, fast model)

4. **Refine** (Claude with think tool, Opus-tier, conditional):
   - Only triggered if Score step identifies issues above threshold
   - Input: draft + specific improvement instructions from scoring
   - Output: refined draft
   - Think tool used to verify each improvement addresses the flagged issue

**Cost optimization:**
- Cache methodology + voice profile at 1-hour TTL (these are the same across all 4 steps)
- Use Sonnet for the Score step (fast, cheap, structured output)
- Use Opus for Plan + Draft + Refine (quality-critical)
- The Score step acts as a quality gate — if the draft scores well, skip the Refine step entirely (saves ~25% of chain cost)

---

## Summary: Architectural Recommendations

| Component | Recommended Approach | Key Source |
|---|---|---|
| **Agent architecture** | Plan-then-execute with think tool between steps | Anthropic advanced tool use, LangGraph |
| **Context management** | 3-tier prompt caching (methodology/profile/dynamic) | Anthropic prompt caching docs |
| **Swipe retrieval** | Hybrid search + structural fingerprint matching + re-ranking | RAG best practices, BeatPatternService |
| **Few-shot examples** | 2-3 diverse, compressed swipe examples selected by format + similarity | COBRA/CASE diversity, embedding retrieval |
| **Format constraints** | JSON schema tool output + post-validation + retry loop | Structured output APIs |
| **Voice transfer** | Structured voice profile + contrastive examples + dynamic samples | GhostWriter, style blueprint research |
| **Generation pipeline** | 4-step chain: Plan -> Draft -> Score -> Refine (conditional) | ACL 2024, Jasper/Copy.ai patterns |
| **Model selection** | Opus for Plan/Draft/Refine, Sonnet for Score | Anthropic adaptive thinking |
| **Cost control** | Prompt caching (90% savings), conditional refinement, model tiering | Anthropic pricing, chaining research |
