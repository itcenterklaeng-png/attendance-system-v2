/**
 * Setup Super Admin
 *
 * ทำ 3 อย่าง:
 *   1. ตั้ง password ให้ itcenterklaeng@gmail.com (Auth)
 *   2. UPSERT public.users → role='admin', full_name='Super Admin'
 *   3. ลด kroobank100@gmail.com → role='user' (เป็นครูธรรมดา)
 *
 * Usage:
 *   cd scripts
 *   node setup-admin.js [--admin-password=YourSecurePass]
 *
 * ถ้าไม่ใส่ --admin-password → ใช้ default = 'Admin@2569'
 */

import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

const ADMIN_EMAIL = 'itcenterklaeng@gmail.com';
const ADMIN_NAME  = 'Super Admin';
const TEACHER_DEMOTE = 'kroobank100@gmail.com';

// อ่าน --admin-password=xxx จาก CLI args
function getArg(name, def) {
  const a = process.argv.find(x => x.startsWith(`--${name}=`));
  return a ? a.split('=', 2)[1] : def;
}
const ADMIN_PASSWORD = getArg('admin-password', 'Admin@2569');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_SERVICE_KEY in .env');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false }
});

async function findAuthUserByEmail(email) {
  // listUsers paginated — หา user
  let page = 1;
  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const found = data.users.find(u => (u.email || '').toLowerCase() === email.toLowerCase());
    if (found) return found;
    if (data.users.length < 1000) return null;
    page++;
  }
}

async function main() {
  console.log('🔧 Setup Super Admin');
  console.log(`   Supabase: ${SUPABASE_URL}`);
  console.log(`   Admin:    ${ADMIN_EMAIL}`);
  console.log(`   Password: ${ADMIN_PASSWORD}`);
  console.log('');

  // ==========================
  // 1. หา itcenterklaeng ใน auth.users
  // ==========================
  console.log(`1️⃣  ตรวจ ${ADMIN_EMAIL} ใน auth.users…`);
  let adminAuth = await findAuthUserByEmail(ADMIN_EMAIL);

  if (!adminAuth) {
    // สร้างใหม่
    console.log(`     ⚠  ไม่พบ — สร้างใหม่`);
    const { data, error } = await supabase.auth.admin.createUser({
      email: ADMIN_EMAIL,
      password: ADMIN_PASSWORD,
      email_confirm: true,
      user_metadata: {
        source: 'setup-admin',
        role: 'admin',
        full_name: ADMIN_NAME,
        must_change_password: false
      }
    });
    if (error) throw error;
    adminAuth = data.user;
    console.log(`     ✅ สร้างแล้ว (id=${adminAuth.id.slice(0, 8)}…)`);
  } else {
    console.log(`     ✓ พบ — กำลังตั้ง password ใหม่ (id=${adminAuth.id.slice(0, 8)}…)`);
    const { error } = await supabase.auth.admin.updateUserById(adminAuth.id, {
      password: ADMIN_PASSWORD,
      email_confirm: true
    });
    if (error) throw error;
    console.log(`     ✅ ตั้ง password ใหม่แล้ว`);
  }

  // ==========================
  // 2. UPSERT public.users → Super Admin
  // ==========================
  console.log('');
  console.log('2️⃣  UPSERT public.users → Super Admin…');
  const { error: upErr } = await supabase
    .from('users')
    .upsert({
      id: adminAuth.id,
      email: ADMIN_EMAIL,
      role: 'admin',
      full_name: ADMIN_NAME,
      teacher_id: null,
      status: 'active',
      must_change_password: false
    }, { onConflict: 'id' });
  if (upErr) throw upErr;
  console.log(`     ✅ ${ADMIN_EMAIL} → role=admin, full_name="${ADMIN_NAME}"`);

  // ==========================
  // 3. ลด kroobank100 เป็น user
  // ==========================
  console.log('');
  console.log(`3️⃣  ลด ${TEACHER_DEMOTE} → role=user…`);
  const { data: demoted, error: dErr } = await supabase
    .from('users')
    .update({ role: 'user' })
    .eq('email', TEACHER_DEMOTE)
    .select('email, role, teacher_id, full_name');
  if (dErr) throw dErr;
  if (demoted && demoted.length > 0) {
    console.log(`     ✅ ${TEACHER_DEMOTE} → role=${demoted[0].role}, teacher_id=${demoted[0].teacher_id}`);
  } else {
    console.log(`     ⚠  ไม่พบ ${TEACHER_DEMOTE} ใน public.users — ข้าม`);
  }

  // ==========================
  // 4. Verify
  // ==========================
  console.log('');
  console.log('4️⃣  Verify…');
  const { data: verify, error: vErr } = await supabase
    .from('users')
    .select('email, role, teacher_id, full_name, status, must_change_password')
    .in('email', [ADMIN_EMAIL, TEACHER_DEMOTE])
    .order('role', { ascending: false });
  if (vErr) throw vErr;
  console.table(verify);

  console.log('');
  console.log('═══════════════════════════════════');
  console.log('✅ SETUP COMPLETE');
  console.log('');
  console.log(`   Super Admin Login:`);
  console.log(`     email:    ${ADMIN_EMAIL}`);
  console.log(`     password: ${ADMIN_PASSWORD}`);
  console.log('');
  console.log(`   ${TEACHER_DEMOTE} ตอนนี้เป็นครูธรรมดา (role=user)`);
  console.log('═══════════════════════════════════');
}

main().catch(err => {
  console.error('❌ Setup failed:', err);
  process.exit(1);
});
