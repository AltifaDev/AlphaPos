"""
AlphaPos — Staff (employees, timecards) API routes
"""
from fastapi import APIRouter, HTTPException, Request, Depends
from contextlib import closing
import uuid

from .deps import (
    get_db_connection, get_db_row_connection, get_utc_now_iso,
    clean_string, sha256_hash, MERCHANT_ID, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["staff"])


@router.get("/employees")
def get_employees():
    """Returns all employees."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM employees WHERE merchant_id = ?", (MERCHANT_ID,))
            rows = cursor.fetchall()
            return [
                {k: row[k] for k in row.keys() if k != "passcode_hash"}
                for row in rows
            ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/employees/verify")
async def verify_employee(request: Request):
    """Verify employee PIN code."""
    try:
        data = await request.json()
        employee_id = data.get("employee_id") or data.get("id") or ""
        pin = data.get("pin") or data.get("passcode") or ""

        if not employee_id or not pin:
            raise HTTPException(status_code=400, detail="employee_id and pin are required")

        pin_hash = sha256_hash(pin)

        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT id, first_name, last_name, role FROM employees WHERE id = ? AND passcode_hash = ?",
                (employee_id, pin_hash)
            )
            row = cursor.fetchone()
            if row:
                return {"success": True, "employee": dict(row)}
            else:
                return {"success": False, "error": "Invalid PIN"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/timecards")
def get_timecards():
    """Returns timecards."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT * FROM timecards WHERE merchant_id = ? ORDER BY clock_in DESC LIMIT 100",
                (MERCHANT_ID,)
            )
            rows = cursor.fetchall()
            return [dict(row) for row in rows]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/timecards")
async def post_timecard(request: Request):
    """Clock in/out."""
    try:
        data = await request.json()
        tc_id = data.get("id") or str(uuid.uuid4())
        employee_id = clean_string(data.get("employee_id"), "employee_id", 50, required=True, pattern=r"[A-Za-z0-9_-]+")
        clock_in = data.get("clock_in") or get_utc_now_iso()
        clock_out = data.get("clock_out")

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT OR REPLACE INTO timecards (id, employee_id, clock_in, clock_out, merchant_id)
                VALUES (?, ?, ?, ?, ?)
            """, (tc_id, employee_id, clock_in, clock_out, MERCHANT_ID))
            conn.commit()

        supabase_post("timecards", {
            "id": tc_id, "employee_id": employee_id, "clock_in": clock_in,
            "clock_out": clock_out, "merchant_id": MERCHANT_ID
        })

        return {"success": True, "id": tc_id}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
