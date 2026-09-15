# AlphaPos Onboarding Redesign — Product Decision Spec

**Status:** Approved for implementation  
**Date:** 2026-07-25  
**Owner:** Product + iPad Auth  
**Related:** `Docs/AUTH_UX_ARCHITECTURE.md`, `MerchantOnboardingGate.swift`, `activate-merchant`

---

## 1. Decision summary

AlphaPos will move from a **security-first sequential funnel** to **Fast Create → Progressive Complete**.

| Principle | Decision |
|---|---|
| Time-to-dashboard | Target **&lt; 2 minutes** from open app to Dashboard |
| Required at signup | Email, password, name, **shop name**, currency, terms, plan |
| Deferred | Tax ID, phone, business type, owner PIN, MFA, payment (via trial) |
| Subscription gate | Allow `active`, `trial`, `pending_payment` into the app |
| Post-entry | Guided checklist until `ready_to_sell` |
| Resume | Local + server draft so users can return and finish later |

**Non-goals this release:** Full KYC, SSO, multi-store wizard, sample menu catalog (optional later).

---

## 2. Problem statement

Testing showed merchants take too long to “open a store.” Current hard gates:

```
FirstLaunch → Account → Email verify → Login (+MFA) → Shop (+Tax/Phone)
→ Plan/Terms → Activate → subscription==active → Owner PIN → Dashboard
→ Menu + Shift (+ Table) before first sale
```

Issues vs international POS norms (Square / Toast / Lightspeed):

1. Too many sequential hard gates before any product value  
2. Tax ID / phone required in UI though server allows null  
3. Business type collected but not persisted  
4. Paid plans blocked at `pending_payment` with no in-auth Pay CTA  
5. Owner PIN blocks Dashboard instead of cash/shift risk  
6. No guided setup after entry; empty store feels unfinished  
7. Resume is device-local, not a true draft profile  

---

## 3. Target journey

```
FirstLaunch (skippable hint) → Account → Email verify → Login
→ Shop (name + currency; tax/phone optional) → Plan + Terms
→ Activate (trial for paid tiers / active for perpetual)
→ Dashboard immediately (owner unlocked)
→ Checklist: PIN · menu · shift · profile · payment
→ First sale
```

Store lifecycle:

`draft` → `ready_to_sell` → `active_paid`  
(Client checklist + subscription status; not a separate DB enum required for v1.)

---

## 4. Phase specs

### Phase 1 — Minimum signup fields + merge mode/plan

**Goal:** Reduce cognitive load and required typing.

| Field | Before | After |
|---|---|---|
| First / last name | Required | Required |
| Email / password | Required | Required |
| Shop name | Required | Required |
| Currency | Default THB | Required (default OK) |
| Tax ID | Required in UI | **Optional** — complete later |
| Contact phone | Required in UI | **Optional** — complete later |
| Business type | Shown, not saved | **Removed from signup** (Settings later if needed) |
| Terms + plan | Required | Required |
| First-launch online/offline | Forced before auth | **Skippable**; plan selection is source of truth for sync mode |

**Acceptance**

- [ ] Continue from shop step enabled with only shop name  
- [ ] Tax/phone labeled optional  
- [ ] Selecting offline/online plan applies `OfflineSyncModeController`  
- [ ] First launch offers “decide later when choosing a plan”

---

### Phase 2 — Soft commercial gate (trial / no pay-block)

**Goal:** Never leave merchants stuck after creating a tenant.

| Status | Enter app? | UX |
|---|---|---|
| `active` | Yes | Normal |
| `trial` | Yes | Banner: trial ends on date; pay to continue |
| `pending_payment` | Yes | Banner + CTA → Subscription settings |
| `expired` / other | No (or read-only later) | Keep block for now |

**Server (`activate-merchant`)**

- `offline_perpetual` → `subscription_status = active`  
- `offline_subscription` / `online_subscription` → `trial` for **14 days** (`subscription_expires_at`)

**Client**

- Remove hard fail `subscriptionStatus == "active"` only  
- Allow `active | trial | pending_payment`  
- Surface payment CTA on Dashboard checklist / banner  

**Email verification**

- Remains required before **tenant activate** (security / anti-spam)  
- Soft limits for unverified email after activate are deferred (Phase 2b) — banner only if API exposes confirmation state later  

**Acceptance**

- [ ] New paid-plan merchant reaches Dashboard without PayPal  
- [ ] Trial expiry date stored on merchant  
- [ ] Banner visible when status is `trial` or `pending_payment`

---

### Phase 3 — Defer PIN / MFA to real risk moments

**Goal:** Security without blocking first exploration.

| Control | When required |
|---|---|
| Owner PIN | Before **open register shift** or **unlock as store owner** on Staff Lock (if not set) |
| MFA soft prompt | Once at login (skippable); do **not** re-prompt on owner setup if already skipped |
| MFA enrolled | Still required at aal2 for activate / login (unchanged) |

`MerchantOnboardingGate.requiredBeforeDashboard` drops `.ownerPin`.

**Acceptance**

- [ ] New merchant reaches Dashboard without PIN  
- [ ] Opening a shift without PIN presents OwnerSetup  
- [ ] Store-account unlock without PIN presents OwnerSetup  
- [ ] MFA soft skip marks gate; OwnerSetup does not force soft MFA again  

---

### Phase 4 — Guided setup checklist after Dashboard

**Goal:** Replace long pre-entry wizard with post-entry checklist + learn-by-doing first product guide (no sample catalog).

Items (ordered for time-to-value):

1. Add at least one menu item → deep-link to Catalog + **First Product Guide** (name + price; tips; success next-step)  
2. Add at least one table — only when `enable_table_system`  
3. Set owner PIN (if missing) — still required before open shift  
4. Open first register shift  
5. Complete shop profile (tax ID / phone) — optional skip  
6. Activate paid plan (if `trial` / `pending_payment`) — optional during trial  

**First Product Guide:** User creates the item themselves (no seeded menu). Restaurant profile saves `not_tracked` menu item; `simple` retail profile uses finished-good create. Empty states on Catalog / POS / Tables expose primary CTAs.

UI: dismissible card/banner on Dashboard; reopen from Organization profile (“Finish setting up your store”).

**Acceptance**

- [x] Checklist appears for incomplete stores  
- [x] Tapping first menu item opens First Product Guide (not Stock section)  
- [x] Tapping first table opens Add Table when tables enabled  
- [x] Dismiss hides until next launch or until items remain critical (PIN / payment)  
- [x] Reopen checklist from Organization  
- [x] No sample `MenuItem` seeded on activate  

---

### Phase 5 — Draft / resume onboarding

**Goal:** Users can leave and finish later on the same or another device.

| Layer | Behavior |
|---|---|
| Local | Autosave shop/plan draft to `pending_merchant_onboarding` while typing |
| Server | `merchant_onboarding_drafts` keyed by `user_id` |
| Resume | After email verify + login without `merchant_id`, load draft into shop/plan steps |

Draft cleared when `activate-merchant` succeeds.

**Acceptance**

- [ ] Killing app mid shop/plan restores fields on return  
- [ ] Draft upserted when connected  
- [ ] Successful activate deletes draft row  

---

## 5. Metrics

| Metric | Baseline (approx.) | Target |
|---|---|---|
| Open app → Dashboard | Long sequential funnel | &lt; 2 min |
| Open app → first sale (with 1 menu) | High friction | &lt; 10 min |
| Drop-off at tax/phone step | Observed in testing | Near zero (optional) |
| Stuck at `pending_payment` | Blocking | 0 (trial path) |

---

## 6. Security & compliance notes

- Email confirmation before create-tenant remains (abuse control).  
- Device binding + merchant JWT unchanged.  
- Owner PIN still required before cash drawer / shift (PCI-adjacent ops).  
- Subscription status changes remain service-role only (`protect_subscription_state`).  
- Trial is not free forever — enforce expiry in a follow-up (cron / login check).  

---

## 7. Implementation map

| Phase | Primary files |
|---|---|
| 1 | `MerchantAuthView.swift`, `FirstLaunchModeView.swift`, `translations.json` |
| 2 | `activate-merchant/index.ts`, `MerchantAuthView.completeLogin`, checklist banner |
| 3 | `MerchantOnboardingGate.swift`, `AppSessionManager.swift`, `AppRootView.swift`, `POSView` / shift sheet, `StaffLockView` |
| 4 | `StoreSetupChecklist.swift`, `StoreSetupChecklistView.swift`, `MainDashboardView.swift`, `FirstProductGuideSheet.swift`, `CatalogManagerView.swift`, `POSView` / `TableView` empty CTAs, Organization reopen |
| 5 | `merchant_onboarding_drafts` migration, draft save/load in auth flow |

---

## 8. Rollout

1. Ship client + edge function + migration together.  
2. Existing merchants with PIN already set: no change.  
3. Existing `pending_payment` merchants: allow login + checklist pay CTA.  
4. Monitor activate errors and trial conversions for 2 weeks.  

---

## 9. Open follow-ups (not blocking)

- Soft email verify with limited cloud features  
- Sample menu template for faster first sale  
- In-auth PayPal CTA (fix device JWT vs user JWT mismatch)  
- Persist business type in Settings if product needs it  
- Automated trial expiry → `expired` job  
