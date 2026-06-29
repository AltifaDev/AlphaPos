"""
AlphaPos — Tables API route
"""
from fastapi import APIRouter, HTTPException
from contextlib import closing
import json

from .deps import get_db_row_connection, MERCHANT_ID, SUPABASE_URL, SUPABASE_ANON_KEY, log_event

router = APIRouter(prefix="/v1", tags=["tables"])


@router.get("/tables")
def get_tables():
    """Returns restaurant tables with current status and guest count."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()

            cursor.execute("""
                SELECT rt.*, ts.session_token, ts.guest_count, ts.is_active as session_active
                FROM restaurant_tables rt
                LEFT JOIN table_sessions ts ON rt.table_number = ts.table_number 
                    AND ts.is_active = 1 AND ts.merchant_id = ?
                WHERE rt.merchant_id = ?
                ORDER BY CAST(rt.table_number AS INTEGER)
            """, (MERCHANT_ID, MERCHANT_ID))
            rows = cursor.fetchall()

            tables = []
            for row in rows:
                keys = row.keys()
                tables.append({
                    "id": row["id"],
                    "table_number": row["table_number"],
                    "capacity": row["capacity"] if "capacity" in keys else 4,
                    "status": row["status"],
                    "session_token": row["session_token"] if "session_token" in keys else None,
                    "guest_count": row["guest_count"] if "guest_count" in keys else 0,
                    "position_x": row["position_x"] if "position_x" in keys else 0,
                    "position_y": row["position_y"] if "position_y" in keys else 0,
                    "floor": row["floor"] if "floor" in keys else 1,
                })

            return tables
    except Exception as e:
        log_event("error", "get_tables_failed", str(e))
        raise HTTPException(status_code=500, detail=str(e))
