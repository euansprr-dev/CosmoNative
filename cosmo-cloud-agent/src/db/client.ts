// cosmo-cloud-agent/src/db/client.ts
// Supabase client with service_role for cloud agent operations
// Uses service_role key to bypass RLS — all queries MUST include user_id filter

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { config } from '../config';

// Service role client — bypasses RLS, MUST filter by user_id manually
export const supabase: SupabaseClient = createClient(
  config.supabaseUrl,
  config.supabaseServiceRoleKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  }
);

// The user ID this agent serves
export const userId = config.userId;
