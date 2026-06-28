"""
AlphaPos — Sessions API routes (open, close, get)
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from contextlib import closing
from typing import Optional
import uuid

from .deps import (
    get_db_connection, get_db_row_connection, get_utc_now_iso,
    MERCHANT_ID, web_ordering_enabled_for_payload, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["sessions"])


class OpenSessionRequest(BaseModel):
    table_number: Optional[str] = None
    tableNumber: Optional[str] = None
    guest_count: Optional[int] = 2
    guestCount: Optional[int] = None
    merchant_id: Optional[str] = None
    branch_code: Optional[str] = None


class CloseSessionRequest(BaseModel):
    table_number: Optional[str] = None
    tableNumber: Optional[str] = None
    session_token: Optional[str] = None


@router.get("/sessions")
def get_sessions():
    """Returns all active table sessions."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT * FROM table_sessions WHERE is_active = 1 AND merchant_id = ? ORDER BY created_at DESC",
                (MERCHANT_ID,)
            )
            rows = cursor.fetchall()
            sessions = []
            for row in rows:
                keys = row.keys()
                sessions.append({
                    "id": row["id"],
                    "table_number": row["table_number"],
                    "session_token": row["session_token"],
                    "is_active": bool(row["is_active"]),
                    "guest_count": row["guest_count"] if "guest_count" in keys else 2,
                    "created_at": row["created_at"],
                })
            return sessions
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sessions/open")
def open_session(data: OpenSessionRequest):
    """Creates or resumes a table session."""
    payload = data.model_dump()
    if not web_ordering_enabled_for_payload(payload):
        raise HTTPException(status_code=403, detail="Web ordering is disabled for this store.")

    table_number = data.table_number or data.tableNumber or ""
    guest_count = data.guestCount or data.guest_count or 2
    if not table_number:
        raise HTTPException(status_code=400, detail="table_number is required")

    try:
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT session_token FROM table_sessions WHERE table_number = ? AND is_active = 1",
                (table_number,)
            )
            row = cursor.fetchone()
            if row:
                session_token = row[0]
            else:
                session_token = str(uuid.uuid4())
                session_id = str(uuid.uuid4())
                created_at = get_utc_now_iso()
                cursor.execute("""
                    INSERT INTO table_sessions (id, table_number, session_token, is_active, created_at, guest_count, merchant_id)
                    VALUES (?, ?, ?, 1, ?, ?, ?)
                """, (session_id, table_number, session_token, created_at, guest_count, MERCHANT_ID))
                cursor.execute("""
                    UPDATE restaurant_tables SET status = 'occupied' WHERE table_number = ? AND merchant_id = ?
                """, (table_number, MERCHANT_ID))
                conn.commit()

        log_event("info", "session.opened", table_number=table_number, guest_count=guest_count)
        return {"success": True, "session_token": session_token, "table_number": table_number}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sessions/close")
def close_session(data: CloseSessionRequest):
    """Closes a table session."""
    table_number = data.table_number or data.tableNumber or ""
    session_token = data.session_token or ""

    if not table_number and not session_token:
        raise HTTPException(status_code=400, detail="table_number or session_token required")

    try:
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            ended_at = get_utc_now_iso()

            if session_token:
                cursor.execute(
                    "UPDATE table_sessions SET is_active = 0, ended_at = ? WHERE session_token = ?",
                    (ended_at, session_token)
                )
            else:
                cursor.execute(
                    "UPDATE table_sessions SET is_active = 0, ended_at = ? WHERE table_number = ? AND is_active = 1",
                    (ended_at, table_number)
                )

            if table_number:
                cursor.execute(
                    "UPDATE restaurant_tables SET status = 'vacant' WHERE table_number = ? AND merchant_id = ?",
                    (table_number, MERCHANT_ID)
                )
            conn.commit()

        log_event("info", "session.closed", table_number=table_number)
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
