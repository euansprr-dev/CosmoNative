// cosmo-cloud-agent/src/index.ts
// CosmoOS Cloud Telegram Agent — Express server
// Works when your Mac is closed. All data via Supabase Postgres.

import express from 'express';
import { config, validateConfig } from './config';
import { handleUpdate, initWebhook } from './telegram/webhook';
import { startScheduler } from './scheduler/standing';
import { writingRouter } from './api/writing';

const app = express();
app.use(express.json());

// ============================================================
// Health check
// ============================================================

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    version: '1.0.0',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

// ============================================================
// Writing API (used by Mac app for canonical engine access)
// ============================================================

app.use('/api/writing', writingRouter);

// ============================================================
// Telegram webhook endpoint
// ============================================================

app.post('/telegram/webhook', async (req, res) => {
  // Respond immediately to prevent Telegram timeout
  res.sendStatus(200);

  try {
    await handleUpdate(req.body);
  } catch (error) {
    console.error('❌ Webhook handler error:', error);
  }
});

// ============================================================
// Start server
// ============================================================

async function start(): Promise<void> {
  console.log('🚀 CosmoOS Cloud Agent starting...');

  // Validate environment
  validateConfig();

  // Initialize Telegram webhook
  await initWebhook();

  // Start standing instruction scheduler
  startScheduler();

  // Start Express server
  app.listen(config.port, () => {
    console.log(`\n✅ Cloud Agent running on port ${config.port}`);
    console.log(`   Webhook: ${config.telegramWebhookUrl || 'not set (use polling fallback)'}/telegram/webhook`);
    console.log(`   Health: http://localhost:${config.port}/health`);
    console.log(`   Standing instructions: checking every 60s`);
    console.log('');
  });
}

start().catch(error => {
  console.error('❌ Failed to start:', error);
  process.exit(1);
});
