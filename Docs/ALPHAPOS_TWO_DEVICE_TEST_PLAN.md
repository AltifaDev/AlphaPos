# AlphaPos two-device release test

Run this matrix against a staging VPS after applying all migrations through
`20260810000300_staff_atomic_branch_checkout.sql`. Never run payment/failure
injection scenarios against the production merchant.

## Required devices

- iPad Simulator/device: AlphaPos, staging merchant owner account
- iPhone Simulator/device: AlphaPosStaff, paired to the same staging branch
- A second branch under the same merchant for isolation assertions

## Gate scenarios

| Scenario | Action | Required result |
|---|---|---|
| Pairing | Generate code on iPad, approve on POS, pair iPhone | JWT contains merchant and branch; Staff sees only the paired branch |
| Order commit | Create an order with modifiers on Staff | POS receives one complete order; no empty aggregate appears |
| Duplicate submit | Replay the same order ID/RPC twice | One order, one set of items/modifiers |
| Offline order | Disable iPhone network, create order, re-enable network | Queue remains visible; order uploads exactly once |
| Persistent failure | Return 500 at least five times | Order moves to manual-retry state and is never deleted |
| App termination | Terminate Staff while an order is queued | Queue survives relaunch and uploads once |
| Checkout retry | Interrupt response after server commit, retry same idempotency key | One payment and completed order |
| Split payment | Pay one order with two methods | Exact total, two payment rows, one checkout operation |
| Mixed table bill | Pay multiple open orders with two methods | Each order completes once; table closes after commits |
| Realtime | Create order on either device | Other device updates after committed event without timing delay |
| Branch isolation | Pair Staff to branch A while branch B has active orders | No branch-B tables, orders, staff, shifts, or messages are returned |
| Sync diagnostics | Force a 500/timeout | Sync Health shows request ID, status, endpoint, and retryability |

## Evidence to retain

- Screen recording from both devices
- `checkout_operations`, `orders`, `order_items`, and `payments` rows
- request IDs from Sync Health
- Staff offline queue before/after reconnection
- database query proving no duplicate payment/order IDs

Production release is blocked until every row above passes on staging.
