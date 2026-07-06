-- CosmoOS Supabase Media Attachments Sync Schema
-- Run after 003_inbox_sync.sql (Dashboard > SQL Editor > New Query)
--
-- Physical capture (July 2026): media_attachments becomes a synced,
-- local-first domain. Photos of physical pages / camera captures made on
-- either device sync as rows here; the image bytes mirror separately through
-- the private `capture-media` Storage bucket (one folder per user).
--
-- Column convention (the inbox_sync precedent): data columns are quoted
-- camelCase mirroring the GRDB tables EXACTLY so the generic sync pipeline
-- needs zero key mapping. JSON-ish columns stay TEXT. Bookkeeping columns
-- (user_id, _source, is_deleted, created_at, updated_at) are snake_case.
--
-- NOTE: "localStoragePath"/"thumbnailPath" are DEVICE-LOCAL paths — they sync
-- as opaque strings and each device ignores paths that don't exist locally,
-- resolving bytes via "blobReference" instead.

CREATE TABLE IF NOT EXISTS media_attachments (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,

    -- Linkage: legacy Telegram capture id + generalized owner
    "capturedItemId" TEXT NOT NULL DEFAULT '',
    "ownerType" TEXT NOT NULL DEFAULT 'captured_item',  -- inbox_item | captured_item | extract | source_atom
    "ownerUUID" TEXT NOT NULL DEFAULT '',

    kind TEXT NOT NULL DEFAULT 'image',                 -- image | screenshot | page_scan | pdf | ...
    "originalFilename" TEXT,
    "mimeType" TEXT,
    "fileSize" BIGINT,
    "telegramFileId" TEXT,
    "telegramFileUniqueId" TEXT,
    "localStoragePath" TEXT,
    "blobReference" TEXT,                               -- authenticated Storage URL of the original
    "thumbnailPath" TEXT,
    "extractedText" TEXT,
    "transcriptText" TEXT,
    metadata TEXT,                                      -- JSON: pageIndex, scanSessionId, thumbBlobReference, visionLines, inkMarks, transcriptionConfidence, needsLLMPass
    "processingStatus" TEXT NOT NULL DEFAULT 'downloaded',
    "sourceObjectId" TEXT,

    -- App-side timestamps (TEXT ISO8601, exactly as GRDB stores them)
    "createdAt" TEXT NOT NULL,
    "updatedAt" TEXT NOT NULL,

    -- Sync bookkeeping
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_media_attachments_uuid ON media_attachments(uuid);
CREATE INDEX IF NOT EXISTS idx_media_attachments_user_updated ON media_attachments(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_media_attachments_owner ON media_attachments("ownerType", "ownerUUID") WHERE NOT is_deleted;

ALTER TABLE media_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "media_attachments_select_own" ON media_attachments;
CREATE POLICY "media_attachments_select_own" ON media_attachments
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "media_attachments_insert_own" ON media_attachments;
CREATE POLICY "media_attachments_insert_own" ON media_attachments
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "media_attachments_update_own" ON media_attachments;
CREATE POLICY "media_attachments_update_own" ON media_attachments
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "media_attachments_delete_own" ON media_attachments;
CREATE POLICY "media_attachments_delete_own" ON media_attachments
    FOR DELETE USING (auth.uid() = user_id);

-- Realtime: the publication must include the table for postgres_changes.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE media_attachments;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END $$;

-- ============================================================
-- Storage bucket: capture-media (private; originals + thumbnails)
-- Object layout: {user_id}/attachments/{uuid}.{ext} and {uuid}-thumb.jpg
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('capture-media', 'capture-media', FALSE)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "capture_media_select_own" ON storage.objects;
CREATE POLICY "capture_media_select_own" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'capture-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "capture_media_insert_own" ON storage.objects;
CREATE POLICY "capture_media_insert_own" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'capture-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "capture_media_update_own" ON storage.objects;
CREATE POLICY "capture_media_update_own" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'capture-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "capture_media_delete_own" ON storage.objects;
CREATE POLICY "capture_media_delete_own" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'capture-media'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );
