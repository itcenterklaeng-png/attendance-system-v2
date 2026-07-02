-- ============================================
-- 28_teacher_self_update.sql
-- ให้ครูสามารถ update ข้อมูลของ ตัวเอง ได้ (profile.html)
-- ============================================

-- ครูปกติ (role=user) update ได้เฉพาะ row ของตัวเอง
DROP POLICY IF EXISTS tch_self_update ON teachers;

CREATE POLICY tch_self_update ON teachers
  FOR UPDATE
  USING (
    teacher_id IN (
      SELECT teacher_id FROM users
      WHERE id = auth.uid() AND status = 'active'
    )
  )
  WITH CHECK (
    teacher_id IN (
      SELECT teacher_id FROM users
      WHERE id = auth.uid() AND status = 'active'
    )
  );

-- Grant SELECT on users to authenticated (จำเป็นสำหรับ policy ตรวจ teacher_id)
-- (มีอยู่แล้วแต่ safe re-run)
GRANT SELECT ON users TO authenticated;
