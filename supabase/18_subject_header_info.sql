-- ============================================
-- get_subject_header_info — ข้อมูลครู + ห้องสำหรับ modal header
-- ============================================

DROP FUNCTION IF EXISTS get_subject_header_info(TEXT);

CREATE OR REPLACE FUNCTION get_subject_header_info(p_subject_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $body$
DECLARE
  v_teacher_names TEXT;
  v_teacher_phones TEXT;
  v_majors TEXT;
  v_levels TEXT;
  v_years TEXT;
  v_rooms TEXT;
  v_total_classes INT;
BEGIN
  -- ครูผู้สอน
  SELECT
    string_agg(t.full_name, ', ' ORDER BY t.full_name),
    string_agg(COALESCE(t.phone, ''), ', ' ORDER BY t.full_name)
  INTO v_teacher_names, v_teacher_phones
  FROM subject_teachers st
  JOIN teachers t ON t.teacher_id = st.teacher_id
  WHERE st.subject_id = p_subject_id;

  -- ห้องเรียน (aggregate)
  SELECT
    string_agg(DISTINCT c.major, ' / '),
    string_agg(DISTINCT c.level, ' / '),
    string_agg(DISTINCT c.year::TEXT, ', '),
    string_agg(DISTINCT c.room::TEXT, ', '),
    COUNT(DISTINCT c.class_id)::INT
  INTO v_majors, v_levels, v_years, v_rooms, v_total_classes
  FROM enrollments e
  LEFT JOIN classes c ON c.class_id = e.class_id
  WHERE e.subject_id = p_subject_id
    AND c.class_id IS NOT NULL;

  RETURN jsonb_build_object(
    'teacher_names',  COALESCE(v_teacher_names, '-'),
    'teacher_phones', COALESCE(NULLIF(REGEXP_REPLACE(COALESCE(v_teacher_phones, ''), '^,+|,+$', '', 'g'), ''), '-'),
    'majors',         COALESCE(v_majors, '-'),
    'levels',         COALESCE(v_levels, '-'),
    'years',          COALESCE(v_years, '-'),
    'rooms',          COALESCE(v_rooms, '-'),
    'total_classes',  COALESCE(v_total_classes, 0)
  );
END
$body$;

GRANT EXECUTE ON FUNCTION get_subject_header_info(TEXT) TO authenticated;
