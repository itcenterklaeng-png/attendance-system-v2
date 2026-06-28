-- ============================================
-- Row Level Security (RLS) Policies
-- ============================================

-- เปิด RLS ทุกตาราง
ALTER TABLE users             ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers          ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE students          ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects          ENABLE ROW LEVEL SECURITY;
ALTER TABLE subject_teachers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE subject_schedule  ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance        ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE teaching_logs     ENABLE ROW LEVEL SECURITY;

-- ============================================
-- Helper functions
-- ============================================

-- คืนค่า role ของ user ปัจจุบัน
CREATE OR REPLACE FUNCTION app_current_role() RETURNS TEXT AS $$
  SELECT role FROM users WHERE id = auth.uid() AND status = 'active'
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- คืน teacher_id ที่ผูกกับ user ปัจจุบัน
CREATE OR REPLACE FUNCTION current_teacher_id() RETURNS TEXT AS $$
  SELECT teacher_id FROM users WHERE id = auth.uid() AND status = 'active'
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- ตรวจว่าครู (current user) สอนวิชานี้ไหม
CREATE OR REPLACE FUNCTION is_teacher_of_subject(p_subject_id TEXT) RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM subject_teachers st
    WHERE st.subject_id = p_subject_id
      AND st.teacher_id = current_teacher_id()
  )
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- ============================================
-- users
--   user เห็นแค่ตัวเอง / admin เห็นทุกคน
-- ============================================
CREATE POLICY users_self_read ON users
  FOR SELECT USING (id = auth.uid() OR app_current_role() = 'admin');
CREATE POLICY users_admin_write ON users
  FOR ALL USING (app_current_role() = 'admin');

-- ============================================
-- teachers / classes / students / subjects
--   อ่านได้ทุกคน (active users) / เขียนเฉพาะ admin
-- ============================================
CREATE POLICY tch_read ON teachers
  FOR SELECT USING (app_current_role() IN ('admin','user'));
CREATE POLICY tch_admin_write ON teachers
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY cls_read ON classes
  FOR SELECT USING (app_current_role() IN ('admin','user'));
CREATE POLICY cls_admin_write ON classes
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY stu_read ON students
  FOR SELECT USING (app_current_role() IN ('admin','user'));
CREATE POLICY stu_admin_write ON students
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY subj_read ON subjects
  FOR SELECT USING (app_current_role() IN ('admin','user'));
CREATE POLICY subj_admin_write ON subjects
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY st_read ON subject_teachers
  FOR SELECT USING (app_current_role() IN ('admin','user'));
CREATE POLICY st_admin_write ON subject_teachers
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY sched_read ON subject_schedule
  FOR SELECT USING (app_current_role() IN ('admin','user'));
CREATE POLICY sched_admin_write ON subject_schedule
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY enr_read ON enrollments
  FOR SELECT USING (app_current_role() IN ('admin','user'));
CREATE POLICY enr_admin_write ON enrollments
  FOR ALL USING (app_current_role() = 'admin');

-- ============================================
-- attendance
--   admin: ทุกอย่าง
--   ครู: อ่าน/เขียน เฉพาะวิชาตัวเอง
-- ============================================
CREATE POLICY att_admin_all ON attendance
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY att_teacher_select ON attendance
  FOR SELECT USING (
    app_current_role() = 'user' AND is_teacher_of_subject(subject_id)
  );
CREATE POLICY att_teacher_insert ON attendance
  FOR INSERT WITH CHECK (
    app_current_role() = 'user' AND is_teacher_of_subject(subject_id)
  );
CREATE POLICY att_teacher_update ON attendance
  FOR UPDATE USING (
    app_current_role() = 'user' AND is_teacher_of_subject(subject_id)
  );
CREATE POLICY att_teacher_delete ON attendance
  FOR DELETE USING (
    app_current_role() = 'user' AND is_teacher_of_subject(subject_id)
  );

-- ============================================
-- logs
--   ครู: อ่านได้เฉพาะของตัวเอง / admin: ทุกอย่าง
-- ============================================
CREATE POLICY logs_self_read ON logs
  FOR SELECT USING (user_id = auth.uid() OR app_current_role() = 'admin');
CREATE POLICY logs_insert ON logs
  FOR INSERT WITH CHECK (app_current_role() IN ('admin','user'));
CREATE POLICY logs_admin_modify ON logs
  FOR ALL USING (app_current_role() = 'admin');

-- ============================================
-- teaching_logs
--   ครู: เขียนเฉพาะวิชาตัวเอง / admin: ทุกอย่าง
-- ============================================
CREATE POLICY teach_log_admin ON teaching_logs
  FOR ALL USING (app_current_role() = 'admin');

CREATE POLICY teach_log_teacher_select ON teaching_logs
  FOR SELECT USING (
    app_current_role() = 'user' AND is_teacher_of_subject(subject_id)
  );
CREATE POLICY teach_log_teacher_write ON teaching_logs
  FOR INSERT WITH CHECK (
    app_current_role() = 'user' AND is_teacher_of_subject(subject_id)
  );
CREATE POLICY teach_log_teacher_update ON teaching_logs
  FOR UPDATE USING (
    app_current_role() = 'user' AND is_teacher_of_subject(subject_id)
  );
