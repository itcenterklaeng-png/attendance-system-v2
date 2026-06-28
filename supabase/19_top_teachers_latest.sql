-- ============================================
-- get_top_teachers_today — เพิ่ม latest_at + รองรับ p_round = NULL
-- ============================================

DROP FUNCTION IF EXISTS get_top_teachers_today(DATE, INT, INT);

CREATE OR REPLACE FUNCTION get_top_teachers_today(
  p_date  DATE,
  p_round INT DEFAULT NULL,    -- NULL = ทั้ง 2 รอบ
  p_limit INT DEFAULT 20
) RETURNS TABLE (
  teacher_id    TEXT,
  full_name     TEXT,
  department    TEXT,
  earliest_at   TIMESTAMPTZ,
  latest_at     TIMESTAMPTZ,
  subject_count BIGINT,
  total_check   BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $body$
BEGIN
  RETURN QUERY
  WITH per_subj AS (
    SELECT a.checked_by, a.subject_id,
           MIN(a.created_at) AS first_at,
           MAX(a.created_at) AS last_at,
           COUNT(*) AS cnt
    FROM attendance a
    WHERE a.date = p_date
      AND a.checked_by IS NOT NULL
      AND (
        p_round IS NULL
        OR (p_round = 1 AND a.period != 99)
        OR (p_round = 2 AND a.period = 99)
      )
    GROUP BY a.checked_by, a.subject_id
  ),
  agg AS (
    SELECT
      ps.checked_by AS tid,
      MIN(ps.first_at) AS earliest,
      MAX(ps.last_at)  AS latest,
      COUNT(DISTINCT ps.subject_id) AS subj_cnt,
      SUM(ps.cnt) AS tot
    FROM per_subj ps
    GROUP BY ps.checked_by
  )
  SELECT
    t.teacher_id,
    t.full_name,
    t.department,
    a.earliest,
    a.latest,
    a.subj_cnt,
    a.tot
  FROM agg a
  JOIN teachers t ON t.teacher_id = a.tid
  ORDER BY a.latest DESC
  LIMIT p_limit;
END
$body$;

GRANT EXECUTE ON FUNCTION get_top_teachers_today(DATE, INT, INT) TO authenticated;
