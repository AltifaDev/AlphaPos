# Inventory Hybrid Offline/Online — Gaps & Future Work

**Status:** Usable in production for single-device POS  
**Completeness:** ~75–80% of full multi-device hybrid  
**Date:** 2026-07-14  
**Scope:** `AlphaPos/Features/Inventory` + SyncEngine inventory paths

---

## Current state (what already works)

Inventory is **offline-first** on SwiftData and **safe to use normally** on one iPad/Mac POS:

| Capability | Status |
|------------|--------|
| Local writes (receive, waste, adjust/cycle count, PO receive, transfer, POS sell deduct, refund reverse) | Done |
| Push to Supabase when `offline_sync_mode = false` and network is up | Done (items, transactions, lots, POs, recipes) with retry |
| Pull from Supabase | Partial (items, lots, recipes only) |
| Dedicated offline plan (`offline_sync_mode = true`) | By design: no cloud sync, local only |
| Temporary offline while in online plan | Local queue via `isSynced = false`, then push on next sync |

**Example path (screenshot Transaction Log “Sell Local POS…”):**

1. POS checkout → `POSViewModel.deductIngredientsLocally`
2. Updates `InventoryItem.currentQuantity`, consumes FEFO lots, inserts `InventoryTransaction` (`sell`, notes: `Local POS checkout deduct…`, `isSynced = false`)
3. Later `SyncEngine.performSync` → `syncInventoryTransactionsWithRetry` → Supabase `inventory_transactions`

This does **not** mean “local-only forever”; it means authored on Local POS and queued for sync.

---

## Mode gate (reference)

```text
UserDefaults key: offline_sync_mode
  true  → SyncEngine returns early, status = offline (no push/pull)
  false → Online hybrid: SwiftData queue + SyncEngine + Realtime (partial)
```

Relevant files:

- `AlphaPos/Data/Sync/SyncEngine+Notifications.swift` — `performSync` gate
- `AlphaPos/Features/Auth/Views/FirstLaunchModeView.swift`
- `AlphaPos/Features/Auth/Views/MerchantAuthView.swift`
- `AlphaPos/Features/Settings/Views/SettingsView.swift` (diagnostics)

---

## Future work — what is still incomplete

Prioritize in this order for true hybrid (multi-terminal inventory truth).

### P0 — Must have for multi-device correctness

#### 1. Pull `InventoryTransaction` from Supabase

- **Gap:** Only push exists (`syncInventoryTransactions` / `WithRetry`). Other devices’ ledger rows never appear in Transaction Log.
- **Impact:** Audit trail and stock history diverge across terminals; server-generated rows (e.g. void triggers) are invisible.
- **Files to extend:**
  - `SyncEngine+MasterData.swift` (or dedicated inventory sync file)
  - `NetworkManager+Orders.swift` (add fetch API alongside `uploadInventoryTransaction`)
  - Wire into Stage 2 of `performSync` + optionally Realtime
- **Acceptance:** Device B sees Device A’s sell/receive/adjust after sync; no duplicate UUID inserts.

#### 2. Pull `PurchaseOrder` (+ items) from Supabase

- **Gap:** `syncPurchaseOrders` is push-only; no `pullPurchaseOrders*`.
- **Impact:** PO created or updated on one device / back office never lands on others.
- **Files:** `SyncEngine+Menu.swift` (current PO sync), `NetworkManager+Inventory.swift`
- **Acceptance:** Create PO on A → appear on B after pull; status changes (sent/received) converge.

#### 3. Fix outbound quantity merge bug on item pull

- **Gap:** In `pullInventoryItemsFromSupabase`, unsynced outbound deltas use `-tx.quantity` after quantities are already sign-normalized (outbound negative), which can **inflate** stock.
- **Location:** `SyncEngine+MasterData.swift` (~delta reduce over `unsyncedTxs`)
- **Acceptance:** Offline sell while online peer pulls items → merge keeps correct `currentQuantity`; unit tests cover inbound/outbound/adjust.

#### 4. Soft-delete purchase orders (and sync deletes)

- **Gap:** `deletePurchaseOrder` hard-deletes locally; server row can remain.
- **Acceptance:** Delete marks `isDeleted = true`, `isSynced = false`, upload tombstone; remote soft-delete or equivalent.

---

### P1 — Soft-delete / pending UI / schedules

#### 5. Soft-delete inventory transactions upload path

- **Gap:** Soft-deleted local txns may be purged locally without server soft-delete.
- **Acceptance:** Deleted txn appears deleted on other devices after sync.

#### 6. Fix `hasPendingSyncData` coverage

- **Gap:** Pending check includes transactions/POs but can omit `InventoryItem` / `InventoryLot`.
- **File:** `SyncEngine+Notifications.swift`
- **Acceptance:** Banner/status true whenever any inventory entity has `isSynced == false`.

#### 7. Sync or drop `CycleCountSchedule`

- **Gap:** Model has sync-like flags but no SyncEngine / NetworkManager path — effectively local-only.
- **File:** `InventoryControl.swift` (+ SyncEngine wiring)
- **Decision:** Either implement push/pull or remove unused `isSynced` to avoid false expectations.

---

### P2 — Realtime & conflict polish

#### 8. Extend Realtime beyond `inventory_items`

- **Gap:** `SyncEngine+Realtime.swift` only handles `"inventory_items"`.
- **Add:** `inventory_transactions`, `inventory_lots`, `purchase_orders` (or poll after item change).
- **Acceptance:** Second device updates Transaction Log / lots without waiting for full periodic sync only.

#### 9. Stronger conflict resolution

- **Current:** `updatedAt` + unsynced txn delta overlay; lots often “local unsynced wins.”
- **Goal:** Document rules (LWW vs operational transform), add tests for concurrent receive + sell.

#### 10. Align Transaction Log display time

- **Gap:** UI may sort/show `updatedAt` (sync metadata) instead of `createdAt` (business event).
- **File:** `InventoryView.swift` `@Query` / row display
- **Acceptance:** Re-synced rows keep original event time in UI.

#### 11. Server-only movement types

- **Gap:** DB void-stock reversal trigger can insert types not in client `InventoryMovementType`; no pull means invisible anyway.
- **After pull exists:** Map or extend enum so ledger is complete.

---

## Explicit non-goals / by design

| Behavior | Note |
|----------|------|
| `offline_sync_mode = true` never calls cloud | Product plan: offline perpetual — not a bug |
| Web ordering may change stock without local txn history | Separate path; document after txn pull is done |
| Single-device online POS with green sync icon | Already production-capable |

---

## Suggested implementation checklist

- [ ] `fetchInventoryTransactions` + `pullInventoryTransactionsFromSupabase`
- [ ] `fetchPurchaseOrders` + `pullPurchaseOrdersFromSupabase`
- [ ] Unit test: outbound delta merge (no double sign flip)
- [ ] Soft-delete PO + upload tombstone
- [ ] Soft-delete inventory txn sync
- [ ] `hasPendingSyncData` includes items + lots
- [ ] CycleCountSchedule: sync or strip flags
- [ ] Realtime: transactions / lots / POs
- [ ] Transaction Log uses `createdAt` for display/sort
- [ ] Conflict policy doc + tests

---

## Key code map

| Concern | Path |
|---------|------|
| Inventory UI | `AlphaPos/Features/Inventory/Views/InventoryView.swift` |
| Inventory mutations | `AlphaPos/Features/Inventory/ViewModels/InventoryViewModel.swift` |
| POS sell deduct | `AlphaPos/Features/POS/ViewModels/POSViewModel.swift` |
| Sync orchestration | `AlphaPos/Data/Sync/SyncEngine+Notifications.swift` |
| Item + txn push/pull | `AlphaPos/Data/Sync/SyncEngine+MasterData.swift` |
| Retry wrappers | `AlphaPos/Data/Sync/SyncEngine+RetryPolicy.swift` |
| Lots sync | `AlphaPos/Data/Sync/SyncEngine+Inventory.swift` (and RetryPolicy) |
| PO sync | `AlphaPos/Data/Sync/SyncEngine+Menu.swift` |
| Realtime | `AlphaPos/Data/Sync/SyncEngine+Realtime.swift` |
| Upload txn API | `AlphaPos/Data/Remote/NetworkManager+Orders.swift` |
| Upload PO API | `AlphaPos/Data/Remote/NetworkManager+Inventory.swift` |
| Models | `InventoryItem`, `InventoryTransaction`, `PurchaseOrder`, `InventoryLot` |

---

## Bottom line

**Can use Inventory normally today** on a primary POS: local DB writes work; when the app is in online mode, data pushes to Supabase.

**Do not treat as 100% hybrid yet** until transaction/PO pull, merge fix, soft-delete, and broader realtime are done — especially if multiple inventory terminals must share one source of truth.
```