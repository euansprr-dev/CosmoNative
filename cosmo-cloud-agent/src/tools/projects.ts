// cosmo-cloud-agent/src/tools/projects.ts
// Project management tools — 4 tools for project CRUD and task organization
// PORTING SOURCE: AgentToolExecutor.swift project-related handlers

import { fetchAtom, fetchAllByType, createAtom, updateAtom, Atom } from '../db/queries';
import { jsonEncode, jsonError } from '../agent/toolExecutor';
import { v4 as uuidv4 } from 'uuid';

// ============================================================
// Helpers
// ============================================================

interface Heading {
  id: string;
  title: string;
  sortOrder: number;
  isCollapsed: boolean;
}

/**
 * Parse headings from project metadata.
 * Handles both JSON string (from Swift GRDB) and native object (from Postgres JSONB).
 */
function parseHeadings(raw: any): Heading[] {
  if (!raw) return [];
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw) as Heading[];
    } catch {
      return [];
    }
  }
  if (Array.isArray(raw)) return raw as Heading[];
  return [];
}

/**
 * Check if a task atom has a project link matching the given project UUID.
 */
function taskBelongsToProject(task: Atom, projectUUID: string): boolean {
  if (!task.links || !Array.isArray(task.links)) return false;
  return task.links.some(l => l.type === 'project' && l.uuid === projectUUID);
}

// ============================================================
// 1. get_projects
// Fetch all active (non-deleted, non-completed) projects with task counts.
// ============================================================

export async function getProjects(_args: Record<string, any>): Promise<string> {
  const allProjects = await fetchAllByType('project');

  // Filter to non-completed projects
  const activeProjects = allProjects.filter(p => {
    const meta = p.metadata || {};
    return !meta.isCompleted;
  });

  // Fetch all tasks once for counting
  const allTasks = await fetchAllByType('task', { limit: 5000 });

  const projects = activeProjects.map(p => {
    const meta = p.metadata || {};
    const headings = parseHeadings(meta.headings);

    // Count tasks linked to this project
    const projectTasks = allTasks.filter(t => taskBelongsToProject(t, p.uuid));
    const taskCount = projectTasks.length;
    const completedTaskCount = projectTasks.filter(t => {
      const tm = t.metadata || {};
      return tm.isCompleted === true;
    }).length;

    return {
      uuid: p.uuid,
      title: p.title,
      color: meta.color ?? '#2D6A4F',
      taskCount,
      completedTaskCount,
      headings: headings.map(h => ({ id: h.id, title: h.title })),
      deadline: meta.deadline ?? null,
      areaUUID: meta.areaUUID ?? null,
    };
  });

  return jsonEncode({
    projects,
    count: projects.length,
  });
}

// ============================================================
// 2. get_project_tasks
// Fetch all tasks for a project, grouped by heading.
// ============================================================

export async function getProjectTasks(args: Record<string, any>): Promise<string> {
  const uuid = args.uuid as string;
  if (!uuid) return jsonError('uuid is required');

  // Fetch the project atom
  const project = await fetchAtom(uuid);
  if (!project) return jsonError(`Project not found: ${uuid}`);
  if (project.type !== 'project') return jsonError(`Atom ${uuid} is not a project`);

  const meta = project.metadata || {};
  const headings = parseHeadings(meta.headings);

  // Fetch all tasks and filter to this project
  const allTasks = await fetchAllByType('task', { limit: 5000 });
  const projectTasks = allTasks.filter(t => taskBelongsToProject(t, uuid));

  // Build heading lookup
  const headingMap = new Map<string, Heading>();
  for (const h of headings) {
    headingMap.set(h.id, h);
  }

  // Group tasks by headingUUID
  const grouped = new Map<string, Atom[]>();
  const ungrouped: Atom[] = [];

  for (const task of projectTasks) {
    const tm = task.metadata || {};
    const headingUUID = tm.headingUUID as string | undefined;

    if (headingUUID && headingMap.has(headingUUID)) {
      const group = grouped.get(headingUUID) || [];
      group.push(task);
      grouped.set(headingUUID, group);
    } else {
      ungrouped.push(task);
    }
  }

  // Sort tasks within each group by manualSortOrder then priority
  const priorityRank: Record<string, number> = {
    critical: 0,
    high: 1,
    medium: 2,
    low: 3,
    none: 4,
  };

  function sortTasks(tasks: Atom[]): Atom[] {
    return tasks.sort((a, b) => {
      const am = a.metadata || {};
      const bm = b.metadata || {};
      const aSort = (am.manualSortOrder as number) ?? 999999;
      const bSort = (bm.manualSortOrder as number) ?? 999999;
      if (aSort !== bSort) return aSort - bSort;
      const aPri = priorityRank[(am.priority as string) ?? 'none'] ?? 4;
      const bPri = priorityRank[(bm.priority as string) ?? 'none'] ?? 4;
      return aPri - bPri;
    });
  }

  function mapTask(task: Atom) {
    const tm = task.metadata || {};
    return {
      uuid: task.uuid,
      title: task.title,
      priority: tm.priority ?? 'none',
      intent: tm.intent ?? null,
      isCompleted: tm.isCompleted === true,
      dueDate: tm.dueDate ?? null,
    };
  }

  // Build groups in heading sort order, then ungrouped last
  const sortedHeadings = [...headings].sort((a, b) => a.sortOrder - b.sortOrder);

  const groups: Array<{ headingTitle: string; headingUUID: string | null; tasks: any[] }> = [];

  for (const heading of sortedHeadings) {
    const tasks = grouped.get(heading.id) || [];
    groups.push({
      headingTitle: heading.title,
      headingUUID: heading.id,
      tasks: sortTasks(tasks).map(mapTask),
    });
  }

  // Add ungrouped tasks
  if (ungrouped.length > 0) {
    groups.push({
      headingTitle: 'Ungrouped',
      headingUUID: null,
      tasks: sortTasks(ungrouped).map(mapTask),
    });
  }

  return jsonEncode({
    project: {
      uuid: project.uuid,
      title: project.title,
      color: meta.color ?? '#2D6A4F',
      deadline: meta.deadline ?? null,
    },
    groups,
    totalTasks: projectTasks.length,
  });
}

// ============================================================
// 3. create_project
// Create a new project atom with optional headings.
// ============================================================

export async function createProject(args: Record<string, any>): Promise<string> {
  const title = args.title as string;
  if (!title) return jsonError('title is required');

  const color = (args.color as string) || '#2D6A4F';
  const areaUUID = args.areaUUID as string | undefined;
  const deadline = args.deadline as string | undefined;
  const notes = args.notes as string | undefined;
  const headingTitles = (args.headings as string[] | undefined) || [];

  // Build headings array
  const headings: Heading[] = headingTitles.map((ht, index) => ({
    id: uuidv4().toUpperCase(),
    title: ht,
    sortOrder: index,
    isCollapsed: false,
  }));

  const atom = await createAtom({
    type: 'project',
    title,
    body: notes ?? null,
    metadata: {
      color,
      ...(areaUUID ? { areaUUID } : {}),
      ...(deadline ? { deadline } : {}),
      ...(notes ? { projectNotes: notes } : {}),
      isCompleted: false,
      isTemporary: false,
      headings: JSON.stringify(headings),
    },
  });

  if (!atom) return jsonError('Failed to create project');

  return jsonEncode({
    success: true,
    uuid: atom.uuid,
    title: atom.title,
    color,
    headingCount: headings.length,
    message: `Project created: "${title}"${headings.length > 0 ? ` with ${headings.length} heading(s)` : ''}`,
  });
}

// ============================================================
// 4. move_task_to_project
// Move a task to a project, optionally into a specific heading.
// ============================================================

export async function moveTaskToProject(args: Record<string, any>): Promise<string> {
  const taskUUID = args.taskUUID as string;
  const projectUUID = args.projectUUID as string;
  const headingUUID = args.headingUUID as string | undefined;

  if (!taskUUID) return jsonError('taskUUID is required');
  if (!projectUUID) return jsonError('projectUUID is required');

  // Fetch task
  const task = await fetchAtom(taskUUID);
  if (!task) return jsonError(`Task not found: ${taskUUID}`);
  if (task.type !== 'task') return jsonError(`Atom ${taskUUID} is not a task`);

  // Fetch project (for name and heading validation)
  const project = await fetchAtom(projectUUID);
  if (!project) return jsonError(`Project not found: ${projectUUID}`);
  if (project.type !== 'project') return jsonError(`Atom ${projectUUID} is not a project`);

  const projectMeta = project.metadata || {};
  const headings = parseHeadings(projectMeta.headings);

  // Validate heading if provided
  let headingName: string | null = null;
  if (headingUUID) {
    const heading = headings.find(h => h.id === headingUUID);
    if (!heading) return jsonError(`Heading not found: ${headingUUID} in project "${project.title}"`);
    headingName = heading.title;
  }

  // Remove existing project links from the task's links array
  const currentLinks = task.links || [];
  const filteredLinks = currentLinks.filter(l => l.type !== 'project');

  // Add new project link
  filteredLinks.push({ type: 'project', uuid: projectUUID, entityType: 'project' });

  // Build metadata updates
  const metadataUpdates: Record<string, any> = {};
  if (headingUUID) {
    metadataUpdates.headingUUID = headingUUID;
  }

  // Direct update — we need to REPLACE links, not merge, so use supabase directly
  // But updateAtom merges links by default. We need to set the full links array.
  // Workaround: fetch + full update via updateAtom with the complete links set.
  // Since updateAtom appends new links and keeps existing ones, we must work around
  // the merge behavior by setting links on the atom manually.

  // We'll use a two-step approach: clear project links via raw update, then set new ones
  // Actually, the simplest approach: use updateAtom's metadata merge + handle links specially

  // Import supabase for direct link replacement
  const { supabase, userId } = await import('../db/client');

  const updatePayload: Record<string, any> = {
    links: filteredLinks,
    updated_at: new Date().toISOString(),
    _source: 'cloud',
  };

  // Merge metadata
  const existingMeta = task.metadata || {};
  if (Object.keys(metadataUpdates).length > 0) {
    updatePayload.metadata = { ...existingMeta, ...metadataUpdates };
  }

  const { error } = await supabase
    .from('atoms')
    .update(updatePayload)
    .eq('uuid', taskUUID)
    .eq('user_id', userId);

  if (error) return jsonError(`Failed to move task: ${error.message}`);

  // Increment version
  await supabase.rpc('increment_atom_version', { atom_uuid: taskUUID });

  return jsonEncode({
    success: true,
    taskUUID,
    projectName: project.title,
    headingName,
    message: `Moved "${task.title}" to project "${project.title}"${headingName ? ` under "${headingName}"` : ''}`,
  });
}
