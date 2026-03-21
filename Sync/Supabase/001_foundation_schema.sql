-- CosmoOS Supabase Foundation Schema
-- Phase 0: Postgres tables mirroring GRDB local-first architecture
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query)
--
-- Prerequisites:
--   1. Create a Supabase project at supabase.com
--   2. Enable the pgvector extension (for Phase 5 semantic search)
--   3. Run this migration in order

-- ============================================================
-- 1. CORE ATOMS TABLE
-- Mirrors the GRDB `atoms` table. Uses JSONB instead of TEXT
-- for server-side queries on metadata/structured/links.
-- ============================================================

CREATE TABLE IF NOT EXISTS atoms (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL,

    -- Common fields
    title TEXT,
    body TEXT,

    -- Flexible JSON storage (JSONB for server-side querying)
    structured JSONB,
    metadata JSONB,
    links JSONB,

    -- Timestamps (TIMESTAMPTZ for timezone-aware server operations)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Soft delete
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,

    -- Multi-user support
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Sync tracking
    _version INTEGER NOT NULL DEFAULT 1,
    _source TEXT NOT NULL DEFAULT 'mac'  -- 'mac' or 'cloud'
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_atoms_uuid ON atoms(uuid);
CREATE INDEX IF NOT EXISTS idx_atoms_type ON atoms(type) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_atoms_updated ON atoms(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_atoms_user ON atoms(user_id) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_atoms_user_type ON atoms(user_id, type) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_atoms_user_updated ON atoms(user_id, updated_at DESC) WHERE NOT is_deleted;

-- JSONB indexes for common metadata queries
CREATE INDEX IF NOT EXISTS idx_atoms_metadata_gin ON atoms USING GIN (metadata jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_atoms_links_gin ON atoms USING GIN (links jsonb_path_ops);

-- Full-text search (replaces local FTS5)
ALTER TABLE atoms ADD COLUMN IF NOT EXISTS fts tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(body, '')), 'B')
    ) STORED;
CREATE INDEX IF NOT EXISTS idx_atoms_fts ON atoms USING GIN (fts);

-- ============================================================
-- 2. GRAPH EDGES TABLE
-- Knowledge graph relationships between atoms.
-- graph_nodes is NOT synced — it's derived/cached server-side.
-- ============================================================

CREATE TABLE IF NOT EXISTS graph_edges (
    id BIGSERIAL PRIMARY KEY,
    source_uuid TEXT NOT NULL,
    target_uuid TEXT NOT NULL,

    -- Edge properties
    edge_type TEXT NOT NULL,         -- explicit, reference, semantic, conceptual, contextual, transitive
    link_type TEXT,                  -- Original AtomLinkType (for explicit edges)
    is_directed BOOLEAN DEFAULT TRUE,

    -- Weight components
    structural_weight REAL DEFAULT 0.0,
    semantic_weight REAL DEFAULT 0.0,
    recency_weight REAL DEFAULT 1.0,
    usage_weight REAL DEFAULT 0.0,
    combined_weight REAL DEFAULT 0.0,

    -- Multi-user support
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Composite uniqueness
    UNIQUE(source_uuid, target_uuid, edge_type, user_id)
);

CREATE INDEX IF NOT EXISTS idx_graph_edges_source ON graph_edges(source_uuid);
CREATE INDEX IF NOT EXISTS idx_graph_edges_target ON graph_edges(target_uuid);
CREATE INDEX IF NOT EXISTS idx_graph_edges_type ON graph_edges(edge_type);
CREATE INDEX IF NOT EXISTS idx_graph_edges_weight ON graph_edges(combined_weight DESC);
CREATE INDEX IF NOT EXISTS idx_graph_edges_user ON graph_edges(user_id);

-- ============================================================
-- 3. CANVAS BLOCKS TABLE
-- Spatial positioning of atoms on thinkspace canvases.
-- ============================================================

CREATE TABLE IF NOT EXISTS canvas_blocks (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,

    -- Block identity
    atom_uuid TEXT NOT NULL,
    thinkspace_id TEXT,              -- Which canvas this block belongs to

    -- Spatial properties
    position_x INTEGER NOT NULL DEFAULT 0,
    position_y INTEGER NOT NULL DEFAULT 0,
    width INTEGER DEFAULT 320,
    height INTEGER DEFAULT 340,
    z_index INTEGER DEFAULT 0,
    is_collapsed BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,

    -- Legacy fields (kept for backward compat during migration)
    document_type TEXT,
    document_id INTEGER,
    document_uuid TEXT,
    entity_id INTEGER,
    entity_uuid TEXT,
    entity_type TEXT,
    entity_title TEXT,
    zone TEXT,
    note_content TEXT,

    -- Soft delete
    is_deleted BOOLEAN DEFAULT FALSE,

    -- Multi-user support
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_canvas_blocks_atom ON canvas_blocks(atom_uuid);
CREATE INDEX IF NOT EXISTS idx_canvas_blocks_thinkspace ON canvas_blocks(thinkspace_id) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_canvas_blocks_user ON canvas_blocks(user_id) WHERE NOT is_deleted;

-- ============================================================
-- 4. PROMPT TEMPLATES TABLE
-- Cloud storage for PromptTemplateStore content (methodology,
-- system prompts, platform constraints). Synced from Mac,
-- read by cloud agent.
-- ============================================================

CREATE TABLE IF NOT EXISTS prompt_templates (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    key TEXT NOT NULL,               -- 'methodology', 'unified_system_prompt', 'platform_constraints', 'identity'
    content TEXT NOT NULL,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, key)
);

-- ============================================================
-- 5. AGENT CONVERSATIONS TABLE
-- Shared conversation history between Mac and cloud agent.
-- ============================================================

CREATE TABLE IF NOT EXISTS agent_conversations (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    chat_id TEXT NOT NULL,           -- Telegram chat ID or in-app UUID
    messages JSONB NOT NULL DEFAULT '[]'::jsonb,
    summary TEXT,                    -- Compressed summary for long conversations
    active_content_uuid TEXT,        -- Currently linked content atom
    linked_atom_uuids JSONB DEFAULT '[]'::jsonb,
    estimated_tokens INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_user_chat ON agent_conversations(user_id, chat_id);

-- ============================================================
-- 6. API USAGE TRACKING TABLE
-- Tracks LLM API costs per user for billing/monitoring.
-- ============================================================

CREATE TABLE IF NOT EXISTS api_usage (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cached_tokens INTEGER DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    tool_name TEXT,                  -- Which agent tool triggered this call
    content_uuid TEXT,               -- Content atom being worked on
    intent TEXT,                     -- Agent intent classification
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_api_usage_user ON api_usage(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_usage_content ON api_usage(content_uuid) WHERE content_uuid IS NOT NULL;

-- ============================================================
-- 7. ROW LEVEL SECURITY
-- Every table enforces user isolation. Service role bypasses
-- for the cloud agent server.
-- ============================================================

-- atoms
ALTER TABLE atoms ENABLE ROW LEVEL SECURITY;

CREATE POLICY atoms_select ON atoms
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY atoms_insert ON atoms
    FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY atoms_update ON atoms
    FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY atoms_delete ON atoms
    FOR DELETE USING (user_id = auth.uid());

-- Service role bypass (cloud agent uses service_role key)
CREATE POLICY atoms_service_select ON atoms
    FOR SELECT TO service_role USING (true);
CREATE POLICY atoms_service_insert ON atoms
    FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY atoms_service_update ON atoms
    FOR UPDATE TO service_role USING (true) WITH CHECK (true);
CREATE POLICY atoms_service_delete ON atoms
    FOR DELETE TO service_role USING (true);

-- graph_edges
ALTER TABLE graph_edges ENABLE ROW LEVEL SECURITY;

CREATE POLICY edges_select ON graph_edges FOR SELECT USING (user_id = auth.uid());
CREATE POLICY edges_insert ON graph_edges FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY edges_update ON graph_edges FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY edges_delete ON graph_edges FOR DELETE USING (user_id = auth.uid());
CREATE POLICY edges_service ON graph_edges TO service_role USING (true) WITH CHECK (true);

-- canvas_blocks
ALTER TABLE canvas_blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY blocks_select ON canvas_blocks FOR SELECT USING (user_id = auth.uid());
CREATE POLICY blocks_insert ON canvas_blocks FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY blocks_update ON canvas_blocks FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY blocks_delete ON canvas_blocks FOR DELETE USING (user_id = auth.uid());
CREATE POLICY blocks_service ON canvas_blocks TO service_role USING (true) WITH CHECK (true);

-- prompt_templates
ALTER TABLE prompt_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY templates_select ON prompt_templates FOR SELECT USING (user_id = auth.uid());
CREATE POLICY templates_insert ON prompt_templates FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY templates_update ON prompt_templates FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY templates_service ON prompt_templates TO service_role USING (true) WITH CHECK (true);

-- agent_conversations
ALTER TABLE agent_conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY convos_select ON agent_conversations FOR SELECT USING (user_id = auth.uid());
CREATE POLICY convos_insert ON agent_conversations FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY convos_update ON agent_conversations FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY convos_service ON agent_conversations TO service_role USING (true) WITH CHECK (true);

-- api_usage
ALTER TABLE api_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY usage_select ON api_usage FOR SELECT USING (user_id = auth.uid());
CREATE POLICY usage_insert ON api_usage FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY usage_service ON api_usage TO service_role USING (true) WITH CHECK (true);

-- ============================================================
-- 8. REALTIME PUBLICATION
-- Enable Supabase Realtime for atoms table so Mac/iOS clients
-- receive instant updates when the cloud agent writes.
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE atoms;
ALTER PUBLICATION supabase_realtime ADD TABLE canvas_blocks;

-- ============================================================
-- 9. HELPER FUNCTIONS
-- ============================================================

-- Auto-update updated_at timestamp on any UPDATE
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER atoms_updated_at
    BEFORE UPDATE ON atoms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER edges_updated_at
    BEFORE UPDATE ON graph_edges
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER blocks_updated_at
    BEFORE UPDATE ON canvas_blocks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER templates_updated_at
    BEFORE UPDATE ON prompt_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER conversations_updated_at
    BEFORE UPDATE ON agent_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 10. COMMUNITY SWIPES TABLE (Phase 4 — pre-created for schema stability)
-- ============================================================

CREATE TABLE IF NOT EXISTS community_swipes (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,
    atom_uuid TEXT NOT NULL,         -- Reference to contributor's original atom
    contributor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT,
    hook_type TEXT,
    hook_score REAL,
    framework_type TEXT,
    platform TEXT,
    category TEXT,
    tags TEXT[],
    analysis JSONB,                  -- Sanitized swipe analysis (no client-specific data)
    is_approved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE community_swipes ENABLE ROW LEVEL SECURITY;

-- Anyone can read approved swipes
CREATE POLICY community_read ON community_swipes
    FOR SELECT USING (is_approved = true);

-- Users can only insert their own contributions
CREATE POLICY community_insert ON community_swipes
    FOR INSERT WITH CHECK (contributor_id = auth.uid());

-- Users can update/delete only their own un-approved swipes
CREATE POLICY community_update ON community_swipes
    FOR UPDATE USING (contributor_id = auth.uid() AND NOT is_approved);

CREATE POLICY community_delete ON community_swipes
    FOR DELETE USING (contributor_id = auth.uid() AND NOT is_approved);

-- Service role for moderation
CREATE POLICY community_service ON community_swipes
    TO service_role USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_community_approved ON community_swipes(is_approved) WHERE is_approved = true;
CREATE INDEX IF NOT EXISTS idx_community_hook ON community_swipes(hook_type) WHERE is_approved = true;
CREATE INDEX IF NOT EXISTS idx_community_framework ON community_swipes(framework_type) WHERE is_approved = true;
