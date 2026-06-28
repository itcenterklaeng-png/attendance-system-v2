-- ============================================
-- เพิ่ม username สำหรับ login ง่าย (เหมือน teacher_id)
-- ============================================

-- 1. เพิ่ม column username
ALTER TABLE users ADD COLUMN IF NOT EXISTS username TEXT;

-- 2. UNIQUE INDEX (case-insensitive) — ห้ามซ้ำ
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_unique
  ON users (LOWER(username)) WHERE username IS NOT NULL;

-- 3. RPC ใหม่ — ค้น email จาก input (teacher_id หรือ username)
DROP FUNCTION IF EXISTS lookup_email_for_login(TEXT);

CREATE OR REPLACE FUNCTION lookup_email_for_login(p_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $body$
DECLARE
  v_email TEXT;
  v_trim TEXT;
BEGIN
  v_trim := TRIM(p_input);
  IF v_trim IS NULL OR v_trim = '' THEN RETURN NULL; END IF;

  -- 1. ลอง username ใน users
  SELECT u.email INTO v_email
  FROM users u
  WHERE LOWER(u.username) = LOWER(v_trim)
    AND u.status = 'active'
  LIMIT 1;
  IF v_email IS NOT NULL THEN RETURN v_email; END IF;

  -- 2. ลอง teacher_id ใน teachers
  SELECT t.email INTO v_email
  FROM teachers t
  WHERE t.teacher_id = v_trim
    AND t.status = 'active'
    AND t.email IS NOT NULL
  LIMIT 1;
  RETURN v_email;
END;
$body$;

GRANT EXECUTE ON FUNCTION lookup_email_for_login(TEXT) TO anon, authenticated;

-- 4. Backward-compat: lookup_email_by_teacher_id ยังใช้ได้
-- (ไม่ลบ — เผื่อ frontend เก่าใช้อยู่)
