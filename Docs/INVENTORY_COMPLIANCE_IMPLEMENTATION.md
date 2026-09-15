# Inventory Compliance Implementation

## Delivered foundation

- Purchase orders use synchronized tombstones rather than physical local deletion.
- Granular permissions cover receive, adjust, transfer, count, approve and recall.
- Lot disposition supports available, quarantine, rejection, recall, release and destruction.
- Recall header/lot scope and impact view link affected lots to sale references.
- Incoming inspections capture packaging, shelf-life, temperature, certificate, acceptance and rejection.
- Temperature logs capture limits, excursions, corrective action and independent verification.
- Blind count sessions enforce counter/approver separation and recount thresholds.
- Item/supplier-specific unit conversion supports cases/packs into stocking units.
- Supplier scorecard and inventory accuracy calculations are available as shared business logic.
- Server transfer uses row locks plus a unique request id for atomic, idempotent execution.
- Quarantined and recalled lots are excluded from outbound availability.

## Deployment order

1. Back up and restore-test the database.
2. Apply `Database/migrations/046_inventory_compliance.sql` in staging.
3. Run both inventory SQL integration scripts.
4. Build and run the iOS application against staging.
5. Assign granular inventory permissions to roles before enabling mutation UI.
6. Train staff using `INVENTORY_FOOD_SAFETY_SOP.md`.
7. Perform a two-device transfer test and a mock recall.
8. Apply to production during a controlled maintenance window.

## Remaining product integration gates

- Add dedicated recall, inspection, temperature and count-approval screens.
- Add pull/realtime adapters for the new compliance tables (push and pending detection are implemented).
- Route online branch transfers through `transfer_inventory_compliant`; retain the local transaction only as the offline queued request.
- Add configurable approval thresholds and manager-PIN prompts to every mutation screen.
- Add dashboard cards for excursions, quarantined lots, open recalls and count accuracy.

These gates must be completed before describing the UI workflow as fully ISO/HACCP-ready.
