// cosmo-cloud-agent/src/db/queries.ts
// Common database query patterns — Postgres equivalent of AtomRepository
// PORTING NOTE: Every query here mirrors an AtomRepository method in Swift.
// The user_id filter is MANDATORY on every query (service_role bypasses RLS).

import { supabase, userId } from './client';
import { v4 as uuidv4 } from 'uuid';

// ============================================================
// Types
// ============================================================

export interface Atom {
  id?: number;
  uuid: string;
  type: string;
  title: string | null;
  body: string | null;
  structured: Record<string, any> | null;
  metadata: Record<string, any> | null;
  links: Array<{ type: string; uuid: string; entityType?: string; metadata?: string }> | null;
  created_at: string;
  updated_at: string;
  is_deleted: boolean;
  user_id: string;
  _version: number;
  _source: string;
}

export interface GraphEdge {
  source_uuid: string;
  target_uuid: string;
  edge_type: string;
  link_type: string | null;
  combined_weight: number;
}

// ============================================================
// Atom CRUD
// ============================================================

/**
 * Fetch a single atom by UUID.
 * Source: AtomRepository.fetch(uuid:) in Swift
 */
export async function fetchAtom(uuid: string): Promise<Atom | null> {
  const { data, error } = await supabase
    .from('atoms')
    .select('*')
    .eq('uuid', uuid)
    .eq('user_id', userId)
    .eq('is_deleted', false)
    .single();

  if (error || !data) return null;
  return data as Atom;
}

/**
 * Fetch all atoms of a given type.
 * Source: AtomRepository.fetchAll(type:) in Swift
 */
export async function fetchAllByType(
  type: string,
  options?: { limit?: number; offset?: number; orderBy?: string; ascending?: boolean }
): Promise<Atom[]> {
  let query = supabase
    .from('atoms')
    .select('*')
    .eq('type', type)
    .eq('user_id', userId)
    .eq('is_deleted', false);

  if (options?.orderBy) {
    query = query.order(options.orderBy, { ascending: options.ascending ?? false });
  } else {
    query = query.order('updated_at', { ascending: false });
  }

  if (options?.limit) query = query.limit(options.limit);
  if (options?.offset) query = query.range(options.offset, options.offset + (options.limit || 50) - 1);

  const { data, error } = await query;
  if (error || !data) return [];
  return data as Atom[];
}

/**
 * Create a new atom.
 * Source: AtomRepository.create(_:) in Swift
 */
export async function createAtom(params: {
  type: string;
  title?: string | null;
  body?: string | null;
  structured?: Record<string, any> | null;
  metadata?: Record<string, any> | null;
  links?: Array<{ type: string; uuid: string; entityType?: string }> | null;
}): Promise<Atom | null> {
  const now = new Date().toISOString();
  const atom = {
    uuid: uuidv4().toUpperCase(),
    type: params.type,
    title: params.title ?? null,
    body: params.body ?? null,
    structured: params.structured ?? null,
    metadata: params.metadata ?? null,
    links: params.links ?? null,
    created_at: now,
    updated_at: now,
    is_deleted: false,
    user_id: userId,
    _version: 1,
    _source: 'cloud',
  };

  const { data, error } = await supabase
    .from('atoms')
    .insert(atom)
    .select()
    .single();

  if (error) {
    console.error(`❌ createAtom failed (${params.type}): ${error.message}`);
    return null;
  }
  return data as Atom;
}

/**
 * Update an existing atom by UUID.
 * Source: AtomRepository.update(_:) in Swift
 * CRITICAL: Increments _version and sets _source to 'cloud'
 */
export async function updateAtom(
  uuid: string,
  updates: Partial<Pick<Atom, 'title' | 'body' | 'structured' | 'metadata' | 'links'>>
): Promise<Atom | null> {
  // Fetch current to merge metadata/links (not overwrite)
  const current = await fetchAtom(uuid);
  if (!current) return null;

  const merged: Record<string, any> = {
    ...updates,
    updated_at: new Date().toISOString(),
    _source: 'cloud',
  };

  // Merge metadata (don't overwrite entire object, merge keys)
  if (updates.metadata && current.metadata) {
    merged.metadata = { ...current.metadata, ...updates.metadata };
  }

  // Merge links (append, don't replace)
  if (updates.links && current.links) {
    const existingTypes = new Set(current.links.map(l => `${l.type}:${l.uuid}`));
    const newLinks = updates.links.filter(l => !existingTypes.has(`${l.type}:${l.uuid}`));
    merged.links = [...current.links, ...newLinks];
  }

  const { data, error } = await supabase
    .from('atoms')
    .update(merged)
    .eq('uuid', uuid)
    .eq('user_id', userId)
    .select()
    .single();

  if (error) {
    console.error(`❌ updateAtom failed (${uuid}): ${error.message}`);
    return null;
  }

  // Increment version via raw SQL (Supabase JS can't do _version = _version + 1)
  await supabase.rpc('increment_atom_version', { atom_uuid: uuid });

  return data as Atom;
}

/**
 * Soft-delete an atom.
 * Source: AtomRepository.delete(uuid:) in Swift
 */
export async function deleteAtom(uuid: string): Promise<boolean> {
  const { error } = await supabase
    .from('atoms')
    .update({
      is_deleted: true,
      updated_at: new Date().toISOString(),
      _source: 'cloud',
    })
    .eq('uuid', uuid)
    .eq('user_id', userId);

  return !error;
}

// ============================================================
// Search
// ============================================================

/**
 * Full-text search across atoms.
 * Source: HybridSearchEngine.search() in Swift → Postgres FTS
 */
export async function searchAtoms(
  query: string,
  options?: { types?: string[]; limit?: number }
): Promise<Atom[]> {
  const limit = options?.limit ?? 20;

  // Step 1: ILIKE on title first — best for exact title matches (blueprint lookup)
  const ilikeResults = await searchAtomsILike(query, options);
  if (ilikeResults.length > 0) return ilikeResults;

  // Step 2: Fall back to FTS for keyword/semantic search
  let rpcQuery = supabase
    .from('atoms')
    .select('*')
    .eq('user_id', userId)
    .eq('is_deleted', false)
    .textSearch('fts', query, { type: 'websearch' })
    .limit(limit);

  if (options?.types && options.types.length > 0) {
    rpcQuery = rpcQuery.in('type', options.types);
  }

  const { data, error } = await rpcQuery;

  if (error || !data || data.length === 0) {
    // Step 3: ILIKE on body as last resort
    return searchAtomsBodyILike(query, options);
  }

  return (data as Atom[]) || [];
}

async function searchAtomsBodyILike(
  query: string,
  options?: { types?: string[]; limit?: number }
): Promise<Atom[]> {
  const limit = options?.limit ?? 20;
  const pattern = `%${query.substring(0, 100)}%`;

  let q = supabase
    .from('atoms')
    .select('*')
    .eq('user_id', userId)
    .eq('is_deleted', false)
    .ilike('body', pattern)
    .limit(limit)
    .order('updated_at', { ascending: false });

  if (options?.types && options.types.length > 0) {
    q = q.in('type', options.types);
  }

  const { data } = await q;
  return (data as Atom[]) || [];
}

/**
 * ILIKE fallback search (when FTS returns no results or errors).
 * Source: AtomRepository keyword search fallback in Swift
 */
async function searchAtomsILike(
  query: string,
  options?: { types?: string[]; limit?: number }
): Promise<Atom[]> {
  const limit = options?.limit ?? 20;
  const pattern = `%${query}%`;

  let q = supabase
    .from('atoms')
    .select('*')
    .eq('user_id', userId)
    .eq('is_deleted', false)
    .or(`title.ilike.${pattern},body.ilike.${pattern}`)
    .limit(limit)
    .order('updated_at', { ascending: false });

  if (options?.types && options.types.length > 0) {
    q = q.in('type', options.types);
  }

  const { data } = await q;
  return (data as Atom[]) || [];
}

// ============================================================
// Client Resolution
// ============================================================

/**
 * Fuzzy-find a client profile by name.
 * Source: AtomRepository.fuzzyFindClient(_:) in Swift
 */
export async function fuzzyFindClient(query: string): Promise<Atom | null> {
  if (!query || query.trim().length === 0) return null;

  const { data } = await supabase
    .from('atoms')
    .select('*')
    .eq('type', 'client_profile')
    .eq('user_id', userId)
    .eq('is_deleted', false);

  if (!data || data.length === 0) return null;

  const normalizedQuery = query.toLowerCase().trim();

  // Exact match first
  const exact = data.find(
    (a: any) => a.title?.toLowerCase() === normalizedQuery
  );
  if (exact) return exact as Atom;

  // Prefix match
  const prefix = data.find(
    (a: any) => a.title?.toLowerCase().startsWith(normalizedQuery)
  );
  if (prefix) return prefix as Atom;

  // Contains match
  const contains = data.find(
    (a: any) => a.title?.toLowerCase().includes(normalizedQuery)
  );
  if (contains) return contains as Atom;

  return null;
}

// ============================================================
// Swipe Helpers
// ============================================================

/**
 * Check if an atom is a swipe file (research atom with swipe analysis).
 * Source: Atom.isSwipeFileAtom extension in Swift
 */
export function isSwipeFileAtom(atom: Atom): boolean {
  if (atom.type !== 'research') return false;
  const analysis = atom.structured;
  if (!analysis) return false;
  // Swipe files have hookType or swipeAnalysis in structured
  return !!(analysis.hookType || analysis.swipeAnalysis);
}

/**
 * Get swipe analysis from an atom.
 * Source: Atom.swipeAnalysis property in Swift
 */
export function getSwipeAnalysis(atom: Atom): Record<string, any> | null {
  if (!atom.structured) return null;
  // SwipeAnalysis can be stored directly in structured or nested under swipeAnalysis key
  if (atom.structured.swipeAnalysis) return atom.structured.swipeAnalysis;
  if (atom.structured.hookType) return atom.structured;
  return null;
}

// ============================================================
// Graph Edges
// ============================================================

/**
 * Get edges for an atom.
 * Source: GraphQueryEngine.getEdges(for:) in Swift
 */
export async function getEdgesForAtom(atomUuid: string): Promise<GraphEdge[]> {
  const { data } = await supabase
    .from('graph_edges')
    .select('*')
    .eq('user_id', userId)
    .or(`source_uuid.eq.${atomUuid},target_uuid.eq.${atomUuid}`)
    .order('combined_weight', { ascending: false });

  return (data as GraphEdge[]) || [];
}

// ============================================================
// Conversations
// ============================================================

/**
 * Load conversation for a chat.
 * Source: ConversationMemoryService.loadConversation() in Swift
 */
export async function loadConversation(chatId: string): Promise<any | null> {
  const { data } = await supabase
    .from('agent_conversations')
    .select('*')
    .eq('user_id', userId)
    .eq('chat_id', chatId)
    .order('updated_at', { ascending: false })
    .limit(1)
    .single();

  return data;
}

/**
 * Save conversation state.
 * Source: ConversationMemoryService.saveConversation() in Swift
 */
export async function saveConversation(chatId: string, messages: any[], extras?: {
  summary?: string;
  activeContentUUID?: string;
  linkedAtomUUIDs?: string[];
  estimatedTokens?: number;
}): Promise<void> {
  const now = new Date().toISOString();

  await supabase
    .from('agent_conversations')
    .upsert({
      user_id: userId,
      chat_id: chatId,
      messages: messages,
      summary: extras?.summary ?? null,
      active_content_uuid: extras?.activeContentUUID ?? null,
      linked_atom_uuids: extras?.linkedAtomUUIDs ?? [],
      estimated_tokens: extras?.estimatedTokens ?? 0,
      updated_at: now,
    }, { onConflict: 'user_id,chat_id' });
}

// ============================================================
// Prompt Templates
// ============================================================

/**
 * Load a prompt template by key.
 * Source: PromptTemplateStore in Swift (synced to prompt_templates table)
 */
export async function loadPromptTemplate(key: string): Promise<string | null> {
  const { data } = await supabase
    .from('prompt_templates')
    .select('content')
    .eq('user_id', userId)
    .eq('key', key)
    .single();

  return data?.content ?? null;
}

// ============================================================
// API Usage Tracking
// ============================================================

/**
 * Log an API call for cost tracking.
 */
export async function logApiUsage(params: {
  model: string;
  inputTokens: number;
  outputTokens: number;
  cachedTokens?: number;
  costUsd: number;
  toolName?: string;
  contentUUID?: string;
  intent?: string;
}): Promise<void> {
  await supabase.from('api_usage').insert({
    user_id: userId,
    model: params.model,
    input_tokens: params.inputTokens,
    output_tokens: params.outputTokens,
    cached_tokens: params.cachedTokens ?? 0,
    cost_usd: params.costUsd,
    tool_name: params.toolName ?? null,
    content_uuid: params.contentUUID ?? null,
    intent: params.intent ?? null,
  });
}

// ============================================================
// Atom Helpers
// ============================================================

/**
 * Convert an atom to a response dictionary (for tool results).
 * Source: atomToDict() in AgentToolExecutor.swift
 */
export function atomToDict(atom: Atom): Record<string, any> {
  return {
    uuid: atom.uuid,
    type: atom.type,
    title: atom.title,
    body: atom.body ? atom.body.substring(0, 500) : null,
    createdAt: atom.created_at,
    updatedAt: atom.updated_at,
    ...(atom.metadata || {}),
  };
}
