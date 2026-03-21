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
import { processMessage } from '../agent/service';

// Debounce state
const debounceBuffers: Map<string, string[]> = new Map();
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

    // Process through full agent
    const result = await processMessage(joinedText, compositeId);

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
    case '/clear':
      // Clear conversation by saving empty messages
      const { saveConversation } = await import('../db/queries');
      await saveConversation(compositeId, []);
      await sendMessage(chatId, 'Conversation cleared.', threadId);
      break;
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
