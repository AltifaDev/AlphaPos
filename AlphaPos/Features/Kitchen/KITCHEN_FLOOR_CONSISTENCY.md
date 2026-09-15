# Kitchen ↔ Floor State Consistency — Fix Summary

**Date:** 2026-07-12
**Area:** Kitchen Display (KDS) · Table Management · Order lifecycle · Offline-first sync

---

## Problems reported

1. **Ghost tickets.** A table was cleared by the cashier while its kitchen ticket
   was still live. The floor showed the table **vacant**, but the KDS kept showing
   the order forever — e.g. order **#9619** stuck "cooking" for **1,622 minutes**.

2. **Detail view showed no items.** Tapping an order card on the KDS opens a
   full-screen detail view. After a refactor it rendered **nothing** even when the
   order had items (the small cards still worked).

---

## Root causes (confirmed in code)

| # | Location | Cause |
|---|----------|-------|
| 1 | `TableView.swift` → `updateGroupStatus` | Closed the table session but never terminalized the order/items → order stayed `preparing`, items stayed `cooking`. |
| 2 | `KitchenDisplayView.swift` (4 guards) | `if let session = order.tableSession, !session.isActive` failed when `tableSession == nil` (nullified by the `.nullify` delete rule) → orphaned ticket never skipped. |
| 3 | — | No reconciliation/sweep existed for already-stranded tickets. |
| 4 | `NetworkManager.fetchCustomerOrders` | Status filter omitted `cancelled` → a void on one device never propagated to other devices' KDS. |
| 5 | `KitchenDisplayView.swift` → `KitchenOrderDetailView` | `ForEach` was placed **inside** `if displayedItems.isEmpty { }` with no `} else {` → items never rendered when present. |

---

## Fixes

### 1. Central domain layer — `Models/Order+Lifecycle.swift` (new)
- `OrderStatus` / `OrderItemStatus` — explicit state sets (kitchenActive / terminal / active).
- `Order.hasActiveKitchenTicket` — order still owns a live ticket.
- `Order.isOrphanedKitchenTicket` — live dine-in ticket whose session is `nil` **or** inactive (take-out never orphaned).
- `Order.markServed()` / `Order.voidForClear(reason:employeeId:in:)` — sync-safe terminalizers; void writes an `AuditLog`.
- `TableSession.hasPendingKitchenTickets` / `terminalizeOpenOrders(_:in:)` — used by every clear path.

### 2. KDS guard — `KitchenDisplayView.swift`
All **4** guards replaced with `if order.isOrphanedKitchenTicket { continue / return false }`, covering the nil-session case. Ghost tickets disappear immediately.

### 3. Guard rail + void flow — `TableView.swift`
- `updateGroupStatus` now terminalizes lingering orders (**defensive net**) before closing any session.
- `requestClear(_:)` blocks clearing a table with pending tickets and prompts the operator: **Mark as Served** vs **Void Order**.
- Void requires **manager PIN + reason**, recorded to `AuditLog` (parity with other voids).
- Checkout / Vacant / Reserved buttons all route through the single choke point.
- 7 localization keys added (en/th/zh/ja/ko/id/ms).

### 4. Reconciliation sweep — `Data/Sync/SyncEngine+Reconciliation.swift` (new)
Runs every `syncAll`:
- **Orphans** → auto-serve + `AuditLog`.
- **Stale** (> 3h) → raise a service-request alert for a human + `AuditLog` (throttled 1×/h per order).

### 5. Cross-device void propagation — `NetworkManager.swift`
`fetchCustomerOrders` status filter now includes `cancelled`.

### 6. Detail view render bug — `KitchenDisplayView.swift`
Inserted the missing `} else {` so `KitchenOrderDetailView` renders the item list
when items exist and shows the empty state only when there are none. The small
cards (`KitchenPremiumTicketCard`, `KitchenTicketView`) were already correct.

---

## Verification

- **Static checks:** brace/paren balance verified on every changed file; all
  referenced APIs (`createServiceRequest`, `getAlertTime/setAlertTime`, `can()`,
  `APHaptic.trigger`, `AppLogger.sync`) confirmed to exist.
- **Project-wide scan:** no other `if …isEmpty { … ForEach … }` (missing-else)
  bug exists — this was the only occurrence.
- **Tests:** `Tests/KitchenLifecycleTests.swift` (16 tests) added and registered
  in `TestRunner.swift` + `run_tests.sh`, mirroring the pure decision logic
  (same pattern as `OrderSettlementTests`).

> ⚠️ **Not yet compiled here.** `swiftc`/`xcodebuild` are blocked by the local
> sandbox (SIGABRT), so a full build could not be run in this environment.
> Recommended next step: build in Xcode and run `./run_tests.sh`.

---

## Files touched

**New**
- `Models/Order+Lifecycle.swift`
- `Data/Sync/SyncEngine+Reconciliation.swift`
- `Tests/KitchenLifecycleTests.swift`
- `Features/Kitchen/KITCHEN_FLOOR_CONSISTENCY.md` (this file)

**Modified**
- `Features/Kitchen/Views/KitchenDisplayView.swift`
- `Features/Tables/Views/TableView.swift`
- `Data/Remote/NetworkManager.swift`
- `Data/Sync/SyncEngine+Notifications.swift`
- `Core/Localization/AppLocalization.swift`
- `Tests/TestRunner.swift`
- `run_tests.sh`
