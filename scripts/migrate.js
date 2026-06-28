/**
 * Migration script: Google Sheets CSV → Supabase Postgres
 *
 * Usage:
 *   1. Export each sheet จาก Google Sheets เป็น CSV (ดู README.md)
 *   2. วาง CSV ใน scripts/csv/ ตามชื่อที่ระบุ
 *   3. cp .env.example .env แล้วใส่ Supabase keys
 *   4. npm install
 *   5. รัน SQL: supabase/04_auth_setup.sql (Phase 2 แบบ A)
 *   6. npm run migrate:dry   # ลอง parse ดูก่อน (ไม่เขียน DB)
 *   7. npm run migrate       # รันจริง (data)
 *   8. npm run migrate:auth  # สร้าง Supabase Auth users + ตั้งรหัสเริ่มต้น
 *
 * Flags:
 *   --dry-run      → parse + validate, ไม่เขียน DB
 *   --create-auth  → สร้าง Auth users หลังจาก migrate ข้อมูลเสร็จ
 *   --auth-only    → ข้าม migrate ข้อมูล, ทำแค่สร้าง Auth users
 *   --skip-data    → alias ของ --auth-only
 */

import { createClient } from '@supabase/supabase-js';
import { parse } from 'csv-parse/sync';
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import 'dotenv/config';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CSV_DIR = join(__dirname, 'csv');
const DRY_RUN = process.argv.includes('--dry-run');
const CREATE_AUTH = process.argv.includes('--create-auth') || process.argv.includes('--auth-only');
const AUTH_ONLY = process.argv.includes('--auth-only') || process.argv.includes('--skip-data');
const BATCH_SIZE = 500;

// ⭐ Phase 2 (แบบ A) — รหัสเริ่มต้นเดียวกันทุกคน, บังคับเปลี่ยนรหัสครั้งแรก
const INITIAL_PASSWORD = process.env.INITIAL_PASSWORD || '123456789';
// ⭐ admin emails (จะตั้ง role='admin' ตอนสร้าง user)
const ADMIN_EMAILS = (process.env.ADMIN_EMAILS || 'kroobank100@gmail.com')
  .split(',').map(s => s.trim().toLowerCase()).filter(Boolean);

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_SERVICE_KEY in .env');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false }
});

// ============================================
// Helpers
// ============================================
function readCsv(filename) {
  const path = join(CSV_DIR, filename);
  if (!existsSync(path)) {
    console.log(`  ⏭  ${filename} ไม่พบ — ข้าม`);
    return null;
  }
  const content = readFileSync(path, 'utf-8');
  return parse(content, { columns: true, skip_empty_lines: true, trim: true });
}

function toDate(v) {
  if (!v) return null;
  const s = String(v).trim();
  if (!s) return null;
  // รองรับหลาย format: 2026-05-25, 5/25/2026, 25/5/2026, ISO
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  const d = new Date(s);
  if (isNaN(d.getTime())) return null;
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function toInt(v, def = null) {
  if (v === '' || v == null) return def;
  const n = parseInt(v, 10);
  return isNaN(n) ? def : n;
}

function nonEmpty(v) {
  const s = String(v == null ? '' : v).trim();
  return s || null;
}

// ============================================
// Parent ID cache + orphan filter
// ============================================
const parentIds = {
  teachers: new Set(),
  classes:  new Set(),
  students: new Set(),
  subjects: new Set()
};

// ตารางลูก → list ของ FK ที่ต้องตรวจ (col ใน row → parent table)
const FK_CHECKS = {
  subject_teachers: [
    { col: 'subject_id', parent: 'subjects' },
    { col: 'teacher_id', parent: 'teachers' }
  ],
  subject_schedule: [
    { col: 'subject_id', parent: 'subjects' }
  ],
  enrollments: [
    { col: 'student_id', parent: 'students' },
    { col: 'subject_id', parent: 'subjects' }
    // class_id เป็น optional (ON DELETE SET NULL) → ไม่ต้องตรวจ
  ],
  attendance: [
    { col: 'subject_id', parent: 'subjects' },
    { col: 'student_id', parent: 'students' }
    // checked_by เป็น optional → ตรวจแยก (null ได้)
  ],
  teaching_logs: [
    { col: 'subject_id', parent: 'subjects' }
    // teacher_id เป็น optional → ไม่ตรวจ
  ]
};

async function loadParentCache(table, idCol) {
  const PAGE = 1000;
  let from = 0;
  parentIds[table].clear();
  while (true) {
    const { data, error } = await supabase
      .from(table).select(idCol)
      .range(from, from + PAGE - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    data.forEach(r => parentIds[table].add(r[idCol]));
    if (data.length < PAGE) break;
    from += PAGE;
  }
}

function filterOrphans(table, rows) {
  const checks = FK_CHECKS[table];
  if (!checks) return { kept: rows, orphans: 0, byCol: {} };
  let orphans = 0;
  const byCol = {};
  const kept = [];
  for (const row of rows) {
    let bad = null;
    for (const { col, parent } of checks) {
      const val = row[col];
      if (!val || !parentIds[parent].has(val)) { bad = col; break; }
    }
    if (bad) {
      orphans++;
      byCol[bad] = (byCol[bad] || 0) + 1;

      // Special handling — ถ้า attendance อ้าง checked_by ที่ไม่มี ให้ตั้งเป็น null แทน drop
      // (ไม่ทำที่นี่ — ทำใน transformer แทน)
    } else {
      // ถ้ามี checked_by อ้างถึง teacher ที่ไม่มี → ตั้งเป็น null (ป้องกัน FK fail บน optional col)
      if (table === 'attendance' && row.checked_by && !parentIds.teachers.has(row.checked_by)) {
        row.checked_by = null;
      }
      kept.push(row);
    }
  }
  return { kept, orphans, byCol };
}

// Dedupe rows by conflict key (เก็บค่าหลังสุดของ key เดียวกัน)
function dedupeByKey(rows, conflictKey) {
  if (!conflictKey || !rows || rows.length === 0) return { deduped: rows || [], dupCount: 0 };
  const keys = conflictKey.split(',').map(k => k.trim());
  const map = new Map();
  let dupCount = 0;
  for (const row of rows) {
    const key = keys.map(k => String(row[k] ?? '')).join('|');
    if (map.has(key)) dupCount++;
    map.set(key, row);   // ใช้ค่าหลังสุด (override)
  }
  return { deduped: Array.from(map.values()), dupCount };
}

async function upsertBatch(table, rows, conflictKey) {
  if (!rows || rows.length === 0) return 0;

  // ⭐ Dedupe ก่อน upsert (ป้องกัน Postgres error 21000)
  const { deduped, dupCount } = dedupeByKey(rows, conflictKey);
  if (dupCount > 0) {
    console.log(`     ⚠  พบ duplicate ${dupCount} rows — เก็บค่าหลังสุด (เหลือ ${deduped.length} unique)`);
  }
  rows = deduped;

  let inserted = 0;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    if (DRY_RUN) {
      console.log(`     [dry-run] ${table} batch ${i / BATCH_SIZE + 1}: ${batch.length} rows`);
      inserted += batch.length;
      continue;
    }
    const opts = conflictKey ? { onConflict: conflictKey } : {};
    const { error, count } = await supabase.from(table).upsert(batch, opts);
    if (error) {
      console.error(`     ❌ ${table} batch error:`, error.message);
      console.error(`     first row:`, JSON.stringify(batch[0]));
      throw error;
    }
    inserted += batch.length;
    process.stdout.write(`     ✓ ${inserted}/${rows.length}\r`);
  }
  console.log(`     ✅ ${table}: ${inserted} rows`);
  return inserted;
}

// ============================================
// Transformers — Sheets row → Postgres row
// ============================================
const T = {
  teachers: (r) => ({
    teacher_id: nonEmpty(r.teacherId),
    full_name:  nonEmpty(r.fullName) || nonEmpty(r.teacherName) || '(ไม่มีชื่อ)',
    email:      nonEmpty(r.email),
    phone:      nonEmpty(r.phone),
    department: nonEmpty(r.department),
    status:     (nonEmpty(r.status) || 'active').toLowerCase()
  }),
  classes: (r) => ({
    class_id:   nonEmpty(r.classId),
    major:      nonEmpty(r.major) || '(ไม่ระบุ)',
    level:      nonEmpty(r.level) || 'ปวช.',
    year:       toInt(r.year, 1),
    room:       toInt(r.room, 1),
    advisor_id: nonEmpty(r.advisorId) || nonEmpty(r.homeroomTeacher)
  }),
  students: (r) => ({
    student_id: nonEmpty(r.studentId),
    full_name:  nonEmpty(r.fullName) || nonEmpty(r.studentName) || '(ไม่มีชื่อ)',
    class_id:   nonEmpty(r.classId),
    status:     (nonEmpty(r.status) || 'active').toLowerCase()
  }),
  subjects: (r) => ({
    subject_id:   nonEmpty(r.subjectId),
    subject_name: nonEmpty(r.subjectName) || '(ไม่มีชื่อ)',
    major:        nonEmpty(r.major),
    course_type:  (nonEmpty(r.courseType) || 'normal').toLowerCase(),
    total_hours:  toInt(r.totalHours),
    start_date:   toDate(r.startDate),
    end_date:     toDate(r.endDate),
    department:   nonEmpty(r.department)
  }),
  subject_teachers: (r) => ({
    subject_id: nonEmpty(r.subjectId),
    teacher_id: nonEmpty(r.teacherId)
  }),
  subject_schedule: (r) => ({
    subject_id: nonEmpty(r.subjectId),
    date:       toDate(r.date),
    periods:    nonEmpty(r.periods)
  }),
  enrollments: (r) => ({
    student_id: nonEmpty(r.studentId),
    subject_id: nonEmpty(r.subjectId),
    class_id:   nonEmpty(r.classId)
  }),
  attendance: (r) => ({
    date:       toDate(r.date),
    subject_id: nonEmpty(r.subjectId),
    student_id: nonEmpty(r.studentId),
    status:     nonEmpty(r.status),
    period:     toInt(r.period, 1),
    checked_by: nonEmpty(r.checkedBy),
    note:       nonEmpty(r.note),
    late_at:    nonEmpty(r.lateAt)
  }),
  teaching_logs: (r) => ({
    subject_id: nonEmpty(r.subjectId),
    date:       toDate(r.date),
    teacher_id: nonEmpty(r.teacherId),
    content:    nonEmpty(r.content) || nonEmpty(r.detail),
    materials:  nonEmpty(r.materials),
    motivation: nonEmpty(r.motivation),
    results:    nonEmpty(r.results),
    problems:   nonEmpty(r.problems),
    image_url:  nonEmpty(r.imageUrl) || nonEmpty(r.image_url)
  })
};

// ============================================
// Validation — กรอง row ที่ไม่ valid ออก
// ============================================
function validate(table, rows) {
  const filtered = [];
  const errors = [];
  rows.forEach((r, i) => {
    // PK ต้องมี
    const pks = {
      teachers: ['teacher_id'],
      classes: ['class_id'],
      students: ['student_id'],
      subjects: ['subject_id'],
      subject_teachers: ['subject_id', 'teacher_id'],
      subject_schedule: ['subject_id', 'date'],
      enrollments: ['student_id', 'subject_id'],
      attendance: ['date', 'subject_id', 'student_id', 'period'],
      teaching_logs: ['subject_id', 'date']
    }[table] || [];
    const missing = pks.filter(k => !r[k]);
    if (missing.length > 0) {
      errors.push(`row ${i + 2}: missing ${missing.join(',')}`);
      return;
    }
    // status check
    if (table === 'attendance') {
      if (!['มา','ขาด','สาย','ลาป่วย','ลากิจ'].includes(r.status)) {
        errors.push(`row ${i + 2}: invalid status "${r.status}"`);
        return;
      }
    }
    filtered.push(r);
  });
  if (errors.length > 0) {
    console.log(`     ⚠  ${errors.length} rows skipped (${errors.slice(0, 3).join('; ')}${errors.length > 3 ? '...' : ''})`);
  }
  return filtered;
}

// ============================================
// Phase 2 (แบบ A): สร้าง Supabase Auth users สำหรับครูทุกคนที่มี email
// ============================================
async function createAuthUsersForTeachers() {
  console.log('🔐 Create Auth users (Phase 2 — แบบ A)');
  console.log(`   รหัสเริ่มต้น: ${INITIAL_PASSWORD}`);
  console.log(`   admin emails: ${ADMIN_EMAILS.join(', ') || '(ไม่มี)'}`);
  console.log('');

  // 1. ดึงรายชื่อครูที่มี email จาก DB (หลังจาก migrate teachers แล้ว)
  const { data: teachers, error: teachErr } = await supabase
    .from('teachers')
    .select('teacher_id, full_name, email, status')
    .not('email', 'is', null)
    .eq('status', 'active');

  if (teachErr) {
    console.error(`  ❌ อ่าน teachers ไม่สำเร็จ:`, teachErr.message);
    throw teachErr;
  }
  if (!teachers || teachers.length === 0) {
    console.log(`  ⏭  ไม่มีครูที่มี email — ข้าม`);
    return { created: 0, skipped: 0, errored: 0 };
  }

  console.log(`  พบครู ${teachers.length} คนที่มี email`);
  console.log('');

  // 2. ดึง email ที่มีอยู่ใน auth.users แล้ว เพื่อไม่ให้สร้างซ้ำ
  let existingEmails = new Set();
  if (!DRY_RUN) {
    let page = 1;
    while (true) {
      const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) throw error;
      data.users.forEach(u => u.email && existingEmails.add(u.email.toLowerCase()));
      if (data.users.length < 1000) break;
      page++;
    }
    console.log(`  มี Auth users อยู่แล้ว: ${existingEmails.size} คน`);
  }

  // 3. สร้างทีละคน (Supabase Admin API ไม่มี bulk create)
  let created = 0, skipped = 0, errored = 0;
  const errors = [];
  for (const t of teachers) {
    const email = (t.email || '').trim().toLowerCase();
    if (!email || !email.includes('@')) {
      skipped++;
      continue;
    }
    if (existingEmails.has(email)) {
      skipped++;
      process.stdout.write(`     ⏭  ${email} (มีอยู่แล้ว)\n`);
      continue;
    }

    const isAdmin = ADMIN_EMAILS.includes(email);
    const meta = {
      source: 'migration',
      role: isAdmin ? 'admin' : 'user',
      full_name: t.full_name,
      teacher_id: t.teacher_id,
      must_change_password: true
    };

    if (DRY_RUN) {
      console.log(`     [dry-run] ${email}  role=${meta.role}  teacher_id=${t.teacher_id}`);
      created++;
      continue;
    }

    const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
      email,
      password: INITIAL_PASSWORD,
      email_confirm: true,        // ไม่ต้อง verify email
      user_metadata: meta
    });

    if (createErr) {
      errored++;
      errors.push(`${email}: ${createErr.message}`);
      process.stdout.write(`     ❌ ${email}: ${createErr.message}\n`);
      continue;
    }

    // 4. ผูก teacher_id ใน public.users (trigger สร้าง row แล้ว แต่ต้อง update teacher_id เพิ่ม)
    const { error: linkErr } = await supabase
      .from('users')
      .update({
        teacher_id: t.teacher_id,
        full_name: t.full_name,
        role: isAdmin ? 'admin' : 'user',
        status: 'active',
        must_change_password: true
      })
      .eq('id', newUser.user.id);

    if (linkErr) {
      errored++;
      errors.push(`${email} (link): ${linkErr.message}`);
      process.stdout.write(`     ⚠  ${email}: created but link failed — ${linkErr.message}\n`);
      continue;
    }

    created++;
    if (created % 10 === 0) {
      process.stdout.write(`     ✓ ${created}/${teachers.length}\r`);
    }
  }

  console.log('');
  console.log(`     ✅ created:  ${created}`);
  console.log(`     ⏭  skipped:  ${skipped} (ซ้ำ / ไม่มี email)`);
  console.log(`     ❌ errored:  ${errored}`);
  if (errors.length > 0) {
    console.log('     errors (3 แรก):');
    errors.slice(0, 3).forEach(e => console.log(`        - ${e}`));
  }
  console.log('');

  return { created, skipped, errored };
}

// ============================================
// Main
// ============================================
async function main() {
  const mode = AUTH_ONLY ? 'AUTH-ONLY' : (DRY_RUN ? 'DRY-RUN' : 'LIVE');
  console.log(`🚀 Migration (${mode})`);
  console.log(`   Supabase: ${SUPABASE_URL}`);
  console.log(`   CSV dir:  ${CSV_DIR}`);
  console.log(`   Auth:     ${CREATE_AUTH ? 'YES (Phase 2 แบบ A)' : 'NO (ข้าม)'}`);
  console.log('');

  const stats = { total: 0, byTable: {}, auth: null };

  if (!AUTH_ONLY) {
    // ⭐ ลำดับสำคัญ — parent → child
    const order = [
      { table: 'teachers',         file: 'Teachers.csv',         conflict: 'teacher_id' },
      { table: 'classes',          file: 'Classes.csv',          conflict: 'class_id' },
      { table: 'students',         file: 'Students.csv',         conflict: 'student_id' },
      { table: 'subjects',         file: 'Subjects.csv',         conflict: 'subject_id' },
      { table: 'subject_teachers', file: 'SubjectTeachers.csv',  conflict: 'subject_id,teacher_id' },
      { table: 'subject_schedule', file: 'SubjectSchedule.csv',  conflict: 'subject_id,date' },
      { table: 'enrollments',      file: 'Enrollments.csv',      conflict: 'student_id,subject_id' },
      { table: 'attendance',       file: 'Attendance.csv',       conflict: 'subject_id,student_id,date,period' },
      { table: 'teaching_logs',    file: 'TeachingLogs.csv',     conflict: 'subject_id,date,teacher_id' }
    ];

    // ตารางพ่อ + col PK สำหรับ load cache
    const PARENT_PK = {
      teachers: 'teacher_id',
      classes:  'class_id',
      students: 'student_id',
      subjects: 'subject_id'
    };

    for (const { table, file, conflict } of order) {
      console.log(`📋 ${table}  ←  ${file}`);
      const raw = readCsv(file);
      if (!raw) continue;
      console.log(`     Read: ${raw.length} rows`);
      const transformed = raw.map(T[table]);
      let valid = validate(table, transformed);
      if (valid.length === 0) {
        console.log(`     ⏭  no valid rows`);
        continue;
      }

      // ⭐ Load parent IDs ก่อน — สำหรับตรวจ FK ของตารางลูก
      if (PARENT_PK[table] && !DRY_RUN) {
        await loadParentCache(table, PARENT_PK[table]);
      }

      // ⭐ Filter orphan rows (FK ชี้ไปที่ข้อมูลที่ไม่มี)
      if (FK_CHECKS[table] && !DRY_RUN) {
        const { kept, orphans, byCol } = filterOrphans(table, valid);
        if (orphans > 0) {
          const detail = Object.entries(byCol).map(([c, n]) => `${c}:${n}`).join(', ');
          console.log(`     ⚠  ${orphans} orphan rows ข้าม (${detail}) — เหลือ ${kept.length}`);
        }
        valid = kept;
      }

      if (valid.length === 0) {
        console.log(`     ⏭  ไม่เหลือ valid rows หลังกรอง orphan`);
        continue;
      }

      const n = await upsertBatch(table, valid, conflict);
      stats.byTable[table] = n;
      stats.total += n;

      // ⭐ Refresh cache หลัง upsert parent (ถ้ามี row ใหม่)
      if (PARENT_PK[table] && !DRY_RUN) {
        await loadParentCache(table, PARENT_PK[table]);
      }

      console.log('');
    }
  }

  // ⭐ Phase 2 (แบบ A): สร้าง Auth users
  if (CREATE_AUTH) {
    stats.auth = await createAuthUsersForTeachers();
  }

  console.log('═══════════════════════════');
  console.log(`✅ Migration ${mode} COMPLETE`);
  if (!AUTH_ONLY) {
    console.log(`   Total rows: ${stats.total}`);
    Object.entries(stats.byTable).forEach(([t, n]) => {
      console.log(`   ${t.padEnd(20)} ${n}`);
    });
  }
  if (stats.auth) {
    console.log(`   Auth users  created=${stats.auth.created}  skipped=${stats.auth.skipped}  errored=${stats.auth.errored}`);
  }
}

main().catch(err => {
  console.error('❌ Migration failed:', err);
  process.exit(1);
});
