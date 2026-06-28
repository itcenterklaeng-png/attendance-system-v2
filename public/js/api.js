/**
 * API helpers — wraps Supabase queries สำหรับงานเช็คชื่อ
 */
import { supabase } from './supabase-client.js';

/**
 * ดึงรายวิชาของครูคนนี้ (ผ่าน subject_teachers)
 * คืน [{subject_id, subject_name, major, course_type, classes: [{class_id, students_count}]}]
 */
export async function getMySubjects(teacherId) {
  if (!teacherId) return [];
  // ใช้ join 2 ระดับ — subject_teachers → subjects
  const { data, error } = await supabase
    .from('subject_teachers')
    .select('subject_id, subjects(subject_id, subject_name, major, course_type)')
    .eq('teacher_id', teacherId);
  if (error) throw error;
  return (data || [])
    .filter(r => r.subjects)
    .map(r => r.subjects)
    .sort((a, b) => (a.subject_id || '').localeCompare(b.subject_id || ''));
}

/**
 * ดึงห้องเรียนที่ enroll ในวิชานี้ (distinct class_id)
 */
export async function getClassesOfSubject(subjectId) {
  const { data, error } = await supabase
    .from('enrollments')
    .select('class_id, classes(class_id, major, level, year, room)')
    .eq('subject_id', subjectId)
    .not('class_id', 'is', null);
  if (error) throw error;
  const seen = new Set();
  const out = [];
  (data || []).forEach(r => {
    if (r.classes && !seen.has(r.classes.class_id)) {
      seen.add(r.classes.class_id);
      out.push(r.classes);
    }
  });
  return out.sort((a, b) => (a.class_id || '').localeCompare(b.class_id || ''));
}

/**
 * ดึงรายชื่อนักเรียน + status ของวันที่เลือก
 * เรียก RPC get_students_by_day()
 */
export async function getStudentsByDay({ subjectId, date, round = 1, classId = null }) {
  const { data, error } = await supabase.rpc('get_students_by_day', {
    p_subject_id: subjectId,
    p_date: date,
    p_round: round,
    p_class_id: classId
  });
  if (error) throw error;
  return data || [];
}

/**
 * บันทึกการเช็คชื่อ
 * records = [{student_id, status, note, late_at, class_id}]
 */
export async function saveDailyAttendance({ subjectId, date, round, records }) {
  const { data, error } = await supabase.rpc('save_daily_attendance', {
    p_subject_id: subjectId,
    p_date: date,
    p_round: round,
    p_records: records
  });
  if (error) throw error;
  return data;
}

// ============================================
// Dashboard helpers
// ============================================
export async function getDashboardSummary(date, round = 1) {
  const { data, error } = await supabase.rpc('get_dashboard_summary', { p_date: date, p_round: round });
  if (error) throw error;
  return data || {};
}
export async function getDashboardSubjects(date, round = 1) {
  const { data, error } = await supabase.rpc('get_dashboard_subjects', { p_date: date, p_round: round });
  if (error) throw error;
  return data || [];
}
export async function getTopTeachersToday(date, round = null, limit = 20) {
  const args = { p_date: date, p_limit: limit };
  if (round != null) args.p_round = round;
  const { data, error } = await supabase.rpc('get_top_teachers_today', args);
  if (error) throw error;
  return data || [];
}
export async function getTrend7Days(date, round = 1) {
  const { data, error } = await supabase.rpc('get_trend_7days', {
    p_end_date: date, p_round: round
  });
  if (error) throw error;
  return data || [];
}
export async function getTeacherHome(teacherId, date) {
  const { data, error } = await supabase.rpc('get_teacher_home', {
    p_teacher_id: teacherId, p_date: date
  });
  if (error) throw error;
  return data || [];
}

export async function getSubjectHeaderInfo(subjectId) {
  const { data, error } = await supabase.rpc('get_subject_header_info', { p_subject_id: subjectId });
  if (error) throw error;
  return data || {};
}

export async function getStudentsByStatusToday(date, status, round = 1) {
  const { data, error } = await supabase.rpc('get_students_by_status_today', {
    p_date: date, p_status: status, p_round: round
  });
  if (error) throw error;
  return data || [];
}

export async function getSubjectDetailByDay(subjectId, date, round = 1) {
  const { data, error } = await supabase.rpc('get_subject_detail_by_day', {
    p_subject_id: subjectId, p_date: date, p_round: round
  });
  if (error) throw error;
  return data || [];
}

export async function getTopAbsentees({ from = null, to = null, limit = 30 } = {}) {
  const { data, error } = await supabase.rpc('get_top_absentees', {
    p_date_from: from, p_date_to: to, p_limit: limit
  });
  if (error) throw error;
  return data || [];
}

/**
 * รายงาน — สรุปต่อนักเรียน
 */
export async function getAttendanceSummary({ subjectId, dateFrom, dateTo, classId = null, round = null }) {
  const { data, error } = await supabase.rpc('get_attendance_summary', {
    p_subject_id: subjectId,
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_class_id:  classId,
    p_round:     round
  });
  if (error) throw error;
  return data || [];
}

/**
 * รายงาน — Matrix (นักเรียน x วัน)
 */
export async function getAttendanceMatrix({ subjectId, dateFrom, dateTo, classId = null, round = 1 }) {
  const { data, error } = await supabase.rpc('get_attendance_matrix', {
    p_subject_id: subjectId,
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_class_id:  classId,
    p_round:     round
  });
  if (error) throw error;
  return data || [];
}

/**
 * รายงาน — รายการวันที่ที่มีการเช็คชื่อ
 */
export async function getAttendanceDates({ subjectId, dateFrom, dateTo, round = 1 }) {
  const { data, error } = await supabase.rpc('get_attendance_dates', {
    p_subject_id: subjectId,
    p_date_from: dateFrom,
    p_date_to:   dateTo,
    p_round:     round
  });
  if (error) throw error;
  return (data || []).map(d => d.date);
}

/**
 * Download CSV — สร้าง Blob + click link เพื่อ save
 */
export function downloadCsv(filename, rows) {
  if (!rows || rows.length === 0) { alert('ไม่มีข้อมูลให้ export'); return; }
  const headers = Object.keys(rows[0]);
  const escape = v => {
    if (v == null) return '';
    let s = String(v);
    if (/[",\r\n]/.test(s)) s = `"${s.replace(/"/g, '""')}"`;
    return s;
  };
  const csv = [
    headers.join(','),
    ...rows.map(r => headers.map(h => escape(r[h])).join(','))
  ].join('\r\n');
  // BOM ให้ Excel เปิดภาษาไทยได้ถูก
  const blob = new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * Teaching log — ดึงรายการบันทึก (filter ตามวิชา + ช่วงวันที่)
 */
export async function listTeachingLogs({ subjectId = null, teacherId = null, dateFrom = null, dateTo = null, limit = 200 }) {
  let q = supabase.from('teaching_logs_view').select('*');
  if (subjectId) q = q.eq('subject_id', subjectId);
  if (teacherId) q = q.eq('teacher_id', teacherId);
  if (dateFrom)  q = q.gte('date', dateFrom);
  if (dateTo)    q = q.lte('date', dateTo);
  q = q.order('date', { ascending: false }).limit(limit);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}

/**
 * Teaching log — บันทึก (UPSERT) — ฟิลด์ตาม v1
 */
export async function saveTeachingLog({
  subjectId, date, periods,
  materials, content, motivation, results, problems,
  imageUrl, objectives, suggestions
}) {
  const { data, error } = await supabase.rpc('save_teaching_log', {
    p_subject_id:  subjectId,
    p_date:        date,
    p_periods:     periods || '',
    p_materials:   materials || '',
    p_content:     content || '',
    p_motivation:  motivation || '',
    p_results:     results || '',
    p_problems:    problems || '',
    p_image_url:   imageUrl || null,
    p_objectives:  objectives || null,
    p_suggestions: suggestions || null
  });
  if (error) throw error;
  return data;
}

/**
 * Upload รูปไป Supabase Storage → คืน public URL
 * file = Blob/File object
 * path = "{subject_id}/{filename}"
 */
const TEACHING_LOG_BUCKET = 'teaching-logs';

export async function uploadTeachingLogImage(file, { subjectId, ext = 'jpg' }) {
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 8);
  const path = `${subjectId}/${ts}-${rand}.${ext}`;

  const { error } = await supabase.storage
    .from(TEACHING_LOG_BUCKET)
    .upload(path, file, {
      contentType: file.type || `image/${ext}`,
      upsert: false
    });
  if (error) throw error;

  const { data: { publicUrl } } = supabase.storage
    .from(TEACHING_LOG_BUCKET)
    .getPublicUrl(path);
  return { url: publicUrl, path };
}

/**
 * ลบรูปออกจาก Storage
 */
export async function deleteTeachingLogImage(url) {
  if (!url) return;
  // หา path จาก URL
  const m = url.match(/teaching-logs\/(.+?)(\?|$)/);
  if (!m) return;
  const path = decodeURIComponent(m[1]);
  await supabase.storage.from(TEACHING_LOG_BUCKET).remove([path]);
}

/**
 * Teaching log — ลบ
 */
export async function deleteTeachingLog(id) {
  const { data, error } = await supabase.rpc('delete_teaching_log', { p_id: id });
  if (error) throw error;
  return data;
}

// ============================================
// Admin CRUD helpers — ใช้ supabase.from() ตรง (RLS = admin only)
// ============================================
const STATUSES_AS = ['active', 'inactive'];

// ---- Teachers ----
export async function listTeachers({ search = '', limit = 1000 } = {}) {
  let q = supabase.from('teachers').select('*').order('teacher_id').limit(limit);
  if (search) {
    q = q.or(`teacher_id.ilike.%${search}%,full_name.ilike.%${search}%,email.ilike.%${search}%,department.ilike.%${search}%`);
  }
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}
export async function upsertTeacher(row) {
  const { error } = await supabase.from('teachers').upsert(row, { onConflict: 'teacher_id' });
  if (error) throw error;
}
export async function deleteTeacher(teacherId) {
  const { error } = await supabase.from('teachers').delete().eq('teacher_id', teacherId);
  if (error) throw error;
}

// ---- Students ----
export async function listStudents({ search = '', classId = null, limit = 2000 } = {}) {
  let q = supabase.from('students').select('*').order('student_id').limit(limit);
  if (classId) q = q.eq('class_id', classId);
  if (search) q = q.or(`student_id.ilike.%${search}%,full_name.ilike.%${search}%`);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}
export async function upsertStudent(row) {
  const { error } = await supabase.from('students').upsert(row, { onConflict: 'student_id' });
  if (error) throw error;
}
export async function deleteStudent(studentId) {
  const { error } = await supabase.from('students').delete().eq('student_id', studentId);
  if (error) throw error;
}

// ---- Classes ----
export async function listClasses({ search = '' } = {}) {
  let q = supabase.from('classes').select('*').order('class_id');
  if (search) q = q.or(`class_id.ilike.%${search}%,major.ilike.%${search}%`);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}
export async function upsertClass(row) {
  const { error } = await supabase.from('classes').upsert(row, { onConflict: 'class_id' });
  if (error) throw error;
}
export async function deleteClass(classId) {
  const { error } = await supabase.from('classes').delete().eq('class_id', classId);
  if (error) throw error;
}

// ---- Subjects ----
export async function listSubjects({ search = '' } = {}) {
  let q = supabase.from('subjects').select('*').order('subject_id');
  if (search) q = q.or(`subject_id.ilike.%${search}%,subject_name.ilike.%${search}%,major.ilike.%${search}%`);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}

// ---- Subjects + stats (จาก view) ----
export async function listSubjectsStats() {
  const { data, error } = await supabase
    .from('subjects_stats').select('*').order('subject_id');
  if (error) throw error;
  return data || [];
}

// ---- Classes + stats ----
export async function listClassesStats() {
  const { data, error } = await supabase
    .from('classes_stats').select('*').order('class_id');
  if (error) throw error;
  return data || [];
}

// ---- Subject Schedule (ตารางสอน) ----
export async function getSubjectScheduleAll(subjectId) {
  const { data, error } = await supabase
    .from('subject_schedule')
    .select('date, periods')
    .eq('subject_id', subjectId)
    .order('date');
  if (error) throw error;
  return data || [];
}

/** Overwrite ตารางสอนทั้งหมด — delete เก่า + insert ใหม่ */
export async function saveSubjectSchedule(subjectId, rows) {
  // 1. ลบของเก่า
  const { error: delErr } = await supabase
    .from('subject_schedule')
    .delete()
    .eq('subject_id', subjectId);
  if (delErr) throw delErr;

  // 2. insert ใหม่
  if (rows.length > 0) {
    const data = rows.map(r => ({
      subject_id: subjectId,
      date: r.date,
      periods: r.periods
    }));
    const { error: insErr } = await supabase.from('subject_schedule').insert(data);
    if (insErr) throw insErr;
  }
  return { success: true, count: rows.length };
}

// ดึง teacher mapping ของแต่ละ subject (สำหรับ render badge)
export async function getAllSubjectTeacherMap() {
  const { data, error } = await supabase
    .from('subject_teachers').select('subject_id, teacher_id');
  if (error) throw error;
  const map = {};
  (data || []).forEach(r => { (map[r.subject_id] ??= []).push(r.teacher_id); });
  return map;
}
export async function upsertSubject(row) {
  const { error } = await supabase.from('subjects').upsert(row, { onConflict: 'subject_id' });
  if (error) throw error;
}
export async function deleteSubject(subjectId) {
  const { error } = await supabase.from('subjects').delete().eq('subject_id', subjectId);
  if (error) throw error;
}

// ---- Subject Teachers (assign) ----
export async function getSubjectTeachers(subjectId) {
  const { data, error } = await supabase
    .from('subject_teachers')
    .select('teacher_id, teachers(teacher_id, full_name, department)')
    .eq('subject_id', subjectId);
  if (error) throw error;
  return (data || []).map(r => r.teachers).filter(Boolean);
}
export async function setSubjectTeachers(subjectId, teacherIds) {
  // ลบของเก่า + เพิ่มของใหม่
  await supabase.from('subject_teachers').delete().eq('subject_id', subjectId);
  if (teacherIds.length > 0) {
    const rows = teacherIds.map(tid => ({ subject_id: subjectId, teacher_id: tid }));
    const { error } = await supabase.from('subject_teachers').insert(rows);
    if (error) throw error;
  }
}

// ---- Enrollments ----
export async function bulkEnroll(classId, subjectIds) {
  const { data, error } = await supabase.rpc('bulk_enroll_class', {
    p_class_id: classId,
    p_subject_ids: subjectIds
  });
  if (error) throw error;
  return data;
}
export async function bulkUnenroll(classId, subjectId) {
  const { data, error } = await supabase.rpc('bulk_unenroll_class_subject', {
    p_class_id: classId,
    p_subject_id: subjectId
  });
  if (error) throw error;
  return data;
}
export async function getEnrollmentsOfClass(classId) {
  // หาวิชาที่ห้องนี้ enroll อยู่
  const { data, error } = await supabase
    .from('enrollments')
    .select('subject_id, subjects(subject_id, subject_name, major, course_type)')
    .eq('class_id', classId);
  if (error) throw error;
  const seen = new Set();
  return (data || []).reduce((out, r) => {
    if (r.subjects && !seen.has(r.subjects.subject_id)) {
      seen.add(r.subjects.subject_id);
      out.push(r.subjects);
    }
    return out;
  }, []);
}

/**
 * ดึง enrollment ทั้งหมด — { student_id, subject_id, class_id }
 * ใช้ในเมนูจัดการลงทะเบียน (aggregate by class + subject)
 */
export async function listAllEnrollments() {
  const PAGE = 1000;
  let all = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await supabase
      .from('enrollments')
      .select('student_id, subject_id, class_id')
      .range(from, from + PAGE - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    all = all.concat(data);
    if (data.length < PAGE) break;
  }
  return all;
}

/**
 * ดึงรายชื่อนักเรียน + วิชาในห้อง (สำหรับ class detail modal)
 *   → group by subject_id → [{student_id, full_name}]
 */
export async function getClassEnrollmentDetail(classId) {
  const { data, error } = await supabase
    .from('enrollments')
    .select('student_id, subject_id, students(full_name), subjects(subject_name)')
    .eq('class_id', classId);
  if (error) throw error;
  return data || [];
}

/**
 * สรุปจำนวนวัน/คาบ/ช่วงวันของแต่ละวิชา — ใช้แสดงใน Bulk Enroll preview
 *   → returns { subjectId: { days, periods, firstDate, lastDate } }
 */
export async function getSubjectScheduleCounts() {
  const { data, error } = await supabase.rpc('get_subject_schedule_counts');
  if (error) throw error;
  const map = {};
  (data || []).forEach(r => {
    map[r.subject_id] = {
      days: r.days,
      periods: r.periods,
      firstDate: r.first_date,
      lastDate: r.last_date
    };
  });
  return map;
}

/**
 * ลบ enrollment ทีละคน (admin only)
 */
export async function deleteEnrollment(studentId, subjectId) {
  const { data, error } = await supabase.rpc('delete_enrollment', {
    p_student_id: studentId,
    p_subject_id: subjectId
  });
  if (error) throw error;
  return data;
}

// ---- Users (admin only) ----
export async function listUsers({ search = '' } = {}) {
  let q = supabase.from('users').select('*, teachers(full_name, department)').order('email');
  if (search) q = q.or(`email.ilike.%${search}%,full_name.ilike.%${search}%,teacher_id.ilike.%${search}%,username.ilike.%${search}%`);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}
export async function updateUserRole(userId, patch) {
  const allowed = ['role', 'status', 'teacher_id', 'must_change_password', 'username', 'full_name'];
  const data = {};
  for (const k of allowed) if (patch[k] !== undefined) data[k] = patch[k];
  if (Object.keys(data).length === 0) return;
  const { error } = await supabase.from('users').update(data).eq('id', userId);
  if (error) throw error;
}

/**
 * ดึงสถานะการเช็คชื่อ/บันทึกหลังสอนของครู — สำหรับเมนู "ตรวจสอบสถานะ"
 *   → คืน [{ subjectId, subjectName, totalDates, attendedR1Count, ..., dates: [...] }]
 */
export async function getCheckStatusForTeacher(teacherId) {
  const { data, error } = await supabase.rpc('get_check_status_for_teacher', {
    p_teacher_id: teacherId
  });
  if (error) throw error;
  return data || [];
}

/**
 * Reset password ของ user คนอื่น (admin only)
 *   → เรียก Vercel serverless function /api/admin/reset-password
 *   → backend ตรวจ JWT + role=admin ก่อน reset
 */
export async function adminResetPassword(userId, newPassword) {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('ต้อง login ก่อน');

  const body = { userId };
  if (newPassword) body.newPassword = newPassword;

  const r = await fetch('/api/admin/reset-password', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + session.access_token
    },
    body: JSON.stringify(body)
  });
  const json = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(json.error || `HTTP ${r.status}`);
  return json;
}

/**
 * ดึงตารางสอนของวิชา (periods ของวันนั้น)
 */
export async function getSubjectSchedule(subjectId, date) {
  const { data, error } = await supabase
    .from('subject_schedule')
    .select('periods')
    .eq('subject_id', subjectId)
    .eq('date', date)
    .maybeSingle();
  if (error) throw error;
  return data?.periods || '';
}
