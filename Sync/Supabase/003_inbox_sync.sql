-- CosmoOS Supabase Inbox Sync Schema
-- Run after 001_foundation_schema.sql / 002_helper_functions.sql
-- (Dashboard > SQL Editor > New Query)
--
-- Makes the Inbox a synced, local-first domain shared by Mac and iPhone:
--   inbox_items          — the triage queue (explicit captures)
--   capture_destinations — custom capture lanes
--   captured_items       — items routed into lanes
--
-- Column convention (the swipe_boards precedent): data columns are quoted
-- camelCase mirroring the GRDB tables EXACTLY, so both clients' generic sync
-- pipeline (ChangeTracker payloads → upsert → pull → ConflictResolver raw
-- inserts) needs zero key mapping. JSON-ish columns stay TEXT — payloads pass
-- through untransformed in both directions. Bookkeeping columns (user_id,
-- _source, is_deleted, created_at, updated_at) are snake_case like every
-- other synced table; pull cursors page on updated_at and softDelete PATCHes
-- is_deleted + updated_at + _source.

-- ============================================================
-- 1. INBOX ITEMS (triage queue)
-- ============================================================

CREATE TABLE IF NOT EXISTS inbox_items (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,

    -- Raw capture
    source TEXT NOT NULL DEFAULT 'quick_capture',
    "rawText" TEXT NOT NULL,
    title TEXT,

    -- Classification (written only by the Mac's InboxIngestService queue)
    classification TEXT,
    confidence DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- Merge target
    "mergeTargetUuid" TEXT,
    "mergeTargetTitle" TEXT,
    "mergeTargetType" TEXT,
    "mergePreview" TEXT,

    -- Place target / recommendations
    "placeThinkspaceId" TEXT,
    "placeThinkspaceName" TEXT,
    "placeAtomType" TEXT,
    recommendations TEXT,
    "primaryRouteKind" TEXT,
    "destinationPath" TEXT,
    rationale TEXT,
    "placementPlanSummary" TEXT,

    -- State
    status TEXT NOT NULL DEFAULT 'pending',
    "isRead" BOOLEAN NOT NULL DEFAULT FALSE,

    -- App-side timestamps (TEXT ISO8601, exactly as GRDB stores them)
    "createdAt" TEXT NOT NULL,
    "classifiedAt" TEXT,
    "actionedAt" TEXT,

    -- Source-specific metadata (JSON as TEXT)
    metadata TEXT,

    -- Sync bookkeeping
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inbox_items_uuid ON inbox_items(uuid);
CREATE INDEX IF NOT EXISTS idx_inbox_items_user_updated ON inbox_items(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_inbox_items_user_status ON inbox_items(user_id, status) WHERE NOT is_deleted;

-- ============================================================
-- 2. CAPTURE DESTINATIONS (custom lanes)
-- ============================================================

CREATE TABLE IF NOT EXISTS capture_destinations (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,

    name TEXT NOT NULL,
    "destinationDescription" TEXT,
    type TEXT NOT NULL DEFAULT 'list_lane',
    "aliasesJSON" TEXT NOT NULL DEFAULT '[]',
    icon TEXT NOT NULL DEFAULT 'list.bullet',
    "colorAccentToken" TEXT,
    "defaultObjectType" TEXT NOT NULL DEFAULT 'note',
    "defaultParentTarget" TEXT,
    "defaultReviewBehavior" TEXT NOT NULL DEFAULT 'save_only',
    "telegramCommandPatternsJSON" TEXT,
    "acceptedMediaTypesJSON" TEXT,
    "processingRulesJSON" TEXT,
    "routingRulesJSON" TEXT,
    "isArchived" BOOLEAN NOT NULL DEFAULT FALSE,
    "isEnabled" BOOLEAN NOT NULL DEFAULT TRUE,
    "createdAt" TEXT NOT NULL,
    "updatedAt" TEXT NOT NULL,
    "lastUsedAt" TEXT,
    "itemCount" INTEGER NOT NULL DEFAULT 0,
    "conflictStatus" TEXT NOT NULL DEFAULT 'clear',

    -- Sync bookkeeping
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_capture_destinations_uuid ON capture_destinations(uuid);
CREATE INDEX IF NOT EXISTS idx_capture_destinations_user_updated ON capture_destinations(user_id, updated_at);

-- ============================================================
-- 3. CAPTURED ITEMS (lane contents)
-- ============================================================

CREATE TABLE IF NOT EXISTS captured_items (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,

    "rawText" TEXT,
    caption TEXT,
    "cleanText" TEXT,
    source TEXT NOT NULL DEFAULT 'telegram',
    "telegramMessageId" TEXT,
    "telegramMediaGroupId" TEXT,
    "telegramChatId" TEXT,
    sender TEXT,
    "timestamp" TEXT NOT NULL,
    "captureDestinationId" TEXT,
    "parsedCommand" TEXT,
    "parsedIntent" TEXT,
    "mediaAttachmentIdsJSON" TEXT,
    "createdObjectIdsJSON" TEXT,
    "routingConfidence" DOUBLE PRECISION NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    "parentDeepDiveId" TEXT,
    "parentInquirySessionId" TEXT,
    "parentQuestionId" TEXT,
    "parentProjectId" TEXT,
    "provenanceMetadata" TEXT,
    "createdAt" TEXT NOT NULL,
    "updatedAt" TEXT NOT NULL,

    -- Sync bookkeeping
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_captured_items_uuid ON captured_items(uuid);
CREATE INDEX IF NOT EXISTS idx_captured_items_user_updated ON captured_items(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_captured_items_lane ON captured_items("captureDestinationId") WHERE NOT is_deleted;

-- ============================================================
-- 4. ROW LEVEL SECURITY (owner-only + service-role bypass,
--    same shape as atoms — the cloud agent may route Telegram
--    captures into these tables later)
-- ============================================================

ALTER TABLE inbox_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY inbox_select ON inbox_items FOR SELECT USING (user_id = auth.uid());
CREATE POLICY inbox_insert ON inbox_items FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY inbox_update ON inbox_items FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY inbox_delete ON inbox_items FOR DELETE USING (user_id = auth.uid());
CREATE POLICY inbox_service ON inbox_items TO service_role USING (true) WITH CHECK (true);

ALTER TABLE capture_destinations ENABLE ROW LEVEL SECURITY;
CREATE POLICY lanes_select ON capture_destinations FOR SELECT USING (user_id = auth.uid());
CREATE POLICY lanes_insert ON capture_destinations FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY lanes_update ON capture_destinations FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY lanes_delete ON capture_destinations FOR DELETE USING (user_id = auth.uid());
CREATE POLICY lanes_service ON capture_destinations TO service_role USING (true) WITH CHECK (true);

ALTER TABLE captured_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY captures_select ON captured_items FOR SELECT USING (user_id = auth.uid());
CREATE POLICY captures_insert ON captured_items FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY captures_update ON captured_items FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY captures_delete ON captured_items FOR DELETE USING (user_id = auth.uid());
CREATE POLICY captures_service ON captured_items TO service_role USING (true) WITH CHECK (true);

-- ============================================================
-- 5. updated_at TRIGGERS (pull cursors page on updated_at —
--    every UPDATE must bump it; update_updated_at() is defined
--    in 001_foundation_schema.sql)
-- ============================================================

CREATE TRIGGER inbox_items_updated_at
    BEFORE UPDATE ON inbox_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER capture_destinations_updated_at
    BEFORE UPDATE ON capture_destinations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER captured_items_updated_at
    BEFORE UPDATE ON captured_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 6. REALTIME PUBLICATION (live suggestion pills on the phone,
--    live captures on the Mac)
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE inbox_items;
ALTER PUBLICATION supabase_realtime ADD TABLE capture_destinations;
ALTER PUBLICATION supabase_realtime ADD TABLE captured_items;
