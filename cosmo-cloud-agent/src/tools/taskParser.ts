// cosmo-cloud-agent/src/tools/taskParser.ts
// Line-by-line TypeScript port of Canvas/CommandCenter/TaskInputParser.swift
// Natural language task input parser — extracts priority, dates, times, intents, and recurrence

// MARK: - Interfaces

export interface RecurrenceRule {
  frequency: 'daily' | 'weekly' | 'biweekly' | 'monthly' | 'yearly' | 'weekdays' | 'custom';
  interval: number;
  daysOfWeek: number[] | null;    // 1=Sun, 2=Mon, ..., 7=Sat
  dayOfMonth: number | null;
  endCondition: { type: 'never' } | { type: 'afterOccurrences'; value: number } | { type: 'onDate'; value: string };
}

export interface ParsedTaskInput {
  title: string;
  priority: 'low' | 'medium' | 'high' | 'critical' | null;
  dueDate: string | null;        // ISO8601 yyyy-MM-dd
  scheduledTime: string | null;   // HH:mm (24h)
  intent: string | null;
  recurrenceRule: RecurrenceRule | null;
  projectName: string | null;
  headingName: string | null;
  timeOfDay: 'morning' | 'evening' | null;
  schedulingState: 'anytime' | 'someday' | null;
  deadline: string | null;        // ISO8601 yyyy-MM-dd
}

// MARK: - Timezone Helper

const TIMEZONE = process.env.TIMEZONE || 'UTC';

/** Get "now" in the configured timezone, returned as a Date whose UTC values represent local wall-clock time. */
function getNow(): Date {
  const now = new Date();
  const localeStr = now.toLocaleString('en-US', { timeZone: TIMEZONE });
  return new Date(localeStr);
}

/** Format a Date (interpreted as local wall-clock) to ISO date string yyyy-MM-dd */
function formatDate(d: Date): string {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** Format a Date's time portion to HH:mm (24h) */
function formatTime(d: Date): string {
  const hours = String(d.getHours()).padStart(2, '0');
  const minutes = String(d.getMinutes()).padStart(2, '0');
  return `${hours}:${minutes}`;
}

/** Add days to a date */
function addDays(d: Date, days: number): Date {
  const result = new Date(d);
  result.setDate(result.getDate() + days);
  return result;
}

/** Add months to a date */
function addMonths(d: Date, months: number): Date {
  const result = new Date(d);
  result.setMonth(result.getMonth() + months);
  return result;
}

/** Add weeks to a date */
function addWeeks(d: Date, weeks: number): Date {
  return addDays(d, weeks * 7);
}

/** Get start of day (midnight) */
function startOfDay(d: Date): Date {
  const result = new Date(d);
  result.setHours(0, 0, 0, 0);
  return result;
}

// MARK: - RecurrenceRule Convenience Factories

function dailyRule(interval: number = 1): RecurrenceRule {
  return {
    frequency: 'daily',
    interval,
    daysOfWeek: null,
    dayOfMonth: null,
    endCondition: { type: 'never' },
  };
}

function weekdaysRule(): RecurrenceRule {
  return {
    frequency: 'weekdays',
    interval: 1,
    daysOfWeek: [2, 3, 4, 5, 6], // Mon-Fri in Swift DayOfWeek encoding
    dayOfMonth: null,
    endCondition: { type: 'never' },
  };
}

function weeklyRule(days: number[]): RecurrenceRule {
  return {
    frequency: 'weekly',
    interval: 1,
    daysOfWeek: days,
    dayOfMonth: null,
    endCondition: { type: 'never' },
  };
}

function monthlyRule(onDay: number): RecurrenceRule {
  return {
    frequency: 'monthly',
    interval: 1,
    daysOfWeek: null,
    dayOfMonth: onDay,
    endCondition: { type: 'never' },
  };
}

// MARK: - Extraction Functions

/** Extract /someday or /anytime from input */
function extractSchedulingState(input: string): { value: 'someday' | 'anytime' | null; remaining: string } {
  const patterns: [RegExp, 'someday' | 'anytime'][] = [
    [/\/someday\b/i, 'someday'],
    [/\/anytime\b/i, 'anytime'],
  ];

  for (const [pattern, state] of patterns) {
    const match = input.match(pattern);
    if (match) {
      return { value: state, remaining: input.replace(pattern, '') };
    }
  }
  return { value: null, remaining: input };
}

/** Extract /morning, /am, /evening, /eve from input */
function extractTimeOfDay(input: string): { value: 'morning' | 'evening' | null; remaining: string } {
  const patterns: [RegExp, 'morning' | 'evening'][] = [
    [/\/morning\b/i, 'morning'],
    [/\/am\b/i, 'morning'],
    [/\/evening\b/i, 'evening'],
    [/\/eve\b/i, 'evening'],
  ];

  for (const [pattern, timeOfDay] of patterns) {
    const match = input.match(pattern);
    if (match) {
      return { value: timeOfDay, remaining: input.replace(pattern, '') };
    }
  }
  return { value: null, remaining: input };
}

/** Extract #projectname from input */
function extractProjectTag(input: string): { value: string | null; remaining: string } {
  const regex = /#(\S+)/;
  const match = input.match(regex);
  if (match) {
    const name = match[1];
    return { value: name, remaining: input.replace(match[0], '') };
  }
  return { value: null, remaining: input };
}

/** Extract +heading from input */
function extractHeadingTag(input: string): { value: string | null; remaining: string } {
  const regex = /\+(\S+)/;
  const match = input.match(regex);
  if (match) {
    const name = match[1];
    return { value: name, remaining: input.replace(match[0], '') };
  }
  return { value: null, remaining: input };
}

/** Extract "deadline: friday" or "deadline: mar 15" from input */
function extractDeadline(input: string): { value: string | null; remaining: string } {
  const regex = /\bdeadline:\s*(\S+(?:\s+\d{1,2})?)/i;
  const match = input.match(regex);
  if (match) {
    const dateStr = match[1];
    const remaining = input.replace(match[0], '');
    // Try to parse the deadline date expression using extractDate
    const parsed = extractDate(dateStr);
    return { value: parsed.value, remaining };
  }
  return { value: null, remaining: input };
}

/** Extract priority (p1/p2/p3/p4/!1/!!/!) from input */
function extractPriority(input: string): { value: 'low' | 'medium' | 'high' | 'critical' | null; remaining: string } {
  const patterns: [RegExp, 'low' | 'medium' | 'high' | 'critical'][] = [
    [/\bp1\b/, 'critical'],
    [/\bp2\b/, 'high'],
    [/\bp3\b/, 'medium'],
    [/\bp4\b/, 'low'],
    [/\b!1\b/, 'critical'],
    [/\b!!\b/, 'high'],
    [/\b!\b/, 'medium'],
  ];

  for (const [pattern, priority] of patterns) {
    const match = input.match(pattern);
    if (match) {
      return { value: priority, remaining: input.replace(pattern, '') };
    }
  }
  return { value: null, remaining: input };
}

/** Extract intent keywords — detect only, do NOT remove from title */
function extractIntent(input: string): { value: string | null; remaining: string } {
  const keywords: [RegExp, string][] = [
    [/\bwrite\b/i, 'writeContent'],
    [/\bwriting\b/i, 'writeContent'],
    [/\bdraft\b/i, 'writeContent'],
    [/\bresearch\b/i, 'research'],
    [/\bstudy\b/i, 'studySwipes'],
    [/\bswipe\b/i, 'studySwipes'],
    [/\bthink\b/i, 'deepThink'],
    [/\breview\b/i, 'review'],
  ];

  for (const [pattern, intent] of keywords) {
    const match = input.match(pattern);
    if (match) {
      // Check if it's at the start or preceded by space (matching Swift logic)
      const idx = match.index!;
      const isAtStart = idx === 0;
      const isAfterSpace = !isAtStart && input[idx - 1] === ' ';

      if (isAtStart || isAfterSpace) {
        // Don't remove intent keywords from title — they might be part of task name
        return { value: intent, remaining: input };
      }
    }
  }
  return { value: null, remaining: input };
}

/** Map a day-name token to Swift DayOfWeek rawValue (1=Sun...7=Sat) */
function weekdayFromToken(token: string): number | null {
  switch (token) {
    case 'mon': case 'monday':
      return 2;
    case 'tue': case 'tues': case 'tuesday':
      return 3;
    case 'wed': case 'weds': case 'wednesday':
      return 4;
    case 'thu': case 'thur': case 'thurs': case 'thursday':
      return 5;
    case 'fri': case 'friday':
      return 6;
    case 'sat': case 'saturday':
      return 7;
    case 'sun': case 'sunday':
      return 1;
    default:
      return null;
  }
}

/** Parse a weekday list string like "mon wed fri" or "monday, wednesday, and friday" into DayOfWeek values */
function parseWeekdayList(input: string): number[] {
  const normalized = input
    .toLowerCase()
    .replace(/and/g, ',')
    .replace(/\./g, '');

  const parts = normalized
    .split(',')
    .flatMap((chunk) => chunk.trim().split(/\s+/));

  const days: number[] = [];
  for (const part of parts) {
    const day = weekdayFromToken(part);
    if (day !== null && !days.includes(day)) {
      days.push(day);
    }
  }
  return days;
}

/** Extract recurrence phrases from input */
function extractRecurrence(input: string): { value: RecurrenceRule | null; remaining: string } {
  const today = getNow();
  const currentDayOfMonth = today.getDate();

  const patterns: [RegExp, RecurrenceRule][] = [
    [/\bevery\s+day\b/i, dailyRule()],
    [/\bdaily\b/i, dailyRule()],
    [/\bevery\s+weekdays?\b/i, weekdaysRule()],
    [/\bweekdays?\b/i, weekdaysRule()],
    [/\bevery\s+month\b/i, monthlyRule(currentDayOfMonth)],
  ];

  for (const [pattern, rule] of patterns) {
    const match = input.match(pattern);
    if (match) {
      return { value: rule, remaining: input.replace(match[0], '') };
    }
  }

  // Complex: "every mon wed fri"
  const complexRegex = /\bevery\s+((?:(?:mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|thur(?:s|sday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?:\s*(?:,|and)\s*|\s+)?)+)/i;
  const complexMatch = input.match(complexRegex);
  if (complexMatch) {
    const daysString = complexMatch[1];
    const days = parseWeekdayList(daysString);
    if (days.length > 0) {
      return { value: weeklyRule(days), remaining: input.replace(complexMatch[0], '') };
    }
  }

  return { value: null, remaining: input };
}

/** Parse a time string like "2pm", "2:30pm", "14:00" into hours and minutes */
function parseTimeString(str: string): { hour: number; minute: number } | null {
  const cleaned = str.trim().toLowerCase();

  // Try h:mm am/pm (e.g. "2:30pm", "2:30 pm")
  let match = cleaned.match(/^(\d{1,2}):(\d{2})\s*(am|pm)$/);
  if (match) {
    let hour = parseInt(match[1], 10);
    const minute = parseInt(match[2], 10);
    const ampm = match[3];
    if (ampm === 'pm' && hour !== 12) hour += 12;
    if (ampm === 'am' && hour === 12) hour = 0;
    return { hour, minute };
  }

  // Try h am/pm (e.g. "2pm", "2 pm")
  match = cleaned.match(/^(\d{1,2})\s*(am|pm)$/);
  if (match) {
    let hour = parseInt(match[1], 10);
    const ampm = match[2];
    if (ampm === 'pm' && hour !== 12) hour += 12;
    if (ampm === 'am' && hour === 12) hour = 0;
    return { hour, minute: 0 };
  }

  // Try HH:mm 24h (e.g. "14:00", "9:30")
  match = cleaned.match(/^(\d{1,2}):(\d{2})$/);
  if (match) {
    const hour = parseInt(match[1], 10);
    const minute = parseInt(match[2], 10);
    if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
      return { hour, minute };
    }
  }

  return null;
}

/** Extract time (2pm, 14:00, at 3:30pm) from input */
function extractTime(input: string): { value: string | null; remaining: string } {
  const patterns = [
    /\bat\s+(\d{1,2}:\d{2}\s*(?:am|pm))\b/i,
    /\bat\s+(\d{1,2}\s*(?:am|pm))\b/i,
    /\bat\s+(\d{1,2}:\d{2})\b/i,
    /\b(\d{1,2}:\d{2}\s*(?:am|pm))\b/i,
    /\b(\d{1,2}(?:am|pm))\b/i,
  ];

  for (const pattern of patterns) {
    const match = input.match(pattern);
    if (match) {
      const timeStr = match[1];
      const parsed = parseTimeString(timeStr);
      if (parsed) {
        const remaining = input.replace(match[0], '');
        const formatted = `${String(parsed.hour).padStart(2, '0')}:${String(parsed.minute).padStart(2, '0')}`;
        return { value: formatted, remaining };
      }
    }
  }

  return { value: null, remaining: input };
}

/** Map month abbreviation to 0-indexed month number (JS Date convention) */
function monthFromAbbreviation(str: string): number | null {
  const months: Record<string, number> = {
    jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
    jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
  };
  const prefix = str.substring(0, 3).toLowerCase();
  return months[prefix] ?? null;
}

/** Convert JS Date.getDay() (0=Sun) to Swift Calendar weekday (1=Sun) */
function jsWeekdayToSwift(jsDay: number): number {
  // JS: 0=Sun, 1=Mon, ... 6=Sat
  // Swift Calendar: 1=Sun, 2=Mon, ... 7=Sat
  return jsDay + 1;
}

/** Find next occurrence of a weekday from a given date.
 *  weekday uses Swift Calendar encoding: 1=Sun, 2=Mon, ..., 7=Sat
 *  Always returns a future date (never today). Matches Swift's nextWeekday() which uses daysAhead <= 0 → +7.
 */
function nextWeekday(targetSwiftDay: number, from: Date): Date {
  const currentSwiftDay = jsWeekdayToSwift(from.getDay());
  let daysAhead = targetSwiftDay - currentSwiftDay;
  if (daysAhead <= 0) daysAhead += 7;
  return addDays(from, daysAhead);
}

/** Extract date (today, tomorrow, monday, next week, mar 15, 3/15, in 3 days) from input */
function extractDate(input: string): { value: string | null; remaining: string } {
  const today = getNow();

  // Named dates — order matches Swift exactly
  const namedDates: [RegExp, Date | null][] = [
    [/\btoday\b/i, today],
    [/\btomorrow\b/i, addDays(today, 1)],
    [/\bnext week\b/i, addWeeks(today, 1)],
    [/\bmonday\b/i, nextWeekday(2, today)],
    [/\btuesday\b/i, nextWeekday(3, today)],
    [/\bwednesday\b/i, nextWeekday(4, today)],
    [/\bthursday\b/i, nextWeekday(5, today)],
    [/\bfriday\b/i, nextWeekday(6, today)],
    [/\bsaturday\b/i, nextWeekday(7, today)],
    [/\bsunday\b/i, nextWeekday(1, today)],
  ];

  for (const [pattern, date] of namedDates) {
    const match = input.match(pattern);
    if (match && date) {
      return { value: formatDate(date), remaining: input.replace(match[0], '') };
    }
  }

  // "in X days"
  const inDaysRegex = /\bin\s+(\d+)\s+days?\b/i;
  const inDaysMatch = input.match(inDaysRegex);
  if (inDaysMatch) {
    const days = parseInt(inDaysMatch[1], 10);
    const date = addDays(today, days);
    return { value: formatDate(date), remaining: input.replace(inDaysMatch[0], '') };
  }

  // Month day: "mar 15", "march 15"
  const namedMonthRegex = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s+(\d{1,2})\b/i;
  const namedMonthMatch = input.match(namedMonthRegex);
  if (namedMonthMatch) {
    const monthStr = namedMonthMatch[1].toLowerCase();
    const dayStr = namedMonthMatch[2];
    const month = monthFromAbbreviation(monthStr);
    const day = parseInt(dayStr, 10);

    if (month !== null) {
      const date = new Date(today.getFullYear(), month, day);
      const resultDate = date < startOfDay(today)
        ? new Date(today.getFullYear() + 1, month, day)
        : date;
      return { value: formatDate(resultDate), remaining: input.replace(namedMonthMatch[0], '') };
    }
  }

  // Numeric month/day: "3/15"
  const numericDateRegex = /\b(\d{1,2})\/(\d{1,2})\b/;
  const numericMatch = input.match(numericDateRegex);
  if (numericMatch) {
    const month = parseInt(numericMatch[1], 10) - 1; // Convert to 0-indexed
    const day = parseInt(numericMatch[2], 10);

    if (month >= 0 && month <= 11 && day >= 1 && day <= 31) {
      const date = new Date(today.getFullYear(), month, day);
      const resultDate = date < startOfDay(today)
        ? new Date(today.getFullYear() + 1, month, day)
        : date;
      return { value: formatDate(resultDate), remaining: input.replace(numericMatch[0], '') };
    }
  }

  return { value: null, remaining: input };
}

// MARK: - Next Occurrence for Recurrence Rules

/** Compute the next occurrence date for a recurrence rule from a given start date */
function nextOccurrenceDate(rule: RecurrenceRule, from: Date): string | null {
  const start = startOfDay(from);

  switch (rule.frequency) {
    case 'daily':
      return formatDate(start);

    case 'weekdays': {
      // JS getDay(): 0=Sun, 1=Mon, ..., 6=Sat
      const weekday = start.getDay();
      // Mon=1 through Fri=5
      if (weekday >= 1 && weekday <= 5) {
        return formatDate(start);
      }
      // Weekend → next Monday (Swift DayOfWeek.monday = 2)
      return formatDate(nextWeekday(2, start));
    }

    case 'weekly':
    case 'biweekly':
    case 'custom': {
      const orderedDays = (rule.daysOfWeek ?? []).slice().sort((a, b) => a - b);
      if (orderedDays.length === 0) {
        return formatDate(start);
      }

      // Swift Calendar weekday: 1=Sun, 2=Mon, ..., 7=Sat
      const currentWeekday = jsWeekdayToSwift(start.getDay());

      // Find same-or-later day this week
      const sameOrLater = orderedDays.find((d) => d >= currentWeekday);
      if (sameOrLater !== undefined) {
        const delta = sameOrLater - currentWeekday;
        return formatDate(addDays(start, delta));
      }

      // Wrap to next week
      const next = orderedDays[0];
      const delta = (7 - currentWeekday) + next;
      return formatDate(addDays(start, delta));
    }

    case 'monthly': {
      const targetDay = rule.dayOfMonth ?? start.getDate();
      const currentDay = start.getDate();

      if (currentDay <= targetDay) {
        // This month — construct date at targetDay
        const thisMonth = new Date(start.getFullYear(), start.getMonth(), targetDay);
        return formatDate(thisMonth);
      }

      // Next month
      const nextMonthStart = new Date(start.getFullYear(), start.getMonth() + 1, targetDay);
      return formatDate(nextMonthStart);
    }

    case 'yearly':
      return formatDate(start);
  }
}

// MARK: - Public API

/**
 * Resolve a natural language date expression to an ISO8601 date string.
 * Exported for reuse in reschedule_task.
 */
export function resolveDate(expression: string): string | null {
  const result = extractDate(expression);
  return result.value;
}

/**
 * Parse a natural language task input string into structured metadata.
 * Port of Swift TaskInputParser.parse(_:)
 */
export function parseTaskInput(input: string): ParsedTaskInput {
  let remaining = input;

  // 1. Extract scheduling state (/someday, /anytime)
  const scheduling = extractSchedulingState(remaining);
  remaining = scheduling.remaining;

  // 2. Extract time of day (/morning, /am, /evening, /eve)
  const tod = extractTimeOfDay(remaining);
  remaining = tod.remaining;

  // 3. Extract project tag (#projectname)
  const project = extractProjectTag(remaining);
  remaining = project.remaining;

  // 4. Extract heading tag (+heading)
  const heading = extractHeadingTag(remaining);
  remaining = heading.remaining;

  // 5. Extract deadline (deadline: friday)
  const deadlineResult = extractDeadline(remaining);
  remaining = deadlineResult.remaining;

  // 6. Extract priority (p1/p2/p3/p4/!1/!!/!)
  const priorityResult = extractPriority(remaining);
  remaining = priorityResult.remaining;

  // 7. Extract intent (detect only, do NOT remove from title)
  const intentResult = extractIntent(remaining);
  remaining = intentResult.remaining;

  // 8. Extract recurrence (every day, daily, every weekday, every mon wed fri)
  const recurrenceResult = extractRecurrence(remaining);
  remaining = recurrenceResult.remaining;

  // 9. Extract time (at 2pm, 14:00, 2:30pm)
  const timeResult = extractTime(remaining);
  remaining = timeResult.remaining;

  // 10. Extract date (today, tomorrow, next week, monday, in 3 days, mar 15, 3/15)
  const dateResult = extractDate(remaining);
  remaining = dateResult.remaining;

  let dueDate = dateResult.value;
  const scheduledTime = timeResult.value;
  const recurrenceRule = recurrenceResult.value;

  // If time extracted but no date → default to today
  if (scheduledTime !== null && dueDate === null) {
    dueDate = formatDate(getNow());
  }

  // If recurrence extracted but no date → compute next occurrence from rule
  if (recurrenceRule !== null && dueDate === null) {
    dueDate = nextOccurrenceDate(recurrenceRule, getNow());
  }

  // Clean up title: trim whitespace and collapse multiple spaces
  const title = remaining
    .trim()
    .replace(/  +/g, ' ');

  return {
    title,
    priority: priorityResult.value,
    dueDate,
    scheduledTime,
    intent: intentResult.value,
    recurrenceRule,
    projectName: project.value,
    headingName: heading.value,
    timeOfDay: tod.value,
    schedulingState: scheduling.value,
    deadline: deadlineResult.value,
  };
}
