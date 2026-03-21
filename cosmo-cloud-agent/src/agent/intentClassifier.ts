// cosmo-cloud-agent/src/agent/intentClassifier.ts
// Intent classification — ported from CosmoAgentService.swift classifyIntent()
// PORTING SOURCE: CosmoAgentService.swift lines 1258-1520

export type AgentIntent =
  | 'capture' | 'draft' | 'brainstorm' | 'strategy'
  | 'analyze' | 'plan' | 'correct' | 'execute'
  | 'debrief' | 'reflect' | 'meta' | 'query';

export type ModelTier = 'sensor' | 'strategist' | 'writer';

/**
 * Classify user message intent.
 * Source: CosmoAgentService.classifyIntent() in Swift
 */
export function classifyIntent(text: string): AgentIntent {
  const lower = text.toLowerCase().trim();

  // Quick patterns (highest priority)
  if (/^idea\s+(for\s+)?/i.test(lower) || lower.startsWith('save idea') || lower.startsWith('new idea')) {
    return 'capture';
  }
  if (/lesson|rule|preference|remember this|from now on/i.test(lower)) {
    return 'meta';
  }

  // Draft (before capture — long messages with URLs shouldn't be capture)
  if (/draft|write a thread|write a reel|write about|reel for|carousel for|feedback on slide|revise|rewrite/i.test(lower)) {
    return 'draft';
  }

  // Capture (URLs + capture language)
  if (/https?:\/\//.test(lower)) {
    if (/capture|swipe|save|add/i.test(lower)) return 'capture';
    if (/idea|concept|thought/i.test(lower)) return 'capture';
    return 'capture'; // Bare URL defaults to capture
  }

  // Strategy
  if (/content plan|weekly plan|what should i create|content strategy/i.test(lower)) {
    return 'strategy';
  }

  // Analyze
  if (/analyze|performance|persuasion|engagement|score this|how did/i.test(lower)) {
    return 'analyze';
  }

  // Brainstorm
  if (/brainstorm|let's think|what if|spitball|ideas for|come up with/i.test(lower)) {
    return 'brainstorm';
  }

  // Plan/Schedule
  if (/schedule|plan my|calendar|time block|add a block/i.test(lower)) {
    return 'plan';
  }

  // Correct
  if (/delete|remove|rename|fix the/i.test(lower)) {
    return 'correct';
  }

  // Execute
  if (/advance|complete|publish|activate/i.test(lower)) {
    return 'execute';
  }

  // Debrief
  if (/review|recap|summary of today/i.test(lower)) {
    return 'debrief';
  }

  // Reflect
  if (/reflect|journal|mood/i.test(lower)) {
    return 'reflect';
  }

  // Meta
  if (/settings|standing instruction|preference/i.test(lower)) {
    return 'meta';
  }

  return 'query';
}

/**
 * Get model tier for an intent.
 * Source: CosmoAgentService model routing logic in Swift
 */
export function modelTierForIntent(intent: AgentIntent): ModelTier {
  switch (intent) {
    case 'capture':
    case 'plan':
    case 'query':
    case 'correct':
      return 'sensor';
    case 'analyze':
    case 'strategy':
    case 'debrief':
    case 'reflect':
    case 'execute':
    case 'meta':
      return 'strategist';
    case 'draft':
    case 'brainstorm':
      return 'writer';
  }
}

/**
 * Get max tool iterations for an intent.
 * Source: CosmoAgentService.maxToolIterations() in Swift
 */
export function maxToolIterations(intent: AgentIntent): number {
  switch (intent) {
    case 'capture': return 4;
    case 'correct': return 4;
    case 'meta': return 4;
    case 'plan': return 6;
    case 'debrief': return 6;
    case 'reflect': return 6;
    case 'query': return 8;
    case 'execute': return 8;
    case 'analyze': return 10;
    case 'brainstorm': return 12;
    case 'strategy': return 12;
    case 'draft': return 16;
  }
}
