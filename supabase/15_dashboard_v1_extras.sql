-- ============================================
-- Phase 9.3 — Dashboard extras (เหมือน v1)
-- ============================================

-- ============================================
-- 1) get_top_teachers_today — ครูเช็คชื่อเร็วที่สุดของวัน
-- ============================================
CREATE OR REPLACE FUNCTION get_top_teachers_today(
  p_date  DATE,
  p_round INT DEFAULT 1,
  p_limit INT DEFAULT 10
) RETURNS TABLE (
  teacher_id    TEXT,
  full_name     TEXT,
  department    TEXT,
  earliest_at   TIMESTAMPTZ,
  subject_count BIGINT,
  total_check   BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH first_checks AS (
    SELECT a.checked_by, a.subject_id, MIN(a.created_at) AS first_at
    FROM attendance a
    WHERE a.date = p_date
      AND a.checked_by IS NOT NULL
      AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
    GROUP BY a.checked_by, a.subject_id
  ),
  per_teacher AS (
    SELECT
      fc.checked_by AS tid,
      MIN(fc.first_at) AS earliest,
      COUNT(DISTINCT fc.subject_id) AS subj_cnt
    FROM first_checks fc
    GROUP BY fc.checked_by
  ),
  total_per AS (
    SELECT a.checked_by AS tid, COUNT(*) AS cnt
    FROM attendance a
    WHERE a.date = p_date
      AND a.checked_by IS NOT NULL
      AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
    GROUP BY a.checked_by
  )
  SELECT
    t.teacher_id,
    t.full_name,
    t.department,
    pt.earliest,
    pt.subj_cnt,
    COALESCE(tp.cnt, 0) AS total_check
  FROM per_teacher pt
  JOIN teachers t ON t.teacher_id = pt.tid
  LEFT JOIN total_per tp ON tp.tid = pt.tid
  ORDER BY pt.earliest ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_top_teachers_today(DATE, INT, INT) TO authenticated;


-- ============================================
-- 2) get_trend_7days — เทรนด์ % เข้าเรียน 7 วันย้อนหลัง
-- ============================================
CREATE OR REPLACE FUNCTION get_trend_7days(
  p_end_date DATE,
  p_round    INT DEFAULT 1
) RETURNS TABLE (
  date DATE,
  total_check BIGINT,
  present     BIGINT,
  pct_present NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH date_series AS (
    SELECT (p_end_date - i)::DATE AS d
    FROM generate_series(0, 6) i
  ),
  daily AS (
    SELECT
      a.date AS dt,
      COUNT(*) AS total_check,
      COUNT(*) FILTER (WHERE a.status = 'มา') AS present
    FROM attendance a
    WHERE a.date BETWEEN (p_end_date - 6) AND p_end_date
      AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
    GROUP BY a.date
  )
  SELECT
    ds.d,
    COALESCE(dy.total_check, 0) AS total_check,
    COALESCE(dy.present, 0)     AS present,
    CASE WHEN COALESCE(dy.total_check, 0) = 0 THEN 0
         ELSE ROUND(dy.present * 100.0 / dy.total_check, 1)
    END AS pct_present
  FROM date_series ds
  LEFT JOIN daily dy ON dy.dt = ds.d
  ORDER BY ds.d;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_trend_7days(DATE, INT) TO authenticated;


-- ============================================
-- 3) get_subject_detail_by_day — รายชื่อ + status ของวิชา/วัน
-- ============================================
CREATE OR REPLACE FUNCTION get_subject_detail_by_day(
  p_subject_id TEXT,
  p_date       DATE,
  p_round      INT DEFAULT 1
) RETURNS TABLE (
  student_id TEXT,
  full_name  TEXT,
  class_id   TEXT,
  status     TEXT,
  note       TEXT,
  late_at    TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT ON (s.student_id)
    s.student_id,
    s.full_name,
    s.class_id,
    a.status,
    a.note,
    a.late_at
  FROM enrollments e
  JOIN students s ON s.student_id = e.student_id
  LEFT JOIN attendance a
    ON a.student_id = e.student_id
   AND a.subject_id = e.subject_id
   AND a.date = p_date
   AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
  WHERE e.subject_id = p_subject_id
    AND s.status = 'active'
  ORDER BY s.student_id, a.period NULLS LAST;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_subject_detail_by_day(TEXT, DATE, INT) TO authenticated;
