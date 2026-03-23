// cosmo-cloud-agent/src/telegram/webhook.ts
// Telegram webhook handler — ported from TelegramBridgeService.swift
// PORTING SOURCE: TelegramBridgeService.swift lines 595-928
//
// Key differences from Swift version:
// - Webhook instead of long polling
// - No writing session manager (Phase 3)
// - No Flash-Lite router (simplification — all goes through full agent)
// - Debounce still implemented (2.5s window)

import { config } from '../config';
import { processMessage, ToolProgressCallback } from '../agent/service';

// Debounce state
const debounceBuffers: Map<string, string[]> = new Map();

// Last active chat ID — used for proactive messages (heartbeat, standing instructions)
let lastActiveChatId: string | null = config.telegramChatId || null;

/** Get the chat ID to send proactive messages to */
export function getProactiveChatId(): string | null {
  return lastActiveChatId;
}
const debounceTimers: Map<string, NodeJS.Timeout> = new Map();
const processingChats: Set<string> = new Set();

// Bot info
let botUsername: string | null = null;

/**
 * Initialize the webhook — register with Telegram API and fetch bot info.
 */
export async function initWebhook(): Promise<void> {
  // Fetch bot username
  const meResponse = await fetch(
    `https://api.telegram.org/bot${config.telegramBotToken}/getMe`
  );
  const meData = await meResponse.json() as any;
  if (meData.ok) {
    botUsername = meData.result.username;
    console.log(`🤖 Telegram bot: @${botUsername}`);
  }

  // Set webhook if URL is configured
  if (config.telegramWebhookUrl) {
    const webhookResponse = await fetch(
      `https://api.telegram.org/bot${config.telegramBotToken}/setWebhook`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          url: `${config.telegramWebhookUrl}/telegram/webhook`,
          allowed_updates: ['message', 'callback_query'],
        }),
      }
    );
    const webhookData = await webhookResponse.json() as any;
    console.log(`📡 Webhook set: ${webhookData.ok ? 'success' : webhookData.description}`);
  } else {
    console.log('⚠️ No TELEGRAM_WEBHOOK_URL set — webhook not registered');
  }
}

/**
 * Handle incoming Telegram update (webhook payload).
 * Source: TelegramBridgeService.handleUpdate() in Swift
 */
export async function handleUpdate(update: any): Promise<void> {
  if (update.message) {
    await handleMessage(update.message);
  } else if (update.callback_query) {
    await handleCallbackQuery(update.callback_query);
  }
}

// ============================================================
// Message Handling
// ============================================================

async function handleMessage(message: any): Promise<void> {
  const chatId = String(message.chat.id);
  const threadId = message.message_thread_id;
  const compositeId = threadId ? `${chatId}:${threadId}` : chatId;

  // Track last active chat for proactive messages (heartbeat, standing instructions)
  if (lastActiveChatId !== chatId) {
    console.log(`📱 Active chat ID: ${chatId}`);
  }
  lastActiveChatId = chatId;

  // Extract text
  const text = message.text as string | undefined;
  if (!text) return; // Skip non-text messages for now

  // Group chat filtering — only respond to @mentions or replies to bot
  const chatType = message.chat.type;
  if (chatType === 'group' || chatType === 'supergroup') {
    const isMentioned = botUsername && text.includes(`@${botUsername}`);
    const isReply = message.reply_to_message?.from?.is_bot === true;
    if (!isMentioned && !isReply) return;
  }

  // Strip @mention from text
  let cleanText = text;
  if (botUsername) {
    cleanText = cleanText.replace(new RegExp(`@${botUsername}\\s?`, 'gi'), '').trim();
  }

  // Commands (bypass debounce)
  if (cleanText.startsWith('/')) {
    await handleCommand(compositeId, cleanText, chatId, threadId);
    return;
  }

  // Debounce accumulation (2.5s window)
  if (processingChats.has(compositeId)) {
    // Already processing — buffer
    const buffer = debounceBuffers.get(compositeId) || [];
    buffer.push(cleanText);
    debounceBuffers.set(compositeId, buffer);
    return;
  }

  // Start debounce
  const existingBuffer = debounceBuffers.get(compositeId);
  if (existingBuffer) {
    existingBuffer.push(cleanText);
  } else {
    debounceBuffers.set(compositeId, [cleanText]);
  }

  // Clear existing timer
  const existingTimer = debounceTimers.get(compositeId);
  if (existingTimer) clearTimeout(existingTimer);

  // Schedule flush after debounce window
  const timer = setTimeout(() => {
    debounceTimers.delete(compositeId);
    flushDebounceBuffer(compositeId, chatId, threadId);
  }, config.debounceWindowMs);

  debounceTimers.set(compositeId, timer);
}

async function flushDebounceBuffer(compositeId: string, chatId: string, threadId?: number): Promise<void> {
  const buffer = debounceBuffers.get(compositeId);
  debounceBuffers.delete(compositeId);
  if (!buffer || buffer.length === 0) return;

  const joinedText = buffer.join('\n\n');
  processingChats.add(compositeId);

  try {
    // Send typing indicator
    await sendChatAction(chatId, 'typing', threadId);

    // Create progress tracker for live-updating status message
    const progress = createProgressTracker(chatId, threadId);

    // Process through full agent with progress callback
    const result = await processMessage(joinedText, compositeId, progress.callback);

    // Finalize progress message (change header to ✅ Done)
    await progress.finalize();

    // Send response (with chunking for long messages)
    await sendLongMessage(chatId, result.response, threadId);

    // Log tools used
    if (result.toolsUsed.length > 0) {
      console.log(`  Tools: ${result.toolsUsed.join(', ')}`);
    }
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.error(`❌ Agent processing failed: ${errorMsg}`);
    await sendMessage(chatId, `Something went wrong. Please try again.`, threadId);
  } finally {
    processingChats.delete(compositeId);

    // Process any deferred messages that arrived during processing
    const deferred = debounceBuffers.get(compositeId);
    if (deferred && deferred.length > 0) {
      debounceBuffers.delete(compositeId);
      debounceBuffers.set(compositeId, deferred);
      const timer = setTimeout(() => {
        debounceTimers.delete(compositeId);
        flushDebounceBuffer(compositeId, chatId, threadId);
      }, config.debounceWindowMs);
      debounceTimers.set(compositeId, timer);
    }
  }
}

// ============================================================
// Commands
// ============================================================

async function handleCommand(compositeId: string, text: string, chatId: string, threadId?: number): Promise<void> {
  const command = text.split(' ')[0].toLowerCase();

  switch (command) {
    case '/start':
      await sendMessage(chatId, 'Welcome to CosmoOS Cloud Agent. I work even when your Mac is closed. Send me a message to get started.', threadId);
      break;
    case '/clear': {
      const { loadConversation, saveConversation } = await import('../db/queries');
      const existing = await loadConversation(compositeId);

      // Summarize before clearing (preserve context)
      let summary = existing?.summary || '';
      if (existing?.messages && existing.messages.length > 0) {
        try {
          const msgText = existing.messages
            .filter((m: any) => m.role === 'user' || (m.role === 'assistant' && !m.toolCalls))
            .map((m: any) => `${m.role}: ${typeof m.content === 'string' ? m.content.substring(0, 150) : ''}`)
            .join('\n');

          const response = await fetch(`${config.openRouterBaseUrl}/chat/completions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${config.openRouterApiKey}` },
            body: JSON.stringify({
              model: config.models.sensor,
              messages: [
                { role: 'system', content: 'Summarize in 2 sentences. Preserve: client names, content created, key decisions.' },
                { role: 'user', content: msgText },
              ],
              max_tokens: 128,
            }),
          });
          const data = await response.json() as any;
          const newSummary = data.choices?.[0]?.message?.content || '';
          if (newSummary) {
            summary = summary ? `${summary} | ${newSummary}` : newSummary;
          }
        } catch {}
      }

      await saveConversation(compositeId, [], { summary: summary || undefined });
      await sendMessage(chatId, 'Context cleared ✓\nStarting fresh — previous context summarized for continuity.', threadId);
      break;
    }
    default:
      await sendMessage(chatId, `Unknown command: ${command}`, threadId);
  }
}

// ============================================================
// Callback Queries (Inline Buttons)
// ============================================================

async function handleCallbackQuery(callback: any): Promise<void> {
  const callbackId = callback.id;
  const data = callback.data as string;
  const chatId = String(callback.message?.chat?.id || '');
  const threadId = callback.message?.message_thread_id;
  const compositeId = threadId ? `${chatId}:${threadId}` : chatId;

  // Acknowledge callback
  await fetch(`https://api.telegram.org/bot${config.telegramBotToken}/answerCallbackQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ callback_query_id: callbackId }),
  });

  // Route callback data as a message to the agent
  if (data.startsWith('agent_btn:')) {
    const action = data.replace('agent_btn:', '');
    try {
      const result = await processMessage(action, compositeId);
      await sendLongMessage(chatId, result.response, threadId);
    } catch (error) {
      await sendMessage(chatId, 'Failed to process action.', threadId);
    }
  }
}

// ============================================================
// Telegram API Helpers
// ============================================================

const MAX_MESSAGE_LENGTH = 4096;
const MAX_SEND_RETRIES = 3;

async function sendMessage(
  chatId: string,
  text: string,
  threadId?: number,
  parseMode?: string,
  replyMarkup?: any
): Promise<boolean> {
  const body: any = {
    chat_id: chatId,
    text,
  };
  if (threadId) body.message_thread_id = threadId;
  if (parseMode) body.parse_mode = parseMode;
  if (replyMarkup) body.reply_markup = replyMarkup;

  let retryCount = 0;
  while (retryCount <= MAX_SEND_RETRIES) {
    const response = await fetch(
      `https://api.telegram.org/bot${config.telegramBotToken}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }
    );

    if (response.status === 429) {
      // Rate limited
      const retryData = await response.json() as any;
      const retryAfter = retryData.parameters?.retry_after || Math.pow(2, retryCount + 1);
      console.log(`⏳ Rate limited, waiting ${retryAfter}s`);
      await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
      retryCount++;
      continue;
    }

    if (response.ok) return true;

    console.error(`❌ sendMessage failed: ${response.status}`);
    return false;
  }

  return false;
}

async function sendLongMessage(chatId: string, text: string, threadId?: number): Promise<void> {
  if (text.length <= MAX_MESSAGE_LENGTH) {
    await sendMessage(chatId, text, threadId);
    return;
  }

  // Split at paragraph boundaries
  const chunks: string[] = [];
  let remaining = text;
  while (remaining.length > MAX_MESSAGE_LENGTH) {
    let splitIndex = remaining.lastIndexOf('\n\n', MAX_MESSAGE_LENGTH);
    if (splitIndex === -1 || splitIndex < MAX_MESSAGE_LENGTH / 2) {
      splitIndex = remaining.lastIndexOf('\n', MAX_MESSAGE_LENGTH);
    }
    if (splitIndex === -1 || splitIndex < MAX_MESSAGE_LENGTH / 2) {
      splitIndex = MAX_MESSAGE_LENGTH;
    }
    chunks.push(remaining.substring(0, splitIndex));
    remaining = remaining.substring(splitIndex).trimStart();
  }
  if (remaining) chunks.push(remaining);

  for (const chunk of chunks) {
    await sendMessage(chatId, chunk, threadId);
    // Small delay between chunks to avoid rate limits
    await new Promise(resolve => setTimeout(resolve, 200));
  }
}

async function sendChatAction(chatId: string, action: string, threadId?: number): Promise<void> {
  const body: any = { chat_id: chatId, action };
  if (threadId) body.message_thread_id = threadId;

  await fetch(
    `https://api.telegram.org/bot${config.telegramBotToken}/sendChatAction`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }
  );
}

/**
 * Send inline keyboard buttons.
 * Source: TelegramBridgeService send_telegram_buttons in Swift
 */
// ============================================================
// Real-Time Progress Tracker (live-updating message during tool loop)
// ============================================================

const PHASE_MAP: Record<string, string> = {
  generate_outline: 'outline', update_outline: 'outline',
  generate_draft: 'draft', write_draft: 'draft',
  generate_hooks: 'hooks', add_hooks: 'hooks',
  score_draft: 'score', run_scorecard: 'score',
  revise_draft: 'revise',
};

export function createProgressTracker(chatId: string, threadId?: number) {
  const completedLines: string[] = [];
  const completedPhases = new Set<string>();
  let activeLine: string | null = null;
  let messageId: number | null = null;
  let lastFlush = 0;
  let flushTimeout: NodeJS.Timeout | null = null;
  let flushing = false; // Lock to prevent race condition
  let dirty = false;    // Flag to re-flush after current flush completes
  let toolCount = 0;
  const startTime = Date.now();

  function buildText(isFinal: boolean): string {
    const parts: string[] = [];
    parts.push(isFinal ? '✅ Done' : '🔄 Working...');
    parts.push('');
    for (const line of completedLines) {
      parts.push(`  ✓ ${line}`);
    }
    if (!isFinal && activeLine) {
      parts.push(`  ⏳ ${activeLine}...`);
    }
    return parts.join('\n');
  }

  async function flush(isFinal: boolean): Promise<void> {
    if (flushing && !isFinal) { dirty = true; return; } // Don't overlap flushes
    flushing = true;
    const text = buildText(isFinal);
    if (!messageId) {
      messageId = await sendMessageReturningId(chatId, text, threadId);
    } else {
      await editMessage(chatId, messageId, text, threadId);
    }
    lastFlush = Date.now();
    flushing = false;
    // If more events arrived during flush, re-flush
    if (dirty && !isFinal) { dirty = false; scheduleFlush(); }
  }

  function scheduleFlush(): void {
    if (flushTimeout) return;
    const elapsed = Date.now() - lastFlush;
    const delay = Math.max(0, 1500 - elapsed);
    flushTimeout = setTimeout(async () => {
      flushTimeout = null;
      await flush(false);
    }, delay);
  }

  const callback: ToolProgressCallback = (event) => {
    if (event.type === 'started') {
      activeLine = event.label;
      // Only show progress for longer workflows (>3 tools or slow actions)
      // For fast actions, we skip the progress message entirely
      if (toolCount >= 3) {
        scheduleFlush();
      }
    } else if (event.type === 'completed') {
      toolCount++;
      const phase = PHASE_MAP[event.tool];
      if (phase && completedPhases.has(phase)) return; // Dedup
      if (phase) completedPhases.add(phase);

      let line = event.label;
      if (event.preview) line += ` (${event.preview})`;
      completedLines.push(line);
      activeLine = null;
      // Start showing progress after 3rd tool completes
      if (toolCount >= 3) {
        scheduleFlush();
      }
    }
  };

  const finalize = async (): Promise<void> => {
    if (flushTimeout) { clearTimeout(flushTimeout); flushTimeout = null; }
    const elapsed = Date.now() - startTime;

    // For fast actions (≤3 tools or < 5 seconds), delete progress message
    // instead of showing it — the final response is enough
    if (toolCount <= 3 || elapsed < 5000) {
      if (messageId) {
        // Delete the progress message silently
        try {
          await fetch(
            `https://api.telegram.org/bot${config.telegramBotToken}/deleteMessage`,
            { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chat_id: chatId, message_id: messageId }) }
          );
        } catch {}
      }
      return;
    }

    // For longer workflows, finalize with ✅ Done header
    if (completedLines.length > 0) {
      await flush(true);
    }
  };

  return { callback, finalize };
}

async function sendMessageReturningId(chatId: string, text: string, threadId?: number): Promise<number | null> {
  const body: any = { chat_id: chatId, text };
  if (threadId) body.message_thread_id = threadId;

  const response = await fetch(
    `https://api.telegram.org/bot${config.telegramBotToken}/sendMessage`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
  );

  if (!response.ok) return null;
  const data = await response.json() as any;
  return data.result?.message_id ?? null;
}

async function editMessage(chatId: string, messageId: number, text: string, threadId?: number): Promise<void> {
  const body: any = { chat_id: chatId, message_id: messageId, text };
  if (threadId) body.message_thread_id = threadId;

  await fetch(
    `https://api.telegram.org/bot${config.telegramBotToken}/editMessageText`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
  ).catch(() => {}); // Silent failure — edit is best-effort
}

export async function sendTelegramButtons(
  chatId: string,
  message: string,
  buttons: Array<{ label: string; action: string }>,
  threadId?: number
): Promise<boolean> {
  // Arrange buttons in rows (max 3 per row, max 8 total)
  const capped = buttons.slice(0, 8);
  const rows: any[][] = [];
  for (let i = 0; i < capped.length; i += 3) {
    rows.push(
      capped.slice(i, i + 3).map(b => ({
        text: b.label,
        callback_data: `agent_btn:${b.action}`,
      }))
    );
  }

  return sendMessage(chatId, message, threadId, undefined, {
    inline_keyboard: rows,
  });
}
