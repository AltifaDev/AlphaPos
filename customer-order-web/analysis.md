# Customer Order Web — System Analysis

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
  ├── Supabase JS SDK (direct reads: menu, modifiers, sessions, orders)
  │     └── Supabase Realtime (WebSocket subscriptions)
  │
  └── Python HTTP Server (server.py)
        ├── Local SQLite (read/write cache)
        └── Supabase REST API (dual-write proxy)
              └── Supabase PostgreSQL (cloud master)
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
- **Dual-write pattern** — writes go to both SQLite and Supabase for redundancy
- **Comprehensive API** — 16 GET + 12 POST endpoints covering orders, sessions, payments, menu, promotions, modifiers, employees, timecards, service requests

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
| Direct customer order writes to Supabase | Customer orders now submit through `/v1/orders` so server-side validation is enforced before dual-write. |
| Missing server-side price validation for customer orders | `/v1/orders` recalculates menu item, modifier, service charge, VAT, and total from server-side data and rejects mismatches. |
| Silent Supabase dual-write failures | Failed Supabase writes are now stored in `pending_supabase_writes` and retried on server startup. |
| Missing retry queue visibility | Added `/v1/sync/status` and authenticated `/v1/sync/retry` endpoints for queue monitoring and manual retry. |

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
