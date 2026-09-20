# AlphaPos Disaster Recovery (DR) & Business Continuity Runbook

## 1. วัตถุประสงค์และเกณฑ์การกู้คืน (Objectives & SLA)

| ตัวชี้วัด | เป้าหมาย (Target) | คำอธิบาย |
| :--- | :--- | :--- |
| **RPO (Recovery Point Objective)** | **<= 5 นาที** | ยอมสูญเสียข้อมูลสูงสุดไม่เกิน 5 นาที (รับประกันด้วย WAL Archiving + Sync Outbox Ledger) |
| **RTO (Recovery Time Objective)** | **<= 15 นาที** | ต้องกู้ระบบและเปิดบริการใหม่ได้ภายใน 15 นาทีหลังจากเกิดอุบัติการณ์ร้ายแรง |
| **Data Integrity Gate** | **100% Zero Leak** | ข้อมูลแต่ละร้านค้าต้องแยกกันเด็ดขาด ห้ามมีการปะปนข้าม Tenant โดยเด็ดขาด |

---

## 2. นโยบายการสำรองข้อมูล (Backup Architecture)

### 2.1 กลยุทธ์ 3-2-1 Backup
1. **3 Copies**: 1 สำเนาบน Live DB, 1 สำเนาบน Local VPS Disk (`/opt/alphapos/backups`), 1 สำเนาส่งออก Offsite S3/Cold Storage ที่เข้ารหัส
2. **2 Media Types**: Binary Custom Dump (`.dump`) สำหรับ Restore เร็ว + Plain JSON ต่อ Tenant (`public.export_merchant_data()`) สำหรับความเข้ากันได้
3. **1 Offsite**: ส่งไฟล์สำรองขึ้น Object Storage แยก Account พร้อมตั้ง Object Lock / Immutability 30 วัน

### 2.2 ตารางการสำรองข้อมูลอัตโนมัติ (Automated Schedule)
- **Snapshot Dump ประจำวัน**: รันทุกวันเวลา 03:00 น. ผ่าน `scripts/backup-production.sh`
- **Verification Dry-Run**: รัน `scripts/verify_backup_restore.sh` ทุกสัปดาห์ เพื่อทดสอบ restore เข้า sandbox จริง ป้องกันปัญหา "สำรองได้แต่กู้ไม่ขึ้น"

---

## 3. ขั้นตอนการกู้คืนระบบเมื่อเกิดภัยพิบัติ (Disaster Recovery Procedures)

### สถานการณ์ที่ 1: ข้อมูลบางร้านค้าเสียหาย หรือต้องการย้อนหลังเฉพาะร้าน (Tenant Rollback)
หากข้อมูลของร้านค้าใดเกิดความผิดพลาดเฉพาะจุด:
```bash
# 1. แตกไฟล์ JSON ของร้านค้านั้น
gunzip -k /opt/alphapos/backups/LATEST/tenants/merchant_<MERCHANT_UUID>.json.gz

# 2. นำเข้าข้อมูลผ่าน API หรือตรวจสอบความแตกต่าง
# (โครงสร้าง JSON เป็นเอกสารมาตรฐาน PDPA/GDPR สอดคล้องกับ schema)
```

### สถานการณ์ที่ 2: เซิร์ฟเวอร์หลักหรือฐานข้อมูลเสียหายทั้งหมด (Full Host Recovery)

#### ขั้นตอนที่ 1: ตรวจสอบความถูกต้องของไฟล์สำรอง (Integrity Check)
```bash
cd /opt/alphapos/backups/<TIMESTAMP>
sha256sum --check CHECKSUMS.sha256
```

#### ขั้นตอนที่ 2: เริ่มต้น Container ฐานข้อมูลใหม่
```bash
cd /opt/alphapos/supabase
docker compose -f docker-compose.vps.yml down -v
docker compose -f docker-compose.vps.yml up -d db
```

#### ขั้นตอนที่ 3: Restore ข้อมูลจาก Custom Dump
```bash
DUMP_FILE=$(ls -1 /opt/alphapos/backups/<TIMESTAMP>/*.dump)
docker exec -i supabase_db_AlphaPos pg_restore -U postgres -d postgres --clean --if-exists < "${DUMP_FILE}"
```

#### ขั้นตอนที่ 4: ตรวจสอบความสมบูรณ์และเปิดรับทราฟฟิก (Sanity & Warm-up)
```bash
# รัน Health Check Telemetry
python3 /opt/alphapos/scripts/monitor_system_health.py

# แจ้งเตือน PostgREST ให้รีโหลด Schema Cache
docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres -c "NOTIFY pgrst, 'reload schema';"
```

#### ขั้นตอนที่ 5: ตรวจสอบ Outbox Queue และ Replay งานที่ค้าง
```bash
# หากมีงานพิมพ์หรือ Push ค้างใน DLQ หลังกู้คืน ให้สั่ง Replay
docker exec -i supabase_db_AlphaPos psql -U postgres -d postgres -c "SELECT public.requeue_sync_outbox_dlq(NULL);"
```

---

## 4. แผนปฏิบัติการทดสอบระบบ (Regular Drills)
- ดำเนินการทดสอบกู้คืนแบบ Dry-Run ทุกวันอาทิตย์ เวลา 04:00 น. ด้วยคำสั่ง:
  ```bash
  ./scripts/verify_backup_restore.sh
  ```
- หากสคริปต์รายงานข้อผิดพลาด จะมีการยิง Alert ไปยัง Webhook ทีม Operations ทันที
