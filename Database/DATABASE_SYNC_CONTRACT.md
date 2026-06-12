# 📋 DATABASE SYNC CONTRACT
## AlphaPos: SwiftData (iPad) ↔ Supabase Schema Agreement

> **อ่านเอกสารนี้ทุกครั้งก่อนเพิ่ม SwiftData Model ใหม่หรือแก้ไข Model เดิม**

---

## 🔴 กฎเหล็ก (MUST FOLLOW)

1. **ทุก SwiftData `@Model` ต้องมีตารางใน Supabase ก่อนจะ sync ได้**
2. **ทุกตารางใน Supabase ต้องมี `merchant_id UUID NOT NULL` เสมอ** (Multi-tenant isolation)
3. **ทุกตารางต้องมี RLS Policy ที่ใช้ `get_active_merchant_id()` เสมอ**
4. **เมื่อเพิ่มคอลัมน์ใน SwiftData ต้องรัน Migration SQL ใน `Database/migrations/` ด้วย**
5. **ทุก Migration ต้องเป็น Idempotent** — ใช้ `CREATE TABLE IF NOT EXISTS` และ `ADD COLUMN IF NOT EXISTS`

---

## 📦 ตารางทั้งหมด (ณ 2026-06-09)

| Supabase Table | SwiftData Model | มี Sync? | Migration | สถานะ |
|---|---|---|---|---|
| merchants | (UserDefaults) | ✅ syncMerchant | 001 | ✅ |
| merchant_users | (auth.users) | - | 001 | ✅ |
| branches | Branch | ❌ No sync | 001 | ✅ |
| categories | Category | ❌ No sync | (existed) | ✅ |
| restaurant_tables | RestaurantTable | ✅ syncTables | 001 | ✅ |
| menu_items | MenuItem | ✅ syncMenuItems | 001 | ✅ |
| menu_item_modifier_groups | MenuItemModifierGroup | ❌ No sync | (existed) | ✅ |
| modifier_groups | ModifierGroup | ❌ No sync | (existed) | ✅ |
| modifiers | Modifier | ❌ No sync | (existed) | ✅ |
| table_sessions | TableSession | ✅ syncTableSessions | 001 | ✅ |
| orders | Order | ✅ syncOrders | 001 + 002 | ✅ |
| order_items | OrderItem | ✅ (via pull) | 001 + 002 | ✅ |
| order_item_modifiers | OrderItemModifier | ❌ No sync | (existed) | ✅ |
| payments | Payment | ✅ syncPayments | 001 + 002 | ✅ |
| service_requests | (web-only) | ✅ syncServiceRequests | 001 | ✅ |
| employees | Employee | ✅ syncEmployees | 001 + 002 + 008 | ✅ |
| employee_shifts | EmployeeShift | ✅ syncEmployeeShifts | (existed) + 008 | ✅ |
| timecards | Timecard | ✅ syncTimecards | 001 + 002 | ✅ |
| promotions | Promotion | ✅ syncPromotions | (prev session) | ✅ |
| inventory_items | InventoryItem | ❌ No sync | (existed) + 002 | ✅ |
| inventory_transactions | InventoryTransaction | ✅ syncInventoryTransactions | 001 + 002 | ✅ |
| recipes | Recipe | ❌ No sync | (existed) | ✅ |
| suppliers | Supplier | ❌ No sync | (existed) | ✅ |
| roles | Role | ❌ No sync | (existed) | ✅ |
| users | User | ❌ No sync | (existed) | ✅ |
| register_sessions | RegisterSession | ❌ No sync | (existed) | ✅ |
| **purchase_orders** | **PurchaseOrder** | **✅ syncPurchaseOrders** | **003** | **✅ Done** |
| **purchase_order_items** | **PurchaseOrderItem** | **✅ (via syncPurchaseOrders)** | **003** | **✅ Done** |
| **delivery_prices** | **DeliveryPrice** | **✅ syncDeliveryPrices** | **003** | **✅ Done** |
| payroll_periods | (N/A) | - | (Supabase only) | ✅ |
| payroll_slips | (N/A) | - | (Supabase only) | ✅ |
| user_sessions | (N/A) | - | (Supabase only) | ✅ |

---

## 📐 Column Mapping Rules (Swift → PostgreSQL)

| Swift Type | PostgreSQL Type |
|---|---|
| `UUID` | `UUID` |
| `String` | `VARCHAR(N)` or `TEXT` |
| `Int` | `INTEGER` |
| `Double` | `DECIMAL(10,2)` |
| `Bool` | `BOOLEAN` |
| `Date` | `TIMESTAMP WITH TIME ZONE` |
| `Data` | `TEXT` (base64) หรือ Supabase Storage URL |
| `Optional<T>` | Column nullable (`NULL` allowed) |
| `@Relationship` | FK column `_id UUID` |

**camelCase → snake_case:** `orderType` → `order_type`, `isSynced` → `is_synced`

---

## 🆕 ขั้นตอนเพิ่ม Model ใหม่ (Checklist)

เมื่อต้องการเพิ่ม SwiftData Model ใหม่ ให้ทำตามขั้นตอนนี้ทุกครั้ง:

```
[ ] 1. สร้าง Swift file ใน AlphaPos/Models/<ModelName>.swift
[ ] 2. เพิ่ม merchant_id: UUID ใน SwiftData model (สำหรับ sync)
[ ] 3. เพิ่ม isSynced: Bool, isDeleted: Bool, updatedAt: Date (sync metadata)
[ ] 4. สร้าง SQL migration file ใน Database/migrations/<next_number>_<description>.sql
[ ] 5. Migration SQL ต้องมี:
       - CREATE TABLE IF NOT EXISTS public.<table_name>
       - merchant_id UUID NOT NULL + FOREIGN KEY
       - ALTER TABLE ENABLE ROW LEVEL SECURITY
       - CREATE POLICY ... USING (merchant_id = get_active_merchant_id())
       - CREATE INDEX ... ON <table> (merchant_id)
[ ] 6. Apply migration ใน Supabase Dashboard หรือผ่าน MCP tool execute_sql
[ ] 7. เพิ่มฟังก์ชัน sync<ModelName>() ใน SyncEngine.swift
[ ] 8. เพิ่ม uploadModelName() ใน NetworkManager.swift
[ ] 9. อัพเดตตารางนี้ใน DATABASE_SYNC_CONTRACT.md
```

---

## ⚡ ขั้นตอนเพิ่มคอลัมน์ใหม่ใน Model ที่มีอยู่

```
[ ] 1. เพิ่ม property ใน Swift @Model class
[ ] 2. สร้าง migration file ใหม่ใน Database/migrations/
[ ] 3. ใช้: ALTER TABLE public.<table> ADD COLUMN IF NOT EXISTS <col> <type>;
[ ] 4. Apply ใน Supabase
[ ] 5. อัพเดต payload ใน NetworkManager.swift (ส่ง field ใหม่ขึ้น cloud)
[ ] 6. ทดสอบ sync ใน iPad Simulator
```

---

## 🔒 Security Template (ใช้สำหรับทุกตารางใหม่)

```sql
-- 1. Enable RLS
ALTER TABLE public.<table_name> ENABLE ROW LEVEL SECURITY;

-- 2. Policy สำหรับ iPad POS (anon role + merchant JWT)
CREATE POLICY "merchant_isolation_<table_name>" ON public.<table_name>
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

-- 3. Index บังคับ
CREATE INDEX IF NOT EXISTS idx_<table_name>_merchant ON public.<table_name> (merchant_id);
```

---

## 🔍 คำสั่ง Audit (รันเพื่อตรวจสอบ drift)

```sql
-- ตรวจสอบตารางทั้งหมดที่ไม่มี merchant_id (อันตราย!)
SELECT table_name 
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_name = t.table_name 
      AND c.table_schema = 'public'
      AND c.column_name = 'merchant_id'
  )
ORDER BY table_name;

-- ตรวจสอบตารางที่ไม่มี RLS enabled
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND rowsecurity = false;
```

---

## 📁 Migration Files

| ไฟล์ | วันที่สร้าง | เนื้อหา | สถานะ |
|---|---|---|---|
| `001_initial_schema.sql` | 2026-06-09 | Schema เริ่มต้นของระบบ | ✅ Applied |
| `002_extended_columns.sql` | 2026-06-09 | คอลัมน์ที่ขาดหายใน 7 ตาราง | ✅ Applied |
| `003_missing_tables.sql` | 2026-06-09 | purchase_orders, purchase_order_items, delivery_prices | ✅ Applied |
| `008_employee_face_embedding.sql` | 2026-06-12 | face_embedding, employee_shifts sync cols, RLS | ✅ Applied |

---

*อัพเดตล่าสุด: 2026-06-09 | Project: sdmtkixrqkmwcpwoisrg*
