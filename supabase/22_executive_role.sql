-- ============================================
-- เพิ่ม role 'executive' (ผู้บริหาร) — ดูได้ทุกอย่าง แต่แก้ไม่ได้
-- ============================================

-- 1. ขยาย CHECK constraint
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('admin','user','executive'));

-- ============================================
-- 2. RLS — ให้ executive อ่านได้ทุกตาราง
-- ============================================

-- users: ตัวเอง + admin/executive อ่านได้ทุกคน
DROP POLICY IF EXISTS users_self_read ON users;
CREATE POLICY users_self_read ON users
  FOR SELECT USING (
    id = auth.uid()
    OR app_current_role() IN ('admin', 'executive')
  );

-- teachers/classes/students/subjects/subject_teachers/subject_schedule/enrollments
DROP POLICY IF EXISTS tch_read ON teachers;
CREATE POLICY tch_read ON teachers
  FOR SELECT USING (app_current_role() IN ('admin','user','executive'));

DROP POLICY IF EXISTS cls_read ON classes;
CREATE POLICY cls_read ON classes
  FOR SELECT USING (app_current_role() IN ('admin','user','executive'));

DROP POLICY IF EXISTS stu_read ON students;
CREATE POLICY stu_read ON students
  FOR SELECT USING (app_current_role() IN ('admin','user','executive'));

DROP POLICY IF EXISTS subj_read ON subjects;
CREATE POLICY subj_read ON subjects
  FOR SELECT USING (app_current_role() IN ('admin','user','executive'));

DROP POLICY IF EXISTS st_read ON subject_teachers;
CREATE POLICY st_read ON subject_teachers
  FOR SELECT USING (app_current_role() IN ('admin','user','executive'));

DROP POLICY IF EXISTS sched_read ON subject_schedule;
CREATE POLICY sched_read ON subject_schedule
  FOR SELECT USING (app_current_role() IN ('admin','user','executive'));

DROP POLICY IF EXISTS enr_read ON enrollments;
CREATE POLICY enr_read ON enrollments
  FOR SELECT USING (app_current_role() IN ('admin','user','executive'));

-- attendance: executive อ่านได้ทั้งหมด
DROP POLICY IF EXISTS att_executive_read ON attendance;
CREATE POLICY att_executive_read ON attendance
  FOR SELECT USING (app_current_role() = 'executive');

-- teaching_logs: executive อ่านได้ทั้งหมด
DROP POLICY IF EXISTS teach_log_executive_read ON teaching_logs;
CREATE POLICY teach_log_executive_read ON teaching_logs
  FOR SELECT USING (app_current_role() = 'executive');

-- logs: executive อ่านได้
DROP POLICY IF EXISTS logs_executive_read ON logs;
CREATE POLICY logs_executive_read ON logs
  FOR SELECT USING (app_current_role() = 'executive');
