-- ============================================
-- เพิ่ม column department ในตาราง teachers
-- รัน SQL นี้ใน Supabase SQL Editor ก่อน migrate
-- ============================================

ALTER TABLE teachers
  ADD COLUMN IF NOT EXISTS department TEXT;

CREATE INDEX IF NOT EXISTS idx_teachers_department ON teachers(department) WHERE department IS NOT NULL;

-- เช็คผล
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_name = 'teachers' ORDER BY ordinal_position;
