/**
 * Auth helpers — session check, login, logout, guard
 */
import { supabase } from './supabase-client.js';

/**
 * Resolve email — input อาจเป็น email หรือ teacherId
 * ถ้าเป็น teacherId → lookup จาก RPC
 */
export async function resolveEmail(input) {
  const s = (input || '').trim();
  if (!s) throw new Error('กรุณาใส่ ชื่อผู้ใช้ / รหัสครู / email');
  if (s.includes('@')) return s;

  // ใช้ unified lookup — ค้น username + teacher_id
  const { data, error } = await supabase.rpc('lookup_email_for_login', { p_input: s });
  if (error) throw new Error('Lookup fail: ' + error.message);
  if (!data) throw new Error(`ไม่พบผู้ใช้ "${s}" — ลองใส่ email แทน`);
  return data;
}

/**
 * Login (email + password)
 */
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

/**
 * Logout
 */
export async function signOut() {
  await supabase.auth.signOut();
  window.location.href = 'login.html';
}

/**
 * ดึง session ปัจจุบัน
 */
export async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

/**
 * ดึง profile (users + teachers join)
 */
export async function getProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from('users')
    .select('id, email, role, teacher_id, full_name, status, must_change_password, teachers(full_name, department)')
    .eq('id', user.id)
    .single();

  if (error) {
    console.error('getProfile error:', error);
    return null;
  }
  return {
    ...data,
    auth_email: user.email,
    teacher_full_name: data.teachers?.full_name,
    department: data.teachers?.department
  };
}

/**
 * Guard: ถ้าไม่ login → redirect ไป login.html
 * ถ้า must_change_password = true → redirect ไป change-password.html (ยกเว้นอยู่หน้านั้นอยู่แล้ว)
 * คืน profile กลับถ้าผ่าน
 */
export async function requireAuth({ requireChangePassword = true } = {}) {
  const session = await getSession();
  if (!session) {
    window.location.href = 'login.html';
    return null;
  }

  const profile = await getProfile();
  if (!profile) {
    window.location.href = 'login.html';
    return null;
  }

  if (profile.status !== 'active') {
    alert('บัญชีของคุณถูกระงับการใช้งาน');
    await signOut();
    return null;
  }

  if (requireChangePassword && profile.must_change_password) {
    if (!window.location.pathname.endsWith('change-password.html')) {
      window.location.href = 'change-password.html';
      return null;
    }
  }
  return profile;
}

/**
 * Render user info ใน header (ใช้ใน home/attendance)
 */
export function renderHeaderUser(profile) {
  const el = document.getElementById('header-user');
  if (!el || !profile) return;
  const name = profile.teacher_full_name || profile.full_name || profile.email;
  const roleBadge = profile.role === 'admin'
    ? '<span class="badge badge-admin">admin</span>'
    : '<span class="badge badge-user">ครู</span>';
  el.innerHTML = `
    <span>${name} ${roleBadge}</span>
    <button onclick="window._logout()">🚪 ออก</button>
  `;
  window._logout = signOut;
}
