"""
AlphaPos — Estimated Wait Time API route
"""
from fastapi import APIRouter, HTTPException
from contextlib import closing

from .deps import (
    get_db_row_connection, get_utc_now_iso,
    MERCHANT_ID, supabase_rpc, log_event
)

router = APIRouter(prefix="/v1", tags=["wait-time"])


@router.get("/wait-time")
def get_wait_time():
    """
    Returns estimated wait time based on current kitchen load.
    Tries Supabase RPC first, falls back to local SQLite calculation.
    """
    try:
        result = None

        # Try Supabase RPC
        if MERCHANT_ID:
            result = supabase_rpc("get_estimated_wait_time", {"p_merchant_id": MERCHANT_ID})

        # Fallback: local calculation
        if not result:
            with closing(get_db_row_connection()) as conn:
                cursor = conn.cursor()

                cursor.execute(
                    "SELECT COUNT(*) as cnt FROM orders WHERE status IN ('preparing', 'confirmed') AND created_at > datetime('now', '-4 hours')"
                )
                orders_ahead = cursor.fetchone()["cnt"]

                cursor.execute(
                    "SELECT COALESCE(SUM(quantity), 0) as cnt FROM order_items WHERE status IN ('cooking', 'pending')"
                )
                items_in_queue = cursor.fetchone()["cnt"]

                avg_prep_time = 12.0
                estimated_minutes = max(5, min(90, int(
                    items_in_queue * avg_prep_time / max(1, min(orders_ahead, 5))
                )))

                result = {
                    "estimated_minutes": estimated_minutes,
                    "orders_ahead": orders_ahead,
                    "items_in_queue": items_in_queue,
                    "avg_prep_time_minutes": avg_prep_time,
                    "calculated_at": get_utc_now_iso()
                }

        return result

    except Exception as e:
        log_event("error", "wait_time_error", str(e))
        raise HTTPException(status_code=500, detail=str(e))
