-- Canvas drawings sync — Supabase migration
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).
-- Purely ADDITIVE: creates the canvas_drawings table so Mac canvas drawings
-- (shapes, freehand strokes, text annotations) sync to the cloud and render
-- on the iPhone map. Mirrors the Mac's local canvas_drawings schema plus the
-- standard sync columns (user_id, _source, _version, synced_at).

CREATE TABLE IF NOT EXISTS canvas_drawings (
    id BIGSERIAL PRIMARY KEY,
    uuid TEXT UNIQUE NOT NULL,               -- Mac local drawing id
    thinkspace_id TEXT,
    drawing_type TEXT NOT NULL,              -- shape | freehand | text
    shape_kind TEXT,                         -- rectangle | roundedRectangle | circle | line | arrow | triangle
    origin_x DOUBLE PRECISION NOT NULL DEFAULT 0,
    origin_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    width DOUBLE PRECISION,
    height DOUBLE PRECISION,
    rotation DOUBLE PRECISION DEFAULT 0,
    path_data TEXT,                          -- freehand: JSON [{x,y,w?}] in canvas coords
    text_content TEXT,
    text_weight TEXT,                        -- S | M | L | X | XL
    stroke_color TEXT NOT NULL DEFAULT '#1A1A1A',
    fill_color TEXT,
    stroke_width DOUBLE PRECISION NOT NULL DEFAULT 2.5,
    opacity DOUBLE PRECISION NOT NULL DEFAULT 1,
    z_index INTEGER DEFAULT 0,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    _source TEXT NOT NULL DEFAULT 'mac',
    _version INTEGER NOT NULL DEFAULT 1,
    synced_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_canvas_drawings_user ON canvas_drawings(user_id) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_canvas_drawings_thinkspace ON canvas_drawings(thinkspace_id) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_canvas_drawings_updated ON canvas_drawings(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_canvas_drawings_source ON canvas_drawings(_source);

ALTER TABLE canvas_drawings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "canvas_drawings_select_own" ON canvas_drawings;
CREATE POLICY "canvas_drawings_select_own" ON canvas_drawings
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "canvas_drawings_insert_own" ON canvas_drawings;
CREATE POLICY "canvas_drawings_insert_own" ON canvas_drawings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "canvas_drawings_update_own" ON canvas_drawings;
CREATE POLICY "canvas_drawings_update_own" ON canvas_drawings
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "canvas_drawings_delete_own" ON canvas_drawings;
CREATE POLICY "canvas_drawings_delete_own" ON canvas_drawings
    FOR DELETE USING (auth.uid() = user_id);
