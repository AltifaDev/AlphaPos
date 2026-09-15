# AlphaPos — Deploy Checklist (Dashboard/Report/Inventory/Notification fixes)

_ทำตามลำดับนี้เป๊ะ ๆ — migrations ต้องรัน **ก่อน** deploy แอป_
วันที่จัดทำ: 2026-07-11

---

## ⚠️ หลักการสำคัญ
0. **Production ห้ามใช้ `supabase stop`, `supabase db reset` และ `supabase stop --no-backup`** — ใช้ restart เฉพาะ service เท่านั้น
1. **รัน Supabase migrations ที่ VPS ก่อน** เสมอ — แอปเวอร์ชันใหม่ส่ง `createdAt` ขึ้น backend และ report คาดหวัง index
2. Migration ทั้งหมด **idempotent** — รันซ้ำได้ปลอดภัย (ตรวจแล้ว: `IF NOT EXISTS` + conditional `WHERE`)
3. Backfill ฝั่ง SwiftData รัน**อัตโนมัติ**รอบ sync แรกหลัง deploy (one-time, UserDefaults gate)

---

## ขั้นที่ 1 — Backup
```bash
# สำรอง Supabase DB ที่ VPS (119.59.99.163) ก่อนแตะอะไร
ssh <user>@119.59.99.163
pg_dump -U postgres -d alphapos -F c -f ~/alphapos_backup_$(date +%Y%m%d_%H%M).dump
```

## ขั้นที่ 2 — รัน Supabase Migrations (ตามลำดับ)
```bash
# ผ่าน supabase CLI (แนะนำ) — จะรันเฉพาะ migration ที่ยังไม่เคยรัน
cd /Users/mac/Documents/AlphaPos
supabase db push

# หรือรันตรงด้วย psql ตามลำดับ timestamp:
#   20260711000200_inventory_txn_event_time.sql        (index + column, idempotent)
#   20260711000300_backfill_inventory_txn_created_at.sql (backfill created_at, idempotent)
```
**ยืนยันหลังรัน:**
```sql
-- index ถูกสร้าง
SELECT indexname FROM pg_indexes
 WHERE tablename='inventory_transactions'
   AND indexname LIKE 'idx_inventory_transactions_%created%';
-- ควรเห็น: idx_inventory_transactions_merchant_created, idx_inventory_transactions_item_type_created

-- backfill ได้ผล: ไม่ควรมี created_at โผล่หลัง updated_at เกิน 5 วินาที
SELECT COUNT(*) FROM inventory_transactions
 WHERE created_at > updated_at + INTERVAL '5 seconds';
-- ควรได้ 0 (หรือใกล้ 0)
```

## ขั้นที่ 3 — Unit Tests (เครื่องที่มี Xcode)
```bash
cd /Users/mac/Documents/AlphaPos
./run_tests.sh
# ต้องได้ exit code 0 — All tests passed ✅
# สนใจเป็นพิเศษ: InventoryAdvancedTests (§4 MovementType sign, §7 Analytics),
#               OrderSettlementTests, InventoryTests
```

## ขั้นที่ 4 — Build ทั้ง 2 Target
```bash
# iPad target
xcodebuild -scheme AlphaPos -destination 'generic/platform=iOS' build

# iPhone target (แยก module — ไม่ใช้ InventoryTransaction/isRecognizedSale)
xcodebuild -scheme AlphaPosStaff -destination 'generic/platform=iOS' build
```
> หมายเหตุ: AlphaPosStaff ยืนยันแล้วว่า**ไม่อ้างอิง** โมเดลที่แก้ → ความเสี่ยง build iPhone ต่ำ

## ขั้นที่ 5 — Smoke Test บนอุปกรณ์จริง
- [ ] เปิดแอป iPad → รอ sync รอบแรก → ตรวจ log `InventoryTxn createdAt backfill: repaired N/M rows`
- [ ] **Dashboard = Daily Sales report** ยอดวันเดียวกันตรงกัน
- [ ] ขายตรง (takeaway) จ่ายเงิน → โผล่ในยอดขาย Dashboard + report ทันที
- [ ] Waste report → วันที่ถูกต้อง (ไม่กระจุกวันเดียว)
- [ ] COGS / Waste% / Turnover เป็นค่า**บวก** (ไม่ติดลบ)
- [ ] สต็อกต่ำ: Dashboard banner = Inventory list = Inventory report (ใช้ reorderLevel เท่ากัน)
- [ ] Quick order จาก iPhone → โผล่ใน Notification Center iPad (label "Quick Order", device "Staff iPhone")
- [ ] Table order → โผล่ครั้งเดียว (ไม่ซ้ำ 2 entry) + tap navigate ไปโต๊ะได้
- [ ] Quick order notification → tap แล้วไม่ navigate (ไม่มีโต๊ะ) — ถูกต้อง
- [ ] Badge/unread count ตรงกับจำนวน alert จริง

## ขั้นที่ 6 — ตรวจ Multi-device
- [ ] Quick order (completed) จาก iPhone → pull ขึ้น iPad → นับในยอดขาย
- [ ] เปิด 2 iPad → ยอดขาย + สต็อกตรงกันหลัง sync

---

## VPS — Supabase Auth (production)

Do not run `supabase start/stop` as a production deployment step. Configure and
verify Auth without cycling the PostgreSQL stack:

```bash
./scripts/deploy-vps-auth-production.sh   # from Mac
# or on VPS:
./scripts/fix-vps-auth-urls.sh apply && ./scripts/fix-vps-auth-urls.sh verify
```

See [Docs/VPS_AUTH_PRODUCTION.md](Docs/VPS_AUTH_PRODUCTION.md).

---

## Rollback plan
- **แอป:** ติดตั้ง build เดิมกลับ — SwiftData store เดิมใช้ได้ (เพิ่ม field `createdAt` เป็น additive, lightweight migration ถอยได้)
- **DB:** migration เป็น additive (เพิ่ม index/column, backfill) — ไม่มี drop → ไม่ต้อง rollback DB โดยทั่วไป; ถ้าจำเป็นใช้ `pg_restore` จาก backup ขั้นที่ 1
- **Backfill flag:** ถ้าต้องรัน backfill ใหม่ ลบ key `did_backfill_inventory_txn_created_at_v1` ใน UserDefaults

---

## หมายเหตุความเสี่ยงที่ตรวจแล้ว (static)
- ✅ ทุก `InventoryTransaction(...)` call site (22 จุด) ใช้ named params + `createdAt` มี default → ไม่มี call เดิมพัง
- ✅ Seed waste 3 จุด (POSViewModel ~2058) เพิ่ม `createdAt` ตรงกับ `updatedAt` แล้ว (กัน regression วันที่)
- ✅ AlphaPosStaff ไม่อ้างอิงโมเดลที่แก้ → build iPhone ไม่กระทบ
- ✅ Unit tests ใช้ mock/pure types → ไม่กระทบจากการเปลี่ยนเครื่องหมาย/createdAt
- ✅ Migration idempotent + ลำดับถูกต้อง (000200 → 000300 → 000400 ไม่ชนกัน)
- ⚠️ ยืนยัน type-check เต็มรูปแบบไม่ได้ (ไม่มี Swift compiler ในสภาพแวดล้อมวิเคราะห์) — ต้อง build จริงที่ขั้นที่ 3-4
