/**
 * Add User (Admin / Executive / Teacher)
 *
 * Usage:
 *   node add-user.js --email=foo@bar.com --password=Pass123 --role=admin
 *   node add-user.js --email=director@school.com --role=executive --name="ผอ.โรงเรียน"
 *   node add-user.js --email=teacher@gmail.com --role=user --teacher-id=t099
 *
 * Roles:
 *   admin     — ผู้ดูแลระบบ (สิทธิ์เต็ม)
 *   executive — ผู้บริหาร (ดูได้ทุกอย่าง แก้ไม่ได้)
 *   user      — ครู (เห็นเฉพาะวิชาของตัวเอง)
 *
 * Required:
 *   --email     อีเมล (จำเป็น)
 *
 * Optional:
 *   --password  รหัสผ่าน (default: 123456789 — ต้องเปลี่ยนตอน login ครั้งแรก)
 *   --role      admin / executive / user (default: user)
 *   --name      ชื่อจริง (สำหรับ admin/executive ที่ไม่ผูกกับ teacher)
 *   --teacher-id  ผูกกับ teacher_id (สำหรับ role=user)
 *   --no-force-change  ถ้าใส่ — ไม่ต้องบังคับเปลี่ยนรหัสครั้งแรก
 */

import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

function getArg(name, def) {
  const a = process.argv.find(x => x.startsWith(`--${name}=`));
  return a ? a.split('=', 2)[1] : def;
}
function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

const EMAIL    = getArg('email');
const PASSWORD = getArg('password', '123456789');
const ROLE     = getArg('role', 'user');
const NAME     = getArg('name', null);
const TEACHER  = getArg('teacher-id', null);
const USERNAME = getArg('username', null);   // สำหรับ login ง่ายๆ
const FORCE    = !hasFlag('no-force-change');

if (!EMAIL) {
  console.error('❌ Missing --email');
  console.error('   Example: node add-user.js --email=foo@bar.com --role=admin');
  process.exit(1);
}
if (!['admin', 'executive', 'user'].includes(ROLE)) {
  console.error(`❌ Invalid --role: ${ROLE}  (must be admin | executive | user)`);
  process.exit(1);
}

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
  const roleTH = { admin: 'ผู้ดูแลระบบ', executive: 'ผู้บริหาร', user: 'ครู' }[ROLE];
  console.log(`👤 Add User`);
  console.log(`   email:    ${EMAIL}`);
  console.log(`   password: ${PASSWORD}`);
  console.log(`   role:     ${ROLE} (${roleTH})`);
  if (NAME)     console.log(`   name:     ${NAME}`);
  if (USERNAME) console.log(`   username: ${USERNAME} (สำหรับ login สั้นๆ)`);
  if (TEACHER)  console.log(`   teacher:  ${TEACHER}`);
  console.log(`   change-on-first-login: ${FORCE ? 'YES' : 'NO'}`);
  console.log('');

  // 1. สร้าง / อัพเดท auth user
  let auth = await findAuthUserByEmail(EMAIL);
  if (auth) {
    console.log(`1️⃣  พบ user อยู่แล้ว → ตั้ง password ใหม่`);
    const { error } = await supabase.auth.admin.updateUserById(auth.id, {
      password: PASSWORD,
      email_confirm: true
    });
    if (error) throw error;
  } else {
    console.log(`1️⃣  สร้าง auth user ใหม่`);
    const { data, error } = await supabase.auth.admin.createUser({
      email: EMAIL,
      password: PASSWORD,
      email_confirm: true,
      user_metadata: {
        source: 'add-user',
        role: ROLE,
        full_name: NAME || EMAIL,
        must_change_password: FORCE
      }
    });
    if (error) throw error;
    auth = data.user;
  }
  console.log(`     ✅ id=${auth.id.slice(0, 8)}…`);

  // 2. UPSERT public.users
  console.log('');
  console.log('2️⃣  UPSERT public.users');
  const { error: upErr } = await supabase
    .from('users')
    .upsert({
      id: auth.id,
      email: EMAIL,
      role: ROLE,
      full_name: NAME || (TEACHER ? null : EMAIL),
      teacher_id: TEACHER,
      username: USERNAME,
      status: 'active',
      must_change_password: FORCE
    }, { onConflict: 'id' });
  if (upErr) throw upErr;
  console.log(`     ✅ role=${ROLE}`);

  // 3. Verify
  console.log('');
  console.log('3️⃣  Verify');
  const { data: row, error: vErr } = await supabase
    .from('users')
    .select('email, username, role, teacher_id, full_name, status, must_change_password')
    .eq('id', auth.id)
    .single();
  if (vErr) throw vErr;
  console.table([row]);

  console.log('');
  console.log('═══════════════════════════════════');
  console.log(`✅ DONE`);
  console.log('');
  console.log(`   Login info:`);
  console.log(`     email:    ${EMAIL}`);
  if (USERNAME) console.log(`     username: ${USERNAME}  ⭐ (ใช้แทน email ตอน login ได้)`);
  if (TEACHER)  console.log(`     teacherId: ${TEACHER}  (ใช้แทน email ตอน login ได้)`);
  console.log(`     password: ${PASSWORD}`);
  console.log(`     role:     ${roleTH}`);
  if (FORCE) console.log(`     ⚠ ต้องเปลี่ยนรหัสครั้งแรกที่ login`);
  console.log('═══════════════════════════════════');
}

main().catch(err => {
  console.error('❌ Failed:', err.message || err);
  process.exit(1);
});
