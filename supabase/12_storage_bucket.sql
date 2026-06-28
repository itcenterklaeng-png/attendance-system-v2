-- ============================================
-- Phase A — Supabase Storage Bucket: teaching-logs
-- ============================================

-- 1. สร้าง bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'teaching-logs',
  'teaching-logs',
  true,                                            -- public ดูได้
  5 * 1024 * 1024,                                 -- 5 MB ต่อไฟล์
  ARRAY['image/jpeg', 'image/png', 'image/webp']   -- เฉพาะรูปภาพ
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. RLS Policies
-- ดู: ทุกคน (public bucket — ใครก็เปิด URL ได้)
DROP POLICY IF EXISTS "teaching_logs_public_read" ON storage.objects;
CREATE POLICY "teaching_logs_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'teaching-logs');

-- อัพโหลด: ครูที่ login + active
DROP POLICY IF EXISTS "teaching_logs_authenticated_insert" ON storage.objects;
CREATE POLICY "teaching_logs_authenticated_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'teaching-logs'
    AND auth.role() = 'authenticated'
    AND app_current_role() IN ('admin', 'user')
  );

-- อัพเดท (overwrite): เจ้าของไฟล์ หรือ admin
DROP POLICY IF EXISTS "teaching_logs_owner_update" ON storage.objects;
CREATE POLICY "teaching_logs_owner_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'teaching-logs'
    AND (owner = auth.uid() OR app_current_role() = 'admin')
  );

-- ลบ: เจ้าของไฟล์ หรือ admin
DROP POLICY IF EXISTS "teaching_logs_owner_delete" ON storage.objects;
CREATE POLICY "teaching_logs_owner_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'teaching-logs'
    AND (owner = auth.uid() OR app_current_role() = 'admin')
  );
