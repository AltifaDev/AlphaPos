import os
from seed import DEFAULT_EMPLOYEES, DEFAULT_MENU, get_default_tables

import sys
import json
import sqlite3
import urllib.parse
import urllib.request
import re
import time
import hmac
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import uuid
from datetime import datetime, timedelta
import hashlib
from dotenv import load_dotenv
from contextlib import closing

def sha256_hash(string):
    if not string:
        return ""
    return hashlib.sha256(string.encode('utf-8')).hexdigest()

# Load .env file if present
load_dotenv()

# Automatically change directory to the script's folder to prevent 404 File Not Found errors
script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir:
    os.chdir(script_dir)

PORT = int(os.getenv("PORT", "8080"))
DB_FILE = "alphapos.db"

# ==========================================
# Configuration (from environment variables)
# ==========================================
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

MERCHANT_ID = os.getenv("MERCHANT_ID", "")

# Allowed origins for CORS (comma-separated in env, defaults to localhost only)
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:8080,http://127.0.0.1:8080").split(",")

# Authentication token for API access (simple bearer token for local dev)
API_AUTH_TOKEN = os.getenv("API_AUTH_TOKEN", "")

# Production mode disables dev features (simulator panel, etc.)
IS_PRODUCTION = os.getenv("ALPHAPOS_ENV") == "production"

def sync_menu_from_supabase(conn):
    """
    Fetch menu items from Supabase (cloud master) and update local SQLite cache.
    - If Supabase is online: replace all local menu items with the latest from Supabase.
    - If Supabase is offline: silently skip (local SQLite data is used as fallback).
    """
    try:
        url = f"{SUPABASE_URL}/rest/v1/menu_items?select=*"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
        
        if not data:
            print("[Sync] Supabase returned 0 items — skipping SQLite update.")
            return
        
        cursor = conn.cursor()
        # Wipe existing menu items and replace with Supabase data
        cursor.execute("-- UPSERT used instead")
        for item in data:
            cursor.execute(
                "INSERT OR REPLACE INTO menu_items VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    item.get("id", str(uuid.uuid4())),
                    item.get("name", ""),
                    item.get("description", ""),
                    float(item.get("price", 0)),
                    item.get("category", "mains"),
                    item.get("emoji", "🍽️"),
                    item.get("img_class", "img-main"),
                    item.get("image_url", "")
                )
            )
        conn.commit()
        print(f"[Sync] ✅ Synced {len(data)} menu items from Supabase to SQLite.")
    
    except Exception as e:
        print(f"[Sync] ⚠️  Supabase offline or error — using local SQLite cache. ({e})")


def sync_promotions_from_supabase(conn):
    """
    Fetch promotions from Supabase (cloud master) and update local SQLite cache.
    - If Supabase is online: replace/update all local promotions with latest from Supabase.
    - If Supabase is offline: silently skip (local SQLite cache is used).
    """
    try:
        url = f"{SUPABASE_URL}/rest/v1/promotions?select=*"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
        
        if not data:
            print("[Sync] Supabase returned 0 promotions — skipping SQLite update.")
            return
        
        cursor = conn.cursor()
        for item in data:
            is_active = item.get("is_active", 1)
            if isinstance(is_active, bool):
                is_active = 1 if is_active else 0
            is_deleted = item.get("is_deleted", 0)
            if isinstance(is_deleted, bool):
                is_deleted = 1 if is_deleted else 0
                
            cursor.execute(
                "INSERT OR REPLACE INTO promotions (id, title, promo_description, image_data, is_active, is_deleted, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    item.get("id"),
                    item.get("title", ""),
                    item.get("promo_description", ""),
                    item.get("image_data", ""),
                    is_active,
                    is_deleted,
                    item.get("updated_at", "")
                )
            )
        conn.commit()
        print(f"[Sync] Successfully cached {len(data)} promotions from Supabase to SQLite.")
    except Exception as e:
        print(f"[Sync] ⚠️ Failed to sync promotions from Supabase: {str(e)}")


def fetch_promotions_from_supabase():
    """
    Fetch promotions directly from Supabase (cloud master).
    Returns list of promotion dicts, or empty list on failure.
    """
    try:
        url = f"{SUPABASE_URL}/rest/v1/promotions?select=*&is_deleted=eq.0"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
        
        return data if data else []
    except Exception as e:
        print(f"[Sync] ⚠️  Failed to fetch promotions from Supabase: {str(e)}")
        return []


def supabase_request(method, endpoint, payload=None, query_params=None):
    """
    Make a request to Supabase REST API.
    Returns (success, response_data) tuple.
    """
    try:
        url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
        if query_params:
            url += "?" + urllib.parse.urlencode(query_params)
        
        data_bytes = json.dumps(payload).encode("utf-8") if payload else None
        req = urllib.request.Request(url, data=data_bytes, method=method)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("Prefer", "return=minimal")
        req.add_header("x-merchant-id", MERCHANT_ID)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            return True, response.read().decode()
    except Exception as e:
        print(f"[Supabase] {method} {endpoint} failed: {str(e)}")
        return False, str(e)


def sync_table_sessions_from_supabase(conn):
    """
    Fetch table_sessions from Supabase (cloud master) and cache locally in SQLite.
    Called on server startup to sync guest count data.
    """
    try:
        print("[Sync] Fetching table_sessions from Supabase...")
        
        url = f"{SUPABASE_URL}/rest/v1/table_sessions?is_deleted=eq.false&limit=1000"
        
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            sessions_data = json.loads(response.read().decode())
        
        if not sessions_data:
            print("[Sync] No table_sessions returned from Supabase")
            return
        
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM table_sessions WHERE merchant_id = ?", (MERCHANT_ID,))
        
        for session in sessions_data:
            cursor.execute('''
                INSERT OR REPLACE INTO table_sessions 
                (id, table_number, session_token, is_active, created_at, ended_at, guest_count, merchant_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                session.get("id"),
                session.get("table_number", session.get("table_id", "")),
                session.get("session_token"),
                1 if session.get("is_active", True) else 0,
                session.get("started_at") or session.get("created_at"),
                session.get("ended_at"),
                session.get("guest_count", 1),
                session.get("merchant_id")
            ))
        
        conn.commit()
        print(f"[Sync] ✅ Cached {len(sessions_data)} table sessions from Supabase")
        
    except urllib.error.HTTPError as e:
        print(f"[Sync] ⚠️ HTTP {e.code}: {e.reason} - Supabase table_sessions offline")
        
    except Exception as e:
        print(f"[Sync] ⚠️ Failed to sync table_sessions: {str(e)}")


thread_local = threading.local()

def get_db_connection():
    conn = sqlite3.connect(DB_FILE)
    if not hasattr(thread_local, "connections"):
        thread_local.connections = []
    thread_local.connections.append(conn)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    return conn

def close_thread_connections():
    if hasattr(thread_local, "connections"):
        for conn in thread_local.connections:
            try:
                conn.close()
            except Exception:
                pass
        thread_local.connections.clear()


def _as_bool(value, default=True):
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value).strip().lower() not in ("0", "false", "no", "off")


def get_merchant_web_settings(merchant_id=None, branch_code=None):
    merchant_id = merchant_id or MERCHANT_ID
    branch_code = branch_code or ""
    fallback = {
        "is_table_system_enabled": True,
        "is_web_ordering_enabled": True,
    }

    try:
        with closing(get_db_connection()) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='merchants'")
            if not cursor.fetchone():
                return fallback

            clauses = []
            params = []
            if merchant_id:
                clauses.append("id = ?")
                params.append(merchant_id)
            if branch_code:
                clauses.append("branch_code = ?")
                params.append(branch_code)

            where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
            row = cursor.execute(
                "SELECT is_table_system_enabled, is_web_ordering_enabled FROM merchants"
                + where
                + " LIMIT 1",
                params
            ).fetchone()

            if not row and merchant_id and branch_code:
                row = cursor.execute(
                    "SELECT is_table_system_enabled, is_web_ordering_enabled FROM merchants WHERE id = ? LIMIT 1",
                    (merchant_id,)
                ).fetchone()

            if not row:
                return fallback

            return {
                "is_table_system_enabled": _as_bool(row["is_table_system_enabled"]),
                "is_web_ordering_enabled": _as_bool(row["is_web_ordering_enabled"]),
            }
    except Exception as e:
        print(f"[Merchant Settings] Falling back to enabled settings: {e}")
        return fallback


def web_ordering_enabled_for_payload(payload):
    settings = get_merchant_web_settings(
        payload.get("merchant_id") or payload.get("merchantId"),
        payload.get("branch_code") or payload.get("branchCode") or payload.get("branch")
    )
    return settings["is_table_system_enabled"] and settings["is_web_ordering_enabled"]


def sync_modifiers_from_supabase(conn):
    """
    Fetch modifier groups, modifiers, and menu item links from Supabase
    and cache them in the local SQLite database.
    """
    try:
        # A. Fetch modifier groups
        url = f"{SUPABASE_URL}/rest/v1/modifier_groups?select=*&is_deleted=eq.false"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        with urllib.request.urlopen(req, timeout=5) as response:
            groups = json.loads(response.read().decode()) or []
        
        # B. Fetch modifiers
        url = f"{SUPABASE_URL}/rest/v1/modifiers?select=*&is_deleted=eq.false"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        with urllib.request.urlopen(req, timeout=5) as response:
            mods = json.loads(response.read().decode()) or []

        # C. Fetch menu item modifier groups
        url = f"{SUPABASE_URL}/rest/v1/menu_item_modifier_groups?select=*&is_deleted=eq.false"
        req = urllib.request.Request(url)
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        with urllib.request.urlopen(req, timeout=5) as response:
            junctions = json.loads(response.read().decode()) or []

        cursor = conn.cursor()
        
        # 1. Update modifier_groups
        cursor.execute("-- UPSERT used instead")
        for g in groups:
            cursor.execute(
                "INSERT OR REPLACE INTO modifier_groups (id, name, min_selection, max_selection, merchant_id) VALUES (?, ?, ?, ?, ?)",
                (g.get("id"), g.get("name", ""), g.get("min_selection", 0), g.get("max_selection", 1), g.get("merchant_id"))
            )
            
        # 2. Update modifiers
        cursor.execute("-- UPSERT used instead")
        for m in mods:
            cursor.execute(
                "INSERT OR REPLACE INTO modifiers (id, modifier_group_id, name, extra_price, is_available, merchant_id) VALUES (?, ?, ?, ?, ?, ?)",
                (m.get("id"), m.get("modifier_group_id"), m.get("name", ""), float(m.get("extra_price", 0.0)), 1 if m.get("is_available", True) else 0, m.get("merchant_id"))
            )
            
        # 3. Update menu_item_modifier_groups
        cursor.execute("-- UPSERT used instead")
        for j in junctions:
            cursor.execute(
                "INSERT OR REPLACE INTO menu_item_modifier_groups (menu_item_id, modifier_group_id, merchant_id) VALUES (?, ?, ?)",
                (j.get("menu_item_id"), j.get("modifier_group_id"), j.get("merchant_id"))
            )
            
        conn.commit()
        print(f"[Sync] ✅ Synced modifiers: {len(groups)} groups, {len(mods)} modifiers, {len(junctions)} links.")
    except Exception as e:
        print(f"[Sync] ⚠️  Failed to sync modifiers from Supabase: {str(e)}")

def get_utc_now_iso():
    return datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

# Best-effort proxy to Supabase REST API (used for dual-write from local server)
def enqueue_supabase_write(endpoint, payload, last_error=""):
    try:
        with closing(get_db_connection()) as conn:
            with conn:
                conn.execute('''
                    INSERT INTO pending_supabase_writes (id, endpoint, payload, attempt_count, last_error, created_at, updated_at)
                    VALUES (?, ?, ?, 0, ?, ?, ?)
                ''', (
                    str(uuid.uuid4()),
                    endpoint,
                    json.dumps(payload, separators=(",", ":")),
                    str(last_error)[:500],
                    get_utc_now_iso(),
                    get_utc_now_iso()
                ))
    except Exception as queue_error:
        print(f"[Supabase Queue] Failed to enqueue {endpoint}: {queue_error}")


def supabase_post(endpoint, payload, queue_on_fail=True):
    try:
        if not SUPABASE_URL or not SUPABASE_ANON_KEY:
            raise RuntimeError("Supabase URL/key not configured")
        url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        req.add_header("Prefer", "resolution=merge-duplicates")
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.getcode() in (200, 201, 204)
    except Exception as e:
        print(f"[Supabase Proxy] POST {endpoint} failed: {e}")
        if queue_on_fail:
            enqueue_supabase_write(endpoint, payload, str(e))
        return False


def flush_pending_supabase_writes(limit=50):
    try:
        with closing(get_db_connection()) as conn:
            conn.row_factory = sqlite3.Row
            with conn:
                rows = conn.execute('''
                    SELECT * FROM pending_supabase_writes
                    ORDER BY created_at ASC
                    LIMIT ?
                ''', (limit,)).fetchall()

                for row in rows:
                    payload = json.loads(row["payload"])
                    success = supabase_post(row["endpoint"], payload, queue_on_fail=False)
                    if success:
                        conn.execute("DELETE FROM pending_supabase_writes WHERE id = ?", (row["id"],))
                    else:
                        conn.execute('''
                            UPDATE pending_supabase_writes
                            SET attempt_count = attempt_count + 1,
                                updated_at = ?
                            WHERE id = ?
                        ''', (get_utc_now_iso(), row["id"]))
                if rows:
                    print(f"[Supabase Queue] Processed {len(rows)} pending write(s).")
    except Exception as e:
        print(f"[Supabase Queue] Flush failed: {e}")

# ==========================================
# Database Setup & Seeding
# ==========================================
def init_db():
    conn = get_db_connection()
    try:
        _init_db_helper(conn)
    finally:
        conn.close()

def _init_db_helper(conn):
    cursor = conn.cursor()
    
    # 1. Orders table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS orders (
            id TEXT PRIMARY KEY,
            order_number TEXT NOT NULL,
            table_number TEXT NOT NULL,
            total REAL NOT NULL,
            status TEXT NOT NULL, -- 'preparing', 'ready', 'served', 'completed', 'cancelled'
            created_at TEXT NOT NULL,
            updated_at TEXT,
            session_token TEXT,
            guest_count INTEGER DEFAULT 2,
            merchant_id TEXT,
            is_synced INTEGER DEFAULT 0
        )
    ''')
    
    # 2. Order Items table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS order_items (
            id TEXT PRIMARY KEY,
            order_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            price REAL NOT NULL,
            status TEXT DEFAULT 'cooking',
            item_id TEXT,
            merchant_id TEXT,
            FOREIGN KEY (order_id) REFERENCES orders (id)
        )
    ''')
    
    # 3. Menu Items table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS menu_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            price REAL NOT NULL,
            category TEXT NOT NULL,
            emoji TEXT,
            img_class TEXT,
            image_url TEXT
        )
    ''')
    
    # Ensure image_url column exists in menu_items
    cursor.execute("PRAGMA table_info(menu_items)")
    columns = [col[1] for col in cursor.fetchall()]
    if 'image_url' not in columns:
        cursor.execute("ALTER TABLE menu_items ADD COLUMN image_url TEXT")

    # 4. Table Sessions table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS table_sessions (
            id TEXT PRIMARY KEY,
            table_number TEXT NOT NULL,
            session_token TEXT NOT NULL,
            is_active INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            ended_at TEXT,
            guest_count INTEGER DEFAULT 2,
            merchant_id TEXT
        )
    ''')

    # 5. Service Requests table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS service_requests (
            id TEXT PRIMARY KEY,
            table_number TEXT NOT NULL,
            request_type TEXT NOT NULL,
            status TEXT NOT NULL, -- 'pending', 'completed'
            created_at TEXT NOT NULL,
            merchant_id TEXT
        )
    ''')
    
    # 6. Employees table (sync with Supabase schema: pin_hash, not pin_code_hash)
    cursor.execute("PRAGMA table_info(employees)")
    employee_columns = {col[1] for col in cursor.fetchall()}
    if 'pin_code_hash' in employee_columns and 'pin_hash' not in employee_columns:
        cursor.execute("ALTER TABLE employees RENAME COLUMN pin_code_hash TO pin_hash")
        conn.commit()
        print("Database migration: pin_code_hash → pin_hash")
    elif 'pin_code' in employee_columns:
        cursor.execute("DROP TABLE employees")
        conn.commit()

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS employees (
            id TEXT PRIMARY KEY,
            first_name TEXT NOT NULL,
            last_name TEXT NOT NULL,
            phone TEXT,
            national_id TEXT,
            employment_type TEXT NOT NULL, -- 'hourly', 'monthly'
            pay_rate REAL NOT NULL,
            username TEXT NOT NULL,
            pin_hash TEXT NOT NULL DEFAULT '',
            role TEXT NOT NULL
        )
    ''')
    
    # 7. Timecards table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS timecards (
            id TEXT PRIMARY KEY,
            employee_id TEXT NOT NULL,
            employee_name TEXT NOT NULL,
            clock_in REAL NOT NULL,
            clock_out REAL,
            break_duration INTEGER DEFAULT 0,
            overtime_minutes INTEGER DEFAULT 0,
            status TEXT NOT NULL, -- 'approved', 'pending_audit', 'rejected'
            notes TEXT,
            clock_in_confidence REAL,
            clock_out_confidence REAL,
            merchant_id TEXT,
            FOREIGN KEY (employee_id) REFERENCES employees (id)
        )
    ''')
    
    # 8. Payments table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS payments (
            id TEXT PRIMARY KEY,
            order_id TEXT NOT NULL,
            amount REAL NOT NULL,
            payment_method TEXT NOT NULL,
            created_at TEXT NOT NULL,
            status TEXT DEFAULT 'completed',
            merchant_id TEXT,
            FOREIGN KEY (order_id) REFERENCES orders (id)
        )
    ''')
    
    # 9. Promotions table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS promotions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            promo_description TEXT,
            image_data TEXT,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT NOT NULL
        )
    ''')
    
    # 10. Modifier groups table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS modifier_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            min_selection INTEGER DEFAULT 0,
            max_selection INTEGER DEFAULT 1,
            merchant_id TEXT
        )
    ''')
    
    # 11. Modifiers table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS modifiers (
            id TEXT PRIMARY KEY,
            modifier_group_id TEXT,
            name TEXT NOT NULL,
            extra_price REAL DEFAULT 0.0,
            is_available INTEGER DEFAULT 1,
            merchant_id TEXT,
            FOREIGN KEY (modifier_group_id) REFERENCES modifier_groups (id)
        )
    ''')
    
    # 12. Menu item modifier groups junction
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS menu_item_modifier_groups (
            menu_item_id TEXT,
            modifier_group_id TEXT,
            merchant_id TEXT,
            PRIMARY KEY (menu_item_id, modifier_group_id),
            FOREIGN KEY (menu_item_id) REFERENCES menu_items (id),
            FOREIGN KEY (modifier_group_id) REFERENCES modifier_groups (id)
        )
    ''')
    
    # 13. Order item modifiers table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS order_item_modifiers (
            id TEXT PRIMARY KEY,
            order_item_id TEXT,
            modifier_id TEXT,
            price REAL,
            merchant_id TEXT,
            FOREIGN KEY (order_item_id) REFERENCES order_items (id),
            FOREIGN KEY (modifier_id) REFERENCES modifiers (id)
        )
    ''')
    
    # 14. Restaurant Tables table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS restaurant_tables (
            id TEXT PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            table_number TEXT NOT NULL,
            capacity INTEGER NOT NULL DEFAULT 2,
            status TEXT NOT NULL DEFAULT 'vacant',
            qr_code_identifier TEXT,
            position_x REAL NOT NULL DEFAULT 0.0,
            position_y REAL NOT NULL DEFAULT 0.0,
            floor INTEGER NOT NULL DEFAULT 1,
            is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
            is_round BOOLEAN NOT NULL DEFAULT FALSE,
            zone TEXT NOT NULL DEFAULT 'Indoor'
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS merchants (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            phone TEXT,
            currency TEXT DEFAULT 'THB',
            kitchen_workflow_required BOOLEAN DEFAULT FALSE,
            website TEXT,
            address_street TEXT,
            tax_id TEXT,
            branch_code TEXT,
            tax_rate REAL DEFAULT 0.00,
            tax_type TEXT DEFAULT 'exclusive',
            service_charge_rate REAL DEFAULT 0.00,
            receipt_header TEXT,
            receipt_footer TEXT,
            is_table_system_enabled BOOLEAN DEFAULT TRUE,
            is_web_ordering_enabled BOOLEAN DEFAULT TRUE
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS pending_supabase_writes (
            id TEXT PRIMARY KEY,
            endpoint TEXT NOT NULL,
            payload TEXT NOT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    ''')

    cursor.execute("SELECT COUNT(*) FROM restaurant_tables")
    if cursor.fetchone()[0] == 0:
        default_tables = get_default_tables(MERCHANT_ID)
        cursor.executemany("INSERT INTO restaurant_tables VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", default_tables)
        conn.commit()
        print("Database initialized and restaurant_tables seeded successfully.")
    
    # Migration: Add missing columns to existing tables (idempotent)
    for table, col, col_type in [
        ("orders", "merchant_id", "TEXT"),
        ("orders", "updated_at", "TEXT"),
        ("order_items", "merchant_id", "TEXT"),
        ("payments", "merchant_id", "TEXT"),
        ("table_sessions", "merchant_id", "TEXT"),
        ("service_requests", "merchant_id", "TEXT"),
        ("timecards", "merchant_id", "TEXT"),
        ("restaurant_tables", "zone", "TEXT"),
        ("merchants", "is_table_system_enabled", "BOOLEAN"),
        ("merchants", "is_web_ordering_enabled", "BOOLEAN"),
        ("merchants", "branch_code", "TEXT"),
    ]:
        allowed_tables = {"orders", "order_items", "payments", "table_sessions", "service_requests", "timecards", "employees", "menu_items", "promotions", "restaurant_tables", "merchants"}
        allowed_col_types = {"TEXT", "INTEGER", "REAL", "BOOLEAN"}
        allowed_cols = {"merchant_id", "updated_at", "zone", "is_table_system_enabled", "is_web_ordering_enabled", "branch_code"}
        if table not in allowed_tables:
            print(f"Database migration: Skipped unknown table '{table}'")
            continue
        if col_type not in allowed_col_types:
            print(f"Database migration: Skipped unknown column type '{col_type}'")
            continue
        if col not in allowed_cols:
            print(f"Database migration: Skipped unknown column name '{col}'")
            continue
        cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name=?", (table,))
        if not cursor.fetchone():
            continue  # Table doesn't exist yet (will be created by CREATE TABLE IF NOT EXISTS)
        # Use string formatting only after allowlist validation
        cursor.execute(f"PRAGMA table_info({table})")
        existing_cols = {col[1] for col in cursor.fetchall()}
        if col not in existing_cols:
            cursor.execute(f"ALTER TABLE {table} ADD COLUMN {col} {col_type}")
            print(f"Database migration: Added {col} to {table}")

    # Create Indexes
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_orders_table_created ON orders (table_number, created_at);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sessions_active ON table_sessions (table_number, is_active);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items (order_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_timecards_employee ON timecards (employee_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_payments_order ON payments (order_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_promotions_active ON promotions (is_active, is_deleted);")
    
    # Missing foreign key and merchant indexes
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_modifiers_group ON modifiers (modifier_group_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_menu_item_modifiers_item ON menu_item_modifier_groups (menu_item_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_order_item_modifiers_item ON order_item_modifiers (order_item_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_orders_merchant ON orders (merchant_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_service_requests_merchant ON service_requests (merchant_id);")
    
    conn.commit()

    # Seed default employees if table is empty
    cursor.execute("SELECT COUNT(*) FROM employees")
    if cursor.fetchone()[0] == 0:
        default_employees = DEFAULT_EMPLOYEES
        # Note: 10 columns matching CREATE TABLE (id, first_name, last_name, phone, national_id, employment_type, pay_rate, username, pin_hash, role)
        cursor.executemany("INSERT INTO employees VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", default_employees)
        conn.commit()
        print("Database employees seeded successfully.")


    # Alter table if existing schema is missing columns session_token or guest_count in orders
    cursor.execute("PRAGMA table_info(orders)")
    orders_columns = [col[1] for col in cursor.fetchall()]
    if 'session_token' not in orders_columns:
        cursor.execute("ALTER TABLE orders ADD COLUMN session_token TEXT")
    if 'guest_count' not in orders_columns:
        cursor.execute("ALTER TABLE orders ADD COLUMN guest_count INTEGER DEFAULT 2")
    
    # Alter table if existing schema is missing columns status or item_id in order_items
    cursor.execute("PRAGMA table_info(order_items)")
    columns = [col[1] for col in cursor.fetchall()]
    if 'status' not in columns:
        cursor.execute("ALTER TABLE order_items ADD COLUMN status TEXT DEFAULT 'cooking'")
    if 'item_id' not in columns:
        cursor.execute("ALTER TABLE order_items ADD COLUMN item_id TEXT")
    
    # Alter table if existing schema is missing columns guest_count in table_sessions
    cursor.execute("PRAGMA table_info(table_sessions)")
    session_columns = [col[1] for col in cursor.fetchall()]
    if 'guest_count' not in session_columns:
        cursor.execute("ALTER TABLE table_sessions ADD COLUMN guest_count INTEGER DEFAULT 2")
        
    conn.commit()

    # Seed default menu items if table is empty
    cursor.execute("SELECT COUNT(*) FROM menu_items")
    if cursor.fetchone()[0] == 0:
        default_menu = DEFAULT_MENU
        cursor.executemany("INSERT INTO menu_items VALUES (?, ?, ?, ?, ?, ?, ?, ?)", default_menu)
        conn.commit()
        print("Database initialized and Isan menu (50 items) seeded successfully.")
    
    # Always sync latest menu from Supabase on startup (single source of truth)
    sync_menu_from_supabase(conn)
    sync_table_sessions_from_supabase(conn)
    sync_promotions_from_supabase(conn)
    sync_modifiers_from_supabase(conn)
    flush_pending_supabase_writes()


# ==========================================
# Custom HTTP Request Handler
# ==========================================
class UnifiedRequestHandler(BaseHTTPRequestHandler):
    
    def handle(self):
        try:
            super().handle()
        finally:
            close_thread_connections()
    
    def _get_allowed_origin(self):
        origin = self.headers.get('Origin', '')
        if not origin:
            return ''
        for allowed in ALLOWED_ORIGINS:
            if origin.rstrip('/') == allowed.rstrip('/'):
                return origin
        return ''
    
    def _send_json_response(self, status_code, data):
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        body = json.dumps(data).encode("utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    
    def _send_error_json(self, status_code, message):
        self._send_json_response(status_code, {"error": message})
    
    def _require_auth(self):
        """Bearer token authentication for API endpoints. Required by default."""
        auth_header = self.headers.get('Authorization', '')
        if auth_header == f"Bearer {API_AUTH_TOKEN}":
            return True
        if not API_AUTH_TOKEN:
            # Dev mode: also allow from localhost without token
            client_host = self.client_address[0]
            if client_host in ('127.0.0.1', '::1', 'localhost'):
                return True
        self._send_error_json(401, "Unauthorized: invalid or missing API token")
        return False

    def _is_public_customer_post(self, path):
        return path in {"/v1/sessions/open", "/v1/orders", "/v1/requests"}
    
    def end_headers(self):
        allowed = self._get_allowed_origin()
        supabase_connect_src = ""
        if SUPABASE_URL:
            supabase_connect_src = (
                f" {SUPABASE_URL.rstrip('/')}"
                f" {SUPABASE_URL.rstrip('/').replace('https://', 'wss://').replace('http://', 'ws://')}"
            )
        if allowed:
            self.send_header('Access-Control-Allow-Origin', allowed)
            self.send_header('Vary', 'Origin')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With')
        self.send_header('Access-Control-Allow-Credentials', 'true')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')
        self.send_header('Referrer-Policy', 'strict-origin-when-cross-origin')
        self.send_header('Permissions-Policy', 'geolocation=(self), camera=(), microphone=()')
        self.send_header('Content-Security-Policy',
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://unpkg.com; "
            "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://fonts.googleapis.com; "
            "img-src 'self' data: https:; "
            f"connect-src 'self'{supabase_connect_src}; "
            "font-src 'self' data: https://fonts.gstatic.com; "
            "frame-ancestors 'none'")
        if not IS_PRODUCTION:
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_HEAD(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        path = parsed_path.path
        
        # GET endpoints are read-only / public data — no auth required.
        # Auth is enforced on POST (write) endpoints.
        
        # 1. API Endpoint: GET /v1/menu
        if path == "/v1/menu":
            self.handle_get_menu()
            return
            
        # 2. API Endpoint: GET /v1/orders (Returns list of orders for POS/KDS syncing)
        if path == "/v1/orders":
            self.handle_get_orders()
            return

        # 3. API Endpoint: GET /v1/requests (Returns active service requests)
        if path == "/v1/requests":
            self.handle_get_requests()
            return

        # 4. API Endpoint: GET /v1/sessions
        if path == "/v1/sessions":
            self.handle_get_sessions()
            return

        # 5. API Endpoint: GET /v1/tables
        if path == "/v1/tables":
            self.handle_get_tables()
            return

        # 6. API Endpoint: GET /v1/employees
        if path == "/v1/employees":
            self.handle_get_employees()
            return

        # 7. API Endpoint: GET /v1/timecards
        if path == "/v1/timecards":
            self.handle_get_timecards()
            return

        # 7.5. API Endpoint: GET /v1/merchants
        if path == "/v1/merchants":
            self.handle_get_merchants()
            return

        # 8. API Endpoint: GET /v1/sync
        if path == "/v1/sync":
            self.handle_get_sync()
            return

        if path == "/v1/sync/status":
            self.handle_get_sync_status()
            return

        # 9. API Endpoint: GET /v1/promotions
        if path == "/v1/promotions":
            self.handle_get_promotions()
            return
            
        # 9.5. API Endpoint: GET /v1/modifiers-config
        if path == "/v1/modifiers-config":
            self.handle_get_modifiers_config()
            return

        # Serve config.js dynamically from environment variables
        if path == "/config.js":
            self.handle_get_config_js()
            return

        # 10. Default: Serve static files
        self.handle_static_files(path)

    def do_POST(self):
        parsed_path = urllib.parse.urlparse(self.path)
        path = parsed_path.path
        
        # Customer self-ordering writes are public by design; admin/POS writes still require auth.
        if not self._is_public_customer_post(path) and not self._require_auth():
            return
        
        # 0. API Endpoint: POST /v1/employees/verify (Verifies employee PIN hash)
        if path == "/v1/employees/verify":
            self.handle_post_employee_verify()
            return

        # 1. API Endpoint: POST /v1/orders (Submits new orders from Mobile or iPad POS)
        if path == "/v1/orders":
            self.handle_post_order()
            return
            
        # 2. API Endpoint: POST /v1/payments (Simulates uploading POS payments)
        if path == "/v1/payments":
            self.handle_post_payment()
            return

        # 2b. API Endpoint: POST /v1/timecards (Clock-in / Clock-out)
        if path == "/v1/timecards":
            self.handle_post_timecard()
            return


        # 3. API Endpoint: POST /v1/sessions/open (Creates or resumes session)
        if path == "/v1/sessions/open":
            self.handle_open_session()
            return

        # 4. API Endpoint: POST /v1/sessions/close (Closes session)
        if path == "/v1/sessions/close":
            self.handle_close_session()
            return

        # 5. API Endpoint: POST /v1/requests (Creates staff request)
        if path == "/v1/requests":
            self.handle_post_request()
            return

        # 6. API Endpoint: POST /v1/requests/complete or POST /v1/requests/<id>/complete
        if path == "/v1/requests/complete":
            self.handle_post_request_complete_payload()
            return
            
        if path.startswith("/v1/requests/") and path.endswith("/complete"):
            parts = path.split("/")
            if len(parts) >= 5:
                req_id = parts[3]
                self.handle_complete_request(req_id)
                return

        # 6b. API Endpoint: POST /v1/orders/items/delete
        if path == "/v1/orders/items/delete":
            self.handle_delete_order_item()
            return

        # 7. API Endpoint: POST /v1/promotions (Upserts a promotion)
        if path == "/v1/promotions":
            self.handle_post_promotion()
            return

        # 8. API Endpoint: POST /v1/promotions/delete (Deletes a promotion)
        if path == "/v1/promotions/delete":
            self.handle_delete_promotion()
            return

        if path == "/v1/sync/retry":
            self.handle_post_sync_retry()
            return

        self.send_error(404, "Endpoint not found")

    # ==========================================
    # Endpoint Handlers
    # ==========================================

    def handle_get_sync_status(self):
        try:
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                row = conn.execute('''
                    SELECT
                        COUNT(*) AS pending_count,
                        COALESCE(MAX(attempt_count), 0) AS max_attempts,
                        MIN(created_at) AS oldest_created_at,
                        MAX(updated_at) AS last_attempt_at
                    FROM pending_supabase_writes
                ''').fetchone()
                by_endpoint_rows = conn.execute('''
                    SELECT endpoint, COUNT(*) AS count
                    FROM pending_supabase_writes
                    GROUP BY endpoint
                    ORDER BY count DESC, endpoint ASC
                ''').fetchall()

                self._send_json_response(200, {
                    "pendingCount": row["pending_count"],
                    "maxAttempts": row["max_attempts"],
                    "oldestCreatedAt": row["oldest_created_at"],
                    "lastAttemptAt": row["last_attempt_at"],
                    "byEndpoint": [
                        {"endpoint": item["endpoint"], "count": item["count"]}
                        for item in by_endpoint_rows
                    ]
                })
        except Exception as e:
            self._send_error_json(500, f"Sync status error: {str(e)}")

    def handle_post_sync_retry(self):
        try:
            flush_pending_supabase_writes(limit=100)
            self.handle_get_sync_status()
        except Exception as e:
            self._send_error_json(500, f"Sync retry error: {str(e)}")
    
    def handle_get_menu(self):
        try:
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM menu_items")
                rows = cursor.fetchall()
                
                menu = []
                for row in rows:
                    menu.append({
                        "id": row["id"],
                        "name": row["name"],
                        "desc": row["description"],
                        "price": row["price"],
                        "category": row["category"],
                        "emoji": row["emoji"],
                        "imgClass": row["img_class"],
                        "image_url": row["image_url"] if "image_url" in row.keys() else ""
                    })
                
                response_data = json.dumps(menu).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")

    def handle_get_orders(self):
        try:
            parsed_path = urllib.parse.urlparse(self.path)
            query_params = urllib.parse.parse_qs(parsed_path.query)
            table_number = query_params.get("table", [None])[0]
            token = query_params.get("token", [None])[0]
            
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                
                if table_number and token:
                    # Find start time of active session
                    cursor.execute("""
                        SELECT created_at FROM table_sessions 
                        WHERE table_number = ? AND session_token = ? AND is_active = 1
                    """, (table_number, token))
                    session_row = cursor.fetchone()
                    
                    if session_row:
                        session_start = session_row["created_at"]
                        # Fetch orders for this table session
                        cursor.execute("""
                            SELECT * FROM orders 
                            WHERE table_number = ? AND created_at >= ?
                            ORDER BY created_at ASC
                        """, (table_number, session_start))
                        order_rows = cursor.fetchall()
                    else:
                        order_rows = []
                else:
                    # Fetch preparing kitchen orders + all orders belonging to active table sessions for POS/KDS sync
                    cursor.execute("""
                        SELECT DISTINCT o.* FROM orders o
                        LEFT JOIN table_sessions ts ON o.table_number = ts.table_number AND ts.is_active = 1
                        WHERE o.status IN ('preparing', 'ready')
                           OR (ts.is_active = 1 AND o.created_at >= ts.created_at)
                        ORDER BY o.created_at DESC
                    """)
                    order_rows = cursor.fetchall()

                    
                orders = []
                for order_row in order_rows:
                    order_id = order_row["id"]
                    
                    cursor.execute("SELECT * FROM order_items WHERE order_id = ?", (order_id,))
                    item_rows = cursor.fetchall()
                    
                    items = []
                    for item_row in item_rows:
                        items.append({
                            "id": item_row["id"],
                            "name": item_row["item_name"],
                            "quantity": item_row["quantity"],
                            "price": item_row["price"],
                            "status": item_row["status"],
                            "item_id": item_row["item_id"]
                        })
                    
                    # Fetch payments for this order
                    cursor.execute("SELECT * FROM payments WHERE order_id = ?", (order_id,))
                    payment_rows = cursor.fetchall()
                    payments = []
                    for p_row in payment_rows:
                        payments.append({
                            "id": p_row["id"],
                            "orderId": p_row["order_id"],
                            "amount": p_row["amount"],
                            "paymentMethod": p_row["payment_method"],
                            "createdAt": p_row["created_at"]
                        })
                    
                    orders.append({
                        "id": order_row["id"],
                        "orderNumber": order_row["order_number"],
                        "tableNumber": order_row["table_number"],
                        "total": order_row["total"],
                        "status": order_row["status"],
                        "createdAt": order_row["created_at"],
                        "items": items,
                        "payments": payments
                    })
                    
                response_data = json.dumps(orders).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")

    def handle_post_order(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        try:
            order_data = json.loads(post_data.decode("utf-8"))
            if not web_ordering_enabled_for_payload(order_data):
                self._send_error_json(403, "Web ordering is disabled for this store or branch.")
                return
            
            # Extract and sanitize fields
            table_number = str(order_data.get("tableNumber") or order_data.get("table_number") or "1")[:10]
            total_client = float(order_data.get("total", 0.0))
            items = order_data.get("items", [])
            order_id = str(order_data.get("id") or str(uuid.uuid4()))[:50]
            status = str(order_data.get("status") or "preparing")[:20]
            allowed_order_statuses = {"preparing", "ready", "served", "cancelled"}
            if status not in allowed_order_statuses:
                raise ValueError(f"Invalid order status '{status}'.")
            session_token = order_data.get("sessionToken") or order_data.get("session_token")
            session_token = str(session_token)[:50] if session_token else None
            guest_count = int(order_data.get("guestCount") or order_data.get("guest_count") or 2)
            guest_count = max(1, min(guest_count, 100))
            if not isinstance(items, list) or not items:
                raise ValueError("Order must contain at least one item.")
            
            # Generate clean invoice number (e.g. ORD-6401)
            order_number = str(order_data.get("orderNumber") or order_data.get("order_number") or f"ORD-{str(uuid.uuid4().int)[:4]}")[:20]
            created_at_str = get_utc_now_iso()
            
            with closing(get_db_connection()) as conn:
                with conn:
                    cursor = conn.cursor()
                    
                    # Recalculate and validate prices on the server side
                    computed_subtotal = 0.0
                    verified_items = []
                    
                    for item in items:
                        menu_item_id = item.get("item_id") or item.get("id")
                        menu_item_id = str(menu_item_id)[:50] if menu_item_id else None
                        
                        qty = int(item.get("quantity") or item.get("qty", 1))
                        qty = max(1, min(qty, 99))  # Clamp quantity
                        
                        # Fetch menu data from local DB strictly
                        base_price = 0.0
                        menu_item_name = "Unknown Dish"
                        if menu_item_id:
                            cursor.execute("SELECT name, price FROM menu_items WHERE id = ?", (menu_item_id,))
                            row = cursor.fetchone()
                            if row:
                                menu_item_name = str(row[0])
                                base_price = float(row[1])
                            else:
                                raise ValueError(f"Menu item '{menu_item_id}' not found in database.")
                        else:
                            raise ValueError("item_id is required for all ordered items.")
                        
                        # Fetch modifiers prices
                        item_modifiers = item.get("modifiers", [])
                        verified_modifiers = []
                        modifier_price_sum = 0.0
                        
                        for mod in item_modifiers:
                            mod_id = mod.get("modifier_id") or mod.get("id")
                            mod_id = str(mod_id)[:50] if mod_id else None
                            
                            mod_price = 0.0
                            if mod_id:
                                cursor.execute("SELECT extra_price FROM modifiers WHERE id = ? AND is_available = 1", (mod_id,))
                                mod_row = cursor.fetchone()
                                if mod_row:
                                    mod_price = float(mod_row[0])
                                else:
                                    cursor.execute("SELECT extra_price FROM modifiers WHERE (name = ? OR id = ?) AND is_available = 1", (mod.get("name", ""), mod_id))
                                    mod_row2 = cursor.fetchone()
                                    if mod_row2:
                                        mod_price = float(mod_row2[0])
                                    else:
                                        raise ValueError(f"Modifier '{mod_id}' not found or unavailable in database.")
                            else:
                                raise ValueError("modifier_id is required for all selected modifiers.")
                            
                            modifier_price_sum += mod_price
                            verified_modifiers.append({
                                "id": str(mod.get("id") or str(uuid.uuid4()))[:50],
                                "modifier_id": mod_id,
                                "price": mod_price
                            })
                        
                        computed_item_price = base_price + modifier_price_sum
                        computed_subtotal += computed_item_price * qty
                        
                        verified_items.append({
                            "id": str(item.get("id") or str(uuid.uuid4()))[:50],
                            "item_id": menu_item_id,
                            "name": menu_item_name[:100],
                            "quantity": qty,
                            "price": computed_item_price,
                            "status": str(item.get("status") or "cooking")[:20],
                            "modifiers": verified_modifiers
                        })
                    
                    # Recalculate totals
                    computed_service_charge = computed_subtotal * 0.10
                    computed_tax = (computed_subtotal + computed_service_charge) * 0.07
                    computed_total = computed_subtotal + computed_service_charge + computed_tax
                    if abs(total_client - computed_total) > 0.05:
                        raise ValueError(
                            f"Order total mismatch. Client sent {total_client:.2f}, server calculated {computed_total:.2f}."
                        )
                    
                    total = computed_total
                    items = verified_items
                    
                    # Check if there is an active session for this table
                    cursor.execute("SELECT session_token FROM table_sessions WHERE table_number = ? AND is_active = 1", (table_number,))
                    session_row = cursor.fetchone()
                    if not session_row:
                        # No active session exists on the server! Auto-create one.
                        session_token = str(uuid.uuid4())
                        session_id = str(uuid.uuid4())
                        sess_created_at = (datetime.utcnow() - timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
                        
                        cursor.execute('''
                            INSERT INTO table_sessions (id, table_number, session_token, is_active, created_at, guest_count, merchant_id)
                            VALUES (?, ?, ?, 1, ?, ?, ?)
                        ''', (session_id, table_number, session_token, sess_created_at, 2, MERCHANT_ID))
                        cursor.execute('''
                            UPDATE restaurant_tables SET status = 'occupied' WHERE table_number = ? AND merchant_id = ?
                        ''', (table_number, MERCHANT_ID))
                        print(f"Server API [Order Auto-Session]: Opened active session for Table {table_number} (Token: {session_token[:8]}...)")
                    
                    # Check if order already exists
                    cursor.execute("SELECT id FROM orders WHERE id = ?", (order_id,))
                    exists = cursor.fetchone()
                    
                    if exists:
                        # Update Order
                        updated_at_str = get_utc_now_iso()
                        cursor.execute('''
                            UPDATE orders 
                            SET status = ?, total = ?, updated_at = ?, session_token = COALESCE(?, session_token), guest_count = ?, is_synced = 0
                            WHERE id = ?
                        ''', (status, total, updated_at_str, session_token, guest_count, order_id))
                        
                        # Upsert Order Items
                        for item in items:
                            client_id = item.get("id")
                            menu_item_id = item.get("item_id") or client_id
                            name = item.get("name")
                            qty = item.get("quantity")
                            price = item.get("price")
                            item_status = item.get("status")
                            
                            # Look for existing item *only* within this specific order
                            item_exists = None
                            if client_id:
                                cursor.execute("SELECT id FROM order_items WHERE (id = ? OR item_id = ?) AND order_id = ?", (client_id, client_id, order_id))
                                item_exists = cursor.fetchone()
                            
                            if not item_exists and menu_item_id:
                                cursor.execute("SELECT id FROM order_items WHERE item_id = ? AND order_id = ?", (menu_item_id, order_id))
                                item_exists = cursor.fetchone()
                                
                            if item_exists:
                                cursor.execute('''
                                    UPDATE order_items 
                                    SET quantity = ?, price = ?, status = ?
                                    WHERE id = ?
                                ''', (qty, price, item_status, item_exists[0]))
                                db_id = item_exists[0]
                            else:
                                new_item_id = str(uuid.uuid4())
                                cursor.execute('''
                                    INSERT INTO order_items (id, order_id, item_name, quantity, price, status, item_id, merchant_id)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                                ''', (new_item_id, order_id, name, qty, price, item_status, menu_item_id, MERCHANT_ID))
                                db_id = new_item_id
                                
                            # Delete and recreate modifiers for this item
                            cursor.execute("DELETE FROM order_item_modifiers WHERE order_item_id = ?", (db_id,))
                            item_modifiers = item.get("modifiers", [])
                            for mod in item_modifiers:
                                mod_id = mod.get("modifier_id")
                                mod_price = mod.get("price")
                                if mod_id:
                                    mod_db_id = str(uuid.uuid4())
                                    cursor.execute('''
                                        INSERT INTO order_item_modifiers (id, order_item_id, modifier_id, price, merchant_id)
                                        VALUES (?, ?, ?, ?, ?)
                                    ''', (mod_db_id, db_id, mod_id, mod_price, MERCHANT_ID))
                    else:
                        # Insert New Order
                        updated_at_str = get_utc_now_iso()
                        cursor.execute('''
                            INSERT INTO orders (id, order_number, table_number, total, status, created_at, updated_at, session_token, guest_count, merchant_id, is_synced)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ''', (order_id, order_number, table_number, total, status, created_at_str, updated_at_str, session_token, guest_count, MERCHANT_ID, 0))
                        
                        # Insert Order Items
                        for item in items:
                            client_id = item.get("id")
                            menu_item_id = item.get("item_id")
                            name = item.get("name")
                            qty = item.get("quantity")
                            price = item.get("price")
                            item_status = item.get("status")
                            
                            db_id = client_id or str(uuid.uuid4())
                            cursor.execute('''
                                INSERT INTO order_items (id, order_id, item_name, quantity, price, status, item_id, merchant_id)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            ''', (db_id, order_id, name, qty, price, item_status, menu_item_id, MERCHANT_ID))
                            
                            # Insert Order Item Modifiers
                            item_modifiers = item.get("modifiers", [])
                            for mod in item_modifiers:
                                mod_id = mod.get("modifier_id")
                                mod_price = mod.get("price")
                                if mod_id:
                                    mod_db_id = str(uuid.uuid4())
                                    cursor.execute('''
                                        INSERT INTO order_item_modifiers (id, order_item_id, modifier_id, price, merchant_id)
                                        VALUES (?, ?, ?, ?, ?)
                                    ''', (mod_db_id, db_id, mod_id, mod_price, MERCHANT_ID))
            
            # Best-effort dual-write to Supabase (so POS apps can see this order)
            supabase_order = {
                "id": order_id,
                "order_number": order_number,
                "table_number": table_number,
                "total": total,
                "status": status,
                "created_at": created_at_str,
                "updated_at": get_utc_now_iso(),
                "merchant_id": MERCHANT_ID,
                "session_token": session_token,
                "guest_count": guest_count
            }
            order_synced = supabase_post("orders", supabase_order)
            if order_synced:
                with closing(get_db_connection()) as conn:
                    with conn:
                        conn.execute("UPDATE orders SET is_synced = 1 WHERE id = ?", (order_id,))
            for item in items:
                item_id_db = item.get("id")
                supabase_item = {
                    "id": item_id_db,
                    "order_id": order_id,
                    "item_name": item.get("name"),
                    "quantity": item.get("quantity"),
                    "price": item.get("price"),
                    "status": item.get("status"),
                    "item_id": item.get("item_id"),
                    "merchant_id": MERCHANT_ID
                }
                supabase_post("order_items", supabase_item)
                
                # Dual-write modifiers to Supabase
                item_modifiers = item.get("modifiers", [])
                for mod in item_modifiers:
                    mod_id = mod.get("modifier_id")
                    mod_price = mod.get("price")
                    if mod_id:
                        supabase_mod = {
                            "id": str(uuid.uuid4()),
                            "order_item_id": item_id_db,
                            "modifier_id": mod_id,
                            "price": mod_price,
                            "merchant_id": MERCHANT_ID
                        }
                        supabase_post("order_item_modifiers", supabase_mod)
            
            # Response success
            response = {
                "success": True,
                "orderId": order_id,
                "orderNumber": order_number,
                "total": round(total, 2),
                "message": "Order successfully created/updated."
            }
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(response).encode("utf-8"))
            print(f"Server API [Order]: Saved/Updated {order_number} for Table {table_number} (Total: ฿{total}, Status: {status})")
            
        except Exception as e:
            self._send_error_json(400, f"Invalid order payload: {str(e)}")

    def handle_post_payment(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            pay_data = json.loads(post_data.decode("utf-8"))
            pay_id = pay_data.get("id") or str(uuid.uuid4())
            order_id = pay_data.get("order_id")
            amount = float(pay_data.get("amount", 0.0))
            method = pay_data.get("payment_method") or pay_data.get("method") or "Cash"
            created_at = get_utc_now_iso()
            
            # Normalise method to match iPad display strings
            if method.lower() == "cash":
                method = "Cash"
            elif method.lower() in ("qr", "qr promptpay", "promptpay qr", "promptpay"):
                method = "QR PromptPay"
            elif method.lower() in ("card", "credit card", "credit_card"):
                method = "Credit Card"
                
            if not order_id:
                raise ValueError("order_id is required.")
            if amount <= 0:
                raise ValueError("Payment amount must be greater than zero.")

            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT id FROM orders WHERE id = ?", (order_id,))
                if not cursor.fetchone():
                    raise ValueError(f"Order '{order_id}' not found.")

                cursor.execute('''
                    INSERT OR REPLACE INTO payments (id, order_id, amount, payment_method, created_at, merchant_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (pay_id, order_id, amount, method, created_at, MERCHANT_ID))
                conn.commit()
            
            # Best-effort dual-write to Supabase
            supabase_post("payments", {
                "id": pay_id,
                "order_id": order_id,
                "amount": amount,
                "payment_method": method.lower().replace(" ", "_"),
                "created_at": created_at,
                "status": "completed",
                "merchant_id": MERCHANT_ID
            })
            
            print(f"Server API [Payment]: Confirmed and saved payment of ฿{amount} via {method} for Order ID: {order_id}")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True}).encode("utf-8"))
        except Exception as e:
            self.send_error(400, f"Error saving payment: {str(e)}")

    def handle_get_sessions(self):
        try:
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                if MERCHANT_ID:
                    cursor.execute("SELECT * FROM table_sessions WHERE is_active = 1 AND merchant_id = ?", (MERCHANT_ID,))
                else:
                    cursor.execute("SELECT * FROM table_sessions WHERE is_active = 1")
                rows = cursor.fetchall()
                
                sessions = []
                for row in rows:
                    sessions.append({
                        "id": row["id"],
                        "tableNumber": row["table_number"],
                        "sessionToken": row["session_token"],
                        "createdAt": row["created_at"],
                        "guestCount": row["guest_count"]
                    })
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(sessions).encode("utf-8"))
        except Exception as e:
            self.send_error(500, f"Error fetching sessions: {str(e)}")

    def handle_open_session(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            data = json.loads(post_data.decode("utf-8"))
            if not web_ordering_enabled_for_payload(data):
                self._send_error_json(403, "Web ordering is disabled for this store or branch.")
                return
            table_number = str(data.get("table_number") or data.get("tableNumber") or "")
            guest_count = int(data.get("guest_count") or data.get("guestCount") or 2)
            if not table_number:
                self.send_error(400, "table_number is required")
                return
            
            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                
                # Check if there is an active session
                cursor.execute("SELECT session_token FROM table_sessions WHERE table_number = ? AND is_active = 1", (table_number,))
                row = cursor.fetchone()
                if row:
                    session_token = row[0]
                else:
                    session_token = str(uuid.uuid4())
                    session_id = str(uuid.uuid4())
                    created_at = get_utc_now_iso()
                    cursor.execute('''
                        INSERT INTO table_sessions (id, table_number, session_token, is_active, created_at, guest_count, merchant_id)
                        VALUES (?, ?, ?, 1, ?, ?, ?)
                    ''', (session_id, table_number, session_token, created_at, guest_count, MERCHANT_ID))
                    cursor.execute('''
                        UPDATE restaurant_tables SET status = 'occupied' WHERE table_number = ? AND merchant_id = ?
                    ''', (table_number, MERCHANT_ID))
                    conn.commit()
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "success": True,
                "session_token": session_token,
                "table_number": table_number
            }).encode("utf-8"))
            print(f"Server API [Session]: Opened/Resumed session for Table {table_number} with {guest_count} guests (Token: {session_token[:8]}...)")
        except Exception as e:
            self.send_error(500, f"Error opening session: {str(e)}")

    def handle_close_session(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            data = json.loads(post_data.decode("utf-8"))
            table_number = str(data.get("table_number") or data.get("tableNumber") or "")
            if not table_number:
                self.send_error(400, "table_number is required")
                return
            
            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                
                ended_at = get_utc_now_iso()
                cursor.execute('''
                    UPDATE table_sessions 
                    SET is_active = 0, ended_at = ?
                    WHERE table_number = ? AND is_active = 1
                ''', (ended_at, table_number))
                cursor.execute('''
                    UPDATE restaurant_tables SET status = 'vacant' WHERE table_number = ? AND merchant_id = ?
                ''', (table_number, MERCHANT_ID))
                conn.commit()
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True}).encode("utf-8"))
            print(f"Server API [Session]: Closed session for Table {table_number}")
        except Exception as e:
            self.send_error(500, f"Error closing session: {str(e)}")

    def handle_post_request(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            data = json.loads(post_data.decode("utf-8"))
            if not web_ordering_enabled_for_payload(data):
                self._send_error_json(403, "Web ordering is disabled for this store or branch.")
                return
            table_number = str(data.get("table_number") or data.get("tableNumber") or "")
            request_type = str(data.get("request_type") or data.get("requestType") or "")
            if not table_number or not request_type:
                self.send_error(400, "table_number and request_type are required")
                return
            
            req_id = str(uuid.uuid4())
            created_at = get_utc_now_iso()
            
            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                cursor.execute('''
                    INSERT INTO service_requests (id, table_number, request_type, status, created_at, merchant_id)
                    VALUES (?, ?, ?, 'pending', ?, ?)
                ''', (req_id, table_number, request_type, created_at, MERCHANT_ID))
                conn.commit()
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "id": req_id}).encode("utf-8"))
            print(f"Server API [Request]: New request from Table {table_number}: {request_type}")
        except Exception as e:
            self.send_error(500, f"Error posting service request: {str(e)}")

    def handle_get_requests(self):
        try:
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM service_requests WHERE status = 'pending' ORDER BY created_at ASC")
                rows = cursor.fetchall()
                
                reqs = []
                for row in rows:
                    reqs.append({
                        "id": row["id"],
                        "tableNumber": row["table_number"],
                        "requestType": row["request_type"],
                        "status": row["status"],
                        "createdAt": row["created_at"]
                    })
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(reqs).encode("utf-8"))
        except Exception as e:
            self.send_error(500, f"Error fetching service requests: {str(e)}")

    def handle_post_request_complete_payload(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            data = json.loads(post_data.decode("utf-8"))
            req_id = data.get("id") or data.get("request_id")
            if not req_id:
                self.send_error(400, "id is required")
                return
            self.handle_complete_request(req_id)
        except Exception as e:
            self.send_error(500, f"Error completing request: {str(e)}")

    def handle_complete_request(self, req_id):
        try:
            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                cursor.execute("UPDATE service_requests SET status = 'completed' WHERE id = ?", (req_id,))
                conn.commit()
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True}).encode("utf-8"))
            print(f"Server API [Request]: Completed request {req_id}")
        except Exception as e:
            self.send_error(500, f"Error completing request: {str(e)}")

    def handle_delete_order_item(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            data = json.loads(post_data.decode("utf-8"))
            order_item_id = data.get("order_item_id") or data.get("itemId") or data.get("id")
            if not order_item_id:
                self.send_error(400, "order_item_id is required")
                return
            
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                
                # Find the item's order_id and pricing details to recalculate total
                cursor.execute("SELECT order_id, price, quantity FROM order_items WHERE id = ?", (order_item_id,))
                row = cursor.fetchone()
                if not row:
                    self.send_error(404, "Order item not found")
                    return
                
                order_id = row["order_id"]
                
                # Delete order item
                cursor.execute("DELETE FROM order_items WHERE id = ?", (order_item_id,))
                
                # Recalculate order total
                cursor.execute("SELECT SUM(price * quantity) FROM order_items WHERE order_id = ?", (order_id,))
                remaining_subtotal = cursor.fetchone()[0] or 0.0
                
                if remaining_subtotal == 0:
                    # No items left, delete the order entirely
                    cursor.execute("DELETE FROM orders WHERE id = ?", (order_id,))
                    conn.commit()
                    print(f"Server API [Order Item]: Deleted order item {order_item_id}. Order {order_id} has no items left and was deleted.")
                else:
                    # Get old total
                    cursor.execute("SELECT total FROM orders WHERE id = ?", (order_id,))
                    old_total = cursor.fetchone()[0] or 0.0
                    
                    # We calculate old subtotal as remaining_subtotal + deleted_item_subtotal
                    deleted_subtotal = float(row["price"]) * int(row["quantity"])
                    old_subtotal = remaining_subtotal + deleted_subtotal
                    
                    if old_subtotal > 0:
                        new_total = (remaining_subtotal / old_subtotal) * old_total
                    else:
                        new_total = remaining_subtotal
                        
                    cursor.execute("UPDATE orders SET total = ? WHERE id = ?", (new_total, order_id))
                    conn.commit()
                    print(f"Server API [Order Item]: Deleted order item {order_item_id}. Updated Order {order_id} total to {new_total:.2f}")
                
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True}).encode("utf-8"))
        except Exception as e:
            self.send_error(500, f"Error deleting order item: {str(e)}")

    def handle_get_tables(self):
        try:
            static_tables = [
                {"tableNumber": "1", "capacity": 2, "floor": 1},
                {"tableNumber": "2", "capacity": 4, "floor": 1},
                {"tableNumber": "3", "capacity": 4, "floor": 1},
                {"tableNumber": "4", "capacity": 6, "floor": 1},
                {"tableNumber": "5", "capacity": 8, "floor": 1},
                {"tableNumber": "VIP 1", "capacity": 10, "floor": 1},
                {"tableNumber": "201", "capacity": 4, "floor": 2},
                {"tableNumber": "202", "capacity": 4, "floor": 2},
                {"tableNumber": "203", "capacity": 6, "floor": 2},
                {"tableNumber": "301 (ROOF)", "capacity": 8, "floor": 3}
            ]
            
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                if MERCHANT_ID:
                    cursor.execute("SELECT * FROM table_sessions WHERE is_active = 1 AND merchant_id = ?", (MERCHANT_ID,))
                else:
                    cursor.execute("SELECT * FROM table_sessions WHERE is_active = 1")
                active_sessions = {row["table_number"]: dict(row) for row in cursor.fetchall()}
                
                table_totals = {}
                for table_num, sess in active_sessions.items():
                    cursor.execute("SELECT SUM(total) FROM orders WHERE table_number = ? AND created_at >= ?", (table_num, sess["created_at"]))
                    total = cursor.fetchone()[0] or 0.0
                    table_totals[table_num] = total
            
            tables = []
            for t in static_tables:
                num = t["tableNumber"]
                session = active_sessions.get(num)
                status = "vacant"
                guest_count = 0
                session_token = None
                total = 0.0
                
                if session:
                    status = "occupied"
                    guest_count = session.get("guest_count", 2)
                    session_token = session["session_token"]
                    total = table_totals.get(num, 0.0)
                
                tables.append({
                    "tableNumber": num,
                    "capacity": t["capacity"],
                    "floor": t["floor"],
                    "status": status,
                    "guestCount": guest_count,
                    "sessionToken": session_token,
                    "currentTotal": total
                })
                
            response_data = json.dumps(tables).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")

    def handle_get_sync(self):
        try:
            static_tables = [
                {"tableNumber": "1", "capacity": 2, "floor": 1},
                {"tableNumber": "2", "capacity": 4, "floor": 1},
                {"tableNumber": "3", "capacity": 4, "floor": 1},
                {"tableNumber": "4", "capacity": 6, "floor": 1},
                {"tableNumber": "5", "capacity": 8, "floor": 1},
                {"tableNumber": "VIP 1", "capacity": 10, "floor": 1},
                {"tableNumber": "201", "capacity": 4, "floor": 2},
                {"tableNumber": "202", "capacity": 4, "floor": 2},
                {"tableNumber": "203", "capacity": 6, "floor": 2},
                {"tableNumber": "301 (ROOF)", "capacity": 8, "floor": 3}
            ]
            
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                
                cursor.execute("SELECT * FROM table_sessions WHERE is_active = 1")
                active_sessions = {row["table_number"]: dict(row) for row in cursor.fetchall()}
                
                table_totals = {}
                for table_num, sess in active_sessions.items():
                    cursor.execute("SELECT SUM(total) FROM orders WHERE table_number = ? AND created_at >= ?", (table_num, sess["created_at"]))
                    total = cursor.fetchone()[0] or 0.0
                    table_totals[table_num] = total
                
                tables = []
                for t in static_tables:
                    num = t["tableNumber"]
                    session = active_sessions.get(num)
                    status = "vacant"
                    guest_count = 0
                    session_token = None
                    total = 0.0
                    
                    if session:
                        status = "occupied"
                        guest_count = session.get("guest_count", 2)
                        session_token = session["session_token"]
                        total = table_totals.get(num, 0.0)
                    
                    tables.append({
                        "tableNumber": num,
                        "capacity": t["capacity"],
                        "floor": t["floor"],
                        "status": status,
                        "guestCount": guest_count,
                        "sessionToken": session_token,
                        "currentTotal": total
                    })
                    
                cursor.execute("SELECT * FROM service_requests WHERE status = 'pending' ORDER BY created_at ASC")
                req_rows = cursor.fetchall()
                
                requests = []
                for row in req_rows:
                    requests.append({
                        "id": row["id"],
                        "tableNumber": row["table_number"],
                        "requestType": row["request_type"],
                        "status": row["status"],
                        "createdAt": row["created_at"]
                    })
                    
                # Query active/preparing/ready orders
                cursor.execute("SELECT * FROM orders WHERE status IN ('preparing', 'ready') ORDER BY created_at DESC")
                order_rows = cursor.fetchall()
                
                orders = []
                for order_row in order_rows:
                    order_id = order_row["id"]
                    
                    cursor.execute("SELECT * FROM order_items WHERE order_id = ?", (order_id,))
                    item_rows = cursor.fetchall()
                    
                    items = []
                    for item_row in item_rows:
                        items.append({
                            "id": item_row["id"],
                            "name": item_row["item_name"],
                            "quantity": item_row["quantity"],
                            "price": item_row["price"],
                            "status": item_row["status"],
                            "item_id": item_row["item_id"]
                        })
                    
                    # Fetch payments for this order
                    cursor.execute("SELECT * FROM payments WHERE order_id = ?", (order_id,))
                    payment_rows = cursor.fetchall()
                    payments = []
                    for p_row in payment_rows:
                        payments.append({
                            "id": p_row["id"],
                            "orderId": p_row["order_id"],
                            "amount": p_row["amount"],
                            "paymentMethod": p_row["payment_method"],
                            "createdAt": p_row["created_at"]
                        })
                    
                    orders.append({
                        "id": order_row["id"],
                        "orderNumber": order_row["order_number"],
                        "tableNumber": order_row["table_number"],
                        "total": order_row["total"],
                        "status": order_row["status"],
                        "createdAt": order_row["created_at"],
                        "items": items,
                        "payments": payments
                    })
            
            sync_data = {
                "tables": tables,
                "requests": requests,
                "orders": orders
            }
            
            response_data = json.dumps(sync_data).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")

    def handle_get_employees(self):
        try:
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM employees")
                rows = cursor.fetchall()
                
                employees = []
                for row in rows:
                    employees.append({
                        "id": row["id"],
                        "firstName": row["first_name"],
                        "lastName": row["last_name"],
                        "phone": row["phone"],
                        "nationalId": row["national_id"],
                        "employmentType": row["employment_type"],
                        "payRate": row["pay_rate"],
                        "username": row["username"],
                        "role": row["role"]
                    })
            
            response_data = json.dumps(employees).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")

    def handle_post_employee_verify(self):
        try:
            content_length = int(self.headers["Content-Length"])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode("utf-8"))
            employee_id = data.get("employee_id") or data.get("employeeId")
            pin_digits = data.get("pin_digits") or data.get("pinDigits")
            
            if not employee_id or not pin_digits:
                self.send_error(400, "Missing employee_id or pin_digits")
                return

            # Rate limiting: max 5 attempts per employee per minute
            now = time.time()
            self._pin_attempts = getattr(self, '_pin_attempts', {})
            attempts = self._pin_attempts.get(employee_id, [])
            attempts = [t for t in attempts if now - t < 60]
            self._pin_attempts[employee_id] = attempts
            if len(attempts) >= 5:
                self._send_error_json(429, "Too many attempts. Try again later.")
                return
            attempts.append(now)

            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT pin_hash FROM employees WHERE id = ?", (employee_id,))
                row = cursor.fetchone()

            # Always use constant-time comparison to prevent timing attacks
            if row:
                stored_hash = (row[0] or "").encode("utf-8")
                if len(pin_digits) == 4:
                    input_hash = sha256_hash(pin_digits).encode("utf-8")
                else:
                    input_hash = pin_digits.encode("utf-8")
                
                if hmac.compare_digest(input_hash, stored_hash):
                    # Clear attempts on success
                    self._pin_attempts.pop(employee_id, None)
                    self._send_json_response(200, {"verified": True})
                    return

            # Always return the same response regardless of whether employee exists
            # to prevent employee ID enumeration
            self._send_json_response(200, {"verified": False})
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")

    def handle_get_merchants(self):
        try:
            if SUPABASE_URL and SUPABASE_ANON_KEY:
                import urllib.request
                import json
                url = f"{SUPABASE_URL}/rest/v1/merchants?select=id,name,kitchen_workflow_required,is_table_system_enabled,is_web_ordering_enabled"
                req = urllib.request.Request(
                    url,
                    headers={
                        "apikey": SUPABASE_ANON_KEY,
                        "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
                    }
                )
                try:
                    with urllib.request.urlopen(req) as res:
                        data = json.loads(res.read().decode("utf-8"))
                        self.send_response(200)
                        self.send_header("Content-Type", "application/json")
                        self.send_header("Access-Control-Allow-Origin", "*")
                        self.end_headers()
                        self.wfile.write(json.dumps(data).encode("utf-8"))
                        return
                except Exception as ex:
                    print(f"Error querying remote merchants: {ex}")

            try:
                with closing(get_db_connection()) as conn:
                    conn.row_factory = sqlite3.Row
                    rows = conn.execute('''
                        SELECT id, name, branch_code, kitchen_workflow_required,
                               is_table_system_enabled, is_web_ordering_enabled
                        FROM merchants
                        ORDER BY name ASC
                    ''').fetchall()
                    if rows:
                        self._send_json_response(200, [{
                            "id": row["id"],
                            "name": row["name"],
                            "branch_code": row["branch_code"],
                            "kitchen_workflow_required": _as_bool(row["kitchen_workflow_required"], False),
                            "is_table_system_enabled": _as_bool(row["is_table_system_enabled"]),
                            "is_web_ordering_enabled": _as_bool(row["is_web_ordering_enabled"])
                        } for row in rows])
                        return
            except Exception as local_ex:
                print(f"Error querying local merchants: {local_ex}")
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps([{
                "id": MERCHANT_ID or "163350b0-056d-4d5e-b5d4-24e7aac5ab6d",
                "name": "AlphaPos HQ",
                "kitchen_workflow_required": False,
                "is_table_system_enabled": True,
                "is_web_ordering_enabled": True
            }]).encode("utf-8"))
        except Exception as e:
            self.send_error(500, f"Error fetching merchant settings: {str(e)}")

    def handle_get_timecards(self):
        try:
            parsed_path = urllib.parse.urlparse(self.path)
            query_params = urllib.parse.parse_qs(parsed_path.query)
            employee_id = query_params.get("employee_id", [None])[0]
            
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                
                if employee_id:
                    cursor.execute("SELECT * FROM timecards WHERE employee_id = ? ORDER BY clock_in DESC", (employee_id,))
                else:
                    cursor.execute("SELECT * FROM timecards ORDER BY clock_in DESC")
                rows = cursor.fetchall()
                
                timecards = []
                for row in rows:
                    timecards.append({
                        "id": row["id"],
                        "employeeId": row["employee_id"],
                        "employeeName": row["employee_name"],
                        "clockIn": row["clock_in"],
                        "clockOut": row["clock_out"],
                        "breakDurationMinutes": row["break_duration"],
                        "overtimeMinutes": row["overtime_minutes"],
                        "status": row["status"],
                        "notes": row["notes"],
                        "clockInFaceConfidence": row["clock_in_confidence"],
                        "clockOutFaceConfidence": row["clock_out_confidence"]
                    })
            
            response_data = json.dumps(timecards).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")

    def handle_post_timecard(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            data = json.loads(post_data.decode("utf-8"))
            tc_id = data.get("id") or str(uuid.uuid4())
            employee_name = data.get("employee_name") or data.get("employeeName") or "Staff"
            employee_id = data.get("employee_id") or data.get("employeeId")
            clock_in = data.get("clock_in") or data.get("clockIn")
            clock_out = data.get("clock_out") or data.get("clockOut")
            
            if isinstance(clock_in, str):
                try:
                    clock_in = datetime.fromisoformat(clock_in.replace("Z", "+00:00")).timestamp()
                except:
                    clock_in = datetime.now().timestamp()
            elif clock_in is None:
                clock_in = datetime.now().timestamp()
                
            if isinstance(clock_out, str):
                try:
                    clock_out = datetime.fromisoformat(clock_out.replace("Z", "+00:00")).timestamp()
                except:
                    clock_out = None
            elif clock_out == 0 or clock_out == 0.0:
                clock_out = None

            break_duration = int(data.get("break_duration") or data.get("breakDurationMinutes") or 0)
            overtime_minutes = int(data.get("overtime_minutes") or data.get("overtimeMinutes") or 0)
            status = data.get("status") or "approved"
            notes = data.get("notes")
            clock_in_confidence = data.get("clock_in_confidence") or data.get("clockInFaceConfidence")
            clock_out_confidence = data.get("clock_out_confidence") or data.get("clockOutFaceConfidence")

            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()

                if not employee_id:
                    first_name = employee_name.split(" ")[0]
                    cursor.execute("SELECT id FROM employees WHERE first_name LIKE ? OR username LIKE ?", (first_name, first_name.lower()))
                    row = cursor.fetchone()
                    if row:
                        employee_id = row[0]
                    else:
                        employee_id = "11111111-1111-1111-1111-111111111111"

                cursor.execute("SELECT id FROM timecards WHERE id = ?", (tc_id,))
                exists = cursor.fetchone()
                if exists:
                    cursor.execute('''
                        UPDATE timecards
                        SET clock_out = ?, break_duration = ?, overtime_minutes = ?, status = ?, notes = ?, clock_out_confidence = ?
                        WHERE id = ?
                    ''', (clock_out, break_duration, overtime_minutes, status, notes, clock_out_confidence, tc_id))
                else:
                    cursor.execute('''
                        INSERT INTO timecards (id, employee_id, employee_name, clock_in, clock_out, break_duration, overtime_minutes, status, notes, clock_in_confidence, clock_out_confidence)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', (tc_id, employee_id, employee_name, clock_in, clock_out, break_duration, overtime_minutes, status, notes, clock_in_confidence, clock_out_confidence))
                
                conn.commit()

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "id": tc_id}).encode("utf-8"))
            print(f"Server API [Timecard]: Saved timecard for {employee_name} ({status})")
        except Exception as e:
            self.send_error(500, f"Error saving timecard: {str(e)}")


    def handle_get_promotions(self):
        try:
            # Try to sync remote promotions to local SQLite first (failsafe)
            try:
                with closing(get_db_connection()) as conn:
                    sync_promotions_from_supabase(conn)
            except Exception as e:
                print(f"Server API [Promotion]: Skipped sync during fetch: {str(e)}")
            
            # Fetch active, non-deleted promotions from local SQLite
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("SELECT id, title, promo_description, image_data, is_active, is_deleted, updated_at FROM promotions WHERE is_active = 1 AND is_deleted = 0 ORDER BY updated_at DESC")
                rows = cursor.fetchall()
                
                promotions = []
                for row in rows:
                    promotions.append({
                        "id": row["id"],
                        "title": row["title"],
                        "promoDescription": row["promo_description"],
                        "imageData": row["image_data"],
                        "isActive": bool(row["is_active"]),
                        "isDeleted": bool(row["is_deleted"]),
                        "updatedAt": row["updated_at"]
                    })
            
            response_data = json.dumps(promotions).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Error fetching promotions: {str(e)}")

    def handle_post_promotion(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            promo_data = json.loads(post_data.decode("utf-8"))
            promo_id = promo_data.get("id")
            title = promo_data.get("title")
            promo_desc = promo_data.get("promoDescription") or promo_data.get("promo_description")
            image_data = promo_data.get("imageData") or promo_data.get("image_data")
            is_active = promo_data.get("isActive") if promo_data.get("isActive") is not None else True
            is_deleted = promo_data.get("isDeleted") if promo_data.get("isDeleted") is not None else False
            updated_at = promo_data.get("updatedAt") or promo_data.get("updated_at") or get_utc_now_iso()
            
            if not promo_id or not title:
                self.send_error(400, "id and title are required")
                return
            
            payload = {
                "id": promo_id,
                "title": title,
                "promo_description": promo_desc or "",
                "image_data": image_data or "",
                "is_active": 1 if is_active else 0,
                "is_deleted": 1 if is_deleted else 0,
                "updated_at": updated_at,
                "merchant_id": MERCHANT_ID
            }
            
            # Save to SQLite local DB cache first
            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "INSERT OR REPLACE INTO promotions (id, title, promo_description, image_data, is_active, is_deleted, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (
                        promo_id,
                        title,
                        promo_desc or "",
                        image_data or "",
                        1 if is_active else 0,
                        1 if is_deleted else 0,
                        updated_at
                    )
                )
                conn.commit()
            
            success, _ = supabase_request("POST", "promotions", payload, {"on_conflict": "id"})
            
            if not success:
                # Try PATCH if upsert fails
                success, _ = supabase_request("PATCH", "promotions", payload, {"id": f"eq.{promo_id}"})
            
            print(f"Server API [Promotion]: Saved/Updated promotion: {title} (ID: {promo_id})")
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "id": promo_id}).encode("utf-8"))
        except Exception as e:
            self.send_error(400, f"Error saving promotion: {str(e)}")

    def handle_delete_promotion(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        try:
            data = json.loads(post_data.decode("utf-8"))
            promo_id = data.get("id")
            if not promo_id:
                self.send_error(400, "id is required")
                return
            
            # Soft-delete on local SQLite database first
            with closing(get_db_connection()) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "UPDATE promotions SET is_deleted = 1, updated_at = ? WHERE id = ?",
                    (get_utc_now_iso(), promo_id)
                )
                conn.commit()
            
            # Soft-delete on Supabase (matching Staff app behavior)
            payload = {
                "is_deleted": 1,
                "updated_at": get_utc_now_iso()
            }
            success, _ = supabase_request("PATCH", "promotions", payload, {"id": f"eq.{promo_id}"})
            
            print(f"Server API [Promotion]: Soft-deleted promotion ID: {promo_id}")
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True}).encode("utf-8"))
        except Exception as e:
            self.send_error(500, f"Error deleting promotion: {str(e)}")


    def handle_get_modifiers_config(self):
        try:
            with closing(get_db_connection()) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                
                # 1. Fetch groups
                cursor.execute("SELECT id, name, min_selection, max_selection, merchant_id FROM modifier_groups")
                groups = [dict(r) for r in cursor.fetchall()]
                
                # 2. Fetch modifiers
                cursor.execute("SELECT id, modifier_group_id, name, extra_price, is_available, merchant_id FROM modifiers")
                mods = [dict(r) for r in cursor.fetchall()]
                
                # 3. Fetch links
                cursor.execute("SELECT menu_item_id, modifier_group_id, merchant_id FROM menu_item_modifier_groups")
                links = [dict(r) for r in cursor.fetchall()]
            
            response_data = json.dumps({
                "groups": groups,
                "modifiers": mods,
                "links": links
            }).encode("utf-8")
            
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", self._get_allowed_origin())
            self.send_header("Access-Control-Allow-Headers", "Content-Type, x-merchant-id")
            self.end_headers()
            self.wfile.write(response_data)
        except Exception as e:
            self.send_error(500, f"Database error: {str(e)}")


    def handle_get_config_js(self):
        js_content = f"""window.ALPHAPOS_CONFIG = {{
    supabaseUrl: '{SUPABASE_URL}',
    supabaseKey: '{SUPABASE_ANON_KEY}',
    merchantId: '{MERCHANT_ID}',
    isProduction: {str(IS_PRODUCTION).lower()}
}};"""
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript")
        self.send_header("Access-Control-Allow-Origin", self._get_allowed_origin())
        self.send_header("Content-Length", str(len(js_content)))
        self.end_headers()
        self.wfile.write(js_content.encode("utf-8"))


    # ==========================================
    # Static Assets Router
    # ==========================================
    def handle_static_files(self, path):
        if path == "/":
            path = "/index.html"
            
        # Strip leading slash to get relative file path
        file_path = path.lstrip("/")
        
        # Security: Prevent escaping web folder
        if ".." in file_path or file_path.startswith("/"):
            self.send_error(403, "Access Denied")
            return
        
        # Security: Block sensitive files
        blocked_extensions = (".db", ".sqlite", ".sql", ".env", ".plist", ".json", ".yaml", ".yml")
        blocked_names = (".env", ".git", ".htaccess", ".gitignore", "config.json")
        if file_path.endswith(blocked_extensions) or file_path.startswith(".") or file_path in blocked_names:
            self.send_error(403, "Access Denied")
            return
            
        if not os.path.exists(file_path):
            self.send_error(404, "File Not Found")
            return
            
        # Determine mime type
        mime_type = "text/plain"
        if file_path.endswith(".html"): mime_type = "text/html"
        elif file_path.endswith(".css"): mime_type = "text/css"
        elif file_path.endswith(".js"): mime_type = "application/javascript"
        elif file_path.endswith(".png"): mime_type = "image/png"
        elif file_path.endswith(".jpg") or file_path.endswith(".jpeg"): mime_type = "image/jpeg"
        elif file_path.endswith(".ico"): mime_type = "image/x-icon"
        
        try:
            with open(file_path, "rb") as f:
                content = f.read()
                
            self.send_response(200)
            self.send_header("Content-Type", mime_type)
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_error(500, f"Error serving file: {str(e)}")

# ==========================================
# Server Launcher
# ==========================================
def run():
    init_db()
    server_address = ('', PORT)
    httpd = HTTPServer(server_address, UnifiedRequestHandler)
    print(f"==========================================================")
    print(f"      Unified API Backend Server active on port: {PORT}")
    print(f"      Database: {DB_FILE} (SQLite)")
    print(f"==========================================================")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.server_close()
        sys.exit(0)

if __name__ == '__main__':
    run()
