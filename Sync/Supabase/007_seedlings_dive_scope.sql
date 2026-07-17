-- CosmoOS Supabase Seedlings — dive-scope fields (Seedbed unification)
-- Run after 006_seedlings_sync.sql (Dashboard > SQL Editor > New Query)
--
-- Deep Dive seedbeds migrate onto the seedlings store (scopeDeepDiveUUID was
-- in 006); the resolver's concept hierarchy travels with each seedling.
-- Thought-level research provenance (sourceExtractUUID, sessionUUID, …) lives
-- inside thoughtsJSON — no schema change needed for it.

ALTER TABLE seedlings ADD COLUMN IF NOT EXISTS "parentConceptName" TEXT;
ALTER TABLE seedlings ADD COLUMN IF NOT EXISTS "relatedConceptNamesJSON" TEXT;

CREATE INDEX IF NOT EXISTS idx_seedlings_scope
    ON seedlings(user_id, "scopeDeepDiveUUID") WHERE NOT is_deleted;
