-- CosmoOS Supabase Seedlings (the global Seedbed)
-- Run after 005_capture_requests_push.sql (Dashboard > SQL Editor > New Query)
--
-- A seedling is a named proto-concept accruing captured thoughts before it
-- earns a Concept page. Thoughts routed "grow" from either device land here;
-- the Mac's develop flow settles a seedling into a page. Data columns mirror
-- both apps' GRDB tables exactly (quoted camelCase); JSON payloads stay TEXT
-- for byte-identical round-trips.

CREATE TABLE IF NOT EXISTS seedlings (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,

    "conceptKey" TEXT NOT NULL DEFAULT '',
    "name" TEXT NOT NULL DEFAULT '',
    "aliasesJSON" TEXT,
    "thoughtsJSON" TEXT,
    status TEXT NOT NULL DEFAULT 'growing',       -- growing | developed | folded
    "pinnedAt" TEXT,
    "mergeTargetConnectionUUID" TEXT,
    "developedConnectionUUID" TEXT,
    "scopeDeepDiveUUID" TEXT,
    "affinityClusterId" TEXT,
    "affinityClusterName" TEXT,
    "affinityThinkspaceId" TEXT,
    "affinityThinkspaceName" TEXT,
    "createdAt" TEXT NOT NULL,
    "updatedAt" TEXT NOT NULL,                    -- app data (ISO8601 app-side)
    "lastTouchedAt" TEXT NOT NULL,

    -- Sync bookkeeping
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_seedlings_uuid ON seedlings(uuid);
CREATE INDEX IF NOT EXISTS idx_seedlings_user_updated ON seedlings(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_seedlings_growing ON seedlings(user_id, status) WHERE NOT is_deleted;

ALTER TABLE seedlings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "seedlings_select_own" ON seedlings;
CREATE POLICY "seedlings_select_own" ON seedlings
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "seedlings_insert_own" ON seedlings;
CREATE POLICY "seedlings_insert_own" ON seedlings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "seedlings_update_own" ON seedlings;
CREATE POLICY "seedlings_update_own" ON seedlings
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "seedlings_delete_own" ON seedlings;
CREATE POLICY "seedlings_delete_own" ON seedlings
    FOR DELETE USING (auth.uid() = user_id);

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE seedlings;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END $$;
