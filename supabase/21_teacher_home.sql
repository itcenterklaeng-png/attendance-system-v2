-- ============================================
-- get_teacher_home — รายการวิชาที่สอน + สถานะ + ห้องเรียน
-- ============================================

DROP FUNCTION IF EXISTS get_teacher_home(TEXT, DATE);

CREATE OR REPLACE FUNCTION get_teacher_home(p_teacher_id TEXT, p_date DATE)
RETURNS TABLE (
  subject_id       TEXT,
  subject_name     TEXT,
  major            TEXT,
  course_type      TEXT,
  total_hours      INT,
  start_date       DATE,
  end_date         DATE,
  today_periods    TEXT,
  has_round_1      BOOLEAN,
  has_round_2      BOOLEAN,
  has_teaching_log BOOLEAN,
  classes          JSONB
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $body$
BEGIN
  RETURN QUERY
  WITH my_subj AS (
    SELECT s.subject_id, s.subject_name, s.major, s.course_type,
           s.total_hours, s.start_date, s.end_date
    FROM subject_teachers st
    JOIN subjects s ON s.subject_id = st.subject_id
    WHERE st.teacher_id = p_teacher_id
  ),
  today_sched AS (
    SELECT sch.subject_id AS sid, sch.periods
    FROM subject_schedule sch
    WHERE sch.date = p_date
  ),
  has_r1 AS (
    SELECT DISTINCT a.subject_id AS sid FROM attendance a
    WHERE a.date = p_date AND a.period != 99
  ),
  has_r2 AS (
    SELECT DISTINCT a.subject_id AS sid FROM attendance a
    WHERE a.date = p_date AND a.period = 99
  ),
  has_tl AS (
    SELECT DISTINCT tl.subject_id AS sid FROM teaching_logs tl
    WHERE tl.date = p_date
  ),
  per_class AS (
    SELECT e.subject_id AS sid, e.class_id AS cid, COUNT(*) AS cnt
    FROM enrollments e
    JOIN students s ON s.student_id = e.student_id AND s.status = 'active'
    WHERE e.class_id IS NOT NULL
    GROUP BY e.subject_id, e.class_id
  ),
  subj_classes AS (
    SELECT
      pc.sid,
      jsonb_agg(jsonb_build_object(
        'class_id', c.class_id,
        'label',
          CASE
            WHEN c.level IS NULL THEN COALESCE(c.major, c.class_id)
            ELSE COALESCE(c.major, '') || ' ' || c.level || c.year::TEXT || '/' || c.room::TEXT
          END,
        'student_count', pc.cnt
      ) ORDER BY c.class_id) AS classes
    FROM per_class pc
    JOIN classes c ON c.class_id = pc.cid
    GROUP BY pc.sid
  )
  SELECT
    ms.subject_id,
    ms.subject_name,
    ms.major,
    ms.course_type,
    ms.total_hours,
    ms.start_date,
    ms.end_date,
    ts.periods,
    (h1.sid IS NOT NULL),
    (h2.sid IS NOT NULL),
    (htl.sid IS NOT NULL),
    COALESCE(sc.classes, '[]'::jsonb)
  FROM my_subj ms
  LEFT JOIN today_sched ts ON ts.sid = ms.subject_id
  LEFT JOIN has_r1 h1     ON h1.sid = ms.subject_id
  LEFT JOIN has_r2 h2     ON h2.sid = ms.subject_id
  LEFT JOIN has_tl htl    ON htl.sid = ms.subject_id
  LEFT JOIN subj_classes sc ON sc.sid = ms.subject_id
  ORDER BY (ts.periods IS NULL), ms.subject_id;  -- มีคาบวันนี้ขึ้นมาก่อน
END
$body$;

GRANT EXECUTE ON FUNCTION get_teacher_home(TEXT, DATE) TO authenticated;
