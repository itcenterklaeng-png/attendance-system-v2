/**
 * Shared layout — sidebar + topbar (เหมือน v1)
 * ใช้กับทุกหน้าที่ login แล้ว
 */
import { signOut } from './auth.js';
import { supabase } from './supabase-client.js';

const LOGO_URL = 'https://drive.google.com/thumbnail?id=1fWwwh6htzUfnuJ_UGUlY5DLEchopSbfi&sz=w128';

// เมนูทั้งหมด — กรองตาม role ตอน render (เอา "หน้าแรก" ออก — เช็คชื่อเป็นหน้าหลัก)
const MENU = [
  // ⭐ เมนูหลัก — สำหรับครูทุกคน + admin (เรียงตามที่ user ระบุ)
  { id: 'attendance',           href: 'attendance.html',           icon: 'fa-clipboard-check',label: 'เช็คชื่อนักเรียน',       roles: ['admin','user'] },
  { id: 'reports',              href: 'reports.html',              icon: 'fa-chart-bar',      label: 'รายงานการเช็คชื่อ',     roles: ['admin','user','executive'] },
  { id: 'teaching-log-reports', href: 'teaching-log-reports.html', icon: 'fa-file-alt',       label: 'รายงานบันทึกหลังสอน',   roles: ['admin','user','executive'] },
  { id: 'attendance-status',    href: 'attendance-status.html',    icon: 'fa-tasks',          label: 'ตรวจสอบสถานะเช็คชื่อ',  roles: ['admin','user'] },
  // ⭐ แดชบอร์ด — ครูทุกคนดูได้
  { id: 'dashboard',            href: 'dashboard.html',            icon: 'fa-tachometer-alt', label: 'แดชบอร์ด',               roles: ['admin','executive','user'] },
  // ⭐ เมนู admin only
  { id: 'admin',                href: 'admin.html',                icon: 'fa-cog',            label: 'จัดการระบบ',             roles: ['admin'] }
];

/**
 * เรียกใน script type="module" ของแต่ละหน้า:
 *   import { initLayout } from './js/layout.js';
 *   await initLayout(profile, 'home');
 */
export function initLayout(profile, activeId, opts = {}) {
  injectFonts();
  injectShell(profile, activeId, opts);
  startClock();
  wireGlobalHandlers();
  startPresence(profile);
}

function injectFonts() {
  if (document.getElementById('fa-css')) return;
  const links = [
    { id: 'fa-css',   href: 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css' },
    { id: 'bs-css',   href: 'https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css' },
    { id: 'sb-font',  href: 'https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600;700;800&display=swap' }
  ];
  links.forEach(l => {
    const link = document.createElement('link');
    link.id = l.id; link.rel = 'stylesheet'; link.href = l.href;
    document.head.appendChild(link);
  });
  const meta = document.createElement('meta');
  meta.name = 'theme-color'; meta.content = '#1a237e';
  document.head.appendChild(meta);

  // Responsive + font override (Bootstrap reset Sarabun ก่อน)
  if (!document.getElementById('layout-mq')) {
    const st = document.createElement('style');
    st.id = 'layout-mq';
    st.textContent = `
      /* ⭐ Force Sarabun font everywhere — override Bootstrap default */
      :root {
        --bs-body-font-family: 'Sarabun', 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
      }
      html, body, button, input, select, textarea, .form-control, .form-select, .btn,
      table, th, td, h1, h2, h3, h4, h5, h6, p, span, div, a, label, .card, .card-title, .card-subtitle {
        font-family: 'Sarabun', 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif !important;
      }
      code, pre, kbd, samp {
        font-family: 'Cascadia Code', 'Consolas', 'Courier New', monospace !important;
      }

      /* hover state ของ nav-btn */
      .nav-btn:hover { background: rgba(255,255,255,.07) !important; color:#fff !important; }

      /* presence pulse */
      @keyframes presence-pulse {
        0% { box-shadow: 0 0 0 0 rgba(34, 197, 94, .6); }
        70% { box-shadow: 0 0 0 8px rgba(34, 197, 94, 0); }
        100% { box-shadow: 0 0 0 0 rgba(34, 197, 94, 0); }
      }
      .presence-box:hover { background: #bbf7d0 !important; }

      /* presence popover */
      #presence-popover {
        position: fixed;
        top: 56px; right: 16px;
        background: #fff;
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        box-shadow: 0 10px 25px rgba(0,0,0,.12);
        min-width: 260px; max-width: 320px; max-height: 400px;
        overflow-y: auto;
        z-index: 100;
        padding: .75rem;
        display: none;
        font-family: 'Sarabun', sans-serif;
      }
      #presence-popover.show { display: block; }
      .presence-user-row {
        display: flex; align-items: center; gap: .55rem;
        padding: .5rem .35rem;
        border-radius: 6px;
        font-size: 13px;
      }
      .presence-user-row:hover { background: #f3f4f6; }
      .presence-user-avatar {
        width: 30px; height: 30px; border-radius: 50%;
        background: linear-gradient(135deg, #1a237e, #3949ab);
        color: #fff;
        display: flex; align-items: center; justify-content: center;
        font-weight: 700; font-size: 12px;
        flex-shrink: 0;
      }
      .presence-user-row.is-me .presence-user-avatar { background: linear-gradient(135deg, #ca8a04, #eab308); }

      @media (max-width: 768px) {
        #sidebar { transform: translateX(-100%); box-shadow: 5px 0 20px rgba(0,0,0,.3); }
        #sidebar.show { transform: translateX(0); }
        #main-content { margin-left: 0 !important; }
        .topbar { left: 0 !important; }
        .btn-hamburger { display: inline-flex !important; }
        #sidebar-overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,.5); z-index: 98; }
        #sidebar-overlay.show { display: block; }
      }
    `;
    document.head.appendChild(st);
  }
}

function injectShell(profile, activeId, opts) {
  const name = profile.teacher_full_name || profile.full_name || profile.email;
  const role = profile.role === 'admin' ? 'ผู้ดูแลระบบ'
             : profile.role === 'executive' ? 'ผู้บริหาร'
             : 'ครู';
  const teacherIdLine = profile.teacher_id ? `<div style="font-size:11px;opacity:.7">รหัส: ${escapeHtml(profile.teacher_id)}</div>` : '';
  // ⭐ เมนูแยก 2 กลุ่ม — กลุ่มหลัก vs กลุ่ม admin/executive
  const ADMIN_ONLY_IDS = new Set(['admin']);
  const allowed = MENU.filter(m => m.roles.includes(profile.role));
  const visibleAdminCount = allowed.filter(m => ADMIN_ONLY_IDS.has(m.id)).length;

  const renderNavBtn = (m) => {
    const active = m.id === activeId;
    const baseStyle = `display:flex;align-items:center;gap:10px;padding:11px 18px;text-decoration:none;font-size:13.5px;font-weight:${active ? 600 : 500};color:${active ? '#fff' : 'rgba(255,255,255,.75)'};background:${active ? 'rgba(255,255,255,.14)' : 'transparent'};border-left:3px solid ${active ? '#ffd600' : 'transparent'};transition:all .18s;`;
    return `
      <a class="nav-btn ${active ? 'active' : ''}" href="${m.href}" style="${baseStyle}">
        <i class="fas ${m.icon}" style="width:18px;text-align:center;font-size:14px;"></i>
        <span>${escapeHtml(m.label)}</span>
      </a>
    `;
  };

  const mainItems = allowed.filter(m => !ADMIN_ONLY_IDS.has(m.id)).map(renderNavBtn).join('');
  const adminItems = allowed.filter(m => ADMIN_ONLY_IDS.has(m.id)).map(renderNavBtn).join('');

  // เพิ่ม divider + section label ถ้ามีเมนู admin
  const dividerHtml = visibleAdminCount > 0 ? `
    <div style="margin:10px 16px 4px;padding-top:10px;border-top:1px solid rgba(255,255,255,.12);font-size:10.5px;color:rgba(255,214,0,.7);font-weight:700;letter-spacing:.5px;">
      <i class="fas fa-shield-alt me-1"></i> ผู้ดูแลระบบ
    </div>
  ` : '';
  const navItems = mainItems + dividerHtml + adminItems;

  // sidebar overlay (mobile)
  const overlay = document.createElement('div');
  overlay.id = 'sidebar-overlay';
  overlay.onclick = closeSidebar;
  document.body.prepend(overlay);

  // sidebar — inline style เป็น fallback กรณี CSS ยังไม่โหลด
  const sidebar = document.createElement('nav');
  sidebar.id = 'sidebar';
  sidebar.style.cssText = `
    width:260px; min-height:100vh;
    background:linear-gradient(180deg,#0d1657 0%,#1a237e 60%,#3949ab 100%);
    position:fixed; top:0; left:0; z-index:99;
    display:flex; flex-direction:column;
    transition:transform .25s ease;
    font-family:'Sarabun','Segoe UI',sans-serif;
    color:#fff;
  `;
  sidebar.innerHTML = `
    <div class="sidebar-brand" style="padding:16px 14px;text-align:center;border-bottom:1px solid rgba(255,255,255,.1);">
      <div class="brand-icon" style="width:52px;height:52px;border-radius:12px;background:rgba(255,214,0,.15);border:2px solid rgba(255,214,0,.5);display:inline-flex;align-items:center;justify-content:center;margin-bottom:6px;overflow:hidden;padding:4px;">
        <img src="${LOGO_URL}" alt="โลโก้" style="max-width:100%;max-height:100%;object-fit:contain;border-radius:50%;background:#fff;">
      </div>
      <h6 style="color:#fff;margin:0;font-weight:700;font-size:13px;line-height:1.4;">วิทยาลัยการอาชีพแกลง</h6>
      <small style="color:rgba(255,255,255,.5);font-size:10.5px;">ระบบเช็คชื่อนักเรียน</small>
    </div>
    <div class="sidebar-nav" style="padding:8px 0;flex:1;overflow-y:auto;">${navItems}</div>
    <div class="sidebar-footer" style="padding:12px;border-top:1px solid rgba(255,255,255,.1);">
      <div class="user-info" style="display:flex;align-items:center;gap:10px;padding:8px;border-radius:9px;background:rgba(255,255,255,.07);margin-bottom:8px;">
        <div class="user-avatar" style="width:36px;height:36px;border-radius:50%;background:rgba(255,214,0,.15);border:2px solid rgba(255,214,0,.5);display:flex;align-items:center;justify-content:center;color:#ffd600;font-size:20px;flex-shrink:0;"><i class="fas fa-user-circle"></i></div>
        <div style="flex:1;min-width:0;">
          <div class="user-name" title="${escapeHtml(name)}" style="font-weight:600;font-size:13px;color:#fff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${escapeHtml(name)}</div>
          <div class="user-role" style="font-size:11px;color:#ffd600;">${role}</div>
          ${teacherIdLine}
        </div>
      </div>
      <button class="btn-foot" onclick="window.location.href='change-password.html'" style="width:100%;padding:8px 12px;background:rgba(255,255,255,.1);color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:12.5px;font-family:inherit;text-align:left;margin-bottom:6px;">
        <i class="fas fa-key"></i> เปลี่ยนรหัสผ่าน
      </button>
      <button class="btn-foot danger" onclick="window._appLogout()" style="width:100%;padding:8px 12px;background:rgba(198,40,40,.3);color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:12.5px;font-family:inherit;text-align:left;">
        <i class="fas fa-sign-out-alt"></i> ออกจากระบบ
      </button>
      <div class="sidebar-credit" style="margin-top:12px;padding-top:10px;border-top:1px dashed rgba(255,255,255,.15);font-size:10.5px;color:rgba(255,255,255,.55);text-align:center;line-height:1.5;">
        <div style="font-weight:600;color:rgba(255,255,255,.75);">พัฒนาโดย</div>
        <div>ว่าที่ร้อยตรีพงศกร พงษ์พันนา</div>
        <div style="opacity:.75;">หัวหน้างานศูนย์ดิจิทัล<br>และสื่อสารองค์กร</div>
        <div style="opacity:.75;">วิทยาลัยการอาชีพแกลง</div>
      </div>
    </div>
  `;
  document.body.prepend(sidebar);

  // main-content wrapper around existing content
  const existing = document.body.querySelector('main, .container, .page-body, #app-body');
  let main;
  if (existing && existing.classList.contains('main-content')) {
    main = existing;
  } else {
    main = document.createElement('main');
    main.id = 'main-content';
    main.className = 'main-content';
    main.style.cssText = `
      margin-left:260px; min-height:100vh;
      padding:56px 16px 16px;
      transition:margin-left .25s ease;
    `;
    const topbar = `
      <div class="topbar" style="position:fixed;top:0;left:260px;right:0;height:56px;background:#fff;border-bottom:1px solid #e8eaf6;display:flex;align-items:center;justify-content:space-between;padding:0 16px;z-index:50;box-shadow:0 2px 8px rgba(0,0,0,.06);">
        <div class="d-flex align-items-center gap-2" style="display:flex;align-items:center;gap:8px;">
          <button class="btn-hamburger" onclick="window._toggleSidebar()" aria-label="เมนู" style="background:none;border:none;font-size:20px;color:#1a237e;cursor:pointer;padding:6px 10px;display:none;">
            <i class="fas fa-bars"></i>
          </button>
          <h1 class="page-title" style="font-size:18px;font-weight:700;color:#1a237e;margin:0;">
            <i class="fas ${opts.icon || 'fa-home'}"></i> ${escapeHtml(opts.title || 'หน้าหลัก')}
          </h1>
        </div>
        <div class="d-flex align-items-center gap-2" style="display:flex;align-items:center;gap:8px;">
          <button class="presence-box" id="presence-btn" title="คนที่ออนไลน์อยู่ — คลิกเพื่อดูรายชื่อ"
            style="background:#dcfce7;padding:6px 12px;border-radius:8px;font-size:12.5px;line-height:1.2;border:1px solid #bbf7d0;cursor:pointer;font-family:inherit;display:inline-flex;align-items:center;gap:6px;color:#166534;font-weight:700;">
            <span class="presence-dot" style="display:inline-block;width:8px;height:8px;border-radius:50%;background:#22c55e;box-shadow:0 0 0 0 rgba(34,197,94,.5);animation:presence-pulse 2s infinite;"></span>
            <span>ออนไลน์</span>
            <span class="presence-count" id="presence-count" style="background:#22c55e;color:#fff;padding:1px 8px;border-radius:999px;font-size:11.5px;min-width:18px;text-align:center;">1</span>
          </button>
          <div class="clock-box" style="background:#f0f2f5;padding:6px 12px;border-radius:8px;text-align:right;font-size:11px;line-height:1.2;">
            <div style="display:flex;align-items:baseline;gap:2px;justify-content:flex-end;">
              <span class="clock-time" id="clock-hm" style="font-weight:700;font-size:15px;color:#1a237e;">00:00</span>
              <span class="clock-sec"  id="clock-s" style="font-size:11px;color:#546e7a;">:00</span>
            </div>
            <div class="clock-date" id="clock-date" style="color:#546e7a;font-size:10.5px;"></div>
          </div>
        </div>
      </div>
      <div class="content-area" id="content-area"></div>
    `;
    main.innerHTML = topbar;
    // ย้าย body children (ที่ไม่ใช่ sidebar/overlay/script) เข้า content-area
    const contentArea = main.querySelector('#content-area');
    Array.from(document.body.children).forEach(el => {
      if (el === sidebar || el === overlay || el === main) return;
      if (el.tagName === 'SCRIPT' || el.tagName === 'TEMPLATE') return;
      if (el.id === 'toast-host') return;
      contentArea.appendChild(el);
    });
    document.body.appendChild(main);
  }
}

function closeSidebar() {
  document.getElementById('sidebar')?.classList.remove('show');
  document.getElementById('sidebar-overlay')?.classList.remove('show');
}
function toggleSidebar() {
  const sb = document.getElementById('sidebar');
  const ov = document.getElementById('sidebar-overlay');
  if (!sb) return;
  sb.classList.toggle('show');
  ov?.classList.toggle('show');
}

function wireGlobalHandlers() {
  window._toggleSidebar = toggleSidebar;
  window._closeSidebar  = closeSidebar;
  window._appLogout     = signOut;
}

function startClock() {
  const days = ['อาทิตย์','จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์'];
  const months = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.','ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
  function tick() {
    const d = new Date();
    const hm = `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
    const s = `:${String(d.getSeconds()).padStart(2,'0')}`;
    const dateStr = `${days[d.getDay()]} ${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear() + 543}`;
    const hmEl = document.getElementById('clock-hm');
    const sEl  = document.getElementById('clock-s');
    const dEl  = document.getElementById('clock-date');
    if (hmEl) hmEl.textContent = hm;
    if (sEl)  sEl.textContent  = s;
    if (dEl)  dEl.textContent  = dateStr;
  }
  tick();
  setInterval(tick, 1000);
}

function escapeHtml(s) {
  if (s == null) return '';
  return String(s).replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
}

// ============================================
// Realtime Presence — แสดงจำนวนคนออนไลน์ใน topbar
// ใช้ Supabase Realtime Presence (built-in)
// ============================================
let presenceChannel = null;
const PRESENCE_USERS = new Map(); // user_id → { name, role, joined_at }

function startPresence(profile) {
  if (!profile || !profile.id) return;
  const myUserId = profile.id;
  const myName = profile.teacher_full_name || profile.full_name || profile.email;
  const myRole = profile.role === 'admin' ? 'ผู้ดูแลระบบ'
              : profile.role === 'executive' ? 'ผู้บริหาร'
              : 'ครู';

  // สร้าง popover element
  let popover = document.getElementById('presence-popover');
  if (!popover) {
    popover = document.createElement('div');
    popover.id = 'presence-popover';
    document.body.appendChild(popover);
  }

  // toggle popover
  const btn = document.getElementById('presence-btn');
  if (btn) {
    btn.onclick = (e) => {
      e.stopPropagation();
      popover.classList.toggle('show');
      if (popover.classList.contains('show')) renderPopover(myUserId);
    };
  }
  // ปิด popover เมื่อคลิกที่อื่น
  document.addEventListener('click', (e) => {
    if (!popover.contains(e.target) && e.target.id !== 'presence-btn' && !e.target.closest('#presence-btn')) {
      popover.classList.remove('show');
    }
  });

  // ปิด channel เก่า (เผื่อ initLayout ถูกเรียกซ้ำ)
  if (presenceChannel) {
    try { supabase.removeChannel(presenceChannel); } catch {}
    presenceChannel = null;
  }

  presenceChannel = supabase.channel('online-users', {
    config: { presence: { key: myUserId } }
  });

  presenceChannel
    .on('presence', { event: 'sync' }, () => {
      const state = presenceChannel.presenceState();
      PRESENCE_USERS.clear();
      Object.keys(state).forEach(uid => {
        const meta = state[uid][0]; // เอา instance ล่าสุด (อาจมีหลาย tab)
        if (meta) PRESENCE_USERS.set(uid, meta);
      });
      updatePresenceUI(myUserId);
    })
    .subscribe(async (status) => {
      if (status === 'SUBSCRIBED') {
        await presenceChannel.track({
          user_id: myUserId,
          name: myName,
          role: myRole,
          email: profile.email,
          joined_at: new Date().toISOString()
        });
      }
    });

  // ออกจาก channel เมื่อปิด tab
  window.addEventListener('beforeunload', () => {
    if (presenceChannel) {
      try { presenceChannel.untrack(); supabase.removeChannel(presenceChannel); } catch {}
    }
  });
}

function updatePresenceUI(myUserId) {
  const count = PRESENCE_USERS.size;
  const el = document.getElementById('presence-count');
  if (el) el.textContent = String(count);
  // re-render popover ถ้าเปิดอยู่
  const pop = document.getElementById('presence-popover');
  if (pop && pop.classList.contains('show')) renderPopover(myUserId);
}

function renderPopover(myUserId) {
  const pop = document.getElementById('presence-popover');
  if (!pop) return;
  const list = Array.from(PRESENCE_USERS.entries()).map(([uid, meta]) => {
    const isMe = uid === myUserId;
    const name = meta.name || meta.email || 'ผู้ใช้';
    const role = meta.role || '';
    const initial = (name || '?').trim().charAt(0).toUpperCase();
    return `
      <div class="presence-user-row ${isMe ? 'is-me' : ''}" title="${escapeHtml(meta.email || '')}">
        <div class="presence-user-avatar">${escapeHtml(initial)}</div>
        <div style="flex:1;min-width:0;">
          <div style="font-weight:600;color:#1a237e;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">
            ${escapeHtml(name)}${isMe ? ' <span style="color:#ca8a04;font-size:11px;">(คุณ)</span>' : ''}
          </div>
          <div style="font-size:11px;color:#64748b;">${escapeHtml(role)}</div>
        </div>
        <span style="width:8px;height:8px;border-radius:50%;background:#22c55e;"></span>
      </div>
    `;
  }).join('');

  pop.innerHTML = `
    <div style="padding:.4rem .5rem;font-weight:700;color:#1a237e;border-bottom:1px solid #e5e7eb;margin-bottom:.4rem;display:flex;align-items:center;gap:.4rem;">
      <i class="fas fa-users" style="color:#22c55e;"></i>
      <span style="flex:1;">ออนไลน์ ${PRESENCE_USERS.size} คน</span>
    </div>
    ${list || '<div style="text-align:center;color:#94a3b8;padding:1rem;">ไม่มีคนออนไลน์</div>'}
  `;
}
