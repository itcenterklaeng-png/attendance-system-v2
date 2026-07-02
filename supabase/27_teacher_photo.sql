-- ============================================
-- 27_teacher_photo.sql
-- เพิ่ม photo_url ให้ teachers table
-- ใช้กับหน้า profile.html (upload รูปโปรไฟล์)
-- ============================================

ALTER TABLE teachers
  ADD COLUMN IF NOT EXISTS photo_url TEXT;

COMMENT ON COLUMN teachers.photo_url IS 'URL รูปโปรไฟล์ครู (Supabase Storage)';
