"""
AlphaPos — Merchants API route
"""
from fastapi import APIRouter, HTTPException
from contextlib import closing

from .deps import get_db_row_connection, MERCHANT_ID, log_event

router = APIRouter(prefix="/v1", tags=["merchants"])


@router.get("/merchants")
def get_merchants():
    """Returns merchant settings."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM merchants WHERE id = ? LIMIT 1", (MERCHANT_ID,))
            row = cursor.fetchone()
            if not row:
                return {"id": MERCHANT_ID, "name": "AlphaPos Restaurant"}
            return dict(row)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
