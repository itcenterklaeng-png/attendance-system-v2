/**
 * Utility helpers — date, alert, DOM
 */

/**
 * วันที่วันนี้ ในรูปแบบ YYYY-MM-DD (timezone Bangkok)
 */
export function todayISO() {
  const d = new Date();
  const tz = -d.getTimezoneOffset();           // นาที offset
  const local = new Date(d.getTime() + tz * 60000);
  return local.toISOString().slice(0, 10);
}

/**
 * format date เป็นไทย (เช่น "27 มิ.ย. 2569")
 */
export function formatThaiDate(isoDate) {
  if (!isoDate) return '';
  const [y, m, d] = isoDate.split('-').map(Number);
  const months = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.','ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
  return `${d} ${months[m-1]} ${y + 543}`;
}

/**
 * แสดง alert ในกล่อง #alert-area + แสดง toast ลอยที่มุมขวาบน
 * type: 'success' | 'error' | 'warn' | 'info'
 */
export function showAlert(msg, type = 'info', timeout = 4000) {
  const area = document.getElementById('alert-area');
  if (area) {
    area.innerHTML = `<div class="alert alert-${type}">${msg}</div>`;
    if (timeout > 0 && type === 'success') {
      setTimeout(() => { if (area.firstChild?.textContent === msg) area.innerHTML = ''; }, timeout);
    }
  }
  // toast ที่มุมบนขวา — เห็นชัดแม้ scroll อยู่ล่าง
  showToast(msg, type, timeout);
}

function showToast(msg, type, timeout) {
  let host = document.getElementById('toast-host');
  if (!host) {
    host = document.createElement('div');
    host.id = 'toast-host';
    host.style.cssText = 'position:fixed; top:16px; right:16px; z-index:9999; max-width: 380px; display: flex; flex-direction: column; gap: 8px;';
    document.body.appendChild(host);
  }
  const toast = document.createElement('div');
  const colors = {
    success: 'background:#d1fae5; color:#065f46; border-left:4px solid #15803d;',
    error:   'background:#fee2e2; color:#991b1b; border-left:4px solid #dc2626;',
    warn:    'background:#fef3c7; color:#92400e; border-left:4px solid #b45309;',
    info:    'background:#dbeafe; color:#1e40af; border-left:4px solid #2563eb;'
  };
  toast.style.cssText = `${colors[type]} padding: 14px 16px; border-radius: 10px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); font-size: 14px; cursor: pointer; animation: slideIn .25s ease-out;`;
  toast.textContent = msg;
  toast.onclick = () => toast.remove();
  host.appendChild(toast);
  const dur = (type === 'error' || type === 'warn') ? Math.max(timeout, 6000) : (timeout || 4000);
  if (dur > 0) setTimeout(() => toast.remove(), dur);
}

// inject animation keyframes
if (typeof document !== 'undefined' && !document.getElementById('toast-anim')) {
  const style = document.createElement('style');
  style.id = 'toast-anim';
  style.textContent = '@keyframes slideIn { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }';
  document.head.appendChild(style);
}

/**
 * Debounce
 */
export function debounce(fn, ms = 300) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

/**
 * Escape HTML (สำหรับ insert text เข้า DOM)
 */
export function esc(s) {
  if (s == null) return '';
  return String(s).replace(/[&<>"']/g, c => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  }[c]));
}
