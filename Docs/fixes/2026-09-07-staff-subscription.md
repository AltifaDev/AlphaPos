# Staff subscription status correction

The login screen previously treated every status other than `active` as expired,
including valid trials and pending payment. Missing status/tier also defaulted to
active/online, and expiry was not evaluated.

Staff now calls `get_staff_subscription_access`. PostgreSQL evaluates the plan,
status and expiry using statement time. Online active/trial subscriptions with a
finite future expiry are allowed. Pending payment, expired trial, expired paid
plan, offline plan, inactive account and incomplete data have distinct outcomes.
Unknown responses never grant access. Every retry makes a fresh request.

The RPC uses invoker permissions/RLS and requires a merchant claim in the JWT;
a merchant header alone is insufficient. Its result is also checked against the
paired merchant by Staff. The main register may continue opening billing during
trial/pending states; that is separate from companion-device entitlement.

## Release and validation

- Migration: `supabase/migrations/20260907000100_staff_subscription_access.sql`.
- Applied to the configured production database on 2026-09-07.
- SQL regression: `Database/test_staff_subscription_access.sql` (20 cases).
- Verified authenticated tenant lookup and rejection of header-only lookup.
- Swift regression: `AlphaPosStaffTests/SubscriptionAccessTests.swift`; all 3 tests passed on iOS Simulator.
- Staff simulator and signed device builds succeeded.
- Installed the Debug build on the paired iPhone 13 Pro Max (AltifaDev.AlphaPosStaff).
  No App Store/TestFlight release was performed.
- Install/release the rebuilt Staff app to replace the old client-side condition.
  Existing installed clients continue using their old condition until updated.
- No merchant subscription/payment rows were changed.

The reported merchant currently has online/pending_payment with no expiry.
No subscription_change_requests rows were found for that merchant at inspection.
This is not proof that no payment happened outside this flow. Reconcile any
receipt/provider confirmation before changing entitlement or requesting payment.

Missing expiry on an online active/trial subscription deliberately requires data
repair from verified entitlement; it is not treated as perpetual access.
