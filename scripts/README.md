# Migration Script — Sheets → Supabase

ย้ายข้อมูลจาก Google Sheets ของระบบเก่า ไป Supabase Postgres
และสร้าง Supabase Auth users สำหรับครูทุกคน (Phase 2 — แบบ A)

---

## ขั้นที่ 1 — Export CSV จาก Google Sheets

1. เปิด Google Sheets ของระบบเดิม
2. ทุกชีท (9 อัน) → **File → Download → Comma Separated Values (.csv)**
3. ตั้งชื่อให้ตรงนี้ (ลำดับสำคัญ — ทำตามนี้เลย):

| ชีทเดิม | ชื่อไฟล์ที่ใช้ |
|---|---|
| Teachers | `Teachers.csv` |
| Classes | `Classes.csv` |
| Students | `Students.csv` |
| Subjects | `Subjects.csv` |
| SubjectTeachers | `SubjectTeachers.csv` |
| SubjectSchedule | `SubjectSchedule.csv` |
| Enrollments | `Enrollments.csv` |
| Attendance | `Attendance.csv` |
| TeachingLogs | `TeachingLogs.csv` |

4. **วางทุกไฟล์ที่ `scripts/csv/`**

---

## ขั้นที่ 2 — ตั้งค่า .env

```bash
cd scripts
cp .env.example .env
```

แก้ `.env`:
- `SUPABASE_URL` = Project URL
- `SUPABASE_SERVICE_KEY` = **Secret key** (`sb_secret_...`) จาก Settings → API
- `INITIAL_PASSWORD` = รหัสเริ่มต้นที่จะให้ครูทุกคน (default = `123456789`)
- `ADMIN_EMAILS` = email ของ admin (คั่นด้วย comma ถ้ามีหลายคน)

⚠ ใช้ Secret key เพราะต้อง bypass RLS + เรียก Auth Admin API

---

## ขั้นที่ 3 — รัน SQL setup (ครั้งเดียว)

ใน Supabase Dashboard → SQL Editor → New query → รัน **ตามลำดับ**:

1. `supabase/01_schema.sql` (ถ้ายังไม่ได้รัน)
2. `supabase/02_rls.sql`
3. `supabase/03_functions.sql`
4. **`supabase/04_auth_setup.sql`** ← Phase 2 (แบบ A) ⭐ ใหม่!

ขั้น 4 จะเพิ่ม `must_change_password` ใน `users` + แก้ trigger ให้รองรับ migration

---

## ขั้นที่ 4 — Install + Dry-run

```bash
npm install
npm run migrate:dry        # parse CSV + validate ไม่เขียน DB
```

Dry-run จะ parse + validate — ตรวจให้ผ่านทุก table ก่อน

---

## ขั้นที่ 5 — Migrate (data + auth)

มี 3 ทางเลือก:

### 🟢 รันครั้งเดียวจบ (แนะนำ)
```bash
npm run migrate:full       # migrate data + สร้าง Auth users
```

### 🟡 รันทีละขั้น
```bash
npm run migrate            # migrate ข้อมูลอย่างเดียว
npm run migrate:auth       # สร้าง Auth users (หลังจาก migrate ข้อมูลเสร็จ)
```

### 🔵 ทดสอบ auth-only ก่อน
```bash
npm run migrate:auth-dry   # ดูว่าจะสร้างกี่คน (ไม่ทำจริง)
```

---

## ผลลัพธ์ของ Phase 2 (แบบ A)

หลังรัน `migrate:full` หรือ `migrate:auth` สำเร็จ:

- ✅ สร้าง user ใน `auth.users` สำหรับครูทุกคนที่มี email
- ✅ ทุกคนใช้รหัสเริ่มต้นเดียวกัน = ค่าใน `INITIAL_PASSWORD`
- ✅ `email_confirm = true` → ครู login ได้เลย ไม่ต้องยืนยัน email
- ✅ ผูก `teacher_id` ใน `public.users` → ครู login มาเห็นวิชาของตัวเอง
- ✅ ตั้ง flag `must_change_password = true` → Phase 3 จะใช้บังคับเปลี่ยนรหัส
- ✅ Email ที่อยู่ใน `ADMIN_EMAILS` จะตั้ง `role='admin'` อัตโนมัติ

---

## Verify หลัง migrate

ใน Supabase SQL Editor:

```sql
-- จำนวน rows ในแต่ละตาราง
SELECT 'teachers' AS t, COUNT(*) FROM teachers
UNION ALL SELECT 'classes', COUNT(*) FROM classes
UNION ALL SELECT 'students', COUNT(*) FROM students
UNION ALL SELECT 'subjects', COUNT(*) FROM subjects
UNION ALL SELECT 'subject_teachers', COUNT(*) FROM subject_teachers
UNION ALL SELECT 'subject_schedule', COUNT(*) FROM subject_schedule
UNION ALL SELECT 'enrollments', COUNT(*) FROM enrollments
UNION ALL SELECT 'attendance', COUNT(*) FROM attendance
UNION ALL SELECT 'teaching_logs', COUNT(*) FROM teaching_logs;

-- จำนวน Auth users ที่สร้างจาก migration
SELECT COUNT(*) FROM users WHERE must_change_password = true;

-- ดู admin ที่ถูกตั้ง
SELECT email, role, teacher_id, full_name, status, must_change_password
FROM users WHERE role = 'admin';
```

เทียบกับจำนวนแถวใน Sheets — ควรใกล้เคียง (อาจขาดแค่ row ที่ invalid)

---

## ถ้าผิด — Rollback

### Rollback ข้อมูล
```sql
TRUNCATE attendance, teaching_logs, logs,
         enrollments, subject_schedule, subject_teachers,
         subjects, students, classes, teachers RESTART IDENTITY CASCADE;
```

### Rollback Auth users (ระวัง!)
```sql
-- ลบ Auth users ที่สร้างจาก migration เท่านั้น (source=migration)
DELETE FROM auth.users
WHERE raw_user_meta_data->>'source' = 'migration';
-- public.users จะลบตามอัตโนมัติ (ON DELETE CASCADE)
```

แล้วรัน migrate ใหม่

---

## Phase 3 — UI Login + เปลี่ยนรหัสครั้งแรก (ถัดไป)

หลัง Phase 2 เสร็จ ต้องมีหน้า UI:

1. **หน้า Login** — email + password
2. **Middleware ตรวจ flag** — ถ้า `must_change_password = true` → เด้งไปหน้าเปลี่ยนรหัส
3. **หน้าเปลี่ยนรหัส** — ตั้งรหัสใหม่ + เรียก `clear_must_change_password()`
4. **หลังจากนั้น** — เข้าระบบปกติ

ดูแผนเต็มได้ที่ `../../MIGRATION_PLAN.md`
