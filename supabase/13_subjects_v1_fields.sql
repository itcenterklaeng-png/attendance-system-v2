-- ============================================
-- เพิ่ม columns ใน subjects ให้ตรง v1
-- ============================================
ALTER TABLE subjects
  ADD COLUMN IF NOT EXISTS total_hours INT,
  ADD COLUMN IF NOT EXISTS start_date  DATE,
  ADD COLUMN IF NOT EXISTS end_date    DATE,
  ADD COLUMN IF NOT EXISTS department  TEXT;

-- ============================================
-- view: subjects_stats — สรุปสำหรับ admin (ครูผู้สอน + ตารางสอน)
-- ============================================
CREATE OR REPLACE VIEW subjects_stats AS
SELECT
  s.subject_id,
  s.subject_name,
  s.major,
  s.department,
  s.course_type,
  s.total_hours,
  s.start_date,
  s.end_date,
  COALESCE(t_cnt.teacher_count, 0)    AS teacher_count,
  COALESCE(sc_cnt.day_count, 0)       AS schedule_days,
  COALESCE(sc_cnt.period_count, 0)    AS schedule_periods
FROM subjects s
LEFT JOIN (
  SELECT subject_id, COUNT(*) AS teacher_count
  FROM subject_teachers GROUP BY subject_id
) t_cnt ON t_cnt.subject_id = s.subject_id
LEFT JOIN (
  SELECT subject_id,
         COUNT(DISTINCT date) AS day_count,
         SUM(array_length(string_to_array(periods, ','), 1)) AS period_count
  FROM subject_schedule GROUP BY subject_id
) sc_cnt ON sc_cnt.subject_id = s.subject_id;

GRANT SELECT ON subjects_stats TO authenticated;

-- ============================================
-- view: classes_stats — นับนักเรียนใน class
-- ============================================
CREATE OR REPLACE VIEW classes_stats AS
SELECT
  c.class_id,
  c.major,
  c.level,
  c.year,
  c.room,
  c.advisor_id,
  t.full_name AS advisor_name,
  COALESCE(s_cnt.student_count, 0) AS student_count
FROM classes c
LEFT JOIN teachers t ON t.teacher_id = c.advisor_id
LEFT JOIN (
  SELECT class_id, COUNT(*) AS student_count
  FROM students WHERE status = 'active'
  GROUP BY class_id
) s_cnt ON s_cnt.class_id = c.class_id;

GRANT SELECT ON classes_stats TO authenticated;
