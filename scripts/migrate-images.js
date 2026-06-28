/**
 * Migrate รูปภาพจาก Google Drive → Supabase Storage
 *
 * Usage:
 *   node migrate-images.js              # รันจริง
 *   node migrate-images.js --dry-run    # ลอง parse ดูว่าจะทำอะไร ไม่ download ไม่ upload
 *   node migrate-images.js --limit 10   # ทำ 10 อันแรก
 *   node migrate-images.js --resume     # ข้าม row ที่ image_url เป็น supabase URL แล้ว
 */

import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

const DRY_RUN = process.argv.includes('--dry-run');
const RESUME  = process.argv.includes('--resume') || true;  // default = resume
const LIMIT   = (() => {
  const i = process.argv.indexOf('--limit');
  if (i === -1) return null;
  return parseInt(process.argv[i + 1], 10);
})();
const DELAY_MS = 1000;  // delay ระหว่างรูป ป้องกัน Drive rate-limit
const BUCKET = 'teaching-logs';

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
function isSupabaseUrl(url) {
  return url && url.includes('supabase.co/storage/v1/object');
}
function isDriveUrl(url) {
  return url && (url.includes('drive.google.com') || url.includes('googleusercontent.com'));
}

function extractDriveId(url) {
  if (!url) return null;
  const m1 = url.match(/[?&]id=([a-zA-Z0-9_-]+)/);
  const m2 = url.match(/\/file\/d\/([a-zA-Z0-9_-]+)/);
  const m3 = url.match(/googleusercontent\.com\/d\/([a-zA-Z0-9_-]+)/);
  return (m1 || m2 || m3)?.[1] || null;
}

function gdriveFallbackUrls(id) {
  return [
    `https://drive.google.com/thumbnail?id=${id}&sz=w1600`,
    `https://lh3.googleusercontent.com/d/${id}=w1600`,
    `https://drive.google.com/uc?export=view&id=${id}`,
    `https://drive.google.com/uc?id=${id}`
  ];
}

async function tryDownload(urls) {
  for (const url of urls) {
    try {
      const res = await fetch(url, {
        redirect: 'follow',
        headers: { 'User-Agent': 'Mozilla/5.0 attendance-migration' }
      });
      if (!res.ok) continue;
      const ct = res.headers.get('content-type') || '';
      if (!ct.startsWith('image/')) continue;
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length < 1000) continue;   // ต่ำกว่า 1KB น่าจะเป็น error page
      return { buf, contentType: ct, url };
    } catch (e) { /* ลองตัวต่อไป */ }
  }
  return null;
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ============================================
// Main
// ============================================
async function main() {
  console.log(`🖼  Migrate รูปภาพ ${DRY_RUN ? '(DRY-RUN)' : '(LIVE)'}`);
  console.log(`   Supabase: ${SUPABASE_URL}`);
  console.log(`   Bucket:   ${BUCKET}`);
  if (LIMIT) console.log(`   Limit:    ${LIMIT}`);
  console.log('');

  // 1. ดึง teaching_logs ที่ image_url เป็น drive
  let q = supabase
    .from('teaching_logs')
    .select('id, subject_id, date, teacher_id, image_url')
    .not('image_url', 'is', null);
  if (LIMIT) q = q.limit(LIMIT * 3);   // เผื่อ filter
  const { data: logs, error } = await q;
  if (error) { console.error('❌ load fail:', error.message); process.exit(1); }

  const targets = logs.filter(l => {
    if (!l.image_url) return false;
    if (RESUME && isSupabaseUrl(l.image_url)) return false;   // ข้ามที่ migrate แล้ว
    return isDriveUrl(l.image_url);
  }).slice(0, LIMIT || 9999);

  console.log(`📋 พบ ${logs.length} rows ที่มี image_url`);
  console.log(`   → จะ migrate ${targets.length} รูป (ข้าม ${logs.length - targets.length} ที่เสร็จแล้ว/ไม่ใช่ drive)`);
  console.log('');

  const stats = { ok: 0, fail: 0, skip: 0, errors: [] };

  for (let i = 0; i < targets.length; i++) {
    const log = targets[i];
    const progress = `[${i + 1}/${targets.length}]`;
    const id = extractDriveId(log.image_url);
    if (!id) {
      console.log(`${progress} ⚠  log #${log.id}: ไม่พบ drive id`);
      stats.skip++; continue;
    }

    process.stdout.write(`${progress} log #${log.id} (subject=${log.subject_id} date=${log.date}) → drive id ${id} ... `);

    if (DRY_RUN) {
      console.log('SKIP (dry-run)');
      stats.skip++;
      continue;
    }

    // 2. ดาวน์โหลดจาก Drive (ลอง 4 URL)
    const dl = await tryDownload(gdriveFallbackUrls(id));
    if (!dl) {
      console.log('❌ download fail (รูปอาจถูกลบหรือ private)');
      stats.fail++;
      stats.errors.push(`log #${log.id}: download fail (drive id ${id})`);
      await sleep(DELAY_MS);
      continue;
    }

    // 3. upload ไป Supabase Storage
    const ext = dl.contentType.includes('png') ? 'png'
              : dl.contentType.includes('webp') ? 'webp'
              : 'jpg';
    const path = `${log.subject_id}/${log.id}.${ext}`;

    const { error: upErr } = await supabase.storage
      .from(BUCKET)
      .upload(path, dl.buf, { contentType: dl.contentType, upsert: true });

    if (upErr) {
      console.log(`❌ upload fail: ${upErr.message}`);
      stats.fail++;
      stats.errors.push(`log #${log.id}: ${upErr.message}`);
      await sleep(DELAY_MS);
      continue;
    }

    // 4. ดึง public URL
    const { data: { publicUrl } } = supabase.storage.from(BUCKET).getPublicUrl(path);

    // 5. update DB
    const { error: updErr } = await supabase
      .from('teaching_logs')
      .update({ image_url: publicUrl })
      .eq('id', log.id);

    if (updErr) {
      console.log(`❌ DB update fail: ${updErr.message}`);
      stats.fail++;
      stats.errors.push(`log #${log.id}: ${updErr.message}`);
      await sleep(DELAY_MS);
      continue;
    }

    console.log(`✅ ${(dl.buf.length / 1024).toFixed(0)} KB → ${path}`);
    stats.ok++;
    await sleep(DELAY_MS);
  }

  console.log('');
  console.log('═══════════════════════════════════');
  console.log(`✅ COMPLETE`);
  console.log(`   ✓ success: ${stats.ok}`);
  console.log(`   ✗ failed:  ${stats.fail}`);
  console.log(`   ⏭ skipped: ${stats.skip}`);
  if (stats.errors.length > 0) {
    console.log('');
    console.log('   Errors (10 แรก):');
    stats.errors.slice(0, 10).forEach(e => console.log('     - ' + e));
    if (stats.errors.length > 10) console.log(`     ...อีก ${stats.errors.length - 10} อัน`);
  }
  console.log('═══════════════════════════════════');
}

main().catch(err => {
  console.error('❌ Migration failed:', err);
  process.exit(1);
});
