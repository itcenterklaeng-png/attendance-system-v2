/**
 * Export 9 sheets เป็น CSV รวมเป็น zip ไฟล์เดียว
 *
 * วิธีใช้:
 *   1. เปิด Google Sheets ของระบบเดิม
 *   2. Extensions → Apps Script
 *   3. ลบโค้ดเดิม → paste โค้ดนี้ → กด Save (💾)
 *   4. เลือกฟังก์ชัน exportAllToCSV → กด Run
 *   5. ครั้งแรก จะขอ permission → Review permissions → Allow
 *   6. รอจนเสร็จ (~10 วินาที)
 *   7. ดูใน Google Drive → จะมีไฟล์ "attendance-csv-export-YYYYMMDD-HHMM.zip"
 *   8. ดาวน์โหลด zip → แตก → วาง CSV ทั้ง 9 ไฟล์ใน scripts/csv/
 */

const SHEETS_TO_EXPORT = [
  'Teachers',
  'Classes',
  'Students',
  'Subjects',
  'SubjectTeachers',
  'SubjectSchedule',
  'Enrollments',
  'Attendance',
  'TeachingLogs'
];

function exportAllToCSV() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const ssName = ss.getName();
  const stamp = Utilities.formatDate(new Date(), 'Asia/Bangkok', 'yyyyMMdd-HHmm');
  const folderName = `attendance-csv-export-${stamp}`;

  // สร้างโฟลเดอร์ใน Google Drive
  const folder = DriveApp.createFolder(folderName);
  const blobs = [];
  const summary = [];

  SHEETS_TO_EXPORT.forEach(sheetName => {
    const sheet = ss.getSheetByName(sheetName);
    if (!sheet) {
      summary.push(`❌ ${sheetName}: ไม่พบชีท`);
      return;
    }
    const data = sheet.getDataRange().getValues();
    if (data.length === 0) {
      summary.push(`⏭ ${sheetName}: ว่าง (0 rows)`);
      return;
    }

    const csv = toCsv(data);
    const blob = Utilities.newBlob(csv, 'text/csv', `${sheetName}.csv`);
    folder.createFile(blob);
    blobs.push(blob);
    summary.push(`✅ ${sheetName}: ${data.length - 1} rows`);
  });

  // สร้าง zip รวมทุก CSV
  const zip = Utilities.zip(blobs, `${folderName}.zip`);
  const zipFile = folder.createFile(zip);

  // log + alert
  const msg =
    `Export เสร็จ!\n\n` +
    `📁 โฟลเดอร์: ${folderName}\n` +
    `🔗 Zip: ${zipFile.getUrl()}\n\n` +
    `รายละเอียด:\n${summary.join('\n')}\n\n` +
    `ไปดูใน Google Drive → ดาวน์โหลด zip → แตก → วางใน scripts/csv/`;

  Logger.log(msg);

  try {
    SpreadsheetApp.getUi().alert('Export เสร็จ', msg, SpreadsheetApp.getUi().ButtonSet.OK);
  } catch (e) {
    // ถ้ารันจาก editor ตรง ๆ ไม่มี UI → ข้าม
  }
}

/**
 * แปลง 2D array เป็น CSV string (RFC 4180)
 */
function toCsv(rows) {
  return rows.map(row =>
    row.map(cell => {
      if (cell == null) return '';
      let s = String(cell);
      // ถ้ามี comma, quote, หรือ newline → ใส่ double quote ครอบ + escape "
      if (/[",\r\n]/.test(s)) {
        s = `"${s.replace(/"/g, '""')}"`;
      }
      return s;
    }).join(',')
  ).join('\r\n');
}

/**
 * ฟังก์ชันเสริม — แสดง preview ของแต่ละชีท (rows + columns)
 */
function previewSheets() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const lines = [];
  SHEETS_TO_EXPORT.forEach(name => {
    const sh = ss.getSheetByName(name);
    if (!sh) { lines.push(`❌ ${name}: not found`); return; }
    const rows = sh.getLastRow();
    const cols = sh.getLastColumn();
    const headers = sh.getRange(1, 1, 1, cols).getValues()[0].join(', ');
    lines.push(`✅ ${name}: ${rows - 1} rows × ${cols} cols\n   headers: ${headers}`);
  });
  Logger.log(lines.join('\n\n'));
}
