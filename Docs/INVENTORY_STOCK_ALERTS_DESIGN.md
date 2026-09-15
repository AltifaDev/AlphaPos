# Inventory Stock Alerts & POS Lock — Design

**Date:** 2026-07-14  
**Status:** Phase 1 + Phase 2 implemented

---

## Phase 1 (complete)

- Notification Center category **Inventory** + live low/OOS rows  
- Soft POS lock when sellable servings &lt; 1  
- Optional auto sold-out (`auto_disable_oos_menu`)  
- Design rules for retail vs restaurant BOM  

---

## Phase 2 (complete)

### 1. Sync `is_available`
- Upload: `NetworkManager.uploadMenuItem` sends `is_available`  
- Pull: `pullMenuItemsFromSupabase` applies remote availability when local is synced  
- Migration: `supabase/migrations/20260714000100_menu_items_is_available.sql`  
- Customer web already filters `is_available=eq.true` — auto sold-out now reaches QR ordering after sync  

### 2. Staff push `inventory_alert`
- Edge Function: `send-staff-push` handles `inventory_alert` / `inventory_low` / `inventory_out`  
- POS: `NetworkManager.sendStaffPush` + `SyncEngine.pushInventoryAlertToStaff` on first OOS pulse  
- Settings: `enable_inventory_staff_push` (POS) + `push_inventory_alerts` (Staff app)  

### 3. Deep-link Notification → Inventory
- Tap Inventory alert → `.openInventoryItemNotification`  
- MainDashboard switches to Inventory tab  
- InventoryView focuses search on that SKU  

### 4. Full shortage list on POS
- `checkStockBeforeAdding` lists **all** short recipe/modifier lines (not only the first)  

---

## Settings cheat sheet

| Key | Default | Effect |
|-----|---------|--------|
| `enable_inventory_stock_alerts` | true | Sidebar live rows |
| `auto_disable_oos_menu` | false | Flip `isAvailable` + sync to web |
| `enable_inventory_staff_push` | true | Edge push on first OOS |
| `push_inventory_alerts` (Staff) | true | Receive inventory pushes |

---

## Restaurant reminder

- Soft lock (default): POS only; menu still visible for 86 if needed  
- Hard auto sold-out: enable for QR/web parity when ingredients cannot make 1 serving  
- Sellable servings = min floor(onHand / recipeQty) across BOM lines  

---

## Deploy notes

1. Apply migration `menu_items_is_available` (local file: `supabase/migrations/20260715000100_menu_items_is_available.sql`) on VPS Supabase  
2. Redeploy Edge Function `send-staff-push`  
3. Staff app build with inventory preference toggle  
