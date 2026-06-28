-- ============================================
-- 25_attendance_round2_fallback.sql
-- แก้ get_students_by_day ให้รอบ 2 ใช้สถานะรอบ 1 เป็นค่าเริ่มต้น
-- ถ้ายังไม่เคยเช็ครอบ 2
--
-- พฤติกรรมใหม่:
--   p_round = 1 → ดึงสถานะรอบ 1 (period != 99)
--   p_round = 2 → ดึงสถานะรอบ 2 (period = 99) ก่อน
--                 ถ้าไม่มี → fallback ดึงสถานะรอบ 1 มา pre-fill
-- ============================================

DROP FUNCTION IF EXISTS get_students_by_day(TEXT, DATE, INT, TEXT);

CREATE OR REPLACE FUNCTION get_students_by_day(
  p_subject_id TEXT,
  p_date       DATE,
  p_round      INT DEFAULT 1,
  p_class_id   TEXT DEFAULT NULL
) RETURNS TABLE (
  student_id  TEXT,
  full_name   TEXT,
  class_id    TEXT,
  status      TEXT,
  note        TEXT,
  late_at     TEXT,
  period      INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
BEGIN
  RETURN QUERY
  SELECT
    s.student_id,
    s.full_name,
    s.class_id,
    a.status,
    a.note,
    a.late_at,
    a.period
  FROM enrollments e
  JOIN students s ON s.student_id = e.student_id
  LEFT JOIN LATERAL (
    -- เลือก attendance ที่ตรงกับ student + subject + date
    -- ถ้า p_round = 1: ดึงเฉพาะ period != 99 (รอบ 1)
    -- ถ้า p_round = 2: ดึงทั้ง period 99 และ != 99 — แต่ priority period=99 ก่อน
    SELECT att.status, att.note, att.late_at, att.period
    FROM attendance att
    WHERE att.student_id = e.student_id
      AND att.subject_id = e.subject_id
      AND att.date = p_date
      AND (
        (p_round = 1 AND att.period != 99) OR
        (p_round = 2)
      )
    ORDER BY
      -- priority 1: ถ้ารอบ 2 มีข้อมูลแล้ว (period=99) → เอาก่อน
      -- priority 2: fallback ใช้รอบ 1
      CASE
        WHEN p_round = 2 AND att.period = 99 THEN 0
        ELSE 1
      END,
      att.created_at DESC NULLS LAST
    LIMIT 1
  ) a ON TRUE
  WHERE e.subject_id = p_subject_id
    AND (p_class_id IS NULL OR e.class_id = p_class_id)
    AND s.status = 'active'
  ORDER BY s.student_id;
END;
$body$;

GRANT EXECUTE ON FUNCTION get_students_by_day(TEXT, DATE, INT, TEXT) TO authenticated;
