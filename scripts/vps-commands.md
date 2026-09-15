# VPS Commands — Deploy Push Notifications
# รันทีละ block บน VPS (ssh root@119.59.99.163)

## ─── STEP 1: ตรวจสอบ Docker containers ───────────────────────────────────────

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

ดู container ที่มีชื่อว่า edge, functions, postgres, supabase

---

## ─── STEP 2: หา service_role_key ────────────────────────────────────────────

```bash
# ลองหาจาก .env files ที่พบบ่อย
grep -r "SERVICE_ROLE_KEY\|service_role" /opt/supabase/.env 2>/dev/null || \
grep -r "SERVICE_ROLE_KEY\|service_role" /root/supabase/.env 2>/dev/null || \
grep -r "SERVICE_ROLE_KEY\|service_role" /home/supabase/.env 2>/dev/null || \
find / -name ".env" -path "*/supabase/*" 2>/dev/null | xargs grep "SERVICE_ROLE_KEY" 2>/dev/null | head -5
```

---

## ─── STEP 3: Upload Edge Function ───────────────────────────────────────────

```bash
# สร้าง folder
mkdir -p /opt/supabase/functions/send-staff-push

# สร้าง index.ts (copy เนื้อหาจากไฟล์ supabase/functions/send-staff-push/index.ts)
cat > /opt/supabase/functions/send-staff-push/index.ts << 'FUNCEOF'
[วาง content ของ index.ts ที่นี่]
FUNCEOF
```

หรือ upload ผ่าน scp จาก Mac:
```bash
# รันบน Mac (ไม่ใช่ VPS)
scp /Users/mac/Documents/AlphaPos/supabase/functions/send-staff-push/index.ts \
    root@119.59.99.163:/opt/supabase/functions/send-staff-push/index.ts
```

---

## ─── STEP 4: ตั้งค่า APNs Secrets ──────────────────────────────────────────

แทน YOUR_KEY_ID ด้วย Key ID จาก developer.apple.com
แทน YOUR_P8_CONTENT ด้วย content ใน .p8 file

```bash
# หา .env file ของ Supabase
ls /opt/supabase/
ls /root/supabase/ 2>/dev/null || true

# เพิ่ม secrets เข้าไปใน .env หลัก
# (เปลี่ยน path ให้ตรงกับ .env จริงของคุณ)

ENV_FILE="/opt/supabase/.env"  # แก้ path ให้ถูก

# เพิ่ม APNs secrets
cat >> "$ENV_FILE" << 'SECRETEOF'

# ── APNs Push Notification Secrets ──
APNS_KEY_ID=YOUR_KEY_ID_HERE
APNS_TEAM_ID=SNU4S3B885
APNS_ENVIRONMENT=sandbox
APNS_STAFF_BUNDLE_ID=AltifaDev.AlphaPosStaff
APNS_POS_BUNDLE_ID=AltifaDev.AlphaPos
SECRETEOF

# เพิ่ม private key (แทน YOUR_P8_CONTENT ด้วยบรรทัดใน .p8 รวมกันด้วย \n)
# วิธีง่ายที่สุด: upload .p8 ไปก่อนแล้วแปลง
```

**วิธีแปลง .p8 เป็น single line (รันบน Mac):**
```bash
python3 -c "
content = open('$HOME/Downloads/AuthKey_YOURKEYID.p8').read().strip()
escaped = content.replace('\n', '\\\\n')
print(f'APNS_PRIVATE_KEY={escaped}')
"
```
แล้ว copy output ไป append ใน `.env` บน VPS

---

## ─── STEP 5: Run Database Migration ─────────────────────────────────────────

```bash
# หา Postgres container name
PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "postgres|supabase-db|db" | head -1)
echo "Postgres container: $PG_CONTAINER"

# Upload migration file จาก Mac ก่อน:
# scp /Users/mac/Documents/AlphaPos/supabase/migrations/20260711000400_staff_push_triggers.sql \
#     root@119.59.99.163:/tmp/staff_push_triggers.sql

# Run migration
docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres < /tmp/staff_push_triggers.sql
```

ถ้าต้องการ password postgres:
```bash
docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres -W < /tmp/staff_push_triggers.sql
```

---

## ─── STEP 6: Set SUPABASE_URL ใน app.settings ─────────────────────────────

Migration ใช้ `current_setting('app.settings.supabase_url')` — ต้องตั้งค่านี้:

```bash
PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "postgres|supabase-db|db" | head -1)

docker exec "$PG_CONTAINER" psql -U postgres -d postgres -c "
ALTER DATABASE postgres SET app.settings.supabase_url = 'https://api.alphaposweb.com';
"
```

หา service_role_key แล้วตั้งด้วย:
```bash
docker exec "$PG_CONTAINER" psql -U postgres -d postgres -c "
ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_SERVICE_ROLE_KEY';
"
```

---

## ─── STEP 7: Restart Edge Runtime Container ─────────────────────────────────

```bash
# หา edge runtime container
EDGE_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "edge|functions" | head -1)
echo "Edge container: $EDGE_CONTAINER"

docker restart "$EDGE_CONTAINER"
echo "Restarted: $EDGE_CONTAINER"
```

---

## ─── STEP 8: Test Push Function ─────────────────────────────────────────────

```bash
# แทน YOUR_SERVICE_ROLE_KEY ด้วย key จริง
curl -X POST https://api.alphaposweb.com/functions/v1/send-staff-push \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "apikey: YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "new_order",
    "merchant_id": "163350b0-056d-4d5e-b5d4-24e7aac5ab6d",
    "order_number": "TEST-001",
    "table_number": "1"
  }'
```

Response ที่ถูกต้องควรเป็น:
```json
{"delivered": 1, "total": 1, "badge_count": 0}
```

ถ้า `delivered: 0` แสดงว่า app ยังไม่ได้ register device token (ต้องรัน app บน device จริงก่อน)
ถ้า error เรื่อง APNs credentials → ตรวจ APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY

---

## ─── STEP 9: ตรวจสอบ Migration สำเร็จ ──────────────────────────────────────

```bash
PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "postgres|supabase-db|db" | head -1)

docker exec "$PG_CONTAINER" psql -U postgres -d postgres -c "
SELECT trigger_name, event_object_table, event_manipulation 
FROM information_schema.triggers 
WHERE trigger_name LIKE 'trg_push_%'
ORDER BY event_object_table, trigger_name;
"
```

ควรเห็น 5 triggers:
```
trg_push_new_order        | orders              | INSERT
trg_push_order_status     | orders              | UPDATE
trg_push_web_order        | orders              | INSERT
trg_push_service_request  | service_requests    | INSERT
trg_push_table_status     | restaurant_tables   | UPDATE
```
