-- CosmoOS iOS Companion — Supabase migration
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).
-- All changes are ADDITIVE — no existing behavior is modified.
--
-- 1. canvas_blocks sync columns
--    The Mac already pushes canvas_blocks, but the table was missing the
--    _source/_version/synced_at columns the push payload carries, so every
--    canvas_blocks push has been failing with PGRST204. This fixes those
--    pushes AND enables the iPhone to sync spatial data both ways.
-- 2. swipe_boards table — board definitions sync between Mac and iPhone.
-- 3. atom-images storage bucket — doc images render on both devices.

-- ============================================================
-- 1. canvas_blocks: sync columns
-- ============================================================

ALTER TABLE canvas_blocks ADD COLUMN IF NOT EXISTS _source TEXT NOT NULL DEFAULT 'mac';
ALTER TABLE canvas_blocks ADD COLUMN IF NOT EXISTS _version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE canvas_blocks ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_canvas_blocks_updated ON canvas_blocks(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_canvas_blocks_source ON canvas_blocks(_source);

-- ============================================================
-- 2. swipe_boards
-- ============================================================

CREATE TABLE IF NOT EXISTS swipe_boards (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT 'star',
    "tintToken" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isArchived" BOOLEAN NOT NULL DEFAULT FALSE,
    "createdAt" TEXT,
    "updatedAt" TEXT,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    _version INTEGER NOT NULL DEFAULT 1,
    synced_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_swipe_boards_user ON swipe_boards(user_id) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_swipe_boards_updated ON swipe_boards(updated_at DESC);

ALTER TABLE swipe_boards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "swipe_boards_select_own" ON swipe_boards;
CREATE POLICY "swipe_boards_select_own" ON swipe_boards
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "swipe_boards_insert_own" ON swipe_boards;
CREATE POLICY "swipe_boards_insert_own" ON swipe_boards
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "swipe_boards_update_own" ON swipe_boards;
CREATE POLICY "swipe_boards_update_own" ON swipe_boards
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "swipe_boards_delete_own" ON swipe_boards;
CREATE POLICY "swipe_boards_delete_own" ON swipe_boards
    FOR DELETE USING (auth.uid() = user_id);

-- ============================================================
-- 3. atom-images storage bucket (per-user folders)
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('atom-images', 'atom-images', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "atom_images_select_own" ON storage.objects;
CREATE POLICY "atom_images_select_own" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'atom-images'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "atom_images_insert_own" ON storage.objects;
CREATE POLICY "atom_images_insert_own" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'atom-images'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "atom_images_update_own" ON storage.objects;
CREATE POLICY "atom_images_update_own" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'atom-images'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "atom_images_delete_own" ON storage.objects;
CREATE POLICY "atom_images_delete_own" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'atom-images'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );
