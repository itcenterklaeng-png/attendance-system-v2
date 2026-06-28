-- ============================================
-- Phase 4 — Report Functions
-- ============================================

-- ============================================
-- 1) get_attendance_summary
--   สรุปต่อ "นักเรียน" — count แต่ละ status ในช่วงวันที่
-- ============================================
CREATE OR REPLACE FUNCTION get_attendance_summary(
  p_subject_id  TEXT,
  p_date_from   DATE,
  p_date_to     DATE,
  p_class_id    TEXT DEFAULT NULL,
  p_round       INT  DEFAULT NULL    -- NULL = ทั้งสองรอบ, 1 = รอบ1, 2 = รอบ2
) RETURNS TABLE (
  student_id   TEXT,
  full_name    TEXT,
  class_id     TEXT,
  cnt_present  BIGINT,
  cnt_absent   BIGINT,
  cnt_late     BIGINT,
  cnt_sick     BIGINT,
  cnt_leave    BIGINT,
  cnt_total    BIGINT,
  pct_present  NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH base AS (
    SELECT a.student_id, a.status
    FROM attendance a
    WHERE a.subject_id = p_subject_id
      AND a.date BETWEEN p_date_from AND p_date_to
      AND (
        p_round IS NULL
        OR (p_round = 1 AND a.period != 99)
        OR (p_round = 2 AND a.period = 99)
      )
      AND (p_class_id IS NULL OR a.student_id IN (
        SELECT e.student_id FROM enrollments e WHERE e.subject_id = p_subject_id AND e.class_id = p_class_id
      ))
  ),
  agg AS (
    SELECT
      s.student_id,
      s.full_name,
      s.class_id,
      COUNT(*) FILTER (WHERE b.status = 'มา')     AS cnt_present,
      COUNT(*) FILTER (WHERE b.status = 'ขาด')    AS cnt_absent,
      COUNT(*) FILTER (WHERE b.status = 'สาย')    AS cnt_late,
      COUNT(*) FILTER (WHERE b.status = 'ลาป่วย') AS cnt_sick,
      COUNT(*) FILTER (WHERE b.status = 'ลากิจ')  AS cnt_leave,
      COUNT(*)                                     AS cnt_total
    FROM enrollments e
    JOIN students s ON s.student_id = e.student_id
    LEFT JOIN base b ON b.student_id = s.student_id
    WHERE e.subject_id = p_subject_id
      AND (p_class_id IS NULL OR e.class_id = p_class_id)
      AND s.status = 'active'
    GROUP BY s.student_id, s.full_name, s.class_id
  )
  SELECT
    agg.student_id, agg.full_name, agg.class_id,
    agg.cnt_present, agg.cnt_absent, agg.cnt_late, agg.cnt_sick, agg.cnt_leave, agg.cnt_total,
    CASE WHEN agg.cnt_total = 0 THEN 0
         ELSE ROUND(agg.cnt_present * 100.0 / agg.cnt_total, 1)
    END AS pct_present
  FROM agg
  ORDER BY agg.student_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- ============================================
-- 2) get_attendance_matrix
--   matrix: นักเรียน x วันที่ — สำหรับมุมมอง "ตาราง" รายวัน
--   Return: 1 row ต่อนักเรียน, ใน data จะมี JSONB array ของ {date, statuses[]}
-- ============================================
CREATE OR REPLACE FUNCTION get_attendance_matrix(
  p_subject_id  TEXT,
  p_date_from   DATE,
  p_date_to     DATE,
  p_class_id    TEXT DEFAULT NULL,
  p_round       INT  DEFAULT 1       -- รอบ 1 หรือ 2 (1 = ดูจริงตามคาบ, 2 = ดูรอบที่ 2)
) RETURNS TABLE (
  student_id  TEXT,
  full_name   TEXT,
  class_id    TEXT,
  cells       JSONB              -- { '2026-06-27': 'มา', '2026-06-28': 'ขาด', ... }
) AS $$
BEGIN
  RETURN QUERY
  WITH days AS (
    SELECT
      s.student_id,
      s.full_name,
      s.class_id,
      jsonb_object_agg(
        to_char(a.date, 'YYYY-MM-DD'),
        a.status
      ) FILTER (WHERE a.date IS NOT NULL) AS cells
    FROM enrollments e
    JOIN students s ON s.student_id = e.student_id
    LEFT JOIN LATERAL (
      SELECT a2.date, a2.status, a2.period
      FROM attendance a2
      WHERE a2.subject_id = p_subject_id
        AND a2.student_id = s.student_id
        AND a2.date BETWEEN p_date_from AND p_date_to
        AND ((p_round = 1 AND a2.period != 99) OR (p_round = 2 AND a2.period = 99))
      -- เก็บ status เดียวต่อวัน (status ที่เห็นล่าสุดของวันนั้น)
      ORDER BY a2.date, a2.period
      LIMIT 9999
    ) a ON true
    WHERE e.subject_id = p_subject_id
      AND (p_class_id IS NULL OR e.class_id = p_class_id)
      AND s.status = 'active'
    GROUP BY s.student_id, s.full_name, s.class_id
  )
  SELECT d.student_id, d.full_name, d.class_id, COALESCE(d.cells, '{}'::jsonb)
  FROM days d
  ORDER BY d.student_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- ============================================
-- 3) get_attendance_dates
--   คืนรายการวันที่ที่มีการเช็คชื่อในช่วง (สำหรับ header ของ matrix)
-- ============================================
CREATE OR REPLACE FUNCTION get_attendance_dates(
  p_subject_id  TEXT,
  p_date_from   DATE,
  p_date_to     DATE,
  p_round       INT DEFAULT 1
) RETURNS TABLE (date DATE) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT a.date
  FROM attendance a
  WHERE a.subject_id = p_subject_id
    AND a.date BETWEEN p_date_from AND p_date_to
    AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
  ORDER BY a.date;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- Grant ให้ทั้ง 2 role
GRANT EXECUTE ON FUNCTION get_attendance_summary(TEXT, DATE, DATE, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_attendance_matrix(TEXT, DATE, DATE, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_attendance_dates(TEXT, DATE, DATE, INT) TO authenticated;
