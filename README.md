# Attendance System v2 — Vercel + Supabase

ระบบเช็คชื่อ rebuild จาก Apps Script + Sheets → Vercel + Supabase

## โครงสร้างโฟลเดอร์

```
attendance-system-v2/
├── supabase/
│   ├── 01_schema.sql      # 11 ตาราง + indexes + triggers
│   ├── 02_rls.sql         # Row Level Security policies
│   └── 03_functions.sql   # Stored procedures (save attendance, bulk enroll, ...)
├── api/                   # (Phase 3) Vercel Functions
├── public/                # (Phase 4) static frontend
├── scripts/
│   └── migrate.js         # (Phase 2) ย้ายข้อมูลจาก Sheets
└── README.md
```

## วิธีติดตั้ง Phase 1 (Schema)

### 1. สร้าง Supabase project
1. ไป https://supabase.com → New Project
2. Region: **Southeast Asia (Singapore)** ใกล้ที่สุด
3. Database password: เก็บไว้ดี ๆ
4. รอ ~2 นาที จนสีเขียว

### 2. รัน SQL ตามลำดับ
1. Supabase Dashboard → **SQL Editor** → New query
2. Copy เนื้อหา `01_schema.sql` → paste → **Run**
3. Copy เนื้อหา `02_rls.sql` → paste → **Run**
4. Copy เนื้อหา `03_functions.sql` → paste → **Run**

### 3. สร้าง admin คนแรก (ทำหลัง Google OAuth login)
หลังจาก login Google ครั้งแรก จะมี row ใน `users` (status='inactive')
รัน:
```sql
UPDATE users
SET role = 'admin', status = 'active', full_name = 'ชื่อจริง'
WHERE email = 'kroobank100@gmail.com';
```

## ความเปลี่ยนแปลงสำคัญจาก v1

| v1 (Apps Script) | v2 (Supabase) |
|---|---|
| LockService.waitLock() | Postgres transaction (auto) |
| clearContent + setValues (เสี่ยง) | INSERT/DELETE atomic |
| Cache 60 วิ | Realtime subscription |
| Auth custom (Auth.gs) | Supabase Auth (Google OAuth) |
| Duplicate classes ได้ | UNIQUE constraint (major,level,year,room) |
| Duplicate attendance ได้ | UNIQUE constraint (subject,student,date,period) |
| Race condition | กำจัดที่ DB level |

## Phase ถัดไป

- [x] Phase 1: Schema + RLS
- [ ] Phase 2: Migration script (Sheets → Postgres)
- [ ] Phase 3: API routes
- [ ] Phase 4: Frontend adapter
- [ ] Phase 5: Google OAuth setup
- [ ] Phase 6: Realtime integration
- [ ] Phase 7: Cron jobs
- [ ] Phase 8: Cutover

ดูแผนละเอียดที่ `../MIGRATION_PLAN.md`
