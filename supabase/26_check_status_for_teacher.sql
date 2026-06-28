-- ============================================
-- 26_check_status_for_teacher.sql
-- RPC สำหรับเมนู "ตรวจสอบสถานะการเช็คชื่อ" (เหมือน v1 V2.7.CI)
-- รับ teacher_id → คืน JSON array of subjects + dates + flags
-- ============================================

DROP FUNCTION IF EXISTS get_check_status_for_teacher(TEXT);

CREATE OR REPLACE FUNCTION get_check_status_for_teacher(p_teacher_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_result JSONB;
BEGIN
  WITH
  my_subjects AS (
    SELECT s.subject_id, s.subject_name, COALESCE(s.major, '') AS major
    FROM subject_teachers st
    JOIN subjects s ON s.subject_id = st.subject_id
    WHERE st.teacher_id = p_teacher_id
  ),
  sched_dates AS (
    SELECT ss.subject_id, ss.date
    FROM subject_schedule ss
    WHERE ss.subject_id IN (SELECT subject_id FROM my_subjects)
      AND COALESCE(ss.periods, '') <> ''
  ),
  has_r1 AS (
    SELECT DISTINCT a.subject_id, a.date
    FROM attendance a
    WHERE a.period <> 99
      AND a.subject_id IN (SELECT subject_id FROM my_subjects)
  ),
  has_r2 AS (
    SELECT DISTINCT a.subject_id, a.date
    FROM attendance a
    WHERE a.period = 99
      AND a.subject_id IN (SELECT subject_id FROM my_subjects)
  ),
  has_tl AS (
    SELECT DISTINCT t.subject_id, t.date
    FROM teaching_logs t
    WHERE t.subject_id IN (SELECT subject_id FROM my_subjects)
  ),
  flagged AS (
    SELECT
      sd.subject_id,
      sd.date,
      EXISTS(SELECT 1 FROM has_r1 r WHERE r.subject_id = sd.subject_id AND r.date = sd.date) AS r1,
      EXISTS(SELECT 1 FROM has_r2 r WHERE r.subject_id = sd.subject_id AND r.date = sd.date) AS r2,
      EXISTS(SELECT 1 FROM has_tl r WHERE r.subject_id = sd.subject_id AND r.date = sd.date) AS tl
    FROM sched_dates sd
  ),
  per_subject AS (
    SELECT
      ms.subject_id,
      ms.subject_name,
      ms.major,
      COUNT(f.date)                              AS total_dates,
      COUNT(f.date) FILTER (WHERE f.r1)          AS attended_r1,
      COUNT(f.date) FILTER (WHERE f.r2)          AS attended_r2,
      COUNT(f.date) FILTER (WHERE f.tl)          AS teaching_log_count,
      COALESCE(
        jsonb_agg(jsonb_build_object(
          'date',            f.date,
          'hasAttendanceR1', f.r1,
          'hasAttendanceR2', f.r2,
          'hasTeachingLog',  f.tl
        ) ORDER BY f.date)
        FILTER (WHERE f.date IS NOT NULL),
        '[]'::jsonb
      ) AS dates
    FROM my_subjects ms
    LEFT JOIN flagged f ON f.subject_id = ms.subject_id
    GROUP BY ms.subject_id, ms.subject_name, ms.major
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'subjectId',        subject_id,
    'subjectName',      subject_name,
    'major',            major,
    'totalDates',       total_dates,
    'attendedR1Count',  attended_r1,
    'attendedR2Count',  attended_r2,
    'teachingLogCount', teaching_log_count,
    'dates',            dates
  ) ORDER BY subject_name), '[]'::jsonb)
  INTO v_result
  FROM per_subject;

  RETURN v_result;
END;
$body$;

GRANT EXECUTE ON FUNCTION get_check_status_for_teacher(TEXT) TO authenticated;
