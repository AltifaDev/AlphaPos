"""
AlphaPos Customer Web — FastAPI Server
Replaces the monolithic http.server with modular async endpoints.

Run: uvicorn server_fastapi:app --host 0.0.0.0 --port 8080 --reload
Docs: http://localhost:8080/docs
"""
import os
import json
import sqlite3
import urllib.request
from contextlib import closing
from pathlib import Path

from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, Response

from api.deps import (
    DB_FILE, MERCHANT_ID, SUPABASE_URL, SUPABASE_ANON_KEY,
    API_AUTH_TOKEN, IS_PRODUCTION, ALLOWED_ORIGINS,
    get_db_connection, get_utc_now_iso, log_event
)
from api import menu, orders, payments, sessions, tables, staff, promotions, requests as svc_requests, sync, feedback, wait_time, merchants


# ==========================================
# App Instance
# ==========================================
app = FastAPI(
    title="AlphaPos Customer Web API",
    description="Multi-tenant restaurant POS — customer self-ordering backend",
    version="2.0.0",
    docs_url="/docs" if not IS_PRODUCTION else None,
    redoc_url=None,
)

# ==========================================
# CORS Middleware
# ==========================================
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS + ["*"] if not IS_PRODUCTION else ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
# Include API Routers
# ==========================================
app.include_router(menu.router)
app.include_router(orders.router)
app.include_router(payments.router)
app.include_router(sessions.router)
app.include_router(tables.router)
app.include_router(staff.router)
app.include_router(promotions.router)
app.include_router(svc_requests.router)
app.include_router(sync.router)
app.include_router(feedback.router)
app.include_router(wait_time.router)
app.include_router(merchants.router)


# ==========================================
# Dynamic config.js endpoint
# ==========================================
@app.get("/config.js")
def get_config_js():
    """Serve config.js — tries physical file first, falls back to dynamic generation."""
    config_path = Path(__file__).parent / "config.js"
    if config_path.exists():
        return FileResponse(config_path, media_type="application/javascript")

    js_content = f"""window.ALPHAPOS_CONFIG = {{
    supabaseUrl: '{SUPABASE_URL}',
    supabaseKey: '{SUPABASE_ANON_KEY}',
    merchantId: '{MERCHANT_ID}',
    apiAuthToken: '{API_AUTH_TOKEN if not IS_PRODUCTION else ""}',
    paymentProviders: {{
        promptpay: {str(bool(os.getenv("PROMPTPAY_ID", ""))).lower()},
        external: false
    }},
    isProduction: {str(IS_PRODUCTION).lower()}
}};"""
    return Response(content=js_content, media_type="application/javascript")


# ==========================================
# Startup: Init DB + Sync from Supabase
# ==========================================
@app.on_event("startup")
def startup_event():
    """Initialize SQLite database and sync from Supabase on startup."""
    init_db()
    log_event("info", "server.started", port=int(os.getenv("PORT", "8080")))


def init_db():
    """Create SQLite tables if they don't exist + seed defaults."""
    conn = get_db_connection()
    try:
        cursor = conn.cursor()

        cursor.execute('''CREATE TABLE IF NOT EXISTS orders (
            id TEXT PRIMARY KEY, order_number TEXT NOT NULL, table_number TEXT NOT NULL,
            total REAL NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL,
            updated_at TEXT, session_token TEXT, guest_count INTEGER DEFAULT 2,
            merchant_id TEXT, is_synced INTEGER DEFAULT 0
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS order_items (
            id TEXT PRIMARY KEY, order_id TEXT NOT NULL, item_name TEXT NOT NULL,
            quantity INTEGER NOT NULL, price REAL NOT NULL, status TEXT DEFAULT 'cooking',
            item_id TEXT, merchant_id TEXT, notes TEXT,
            FOREIGN KEY (order_id) REFERENCES orders (id)
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS menu_items (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
            price REAL NOT NULL, category TEXT NOT NULL, emoji TEXT,
            img_class TEXT, image_url TEXT,
            name_translations TEXT DEFAULT '{}', description_translations TEXT DEFAULT '{}'
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS table_sessions (
            id TEXT PRIMARY KEY, table_number TEXT NOT NULL, session_token TEXT NOT NULL,
            is_active INTEGER NOT NULL, created_at TEXT NOT NULL, ended_at TEXT,
            guest_count INTEGER DEFAULT 2, merchant_id TEXT
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS service_requests (
            id TEXT PRIMARY KEY, table_number TEXT NOT NULL, request_type TEXT NOT NULL,
            status TEXT DEFAULT 'pending', created_at TEXT NOT NULL, merchant_id TEXT
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS payments (
            id TEXT PRIMARY KEY, order_id TEXT NOT NULL, amount REAL NOT NULL,
            payment_method TEXT NOT NULL, created_at TEXT NOT NULL, merchant_id TEXT
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS restaurant_tables (
            id TEXT PRIMARY KEY, table_number TEXT NOT NULL, capacity INTEGER DEFAULT 4,
            status TEXT DEFAULT 'vacant', merchant_id TEXT, position_x REAL DEFAULT 0,
            position_y REAL DEFAULT 0, floor INTEGER DEFAULT 1
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS employees (
            id TEXT PRIMARY KEY, first_name TEXT, last_name TEXT, role TEXT,
            passcode_hash TEXT, merchant_id TEXT, is_active INTEGER DEFAULT 1
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS timecards (
            id TEXT PRIMARY KEY, employee_id TEXT, clock_in TEXT, clock_out TEXT, merchant_id TEXT
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS promotions (
            id TEXT PRIMARY KEY, title TEXT, promo_description TEXT, image_data TEXT,
            media_type TEXT DEFAULT 'image', is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0, updated_at TEXT
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS modifier_groups (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, selection_type TEXT DEFAULT 'single',
            min_selections INTEGER DEFAULT 0, max_selections INTEGER DEFAULT 1,
            sort_order INTEGER DEFAULT 0, is_available INTEGER DEFAULT 1,
            menu_item_ids TEXT DEFAULT '[]'
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS modifiers (
            id TEXT PRIMARY KEY, group_id TEXT, name TEXT NOT NULL,
            extra_price REAL DEFAULT 0, is_available INTEGER DEFAULT 1,
            is_default INTEGER DEFAULT 0, sort_order INTEGER DEFAULT 0
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS pending_supabase_writes (
            id TEXT PRIMARY KEY, endpoint TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS event_logs (
            id TEXT PRIMARY KEY, level TEXT, event TEXT, message TEXT, payload TEXT, created_at TEXT
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS merchants (
            id TEXT PRIMARY KEY, name TEXT, email TEXT, phone TEXT,
            is_table_system_enabled INTEGER DEFAULT 1,
            is_web_ordering_enabled INTEGER DEFAULT 1,
            branch_code TEXT,
            latitude REAL,
            longitude REAL,
            geofence_radius_meters INTEGER DEFAULT 50
        )''')

        cursor.execute('''CREATE TABLE IF NOT EXISTS customer_feedback (
            id TEXT PRIMARY KEY, merchant_id TEXT, order_id TEXT, table_number TEXT,
            session_token TEXT, overall_rating INTEGER, food_rating INTEGER,
            service_rating INTEGER, ambience_rating INTEGER,
            comment TEXT, customer_name TEXT, tags TEXT, created_at TEXT
        )''')

        conn.commit()

        # Catalog / tables / staff come from Supabase sync — no local demo seed.

        # Sync from Supabase
        _sync_from_supabase(conn)

    finally:
        conn.close()



def _sync_from_supabase(conn):
    """Best-effort sync from Supabase on startup."""
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        return

    try:
        # Sync menu items
        url = f"{SUPABASE_URL}/rest/v1/menu_items?select=*"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
        if data:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM menu_items")
            for item in data:
                name_trans = json.dumps(item.get("name_translations", {}))
                desc_trans = json.dumps(item.get("description_translations", {}))
                cursor.execute(
                    "INSERT OR REPLACE INTO menu_items (id, name, description, price, category, emoji, img_class, image_url, name_translations, description_translations) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (item.get("id"), item.get("name", ""), item.get("description", ""),
                     float(item.get("price", 0)), item.get("category", "mains"),
                     item.get("emoji", "🍽️"), item.get("img_class", ""),
                     item.get("image_url", ""), name_trans, desc_trans)
                )
            conn.commit()
            print(f"[Sync] ✅ {len(data)} menu items from Supabase")
    except Exception as e:
        print(f"[Sync] ⚠️ Menu sync failed: {e}")

    try:
        # Sync promotions
        url = f"{SUPABASE_URL}/rest/v1/promotions?select=*&is_deleted=eq.false"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
        if data:
            cursor = conn.cursor()
            for item in data:
                is_active = 1 if item.get("is_active", True) else 0
                cursor.execute(
                    "INSERT OR REPLACE INTO promotions (id, title, promo_description, image_data, media_type, is_active, is_deleted, updated_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?)",
                    (item.get("id"), item.get("title", ""), item.get("promo_description", ""),
                     item.get("image_data", ""), item.get("media_type", "image"),
                     is_active, item.get("updated_at", ""))
                )
            conn.commit()
            print(f"[Sync] ✅ {len(data)} promotions from Supabase")
    except Exception as e:
        print(f"[Sync] ⚠️ Promotions sync failed: {e}")


# ==========================================
# Static Files (must be last — catch-all)
# ==========================================
STATIC_DIR = Path(__file__).parent

BLOCKED_EXTENSIONS = {".db", ".sqlite", ".sql", ".env", ".plist", ".yaml", ".yml"}
BLOCKED_NAMES = {".env", ".git", ".htaccess", ".gitignore", "config.json", "server.py", "server_fastapi.py", "seed.py"}

MIME_TYPES = {
    ".html": "text/html", ".css": "text/css", ".js": "application/javascript",
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".ico": "image/x-icon", ".svg": "image/svg+xml", ".webp": "image/webp",
    ".woff2": "font/woff2", ".woff": "font/woff", ".json": "application/json",
}


@app.get("/{path:path}")
def serve_static(path: str):
    """Serve static files with security checks."""
    if not path or path == "/":
        path = "index.html"

    # Security
    if ".." in path or path.startswith("/"):
        raise HTTPException(status_code=403, detail="Access Denied")

    file_path = STATIC_DIR / path
    name = file_path.name
    suffix = file_path.suffix.lower()

    if suffix in BLOCKED_EXTENSIONS or name in BLOCKED_NAMES or name.startswith("."):
        raise HTTPException(status_code=403, detail="Access Denied")

    if not file_path.exists() or not file_path.is_file():
        raise HTTPException(status_code=404, detail="Not Found")

    media_type = MIME_TYPES.get(suffix, "application/octet-stream")
    return FileResponse(file_path, media_type=media_type)
