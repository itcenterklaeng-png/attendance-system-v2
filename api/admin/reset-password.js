/**
 * POST /api/admin/reset-password
 *
 * Body: { userId: string, newPassword?: string }
 * Header: Authorization: Bearer <admin-jwt>
 *
 * ตรวจ JWT ของ caller → ต้องเป็น role=admin
 * จากนั้น reset password ของ userId เป็น newPassword (default: '123456789')
 * + ตั้ง must_change_password = true (บังคับเปลี่ยนตอน login ครั้งหน้า)
 */

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY;

// admin client — ใช้ Service Role Key (bypass RLS)
const admin = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
  : null;

function json(res, status, payload) {
  res.status(status).setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(payload));
}

export default async function handler(req, res) {
  // CORS — สำหรับเรียกจาก browser
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'POST') {
    return json(res, 405, { error: 'Method not allowed' });
  }
  if (!admin) {
    return json(res, 500, { error: 'Server misconfigured — missing SUPABASE env vars' });
  }

  // 1. ดึง JWT จาก Authorization header
  const auth = req.headers.authorization || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return json(res, 401, { error: 'Missing Bearer token' });

  // 2. ตรวจ token → ได้ user
  const { data: u, error: uErr } = await admin.auth.getUser(token);
  if (uErr || !u?.user) return json(res, 401, { error: 'Invalid token' });
  const callerId = u.user.id;

  // 3. caller ต้องเป็น admin
  const { data: caller, error: cErr } = await admin
    .from('users')
    .select('role, status')
    .eq('id', callerId)
    .single();
  if (cErr) return json(res, 500, { error: 'Cannot verify caller: ' + cErr.message });
  if (caller?.status !== 'active' || caller?.role !== 'admin') {
    return json(res, 403, { error: 'Admin only' });
  }

  // 4. parse body
  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  const { userId, newPassword } = body || {};
  if (!userId) return json(res, 400, { error: 'Missing userId' });

  const password = (newPassword && newPassword.length >= 6) ? newPassword : '123456789';

  // 5. ดึง target user — เอา email ไปแสดงใน log
  const { data: target, error: tErr } = await admin
    .from('users')
    .select('email')
    .eq('id', userId)
    .single();
  if (tErr || !target) return json(res, 404, { error: 'Target user not found' });

  // 6. update password ใน Supabase Auth + email_confirm = true (กันกรณียังไม่ confirm)
  const { error: pwErr } = await admin.auth.admin.updateUserById(userId, {
    password,
    email_confirm: true
  });
  if (pwErr) return json(res, 500, { error: 'Reset password fail: ' + pwErr.message });

  // 7. ตั้ง must_change_password = true ใน public.users
  const { error: flagErr } = await admin
    .from('users')
    .update({ must_change_password: true })
    .eq('id', userId);
  if (flagErr) {
    // password reset แล้ว แต่ flag fail — log + ตอบกึ่งสำเร็จ
    return json(res, 200, {
      success: true,
      warning: 'Password reset OK, but flag update failed: ' + flagErr.message,
      email: target.email,
      newPassword: password
    });
  }

  // 8. บันทึก log
  try {
    await admin.from('logs').insert({
      user_id: callerId,
      action: 'ADMIN_RESET_PASSWORD',
      metadata: { target_user: userId, target_email: target.email }
    });
  } catch { /* ignore log error */ }

  return json(res, 200, {
    success: true,
    email: target.email,
    newPassword: password,
    mustChangePassword: true
  });
}
