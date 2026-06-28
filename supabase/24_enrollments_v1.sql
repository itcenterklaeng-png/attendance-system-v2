-- ============================================
-- 24_enrollments_v1.sql
-- เพิ่ม RPC ที่ใช้ในเมนู "ลงทะเบียน" (admin) ให้ครบเหมือน v1
--   1. delete_enrollment(student_id, subject_id) — ลบทีละคน
--   2. get_subject_schedule_counts() — สรุปจำนวนวัน/คาบ/วันแรก-สุดท้าย ของแต่ละวิชา
-- ============================================

-- ---------- 1. delete_enrollment ----------
DROP FUNCTION IF EXISTS delete_enrollment(TEXT, TEXT);

CREATE OR REPLACE FUNCTION delete_enrollment(
  p_student_id TEXT,
  p_subject_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_removed INT;
BEGIN
  IF app_current_role() != 'admin' THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  DELETE FROM enrollments
   WHERE student_id = p_student_id
     AND subject_id = p_subject_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  INSERT INTO logs (user_id, action, metadata)
  VALUES (auth.uid(), 'UNENROLL_ONE',
    jsonb_build_object('student_id', p_student_id, 'subject_id', p_subject_id, 'removed', v_removed));

  RETURN jsonb_build_object('success', true, 'removed', v_removed);
END;
$body$;

GRANT EXECUTE ON FUNCTION delete_enrollment(TEXT, TEXT) TO authenticated;


-- ---------- 2. get_subject_schedule_counts ----------
DROP FUNCTION IF EXISTS get_subject_schedule_counts();

CREATE OR REPLACE FUNCTION get_subject_schedule_counts()
RETURNS TABLE (
  subject_id  TEXT,
  days        BIGINT,
  periods     BIGINT,
  first_date  DATE,
  last_date   DATE
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
  SELECT
    ss.subject_id,
    COUNT(DISTINCT ss.date)::BIGINT AS days,
    COALESCE(SUM(
      CASE
        WHEN ss.periods IS NULL OR ss.periods = '' THEN 0
        ELSE array_length(string_to_array(ss.periods, ','), 1)
      END
    ), 0)::BIGINT AS periods,
    MIN(ss.date) AS first_date,
    MAX(ss.date) AS last_date
  FROM subject_schedule ss
  GROUP BY ss.subject_id;
$body$;

GRANT EXECUTE ON FUNCTION get_subject_schedule_counts() TO authenticated;
