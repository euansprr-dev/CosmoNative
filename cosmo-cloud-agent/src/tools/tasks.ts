// cosmo-cloud-agent/src/tools/tasks.ts
// Enhanced task management tools for the cloud TG agent
// 8 tools: smart_task_create, get_tasks, complete_task, uncomplete_task,
//          reschedule_task, update_task, set_task_recurrence, get_recurring_tasks

import { fetchAtom, fetchAllByType, createAtom, updateAtom, searchAtoms, Atom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';
import { parseTaskInput, resolveDate, ParsedTaskInput, RecurrenceRule } from '../tools/taskParser';
import { v4 as uuidv4 } from 'uuid';

// ============================================================
// Helpers
// ============================================================

const PRIORITY_ORDER: Record<string, number> = {
  critical: 0,
  high: 1,
  medium: 2,
  low: 3,
};

function todayDateString(): string {
  // Use TIMEZONE env var for correct "today" in user's timezone (server runs UTC)
  const tz = process.env.TIMEZONE || 'UTC';
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' });
    return formatter.format(new Date()); // Returns yyyy-MM-dd
  } catch {
    return new Date().toISOString().split('T')[0]; // Fallback to UTC
  }
}

/**
 * Get the task's scheduled date for Today view filtering.
 * Priority: whenDate > focusDate > dueDate
 *
 * CRITICAL: whenDate/focusDate = "when you plan to DO it" (schedule date)
 *           dueDate = "when it's due BY" (deadline)
 *
 * A task with dueDate=March 20 (overdue deadline) but whenDate=March 22
 * (rescheduled to today) should show as TODAY, not OVERDUE.
 * This matches the Mac's CommandCenterDashboardViewModel behavior.
 */
function getTaskDate(meta: Record<string, any>): string | null {
  const raw = (meta.whenDate ?? meta.focusDate ?? meta.dueDate ?? null) as string | null;
  if (!raw) return null;
  return raw.split('T')[0];
}

function isRecurringTemplate(meta: Record<string, any>): boolean {
  return !!meta.recurrence && !meta.recurrenceParentUUID;
}

/**
 * Read the project name from a task's links array.
 * Looks for a link with type "project" and fetches the atom title.
 */
export async function getProjectNameForTask(task: Atom): Promise<string | null> {
  if (!task.links || task.links.length === 0) return null;
  const projectLink = task.links.find(l => l.type === 'project');
  if (!projectLink) return null;
  const project = await fetchAtom(projectLink.uuid);
  return project?.title ?? null;
}

/**
 * Format a RecurrenceRule into a human-readable description.
 */
export function formatRecurrenceDescription(rule: RecurrenceRule): string {
  if (!rule || !rule.frequency) return 'None';

  switch (rule.frequency) {
    case 'daily':
      return rule.interval && rule.interval > 1 ? `Every ${rule.interval} days` : 'Daily';

    case 'weekdays':
      return 'Weekdays (Mon-Fri)';

    case 'weekly': {
      if (rule.daysOfWeek && rule.daysOfWeek.length > 0) {
        const dayNames: Record<number, string> = {
          0: 'Sun', 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat',
        };
        const days = rule.daysOfWeek.map(d => dayNames[d] ?? `Day${d}`).join(', ');
        return `Every ${days}`;
      }
      return rule.interval && rule.interval > 1 ? `Every ${rule.interval} weeks` : 'Weekly';
    }

    case 'monthly': {
      const dayOfMonth = rule.dayOfMonth ?? 1;
      return rule.interval && rule.interval > 1
        ? `Every ${rule.interval} months on day ${dayOfMonth}`
        : `Monthly on day ${dayOfMonth}`;
    }

    case 'yearly':
      return 'Yearly';

    default:
      return String(rule.frequency);
  }
}

/**
 * Format a single task atom into the standard response shape.
 */
async function formatTask(task: Atom): Promise<Record<string, any>> {
  const meta = task.metadata || {};
  const projectName = await getProjectNameForTask(task);

  let checklistProgress: string | null = null;
  if (meta.checklist) {
    try {
      const items = typeof meta.checklist === 'string' ? JSON.parse(meta.checklist) : meta.checklist;
      if (Array.isArray(items) && items.length > 0) {
        const done = items.filter((i: any) => i.isCompleted).length;
        checklistProgress = `${done}/${items.length}`;
      }
    } catch { /* ignore parse errors */ }
  }

  return {
    uuid: task.uuid,
    title: task.title,
    priority: meta.priority ?? 'medium',
    intent: meta.intent ?? null,
    dueDate: meta.dueDate ?? null,
    whenDate: meta.whenDate ?? null,
    focusDate: meta.focusDate ?? null,
    startTime: meta.startTime ?? null,
    isCompleted: meta.isCompleted ?? false,
    completedAt: meta.completedAt ?? null,
    projectName,
    schedulingState: meta.schedulingState ?? null,
    hasChecklist: !!meta.checklist,
    checklistProgress,
    isRecurring: !!meta.recurrence,
    timeOfDay: meta.timeOfDay ?? null,
  };
}

/**
 * Resolve a project by name, returning the UUID if found.
 */
async function resolveProjectByName(name: string): Promise<{ uuid: string; name: string } | null> {
  const results = await searchAtoms(name, { types: ['project'], limit: 5 });
  if (results.length === 0) return null;

  // Prefer exact title match, then first result
  const lower = name.toLowerCase().trim();
  const exact = results.find(a => a.title?.toLowerCase() === lower);
  const match = exact ?? results[0];
  return { uuid: match.uuid, name: match.title ?? name };
}

/**
 * Create a recurring instance from a template for a given date.
 */
async function createRecurrenceInstance(template: Atom, dateStr: string): Promise<Atom | null> {
  const meta = template.metadata || {};

  const instanceMeta: Record<string, any> = {
    ...meta,
    recurrenceParentUUID: template.uuid,
    isCompleted: false,
    completedAt: null,
    dueDate: dateStr,
    whenDate: dateStr,
    focusDate: dateStr,
  };
  // Remove the recurrence rule from the instance — only the template holds it
  delete instanceMeta.recurrence;

  const instance = await createAtom({
    type: 'task',
    title: template.title,
    body: template.body,
    metadata: instanceMeta,
    links: template.links ?? undefined,
  });

  return instance;
}

/**
 * Check if a recurring template should fire on a given date (yyyy-MM-dd).
 */
function shouldRecurrenceFire(rule: RecurrenceRule, dateStr: string): boolean {
  const date = new Date(dateStr + 'T00:00:00');
  const dayOfWeek = date.getDay(); // 0=Sun .. 6=Sat

  switch (rule.frequency) {
    case 'daily':
      return true;

    case 'weekdays':
      return dayOfWeek >= 1 && dayOfWeek <= 5;

    case 'weekly':
      if (rule.daysOfWeek && rule.daysOfWeek.length > 0) {
        return rule.daysOfWeek.includes(dayOfWeek);
      }
      return true; // if no specific days, fire every week on the current day

    case 'monthly':
      return date.getDate() === (rule.dayOfMonth ?? 1);

    case 'yearly':
      return false; // would need month+day check, skip for now

    default:
      return false;
  }
}

// ============================================================
// 1. smart_task_create
// ============================================================

export async function smartTaskCreate(args: Record<string, any>): Promise<string> {
  const input = args.input as string | undefined;

  // Parse NLP input if provided
  let parsed: ParsedTaskInput | null = null;
  if (input) {
    parsed = parseTaskInput(input);
  }

  // Resolve final values — explicit args override parsed
  const title = (args.title as string) ?? parsed?.title ?? null;
  if (!title) return jsonError('Either input or title is required');

  const body = (args.body as string) ?? null;
  const priority = (args.priority as string) ?? parsed?.priority ?? 'medium';
  const intent = (args.intent as string) ?? parsed?.intent ?? 'general';
  const timeOfDay = (args.timeOfDay as string) ?? parsed?.timeOfDay ?? null;
  const schedulingState = (args.schedulingState as string) ?? parsed?.schedulingState ?? null;
  const recurrence = args.recurrence ?? parsed?.recurrenceRule ?? null;

  // Resolve due date
  let dueDate: string | null = null;
  if (args.dueDate) {
    dueDate = resolveDate(args.dueDate) ?? args.dueDate;
  } else if (parsed?.dueDate) {
    dueDate = parsed.dueDate;
  }

  // Resolve project
  let projectUUID: string | null = null;
  let projectName: string | null = null;
  const projectNameArg = (args.projectName as string) ?? parsed?.projectName ?? null;
  if (projectNameArg) {
    const resolved = await resolveProjectByName(projectNameArg);
    if (resolved) {
      projectUUID = resolved.uuid;
      projectName = resolved.name;
    }
  }

  // Build links
  const links: Array<{ type: string; uuid: string; entityType?: string }> = [];
  if (projectUUID) {
    links.push({ type: 'project', uuid: projectUUID, entityType: 'project' });
  }

  // Build metadata
  const metadata: Record<string, any> = {
    priority,
    intent,
    isCompleted: false,
    ...(dueDate ? { dueDate, whenDate: dueDate, focusDate: dueDate } : {}),
    ...(timeOfDay ? { timeOfDay } : {}),
    ...(schedulingState ? { schedulingState } : {}),
    ...(recurrence ? { recurrence: typeof recurrence === 'string' ? recurrence : JSON.stringify(recurrence) } : {}),
  };

  // Build checklist
  if (args.checklist && Array.isArray(args.checklist)) {
    const checklistItems = args.checklist.map((item: { title: string }, index: number) => ({
      id: uuidv4().toUpperCase(),
      title: item.title,
      isCompleted: false,
      sortOrder: index,
    }));
    metadata.checklist = JSON.stringify(checklistItems);
  }

  const atom = await createAtom({
    type: 'task',
    title,
    body,
    metadata,
    links: links.length > 0 ? links : undefined,
  });

  if (!atom) return jsonError('Failed to create task');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    priority,
    dueDate: dueDate ?? null,
    intent,
    recurrence: recurrence ? formatRecurrenceDescription(
      typeof recurrence === 'string' ? JSON.parse(recurrence) : recurrence
    ) : null,
    projectName,
    message: `Task created: "${title}"${dueDate ? ` (due ${dueDate})` : ''}${projectName ? ` in ${projectName}` : ''}`,
  });
}

// ============================================================
// 2. get_tasks
// ============================================================

export async function getTasks(args: Record<string, any>): Promise<string> {
  const list = (args.list as string) || 'today';
  const projectUUID = args.projectUUID as string | undefined;
  const priorityFilter = args.priority as string | undefined;
  const intentFilter = args.intent as string | undefined;
  const searchQuery = args.search as string | undefined;
  const limit = (args.limit as number) || 100;

  // Fetch all tasks
  let allTasks: Atom[];
  if (searchQuery) {
    allTasks = await searchAtoms(searchQuery, { types: ['task'], limit: 200 });
  } else {
    allTasks = await fetchAllByType('task', { limit: 500 });
  }

  // Apply common filters
  if (projectUUID) {
    allTasks = allTasks.filter(t => {
      if (!t.links) return false;
      return t.links.some(l => l.type === 'project' && l.uuid === projectUUID);
    });
  }
  if (priorityFilter) {
    allTasks = allTasks.filter(t => (t.metadata?.priority ?? 'medium') === priorityFilter);
  }
  if (intentFilter) {
    allTasks = allTasks.filter(t => (t.metadata?.intent ?? 'general') === intentFilter);
  }

  const today = todayDateString();

  let sections: Array<{ name: string; tasks: Record<string, any>[] }> = [];

  switch (list) {
    case 'today': {
      // Lazy recurrence generation: check templates that should fire today
      await generateTodayRecurrenceInstances(allTasks, today);
      // Re-fetch to include newly created instances
      allTasks = await fetchAllByType('task', { limit: 500 });
      if (projectUUID) {
        allTasks = allTasks.filter(t => t.links?.some(l => l.type === 'project' && l.uuid === projectUUID));
      }
      if (priorityFilter) {
        allTasks = allTasks.filter(t => (t.metadata?.priority ?? 'medium') === priorityFilter);
      }
      if (intentFilter) {
        allTasks = allTasks.filter(t => (t.metadata?.intent ?? 'general') === intentFilter);
      }

      const incomplete = allTasks.filter(t => !(t.metadata?.isCompleted));

      const overdue: Atom[] = [];
      const scheduled: Atom[] = [];
      const unscheduled: Atom[] = [];

      for (const task of incomplete) {
        const meta = task.metadata || {};
        // Skip recurring templates
        if (isRecurringTemplate(meta)) continue;

        const taskDate = getTaskDate(meta);

        if (taskDate && taskDate < today) {
          overdue.push(task);
        } else if (taskDate === today) {
          const startTime = meta.startTime as string | undefined;
          const startDate = startTime?.split('T')[0];
          if (startTime && startDate === today) {
            scheduled.push(task);
          } else {
            unscheduled.push(task);
          }
        }
      }

      // Sort
      overdue.sort((a, b) => (PRIORITY_ORDER[a.metadata?.priority ?? 'medium'] ?? 2) - (PRIORITY_ORDER[b.metadata?.priority ?? 'medium'] ?? 2));
      scheduled.sort((a, b) => (a.metadata?.startTime ?? '').localeCompare(b.metadata?.startTime ?? ''));
      unscheduled.sort((a, b) => (PRIORITY_ORDER[a.metadata?.priority ?? 'medium'] ?? 2) - (PRIORITY_ORDER[b.metadata?.priority ?? 'medium'] ?? 2));

      const overdueFormatted = await Promise.all(overdue.map(formatTask));
      const scheduledFormatted = await Promise.all(scheduled.map(formatTask));
      const unscheduledFormatted = await Promise.all(unscheduled.map(formatTask));

      if (overdueFormatted.length > 0) sections.push({ name: 'OVERDUE', tasks: overdueFormatted });
      if (scheduledFormatted.length > 0) sections.push({ name: 'SCHEDULED', tasks: scheduledFormatted });
      if (unscheduledFormatted.length > 0) sections.push({ name: 'UNSCHEDULED', tasks: unscheduledFormatted });

      break;
    }

    case 'upcoming': {
      const incomplete = allTasks.filter(t => !(t.metadata?.isCompleted) && !isRecurringTemplate(t.metadata || {}));

      // Group by date for next 7 days
      const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      const groups: Map<string, Atom[]> = new Map();

      for (let i = 1; i <= 7; i++) {
        const d = new Date();
        d.setDate(d.getDate() + i);
        const ds = d.toISOString().split('T')[0];
        groups.set(ds, []);
      }

      for (const task of incomplete) {
        const taskDate = getTaskDate(task.metadata || {});
        if (taskDate && groups.has(taskDate)) {
          groups.get(taskDate)!.push(task);
        }
      }

      for (const [dateKey, tasks] of groups) {
        if (tasks.length === 0) continue;
        const d = new Date(dateKey + 'T00:00:00');
        const dayLabel = dayNames[d.getDay()];
        const formatted = await Promise.all(tasks.map(formatTask));
        sections.push({ name: `${dateKey} (${dayLabel})`, tasks: formatted });
      }

      break;
    }

    case 'anytime': {
      const anytime = allTasks.filter(t => {
        const meta = t.metadata || {};
        if (meta.isCompleted) return false;
        if (isRecurringTemplate(meta)) return false;
        return meta.schedulingState === 'anytime' ||
          (meta.schedulingState == null && meta.whenDate == null && meta.focusDate == null && meta.dueDate == null);
      });
      anytime.sort((a, b) => (PRIORITY_ORDER[a.metadata?.priority ?? 'medium'] ?? 2) - (PRIORITY_ORDER[b.metadata?.priority ?? 'medium'] ?? 2));
      const formatted = await Promise.all(anytime.slice(0, limit).map(formatTask));
      sections.push({ name: 'ANYTIME', tasks: formatted });
      break;
    }

    case 'someday': {
      const someday = allTasks.filter(t => {
        const meta = t.metadata || {};
        return !meta.isCompleted && meta.schedulingState === 'someday';
      });
      someday.sort((a, b) => (PRIORITY_ORDER[a.metadata?.priority ?? 'medium'] ?? 2) - (PRIORITY_ORDER[b.metadata?.priority ?? 'medium'] ?? 2));
      const formatted = await Promise.all(someday.slice(0, limit).map(formatTask));
      sections.push({ name: 'SOMEDAY', tasks: formatted });
      break;
    }

    case 'logbook': {
      const completed = allTasks.filter(t => t.metadata?.isCompleted === true);
      completed.sort((a, b) => (b.metadata?.completedAt ?? '').localeCompare(a.metadata?.completedAt ?? ''));

      // Group by day
      const dayGroups: Map<string, Atom[]> = new Map();
      for (const task of completed.slice(0, limit)) {
        const completedDate = (task.metadata?.completedAt ?? task.updated_at).split('T')[0];
        if (!dayGroups.has(completedDate)) dayGroups.set(completedDate, []);
        dayGroups.get(completedDate)!.push(task);
      }

      for (const [dateKey, tasks] of dayGroups) {
        const formatted = await Promise.all(tasks.map(formatTask));
        sections.push({ name: dateKey, tasks: formatted });
      }
      break;
    }

    case 'overdue': {
      const overdue = allTasks.filter(t => {
        const meta = t.metadata || {};
        if (meta.isCompleted) return false;
        const taskDate = getTaskDate(meta);
        return taskDate != null && taskDate < today;
      });
      overdue.sort((a, b) => (PRIORITY_ORDER[a.metadata?.priority ?? 'medium'] ?? 2) - (PRIORITY_ORDER[b.metadata?.priority ?? 'medium'] ?? 2));
      const formatted = await Promise.all(overdue.slice(0, limit).map(formatTask));
      sections.push({ name: 'OVERDUE', tasks: formatted });
      break;
    }

    case 'all':
    default: {
      const incomplete = allTasks.filter(t => !(t.metadata?.isCompleted));
      incomplete.sort((a, b) => {
        const pDiff = (PRIORITY_ORDER[a.metadata?.priority ?? 'medium'] ?? 2) - (PRIORITY_ORDER[b.metadata?.priority ?? 'medium'] ?? 2);
        if (pDiff !== 0) return pDiff;
        const aDate = getTaskDate(a.metadata || {}) ?? '9999-12-31';
        const bDate = getTaskDate(b.metadata || {}) ?? '9999-12-31';
        return aDate.localeCompare(bDate);
      });
      const formatted = await Promise.all(incomplete.slice(0, limit).map(formatTask));
      sections.push({ name: 'ALL', tasks: formatted });
      break;
    }
  }

  const totalCount = sections.reduce((sum, s) => sum + s.tasks.length, 0);

  return jsonEncode({
    list,
    sections,
    totalCount,
  });
}

/**
 * Lazy recurrence generation: find recurring templates that should fire today
 * but don't yet have a today instance. Create the instance on the fly.
 */
async function generateTodayRecurrenceInstances(allTasks: Atom[], today: string): Promise<void> {
  const templates = allTasks.filter(t => isRecurringTemplate(t.metadata || {}));
  if (templates.length === 0) return;

  // Find all existing instances for today
  const todayInstances = allTasks.filter(t => {
    const meta = t.metadata || {};
    return !!meta.recurrenceParentUUID && getTaskDate(meta) === today;
  });
  const instanceParentUUIDs = new Set(todayInstances.map(t => t.metadata?.recurrenceParentUUID));

  for (const template of templates) {
    // Skip if today instance already exists
    if (instanceParentUUIDs.has(template.uuid)) continue;

    // Parse recurrence rule
    const meta = template.metadata || {};
    let rule: RecurrenceRule;
    try {
      rule = typeof meta.recurrence === 'string' ? JSON.parse(meta.recurrence) : meta.recurrence;
    } catch {
      continue;
    }

    if (shouldRecurrenceFire(rule, today)) {
      await createRecurrenceInstance(template, today);
    }
  }
}

// ============================================================
// 3. complete_task
// ============================================================

export async function completeTask(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const task = await fetchAtom(uuid);
  if (!task) return jsonError(`Task not found: ${uuid}`);

  const meta = task.metadata || {};

  // If this is a recurring template, complete today's instance instead
  if (isRecurringTemplate(meta)) {
    const today = todayDateString();

    // Find today's instance
    const allTasks = await fetchAllByType('task', { limit: 500 });
    let todayInstance = allTasks.find(t => {
      const m = t.metadata || {};
      return m.recurrenceParentUUID === uuid && getTaskDate(m) === today;
    });

    // Create instance if it doesn't exist
    if (!todayInstance) {
      todayInstance = await createRecurrenceInstance(task, today) ?? undefined;
      if (!todayInstance) return jsonError('Failed to create recurring instance for today');
    }

    const updated = await updateAtom(todayInstance.uuid, {
      metadata: {
        isCompleted: true,
        completedAt: new Date().toISOString(),
      },
    });

    if (!updated) return jsonError('Failed to complete recurring task instance');

    return jsonEncode({
      success: true,
      uuid: todayInstance.uuid,
      templateUUID: uuid,
      title: task.title,
      message: `Completed today's instance of recurring task: "${task.title}"`,
    });
  }

  // Regular task completion
  const updated = await updateAtom(uuid, {
    metadata: {
      isCompleted: true,
      completedAt: new Date().toISOString(),
    },
  });

  if (!updated) return jsonError(`Failed to complete task: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    message: `Task completed: "${updated.title}"`,
  });
}

// ============================================================
// 4. uncomplete_task
// ============================================================

export async function uncompleteTask(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const task = await fetchAtom(uuid);
  if (!task) return jsonError(`Task not found: ${uuid}`);

  const updated = await updateAtom(uuid, {
    metadata: {
      isCompleted: false,
      completedAt: null,
    },
  });

  if (!updated) return jsonError(`Failed to uncomplete task: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    message: `Task uncompleted: "${updated.title}"`,
  });
}

// ============================================================
// 5. reschedule_task
// ============================================================

export async function rescheduleTask(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  const when = args.when as string;
  if (!uuid) return jsonError('uuid is required');
  if (!when) return jsonError('when is required (date string or "someday"/"anytime")');

  const task = await fetchAtom(uuid);
  if (!task) return jsonError(`Task not found: ${uuid}`);

  const lowerWhen = when.toLowerCase().trim();

  // Handle scheduling states
  if (lowerWhen === 'someday') {
    const updated = await updateAtom(uuid, {
      metadata: {
        schedulingState: 'someday',
        dueDate: null,
        whenDate: null,
        focusDate: null,
        startTime: null,
        endTime: null,
      },
    });
    if (!updated) return jsonError(`Failed to reschedule task: ${uuid}`);
    return jsonEncode({
      success: true,
      uuid: updated.uuid,
      title: updated.title,
      schedulingState: 'someday',
      message: `Task moved to Someday: "${updated.title}"`,
    });
  }

  if (lowerWhen === 'anytime') {
    const updated = await updateAtom(uuid, {
      metadata: {
        schedulingState: 'anytime',
        dueDate: null,
        whenDate: null,
        focusDate: null,
        startTime: null,
        endTime: null,
      },
    });
    if (!updated) return jsonError(`Failed to reschedule task: ${uuid}`);
    return jsonEncode({
      success: true,
      uuid: updated.uuid,
      title: updated.title,
      schedulingState: 'anytime',
      message: `Task moved to Anytime: "${updated.title}"`,
    });
  }

  // Resolve date expression
  const resolved = resolveDate(when) ?? when;
  // Validate it looks like a date
  if (!/^\d{4}-\d{2}-\d{2}/.test(resolved)) {
    return jsonError(`Could not resolve date: "${when}"`);
  }
  const dateOnly = resolved.split('T')[0];

  const updated = await updateAtom(uuid, {
    metadata: {
      dueDate: dateOnly,
      whenDate: dateOnly,
      focusDate: dateOnly,
      schedulingState: null,
    },
  });

  if (!updated) return jsonError(`Failed to reschedule task: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    dueDate: dateOnly,
    message: `Task rescheduled to ${dateOnly}: "${updated.title}"`,
  });
}

// ============================================================
// 6. update_task
// ============================================================

export async function updateTask(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  const task = await fetchAtom(uuid);
  if (!task) return jsonError(`Task not found: ${uuid}`);

  const updates: Partial<Pick<Atom, 'title' | 'body' | 'metadata' | 'links'>> = {};
  const metaUpdates: Record<string, any> = {};

  // Direct fields
  if (args.title != null) updates.title = args.title;
  if (args.body != null) updates.body = args.body;

  // Metadata fields
  if (args.priority != null) metaUpdates.priority = args.priority;
  if (args.intent != null) metaUpdates.intent = args.intent;
  if (args.dueDate != null) {
    const resolved = resolveDate(args.dueDate) ?? args.dueDate;
    const dateOnly = resolved.split('T')[0];
    metaUpdates.dueDate = dateOnly;
    metaUpdates.whenDate = dateOnly;
    metaUpdates.focusDate = dateOnly;
  }
  if (args.timeOfDay != null) metaUpdates.timeOfDay = args.timeOfDay;
  if (args.schedulingState != null) metaUpdates.schedulingState = args.schedulingState;
  if (args.startTime != null) metaUpdates.startTime = args.startTime;
  if (args.endTime != null) metaUpdates.endTime = args.endTime;
  if (args.headingUUID != null) metaUpdates.headingUUID = args.headingUUID;
  if (args.manualSortOrder != null) metaUpdates.manualSortOrder = args.manualSortOrder;

  // Checklist handling
  if (args.checklist != null && Array.isArray(args.checklist)) {
    const existingMeta = task.metadata || {};
    let existingItems: any[] = [];
    if (existingMeta.checklist) {
      try {
        existingItems = typeof existingMeta.checklist === 'string'
          ? JSON.parse(existingMeta.checklist)
          : existingMeta.checklist;
      } catch { /* ignore */ }
    }
    const existingMap = new Map(existingItems.map((item: any) => [item.id, item]));

    const mergedItems = args.checklist.map((item: any, index: number) => {
      if (item.id && existingMap.has(item.id)) {
        // Update existing item
        const existing = existingMap.get(item.id);
        return {
          ...existing,
          ...(item.title != null ? { title: item.title } : {}),
          ...(item.isCompleted != null ? { isCompleted: item.isCompleted } : {}),
          sortOrder: item.sortOrder ?? index,
        };
      }
      // New item
      return {
        id: uuidv4().toUpperCase(),
        title: item.title ?? '',
        isCompleted: item.isCompleted ?? false,
        sortOrder: item.sortOrder ?? index,
      };
    });

    metaUpdates.checklist = JSON.stringify(mergedItems);
  }

  // Project link
  if (args.projectName != null) {
    const resolved = await resolveProjectByName(args.projectName);
    if (resolved) {
      updates.links = [{ type: 'project', uuid: resolved.uuid, entityType: 'project' }];
    }
  }

  if (Object.keys(metaUpdates).length > 0) {
    updates.metadata = metaUpdates;
  }

  if (Object.keys(updates).length === 0) {
    return jsonError('No updates provided');
  }

  const updated = await updateAtom(uuid, updates);
  if (!updated) return jsonError(`Failed to update task: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    message: `Task updated: "${updated.title}"`,
  });
}

// ============================================================
// 7. set_task_recurrence
// ============================================================

export async function setTaskRecurrence(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  const recurrenceInput = args.recurrence as string | Record<string, any>;
  if (!uuid) return jsonError('uuid is required');
  if (recurrenceInput == null) return jsonError('recurrence is required (object, NLP string, or "none")');

  const task = await fetchAtom(uuid);
  if (!task) return jsonError(`Task not found: ${uuid}`);

  // Handle removal
  if (typeof recurrenceInput === 'string' && recurrenceInput.toLowerCase().trim() === 'none') {
    const updated = await updateAtom(uuid, {
      metadata: { recurrence: null },
    });
    if (!updated) return jsonError(`Failed to remove recurrence: ${uuid}`);
    return jsonEncode({
      success: true,
      uuid: updated.uuid,
      title: updated.title,
      recurrence: null,
      message: `Recurrence removed from: "${updated.title}"`,
    });
  }

  // Parse recurrence — either an object or NLP string
  let rule: RecurrenceRule;
  if (typeof recurrenceInput === 'string') {
    // Use taskParser to extract recurrence from NLP
    const parsed = parseTaskInput(recurrenceInput);
    if (!parsed.recurrenceRule) {
      return jsonError(`Could not parse recurrence from: "${recurrenceInput}"`);
    }
    rule = parsed.recurrenceRule;
  } else {
    rule = recurrenceInput as RecurrenceRule;
  }

  const ruleJson = JSON.stringify(rule);
  const description = formatRecurrenceDescription(rule);

  const updated = await updateAtom(uuid, {
    metadata: { recurrence: ruleJson },
  });

  if (!updated) return jsonError(`Failed to set recurrence: ${uuid}`);

  return jsonEncode({
    success: true,
    uuid: updated.uuid,
    title: updated.title,
    recurrence: description,
    recurrenceRule: rule,
    message: `Recurrence set to "${description}" for: "${updated.title}"`,
  });
}

// ============================================================
// 8. get_recurring_tasks
// ============================================================

export async function getRecurringTasks(args: Record<string, any>): Promise<string> {
  const allTasks = await fetchAllByType('task', { limit: 500 });

  const templates = allTasks.filter(t => isRecurringTemplate(t.metadata || {}));

  const formatted = await Promise.all(templates.map(async (task) => {
    const meta = task.metadata || {};
    let rule: RecurrenceRule | null = null;
    try {
      rule = typeof meta.recurrence === 'string' ? JSON.parse(meta.recurrence) : meta.recurrence;
    } catch { /* ignore */ }

    const base = await formatTask(task);
    return {
      ...base,
      recurrenceDescription: rule ? formatRecurrenceDescription(rule) : 'Unknown',
      recurrenceRule: rule,
    };
  }));

  return jsonEncode({
    templates: formatted,
    count: formatted.length,
    message: formatted.length > 0
      ? `${formatted.length} recurring task template${formatted.length === 1 ? '' : 's'}`
      : 'No recurring tasks found',
  });
}
