// cosmo-cloud-agent/src/scheduler/standing.ts
// Standing instruction scheduler + heartbeat check-ins
// Runs on Railway 24/7 — works when Mac is closed

import cron from 'node-cron';
import { fetchAllByType, updateAtom, Atom } from '../db/queries';
import { processMessage } from '../agent/service';
import { getProactiveChatId } from '../telegram/webhook';
import { config } from '../config';

let schedulerTask: cron.ScheduledTask | null = null;
const heartbeatTasks: cron.ScheduledTask[] = [];

// ============================================================
// Start All Schedulers
// ============================================================

export function startScheduler(): void {
  // Standing instructions — check every 60s
  if (!schedulerTask) {
    schedulerTask = cron.schedule('* * * * *', async () => {
      try {
        await checkAndExecuteInstructions();
      } catch (error) {
        console.error('❌ Scheduler error:', error);
      }
    });
    console.log('⏰ Standing instruction scheduler started (every 60s)');
  }

  // Heartbeat check-ins at 8am, 1pm, 5pm, 9pm in user's timezone
  const tz = config.timezone;
  console.log(`💓 Heartbeat scheduler: 8am/1pm/5pm/9pm (timezone: ${tz})`);

  heartbeatTasks.push(
    cron.schedule('0 8 * * *', () => sendHeartbeat('morning'), { timezone: tz }),
    cron.schedule('0 13 * * *', () => sendHeartbeat('midday'), { timezone: tz }),
    cron.schedule('0 17 * * *', () => sendHeartbeat('evening'), { timezone: tz }),
    cron.schedule('0 21 * * *', () => sendHeartbeat('night'), { timezone: tz }),
  );
}

export function stopScheduler(): void {
  schedulerTask?.stop();
  schedulerTask = null;
  for (const task of heartbeatTasks) task.stop();
  heartbeatTasks.length = 0;
}

// ============================================================
// Heartbeat Check-ins
// ============================================================

type TimeSlot = 'morning' | 'midday' | 'evening' | 'night';

const GREETINGS: Record<TimeSlot, string> = {
  morning: '☀️ Good morning! Here\'s your day:',
  midday: '🔥 Midday check — here\'s where you\'re at:',
  evening: '🌅 Wrapping up — here\'s what\'s left:',
  night: '🌙 End of day review:',
};

async function sendHeartbeat(slot: TimeSlot): Promise<void> {
  const chatId = getProactiveChatId();
  if (!chatId) {
    console.log(`💓 Heartbeat (${slot}): skipped — no active chat ID`);
    return;
  }

  console.log(`💓 Heartbeat (${slot}): building check-in...`);

  try {
    const allTasks = await fetchAllByType('task', { limit: 500 });
    const todayStr = getTodayString();

    // Today's incomplete tasks (using whenDate > focusDate > dueDate priority)
    const todayTasks = allTasks.filter(a => {
      const meta = a.metadata || {};
      if (meta.isCompleted) return false;
      if (meta.recurrence && !meta.recurrenceParentUUID) return false; // Skip templates
      const taskDate = getTaskDateStr(meta);
      return taskDate === todayStr;
    });

    // Completed today
    const completedToday = allTasks.filter(a => {
      const meta = a.metadata || {};
      if (!meta.isCompleted) return false;
      const completedAt = (meta.completedAt as string)?.split('T')[0];
      return completedAt === todayStr;
    }).length;

    const totalToday = todayTasks.length + completedToday;

    // Partition into scheduled / unscheduled
    const scheduled: Array<{ title: string; priority: string; time: string }> = [];
    const unscheduled: Array<{ title: string; priority: string }> = [];

    for (const task of todayTasks) {
      const meta = task.metadata || {};
      const title = task.title || 'Untitled';
      const priority = priorityEmoji(meta.priority as string || 'medium');
      const startTime = meta.startTime as string | undefined;

      if (startTime) {
        const time = formatTime(startTime);
        scheduled.push({ title, priority, time });
      } else {
        unscheduled.push({ title, priority });
      }
    }

    // Sort
    scheduled.sort((a, b) => a.time.localeCompare(b.time));
    const pOrder: Record<string, number> = { '🔴': 0, '🟠': 1, '🟡': 2, '⚪': 3 };
    unscheduled.sort((a, b) => (pOrder[a.priority] ?? 4) - (pOrder[b.priority] ?? 4));

    // Build message
    const lines: string[] = [];
    lines.push(GREETINGS[slot]);
    lines.push('');

    if (todayTasks.length === 0 && completedToday === 0) {
      lines.push('No tasks scheduled for today. Enjoy the free time or capture some ideas.');
    } else {
      lines.push(`${todayTasks.length} task${todayTasks.length === 1 ? '' : 's'} remaining today:`);

      let num = 1;
      if (scheduled.length > 0) {
        lines.push('');
        lines.push('⏰ SCHEDULED');
        for (const t of scheduled) {
          lines.push(`${num}. ${t.priority} ${t.title} — ${t.time}`);
          num++;
        }
      }

      if (unscheduled.length > 0) {
        lines.push('');
        lines.push('📝 UNSCHEDULED');
        for (const t of unscheduled) {
          lines.push(`${num}. ${t.priority} ${t.title}`);
          num++;
        }
      }

      lines.push('');
      lines.push(`✅ ${completedToday}/${totalToday} completed`);
    }

    // Contextual message per time slot
    lines.push('');
    lines.push(getContextualMessage(slot, todayTasks.length, completedToday, totalToday));

    const message = lines.join('\n');

    // Send to Telegram
    await fetch(`https://api.telegram.org/bot${config.telegramBotToken}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text: message }),
    });

    console.log(`💓 Heartbeat (${slot}): sent to chat ${chatId}`);
  } catch (error) {
    console.error(`❌ Heartbeat (${slot}) failed:`, error);
  }
}

function getContextualMessage(slot: TimeSlot, remaining: number, completed: number, total: number): string {
  switch (slot) {
    case 'morning':
      if (total >= 8) return 'Big day ahead. Focus on the scheduled blocks first, then work through the rest.';
      if (total >= 4) return 'Solid lineup. You\'ve got this.';
      if (total > 0) return 'Light day. Knock these out and use the extra time for deep work.';
      return 'Clean slate. Great time to brainstorm or capture swipes.';

    case 'midday':
      if (completed === 0 && remaining > 0) return 'Still at 0 completed. Pick one task and just start — momentum builds fast.';
      if (completed > 0 && remaining > 0) return `You've knocked out ${completed} — keep the momentum going.`;
      if (remaining === 0) return 'All done for today. Impressive. Take a break.';
      return 'Halfway through the day. How\'s it going?';

    case 'evening':
      if (remaining <= 2 && remaining > 0) return `Almost there — just ${remaining} left. Can you close these out tonight?`;
      if (remaining > 5) return `${remaining} tasks still open. Prioritize the critical ones and move the rest to tomorrow.`;
      if (remaining === 0) return 'All done! Clean finish. Well played.';
      return `${remaining} tasks remaining. Focus on what matters most.`;

    case 'night':
      const completionRate = total > 0 ? Math.round((completed / total) * 100) : 0;
      if (completionRate >= 80) return `Great day — ${completionRate}% completion rate. Rest well.`;
      if (completionRate >= 50) return `Decent day — ${completed}/${total} done. ${remaining} rolling to tomorrow.`;
      if (completed > 0) return `${completed}/${total} completed today. Tomorrow's a fresh start.`;
      if (total === 0) return 'Quiet day. Use tomorrow to plan and capture ideas.';
      return `Tough day. ${remaining} tasks carry over. Don't stress — tomorrow you'll crush it.`;
  }
}

// ============================================================
// Standing Instructions (unchanged)
// ============================================================

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
  const currentDay = now.getDay();
  const currentDate = now.getDate();
  const todayStr = now.toISOString().split('T')[0];

  for (const inst of instructions) {
    const meta = inst.metadata || {};
    const schedule = meta.schedule as string || 'daily';
    const targetHour = (meta.hour as number) ?? 9;
    const targetMinute = (meta.minute as number) ?? 0;

    if (currentHour !== targetHour || currentMinute !== targetMinute) continue;

    const lastExecuted = meta.lastExecutedAt as string | undefined;
    if (lastExecuted?.startsWith(todayStr)) continue;

    let shouldExecute = false;
    switch (schedule) {
      case 'daily': shouldExecute = true; break;
      case 'weekday': shouldExecute = currentDay >= 1 && currentDay <= 5; break;
      case 'weekly': shouldExecute = currentDay === ((meta.days as number[])?.[0] ?? 1); break;
      case 'specific_days': shouldExecute = (meta.days as number[])?.includes(currentDay) ?? false; break;
      case 'monthly': shouldExecute = currentDate === ((meta.dayOfMonth as number) ?? 1); break;
      case 'interval': {
        const intervalMinutes = (meta.intervalMinutes as number) ?? 60;
        if (lastExecuted) {
          const elapsed = (now.getTime() - new Date(lastExecuted).getTime()) / (1000 * 60);
          shouldExecute = elapsed >= intervalMinutes;
        } else {
          shouldExecute = true;
        }
        break;
      }
    }

    if (!shouldExecute) continue;

    console.log(`⏰ Executing standing instruction: "${inst.body?.substring(0, 60)}..."`);

    try {
      const chatId = getProactiveChatId() || `standing_${inst.uuid}`;
      const result = await processMessage(inst.body || '', chatId);

      await updateAtom(inst.uuid, {
        metadata: { lastExecutedAt: now.toISOString() },
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

      // Send result to Telegram if we have a chat ID
      const activeChatId = getProactiveChatId();
      if (activeChatId) {
        await fetch(`https://api.telegram.org/bot${config.telegramBotToken}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ chat_id: activeChatId, text: result.response }),
        });
      }

      console.log(`  ✅ Instruction executed: ${result.toolsUsed.length} tools used`);
    } catch (error) {
      console.error(`  ❌ Instruction execution failed:`, error);
    }
  }
}

// ============================================================
// Helpers
// ============================================================

function getTodayString(): string {
  const tz = config.timezone;
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' });
    return formatter.format(new Date());
  } catch {
    return new Date().toISOString().split('T')[0];
  }
}

function getTaskDateStr(meta: Record<string, any>): string | null {
  const raw = (meta.whenDate ?? meta.focusDate ?? meta.dueDate ?? null) as string | null;
  if (!raw) return null;
  return raw.split('T')[0];
}

function priorityEmoji(priority: string): string {
  switch (priority) {
    case 'critical': return '🔴';
    case 'high': return '🟠';
    case 'medium': return '🟡';
    case 'low': return '⚪';
    default: return '🟡';
  }
}

function formatTime(isoTime: string): string {
  try {
    const date = new Date(isoTime);
    const hours = date.getHours();
    const minutes = date.getMinutes();
    const ampm = hours >= 12 ? 'PM' : 'AM';
    const h = hours % 12 || 12;
    const m = minutes.toString().padStart(2, '0');
    return `${h}:${m} ${ampm}`;
  } catch {
    return isoTime;
  }
}
