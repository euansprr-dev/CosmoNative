-- CosmoOS Supabase Capture Requests + Push Tokens
-- Run after 004_media_attachments_sync.sql (Dashboard > SQL Editor > New Query)
--
-- The Mac → iPhone camera relay: the Mac writes a capture_request row (and
-- fires an APNs push at the iPhone); the phone opens straight into the
-- scanner, streams pages up as media_attachments, and settles the request.
-- device_push_tokens carries each device's APNs token so the Mac can address
-- pushes directly (no server; the Mac signs its own APNs JWTs).

CREATE TABLE IF NOT EXISTS capture_requests (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,

    kind TEXT NOT NULL DEFAULT 'inbox_scan',      -- inbox_scan | inquiry_scan
    status TEXT NOT NULL DEFAULT 'pending',       -- pending | claimed | streaming | fulfilled | cancelled | expired
    "scanSessionId" TEXT NOT NULL DEFAULT '',

    -- Inquiry context (kind = inquiry_scan): where scanned thoughts land.
    "deepDiveUUID" TEXT,
    "sessionUUID" TEXT,
    "questionUUID" TEXT,
    "questionTitle" TEXT,
    "deepDiveTitle" TEXT,

    "pageCount" INTEGER NOT NULL DEFAULT 0,
    "requestedAt" TEXT NOT NULL,                  -- ISO8601 app-side
    "fulfilledAt" TEXT,

    -- Sync bookkeeping
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_capture_requests_uuid ON capture_requests(uuid);
CREATE INDEX IF NOT EXISTS idx_capture_requests_user_updated ON capture_requests(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_capture_requests_pending ON capture_requests(user_id, status) WHERE NOT is_deleted;

ALTER TABLE capture_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "capture_requests_select_own" ON capture_requests;
CREATE POLICY "capture_requests_select_own" ON capture_requests
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "capture_requests_insert_own" ON capture_requests;
CREATE POLICY "capture_requests_insert_own" ON capture_requests
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "capture_requests_update_own" ON capture_requests;
CREATE POLICY "capture_requests_update_own" ON capture_requests
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "capture_requests_delete_own" ON capture_requests;
CREATE POLICY "capture_requests_delete_own" ON capture_requests
    FOR DELETE USING (auth.uid() = user_id);

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE capture_requests;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END $$;

-- ============================================================
-- Device push tokens (APNs addressing; not a synced GRDB domain)
-- ============================================================

CREATE TABLE IF NOT EXISTS device_push_tokens (
    id BIGSERIAL PRIMARY KEY,
    device_id TEXT NOT NULL,                      -- identifierForVendor
    platform TEXT NOT NULL DEFAULT 'ios',
    token TEXT NOT NULL,                          -- hex APNs device token
    environment TEXT NOT NULL DEFAULT 'production', -- development | production
    bundle_id TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    UNIQUE (user_id, device_id)
);

ALTER TABLE device_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "device_push_tokens_select_own" ON device_push_tokens;
CREATE POLICY "device_push_tokens_select_own" ON device_push_tokens
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_push_tokens_insert_own" ON device_push_tokens;
CREATE POLICY "device_push_tokens_insert_own" ON device_push_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_push_tokens_update_own" ON device_push_tokens;
CREATE POLICY "device_push_tokens_update_own" ON device_push_tokens
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_push_tokens_delete_own" ON device_push_tokens;
CREATE POLICY "device_push_tokens_delete_own" ON device_push_tokens
    FOR DELETE USING (auth.uid() = user_id);
