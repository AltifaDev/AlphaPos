# AlphaPos iPad — Functional Completeness Audit

วันที่ตรวจ: 2 กรกฎาคม 2026 (ICT)  
ขอบเขต: แอป `AlphaPos` ฝั่ง iPad, SwiftData, SyncEngine, Supabase contract และอุปกรณ์ POS  
วิธีตรวจ: อ่าน navigation และ source code ทุกโมดูลหลัก, trace เส้นทางขาย/ชำระ/คืนเงิน/สต็อก/กะ/สิทธิ์/ซิงค์, ค้นหา mock-stub-no-op และรัน build/tests ที่มีใน repository

## 1. ข้อสรุปผู้บริหาร

**คำตอบคือ: ยังไม่สมบูรณ์ 100% และยังไม่ควรประกาศว่า production-ready สำหรับร้านจริงที่รับบัตร/QR หรือหลายอุปกรณ์**

ตัวโปรแกรมมีขอบเขตเมนูที่กว้างและหลายส่วนทำงานจริงใน local/offline ได้ แต่มีความต่างมากระหว่าง “มีหน้าจอ” กับ “ทำธุรกรรมจริงครบวงจร” โดยเฉพาะ payment gateway, refund, device management, CRM, organization, biometric timecard, tax ledger และ test coverage.

### คะแนนประเมิน

| มิติ | คะแนน | ความหมาย |
|---|---:|---|
| ความครอบคลุมหน้าจอ/เมนู | 85% | มีหน้าหลักเกือบครบตามระบบ restaurant POS |
| CRUD และงานหลังบ้าน local | 72% | เมนู โต๊ะ สต็อก พนักงาน รายงาน และ settings หลายส่วนใช้งานได้ |
| เส้นทางขายเงินสดแบบเครื่องเดียว | 68% | รับออเดอร์ คิดเงิน พิมพ์ และปิดกะมีแกนหลัก แต่ยังมีช่องโหว่ด้านเลขที่/ภาษี/กะ |
| การชำระเงินจริงและ refund | 30% | บัตรและ QR เป็น simulation/manual confirmation; refund ไม่คืนเงินจริงและไม่สร้าง ledger ที่ออกแบบไว้ |
| Multi-device / cloud reliability | 52% | sync กว้าง แต่มี parser bug, demo device, remote action ไม่ทำงาน และ conflict UI ไม่ใช่ conflict engine เต็มรูปแบบ |
| Security / compliance / audit | 45% | มี JWT, Keychain บางส่วน, RBAC และ audit model แต่ owner PIN/default PIN/change password/privacy manifest ยังไม่ผ่าน |
| Automated production-flow tests | 25% | มี test script จำนวนมาก แต่ส่วนใหญ่ทดสอบ helper/mock logic ไม่ใช่ production object graph/end-to-end |
| **ความพร้อมใช้งานรวมโดยประมาณ** | **55%** | เหมาะกับ pilot/internal demo หลังจำกัด payment เป็น cash; ยังไม่ใช่ POS production สมบูรณ์ |

> คะแนนเป็น engineering readiness ไม่ใช่สัดส่วนจำนวนบรรทัด และไม่ควรตีความว่าแก้ครบได้ด้วยการเติม UI อีก 45%; งานที่เหลือส่วนใหญ่เป็น transaction integrity และ integration.

## 2. แผนผังข้อมูลหลัก

```text
Merchant login/JWT
  -> Staff lock + Role permissions
  -> Dashboard navigation
     -> Table session -> Order -> Order items/modifiers
                      -> Payment -> Receipt/Print
                      -> Inventory transaction/lots
                      -> KDS status
                      -> Customer/loyalty
     -> Register session -> Cash movement -> Z report
     -> SwiftData local store <-> SyncEngine <-> Supabase
```

จุดที่เชื่อมดี: table session → orders → KDS, menu/recipe → stock deduction, local models → sync pipeline, register session → cash movements → Z report.  
จุดที่ขาด: payment confirmation → gateway, refund UI → `RefundTransaction`/stock/gateway, checkout → `OrderTaxLine`, settings → runtime หลายค่า, device UI → remote command, CRM → add/edit, notification escalation settings → scheduler.

## 3. ตรวจทีละหน้าจากบอร์ดถึงตั้งค่า

สถานะ: **พร้อม** = แกนหลักใช้จริง, **บางส่วน** = มีข้อมูล/CRUD แต่ยังขาดเส้นทางสำคัญ, **จำลอง** = UI แสดงผลได้แต่ action หลักยัง mock/no-op.

### 3.1 Overview

| หน้า | ทำอะไรได้ | สถานะ | สิ่งที่ขาด/ต้องเชื่อม |
|---|---|---|---|
| Dashboard | KPI รายได้, order วันนี้, โต๊ะใช้งาน, prep time, top items, staff on duty, hourly/category charts, activity feed | บางส่วน | คำนวณจาก local data; ไม่มี server reconciliation/branch scoping ครบทุก query และข้อมูล refund/tax ที่ต้นทางขาดทำให้ KPI คลาดเคลื่อน |
| Notifications | filter alert, read/acknowledge, escalation settings | บางส่วน | ค่า timeout/repeat/sound ถูกบันทึกอย่างเดียว ไม่มี code อื่นอ่านไปทำ escalation; acknowledge อยู่ใน memory store ไม่พบ durable audit/backend acknowledgment |

### 3.2 Operations

| หน้า | ทำอะไรได้ | สถานะ | สิ่งที่ขาด/ต้องเชื่อม |
|---|---|---|---|
| Table Management | แผนผัง/รายการโต๊ะ, floor/zone, drag layout, background plan, preset, add/delete table, join/status, QR batch print, service request, เปิด session | ค่อนข้างพร้อม | ไฟล์ใหญ่ 3,557 บรรทัดเสี่ยง regression; การแก้บาง action ใช้ manager PIN แต่ RBAC ไม่ได้ guard ทุก mutation; ต้องมี concurrency test เมื่อสองเครื่องเปิด/ย้าย/ปิดโต๊ะเดียวกัน |
| Orders / POS | ค้นหาเมนู/SKU/barcode, modifier, note, customer, dine-in/takeout/delivery, hold/recall, promotion, split tender, cash/QR/card, receipt, refund entry | บางส่วน | บัตรและ QR เป็น simulation; ไม่มี transaction idempotency ที่ checkout local, manual discount/price override และ tip flow ไม่ครบ, tax line ไม่ถูกสร้าง, held recall soft-delete order เดิม, ไม่มีตรวจ stock negative ก่อนขาย |
| Kitchen Display | kitchen/bar station, ticket timing, serve/recall/reject, history, waiter alert, auto-complete, search/filter | ค่อนข้างพร้อม | ต้องทดสอบ race ระหว่างหลาย KDS; status transition กระจายหลาย view; ไม่มี production integration test ว่า order ทุกประเภท/รายการเพิ่มทีหลังส่ง ticket เพียงครั้งเดียว |
| Menus / Inventory workspace | catalog, category/modifier, recipe, menu import AI, stock, receive/waste/return/transfer/audit, supplier, PO, branch, expiry/FEFO, safety stock, expense | บางส่วน | `InventoryLot` ไม่อยู่ใน explicit app Schema; lot pull cast `Data` เป็น array ซึ่ง fail เสมอ; bulk/document receive ไม่สร้าง lot; refund ไม่เรียกคืน stock; transfer/PO ต้องทดสอบ atomicity และ cross-branch FK |

### 3.3 Management

| หน้า | ทำอะไรได้ | สถานะ | สิ่งที่ขาด/ต้องเชื่อม |
|---|---|---|---|
| Hot Actions / Cash Drawer | เปิดกะ, opening cash, cash in/out, expected vs actual, close shift, Z receipt/history | บางส่วน | เปิดกะ fallback เป็น UUID สุ่มถ้าไม่มี user ทำให้ FK เสีย; auto-close กะอื่นโดยไม่ reconciliation; `ShiftReport.totalTax` และ discount ถูกใส่ 0; ไม่มีคำสั่ง kick ลิ้นชักเงินจริง |
| Payments | enable methods, ดู transaction, provider cards, gateway credential form, settings | จำลอง | provider connected ถูก hard-code; credential formไม่ persist/verify; auto-reconcile/receipt/tip/multi-currency toggles เป็น `.constant`; ไม่มี PSP SDK/API/webhook |
| Reports | daily sales, Z, VAT, menu profitability, inventory/expiry analytics, employee hours, PDF | บางส่วน | Tax report พึ่ง `OrderTaxLine` ที่ checkout ไม่สร้าง; refund report พึ่ง `RefundTransaction` ที่ refund UI ไม่สร้าง; local-only report ไม่มี server close-of-day reconciliation |
| Accounting | overview, P&L, delivery, menu engineering, inventory, staff, PDF | บางส่วน | เป็น managerial analytics จาก local models ไม่ใช่ double-entry accounting; ไม่มี chart of accounts, journal, AP/AR, settlement reconciliation หรือ immutable period close |
| Marketing | CRUD promotion, schedule, percentage/fixed/buy-X-get-Y/bundle, product/media rules, usage metrics | ค่อนข้างพร้อม | ต้อง test stacking/exclusivity/timezone/refund reversal; navigation ให้สิทธิ์ `.discountApply` ซึ่งไม่เท่ากับ permission จัดการ campaign |
| Loyalty / Gift Cards | rate settings, member points adjustment/history, issue/top-up/redeem/void gift card | บางส่วน | POS checkout ไม่พบ flow earn/redeem ที่ atomic กับ payment; gift card ไม่อยู่ใน payment methods; manual adjustment ไม่มี manager permission guard; card number/duplicate/concurrent redemption ต้องบังคับฝั่ง DB |

### 3.4 People

| หน้า | ทำอะไรได้ | สถานะ | สิ่งที่ขาด/ต้องเชื่อม |
|---|---|---|---|
| Customers | list/search/segment, spend/visit/point, purchase history | จำลองบางส่วน | ปุ่ม Add customer เป็น no-op; ไม่มี edit/merge/consent/delete/export/communication log แม้ comment ระบุไว้; POS มี customer picker/add แยกอีก implementation |
| Payroll | employee/shift/timecard CRUD, approve/reject, Thai address/bank, payroll calculation, PDF/monthly report/calendar | บางส่วน | เป็น calculation/report ไม่ใช่ payroll filing/payment; ไม่มี period lock/versioned formula/tax withholding/social security submission; permission ครอบหน้าแต่ action ไม่แยก approve/edit/pay |
| Timecard | employee list, clock in/out, log, charts | จำลองบางส่วน | face scanner ชื่อและพฤติกรรมเป็น simulator; ไม่มี camera face verification/liveness ที่รับรองได้; test seed ยังใช้ PIN SHA-256 แบบ legacy |

### 3.5 Enterprise

| หน้า | ทำอะไรได้ | สถานะ | สิ่งที่ขาด/ต้องเชื่อม |
|---|---|---|---|
| Stores | profile, VAT/service charge, receipt header/footer/logo, PromptPay, QR design | บางส่วน | เก็บค่าองค์กรใน UserDefaults และไม่เห็น merchant settings record ที่ sync ครบ; ซ้ำกับ Organization/Tax/Receipt pages ทำให้ source of truth แตก |
| Devices | แสดง status, pairing QR/passcode, detail actions | จำลอง | grid ใส่อุปกรณ์ตัวอย่าง 5 เครื่องเสมอ; Force Sync/Logout/Wipe เป็น empty action; app version/status หลายค่า hard-code |
| Organization | profile, subscription, billing, API keys, audit, data/backup | จำลอง | plan/date/price/API key เป็น placeholder; Manage/Regenerate/export/import/delete rows ไม่มี action; profile แก้ UserDefaults โดยไม่มี save/sync |

### 3.6 System

| หน้า | ทำอะไรได้ | สถานะ | สิ่งที่ขาด/ต้องเชื่อม |
|---|---|---|---|
| Integrations / Sync Health | pending queue count, status, run sync, connection, audit, conflict link | บางส่วน | conflict page แสดง queue/strategy แต่ไม่พบ field-level conflict records หรือ deterministic merge audit; purge local changes เป็น operation เสี่ยงและต้อง owner re-auth |
| Settings | account/language, online/offline, directory ไป settings ย่อย, logout/delete account | บางส่วน | Change Password เป็น delay simulation; owner PIN เก็บ plaintext UserDefaults; delete local cache ลบเพียง 4 model ก่อน sign-out;ข้อความอ้าง “purge all” ไม่ตรง implementation |

## 4. Settings ย่อย

| หัวข้อ | ทำอะไรได้ | ช่องว่างสำคัญ |
|---|---|---|
| Appearance | light/dark/system | ใช้ได้ |
| Table System | เปิด/ปิดโต๊ะและ web ordering/offline | ใช้ได้ระดับ setting; ต้องตรวจผลต่อ order ที่กำลังเปิดก่อนสลับ mode |
| KDS | kitchen/bar/workflow | มีผลบางส่วน; ต้องรวม source of truth กับ quick settings ใน KDS |
| Printers | printer CRUD, TCP/BLE/MFi/Star route, station/category routing, preview/test | TCP/BLE มี implementation; Star ต้องมี SDK จึงทำงาน; Swift 6 concurrency warnings; ไม่มี hardware certification matrix/queue persistence/cash drawer kick |
| Security | face toggle, attempt/lockout/session timeout, manager override settings, policy sync | owner PIN/default 8888 ทำลาย trust boundary; `require_face_scan` ไม่ทำให้ simulator กลายเป็น biometric จริง; action guards ไม่ครบตาม permissions |
| Staff devices | current device/pair QR | pairing API มีจริง แต่ lifecycle revoke/rotate/device command ยังไม่ครบ |
| Tax | profile, inclusive/exclusive, item/global basis, rounding, order-type applicability, rates | checkout อ่านเพียงบางค่า; rounding และ applicability ไม่ถูกใช้; tax line ledger ไม่ถูกสร้าง; receipt บางจุด hard-code 10% service charge |
| Receipt templates | receipt/kitchen/bar/sticker templates, 58/80mm, logo/QR, preview | template/renderer กว้าง; ต้อง test byte output กับ printer models และ fiscal fields; sample PromptPay fallback ต้องห้ามใน production |
| Currency | CRUD exchange rates/calculator | ไม่พบ checkout tender/conversion/accounting settlement ใช้อัตรานี้จริง |
| System Ops | seed, clear cache, wipe, server URLs, connection test, audit | developer/danger operations อยู่ใน app target; ต้อง compile-gate หรือ owner+server challenge; default owner PIN ใน wipe flowไม่ปลอดภัย |
| Subscription | แสดง tier/details/update plan | มี network payload บางส่วน แต่ Organization แสดง plan hard-codeคนละ source |
| Sync Conflict | queue, strategy, sync/purge/log | เป็น operational UI มากกว่า conflict-resolution engine ที่เก็บ base/local/remote versions |

## 5. เส้นทางธุรกิจแบบ end-to-end

### A. รับออเดอร์ dine-in → KDS → ชำระ → ปิดโต๊ะ

สถานะ: **ทำงานได้ระดับ pilot**

- เปิด table session, ส่ง order เข้าครัว, เปลี่ยน item/order status และปิดโต๊ะได้
- ตอนชำระแบบโต๊ะ สร้าง Payment ให้ order ที่ยังไม่มี payment และพิมพ์ receipt
- ความเสี่ยง: split payments ทั้งหมดถูกผูกกับ order แรกของหลาย order ใน session; receipt ถูกเลือกเพียง first order; ไม่มี atomic server transaction ครอบ payment + close session + table state; error network เกิดหลัง local close ได้

### B. Counter / takeout cash sale

สถานะ: **ใกล้สุดต่อการใช้งานจริง**

- สร้าง order/items/payment, หักสูตรวัตถุดิบ, sync และพิมพ์ได้
- ต้องแก้เลข order แบบ random 3 หลัก, save failure แล้วยังล้าง cart, shift/user binding, tax ledger และ cash tender/change audit ก่อน production

### C. PromptPay QR

สถานะ: **ไม่ใช่ payment integration**

- สร้าง Thai QR payload ได้
- UI เปลี่ยนเป็น success อัตโนมัติหลัง 3 วินาที และมี Force Confirm; ไม่มี bank/PSP callback, transaction reference หรือ amount verification

### D. Credit card

สถานะ: **simulation เท่านั้น**

- หน้าจอจำลอง connecting/swipe/processing/authorized ตาม timer และกด Skip EDC Simulation เพื่อจบได้
- ไม่มี EDC SDK, acquirer API, reversal, capture, settlement, decline/timeout handling หรือ PCI boundary

### E. Refund

สถานะ: **ไม่ครบและมีความเสี่ยงทางการเงิน**

- เปลี่ยน item/order/payment status และเขียน generic AuditLog
- ไม่สร้าง `RefundTransaction`, ไม่คืน stock แม้มี `reverseInventoryDeduction`, ไม่กระจาย tax/service/discount สำหรับ partial refund, ไม่คืนเงินจริง original tender, และ mark payment ทุกตัวเป็น partial/refunded

### F. Inventory/FEFO

สถานะ: **ออกแบบดีแต่ chain ขาด**

- receive รายชิ้นสร้าง lot, POS consume FEFO, expiry dashboard/safety stock/PO/audit มี
- `InventoryLot` ขาดจาก explicit schema และ remote GET parser cast ผิด; bulk/doc receive ใช้ legacy receive ไม่มี lot; waste/return/refund ต้องทำ lot reversal ให้ครบ

### G. Offline → reconnect

สถานะ: **มีแกนหลักแต่ยังไม่รับรองความถูกต้องทางธุรกรรม**

- models ส่วนใหญ่มี `isSynced/isDeleted/updatedAt`, pipeline push parent ก่อน child และมี realtime/retry
- sync ทุก 5 วินาทีจาก main dashboard; conflict เป็น last-write/strategy หลายจุดโดยไม่มี base version; ไม่มี durable outbox/idempotency key สำหรับ command สำคัญ; local save และ server close แยก transaction

## 6. รายการต้องแก้ตามลำดับ

### P0 — ห้ามเปิด production ก่อนแก้

1. เปลี่ยน owner PIN ไป salted hash ใน Keychain/server policy, บังคับตั้งครั้งแรก และลบ default `8888`.
2. ทำ Change Password จริงผ่าน backend พร้อม verify current password, revoke/rotate session; ห้ามแสดง success จำลอง.
3. ปิด payment card/QR จาก production UI จนมี gateway integration จริง หรือ label ชัดว่า manual external terminal พร้อม reference/manager confirmation.
4. สร้าง payment state machine: initiated/authorized/captured/failed/voided/refunded, idempotency key, immutable reference และ webhook reconciliation.
5. แก้ refund ให้สร้าง `RefundTransaction`, allocate tax/discount/service, คืน stock/lot, คืน loyalty/promotion usage และเรียก gateway reversal/refund แบบ idempotent.
6. แก้ `InventoryLot` schema และ JSON decode ของ pull; เพิ่ม integration test receive → sync → pull → FEFO sale → refund.
7. ห้าม fallback random `openedByUserId`; ต้องมี authenticated operator และห้าม auto-close กะอื่นโดยไม่ reconciliation/override.
8. ถ้า `modelContext.save()` checkout ล้มเหลว ต้อง rollback และคง cart; ห้ามล้าง cart/พิมพ์/sync ต่อ.
9. ทำ atomic checkout/close-table RPC หรือ durable outbox เพื่อไม่ให้ local paid แต่ server open หรือกลับกัน.
10. ลบ/ซ่อน demo device, no-op remote actions, simulated biometric, seed mock menu และ sample PromptPay/Tax ID จาก Release build.

### P1 — ต้องแก้ก่อน rollout หลายสาขา

11. สร้าง `OrderTaxLine` ทุก checkout และใช้ tax applicability/rounding/profile จริง; receipt/report ต้องอ่าน snapshot จาก order ไม่อ่าน UserDefaults ปัจจุบัน.
12. ทำ order/receipt number จาก server/register sequence ที่ unique และ audit ได้ แทน random 100...999.
13. บังคับ RBAC ที่ action/service layer: inventory edit, promotion manage, customer edit, gift/loyalty adjustment, cash movement, refund/void, settings, device command.
14. ทำ Device Management จากข้อมูลจริงและ remote command queue ที่ signed/audited; ลบ hard-coded devices/status/version.
15. ทำ CRM add/edit/merge/consent/delete และรวมกับ CustomerPicker ให้ใช้ form/service เดียว.
16. รวม merchant/store/tax/receipt/organization settings เป็น authoritative server model ลด UserDefaults ซ้ำหลายหน้า.
17. ทำ durable notification acknowledgment/escalation; ให้ settings timeout/repeat/soundถูกใช้งานจริง.
18. ทำ conflict journal ที่เก็บ entity/base/local/remote version และ resolution actor/time; เพิ่ม tenant/branch scoping tests.
19. แก้ PrivacyInfo ให้ประกาศข้อมูลจริง เช่น contact, identifiers, financial/purchase, user content และ sensitive employee/biometric dataตามการใช้งาน/นโยบาย.
20. แยก XCTest/UI test target และทดสอบ production code ไม่ใช่ helper จำลอง.

### P2 — ความครบถ้วนเชิงมาตรฐาน POS

21. เพิ่ม manual discount/price override/reason/approval, tip, comp, no-sale drawer และ paid-order void ที่เป็น ledger ชัดเจน.
22. เพิ่ม digital receipt email/SMS/LINE พร้อม consent และ delivery log.
23. เพิ่ม cash drawer hardware kick/status และ printer job queue/retry persistence.
24. ทำ gift card เป็น payment tender และ loyalty earn/redeem ให้ atomic กับ checkout/refund.
25. ทำ close-of-day reconciliation: tender vs PSP settlement vs cash vs refund/chargeback และ period lock.
26. เพิ่ม stock negative policy, reservation/allocation, unit conversion/yield, lot reversal และ costing snapshot.
27. เพิ่ม backup/restore/export/import ที่ใช้งานจริงพร้อม encryption/checksum/restore drill.
28. ทำ payroll period lock, approval chain, statutory export/payment ถ้าจะวางขายเป็น payroll จริง; ไม่เช่นนั้นเปลี่ยนชื่อเป็น labor estimate.

## 7. Evidence สำคัญใน source code

- Navigation มี 20 tab และ mapping views จริง: `AlphaPos/Features/Dashboard/Views/MainDashboardView.swift:690`.
- Device grid ใส่ placeholder devices และ remote action ว่าง: `DeviceManagementView.swift:134`, `:280`.
- CRM Add customer เป็น no-op: `CustomerCRMView.swift:123`.
- Organization plan/API/export actions เป็น placeholder/no-op: `OrganizationManagementView.swift:162`, `:222`, `:296`.
- Payment settings ใช้ constant binding และ gateway status hard-code: `PaymentGatewayView.swift:579`, `:679`.
- QR auto-success/manual force confirmation: `POSView.swift:2724`, `:2756`, `:2781`.
- Card terminal simulator และ Skip: `POSView.swift:2899`, `:2963`.
- Refund ไม่สร้าง `RefundTransaction`: flow อยู่ `RefundView.swift:82`; model ที่ไม่ได้ใช้ใน flowอยู่ `Models/RefundTransaction.swift`.
- Checkout มี `OrderTaxLine` model/sync แต่ `processCheckout` สร้างเพียง `OrderDiscount`: `POSViewModel.swift:411`, `:455`.
- Owner PIN plaintext/default 8888: `SettingsView.swift:616`, `StaffLockView.swift:524`.
- Change password จำลอง: `SettingsView.swift:904`.
- Register session random user fallback: `CashDrawerManagementView.swift:656`.
- Inventory lot pull cast จาก `Data` ผิดชนิด: `NetworkManager+InventoryLots.swift:116`; compiler เตือนว่า cast fail เสมอ.
- Explicit schema ไม่ใส่ `InventoryLot`: `App.swift:62-78`.
- Star printer transport ระบุ placeholder stub: `PrinterTransport.swift:250`.
- Face scanner เป็น simulator: `EmployeeTimecardView.swift:544`.
- test project มี target เดียว `AlphaPos`; test filesถูก compile เข้า app target และ POS tests mirror logic ด้วย private helper แทนการเรียก `POSViewModel`.
- Privacy manifest ระบุ collected data types เป็น array ว่าง แต่ models/UI เก็บ customer contact, national ID, bank และ face fields: `Supporting Files/PrivacyInfo.xcprivacy`.

## 8. Verification ที่ทำในรอบนี้

- ตรวจ Swift source ประมาณ 85,000 บรรทัดและไฟล์ module/navigation/model/sync/remote contract.
- รัน iPad Simulator Debug build ด้วย Xcode: **BUILD SUCCEEDED** บน iPad (A16), iOS 26.5.
- Build ยังมี Swift concurrency warnings หลายจุดซึ่งระบุว่าจะเป็น error ใน Swift 6 และ warning ว่า InventoryLot response cast fail เสมอ.
- เรียก `./run_tests.sh` แล้ว แต่ standalone test bundle ใช้เวลาคอมไพล์ผิดปกติและไม่จบ จึงยุติกระบวนการ; รอบนี้ **ไม่มีผล test pass ที่เชื่อถือได้**. ตัว project เองมีเพียง app target ไม่มี XCTest target.
- แม้ test helper จะผ่านในอนาคต ต้องตีความว่าไม่ใช่ production E2E เพราะหลาย suite สร้าง calculator/mock model ของตนเอง.
- ไม่ได้ทดสอบเงินจริง, printer hardware, camera/Face ID, Supabase production tenant หรือหลาย device พร้อมกัน เพราะต้องใช้อุปกรณ์และ credential จริง.

## 9. เกณฑ์ที่จะเรียกว่า “100%”

ควรประกาศ 100% เฉพาะเมื่อ P0/P1 ปิดทั้งหมด และมีหลักฐานต่อไปนี้:

- E2E ผ่านทุก tender: cash, QR, card, split, cancel, timeout, retry, duplicate callback, partial/full refund.
- Offline chaos test: kill app/network ระหว่าง save/payment/print/sync แล้วไม่สูญหรือซ้ำ.
- Two-device race test: โต๊ะ/order/stock/gift card เดียวกัน.
- Tax golden tests: inclusive/exclusive, service charge taxable, item exemption, rounding, refund และใบกำกับ.
- Shift/Z reconciliation ตรงกับ payments/refunds/cash movements ทุกบาท.
- Hardware matrix ผ่าน printer/EDC/scanner/drawer ที่รองรับจริง.
- Security review: no default credential, Keychain protection, server-side authorization, tenant isolation และ immutable audit.
- Migration/backup/restore drill จาก version ก่อนหน้าและข้อมูลขนาด production.
- Release build ไม่มี seed/mock/simulator/no-op production path และมี XCTest/UI/integration suite ใน CI.
