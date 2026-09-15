# AlphaPos — สรุปการวิเคราะห์และแก้ไข (Dashboard / Report / Inventory / Notification)

_เอกสารนี้สรุปการตรวจสอบและแก้ไขทั้งหมดในเซสชันการทำงาน — จัดกลุ่มตามหัวข้อ พร้อมไฟล์ที่แก้ สาเหตุ (root cause) และวิธีทดสอบ_

วันที่: 2026-07-11

---

## ภาพรวมสถาปัตยกรรม

```
┌─────────────────┐   push (upload)    ┌──────────────────────┐
│   SwiftData     │ ─────────────────► │  Supabase VPS Docker │
│  (local store)  │ ◄───────────────── │  (PostgreSQL @       │
│  default.store  │   pull (download)  │   119.59.99.163)     │
└────────┬────────┘                    └──────────────────────┘
         │ @Query (อ่านตรง)
         ▼
   Dashboard & Reports  ◄── คำนวณทุกอย่างจาก SwiftData local (offline-first)
```

- **iPad (AlphaPos):** master device — Dashboard, Reports, POS, Inventory
- **iPhone (AlphaPosStaff):** Quick Order (takeaway/walk-in), ส่งขึ้น Supabase ตรง
- **Web (customer-order-web):** Cloudflare Worker → proxy ไป Supabase
- Report/Dashboard ทั้งหมดอ่านจาก SwiftData local ผ่าน `@Query` — Supabase เป็นชั้น sync/backup

---

## ส่วนที่ 1 — Dashboard & Report: ยอดขายสรุปไม่ถูกต้อง

### 1.1 นิยาม "ยอดขาย" ไม่ตรงกันทุกหน้า (root cause หลัก)
แต่ละหน้ากรอง order คนละเกณฑ์ → ตัวเลขไม่ตรงกัน:

| ส่วน | เกณฑ์เดิม | ปัญหา |
|------|-----------|-------|
| Live Dashboard | `status != "cancelled"` | นับ order ที่ยังไม่จ่ายเงินเป็นยอดขาย → เกินจริง |
| Daily/Tax/Menu/Promotion | `status == "completed"` | ตกหล่น order ขายตรงที่จ่ายแล้วแต่ค้าง `preparing` |
| Monthly Comparison | `status != "cancelled" && !payments.isEmpty` | เกณฑ์ที่ 3 ต่างอีก |

**แก้:** เพิ่มนิยามกลาง `isRecognizedSale` ใน `Models/Order.swift`
```swift
var isRecognizedSale: Bool {
    guard !isDeleted, status != "cancelled" else { return false }
    return payments.contains { !$0.isDeleted } || status == "completed"
}
var recognizedNetTotal: Double { max(0, total - refundedTotal) }  // หักคืนเงิน
```
ให้ทุกหน้าใช้เกณฑ์เดียวกัน (Dashboard + 5 report functions).

### 1.2 บั๊กร้ายแรง — ขายตรงไม่เคยตั้ง completed
`POSViewModel.processCheckout(createPayment:true)` สำหรับ takeaway/delivery สร้าง `Payment` แต่ปล่อย order ค้างที่ `preparing` → report ที่กรอง `completed` ทิ้งข้อมูลนี้ทั้งหมด.
**แก้:** เมื่อ `createPayment && tableSession == nil` → ตั้ง `status = "completed"` + items → `served`.

### 1.3 เครื่องหมาย quantity ไม่สม่ำเสมอ → COGS/Waste ติดลบ
POS ขายบันทึก `-qtyDeducted` (ลบ) แต่ FEFO sell / auto-waste บันทึกเป็นบวก → `InventoryAnalytics` คำนวณ COGS/Waste%/Turnover ออกมาติดลบ.
**แก้:** ใช้ `abs()` ใน analytics (COGS, waste, usage, wasteBreakdown) + normalize ที่ต้นทาง (ดูส่วนที่ 2).

### 1.4 เกณฑ์สต็อกต่ำต่างกัน
Dashboard ใช้ `safetyStockLevel`, Inventory + Report ใช้ `reorderLevel`.
**แก้:** Dashboard เปลี่ยนไปใช้ `reorderLevel` (มาตรฐานเดียวกับทั้งระบบ).

**ไฟล์ที่แก้:** `Models/Order.swift`, `Features/POS/ViewModels/POSViewModel.swift`, `Features/Reports/ViewModels/ReportsViewModel.swift`, `Features/Reports/Views/InventoryAnalyticsReportView.swift`, `Features/Dashboard/Views/LiveDashboardView.swift`

---

## ส่วนที่ 2 — InventoryTransaction: createdAt + เครื่องหมาย quantity

### 2.1 ไม่มี `createdAt` — วันที่ธุรกรรมเพี้ยน
โมเดลมีแค่ `updatedAt` (เปลี่ยนทุกครั้งที่ sync) → report ใช้เป็นวันที่ธุรกรรม → waste เก่าโผล่ผิดช่วงเวลา. Network upload ยังตั้ง `created_at = Date()` (เวลา sync) ทับเวลาจริง.

**แก้ (ครบวงจร):**
- `Models/InventoryTransaction.swift`: เพิ่มฟิลด์ `createdAt` (default `Date()` เพื่อ lightweight migration)
- `NetworkManager+Orders.swift`: ส่ง `createdAt` จริงแทน `Date()`
- `SyncEngine+MasterData.swift`, `+RetryPolicy.swift`: ส่ง `txn.createdAt` ขึ้น backend
- Reports (`ReportsViewModel`, `InventoryAnalyticsReportView`, `SafetyStockManager`, `InventoryView`): กรอง/แสดง/เรียงด้วย `createdAt`

### 2.2 บังคับมาตรฐานเครื่องหมายรวมศูนย์
`InventoryTransaction.init` เรียก `normalizedQuantity()` — บังคับตาม movement type:
- Inbound (receive/refund/transfer_in/opening) → **บวก**
- Outbound (sell/waste/return/transfer_out) → **ลบ**
- adjust → คงเครื่องหมายเดิม (signed delta)

Audit signature สร้าง **หลัง** normalize → ลายเซ็นตรงกับค่าที่เก็บ. เพิ่ม property `magnitude` (= `abs(quantity)`) สำหรับ report. แก้ 2 call site ที่ผิด (FEFO sell, auto-expiry waste).

**ผลพลอยได้สำคัญ:** พบว่าบั๊กเครื่องหมายกระทบ `SafetyStockManager` — avg daily usage / reorder point คำนวณจากค่าติดลบ → แก้ให้ใช้ `abs()`.

### 2.3 Backfill ข้อมูลเก่า (2 ฝั่ง)
- **SwiftData:** `SyncEngine+InventoryTxnBackfill.swift` — one-time idempotent (UserDefaults gate), ซ่อม `createdAt` จาก `order.createdAt` (ผ่าน referenceId) หรือ fallback `updatedAt`, ตั้ง `isSynced=false` เพื่อ push ค่าที่ถูกขึ้น backend. เรียกใน `performSync` ก่อน push transactions.
- **Supabase:** `20260711000300_backfill_inventory_txn_created_at.sql` (+ `035_...`) — backfill จาก `orders.created_at` ผ่าน `reference_id`, fallback `updated_at`, idempotent.
- **Index:** `20260711000200_inventory_txn_event_time.sql` (+ `034_...`) — index บน `(merchant_id, created_at)` และ `(item_id, transaction_type, created_at)`.

---

## ส่วนที่ 3 — SwiftData ↔ Supabase: ความสอดคล้อง

- **InventoryTransaction เป็น push-only** — ไม่มี `pullInventoryTransactions` → การแก้ที่ local init เป็น source of truth ฝั่งเดียว ไม่มีค่าเก่าถูกดึงกลับมาทับ.
- **Sign normalize ก่อน upload** → Supabase ได้ค่าเครื่องหมายถูกต้อง.
- **upsert ปลอดภัย:** conflict target `(merchant_id, transaction_type, reference_id, item_id)` มี UNIQUE constraint รองรับ (migration 019) → re-upload = UPDATE ทับ ไม่ซ้ำ.
- **order sync:** `fetchCompletedOrders` กรอง `completed`; `fetchCustomerOrders` กรอง `in.(preparing,ready,served,completed)` + limit 50. การแก้ให้ขายตรง = completed ทำให้ยอดขายขายตรง sync ข้ามเครื่องได้.

**ลำดับ deploy ที่แนะนำ:** รัน Supabase migrations ก่อน → deploy แอป iPad → backfill local รันอัตโนมัติรอบ sync แรก.

---

## ส่วนที่ 4 — โต๊ะ "QUICK" & Notification Center

### 4.1 โต๊ะ QUICK คืออะไร
ไม่ใช่โต๊ะจริง — hardcoded constant `tableNumber: "QUICK"` ใน `QuickOrderView.swift` (iPhone). Quick Order = พนักงานสั่งจาก iPhone โดยไม่เปิดโต๊ะ (takeaway/walk-in), ส่งขึ้น Supabase ตรง + `markOrderCompleted` ทันทีหลังจ่ายเงิน.

### 4.2 Root cause: iPad ไม่แสดง Quick/Staff order ใน Notification Center
`pullCustomerOrders()` เดิมเรียกแค่ `triggerLocalNotification()` (in-app banner) ไม่เรียก `alertNewCustomerOrder()` ซึ่งเป็นทางเดียวที่ post เข้า `NotificationStore` → Notification Center ว่างเปล่าสำหรับ Quick + Staff iPhone orders.
**แก้:** เพิ่มการเรียก `alertNewCustomerOrder()` ควบคู่ + แยก label ("Quick Order" vs "โต๊ะ X"), guard `age < 300 && !isFirstSync` กันแจ้งย้อนหลัง.

### 4.3 Notification ซ้ำซ้อน (พบระหว่างตรวจสอบ)
Order + service request เข้า `NotificationStore` **2 ทาง** → แสดงซ้ำ 2 entry:
- `.newOrder`: captureFromInApp (banner) + alertNewCustomerOrder (postAlert)
- `.serviceRequest`: captureFromInApp + captureServiceRequests (`$activeRequests`)

`addAlert` ไม่มี dedup. dedup แบบอิง orderNumber ใช้ไม่ได้ (banner title ไม่มีเลข).
**แก้ที่ต้นเหตุ:** `captureFromInApp` skip `.newOrder` + `.serviceRequest` (canonical path จัดการแล้วด้วย label ถูกต้อง + dedup). Banner ยังทำงาน (ขับด้วย `activeNotifications` แยก). อีก 4 ประเภท (cooking/delivery/printer/staleShift) มี path เดียว ไม่ซ้ำ.

### 4.4 ผลตรวจสอบเพิ่มเติม
- **itemCount:** ✅ ถูกต้อง — `fetchCustomerOrders` map `order_items` → `items` + fallback ดึงตรง.
- **Quick order ในรายงาน:** ✅ `markOrderCompleted` → completed + payment → `isRecognizedSale = true` → นับในยอดขาย. "pay later" ไม่นับ (ถูกต้อง).
- **badge/unread count:** ✅ ดีขึ้น — derive จาก `alerts` array; ลด entry ซ้ำ → นับถูกต้อง.
- **deep-link:** ✅ Quick order (`tableNumber = nil`, label ไม่มี "Table N") → `canOpen = false` → ไม่ navigate (ถูกต้อง ไม่มีโต๊ะ).

**ไฟล์ที่แก้:** `Core/Notifications/NotificationStore.swift`, `Data/Sync/SyncEngine+FloorPlan.swift`, `Data/Sync/SyncEngine+AlertTriggers.swift`

---

## รายการไฟล์ที่แก้ทั้งหมด

### Swift — Models & Logic
- `Models/Order.swift` — `isRecognizedSale`, `recognizedNetTotal`, `refundedTotal`
- `Models/InventoryTransaction.swift` — `createdAt`, `normalizedQuantity()`, `magnitude`
- `Features/POS/ViewModels/POSViewModel.swift` — ขายตรงตั้ง completed
- `Features/Reports/ViewModels/ReportsViewModel.swift` — ใช้ `isRecognizedSale` + `createdAt`
- `Features/Reports/Views/InventoryAnalyticsReportView.swift` — `abs()` + `createdAt`
- `Features/Inventory/ViewModels/SafetyStockManager.swift` — `abs()` + `createdAt`
- `Features/Inventory/ViewModels/InventoryViewModel+Expiry.swift` — FEFO sell เครื่องหมายลบ
- `Features/Inventory/ViewModels/InventoryExpiryManager.swift` — auto-waste เครื่องหมายลบ
- `Features/Inventory/Views/InventoryView.swift` — เรียง/แสดงด้วย `createdAt`
- `Features/Dashboard/Views/LiveDashboardView.swift` — `isRecognizedSale` + `reorderLevel`

### Swift — Sync & Notification
- `Data/Remote/NetworkManager+Orders.swift` — upload `createdAt` จริง
- `Data/Sync/SyncEngine+MasterData.swift`, `+RetryPolicy.swift` — ส่ง `createdAt`
- `Data/Sync/SyncEngine+InventoryTxnBackfill.swift` — **ไฟล์ใหม่** backfill
- `Data/Sync/SyncEngine+Notifications.swift` — wire backfill
- `Data/Sync/SyncEngine+FloorPlan.swift` — `alertNewCustomerOrder`
- `Data/Sync/SyncEngine+AlertTriggers.swift` — แยก label Quick
- `Core/Notifications/NotificationStore.swift` — skip newOrder/serviceRequest กัน dedup

### SQL Migrations
- `supabase/migrations/20260711000200_inventory_txn_event_time.sql` (+ `Database/migrations/034_...`)
- `supabase/migrations/20260711000300_backfill_inventory_txn_created_at.sql` (+ `Database/migrations/035_...`)

---

## การทดสอบ

⚠️ Swift compiler ไม่พร้อมใช้งานในสภาพแวดล้อมที่วิเคราะห์ — ยืนยันได้เพียง static check (วงเล็บสมดุลครบทุกไฟล์).

**ต้องรันบนเครื่องที่มี Xcode:**
1. `./run_tests.sh` — unit tests (โดยเฉพาะ InventoryTests, OrderSettlementTests, InventoryAdvancedTests)
2. Build ทั้ง 2 target: AlphaPos (iPad) + AlphaPosStaff (iPhone)
3. รัน Supabase migrations ที่ VPS **ก่อน** deploy แอป
4. ตรวจ manual: Dashboard = Daily Sales report วันเดียวกัน, waste report วันที่ถูกต้อง, Notification Center ไม่มี entry ซ้ำ, Quick order แสดงใน Notification Center + นับในยอดขาย
