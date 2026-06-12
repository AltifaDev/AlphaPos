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
| **Supabase credentials in template files** | `config.EXAMPLE.js`, `.env.example` | Both contain **live production** anon key and merchant ID. Anyone with source access can make anonymous Supabase API calls. |
| **Fallback credentials in app.js** | `app.js:221-224` | Hardcoded Supabase URL/key as defaults if `config.js` fails to load. |
| **SQL injection via f-string** | `server.py:553,556` | `f"PRAGMA table_info({table})"` and `f"ALTER TABLE {table} ADD COLUMN {col} {col_type}"`. Mitigated by allowlist but still fragile. |
| **Database connection leaks** | `server.py` (get_menu, get_orders, get_sessions, get_employees, get_timecards, get_tables, get_modifiers_config) | `conn.close()` only called on success path. Exceptions leave connections open → `sqlite3.OperationalError: database is locked` under load. |

---

## 🟡 High Priority Issues

| Issue | Details |
|-------|---------|
| **No price validation** | Server accepts `total`/`price` from client without cross-checking against menu database. Malicious client can submit arbitrary amounts. |
| **Monolithic app.js** | 3,145 lines, all logic in one file/one class. No modularization. |
| **Missing requirements.txt** | Cannot reproduce Python venv. |
| **Dual-write inconsistency** | Writes SQLite first, then best-effort Supabase. If Supabase fails, data is out of sync with no alert. |
| **Cart state is in-memory only** | Page refresh loses cart (modifiers, quantities, notes). Only session token persists via localStorage. |
| **No retry on Supabase failure** | Errors logged via `print()` only — no retry, no alert mechanism. |
| **Native alert() for validation** | `app.js:3072,3121` — uses browser `alert()` instead of in-app toast system. Not localized, browser-dependent styling. |
| **TOCTOU race condition** | `handle_post_order` session auto-creation: two concurrent requests can create duplicate sessions (wasted UUIDs). |
| **Order total recalculation on item delete** | Proportional recalculation assumes linear relationship, breaks with non-linear tax/service charge. |

---

## 🔵 Medium Priority Issues

- **Magic numbers scattered throughout** — service charge 10%, VAT 7%, geofence 50m, polling 10s, timeout 5s, debounce 1.5s, etc.
- **Missing database indexes** — `modifiers.modifier_group_id`, `menu_item_modifier_groups.menu_item_id`, `order_item_modifiers.order_item_id`, `service_requests.merchant_id`
- **Supabase Realtime channels never unsubscribed** — `startStatusPolling` creates channels without cleanup → memory leak
- **i18n covers only 11 hardcoded items** — 50 seed menu items (`isan1-50`) have no translations in app.js
- **styles.css 2,922 lines** — contains unnecessary vendor prefixes, unused properties
- **Duplicate UUID generation logic** — same function written 3 times with slightly different fallback
- **Duplicate serviceKeyMap** — same object literal appears twice in `sendServiceRequest`
- **No scroll restoration** — switching tabs loses scroll position
- **No skeleton loading states** — menu renders without loading placeholders
- **Onboarding progress bar is fake** — animates to 100% regardless of actual async operations
- **Promotions not cached** — fetched from Supabase on every request; if Supabase is down, promotions are empty
- **Payment method normalization inconsistent** — SQLite gets `"Cash"`, Supabase gets `"cash"` (different casing)

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

1. **Remove production credentials from template files** (`.env.example`, `config.EXAMPLE.js`)
2. **Add server-side input validation** — verify prices against menu, clamp quantities, enforce string length limits
3. **Fix database connection leaks** — use `contextlib.closing()` or `try/finally` on all error paths
4. **Create `requirements.txt`** for reproducible Python environment
5. **Modularize `app.js`** — split into separate files (cart.js, menu.js, i18n.js, api.js, ui.js)
6. **Replace `alert()` calls** with in-app toast notification system
7. **Add proper error monitoring** — structured logging, retry logic for Supabase sync failures
8. **add database indexes** on frequently queried foreign key columns
9. **Unsubscribe Realtime channels** on session close / page unload
10. **Add payment gateway integration** for production readiness
