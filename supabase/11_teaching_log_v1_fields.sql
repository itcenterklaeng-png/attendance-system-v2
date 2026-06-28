-- ============================================
-- เพิ่ม columns ใน teaching_logs ให้ตรง v1
-- ============================================

ALTER TABLE teaching_logs
  ADD COLUMN IF NOT EXISTS materials  TEXT,    -- สื่อและอุปกรณ์
  ADD COLUMN IF NOT EXISTS motivation TEXT,    -- วิธีเสริมแรง
  ADD COLUMN IF NOT EXISTS image_url  TEXT;    -- URL รูปภาพ (Supabase Storage หรือ base64)

-- แก้ view ให้ include fields ใหม่
DROP VIEW IF EXISTS teaching_logs_view;
CREATE VIEW teaching_logs_view AS
SELECT
  tl.id,
  tl.subject_id,
  s.subject_name,
  tl.date,
  tl.periods,
  tl.teacher_id,
  t.full_name AS teacher_name,
  t.department,
  tl.content,
  tl.objectives,
  tl.materials,
  tl.motivation,
  tl.results,
  tl.problems,
  tl.suggestions,
  tl.image_url,
  tl.created_at,
  tl.updated_at
FROM teaching_logs tl
LEFT JOIN subjects s ON s.subject_id = tl.subject_id
LEFT JOIN teachers t ON t.teacher_id = tl.teacher_id;

GRANT SELECT ON teaching_logs_view TO authenticated;

-- ============================================
-- แก้ save_teaching_log ให้รับ fields ใหม่
-- ============================================
DROP FUNCTION IF EXISTS save_teaching_log(TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION save_teaching_log(
  p_subject_id  TEXT,
  p_date        DATE,
  p_periods     TEXT,
  p_materials   TEXT,
  p_content     TEXT,
  p_motivation  TEXT,
  p_results     TEXT,
  p_problems    TEXT,
  p_image_url   TEXT DEFAULT NULL,
  p_objectives  TEXT DEFAULT NULL,
  p_suggestions TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_teacher_id  TEXT;
  v_is_admin    BOOLEAN;
  v_id          BIGINT;
BEGIN
  v_teacher_id := current_teacher_id();
  v_is_admin   := app_current_role() = 'admin';

  IF v_teacher_id IS NULL AND NOT v_is_admin THEN
    RAISE EXCEPTION 'ไม่พบ teacher_id ของผู้ใช้';
  END IF;
  IF NOT v_is_admin AND NOT is_teacher_of_subject(p_subject_id) THEN
    RAISE EXCEPTION 'คุณไม่ได้สอนวิชานี้';
  END IF;

  INSERT INTO teaching_logs (
    subject_id, date, teacher_id, periods,
    materials, content, motivation, results, problems,
    image_url, objectives, suggestions
  )
  VALUES (
    p_subject_id, p_date, v_teacher_id, p_periods,
    p_materials, p_content, p_motivation, p_results, p_problems,
    p_image_url, p_objectives, p_suggestions
  )
  ON CONFLICT (subject_id, date, teacher_id) DO UPDATE
    SET periods     = EXCLUDED.periods,
        materials   = EXCLUDED.materials,
        content     = EXCLUDED.content,
        motivation  = EXCLUDED.motivation,
        results     = EXCLUDED.results,
        problems    = EXCLUDED.problems,
        image_url   = EXCLUDED.image_url,
        objectives  = EXCLUDED.objectives,
        suggestions = EXCLUDED.suggestions,
        updated_at  = NOW()
  RETURNING id INTO v_id;

  INSERT INTO logs (user_id, action, metadata)
  VALUES (auth.uid(), 'SAVE_TEACHING_LOG',
    jsonb_build_object('subject_id', p_subject_id, 'date', p_date, 'log_id', v_id));

  RETURN jsonb_build_object('success', true, 'id', v_id, 'message', 'บันทึกสำเร็จ');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION save_teaching_log(TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
