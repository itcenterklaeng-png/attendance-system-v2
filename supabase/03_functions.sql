-- ============================================
-- Stored Functions (atomic operations)
-- ที่จะ port จาก Apps Script
-- ============================================

-- ============================================
-- save_daily_attendance
--   แทน saveDailyAttendance ใน Attendance.gs
--   ⭐ ทุกอย่างใน transaction เดียว — race condition หายไปอัตโนมัติ
--   ⭐ ไม่ต้อง clearContent ทั้งชีท → ข้อมูลไม่หาย
-- ============================================
CREATE OR REPLACE FUNCTION save_daily_attendance(
  p_subject_id  TEXT,
  p_date        DATE,
  p_round       INT,         -- 1 หรือ 2
  p_records     JSONB        -- [{student_id, status, note, late_at, class_id}, ...]
) RETURNS JSONB AS $$
DECLARE
  v_teacher_id   TEXT;
  v_is_admin     BOOLEAN;
  v_periods      INT[];
  v_schedule     TEXT;
  v_round1_missing INT;
  v_deleted      INT := 0;
  v_added        INT := 0;
  v_rec          JSONB;
  v_period       INT;
BEGIN
  -- 1) auth
  v_teacher_id := current_teacher_id();
  v_is_admin   := app_current_role() = 'admin';
  IF v_teacher_id IS NULL AND NOT v_is_admin THEN
    RAISE EXCEPTION 'ไม่พบ teacher_id ของผู้ใช้';
  END IF;
  IF NOT v_is_admin AND NOT is_teacher_of_subject(p_subject_id) THEN
    RAISE EXCEPTION 'คุณไม่ได้สอนวิชานี้';
  END IF;

  -- 2) หา periods ของวันนั้นจาก subject_schedule (ถ้าไม่มี → [1])
  SELECT periods INTO v_schedule
    FROM subject_schedule
    WHERE subject_id = p_subject_id AND date = p_date;
  IF v_schedule IS NOT NULL THEN
    v_periods := string_to_array(v_schedule, ',')::INT[];
  ELSE
    v_periods := ARRAY[1];
  END IF;

  -- 3) ถ้า round 2 → ต้องตรวจรอบ 1 ครบทุกคน enrolled ก่อน
  IF p_round = 2 THEN
    SELECT COUNT(*) INTO v_round1_missing
      FROM enrollments e
      LEFT JOIN attendance a
        ON a.student_id = e.student_id
       AND a.subject_id = e.subject_id
       AND a.date = p_date
       AND a.period != 99
      WHERE e.subject_id = p_subject_id
        AND a.id IS NULL;
    IF v_round1_missing > 0 THEN
      RAISE EXCEPTION 'ต้องเช็คชื่อรอบ 1 ให้ครบทุกคนก่อน (ยังขาด % คน)', v_round1_missing;
    END IF;
  END IF;

  -- 4) ลบของเก่า (ของ round เดียวกัน) เฉพาะ student_id ที่อยู่ใน records
  IF p_round = 2 THEN
    DELETE FROM attendance
      WHERE subject_id = p_subject_id
        AND date = p_date
        AND period = 99
        AND student_id IN (
          SELECT (r->>'student_id')::TEXT FROM jsonb_array_elements(p_records) r
        );
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
  ELSE
    DELETE FROM attendance
      WHERE subject_id = p_subject_id
        AND date = p_date
        AND period != 99
        AND student_id IN (
          SELECT (r->>'student_id')::TEXT FROM jsonb_array_elements(p_records) r
        );
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
  END IF;

  -- 5) แทรกใหม่
  IF p_round = 2 THEN
    -- รอบ 2 = 1 แถวต่อคน (period 99)
    FOR v_rec IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
      INSERT INTO attendance (date, subject_id, student_id, status, period, checked_by, note, late_at)
      VALUES (
        p_date,
        p_subject_id,
        v_rec->>'student_id',
        v_rec->>'status',
        99,
        v_teacher_id,
        NULLIF(v_rec->>'note', ''),
        CASE WHEN v_rec->>'status' = 'สาย' THEN NULLIF(v_rec->>'late_at','') END
      );
      v_added := v_added + 1;
    END LOOP;
  ELSE
    -- รอบ 1 = N แถว ตามจำนวนคาบของวัน
    FOR v_rec IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
      FOREACH v_period IN ARRAY v_periods
      LOOP
        INSERT INTO attendance (date, subject_id, student_id, status, period, checked_by, note, late_at)
        VALUES (
          p_date,
          p_subject_id,
          v_rec->>'student_id',
          v_rec->>'status',
          v_period,
          v_teacher_id,
          NULLIF(v_rec->>'note', ''),
          CASE WHEN v_rec->>'status' = 'สาย' THEN NULLIF(v_rec->>'late_at','') END
        );
        v_added := v_added + 1;
      END LOOP;
    END LOOP;
  END IF;

  -- 6) log
  INSERT INTO logs (user_id, action, metadata)
  VALUES (
    auth.uid(),
    'CHECK_ATTENDANCE_DAY',
    jsonb_build_object(
      'subject_id', p_subject_id,
      'date', p_date,
      'round', p_round,
      'students', jsonb_array_length(p_records),
      'deleted', v_deleted,
      'added', v_added
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', 'บันทึกการเช็คชื่อสำเร็จ',
    'deleted', v_deleted,
    'added', v_added
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================
-- bulk_enroll_class
--   แทน bulkEnrollClass ใน Admin.gs
-- ============================================
CREATE OR REPLACE FUNCTION bulk_enroll_class(
  p_class_id    TEXT,
  p_subject_ids TEXT[]
) RETURNS JSONB AS $$
DECLARE
  v_added INT := 0;
BEGIN
  IF app_current_role() != 'admin' THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  WITH inserted AS (
    INSERT INTO enrollments (student_id, subject_id, class_id)
    SELECT s.student_id, sj.subject_id, p_class_id
      FROM students s
      CROSS JOIN unnest(p_subject_ids) AS sj(subject_id)
     WHERE s.class_id = p_class_id
       AND s.status = 'active'
    ON CONFLICT (student_id, subject_id) DO NOTHING
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_added FROM inserted;

  INSERT INTO logs (user_id, action, metadata)
  VALUES (auth.uid(), 'BULK_ENROLL',
    jsonb_build_object('class_id', p_class_id, 'subjects', p_subject_ids, 'added', v_added));

  RETURN jsonb_build_object('success', true, 'added', v_added);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================
-- bulk_unenroll_class_subject
--   แทน bulkUnenrollClassSubject ใน Admin.gs
-- ============================================
CREATE OR REPLACE FUNCTION bulk_unenroll_class_subject(
  p_class_id    TEXT,
  p_subject_id  TEXT
) RETURNS JSONB AS $$
DECLARE
  v_removed INT;
BEGIN
  IF app_current_role() != 'admin' THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  DELETE FROM enrollments
    WHERE class_id = p_class_id
      AND subject_id = p_subject_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  INSERT INTO logs (user_id, action, metadata)
  VALUES (auth.uid(), 'BULK_UNENROLL',
    jsonb_build_object('class_id', p_class_id, 'subject_id', p_subject_id, 'removed', v_removed));

  RETURN jsonb_build_object('success', true, 'removed', v_removed);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================
-- get_students_by_day
--   แทน getStudentsByDay ใน Attendance.gs
--   คืน enrolled students + status ของวันที่ระบุ + round
-- ============================================
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
) AS $$
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
  LEFT JOIN attendance a
    ON a.student_id = e.student_id
   AND a.subject_id = e.subject_id
   AND a.date = p_date
   AND ((p_round = 2 AND a.period = 99) OR (p_round = 1 AND a.period != 99))
  WHERE e.subject_id = p_subject_id
    AND (p_class_id IS NULL OR e.class_id = p_class_id)
    AND s.status = 'active'
  ORDER BY s.student_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
