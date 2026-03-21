// cosmo-cloud-agent/src/tools/scorecard.ts
// Draft scoring via LLM — simplified cloud version of ContentScorecardEngine
// PORTING SOURCE: ContentScorecardEngine.swift

import { config } from '../config';
import { Atom } from '../db/queries';

/**
 * Score a draft using Claude Sonnet for evaluation.
 * Returns scorecard with hook, copy, CTA, voice, structure scores.
 */
export async function scoreDraftWithLLM(
  atom: Atom,
  draft: string,
): Promise<Record<string, any>> {
  const meta = atom.metadata || {};

  const prompt = `You are evaluating a content draft. Score it on these dimensions (each 0-10):

1. **Hook Score**: Curiosity gap, low barrier, clear promise, numbers/power words, emotional trigger, short/concise
2. **Copy Score**: Tied to business model, "I could do this" factor, no filler, targets pains/benefits, authentic voice, delivers on hook
3. **CTA Score**: Calls out ICP, answers WIIFM, clear outcome/timeline, clear benefit
4. **Voice Match**: How well does this match a professional creator's voice? (0-100%)
5. **Structural Alignment**: How well does the beat progression follow proven patterns? (0-100%)

For each dimension, provide a score AND 1-2 specific suggestions.

Also provide:
- List of voice drifts (specific lines where the draft sounds generic/AI-like)
- Overall confidence score (0-100)
- Guided feedback paragraph (3-4 sentences of actionable next steps)

DRAFT:
${draft.substring(0, 10000)}

Content title: ${atom.title}
Platform: ${meta.platform || 'Unknown'}
Phase: ${meta.phase || 'draft'}

Respond in this exact JSON format:
{
  "hookScore": {"score": 7, "suggestions": ["..."]},
  "copyScore": {"score": 7, "suggestions": ["..."]},
  "ctaScore": {"score": 7, "suggestions": ["..."]},
  "voiceMatchPercentage": 75,
  "voiceDrifts": [{"lineNumber": 1, "issue": "...", "suggestion": "..."}],
  "structuralAlignmentScore": 70,
  "structuralSuggestions": ["..."],
  "overallConfidence": 72,
  "guidedFeedback": "..."
}`;

  try {
    const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.openRouterApiKey}`,
      },
      body: JSON.stringify({
        model: config.models.strategist,
        messages: [
          { role: 'system', content: 'You are a content scoring engine. Return ONLY valid JSON.' },
          { role: 'user', content: prompt },
        ],
        max_tokens: 4096,
        temperature: 0.2,
      }),
    });

    if (!response.ok) throw new Error(`Scorecard API error: ${response.status}`);

    const data = await response.json() as any;
    const content = data.choices?.[0]?.message?.content || '';

    // Extract JSON from response
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error('No JSON in scorecard response');

    const scorecard = JSON.parse(jsonMatch[0]);
    return scorecard;
  } catch (error) {
    return {
      hookScore: { score: 0, suggestions: ['Scoring failed'] },
      copyScore: { score: 0, suggestions: ['Scoring failed'] },
      ctaScore: { score: 0, suggestions: ['Scoring failed'] },
      voiceMatchPercentage: 0,
      voiceDrifts: [],
      structuralAlignmentScore: 0,
      structuralSuggestions: [],
      overallConfidence: 0,
      guidedFeedback: `Scoring error: ${error instanceof Error ? error.message : String(error)}`,
    };
  }
}
