-- ============================================
-- Attendance System v2 — Schema
-- Target: Supabase Postgres
-- ============================================

-- Extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- 1. teachers
-- ============================================
CREATE TABLE teachers (
  teacher_id  TEXT PRIMARY KEY,
  full_name   TEXT NOT NULL,
  email       TEXT,
  phone       TEXT,
  department  TEXT,                                     -- ⭐ แผนกของครู (ช่างกล, ช่างยนต์, ฯลฯ)
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_teachers_email ON teachers(email) WHERE email IS NOT NULL;
CREATE INDEX idx_teachers_department ON teachers(department) WHERE department IS NOT NULL;

-- ============================================
-- 2. classes
-- ============================================
CREATE TABLE classes (
  class_id    TEXT PRIMARY KEY,
  major       TEXT NOT NULL,
  level       TEXT NOT NULL CHECK (level IN (
                'ปวช.','ปวส.','ป.ตรี','ป.โท',
                'มัธยมศึกษา','มัธยมศึกษาตอนต้น','มัธยมศึกษาตอนปลาย',
                'ประถมศึกษา','อนุบาล','อื่นๆ'
              )),
  year        INT  NOT NULL CHECK (year BETWEEN 1 AND 3),
  room        INT  NOT NULL DEFAULT 1 CHECK (room >= 1),
  advisor_id  TEXT REFERENCES teachers(teacher_id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- ⭐ ป้องกัน duplicate ห้อง (สาเหตุของ bug ใน v1)
  UNIQUE (major, level, year, room)
);
CREATE INDEX idx_classes_advisor ON classes(advisor_id);

-- ============================================
-- 3. students
-- ============================================
CREATE TABLE students (
  student_id  TEXT PRIMARY KEY,
  full_name   TEXT NOT NULL,
  class_id    TEXT REFERENCES classes(class_id) ON DELETE SET NULL,
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_students_class ON students(class_id);
CREATE INDEX idx_students_status ON students(status) WHERE status = 'active';

-- ============================================
-- 4. subjects
-- ============================================
CREATE TABLE subjects (
  subject_id   TEXT PRIMARY KEY,
  subject_name TEXT NOT NULL,
  major        TEXT,
  course_type  TEXT NOT NULL DEFAULT 'normal' CHECK (course_type IN ('normal','upskill','short')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_subjects_major ON subjects(major);

-- ============================================
-- 5. subject_teachers (many-to-many)
-- ============================================
CREATE TABLE subject_teachers (
  subject_id  TEXT REFERENCES subjects(subject_id) ON DELETE CASCADE,
  teacher_id  TEXT REFERENCES teachers(teacher_id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (subject_id, teacher_id)
);
CREATE INDEX idx_subj_teachers_teacher ON subject_teachers(teacher_id);

-- ============================================
-- 6. subject_schedule (ตารางสอนของวิชา)
-- ============================================
CREATE TABLE subject_schedule (
  id          BIGSERIAL PRIMARY KEY,
  subject_id  TEXT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
  date        DATE NOT NULL,
  periods     TEXT NOT NULL,  -- "1,2,3,4"
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (subject_id, date)
);
CREATE INDEX idx_sched_subject ON subject_schedule(subject_id);
CREATE INDEX idx_sched_date ON subject_schedule(date);

-- ============================================
-- 7. enrollments
-- ============================================
CREATE TABLE enrollments (
  student_id  TEXT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
  subject_id  TEXT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
  class_id    TEXT REFERENCES classes(class_id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (student_id, subject_id)
);
CREATE INDEX idx_enroll_subject ON enrollments(subject_id);
CREATE INDEX idx_enroll_class ON enrollments(class_id);
CREATE INDEX idx_enroll_subj_cls ON enrollments(subject_id, class_id);

-- ============================================
-- 8. attendance (ตารางหลัก)
-- ============================================
CREATE TABLE attendance (
  id          BIGSERIAL PRIMARY KEY,
  date        DATE NOT NULL,
  subject_id  TEXT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
  student_id  TEXT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
  status      TEXT NOT NULL CHECK (status IN ('มา','ขาด','สาย','ลาป่วย','ลากิจ')),
  period      INT  NOT NULL,  -- 1-12 = รอบ 1 ตามคาบ, 99 = รอบ 2 (เช็คซ้ำ)
  checked_by  TEXT REFERENCES teachers(teacher_id) ON DELETE SET NULL,
  note        TEXT,
  late_at     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- ⭐ ป้องกัน duplicate ระดับ DB (สาเหตุของปัญหาใน v1)
  UNIQUE (subject_id, student_id, date, period)
);
CREATE INDEX idx_att_subj_date ON attendance(subject_id, date);
CREATE INDEX idx_att_student_date ON attendance(student_id, date);
CREATE INDEX idx_att_round1 ON attendance(subject_id, date) WHERE period != 99;
CREATE INDEX idx_att_round2 ON attendance(subject_id, date) WHERE period = 99;

-- ============================================
-- 9. users (link Supabase auth → role + teacher)
-- ============================================
CREATE TABLE users (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT UNIQUE NOT NULL,
  role        TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin','user')),
  teacher_id  TEXT REFERENCES teachers(teacher_id) ON DELETE SET NULL,
  full_name   TEXT,
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_teacher ON users(teacher_id);

-- ============================================
-- 10. logs (audit trail)
-- ============================================
CREATE TABLE logs (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
  action      TEXT NOT NULL,
  metadata    JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_logs_user ON logs(user_id, created_at DESC);
CREATE INDEX idx_logs_created ON logs(created_at DESC);

-- ============================================
-- 11. teaching_logs (บันทึกการสอนของครู)
-- ============================================
CREATE TABLE teaching_logs (
  id          BIGSERIAL PRIMARY KEY,
  subject_id  TEXT NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
  date        DATE NOT NULL,
  teacher_id  TEXT REFERENCES teachers(teacher_id) ON DELETE SET NULL,
  content     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_teach_subj_date ON teaching_logs(subject_id, date);

-- ============================================
-- Triggers — auto-update updated_at
-- ============================================
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER teachers_set_updated_at BEFORE UPDATE ON teachers
  FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER students_set_updated_at BEFORE UPDATE ON students
  FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER subjects_set_updated_at BEFORE UPDATE ON subjects
  FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
CREATE TRIGGER teaching_logs_set_updated_at BEFORE UPDATE ON teaching_logs
  FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- ============================================
-- Auto-create users row when auth.users created (Google OAuth)
-- ============================================
CREATE OR REPLACE FUNCTION trg_handle_new_auth_user() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, role, status)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'user',       -- default role → admin ต้องเปลี่ยนเอง
    'inactive'    -- ⭐ default inactive — admin ต้อง approve ก่อน
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION trg_handle_new_auth_user();
