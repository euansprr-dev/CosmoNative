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
  writingApiKey: process.env.WRITING_API_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || 'cosmo-native-writing-2026',

  // Discovery API (for Swipe File Discover/Creators)
  discoveryApiKey: process.env.DISCOVERY_API_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '',
  youtubeApiKey: process.env.YOUTUBE_API_KEY || '',
  brightDataApiKey: process.env.BRIGHT_DATA_API_KEY || '',
  brightDataDatasets: {
    instagram: {
      profilesByUrl: process.env.BRIGHT_DATA_INSTAGRAM_PROFILES_BY_URL || process.env.BRIGHT_DATA_DATASET_INSTAGRAM || '',
      profilesByUsername: process.env.BRIGHT_DATA_INSTAGRAM_PROFILES_BY_USERNAME || '',
      reelsByUrl: process.env.BRIGHT_DATA_INSTAGRAM_REELS_BY_URL || '',
      postsByUrl: process.env.BRIGHT_DATA_INSTAGRAM_POSTS_BY_URL || '',
    },
    tiktok: {
      profilesByUrl: process.env.BRIGHT_DATA_TIKTOK_PROFILES_BY_URL || process.env.BRIGHT_DATA_DATASET_TIKTOK || '',
      postsByUrl: process.env.BRIGHT_DATA_TIKTOK_POSTS_BY_URL || '',
    },
    linkedin: {
      profilesByUrl: process.env.BRIGHT_DATA_LINKEDIN_PROFILES_BY_URL || process.env.BRIGHT_DATA_DATASET_LINKEDIN || '',
      postsByUrl: process.env.BRIGHT_DATA_LINKEDIN_POSTS_BY_URL || '',
    },
    x: {
      profilesByUrl: process.env.BRIGHT_DATA_X_PROFILES_BY_URL || process.env.BRIGHT_DATA_DATASET_X || '',
      postsByUrl: process.env.BRIGHT_DATA_X_POSTS_BY_URL || '',
    },
  },
  apifyApiKey: process.env.APIFY_API_KEY || '',

  // Swipe worker (cloud-side swipe processing — SWIPE_V2_PLAN.md)
  // OPENAI_API_KEY is deliberately NOT required: without it the worker still
  // extracts/mirrors/analyzes and marks reels 'partial' (no speech transcript).
  openaiApiKey: process.env.OPENAI_API_KEY || '',
  swipeWorkerEnabled: process.env.SWIPE_WORKER_ENABLED !== 'false',
  apifyMonthlyRunCap: parseInt(process.env.APIFY_MONTHLY_RUN_CAP || '3000', 10),

  // Reel V3: native-video understanding (SWIPE_REEL_V3_PLAN.md).
  // GEMINI_API_KEY (direct Google AI API) unlocks tier 1 with fps control;
  // without it tier 2 rides the existing OpenRouter key; tier 3 is the
  // frame-batch pipeline. All optional.
  geminiApiKey: process.env.GEMINI_API_KEY || '',
  geminiVideoModel: process.env.GEMINI_VIDEO_MODEL || 'gemini-3-flash-preview',
  // OpenRouter vision model for slide OCR (frame batches + carousel slides).
  // gemini-2.0-flash-001 was sunset on OpenRouter (404s) — keep this current.
  openRouterVisionModel: process.env.OPENROUTER_VISION_MODEL || 'google/gemini-2.5-flash',
  // Direct Google AI models for the same work. Since Sept 2026 the direct
  // key is the PRIMARY for vision + cleanup passes and OpenRouter the fallback
  // (see swipes/llm.ts) — an empty OpenRouter balance took the pipeline down
  // for six days while this key sat unused.
  geminiVisionModel: process.env.GEMINI_VISION_MODEL || 'gemini-2.5-flash',
  geminiTextModel: process.env.GEMINI_TEXT_MODEL || 'gemini-2.5-flash',
  // Swipe insight pass (mirrors SwipeInsightEngine.analysisTier .sonnet5):
  // direct Anthropic first, OpenRouter second.
  anthropicInsightModel: process.env.ANTHROPIC_INSIGHT_MODEL || 'claude-sonnet-5',
  openRouterInsightModel: process.env.OPENROUTER_INSIGHT_MODEL || 'anthropic/claude-sonnet-5',
  // Stable model tried when the preview model 503s under load.
  geminiVideoFallbackModel: process.env.GEMINI_VIDEO_FALLBACK_MODEL || 'gemini-2.5-flash',
  reelVideoFps: parseFloat(process.env.REEL_VIDEO_FPS || '4'),

  apifyInstagramPostLimit: parseInt(process.env.APIFY_INSTAGRAM_POST_LIMIT || '150', 10),
  apifyInstagramMaxPostLimit: parseInt(process.env.APIFY_INSTAGRAM_MAX_POST_LIMIT || '300', 10),
  apifyInstagramIncrementalPostLimit: parseInt(process.env.APIFY_INSTAGRAM_INCREMENTAL_POST_LIMIT || '50', 10),
  discoverySchedulerEnabled: process.env.DISCOVERY_SCHEDULER_ENABLED === 'true',
  discoveryAllowForceRefresh: process.env.DISCOVERY_ALLOW_FORCE_REFRESH === 'true',
  discoveryRefreshCooldownMinutes: parseInt(process.env.DISCOVERY_REFRESH_COOLDOWN_MINUTES || '15', 10),
  xBearerToken: process.env.X_BEARER_TOKEN || '',

  // Exemplar Codex integration — when true, writing engine uses full Codex + walkthrough
  // instead of old methodology + QuarkProfile. Set to false to revert to legacy behavior.
  useExemplarCodex: process.env.USE_EXEMPLAR_CODEX !== 'false', // default true

  // Single agentic session — when true and codex outline exists, writing engine runs
  // all phases (plan + write + self-edit) in one Opus API call with adaptive thinking.
  // Set to false to revert to multi-phase Sonnet pipeline.
  useSingleSession: process.env.USE_SINGLE_SESSION !== 'false', // default true

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

  const missingDiscoveryProviders = [
    ['DISCOVERY_API_KEY', config.discoveryApiKey],
    ['YOUTUBE_API_KEY', config.youtubeApiKey],
    ['BRIGHT_DATA_API_KEY', config.brightDataApiKey],
    ['APIFY_API_KEY', config.apifyApiKey],
  ].filter(([, value]) => !value).map(([key]) => key);

  if (missingDiscoveryProviders.length > 0) {
    console.warn(`⚠️ Discovery providers not fully configured: ${missingDiscoveryProviders.join(', ')}`);
  }

  console.log('✅ Config validated');
  console.log(`   Supabase: ${config.supabaseUrl}`);
  console.log(`   User: ${config.userId.substring(0, 8)}...`);
  console.log(`   Telegram: ${config.telegramBotToken.substring(0, 8)}...`);
  console.log(`   Models: sensor=${config.models.sensor}, strategist=${config.models.strategist}, writer=${config.models.writer}`);
}
