// cosmo-cloud-agent/src/config.ts
// Environment variable configuration for the cloud agent

export const config = {
  // Supabase
  supabaseUrl: process.env.SUPABASE_URL || 'https://cskxozkzpzxyefqmgsgg.supabase.co',
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || '',
  supabaseAnonKey: process.env.SUPABASE_ANON_KEY || '',

  // The single user ID this agent serves (until multi-user is implemented)
  userId: process.env.COSMO_USER_ID || '',

  // Telegram
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN || '',
  telegramWebhookUrl: process.env.TELEGRAM_WEBHOOK_URL || '',

  // LLM / OpenRouter (used for sensor/strategist calls)
  openRouterApiKey: process.env.OPENROUTER_API_KEY || '',
  openRouterBaseUrl: process.env.OPENROUTER_BASE_URL || 'https://openrouter.ai/api/v1',

  // Direct Anthropic API (used for writing engine — no middleman, native caching)
  // If set, writing engine bypasses OpenRouter entirely for faster, more reliable generation
  anthropicApiKey: process.env.ANTHROPIC_API_KEY || '',

  // Agent LLM (separate key if using direct Anthropic/OpenAI)
  agentLLMApiKey: process.env.AGENT_LLM_API_KEY || '',
  agentLLMBaseUrl: process.env.AGENT_LLM_BASE_URL || '',

  // Model tiers (matching Swift ContentModelTier)
  models: {
    sensor: process.env.MODEL_SENSOR || 'anthropic/claude-haiku-4-5',        // Capture, query, correct, plan
    strategist: process.env.MODEL_STRATEGIST || 'anthropic/claude-sonnet-4-6', // Analyze, strategy, draft/brainstorm routing
    writer: process.env.MODEL_WRITER || 'anthropic/claude-opus-4-6',         // Writing engine inner loop (outline, hooks, draft, revise)
  },

  // Timezone (for task date resolution + heartbeat scheduling on UTC server)
  timezone: process.env.TIMEZONE || 'Asia/Ho_Chi_Minh',

  // Telegram chat ID for proactive messages (heartbeat, standing instructions)
  telegramChatId: process.env.TELEGRAM_CHAT_ID || '',

  // Writing API (for Mac app to call cloud engine directly)
  writingApiKey: process.env.WRITING_API_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '',

  // Server
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',

  // Debounce
  debounceWindowMs: 2500, // 2.5 seconds, matching Swift TelegramBridgeService

  // Tool loop
  maxToolIterations: {
    capture: 4,
    query: 8,
    plan: 6,
    correct: 4,
    meta: 4,
    draft: 16,
    brainstorm: 12,
    strategy: 12,
    analyze: 10,
    execute: 8,
    debrief: 6,
    reflect: 6,
    default: 8,
  } as Record<string, number>,

  // Context assembly
  tokenBudget: 6000,
  strategyTokenBudget: 8000,
  contextCacheTTLMs: 120_000, // 2 minutes
  conversationSummarizationThreshold: 15,

  // Engine cache
  maxCachedEngines: 3,
  engineCacheTTLMs: 30 * 60 * 1000, // 30 minutes
} as const;

export function validateConfig(): void {
  const required = [
    ['SUPABASE_SERVICE_ROLE_KEY', config.supabaseServiceRoleKey],
    ['COSMO_USER_ID', config.userId],
    ['TELEGRAM_BOT_TOKEN', config.telegramBotToken],
    ['OPENROUTER_API_KEY', config.openRouterApiKey],
  ] as const;

  const missing = required.filter(([, value]) => !value).map(([key]) => key);

  if (missing.length > 0) {
    console.error(`❌ Missing required environment variables: ${missing.join(', ')}`);
    process.exit(1);
  }

  console.log('✅ Config validated');
  console.log(`   Supabase: ${config.supabaseUrl}`);
  console.log(`   User: ${config.userId.substring(0, 8)}...`);
  console.log(`   Telegram: ${config.telegramBotToken.substring(0, 8)}...`);
  console.log(`   Models: sensor=${config.models.sensor}, strategist=${config.models.strategist}, writer=${config.models.writer}`);
}
