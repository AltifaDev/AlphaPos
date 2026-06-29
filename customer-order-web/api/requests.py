"""
AlphaPos — Service Requests API routes
"""
from fastapi import APIRouter, HTTPException, Request
from contextlib import closing
import uuid

from .deps import (
    get_db_connection, get_db_row_connection, get_utc_now_iso,
    clean_string, MERCHANT_ID, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["requests"])


@router.get("/requests")
def get_requests():
    """Returns pending service requests."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT * FROM service_requests WHERE merchant_id = ? AND status != 'completed' ORDER BY created_at DESC LIMIT 50",
                (MERCHANT_ID,)
            )
            rows = cursor.fetchall()
            return [dict(row) for row in rows]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/requests")
async def create_request(request: Request):
    """Create a new service request (call staff, request bill, etc.)."""
    try:
        data = await request.json()
        req_id = clean_string(data.get("id") or str(uuid.uuid4()), "id", 50, required=True, pattern=r"[A-Za-z0-9_-]+")
        table_number = clean_string(data.get("table_number") or data.get("tableNumber") or "", "table_number", 10, required=True)
        request_type = clean_string(data.get("request_type") or data.get("type") or "call_staff", "request_type", 50, required=True)
        created_at = get_utc_now_iso()

        with closing(get_db_connection()) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO service_requests (id, table_number, request_type, status, created_at, merchant_id)
                VALUES (?, ?, ?, 'pending', ?, ?)
            """, (req_id, table_number, request_type, created_at, MERCHANT_ID))
            conn.commit()

        supabase_post("service_requests", {
            "id": req_id, "table_number": table_number, "request_type": request_type,
            "status": "pending", "created_at": created_at, "merchant_id": MERCHANT_ID
        })

        log_event("info", "request.created", table_number=table_number, type=request_type)
        return {"success": True, "id": req_id}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/requests/complete")
async def complete_request_payload(request: Request):
    """Complete a service request by ID (in body)."""
    data = await request.json()
    req_id = data.get("id") or data.get("request_id") or ""
    if not req_id:
        raise HTTPException(status_code=400, detail="id is required")
    return _complete_request(req_id)


@router.post("/requests/{req_id}/complete")
def complete_request_path(req_id: str):
    """Complete a service request by ID (in path)."""
    return _complete_request(req_id)


def _complete_request(req_id: str):
    try:
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("UPDATE service_requests SET status = 'completed' WHERE id = ?", (req_id,))
            conn.commit()
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Request not found")
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
