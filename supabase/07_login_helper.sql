-- ============================================
-- RPC: lookup email จาก teacherId
-- ใช้ตอน login เพื่อให้ครูพิมพ์ "t011" แทน "kroobank100@gmail.com" ได้
-- ============================================

CREATE OR REPLACE FUNCTION lookup_email_by_teacher_id(p_teacher_id TEXT)
RETURNS TEXT AS $$
  SELECT email
  FROM teachers
  WHERE teacher_id = p_teacher_id
    AND status = 'active'
    AND email IS NOT NULL
  LIMIT 1;
$$ LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public;

-- Grant ให้ anon (ยังไม่ login) + authenticated (login แล้ว) เรียกได้
GRANT EXECUTE ON FUNCTION lookup_email_by_teacher_id(TEXT) TO anon, authenticated;

-- ============================================
-- (option) revoke direct SELECT teachers จาก anon — เพื่อให้แน่ใจว่าไม่หลุด
-- ============================================
-- RLS ของ teachers อยู่แล้ว (ต้องเป็น active user) — anon block อัตโนมัติ
-- เราใช้ SECURITY DEFINER เพื่อ bypass RLS เฉพาะการ lookup เท่านั้น
