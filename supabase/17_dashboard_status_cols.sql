-- ============================================
-- Phase 9.5 — Status columns + clickable stats
-- ============================================

-- ============================================
-- 1) get_students_by_status_today
--    รายชื่อนักเรียน + วิชา ที่มี status ที่ระบุ ในวันนั้น
-- ============================================
DROP FUNCTION IF EXISTS get_students_by_status_today(DATE, TEXT, INT);

CREATE OR REPLACE FUNCTION get_students_by_status_today(
  p_date   DATE,
  p_status TEXT,
  p_round  INT DEFAULT 1
) RETURNS TABLE (
  student_id   TEXT,
  full_name    TEXT,
  class_id     TEXT,
  subject_id   TEXT,
  subject_name TEXT,
  status       TEXT,
  note         TEXT,
  late_at      TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $body$
BEGIN
  RETURN QUERY
  WITH last_per_subject_student AS (
    SELECT DISTINCT ON (subject_id, student_id)
      subject_id, student_id, status, note, late_at
    FROM attendance
    WHERE date = p_date
      AND ((p_round = 1 AND period != 99) OR (p_round = 2 AND period = 99))
    ORDER BY subject_id, student_id, created_at DESC, period DESC
  )
  SELECT
    s.student_id,
    s.full_name,
    s.class_id,
    a.subject_id,
    sj.subject_name,
    a.status,
    a.note,
    a.late_at
  FROM last_per_subject_student a
  JOIN students s ON s.student_id = a.student_id
  LEFT JOIN subjects sj ON sj.subject_id = a.subject_id
  WHERE a.status = p_status
  ORDER BY s.student_id, a.subject_id;
END
$body$;

GRANT EXECUTE ON FUNCTION get_students_by_status_today(DATE, TEXT, INT) TO authenticated;


-- ============================================
-- 2) get_dashboard_subjects — เพิ่ม has_round_1, has_round_2, has_teaching_log
-- ============================================
DROP FUNCTION IF EXISTS get_dashboard_subjects(DATE, INT);

CREATE OR REPLACE FUNCTION get_dashboard_subjects(p_date DATE, p_round INT DEFAULT 1)
RETURNS TABLE (
  subject_id      TEXT,
  subject_name    TEXT,
  major           TEXT,
  course_type     TEXT,
  teacher_names   TEXT,
  enrolled        BIGINT,
  present         BIGINT,
  absent          BIGINT,
  late            BIGINT,
  sick            BIGINT,
  leave_cnt       BIGINT,
  unchecked       BIGINT,
  pct_present     NUMERIC,
  has_round_1     BOOLEAN,
  has_round_2     BOOLEAN,
  has_teaching_log BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $body$
BEGIN
  RETURN QUERY
  WITH att AS (
    SELECT a.subject_id AS sid, a.student_id, a.status
    FROM attendance a
    WHERE a.date = p_date
      AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
  ),
  att_dedup AS (
    SELECT DISTINCT ON (sid, student_id) sid, student_id, status
    FROM att
    ORDER BY sid, student_id, status
  ),
  enrolled_cnt AS (
    SELECT subject_id AS sid, COUNT(DISTINCT student_id) AS cnt
    FROM enrollments GROUP BY subject_id
  ),
  teacher_lists AS (
    SELECT st.subject_id AS sid, string_agg(t.full_name, ', ' ORDER BY t.full_name) AS names
    FROM subject_teachers st
    JOIN teachers t ON t.teacher_id = st.teacher_id
    GROUP BY st.subject_id
  ),
  r1 AS (
    SELECT DISTINCT subject_id AS sid FROM attendance
    WHERE date = p_date AND period != 99
  ),
  r2 AS (
    SELECT DISTINCT subject_id AS sid FROM attendance
    WHERE date = p_date AND period = 99
  ),
  tl AS (
    SELECT DISTINCT subject_id AS sid FROM teaching_logs
    WHERE date = p_date
  )
  SELECT
    s.subject_id,
    s.subject_name,
    s.major,
    s.course_type,
    COALESCE(tlist.names, '-') AS teacher_names,
    COALESCE(e.cnt, 0) AS enrolled,
    COUNT(*) FILTER (WHERE att_dedup.status = 'มา')     AS present,
    COUNT(*) FILTER (WHERE att_dedup.status = 'ขาด')    AS absent,
    COUNT(*) FILTER (WHERE att_dedup.status = 'สาย')    AS late,
    COUNT(*) FILTER (WHERE att_dedup.status = 'ลาป่วย') AS sick,
    COUNT(*) FILTER (WHERE att_dedup.status = 'ลากิจ')  AS leave_cnt,
    GREATEST(COALESCE(e.cnt, 0) - COUNT(att_dedup.student_id), 0)::BIGINT AS unchecked,
    CASE WHEN COUNT(att_dedup.status) = 0 THEN NULL
         ELSE ROUND(COUNT(*) FILTER (WHERE att_dedup.status = 'มา') * 100.0 / COUNT(att_dedup.status), 1)
    END AS pct_present,
    (r1.sid IS NOT NULL) AS has_round_1,
    (r2.sid IS NOT NULL) AS has_round_2,
    (tl.sid IS NOT NULL) AS has_teaching_log
  FROM subjects s
  LEFT JOIN att_dedup ON att_dedup.sid = s.subject_id
  LEFT JOIN enrolled_cnt e ON e.sid = s.subject_id
  LEFT JOIN teacher_lists tlist ON tlist.sid = s.subject_id
  LEFT JOIN r1 ON r1.sid = s.subject_id
  LEFT JOIN r2 ON r2.sid = s.subject_id
  LEFT JOIN tl ON tl.sid = s.subject_id
  WHERE EXISTS (SELECT 1 FROM subject_schedule sch WHERE sch.subject_id = s.subject_id AND sch.date = p_date)
     OR EXISTS (SELECT 1 FROM att WHERE att.sid = s.subject_id)
  GROUP BY s.subject_id, s.subject_name, s.major, s.course_type, e.cnt, tlist.names, r1.sid, r2.sid, tl.sid
  ORDER BY s.subject_id;
END
$body$;

GRANT EXECUTE ON FUNCTION get_dashboard_subjects(DATE, INT) TO authenticated;
