# Customer Order Web — System Analysis

> Current production baseline: 2026-08-11. Earlier recommendations below are
> historical context; this section is authoritative for the deployed design.

## Current architecture and trust boundary

1. A QR code contains an opaque active table-session token. The browser exchanges
   it with `issue-customer-session-token` for a short-lived, branch-scoped JWT.
2. PostgreSQL RLS derives merchant, branch, table, and session authority from that
   signed JWT. URL parameters and browser storage are not authorization sources.
3. `create_customer_order` is the only customer order-write path. It validates
   menu/modifier prices, calculates totals on the server, creates the full order
   atomically, records an idempotency operation, and commits a `sync_outbox` event.
4. Realtime status is consumed only after the database commit. The shared order
   state machine rejects invalid regressions; polling is only a recovery path.
5. Customer web can request a bill, but cannot record payment, complete checkout,
   or close a table session. AlphaPos/AlphaPosStaff owns atomic payment settlement.

Branch isolation is enforced with restrictive RLS policies, including when other
legacy permissive policies exist. Anonymous order RPC access and legacy REST order
and payment writes are retired. Production operational APIs require a constant-time
admin bearer token and return structured problem responses with trace identifiers.

## Verification baseline

- Backend E2E: token exchange, atomic order creation, retry idempotency, conflict
  rejection, anonymous denial, service request, cross-branch invisibility, closed
  session denial, and cleanup.
- Contract tests: required JWT/RPC/realtime/branch invariants.
- API security tests: private route denial and HTTP 410 legacy tombstones.
- Frontend: production build, dependency audit, and order-state transition tests.

Physical two-device testing remains a release gate: iPad POS + iPhone Staff/customer
browser, including network loss/recovery, duplicate payment attempts, and app
termination during an active order.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python `http.server` (stdlib, no Flask/FastAPI) |
| Database | SQLite3 (local cache) + Supabase PostgreSQL (cloud master) |
| Frontend | Vanilla JS (ES6+), CSS Custom Properties, HTML5 |
| SDK | Supabase JS Client v2 (direct reads), Supabase Realtime (WebSocket) |
| i18n | Inline dictionaries (TH/EN/ZH), `data-translate-key` attributes |
| Security | Bearer token, CORS validation, CSP headers, HMAC PIN, rate limiting |
| Testing | Selenium headless Chrome (test_browser_entry.py) |

## Data Flow

```
Browser (app.js)
  ├── Supabase REST (via Cloudflare Worker proxy origin)
  ├── Supabase Realtime WSS → supabaseRealtimeUrl (api.alphaposweb.com)
  │     └── postgres_changes on orders / table_sessions (+ 10s poll fallback)
  └── Order writes: RPC create_customer_order ONLY (price-validated in Postgres)
        └── POST /v1/orders returns 410 (retired dual-write path)
```

---

## 🟢 Strengths

- **Dual-path data fetching** — tries Supabase JS SDK first, falls back to local Python server
- **Security headers** — CSP, HSTS, X-Frame-Options, X-Content-Type-Options, path traversal blocking
- **i18n** — 3 languages (TH/EN/ZH) with ~90+ translation keys each
- **Location verification** — WiFi IP matching + GPS geofencing (50m radius) via Haversine formula
- **Realtime updates** — Supabase WebSocket subscriptions + 10s polling fallback
- **UI polish** — 30+ CSS animations, dark/light theme, onboarding wizard, bottom sheets, toast system
- **Modifier system** — radio/checkbox groups, per-modifier pricing, min/max constraints
- **Single order write path** — `create_customer_order` RPC validates menu/modifier prices server-side
- **Comprehensive API** — GET history/status via `/v1/orders`; POST create is retired (410)

---

## 🔴 Critical Issues (Fix Immediately)

| Issue | Location | Details |
|-------|----------|---------|
| **SQL injection via f-string** | `server.py:553,556` | `f"PRAGMA table_info({table})"` and `f"ALTER TABLE {table} ADD COLUMN {col} {col_type}"`. Mitigated by allowlist but still fragile. |
| **Database connection leaks** | `server.py` (get_menu, get_orders, get_sessions, get_employees, get_timecards, get_tables, get_modifiers_config) | `conn.close()` only called on success path. Exceptions leave connections open → `sqlite3.OperationalError: database is locked` under load. |

## ✅ Recently Resolved

| Issue | Status |
|-------|--------|
| Supabase credentials in template and local config files | Replaced with placeholders; runtime credentials must come from `.env`, `config.js`, `Config.plist`, or environment variables. |
| Hardcoded Swift app fallback credentials | Removed from POS and Staff config code. |
| Hardcoded customer web CSP Supabase host | Replaced with dynamic CSP host generation from `SUPABASE_URL`. |
| Missing requirements.txt | Added. |
| Direct customer order writes without validation | Orders submit via `rpc/create_customer_order`; Postgres validates menu + modifier unit prices and subtotal. |
| Dual write `/v1/orders` + RPC | `POST /v1/orders` returns 410; atomic RPC is the only create path. |
| Customer Realtime disabled behind Worker | REST stays on Worker; WSS uses `supabaseRealtimeUrl` (api host) with 10s poll fallback. |
| Silent Supabase dual-write failures | Local-server `pending_supabase_writes` retained for non-order sync; cloud `sync_outbox` is the shared hub. |
| Missing retry queue visibility | `/v1/sync/status` + RPC `get_sync_health` expose pending/failed outbox lag for all clients. |

---

## 🟡 Remaining High Priority Issues

| Issue | Details |
|-------|---------|
| **Monolithic app.js still too large** | `api.js`, `cart.js`, `data.js`, `i18n.js`, and `ui.js` are now split out, but most app orchestration still lives in one controller. |
| **TOCTOU race condition** | `handle_post_order` session auto-creation: two concurrent requests can create duplicate sessions (wasted UUIDs). |
| **Payment providers need live credentials** | `/v1/payments/intent` now supports manual and PromptPay intent generation, but real external providers still need configured credentials and settlement reconciliation. |

---

## 🔵 Medium Priority Issues

- **Magic numbers scattered throughout** — service charge 10%, VAT 7%, geofence 50m, polling 10s, timeout 5s, debounce 1.5s, etc.
- **Supabase Realtime channels** — channels and intervals are unsubscribed on page unload/pagehide, but long-running hidden-tab behavior still needs browser QA.
- **i18n covers only 11 hardcoded items** — 50 seed menu items (`isan1-50`) have no translations in app.js
- **styles.css 2,922 lines** — contains unnecessary vendor prefixes, unused properties
- **Duplicate UUID generation logic** — same function written 3 times with slightly different fallback
- **Duplicate serviceKeyMap** — same object literal appears twice in `sendServiceRequest`
- **No scroll restoration** — switching tabs loses scroll position
- **No skeleton loading states** — menu renders without loading placeholders
- **Onboarding progress bar is fake** — animates to 100% regardless of actual async operations
- **Payment method normalization** — local display strings and Supabase payloads are normalized, but reporting should standardize on one canonical enum.

---

## 🟣 Missing Features for Production

- **Payment gateway** (Stripe/Square/PromptPay QR)
- **Offline mode** (Service Worker + IndexedDB)
- **Push notifications** (Web Push API)
- **Admin/dashboard UI** for staff
- **Order progress indicator** (Received → Preparing → Ready → Served)
- **Allergen/nutrition info** on menu items
- **Bill splitting** across guests or payment methods
- **Kitchen printer integration** (ESC/POS thermal)
- **Customer feedback/rating** after dining
- **Loyalty/rewards system**
- **Table reservation** system
- **Email/SMS confirmation** after order
- **Real-time stock/availability** tracking
- **Image URL domain validation** (SSRF risk)

---

## ✅ Recommended Priority Actions

1. ✅ **Remove production credentials from template files** (`.env.example`, `config.EXAMPLE.js`)
2. ✅ **Add server-side input validation** — prices are recalculated server-side, quantities are clamped, IDs/string lengths are validated
3. ✅ **Fix database connection leaks** — request paths use `contextlib.closing()`/`try/finally`
4. ✅ **Create `requirements.txt`** for reproducible Python environment
5. ✅ **Modularize `app.js` incrementally** — split `api.js`, `cart.js`, `data.js`, `i18n.js`, and `ui.js`; further decomposition remains recommended
6. ✅ **Replace `alert()` calls** with in-app toast notification system
7. ✅ **Add proper error monitoring** — structured JSON logs, `event_logs`, and retry queue status/retry endpoints
8. ✅ **Add database indexes** on frequently queried foreign key columns
9. ✅ **Unsubscribe Realtime channels** on page unload/pagehide and clear polling intervals
10. ✅ **Add payment gateway foundation** — `/v1/payments/intent` supports manual and PromptPay intent generation; external processors still require live credentials
