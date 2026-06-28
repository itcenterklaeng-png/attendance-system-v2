-- ============================================
-- Phase 5 — Teaching Log Functions
-- ============================================

-- ============================================
-- 1) save_teaching_log
--   UPSERT teaching_log (1 ต่อ subject+date+teacher)
-- ============================================
CREATE OR REPLACE FUNCTION save_teaching_log(
  p_subject_id  TEXT,
  p_date        DATE,
  p_periods     TEXT,
  p_objectives  TEXT,
  p_content     TEXT,
  p_results     TEXT,
  p_problems    TEXT,
  p_suggestions TEXT
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

  INSERT INTO teaching_logs (subject_id, date, teacher_id, periods, objectives, content, results, problems, suggestions)
  VALUES (p_subject_id, p_date, v_teacher_id, p_periods, p_objectives, p_content, p_results, p_problems, p_suggestions)
  ON CONFLICT (subject_id, date, teacher_id) DO UPDATE
    SET periods     = EXCLUDED.periods,
        objectives  = EXCLUDED.objectives,
        content     = EXCLUDED.content,
        results     = EXCLUDED.results,
        problems    = EXCLUDED.problems,
        suggestions = EXCLUDED.suggestions,
        updated_at  = NOW()
  RETURNING id INTO v_id;

  -- log
  INSERT INTO logs (user_id, action, metadata)
  VALUES (auth.uid(), 'SAVE_TEACHING_LOG',
    jsonb_build_object('subject_id', p_subject_id, 'date', p_date, 'log_id', v_id));

  RETURN jsonb_build_object('success', true, 'id', v_id, 'message', 'บันทึกสำเร็จ');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION save_teaching_log(TEXT, DATE, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================
-- 2) delete_teaching_log
-- ============================================
CREATE OR REPLACE FUNCTION delete_teaching_log(p_id BIGINT)
RETURNS JSONB AS $$
DECLARE
  v_owner TEXT;
  v_is_admin BOOLEAN;
BEGIN
  v_is_admin := app_current_role() = 'admin';
  SELECT teacher_id INTO v_owner FROM teaching_logs WHERE id = p_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'ไม่พบบันทึก';
  END IF;
  IF NOT v_is_admin AND v_owner != current_teacher_id() THEN
    RAISE EXCEPTION 'ลบได้แค่บันทึกของตัวเอง';
  END IF;

  DELETE FROM teaching_logs WHERE id = p_id;

  INSERT INTO logs (user_id, action, metadata)
  VALUES (auth.uid(), 'DELETE_TEACHING_LOG', jsonb_build_object('log_id', p_id));

  RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION delete_teaching_log(BIGINT) TO authenticated;
