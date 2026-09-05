-- Canvas membership without position — Supabase migration (September 2026)
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).
--
-- Purely ADDITIVE. `canvas_blocks.is_placed` distinguishes a placement that
-- is laid out on the space's canvas (TRUE — every existing row) from a
-- membership that has not been placed yet (FALSE — filed by the Inbox,
-- Command-K, or an AI service into a space the user was not looking at; it
-- waits in the canvas tray and shows in the space's library and board).
--
-- Clients that predate the column (the iPhone before its own migration) omit
-- the key on push and take the default. ORDER OF OPERATIONS: ship the iPhone
-- build that tolerates the column FIRST, then run this, then ship the Mac
-- build that pushes the key — PostgREST rejects unknown columns (PGRST204),
-- and the iPhone's pull path inserts every column it receives.

ALTER TABLE canvas_blocks ADD COLUMN IF NOT EXISTS is_placed BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_canvas_blocks_thinkspace_placed
    ON canvas_blocks(thinkspace_id, is_placed) WHERE NOT is_deleted;

NOTIFY pgrst, 'reload schema';
