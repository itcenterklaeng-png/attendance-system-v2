-- ============================================
-- ขยาย schema ของ classes ให้รับ level อื่นๆ
-- (เดิมรับแค่ ปวช./ปวส. → เปลี่ยนเป็น whitelist กว้างขึ้น)
-- ============================================

-- 1. drop CHECK constraint เดิม
ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_level_check;

-- 2. เพิ่ม CHECK constraint ใหม่ที่รับ level ทุกแบบในระบบการศึกษาไทย
ALTER TABLE classes
  ADD CONSTRAINT classes_level_check CHECK (
    level IN (
      'ปวช.',
      'ปวส.',
      'ป.ตรี',
      'ป.โท',
      'มัธยมศึกษา',
      'มัธยมศึกษาตอนต้น',
      'มัธยมศึกษาตอนปลาย',
      'ประถมศึกษา',
      'อนุบาล',
      'อื่นๆ'
    )
  );

-- 3. (option) ถ้าอยาก disable check ไปเลย (อนาคต) → uncomment บรรทัดล่าง
-- ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_level_check;
