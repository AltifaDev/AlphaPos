# Operational access policy

## Implemented in this change

- Exact legacy role aliases; unknown roles deny by default. A non-empty policy
  containing no valid permissions denies access. `none` represents explicit deny-all.
- Manager and supervisor presets use allowlists; new permissions are never
  implicitly inherited by these operational roles.
- Sidebar and destination rendering both enforce the selected permission.
  Promotions, expenses, accounting, permission administration and reading
  notifications have separate permission keys.
- Cashier can sell, use tables, view kitchen status, look up customers in POS,
  open the drawer through its existing workflow, and read scoped notifications.
  Full CRM, whole-store dashboard and manual discount authority are not defaults.
- Stock-only workspace exposes quantities for the active branch, not costs.
  Receiving without cost visibility uses the existing valuation and records
  actor, reason, item, branch and before/after quantities. It is not invoice entry.
- Role administration checks the actor's permissions, prevents editing their own
  shared role and prevents granting authority greater than the actor's.
  Employee account assignment and PIN reset apply the same delegation boundary.
- Role changes are audited. Local session checks lock a session when its stored
  role permissions change, requiring a fresh unlock.
- Report tabs, report loading and export require the relevant sensitive-data
  permissions. Notification history with no verifiable branch is owner-only.

## Existing installations

Saved explicit role grants are preserved. The role editor provides a reset-to-
preset button and a sidebar preview; saving is an explicit administrator action.
There is no automatic revocation of manually granted access in existing stores.
Owner/Admin are protected legacy aliases and cannot be modified through the role
permission editor. This is alias hardening, not a schema migration to role IDs.

## Remaining work (not represented as completed)

- Server/API enforcement parity and role-assignment enforcement on other clients.
- Persisted authorization scopes (own/assigned branches/all), independent from
  the active-branch context used by existing screens.
- Dedicated own-shift dashboard, own-shift drawer/history and self-service HR UI.
- Separate scheduling, table service/layout, menu availability, stock-count and
  negative-stock-policy privileges throughout every legacy form.
- Per-action approval requests, amounts/limits, temporary role delegation,
  expiry/revocation while offline and maker/checker enforcement on each workflow.
- A complete migration from role-name aliases to immutable role preset IDs.

Until scoped views exist, broad modules are hidden instead of exposing all data
under a limited-role label. A sidebar denial is not a substitute for API security.

## Verification checklist

1. Cashier: POS/stock diagnostics work; no full inventory costs, CRM management,
   expense/accounting/promotion administration, HR or system settings.
2. Try an inventory/payment notification or a stale selected tab without its
   permission: destination remains denied.
3. Manager: stock list is branch-only; receiving does not disclose or edit costs.
4. Revoke a role permission: next session guard locks the affected staff session.
5. Non-administrator cannot grant themselves a role or reset a higher-privilege PIN.
6. Save zero role permissions, unlock again: no fallback privileges appear.
7. Unknown role names and names merely containing admin/owner grant no defaults.
8. Full owner access remains available; saved custom grants are not overwritten.
9. Check cost/profit report tab, stale selection and export independently.

Automated policy tests run through `bash run_tests.sh`. Device interaction tests
and backend authorization auditing must be recorded separately from build success.
