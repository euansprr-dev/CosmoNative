# OPTION+A Model Picker and Default Agent Design

Date: 2026-05-06
Status: Design approved for implementation planning
Selected direction: Exact OpenRouter model presets plus a sharper default collaborator prompt

## Goal

Make the OPTION+A Cosmo Window model picker actually control the model used by the normal in-app agent, add the requested current OpenRouter models, and improve the default non-custom agent so it is a stronger general collaborator for brainstorming, research, knowledge work, and content creation.

## Current Context

The current model picker is backed by `AgentModelTier?` on `CosmoWindowViewModel`. That gives the UI only four states: Auto, Haiku, Sonnet, and Opus. The selected value is passed to `CosmoAgentService.processMessage` as `tierOverride`, where it is collapsed into tier routing and OpenRouter failover chains.

That design is fine for broad routing tiers, but it cannot express exact OpenRouter IDs such as `openai/gpt-5.5` or `~google/gemini-flash-latest`. It also makes the picker feel broken because the user is choosing a label, not a concrete model. The UI says "Opus" while routing still has failover and legacy defaults behind it.

OpenRouter correction, 2026-05-06: the `openai/gpt-5.5:thinking` variant can surface in variant docs, but the live model catalog exposes the routable GPT-5.5 model as `openai/gpt-5.5`. The "GPT 5.5 Thinking" picker option should therefore call `openai/gpt-5.5` and send OpenRouter's `reasoning` parameter instead of using a `:thinking` model id.

The default agent prompt already contains useful behavior, but it has grown into one large string. It mixes content ghostwriting rules, tool rules, personality, anti-hallucination behavior, swipe adaptation behavior, and source-specific formatting. That makes it harder to tune the normal OPTION+A experience without also affecting custom agents and specialized writing flows.

## Verified Model IDs

The implementation will add these exact model IDs:

- `openai/gpt-5.5` for GPT 5.5 Thinking, with OpenRouter's `reasoning` request parameter.
- `anthropic/claude-opus-4.7` for Claude Opus 4.7.
- `openai/gpt-chat-latest` for OpenAI GPT Chat Latest.
- `~google/gemini-flash-latest` for the rolling Gemini Flash family alias.

`google/gemini-3.1-flash` was checked and is not a valid OpenRouter endpoint. The approved replacement is the rolling Flash-family alias, `~google/gemini-flash-latest`.

Reference links:

- OpenRouter GPT-5.5: https://openrouter.ai/openai/gpt-5.5/api
- OpenRouter thinking variant: https://openrouter.ai/docs/docs/routing/model-variants/thinking
- OpenRouter Opus 4.7: https://openrouter.ai/anthropic/claude-opus-4.7/api
- OpenRouter GPT Chat Latest: https://openrouter.ai/openai/gpt-chat-latest/providers
- OpenRouter Gemini Flash Latest: https://openrouter.ai/~google/gemini-flash-latest/api

## Selected Architecture

Keep the existing `AgentModelTier` routing contract, but extend it to include explicit model presets for the OPTION+A picker. This avoids a large provider rewrite while still making model selection concrete and testable. Auto remains nil and continues to use intent-based routing. Any explicit picker choice becomes a concrete `AgentModelTier` case with an exact `modelId`.

The failover chains will be updated so explicit model choices start with their selected model instead of being silently remapped into the old Sonnet/Haiku/Opus chain. For example, GPT 5.5 Thinking should call `openai/gpt-5.5` first and only use a compatible fallback if the selected model has a retryable provider failure.

The normal agent prompt will be split into a dedicated default-agent prompt module. `AgentContextAssembler.defaultIdentityPrompt` will become a composed prompt built from named sections:

- Collaborator identity and conversation style.
- Research and retrieval behavior.
- Brainstorming and content strategy behavior.
- Anti-hallucination and citation behavior.
- Tool-use policy.
- Writing quality and AI-tell avoidance.
- Cost discipline and escalation policy.

Custom agents will continue to layer their own `routingPromptLayer` on top. The design goal is to improve the base agent when no custom agent is selected, not to change custom-agent semantics.

## Default Agent Behavior

The normal OPTION+A agent should feel like a pragmatic creative partner rather than a generic chatbot. It should:

- Start by understanding what the user is trying to do, then move the work forward.
- Brainstorm in concrete options and tradeoffs, not vague encouragement.
- Search or retrieve when the user asks for current facts, sources, swipes, client data, content, or library knowledge.
- Say when evidence is thin rather than inventing detail.
- Produce usable drafts when asked, but avoid overusing the heavy writing workflow unless the user explicitly asks for content creation or writing mode.
- Keep casual chat and light brainstorms concise.
- Escalate to deeper models only when the prompt needs long reasoning, synthesis, or high-quality writing.

## Cost Strategy

The implementation will add cost discipline without changing the user's workflow:

- Auto routing remains the default.
- Lightweight capture and routing stay on `google/gemini-3.1-flash-lite-preview` through the existing `FlashLiteRouter`.
- Cheap general chat can use `openai/gpt-chat-latest` or Gemini Flash when explicitly selected.
- GPT 5.5 Thinking is exposed as a deliberate high-reasoning pick, not the default.
- Opus 4.7 is exposed for deep synthesis and premium writing.
- Static prompt text stays first in the system prompt so provider prompt caching can hit. OpenAI and Anthropic both recommend stable prompt prefixes for lower latency and cost, and the existing OpenRouter Anthropic path already sends `cache_control` for the cached system block.
- Dynamic workspace context stays near the end of the prompt and remains token-budgeted.

## Testing Strategy

The implementation will be covered with focused XCTest cases:

- New model cases expose exact OpenRouter IDs.
- The picker option list includes the requested labels and IDs.
- Auto label stays "Auto"; explicit selections show their concrete labels.
- Explicit model choices use a failover chain whose first model is the selected ID.
- The OpenRouter settings model list includes the same IDs.
- The default prompt includes the new cost discipline and collaborator behavior sections.

No live OpenRouter calls are required in tests.

## Spec Self-Review

- Placeholder scan: no placeholders remain.
- Internal consistency: the design keeps Auto as intent routing and explicit choices as exact model presets.
- Scope check: this is one focused implementation plan because all work touches the same model-selection and prompt path.
- Ambiguity check: Gemini Flash uses `~google/gemini-flash-latest`, not the invalid `google/gemini-3.1-flash` ID.
