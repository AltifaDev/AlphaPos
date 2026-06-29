"""
AlphaPos — Sync API routes (status, retry, full sync data)
"""
from fastapi import APIRouter, HTTPException
from contextlib import closing
import json

from .deps import (
    get_db_connection, get_db_row_connection, get_utc_now_iso,
    MERCHANT_ID, SUPABASE_URL, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["sync"])


@router.get("/sync")
def get_sync():
    """Returns all data for full sync (orders, items, sessions, tables)."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()

            # Orders
            cursor.execute("SELECT * FROM orders WHERE merchant_id = ? ORDER BY created_at DESC LIMIT 200", (MERCHANT_ID,))
            orders = [dict(r) for r in cursor.fetchall()]

            # Order Items
            cursor.execute("""
                SELECT oi.* FROM order_items oi
                JOIN orders o ON oi.order_id = o.id
                WHERE o.merchant_id = ?
            """, (MERCHANT_ID,))
            order_items = [dict(r) for r in cursor.fetchall()]

            # Sessions
            cursor.execute("SELECT * FROM table_sessions WHERE merchant_id = ?", (MERCHANT_ID,))
            sessions = [dict(r) for r in cursor.fetchall()]

            # Tables
            cursor.execute("SELECT * FROM restaurant_tables WHERE merchant_id = ?", (MERCHANT_ID,))
            tables = [dict(r) for r in cursor.fetchall()]

            return {
                "orders": orders,
                "order_items": order_items,
                "sessions": sessions,
                "tables": tables,
                "synced_at": get_utc_now_iso()
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sync/status")
def get_sync_status():
    """Returns status of pending Supabase writes queue."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) as cnt FROM pending_supabase_writes")
            row = cursor.fetchone()
            pending_count = row["cnt"] if row else 0

            cursor.execute("SELECT * FROM pending_supabase_writes ORDER BY created_at DESC LIMIT 10")
            items = [dict(r) for r in cursor.fetchall()]

            return {
                "pending_count": pending_count,
                "items": items,
                "supabase_configured": bool(SUPABASE_URL)
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sync/retry")
def post_sync_retry():
    """Retry all pending Supabase writes."""
    try:
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, endpoint, payload FROM pending_supabase_writes ORDER BY created_at ASC LIMIT 50")
            rows = cursor.fetchall()

            succeeded = 0
            failed = 0
            for row in rows:
                row_id, endpoint, payload_str = row
                try:
                    payload = json.loads(payload_str)
                    success = supabase_post(endpoint, payload, queue_on_fail=False)
                    if success:
                        cursor.execute("DELETE FROM pending_supabase_writes WHERE id = ?", (row_id,))
                        succeeded += 1
                    else:
                        failed += 1
                except Exception:
                    failed += 1
            conn.commit()

        return {"success": True, "retried": succeeded + failed, "succeeded": succeeded, "failed": failed}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
