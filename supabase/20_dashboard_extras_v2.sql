-- ============================================
-- Phase 9.10 — เพิ่ม class info ใน status modal + นับวันใน top absentees
-- ============================================

-- ============================================
-- 1) get_students_by_status_today — เพิ่ม class_label, major
-- ============================================
DROP FUNCTION IF EXISTS get_students_by_status_today(DATE, TEXT, INT);

CREATE OR REPLACE FUNCTION get_students_by_status_today(p_date DATE, p_status TEXT, p_round INT DEFAULT 1)
RETURNS TABLE (
  out_student_id   TEXT,
  out_full_name    TEXT,
  out_class_label  TEXT,
  out_major        TEXT,
  out_subject_id   TEXT,
  out_subject_name TEXT,
  out_status       TEXT,
  out_note         TEXT,
  out_late_at      TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $body$
BEGIN
  RETURN QUERY
  WITH dedup AS (
    SELECT DISTINCT ON (a.subject_id, a.student_id)
      a.subject_id AS sid,
      a.student_id AS stid,
      a.status     AS st,
      a.note       AS nt,
      a.late_at    AS la
    FROM attendance a
    WHERE a.date = p_date
      AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
    ORDER BY a.subject_id, a.student_id, a.created_at DESC, a.period DESC
  )
  SELECT
    s.student_id,
    s.full_name,
    CASE
      WHEN c.level IS NULL THEN s.class_id
      ELSE c.level || c.year::TEXT || '/' || c.room::TEXT
    END AS class_label,
    COALESCE(c.major, '-'),
    d.sid,
    sj.subject_name,
    d.st,
    d.nt,
    d.la
  FROM dedup d
  JOIN students s ON s.student_id = d.stid
  LEFT JOIN classes c ON c.class_id = s.class_id
  LEFT JOIN subjects sj ON sj.subject_id = d.sid
  WHERE d.st = p_status
  ORDER BY s.student_id, d.sid;
END
$body$;

GRANT EXECUTE ON FUNCTION get_students_by_status_today(DATE, TEXT, INT) TO authenticated;


-- ============================================
-- 2) get_top_absentees — นับจำนวนวัน (distinct date)
-- ============================================
DROP FUNCTION IF EXISTS get_top_absentees(DATE, DATE, INT);

CREATE OR REPLACE FUNCTION get_top_absentees(
  p_date_from DATE DEFAULT NULL,
  p_date_to   DATE DEFAULT NULL,
  p_limit     INT  DEFAULT 30
) RETURNS TABLE (
  student_id   TEXT,
  full_name    TEXT,
  class_label  TEXT,
  major        TEXT,
  absent_cnt   BIGINT,
  late_cnt     BIGINT,
  sick_cnt     BIGINT,
  leave_cnt    BIGINT,
  total_miss   BIGINT,
  total_check  BIGINT,
  pct_present  NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $body$
BEGIN
  RETURN QUERY
  WITH att AS (
    -- 1 row ต่อ (student, subject, date, status) — dedupe period
    SELECT DISTINCT a.student_id AS sid, a.subject_id, a.date, a.status
    FROM attendance a
    WHERE a.period != 99
      AND (p_date_from IS NULL OR a.date >= p_date_from)
      AND (p_date_to IS NULL OR a.date <= p_date_to)
  ),
  per_student AS (
    SELECT
      sid,
      COUNT(DISTINCT date) FILTER (WHERE status = 'ขาด')     AS absent_days,
      COUNT(DISTINCT date) FILTER (WHERE status = 'สาย')     AS late_days,
      COUNT(DISTINCT date) FILTER (WHERE status = 'ลาป่วย')  AS sick_days,
      COUNT(DISTINCT date) FILTER (WHERE status = 'ลากิจ')   AS leave_days,
      COUNT(DISTINCT date) FILTER (WHERE status = 'มา')      AS present_days,
      COUNT(DISTINCT date)                                    AS total_days
    FROM att
    GROUP BY sid
    HAVING COUNT(DISTINCT date) FILTER (WHERE status != 'มา') > 0
  )
  SELECT
    s.student_id,
    s.full_name,
    CASE
      WHEN c.level IS NULL THEN s.class_id
      ELSE c.level || c.year::TEXT || '/' || c.room::TEXT
    END AS class_label,
    COALESCE(c.major, '-'),
    ps.absent_days::BIGINT,
    ps.late_days::BIGINT,
    ps.sick_days::BIGINT,
    ps.leave_days::BIGINT,
    (ps.absent_days + ps.late_days + ps.sick_days + ps.leave_days)::BIGINT AS total_miss,
    ps.total_days::BIGINT,
    CASE WHEN ps.total_days = 0 THEN 0
         ELSE ROUND(ps.present_days * 100.0 / ps.total_days, 1)
    END AS pct_present
  FROM per_student ps
  JOIN students s ON s.student_id = ps.sid
  LEFT JOIN classes c ON c.class_id = s.class_id
  WHERE s.status = 'active'
  ORDER BY (ps.absent_days + ps.late_days + ps.sick_days + ps.leave_days) DESC
  LIMIT p_limit;
END
$body$;

GRANT EXECUTE ON FUNCTION get_top_absentees(DATE, DATE, INT) TO authenticated;
