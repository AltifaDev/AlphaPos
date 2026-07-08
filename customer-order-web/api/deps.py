"""
AlphaPos — Shared database, config, and utility module.
Used by all API route modules.
"""
import os
import json
import sqlite3
import uuid
import re
import urllib.request
import urllib.parse
import urllib.error
import hashlib
import hmac
from datetime import datetime, timedelta
from contextlib import asynccontextmanager, closing
from typing import Optional, Any
from dotenv import load_dotenv

load_dotenv()

# ==========================================
# Configuration
# ==========================================
PORT = int(os.getenv("PORT", "8080"))
DB_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "alphapos.db")

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
MERCHANT_ID = os.getenv("MERCHANT_ID", "")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:8080,http://127.0.0.1:8080").split(",")
API_AUTH_TOKEN = os.getenv("API_AUTH_TOKEN", "")
IS_PRODUCTION = os.getenv("ALPHAPOS_ENV") == "production"
SERVICE_CHARGE_RATE = float(os.getenv("SERVICE_CHARGE_RATE", "0.10"))
VAT_RATE = float(os.getenv("VAT_RATE", "0.07"))
PROMPTPAY_ID = os.getenv("PROMPTPAY_ID", "")


# ==========================================
# Database Connection
# ==========================================
def get_db_connection() -> sqlite3.Connection:
    """Get a new SQLite connection with WAL mode."""
    conn = sqlite3.connect(DB_FILE)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    return conn


def get_db_row_connection() -> sqlite3.Connection:
    """Get connection with Row factory for dict-like access."""
    conn = get_db_connection()
    conn.row_factory = sqlite3.Row
    return conn


# ==========================================
# Utilities
# ==========================================
def get_utc_now_iso() -> str:
    return datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_hash(string: str) -> str:
    if not string:
        return ""
    return hashlib.sha256(string.encode('utf-8')).hexdigest()


def verify_pin(pin: str, stored_hash: str) -> bool:
    """
    Verifies a PIN against a stored hash using constant-time comparison.
    Supports both legacy SHA-256 and stretched hash (iter:10000:salt:hash) formats.
    """
    if not stored_hash or not pin:
        return False

    # Support new key-stretching format: iter:<iterations>:<salt_b64>:<hash_hex>
    if stored_hash.startswith("iter:"):
        parts = stored_hash.split(":", 3)
        if len(parts) != 4:
            return False
        try:
            iterations = int(parts[1])
        except ValueError:
            return False
        salt = parts[2]
        expected_hash = parts[3]

        # Recreate iterated SHA-256 hash
        current_hash = salt + pin
        for _ in range(iterations):
            current_hash = hashlib.sha256(current_hash.encode('utf-8')).hexdigest()

        return hmac.compare_digest(current_hash.encode('utf-8'), expected_hash.encode('utf-8'))

    # Legacy SHA-256 format
    input_hash = sha256_hash(pin)
    return hmac.compare_digest(input_hash.encode('utf-8'), stored_hash.encode('utf-8'))


def clean_string(value, name: str, max_length: int, required: bool = False, pattern: str = None) -> str:
    if value is None:
        if required:
            raise ValueError(f"{name} is required.")
        return ""
    cleaned = str(value).strip()
    if required and not cleaned:
        raise ValueError(f"{name} is required.")
    if len(cleaned) > max_length:
        raise ValueError(f"{name} must be {max_length} characters or fewer.")
    if pattern and cleaned and not re.fullmatch(pattern, cleaned):
        raise ValueError(f"{name} contains invalid characters.")
    return cleaned


def parse_positive_float(value, name: str, max_value: float = 1_000_000.0) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        raise ValueError(f"{name} must be a number.")
    if parsed <= 0 or parsed > max_value:
        raise ValueError(f"{name} must be greater than zero and no more than {max_value}.")
    return parsed


def calculate_order_total(subtotal: float) -> float:
    service_charge = subtotal * SERVICE_CHARGE_RATE
    vat = (subtotal + service_charge) * VAT_RATE
    return subtotal + service_charge + vat


def _as_bool(value, default: bool = True) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value).strip().lower() not in ("0", "false", "no", "off")


# ==========================================
# Supabase Utilities
# ==========================================
def supabase_request(method: str, endpoint: str, payload: dict = None, query_params: dict = None):
    """Make a request to Supabase REST API. Returns (success, response_data)."""
    try:
        if not SUPABASE_URL or not SUPABASE_ANON_KEY:
            return False, "Supabase not configured"
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
        return False, str(e)


def supabase_post(endpoint: str, payload: dict, queue_on_fail: bool = True):
    """Best-effort POST to Supabase with offline queue fallback."""
    success, result = supabase_request("POST", endpoint, payload)
    if not success and queue_on_fail:
        # Queue for later retry
        try:
            with closing(get_db_connection()) as conn:
                conn.execute(
                    "INSERT INTO pending_supabase_writes (id, endpoint, payload, created_at) VALUES (?, ?, ?, ?)",
                    (str(uuid.uuid4()), endpoint, json.dumps(payload), get_utc_now_iso())
                )
                conn.commit()
        except Exception:
            pass
    return success


def supabase_rpc(function_name: str, params: dict = None):
    """Call a Supabase RPC function. Returns parsed JSON or None."""
    try:
        if not SUPABASE_URL or not SUPABASE_ANON_KEY:
            return None
        url = f"{SUPABASE_URL}/rest/v1/rpc/{function_name}"
        data_bytes = json.dumps(params or {}).encode("utf-8")
        req = urllib.request.Request(url, data=data_bytes, method="POST")
        req.add_header("apikey", SUPABASE_ANON_KEY)
        req.add_header("Authorization", f"Bearer {SUPABASE_ANON_KEY}")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-merchant-id", MERCHANT_ID)
        with urllib.request.urlopen(req, timeout=5) as response:
            return json.loads(response.read().decode())
    except Exception:
        return None


# ==========================================
# Merchant Settings
# ==========================================
def get_merchant_web_settings(merchant_id: str = None, branch_code: str = None) -> dict:
    merchant_id = merchant_id or MERCHANT_ID
    fallback = {"is_table_system_enabled": True, "is_web_ordering_enabled": True}
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='merchants'")
            if not cursor.fetchone():
                return fallback
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
    except Exception:
        return fallback


def web_ordering_enabled_for_payload(payload: dict) -> bool:
    settings = get_merchant_web_settings(
        payload.get("merchant_id") or payload.get("merchantId"),
        payload.get("branch_code") or payload.get("branchCode")
    )
    return settings["is_table_system_enabled"] and settings["is_web_ordering_enabled"]


# ==========================================
# Structured Logging
# ==========================================
def log_event(level: str, event: str, message: str = "", **fields):
    created_at = get_utc_now_iso()
    record = {"ts": created_at, "level": level, "event": event, "message": message, **fields}
    print(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
    try:
        with closing(get_db_connection()) as conn:
            exists = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='event_logs'"
            ).fetchone()
            if exists:
                conn.execute(
                    "INSERT INTO event_logs (id, level, event, message, payload, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                    (str(uuid.uuid4()), level, event, str(message)[:500],
                     json.dumps(fields, ensure_ascii=False)[:2000], created_at)
                )
                conn.commit()
    except Exception:
        pass
