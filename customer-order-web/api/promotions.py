"""
AlphaPos — Promotions API routes
"""
from fastapi import APIRouter, HTTPException, Request
from contextlib import closing
import json
import uuid

from .deps import (
    get_db_connection, get_db_row_connection, get_utc_now_iso,
    clean_string, MERCHANT_ID, supabase_post, supabase_request, log_event
)

router = APIRouter(prefix="/v1", tags=["promotions"])


@router.get("/promotions")
def get_promotions():
    """Returns active promotions."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT * FROM promotions WHERE is_deleted = 0 AND is_active = 1 ORDER BY updated_at DESC"
            )
            rows = cursor.fetchall()
            return [dict(row) for row in rows]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/promotions")
async def upsert_promotion(request: Request):
    """Create or update a promotion."""
    try:
        data = await request.json()
        promo_id = data.get("id") or str(uuid.uuid4())
        title = clean_string(data.get("title"), "title", 200, required=True)
        description = clean_string(data.get("promo_description") or data.get("description") or "", "description", 2000)
        image_data = data.get("image_data") or ""
        media_type = data.get("media_type") or "image"

        with closing(get_db_connection()) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO promotions (id, title, promo_description, image_data, media_type, is_active, is_deleted, updated_at)
                VALUES (?, ?, ?, ?, ?, 1, 0, ?)
            """, (promo_id, title, description, image_data, media_type, get_utc_now_iso()))
            conn.commit()

        supabase_post("promotions", {
            "id": promo_id, "title": title, "promo_description": description,
            "image_data": image_data, "media_type": media_type,
            "is_active": True, "is_deleted": False, "merchant_id": MERCHANT_ID
        })

        return {"success": True, "id": promo_id}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/promotions/delete")
async def delete_promotion(request: Request):
    """Soft-delete a promotion."""
    try:
        data = await request.json()
        promo_id = clean_string(data.get("id"), "id", 50, required=True, pattern=r"[A-Za-z0-9_-]+")

        with closing(get_db_connection()) as conn:
            conn.execute("UPDATE promotions SET is_deleted = 1, updated_at = ? WHERE id = ?", (get_utc_now_iso(), promo_id))
            conn.commit()

        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
