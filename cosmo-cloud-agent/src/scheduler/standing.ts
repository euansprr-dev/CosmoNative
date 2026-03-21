// cosmo-cloud-agent/src/scheduler/standing.ts
// Standing instruction cron scheduler
// Runs every 60 seconds, checks for due standing instructions, executes them.
// Source: AgentProactiveScheduler in Swift

import cron from 'node-cron';
import { fetchAllByType, updateAtom } from '../db/queries';
import { processMessage } from '../agent/service';
import { sendTelegramButtons } from '../telegram/webhook';
import { config } from '../config';

let schedulerTask: cron.ScheduledTask | null = null;

/**
 * Start the standing instruction scheduler.
 * Checks every 60 seconds for instructions that are due.
 */
export function startScheduler(): void {
  if (schedulerTask) return;

  schedulerTask = cron.schedule('* * * * *', async () => {
    try {
      await checkAndExecuteInstructions();
    } catch (error) {
      console.error('❌ Scheduler error:', error);
    }
  });

  console.log('⏰ Standing instruction scheduler started (every 60s)');
}

export function stopScheduler(): void {
  schedulerTask?.stop();
  schedulerTask = null;
}

async function checkAndExecuteInstructions(): Promise<void> {
  const all = await fetchAllByType('agent_learning');
  const instructions = all.filter(a =>
    a.metadata?.subtype === 'standing_instruction' &&
    a.metadata?.enabled !== false
  );

  if (instructions.length === 0) return;

  const now = new Date();
  const currentHour = now.getHours();
  const currentMinute = now.getMinutes();
  const currentDay = now.getDay(); // 0=Sunday, 1=Monday, ...
  const currentDate = now.getDate();
  const todayStr = now.toISOString().split('T')[0];

  for (const inst of instructions) {
    const meta = inst.metadata || {};
    const schedule = meta.schedule as string || 'daily';
    const targetHour = (meta.hour as number) ?? 9;
    const targetMinute = (meta.minute as number) ?? 0;

    // Check if time matches (within current minute)
    if (currentHour !== targetHour || currentMinute !== targetMinute) continue;

    // Check if already executed today
    const lastExecuted = meta.lastExecutedAt as string | undefined;
    if (lastExecuted?.startsWith(todayStr)) continue;

    // Check schedule type
    let shouldExecute = false;

    switch (schedule) {
      case 'daily':
        shouldExecute = true;
        break;

      case 'weekday':
        shouldExecute = currentDay >= 1 && currentDay <= 5;
        break;

      case 'weekly':
        // Default to Monday
        const weeklyDay = (meta.days as number[])?.[0] ?? 1;
        shouldExecute = currentDay === weeklyDay;
        break;

      case 'specific_days':
        const days = meta.days as number[] | undefined;
        shouldExecute = days?.includes(currentDay) ?? false;
        break;

      case 'monthly':
        const dayOfMonth = (meta.dayOfMonth as number) ?? 1;
        shouldExecute = currentDate === dayOfMonth;
        break;

      case 'interval':
        const intervalMinutes = (meta.intervalMinutes as number) ?? 60;
        if (lastExecuted) {
          const lastDate = new Date(lastExecuted);
          const elapsed = (now.getTime() - lastDate.getTime()) / (1000 * 60);
          shouldExecute = elapsed >= intervalMinutes;
        } else {
          shouldExecute = true;
        }
        break;
    }

    if (!shouldExecute) continue;

    // Execute the instruction
    console.log(`⏰ Executing standing instruction: "${inst.body?.substring(0, 60)}..."`);

    try {
      // Use a dedicated chat ID for standing instructions
      const chatId = `standing_${inst.uuid}`;
      const result = await processMessage(inst.body || '', chatId);

      // Update lastExecutedAt
      await updateAtom(inst.uuid, {
        metadata: {
          lastExecutedAt: now.toISOString(),
        },
        structured: {
          ...(inst.structured || {}),
          executionHistory: [
            ...((inst.structured?.executionHistory as any[]) || []).slice(-9),
            {
              executedAt: now.toISOString(),
              responsePreview: result.response.substring(0, 200),
              toolsUsed: result.toolsUsed,
            },
          ],
        },
      });

      // Send result to Telegram (if the user has an active chat)
      // TODO: Store the user's primary Telegram chat ID for proactive messages
      console.log(`  ✅ Instruction executed: ${result.toolsUsed.length} tools used`);
    } catch (error) {
      console.error(`  ❌ Instruction execution failed:`, error);
    }
  }
}
