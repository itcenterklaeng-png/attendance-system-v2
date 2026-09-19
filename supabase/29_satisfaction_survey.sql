-- =============================================
-- Migration 29: Satisfaction Survey (แบบสอบถามความพึงพอใจ)
-- =============================================
-- 2 tables:
--   surveys           — แบบสอบถาม (มี 1 active ในระบบ ณ ขณะหนึ่ง)
--   survey_responses  — คำตอบของผู้ใช้ (1 user = 1 response ต่อ survey)
--
-- RLS:
--   - ทุก authenticated user อ่าน surveys (active) ได้
--   - ทุก authenticated user insert response ของตัวเองได้ (1 ครั้ง)
--   - ทุก authenticated user อ่าน response ของตัวเองได้
--   - admin / executive อ่าน responses ทั้งหมดได้ (สำหรับสรุปผล)

-- ========== TABLES ==========
CREATE TABLE IF NOT EXISTS surveys (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title         text NOT NULL,
  description   text,
  active        boolean NOT NULL DEFAULT true,
  is_mandatory  boolean NOT NULL DEFAULT true,  -- บังคับตอบก่อนใช้งานระบบ
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS survey_responses (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id     uuid NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- ข้อมูลทั่วไป (Section 1)
  gender        text,        -- 'ชาย' | 'หญิง' | 'ไม่ระบุ'
  age_range     text,        -- 'under30' | '30-40' | '41-50' | '51-60' | 'over60'
  role          text,        -- 'teacher' | 'staff' | 'executive' | 'admin'
  experience    text,        -- 'lt1m' | '1-3m' | '4-6m' | 'gt6m'
  device        text,        -- 'mobile' | 'tablet' | 'desktop' | 'laptop'
  -- คะแนน 24 ข้อ (Section 2) — 1..5
  q1  smallint, q2  smallint, q3  smallint, q4  smallint, q5  smallint,
  q6  smallint, q7  smallint, q8  smallint, q9  smallint,
  q10 smallint, q11 smallint, q12 smallint, q13 smallint, q14 smallint,
  q15 smallint, q16 smallint,
  q17 smallint, q18 smallint, q19 smallint,
  q20 smallint, q21 smallint, q22 smallint, q23 smallint, q24 smallint,
  -- ปลายเปิด (Section 3)
  like_most     text,
  improve       text,
  add_feature   text,
  problems      text,
  suggestions   text,
  -- meta
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (survey_id, user_id)   -- 1 คน 1 ครั้ง
);

CREATE INDEX IF NOT EXISTS idx_survey_responses_survey ON survey_responses(survey_id);
CREATE INDEX IF NOT EXISTS idx_survey_responses_user   ON survey_responses(user_id);

-- ========== RLS ==========
ALTER TABLE surveys          ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_responses ENABLE ROW LEVEL SECURITY;

-- surveys: ทุก authenticated user select ได้ (แค่รอบ active)
DROP POLICY IF EXISTS surveys_select_all ON surveys;
CREATE POLICY surveys_select_all ON surveys
  FOR SELECT USING (auth.role() = 'authenticated');

-- surveys: admin เท่านั้นที่ manage (insert/update/delete)
DROP POLICY IF EXISTS surveys_admin_write ON surveys;
CREATE POLICY surveys_admin_write ON surveys
  FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- survey_responses: user select ของตัวเอง + admin/executive select ทั้งหมด
DROP POLICY IF EXISTS sr_select_own_or_admin ON survey_responses;
CREATE POLICY sr_select_own_or_admin ON survey_responses
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin','executive'))
  );

-- survey_responses: user insert ของตัวเอง (1 ครั้ง — บังคับ by UNIQUE)
DROP POLICY IF EXISTS sr_insert_own ON survey_responses;
CREATE POLICY sr_insert_own ON survey_responses
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- (no update / delete for regular user — admin ใช้ policy admin_write)
DROP POLICY IF EXISTS sr_admin_all ON survey_responses;
CREATE POLICY sr_admin_all ON survey_responses
  FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- ========== SEED: create first survey ==========
INSERT INTO surveys (title, description, active, is_mandatory)
SELECT
  'แบบสอบถามความพึงพอใจ ระบบเช็คชื่อออนไลน์ วิทยาลัยการอาชีพแกลง',
  'รอบปีการศึกษา 2569 · โปรดตอบตามความเป็นจริง',
  true,
  true
WHERE NOT EXISTS (SELECT 1 FROM surveys WHERE active = true);

-- ========== RPC: has_responded ==========
CREATE OR REPLACE FUNCTION public.has_responded_active_survey()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_survey_id uuid;
BEGIN
  SELECT id INTO v_survey_id
  FROM surveys WHERE active = true AND is_mandatory = true
  ORDER BY created_at DESC LIMIT 1;

  IF v_survey_id IS NULL THEN
    RETURN true;  -- ไม่มีรอบบังคับ → ถือว่าผ่าน
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM survey_responses
    WHERE survey_id = v_survey_id AND user_id = auth.uid()
  );
END $$;

GRANT EXECUTE ON FUNCTION public.has_responded_active_survey() TO authenticated;

-- ========== RPC: get_survey_stats (admin/executive) ==========
CREATE OR REPLACE FUNCTION public.get_survey_stats(p_survey_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sid uuid;
  v_result jsonb;
BEGIN
  -- guard: admin/executive only
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin','executive')) THEN
    RAISE EXCEPTION 'permission denied';
  END IF;

  v_sid := COALESCE(p_survey_id,
    (SELECT id FROM surveys WHERE active = true ORDER BY created_at DESC LIMIT 1));

  IF v_sid IS NULL THEN
    RETURN jsonb_build_object('total', 0);
  END IF;

  SELECT jsonb_build_object(
    'survey_id',  v_sid,
    'total',      COUNT(*),
    'by_role',    jsonb_build_object(
                    'teacher',   COUNT(*) FILTER (WHERE role = 'teacher'),
                    'staff',     COUNT(*) FILTER (WHERE role = 'staff'),
                    'executive', COUNT(*) FILTER (WHERE role = 'executive'),
                    'admin',     COUNT(*) FILTER (WHERE role = 'admin')
                  ),
    'avg', jsonb_build_object(
      'q1',  AVG(q1)::numeric(4,2),  'q2',  AVG(q2)::numeric(4,2),
      'q3',  AVG(q3)::numeric(4,2),  'q4',  AVG(q4)::numeric(4,2),
      'q5',  AVG(q5)::numeric(4,2),  'q6',  AVG(q6)::numeric(4,2),
      'q7',  AVG(q7)::numeric(4,2),  'q8',  AVG(q8)::numeric(4,2),
      'q9',  AVG(q9)::numeric(4,2),  'q10', AVG(q10)::numeric(4,2),
      'q11', AVG(q11)::numeric(4,2), 'q12', AVG(q12)::numeric(4,2),
      'q13', AVG(q13)::numeric(4,2), 'q14', AVG(q14)::numeric(4,2),
      'q15', AVG(q15)::numeric(4,2), 'q16', AVG(q16)::numeric(4,2),
      'q17', AVG(q17)::numeric(4,2), 'q18', AVG(q18)::numeric(4,2),
      'q19', AVG(q19)::numeric(4,2), 'q20', AVG(q20)::numeric(4,2),
      'q21', AVG(q21)::numeric(4,2), 'q22', AVG(q22)::numeric(4,2),
      'q23', AVG(q23)::numeric(4,2), 'q24', AVG(q24)::numeric(4,2)
    ),
    'grand_avg', (
      (COALESCE(AVG(q1),0)+COALESCE(AVG(q2),0)+COALESCE(AVG(q3),0)+COALESCE(AVG(q4),0)+COALESCE(AVG(q5),0)
      +COALESCE(AVG(q6),0)+COALESCE(AVG(q7),0)+COALESCE(AVG(q8),0)+COALESCE(AVG(q9),0)+COALESCE(AVG(q10),0)
      +COALESCE(AVG(q11),0)+COALESCE(AVG(q12),0)+COALESCE(AVG(q13),0)+COALESCE(AVG(q14),0)+COALESCE(AVG(q15),0)
      +COALESCE(AVG(q16),0)+COALESCE(AVG(q17),0)+COALESCE(AVG(q18),0)+COALESCE(AVG(q19),0)+COALESCE(AVG(q20),0)
      +COALESCE(AVG(q21),0)+COALESCE(AVG(q22),0)+COALESCE(AVG(q23),0)+COALESCE(AVG(q24),0)) / 24.0
    )::numeric(4,2)
  ) INTO v_result
  FROM survey_responses WHERE survey_id = v_sid;

  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.get_survey_stats(uuid) TO authenticated;
