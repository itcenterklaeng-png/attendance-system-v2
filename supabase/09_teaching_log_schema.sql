-- ============================================
-- Phase 5 — ขยาย schema teaching_logs
-- เพิ่ม fields ให้ครบตามแบบฟอร์มของกระทรวงศึกษาธิการ
-- ============================================

ALTER TABLE teaching_logs
  ADD COLUMN IF NOT EXISTS periods     TEXT,        -- คาบที่สอน "1,2,3"
  ADD COLUMN IF NOT EXISTS objectives  TEXT,        -- จุดประสงค์การเรียนรู้
  ADD COLUMN IF NOT EXISTS results     TEXT,        -- ผลการจัดการเรียนการสอน
  ADD COLUMN IF NOT EXISTS problems    TEXT,        -- ปัญหาและอุปสรรค
  ADD COLUMN IF NOT EXISTS suggestions TEXT;        -- ข้อเสนอแนะ

-- Unique constraint — 1 บันทึก ต่อ subject+date+teacher
-- (ครูคนละคนสอนวิชาเดียวกันคนละวันได้ — แต่ครู 1 คน เขียน 1 บันทึก ต่อวัน)
CREATE UNIQUE INDEX IF NOT EXISTS uq_teaching_logs_subj_date_teacher
  ON teaching_logs(subject_id, date, teacher_id);

CREATE INDEX IF NOT EXISTS idx_teaching_logs_date_desc
  ON teaching_logs(date DESC);

-- View ที่ join teacher_name + subject_name ให้ง่ายตอน list
CREATE OR REPLACE VIEW teaching_logs_view AS
SELECT
  tl.id,
  tl.subject_id,
  s.subject_name,
  tl.date,
  tl.periods,
  tl.teacher_id,
  t.full_name AS teacher_name,
  t.department,
  tl.content,
  tl.objectives,
  tl.results,
  tl.problems,
  tl.suggestions,
  tl.created_at,
  tl.updated_at
FROM teaching_logs tl
LEFT JOIN subjects s ON s.subject_id = tl.subject_id
LEFT JOIN teachers t ON t.teacher_id = tl.teacher_id;

-- Grant view ให้ authenticated read ได้ (RLS ของ table จะถูกตรวจ)
GRANT SELECT ON teaching_logs_view TO authenticated;
