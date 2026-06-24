# 🔍 AlphaPos — Audit & Fix Report
> บันทึกการวิเคราะห์และแก้ไขโปรเจกต์ทั้งหมด  
> วันที่: 20–21 มิถุนายน 2569  
> ผู้ดำเนินการ: AI Code Review + Wittawas Sujimongkol

---

## 📋 สารบัญ
1. [ที่มาของปัญหา](#1-ที่มาของปัญหา)
2. [สถาปัตยกรรมระบบ](#2-สถาปัตยกรรมระบบ)
3. [Sprint 1 — Critical Issues](#3-sprint-1--critical-issues-8-รายการ)
4. [Sprint 2 — High Issues](#4-sprint-2--high-issues-7-รายการ)
5. [Sprint 3 — Medium Issues](#5-sprint-3--medium-issues-4-รายการ)
6. [รอบเพิ่มเติม — New Issues หลัง Refactor](#6-รอบเพิ่มเติม--new-issues-4-รายการ)
7. [Offline/Online Mode](#7-offlineonline-mode)
8. [Push Notifications (APNs)](#8-push-notifications-apns)
9. [รายการที่ต้องทำใน Supabase](#9-รายการที่ต้องทำใน-supabase-dashboard)
10. [ไฟล์ที่ถูกแก้ไขทั้งหมด](#10-ไฟล์ที่ถูกแก้ไขทั้งหมด)

---

## 1. ที่มาของปัญหา

### Error ที่พบครั้งแรกใน Xcode Console

```
SyncEngine [InventoryItem Push Error]: Server returned error:
{"code":"23503","details":"Key is not present in table \"branches\".",
"message":"insert or update on table \"inventory_items\" violates
foreign key constraint \"inventory_items_branch_id_fkey\""}

SyncEngine [TableSession Sync Error]: Server returned error:
{"code":"42P10","message":"there is no unique or exclusion constraint
matching the ON CONFLICT specification"}

SyncEngine [StaffSession Sync Error]: Server returned error:
{"code":"23503","details":"Key is not present in table \"employees\".",
"message":"insert or update on table \"staff_sessions\" violates
foreign key constraint \"staff_sessions_employee_id_fkey\""}
```

### สาเหตุหลักที่พบ

| Error Code | สาเหตุ |
|-----------|--------|
| `23503` (FK violation) | Sync ข้อมูล child ก่อน parent — branches ไม่มีในเซิร์ฟเวอร์ก่อน inventory_items |
| `42P10` (no unique constraint) | `on_conflict` ระบุ column combination ที่ไม่มี unique index ใน Supabase |
| `23503` employees | employee UUID เปลี่ยนทุกครั้งที่ re-seed → sessions/logs ชี้ไป UUID ที่ไม่มีแล้ว |

---

## 2. สถาปัตยกรรมระบบ

```
iPad AlphaPos App
├── SwiftData (Local Store) — ทำงานได้ offline 100%
│   ├── 48 Models ทุกตัวมี: isSynced / isDeleted / updatedAt
│   └── Data stays local → syncs to Supabase เมื่อออนไลน์
├── SyncEngine (Offline-First Sync)
│   ├── SyncEngine.swift             — class definition + helpers
│   ├── SyncEngine+Core.swift        — syncAll(), performSync(), push functions
│   ├── SyncEngine+MasterData.swift  — categories, branches, inventory pull
│   ├── SyncEngine+Menu.swift        — menu items, modifiers, promotions
│   ├── SyncEngine+FloorPlan.swift   — tables, sessions, orders pull
│   ├── SyncEngine+Notifications.swift — lifecycle, push notifications, performSync gate
│   ├── SyncEngine+Helpers.swift     — date/value parsing helpers
│   └── SyncEngine+Realtime.swift    — WebSocket realtime subscription
├── NetworkManager (Supabase REST)
│   ├── NetworkManager.swift          — base class, auth, connectivity
│   ├── NetworkManager+Orders.swift   — uploadOrder, order_items
│   ├── NetworkManager+Inventory.swift
│   ├── NetworkManager+Branches.swift
│   ├── NetworkManager+Staff.swift    — employees, sessions
│   ├── NetworkManager+Menu.swift
│   ├── NetworkManager+Customers.swift
│   ├── NetworkManager+Financials.swift
│   ├── NetworkManager+FloorPlan.swift
│   ├── NetworkManager+Loyalty.swift
│   └── NetworkManager+Printers.swift
└── Supabase (Cloud DB) — PostgreSQL + Realtime
```

### performSync Pipeline (ลำดับสำคัญ — FK ordering)

```
syncMerchant → syncSecurityPolicies → syncRolePermissions → syncMerchantDevices
→ syncEmployees → syncStaffSessions → syncAuditLogs
→ syncTables → syncTableSessions → syncFloorPlanImages → syncEmployeeShifts
→ syncOrders → syncPayments → syncOrderDiscounts → syncTimecards
→ syncCategories → pullCategories          ← ต้องก่อน menuItems
→ syncModifierGroups → pullModifierGroups
→ syncModifiers → pullModifiers
→ syncMenuItemModifierGroups
→ syncBranches → pullBranches              ← ต้องก่อน inventoryItems
→ syncInventoryItems → pullInventoryItems
→ syncInventoryTransactions
→ syncMenuItems → syncPromotions → syncPurchaseOrders
→ syncDeliveryPrices → syncPrinters → syncPrintRoutingRules
→ syncCustomers → syncGiftCards → syncLoyaltyTransactions
→ pullRestaurantTables → pullMenuItems → pullPromotions
→ pullCustomerOrders → pullActiveSessions → syncServiceRequests
→ pullCustomers → pullGiftCards → pullLoyaltyTransactions
```

---

## 3. Sprint 1 — Critical Issues (8 รายการ)

### C1 ✅ `uploadOrder` ไม่มี `on_conflict`
**ปัญหา:** POST orders/order_items ไม่มี `on_conflict=id` → retry สร้าง record ซ้ำ  
**แก้:** เพิ่ม `queryItems: [URLQueryItem(name: "on_conflict", value: "id")]` + lowercase UUID  
**ไฟล์:** `NetworkManager+Orders.swift`

### C2 ✅ `syncCategories` / `syncModifiers` ไม่ถูกเรียกใน pipeline
**ปัญหา:** ไม่มีใน performSync → menu_items FK ชี้ไป category_id ที่ไม่มีในเซิร์ฟเวอร์  
**แก้:** เพิ่ม `await syncCategories`, `await syncModifierGroups`, `await syncModifiers` ก่อน `syncMenuItems`  
**ไฟล์:** `SyncEngine+Notifications.swift`

### C3 ✅ `fetchBranchesFromSupabase` ส่ง `is_deleted=eq.false` ไปยัง branches
**ปัญหา:** ตาราง `branches` ใน Supabase ไม่มีคอลัมน์ `is_deleted` → pull error ทุกครั้ง  
**แก้:** Override `fetchBranchesFromSupabase()` ให้ใช้ custom query ไม่ส่ง `is_deleted` filter  
**ไฟล์:** `NetworkManager+Branches.swift`

### C4 ✅ `Config.plist` อยู่ใน repo (Supabase credentials รั่วไหล)
**ปัญหา:** `*.plist` ใน `.gitignore` แต่ Config.plist อาจถูก commit ไปแล้ว  
**แก้:** เพิ่ม `Config.plist` โดยตรงใน `.gitignore` + ยืนยันไม่มีใน git tracking  
**ไฟล์:** `.gitignore`

### C5 ✅ `processCheckout` ไม่ปิด TableSession หลัง dine-in checkout
**ปัญหา:** โต๊ะยังแสดงสถานะครอบครองในสายตา staff app หลัง checkout  
**แก้:** เพิ่ม `session.isActive = false` + `session.endedAt = Date()` เมื่อ `orderType == "dine_in"`  
**ไฟล์:** `POSViewModel.swift`

### C6 ✅ `PayrollDashboardView` ใช้ `sha256` ตรงๆ สำหรับ PIN
**ปัญหา:** `sha256` ไม่มี salt/iteration → brute-force 4-digit PIN ได้ใน <1 วินาที  
**แก้:** เปลี่ยนเป็น `SecurityHelper.hashPIN(...)` (iterated SHA256 + salt, 600k iterations)  
**ไฟล์:** `PayrollDashboardView.swift`

### C7 ✅ `syncPayments` / `syncTimecards` deleted แต่ไม่ส่งลบไป server
**ปัญหา:** `modelContext.delete(payment)` โดยไม่เรียก `deletePaymentOnServer()` → data inconsistency  
**แก้:** เพิ่ม `deletePaymentOnServer()` + `deleteTimecardOnServer()` ใน NetworkManager และเรียกก่อน delete local  
**ไฟล์:** `NetworkManager.swift`, `SyncEngine+Core.swift`

### C8 ✅ `deductIngredientsLocally` มี N+1 Query — fetch ทุก inventory ใน loop
**ปัญหา:** ทุก recipe ใน loop เรียก `FetchDescriptor<InventoryItem>()` ใหม่ = 50+ full-table scans ต่อ checkout  
**แก้:** Pre-fetch inventory เป็น `[String: InventoryItem]` dictionary ครั้งเดียวก่อน loop ส่งเป็น `branchInventoryCache`  
**ไฟล์:** `POSViewModel.swift`

---

## 4. Sprint 2 — High Issues (7 รายการ)

### H3 ✅ `DeliveryPrice` model ขาด sync metadata
**แก้:** เพิ่ม `isSynced`, `isDeleted`, `updatedAt` ใน `DeliveryPrice.swift`

### H4 ✅ `openRegisterSession` ใช้ `UUID()` random เป็น `openedByUserId`
**ปัญหา:** ถ้าไม่มี user → UUID random → FK error ใน Supabase  
**แก้:** `guard let userId = users.first?.id else { return }` — ไม่ fallback UUID() อีกต่อไป  
**ไฟล์:** `CashDrawerManagementView.swift`

### H5 ✅ N+1 Query ใน `syncStaffSessions` และ `syncAuditLogs`
**ปัญหา:** ทุก record ใน loop ทำ `FetchDescriptor<Employee>(predicate: ...)` = N queries  
**แก้:** Pre-fetch employees เป็น `Dictionary<UUID, Employee>` ครั้งเดียวก่อน loop  
**ไฟล์:** `SyncEngine+Core.swift`

### H8 ✅ `EmployeeTimecardViewModel` seed users ใช้ `UUID()` random
**ปัญหา:** UUID เปลี่ยนทุก re-seed → `staff_sessions`, `audit_logs` ชี้ UUID เก่าที่ไม่มีแล้ว → FK error  
**แก้:** ใช้ Fixed UUIDs เหมือน SampleDataSeeder  
```swift
let seedEmp1Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111101")!
let seedEmp2Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111102")!
let seedUser1Id = UUID(uuidString: "11111111-1111-1111-1111-111111112001")!
let seedUser2Id = UUID(uuidString: "11111111-1111-1111-1111-111111112002")!
```
**ไฟล์:** `EmployeeTimecardViewModel.swift`, `MerchantAuthView.swift`, `POSViewModel.swift`

### H10 ✅ Timer leak ใน KitchenDisplayView + MainDashboardView
**ปัญหา:** `Timer.publish().autoconnect()` ไม่ถูก cancel เมื่อ view หายไป → memory/battery leak  
**แก้:** เปลี่ยนเป็น manual `.connect()` ใน `onAppear` + `.cancel()` ใน `onDisappear`  
**ไฟล์:** `KitchenDisplayView.swift`, `MainDashboardView.swift`

### H11 ✅ `catch` blocks หลายจุดไม่ set `encounteredSyncError = true`
**แก้:** เพิ่มใน syncTimecards, syncMenuItems, syncPurchaseOrders  
**ไฟล์:** `SyncEngine+Core.swift`

### H12 ✅ `ManagerPINVerificationSheet` มี developer mode bypass
**ปัญหา:** `developerModeEnabled && (pin == "1234" || pin == "8888")` bypass manager verification  
**แก้:** ลบ isFallback logic ออกทั้งหมด  
**ไฟล์:** `ManagerPINVerificationSheet.swift`

---

## 5. Sprint 3 — Medium Issues (4 รายการ)

### M1 ✅ `FetchDescriptor` ขาด `fetchLimit` รวม 33+ จุด ใน SyncEngine
**ปัญหา:** fetch ข้อมูลทั้งหมดโดยไม่จำกัด → OOM crash เมื่อข้อมูลมีหลายหมื่นรายการ  
**แก้:** เพิ่ม `descriptor.fetchLimit = 500` ทุก sync descriptor  
**ไฟล์:** `SyncEngine+Core.swift`, `SyncEngine+MasterData.swift`, `SyncEngine+Menu.swift`, `SyncEngine+FloorPlan.swift` และ SyncEngine ทั้งหมด

### M2 ✅ `SalesViewModel.updateAnalytics()` บล็อก main thread
**ปัญหา:** 25+ compute loops (812 บรรทัด) รันบน main thread → UI หยุดชั่วคราว  
**แก้:** ใช้ `Task.detached(priority: .userInitiated)` แล้ว `@MainActor func runAnalytics()`  
**ไฟล์:** `SalesViewModel.swift`

### M3 ✅ `AppSessionManager` ใช้ UserDefaults เป็น auth gate
**ปัญหา:** `UserDefaults.bool(forKey: "is_logged_in")` tamper ได้จาก backup/forensic tool  
**แก้:** auth state มาจาก `MerchantAuthManager.shared.isAuthenticated` (Keychain JWT) เท่านั้น  
**ไฟล์:** `AppSessionManager.swift`, `MerchantAuthManager.swift`

### M8 ✅ `face_embedding` ส่งขึ้น Supabase ทุก sync cycle
**ปัญหา:** Base64 embedding (~100KB) ส่งทุกรอบ sync → bandwidth waste  
**แก้:** ส่งเฉพาะเมื่อ `faceRegisteredAt` อยู่ภายใน 24 ชั่วโมงที่ผ่านมา  
**ไฟล์:** `NetworkManager+Staff.swift`

---

## 6. รอบเพิ่มเติม — New Issues (4 รายการ)

พบหลังจากโปรเจกต์ถูก Refactor จาก monolith → extension files

### N1+N2 ✅ `MerchantAuthView` + `POSViewModel` seed users ยังใช้ `sha256`
**แก้:** เปลี่ยน `SecurityHelper.sha256(...)` → `SecurityHelper.hashPIN(...)` ทุกจุดใน seed  
**ไฟล์:** `MerchantAuthView.swift`, `POSViewModel.swift`

### N3 ✅ Extension files ใหม่ขาด `fetchLimit` รวม 21 จุด
**แก้:** เพิ่ม `fetchLimit = 500` สำหรับ bulk fetch, `fetchLimit = 1` สำหรับ point lookup  
**ไฟล์:** `SyncEngine+Core.swift`, `SyncEngine+MasterData.swift`, `SyncEngine+Menu.swift`, `SyncEngine+FloorPlan.swift`

### N4 ✅ `SettingsView` ยังมี `@AppStorage("is_logged_in")`
**แก้:** ลบ property + `isLoggedIn = false` ทั้งสองจุดออก — auth ใช้ `signOutMerchant()` แล้ว  
**ไฟล์:** `SettingsView.swift`

---

## 7. Offline/Online Mode

### โครงสร้างที่มีอยู่แล้ว (Offline-First)
- ทุก Model มี `isSynced / isDeleted / updatedAt`
- SwiftData เก็บข้อมูลทั้งหมดบนเครื่อง
- `SyncEngine.performSync()` abort ทันทีถ้าไม่มีอินเทอร์เน็ต

### สิ่งที่เพิ่มเติมสำหรับ Explicit Offline Mode

**Setting:** Settings → Security → Toggle `offline_sync_mode`

#### การทำงาน

```
offline_sync_mode = true  →  simulateOffline = true
                          →  performSync() return ทันที (ไม่เรียก network เลย)
                          →  cancelPendingSync() ยกเลิก task + WebSocket + timer
                          →  APNs registration ถูกข้ามไป

offline_sync_mode = false →  simulateOffline = false
                          →  invalidateConnectivityCache()
                          →  sync ปกติทุกอย่าง
```

#### ไฟล์ที่เกี่ยวข้อง

| ไฟล์ | การเปลี่ยนแปลง |
|------|--------------|
| `SyncEngine+Notifications.swift` | อ่าน `offline_sync_mode` → set `simulateOffline` → early return |
| `App.swift` | `#if !DEBUG` guard + `!isOfflineMode` guard สำหรับ APNs |
| `SecuritySettingsView.swift` | Toggle label ชัดเจน + wire `simulateOffline` + `cancelPendingSync()` |
| `SyncEngine.swift` | เพิ่ม `cancelPendingSync()` function |

#### ฟีเจอร์ที่ยังทำงานได้ในโหมดออฟไลน์
- ✅ POS (รับออเดอร์, คิดเงิน, พิมพ์ใบเสร็จ)
- ✅ Kitchen Display System
- ✅ Table Management
- ✅ Inventory (local tracking)
- ✅ Reports (จากข้อมูล local)
- ✅ Staff Login (SwiftData employees)
- ✅ Local notifications (order alerts, staff calls)

#### ฟีเจอร์ที่ **ไม่ทำงาน** ในโหมดออฟไลน์
- ❌ Sync ขึ้น Supabase
- ❌ Realtime (WebSocket)
- ❌ Remote Push Notifications (APNs)
- ❌ Customer web ordering รับ order
- ❌ Cross-device sync

---

## 8. Push Notifications (APNs)

### ปัญหา
```
Cannot create a iOS App Development provisioning profile for "AltifaDev.AlphaPos".
Personal development teams do not support the Push Notifications capability.
```

### สาเหตุ
Personal Team (ฟรี) ไม่รองรับ APNs capability ซึ่งต้องใช้ `aps-environment` entitlement

### แก้ไขชั่วคราว (ใช้งาน DEBUG / Personal Team)
1. เพิ่ม `#if !DEBUG` ครอบ `registerForRemoteNotifications()` ใน `App.swift` ✅ **ทำแล้ว**
2. **ต้องทำใน Xcode เอง:** Signing & Capabilities → ลบ **Push Notifications** capability ออก

### เมื่อสมัคร Apple Developer Program ($99/ปี) แล้ว
1. Xcode → Signing & Capabilities → เพิ่ม **Push Notifications** กลับมา
2. ลบ `#if !DEBUG` ออกจาก `App.swift` (2 บรรทัด)
3. สร้าง APNs Key ใน developer.apple.com → upload ไปยัง Supabase

---

## 9. รายการที่ต้องทำใน Supabase Dashboard

รายการเหล่านี้ต้องทำใน **Supabase Dashboard** (ไม่ใช่โค้ด):

| # | รายการ | SQL Command |
|---|--------|-------------|
| **H2** | สร้าง unique index สำหรับ `uploadInventoryTransaction` composite on_conflict | `CREATE UNIQUE INDEX IF NOT EXISTS idx_inv_txn_conflict ON inventory_transactions(merchant_id, transaction_type, reference_id, item_id) WHERE reference_id IS NOT NULL AND item_id IS NOT NULL;` |
| **M4** | `OrderItem.order` Optional → required | SwiftData migration + Supabase NOT NULL constraint (high-risk, maintenance window) |
| **M5** | `MenuItem.id` String → UUID | Data migration ทั้ง SwiftData + Supabase (very high-risk) |
| **M6** | ตรวจสอบ `merchant_devices.branch_id` nullable | `SELECT is_nullable FROM information_schema.columns WHERE table_name='merchant_devices' AND column_name='branch_id';` |
| **M10** | Customer unique index สำหรับ email/phone | `CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_email ON customers(merchant_id, email) WHERE email IS NOT NULL; CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone ON customers(merchant_id, phone) WHERE phone IS NOT NULL;` |

---

## 10. ไฟล์ที่ถูกแก้ไขทั้งหมด

### Data Layer
| ไฟล์ | การแก้ไข |
|------|---------|
| `Data/Sync/SyncEngine.swift` | เพิ่ม `cancelPendingSync()`, fixed seed UUIDs |
| `Data/Sync/SyncEngine+Core.swift` | fetchLimit, employeeMap pre-fetch, encounteredSyncError |
| `Data/Sync/SyncEngine+Notifications.swift` | performSync offline gate, notification deterministic IDs |
| `Data/Sync/SyncEngine+MasterData.swift` | fetchLimit ทุก bulk fetch |
| `Data/Sync/SyncEngine+Menu.swift` | fetchLimit ทุก bulk fetch |
| `Data/Sync/SyncEngine+FloorPlan.swift` | fetchLimit, idDescriptor scope fix |
| `Data/Remote/NetworkManager.swift` | CryptoKit import, deterministicUUIDString, deletePaymentOnServer, deleteTimecardOnServer |
| `Data/Remote/NetworkManager+Orders.swift` | on_conflict=id, lowercase UUID |
| `Data/Remote/NetworkManager+Branches.swift` | fetchBranches no is_deleted, uploadBranch no is_deleted |
| `Data/Remote/NetworkManager+Staff.swift` | face_embedding conditional (24h), hashPIN |
| `Data/Remote/NetworkManager+Inventory.swift` | on_conflict, fetchLimit |

### Models
| ไฟล์ | การแก้ไข |
|------|---------|
| `Models/DeliveryPrice.swift` | เพิ่ม isSynced, isDeleted, updatedAt |

### Features
| ไฟล์ | การแก้ไข |
|------|---------|
| `Features/POS/ViewModels/POSViewModel.swift` | processCheckout closes session, branchInventoryCache, seed hashPIN, autoSeedIfOutdated #if !DEBUG, lastCheckoutError |
| `Features/POS/Views/CashDrawerManagementView.swift` | openRegisterSession guard no UUID() |
| `Features/Payroll/Views/PayrollDashboardView.swift` | sha256 → hashPIN |
| `Features/Sales/ViewModels/SalesViewModel.swift` | Task.detached updateAnalytics |
| `Features/Timecard/ViewModels/EmployeeTimecardViewModel.swift` | fixed seed UUIDs |
| `Features/Tables/Views/ManagerPINVerificationSheet.swift` | ลบ developer bypass |
| `Features/Kitchen/Views/KitchenDisplayView.swift` | timer manual connect/cancel |
| `Features/Dashboard/Views/MainDashboardView.swift` | timer manual connect/cancel |
| `Features/Auth/Views/MerchantAuthView.swift` | fixed seed UUIDs, sha256 → hashPIN |
| `Features/Settings/Views/SecuritySettingsView.swift` | Offline/Online Toggle + wire simulateOffline |
| `Features/Settings/Views/SettingsView.swift` | ลบ @AppStorage is_logged_in |

### Core & Auth
| ไฟล์ | การแก้ไข |
|------|---------|
| `Core/Auth/AppSessionManager.swift` | auth จาก Keychain เท่านั้น (ลบ UserDefaults gate) |
| `Core/Auth/MerchantAuthManager.swift` | comment NON-SENSITIVE cache |
| `Core/Design/RemoteImageView.swift` | ImageCache (NSCache 50MB) + CachedRemoteImage |

### Root
| ไฟล์ | การแก้ไข |
|------|---------|
| `App.swift` | `#if !DEBUG` guard + offline guard สำหรับ APNs |
| `.gitignore` | เพิ่ม `Config.plist` โดยตรง |

---

## 📊 สรุปสถิติ

| หมวด | จำนวน |
|------|-------|
| Critical issues แก้แล้ว | 8 ✅ |
| High issues แก้แล้ว | 7 ✅ |
| Medium issues แก้แล้ว | 4 ✅ |
| New issues (post-refactor) แก้แล้ว | 4 ✅ |
| **รวมแก้ไขด้วยโค้ด** | **23 ✅** |
| รายการต้องทำใน Supabase | 5 ⏳ |
| ไฟล์ที่แก้ไข | 26 ไฟล์ |
| Extensions เพิ่ม (refactor) | 8 SyncEngine + 11 NetworkManager |

---

## 🔑 Key Concepts ที่ควรเข้าใจ

### 1. Offline-First Architecture
ทุกข้อมูลเขียนลง SwiftData ก่อนเสมอ → sync ขึ้น cloud ทีหลัง  
`isSynced = false` = รอ sync | `isSynced = true` = sync แล้ว

### 2. FK Ordering ใน performSync
**parent ต้อง sync ก่อน child เสมอ:**
```
branches → inventory_items → inventory_transactions
employees → staff_sessions, audit_logs
categories → menu_items
```

### 3. on_conflict = Idempotent Upsert
ทุก POST ต้องมี `on_conflict=id` เพื่อให้ retry ปลอดภัย — ไม่สร้าง duplicate

### 4. Fixed Seed UUIDs
```swift
// ห้ามเปลี่ยน! ใช้กำหนดให้ FK references ใน sessions/logs ยังใช้ได้หลัง re-seed
let seedEmp1Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111101")!
let seedEmp2Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111102")!
let seedUser1Id = UUID(uuidString: "11111111-1111-1111-1111-111111112001")!
let seedUser2Id = UUID(uuidString: "11111111-1111-1111-1111-111111112002")!
```

### 5. Security: hashPIN vs sha256
```swift
// ❌ ไม่ปลอดภัย
SecurityHelper.sha256("1234")     // plain SHA256, brute-force < 1 วินาที

// ✅ ปลอดภัย  
SecurityHelper.hashPIN("1234")    // SHA256 × 600,000 iterations + salt
// format: "iter:600000:<salt_b64>:<hash_hex>"
```

---

*เอกสารนี้สร้างโดย AI Code Review Session — AlphaPos Audit 2026-06-20/21*
