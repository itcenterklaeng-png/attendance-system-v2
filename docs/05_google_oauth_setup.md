# Phase 5 — Google OAuth Setup

## ขั้นที่ 1 — Google Cloud Console (ตั้ง OAuth Client)

### 1.1 สร้าง Project
1. ไป https://console.cloud.google.com/
2. คลิกชื่อ project ด้านบน → **New Project**
3. ชื่อ: `Attendance System` → Create
4. รอ ~30 วินาที แล้วเลือก project ที่สร้างใหม่

### 1.2 เปิด APIs
1. ทางซ้าย → **APIs & Services** → **OAuth consent screen**
2. เลือก **External** → Create
3. กรอก:
   - App name: `วิทยาลัยการอาชีพแกลง - ระบบเช็คชื่อ`
   - User support email: `kroobank100@gmail.com`
   - Developer contact: `kroobank100@gmail.com`
4. Save and Continue → Save and Continue → Save and Continue → Back to Dashboard

### 1.3 สร้าง OAuth Client ID
1. ทางซ้าย → **Credentials** → **Create Credentials** → **OAuth client ID**
2. Application type: **Web application**
3. Name: `Supabase Auth`
4. **Authorized JavaScript origins:** (เว้นว่างได้)
5. **Authorized redirect URIs:** ⭐ สำคัญ
   - ก่อนกรอก ไปดู URL ที่ Supabase ก่อน (ขั้นที่ 2.1)

ทำขั้นที่ 2 ก่อน แล้วกลับมาใส่ URL ตรงนี้

---

## ขั้นที่ 2 — Supabase (เปิด Google Provider)

### 2.1 หา Callback URL
1. ไป Supabase Dashboard → project ของคุณ
2. ทางซ้าย → **Authentication** → **Providers**
3. หา **Google** → คลิกเปิด
4. **Copy URL "Callback URL (for OAuth)"** — รูปแบบ:
   `https://xxxxx.supabase.co/auth/v1/callback`

### 2.2 กลับไป Google Cloud
1. กลับไปหน้า Credentials → OAuth Client ที่สร้าง
2. **Authorized redirect URIs** → Add URI → paste Callback URL ที่ copy มา
3. Save
4. หน้านี้จะแสดง **Client ID** และ **Client Secret** — copy ทั้งคู่

### 2.3 ใส่ที่ Supabase
1. กลับ Supabase → Google provider
2. **Google Client ID:** paste
3. **Google Client Secret:** paste
4. (Optional) **Authorized Client IDs:** เว้นว่าง
5. Toggle **Enable Sign in with Google** → ON
6. Save

---

## ขั้นที่ 3 — ทดสอบ Login

### 3.1 หน้าทดสอบ
สร้างไฟล์ `test-login.html` ในเครื่องคุณ:

```html
<!DOCTYPE html>
<html>
<head><title>Test Login</title></head>
<body>
  <h1>Test Supabase Google Login</h1>
  <button id="login">Login with Google</button>
  <button id="logout">Logout</button>
  <pre id="user"></pre>

  <script type="module">
    import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

    // ⭐ แทนที่ด้วยค่าของ project คุณ
    const SUPABASE_URL = 'https://xxxxx.supabase.co';
    const SUPABASE_ANON_KEY = 'eyJ...';   // anon public key

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

    document.getElementById('login').onclick = async () => {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: window.location.href }
      });
      if (error) alert(error.message);
    };

    document.getElementById('logout').onclick = async () => {
      await supabase.auth.signOut();
      location.reload();
    };

    const { data } = await supabase.auth.getUser();
    document.getElementById('user').textContent = JSON.stringify(data, null, 2);
  </script>
</body>
</html>
```

### 3.2 หา anon key
1. Supabase → Settings → **API**
2. Copy **Project URL** → ใส่ `SUPABASE_URL`
3. Copy **anon public key** → ใส่ `SUPABASE_ANON_KEY`

### 3.3 รัน
- เปิด `test-login.html` ใน browser (ดับเบิลคลิกได้เลย)
- กด **Login with Google** → เลือกบัญชี
- กลับมาที่หน้า เห็น JSON มี user info → ✅ เสร็จ

---

## ขั้นที่ 4 — ตั้ง Admin คนแรก

หลังจาก login Google ครั้งแรก จะมี row ใหม่ใน `public.users` แต่ `status='inactive'`

ไป Supabase → SQL Editor:

```sql
-- ดูว่ามี user ใหม่หรือยัง
SELECT id, email, role, status FROM users;

-- ตั้ง kroobank100@gmail.com เป็น admin + active
UPDATE users
SET role = 'admin',
    status = 'active',
    full_name = 'ว่าที่ร้อยตรีพงศกร พงษ์พันนา'
WHERE email = 'kroobank100@gmail.com';
```

---

## ตรวจสอบ

หลังตั้ง admin แล้ว ทดสอบใน SQL Editor:

```sql
-- ควรคืน 'admin'
SELECT app_current_role();
```

ถ้าได้ 'admin' → ✅ พร้อมไป Phase 3 (API routes)

---

## จำกัด domain (Optional)

ถ้าอยากให้เฉพาะอีเมล `@vec.ac.th` (ของโรงเรียน) login ได้:

Google Cloud → OAuth consent screen → **Make External → Internal** (ถ้ามี Google Workspace)

หรือใน trigger `trg_handle_new_auth_user()` ตรวจ domain:

```sql
IF NEW.email NOT LIKE '%@vec.ac.th' AND NEW.email NOT IN ('kroobank100@gmail.com') THEN
  RAISE EXCEPTION 'อนุญาตเฉพาะอีเมลของวิทยาลัยเท่านั้น';
END IF;
```
