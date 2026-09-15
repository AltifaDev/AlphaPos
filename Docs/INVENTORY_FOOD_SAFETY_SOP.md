# AlphaPos Inventory Food-Safety SOP

Document owner: Operations / Food Safety Manager  
Review cycle: at least annually and after every recall, serious deviation, regulatory change, or material process change  
Scope: purchasing, receiving, storage, preparation issue, transfer, count, waste, return, recall and disposal at every branch

## 1. Roles and segregation of duties

| Activity | Operator permission | Independent approval |
|---|---|---|
| Receive and inspect | `inventory.receive` | Required for over-receipt or rejected limits |
| Waste/adjust/return | `inventory.adjust` | `inventory.approve` above configured variance/value limit |
| Branch transfer | `inventory.transfer` | `inventory.approve` for high-value transfer |
| Blind count | `inventory.count` | Counter cannot approve their own count |
| Quarantine/recall | `inventory.recall` | Recall activation and lot release require authorized approver |

Shared accounts are prohibited. Every record must identify the actual operator and, where applicable, a different approver.

## 2. Approved supplier and purchasing

1. Purchase only from an approved supplier unless emergency approval is documented.
2. Maintain supplier identity, tax/contact data, lead time and product association.
3. Review supplier scorecards quarterly: acceptance, packaging, temperature, on-time delivery and rejected quantity.
4. Corrective action is required when a supplier misses the agreed threshold twice consecutively or creates a food-safety incident.

## 3. Receiving and incoming inspection

1. Match delivery to PO, SKU/barcode and supplier document.
2. Record quantity, lot/batch, expiry, unit cost and receiving time.
3. Inspect packaging integrity, required shelf life, certificate reference where applicable and delivery temperature.
4. Record accepted and rejected quantities separately.
5. Any failed safety check must result in `quarantined` or `rejected`; it must not enter available stock.
6. Over-receipt is blocked until an explicit approval workflow authorizes it.

## 4. Temperature control

1. Define minimum/maximum temperature for each controlled storage location or product class.
2. Record at opening, mid-shift, closing and at receipt; connected sensors may record more frequently.
3. A value outside the limit is an excursion. Record immediate containment, affected lot, corrective action and verifier.
4. Quarantine affected lots until an authorized food-safety decision releases or disposes them.

## 5. Lot control, FEFO and allergens

1. Every perishable receipt must have lot/batch and expiry data.
2. Issue stock by FEFO; no-expiry stock follows FIFO.
3. Quarantined, rejected, recalled or destroyed lots are excluded from available quantity.
4. Raw, ready-to-eat and allergen-containing materials must use identified storage locations and the site separation plan.
5. Transfers preserve source lot, expiry and cost identity.

## 6. Blind count and variance approval

1. Create a blind count session; the counter does not see system quantity before submission.
2. Freeze a system snapshot for every line at session creation.
3. A variance above the configured threshold changes status to `recount_required`.
4. A different authorized person approves the final variance.
5. Posting creates immutable inventory movement evidence with count-session reference and reason code.
6. Review line accuracy and value variance monthly by branch and counter.

## 7. Recall and traceability

1. Create a recall with unique number, severity, reason and affected lots.
2. Activation automatically marks all affected lots `recalled` and blocks outbound movement.
3. Generate the impact report: supplier/receipt, branch, current quantity, sale references, recovered and destroyed quantity.
4. Notify affected branches immediately and external parties according to law and the incident plan.
5. Reconcile affected, recovered, destroyed and unrecovered quantities.
6. Close only after corrective action and effectiveness verification are documented.
7. Conduct a mock recall at least annually and measure time to identify all affected lots and transactions.

## 8. Corrective and preventive action (CAPA)

Required fields: incident/reference, root cause, containment, corrective action, owner, due date, evidence, verifier, verification date and effectiveness result. Repeated failure requires process or supplier reassessment.

## 9. Training record

| Employee | Role | Module | Trainer | Training date | Assessment/result | Expiry/retraining date | Signature/evidence |
|---|---|---|---|---|---|---|---|
| | | Receiving & inspection | | | | | |
| | | Temperature and corrective action | | | | | |
| | | FEFO, allergens and quarantine | | | | | |
| | | Recall and traceability | | | | | |
| | | Blind count and approvals | | | | | |

Employees must not perform a restricted task until competency is recorded.

## 10. Internal audit checklist

- [ ] Roles and permissions match current employment duties.
- [ ] No counter approved their own count.
- [ ] PO deletion is represented by synchronized soft-delete evidence.
- [ ] Sample receipts contain supplier, lot, expiry and inspection evidence.
- [ ] Temperature excursions have containment and verified corrective action.
- [ ] Quarantined/recalled lots cannot be sold or transferred.
- [ ] FEFO sample agrees with lot allocation history.
- [ ] Transfer retry does not duplicate stock movement.
- [ ] Supplier scorecards were reviewed and poor performance has CAPA.
- [ ] A mock recall locates upstream and downstream impact within the target time.
- [ ] Inventory ledger reconciles to on-hand quantity.
- [ ] Backup, restore and multi-device reconciliation were tested.

Record finding severity, evidence, owner, due date, correction and closure verification for every failed item.

## 11. Required verification

Run before release and after inventory schema changes:

```sh
./run_tests.sh
psql "$DATABASE_URL" -f scripts/test_inventory_ledger_integration.sql
psql "$DATABASE_URL" -f scripts/test_inventory_compliance_e2e.sql
```

The SQL tests run in a transaction and roll back their test data. Execute them first in a controlled staging environment.

## 12. Standards mapping

This SOP supports, but does not itself certify, ISO 22000 food-safety management, ISO 22005 traceability and HACCP-based operational controls. Certification additionally requires organization-specific hazard analysis, prerequisite programmes, legal review, documented implementation, management review and independent audit.
