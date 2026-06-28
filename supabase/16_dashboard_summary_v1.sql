-- ============================================
-- ปรับ get_dashboard_summary ให้ตรง v1
-- เพิ่ม total_students + yesterday comparison
-- ============================================

CREATE OR REPLACE FUNCTION get_dashboard_summary(
  p_date DATE,
  p_round INT DEFAULT 1
) RETURNS JSONB AS $function$
DECLARE
  v_summary JSONB;
  v_yesterday JSONB;
  v_total_students INT;
  v_total_subjects INT;
  v_checked_subjects INT;
  v_yesterday_date DATE;
BEGIN
  -- ของวันที่ระบุ
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

  -- เมื่อวาน (วันก่อน p_date)
  v_yesterday_date := p_date - INTERVAL '1 day';
  SELECT jsonb_build_object(
    'present', COUNT(*) FILTER (WHERE status = 'มา'),
    'absent',  COUNT(*) FILTER (WHERE status = 'ขาด'),
    'late',    COUNT(*) FILTER (WHERE status = 'สาย'),
    'sick',    COUNT(*) FILTER (WHERE status = 'ลาป่วย'),
    'leave',   COUNT(*) FILTER (WHERE status = 'ลากิจ'),
    'total',   COUNT(*)
  ) INTO v_yesterday
  FROM attendance
  WHERE date = v_yesterday_date
    AND ((p_round = 1 AND period != 99) OR (p_round = 2 AND period = 99));

  -- จำนวนนักเรียน active ทั้งระบบ
  SELECT COUNT(*) INTO v_total_students
  FROM students WHERE status = 'active';

  -- subjects scheduled today
  SELECT COUNT(DISTINCT subject_id) INTO v_total_subjects
  FROM subject_schedule WHERE date = p_date;

  -- subjects actually checked
  SELECT COUNT(DISTINCT subject_id) INTO v_checked_subjects
  FROM attendance
  WHERE date = p_date
    AND ((p_round = 1 AND period != 99) OR (p_round = 2 AND period = 99));

  v_summary := v_summary
    || jsonb_build_object('total_students', COALESCE(v_total_students, 0))
    || jsonb_build_object('scheduled_subjects', COALESCE(v_total_subjects, 0))
    || jsonb_build_object('checked_subjects', COALESCE(v_checked_subjects, 0))
    || jsonb_build_object('yesterday', v_yesterday);

  RETURN v_summary;
END;
$function$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_dashboard_summary(DATE, INT) TO authenticated;
