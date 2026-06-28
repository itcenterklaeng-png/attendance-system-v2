-- ============================================
-- Phase 9 — Dashboard Functions
-- ============================================

-- ============================================
-- 1) get_dashboard_summary
--    สรุปจำนวนเช็คชื่อทั้งระบบในวันที่ระบุ (รอบ 1 = period != 99)
-- ============================================
CREATE OR REPLACE FUNCTION get_dashboard_summary(
  p_date DATE,
  p_round INT DEFAULT 1
) RETURNS JSONB AS $$
DECLARE
  v_summary JSONB;
  v_total_subjects INT;
  v_checked_subjects INT;
BEGIN
  SELECT jsonb_build_object(
    'present', COUNT(*) FILTER (WHERE status = 'มา'),
    'absent',  COUNT(*) FILTER (WHERE status = 'ขาด'),
    'late',    COUNT(*) FILTER (WHERE status = 'สาย'),
    'sick',    COUNT(*) FILTER (WHERE status = 'ลาป่วย'),
    'leave',   COUNT(*) FILTER (WHERE status = 'ลากิจ'),
    'total',   COUNT(*),
    'unique_students', COUNT(DISTINCT student_id),
    'unique_subjects', COUNT(DISTINCT subject_id)
  ) INTO v_summary
  FROM attendance
  WHERE date = p_date
    AND ((p_round = 1 AND period != 99) OR (p_round = 2 AND period = 99));

  -- count distinct subjects with schedule that day
  SELECT COUNT(DISTINCT subject_id) INTO v_total_subjects
  FROM subject_schedule WHERE date = p_date;

  -- count subjects that were actually checked
  SELECT COUNT(DISTINCT subject_id) INTO v_checked_subjects
  FROM attendance
  WHERE date = p_date
    AND ((p_round = 1 AND period != 99) OR (p_round = 2 AND period = 99));

  v_summary := v_summary
    || jsonb_build_object('scheduled_subjects', COALESCE(v_total_subjects, 0))
    || jsonb_build_object('checked_subjects', COALESCE(v_checked_subjects, 0));

  RETURN v_summary;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_dashboard_summary(DATE, INT) TO authenticated;

-- ============================================
-- 2) get_top_absentees
--    Top N นักเรียนที่ขาด+สาย+ลา สูงสุด (รวมทั้งภาคเรียน หรือช่วง)
-- ============================================
CREATE OR REPLACE FUNCTION get_top_absentees(
  p_date_from DATE DEFAULT NULL,
  p_date_to   DATE DEFAULT NULL,
  p_limit     INT  DEFAULT 30
) RETURNS TABLE (
  student_id  TEXT,
  full_name   TEXT,
  class_id    TEXT,
  major       TEXT,
  absent_cnt  BIGINT,
  late_cnt    BIGINT,
  sick_cnt    BIGINT,
  leave_cnt   BIGINT,
  total_miss  BIGINT,
  total_check BIGINT,
  pct_present NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH att AS (
    SELECT a.student_id,
           a.status
    FROM attendance a
    WHERE a.period != 99
      AND (p_date_from IS NULL OR a.date >= p_date_from)
      AND (p_date_to IS NULL OR a.date <= p_date_to)
  ),
  agg AS (
    SELECT
      s.student_id,
      s.full_name,
      s.class_id,
      c.major,
      COUNT(*) FILTER (WHERE att.status = 'ขาด')    AS absent_cnt,
      COUNT(*) FILTER (WHERE att.status = 'สาย')    AS late_cnt,
      COUNT(*) FILTER (WHERE att.status = 'ลาป่วย') AS sick_cnt,
      COUNT(*) FILTER (WHERE att.status = 'ลากิจ')  AS leave_cnt,
      COUNT(*) FILTER (WHERE att.status = 'มา')     AS present_cnt,
      COUNT(*)                                      AS total_check
    FROM students s
    LEFT JOIN classes c ON c.class_id = s.class_id
    LEFT JOIN att ON att.student_id = s.student_id
    WHERE s.status = 'active'
    GROUP BY s.student_id, s.full_name, s.class_id, c.major
    HAVING COUNT(*) FILTER (WHERE att.status != 'มา') > 0
  )
  SELECT
    agg.student_id, agg.full_name, agg.class_id, agg.major,
    agg.absent_cnt, agg.late_cnt, agg.sick_cnt, agg.leave_cnt,
    (agg.absent_cnt + agg.late_cnt + agg.sick_cnt + agg.leave_cnt) AS total_miss,
    agg.total_check,
    CASE WHEN agg.total_check = 0 THEN 0
         ELSE ROUND(agg.present_cnt * 100.0 / agg.total_check, 1)
    END AS pct_present
  FROM agg
  ORDER BY (agg.absent_cnt + agg.late_cnt + agg.sick_cnt + agg.leave_cnt) DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_top_absentees(DATE, DATE, INT) TO authenticated;

-- ============================================
-- 3) get_dashboard_subjects
--    สถิติแยกรายวิชา ของวันที่ระบุ
-- ============================================
CREATE OR REPLACE FUNCTION get_dashboard_subjects(
  p_date DATE,
  p_round INT DEFAULT 1
) RETURNS TABLE (
  subject_id    TEXT,
  subject_name  TEXT,
  major         TEXT,
  course_type   TEXT,
  teacher_names TEXT,
  enrolled      BIGINT,
  present       BIGINT,
  absent        BIGINT,
  late          BIGINT,
  sick          BIGINT,
  leave_cnt     BIGINT,
  unchecked     BIGINT,
  pct_present   NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH att AS (
    SELECT a.subject_id, a.student_id, a.status
    FROM attendance a
    WHERE a.date = p_date
      AND ((p_round = 1 AND a.period != 99) OR (p_round = 2 AND a.period = 99))
  ),
  -- รวม attendance หลายแถวต่อ student (ถ้ามีหลาย period) → เอาค่าเดียว
  att_dedup AS (
    SELECT DISTINCT ON (subject_id, student_id) subject_id, student_id, status
    FROM att
    ORDER BY subject_id, student_id, status
  ),
  enrolled AS (
    SELECT subject_id, COUNT(DISTINCT student_id) AS cnt
    FROM enrollments GROUP BY subject_id
  ),
  teacher_lists AS (
    SELECT st.subject_id, string_agg(t.full_name, ', ' ORDER BY t.full_name) AS names
    FROM subject_teachers st
    JOIN teachers t ON t.teacher_id = st.teacher_id
    GROUP BY st.subject_id
  )
  SELECT
    s.subject_id,
    s.subject_name,
    s.major,
    s.course_type,
    COALESCE(tl.names, '-') AS teacher_names,
    COALESCE(e.cnt, 0) AS enrolled,
    COUNT(*) FILTER (WHERE att_dedup.status = 'มา')     AS present,
    COUNT(*) FILTER (WHERE att_dedup.status = 'ขาด')    AS absent,
    COUNT(*) FILTER (WHERE att_dedup.status = 'สาย')    AS late,
    COUNT(*) FILTER (WHERE att_dedup.status = 'ลาป่วย') AS sick,
    COUNT(*) FILTER (WHERE att_dedup.status = 'ลากิจ')  AS leave_cnt,
    GREATEST(COALESCE(e.cnt, 0) - COUNT(att_dedup.student_id), 0)::BIGINT AS unchecked,
    CASE WHEN COUNT(att_dedup.status) = 0 THEN NULL
         ELSE ROUND(COUNT(*) FILTER (WHERE att_dedup.status = 'มา') * 100.0 / COUNT(att_dedup.status), 1)
    END AS pct_present
  FROM subjects s
  LEFT JOIN att_dedup ON att_dedup.subject_id = s.subject_id
  LEFT JOIN enrolled e ON e.subject_id = s.subject_id
  LEFT JOIN teacher_lists tl ON tl.subject_id = s.subject_id
  -- เฉพาะวิชาที่มีตารางสอนวันนั้น หรือ มี attendance วันนั้น
  WHERE EXISTS (SELECT 1 FROM subject_schedule WHERE subject_id = s.subject_id AND date = p_date)
     OR EXISTS (SELECT 1 FROM att WHERE subject_id = s.subject_id)
  GROUP BY s.subject_id, s.subject_name, s.major, s.course_type, e.cnt, tl.names
  ORDER BY s.subject_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_dashboard_subjects(DATE, INT) TO authenticated;
