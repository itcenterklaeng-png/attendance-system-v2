-- ============================================
-- Auth Setup — Phase 2 (แบบ A)
-- เพิ่ม column สำหรับการบังคับเปลี่ยนรหัสครั้งแรก
-- รัน SQL นี้ใน Supabase SQL Editor ก่อนรัน migrate.js
-- ============================================

-- 1. เพิ่ม column must_change_password
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT true;

-- 2. แก้ trigger ให้ตั้ง must_change_password=true สำหรับ user ที่สร้างใหม่
CREATE OR REPLACE FUNCTION trg_handle_new_auth_user() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, role, status, must_change_password)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user'),
    -- ⭐ ถ้ามาจาก migrate.js (มี source=migration) → active เลย
    --    ถ้ามาจาก Google OAuth → inactive รอ admin approve
    CASE
      WHEN NEW.raw_user_meta_data->>'source' = 'migration' THEN 'active'
      ELSE 'inactive'
    END,
    -- ⭐ ถ้ามาจาก migration → ต้องเปลี่ยนรหัส
    --    ถ้ามาจาก Google OAuth → ไม่ต้อง (ใช้ Google login)
    COALESCE((NEW.raw_user_meta_data->>'must_change_password')::BOOLEAN, true)
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. RLS: ให้ user อ่าน flag must_change_password ของตัวเองได้ + update เมื่อเปลี่ยนรหัสเสร็จ
DROP POLICY IF EXISTS user_read_own_flag ON users;
CREATE POLICY user_read_own_flag ON users
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS user_clear_own_flag ON users;
CREATE POLICY user_clear_own_flag ON users
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND (must_change_password = false)  -- clear ได้อย่างเดียว
  );

-- 4. Helper function — เรียกหลังเปลี่ยนรหัสเสร็จ
CREATE OR REPLACE FUNCTION clear_must_change_password() RETURNS VOID AS $$
BEGIN
  UPDATE users SET must_change_password = false WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Backfill: ถ้ามี users เก่าอยู่แล้ว ตั้งให้ต้องเปลี่ยนรหัส (ถ้ายังไม่ได้ตั้งค่า)
UPDATE users SET must_change_password = true WHERE must_change_password IS NULL;
