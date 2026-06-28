/**
 * Supabase client (singleton)
 * Import ใน ทุกหน้าที่ต้องใช้ Supabase
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SUPABASE_URL, SUPABASE_KEY } from '../config.js';

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    storageKey: 'attendance-v2-auth'
  }
});
