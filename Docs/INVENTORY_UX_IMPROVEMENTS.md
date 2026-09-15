# Inventory UX Improvements (2026-07-14)

## Implemented

### Information architecture
- Tabs reorder to: **Stock → Purchasing → Counts → Products → Recipes* → More**
- `More` groups Suppliers + Expenses
- Purchasing and Counts are first-class (no longer only buried in toolbar)

### Merchant profile (`inventory_profile`)
- Setting in **System Feature Config** (POS & Floorplan section)
- `simple` — hides Recipes tab (retail / no BOM)
- `restaurant` — shows Recipes (default, kitchens)

### Stock list
- Renamed primary surface to **Stock** (not “Raw Materials” only)
- Chips: **All / Ingredients / Finished Goods**
- Empty state CTAs: add stock item + set up products

### Product ↔ stock linking
- `MenuItem.stockTrackingMode` persisted (`not_tracked` | `finished_good` | `recipe_based`)
- Heuristic fallback for legacy rows without the field
- Product editor Recipe tab available on **create** (not only edit)
- Simple profile defaults new products to **Finished Good**
- Clear help text under each tracking mode

### POS
- Badge **ไม่ตัดสต็อก / No stock** when item does not track stock on sale
- Leaf icon when stock is tracked

## Deduction reminder

| Mode | POS effect |
|------|------------|
| Not Tracked | No quantity change |
| Finished Good | Deduct `1 × qty sold` from linked SKU |
| Recipe Based | Deduct `qtyRequired × qty sold` per ingredient (+ modifiers if linked) |

## Related

- Sync gaps: `Docs/INVENTORY_HYBRID_SYNC_ROADMAP.md`
