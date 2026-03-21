-- CosmoOS Supabase Helper Functions
-- Run after 001_foundation_schema.sql

-- Increment atom version (used by cloud agent after updates)
CREATE OR REPLACE FUNCTION increment_atom_version(atom_uuid TEXT)
RETURNS void AS $$
BEGIN
  UPDATE atoms
  SET _version = _version + 1
  WHERE uuid = atom_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add unique constraint on agent_conversations for upsert
-- (needed by saveConversation upsert on user_id,chat_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'agent_conversations_user_chat_unique'
  ) THEN
    ALTER TABLE agent_conversations
    ADD CONSTRAINT agent_conversations_user_chat_unique UNIQUE (user_id, chat_id);
  END IF;
END $$;
