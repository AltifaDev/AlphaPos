"""
AlphaPos — Customer Feedback API route
"""
from fastapi import APIRouter, HTTPException, Request
from contextlib import closing
import uuid

from .deps import (
    get_db_connection, get_utc_now_iso, clean_string,
    MERCHANT_ID, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["feedback"])


@router.post("/feedback")
async def post_feedback(request: Request):
    """Submit customer feedback/rating."""
    try:
        data = await request.json()
        feedback_id = str(uuid.uuid4())
        order_id = data.get("order_id") or ""
        table_number = data.get("table_number") or ""
        session_token = data.get("session_token") or ""
        overall_rating = int(data.get("overall_rating") or data.get("rating") or 5)
        food_rating = data.get("food_rating")
        service_rating = data.get("service_rating")
        ambience_rating = data.get("ambience_rating")
        comment = clean_string(data.get("comment") or "", "comment", 2000)
        customer_name = clean_string(data.get("customer_name") or "", "customer_name", 100)
        tags = data.get("tags") or []
        created_at = get_utc_now_iso()

        # Validate rating range
        if not (1 <= overall_rating <= 5):
            raise ValueError("Rating must be between 1 and 5")

        # Save to local SQLite
        with closing(get_db_connection()) as conn:
            # Create table if not exists
            conn.execute("""
                CREATE TABLE IF NOT EXISTS customer_feedback (
                    id TEXT PRIMARY KEY,
                    merchant_id TEXT,
                    order_id TEXT,
                    table_number TEXT,
                    session_token TEXT,
                    overall_rating INTEGER,
                    food_rating INTEGER,
                    service_rating INTEGER,
                    ambience_rating INTEGER,
                    comment TEXT,
                    customer_name TEXT,
                    tags TEXT,
                    created_at TEXT
                )
            """)
            conn.execute("""
                INSERT INTO customer_feedback (id, merchant_id, order_id, table_number, session_token,
                    overall_rating, food_rating, service_rating, ambience_rating, comment, customer_name, tags, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                feedback_id, MERCHANT_ID, order_id, table_number, session_token,
                overall_rating, food_rating, service_rating, ambience_rating,
                comment, customer_name, ",".join(tags) if tags else "", created_at
            ))
            conn.commit()

        # Dual-write to Supabase
        supabase_post("customer_feedback", {
            "id": feedback_id, "merchant_id": MERCHANT_ID, "order_id": order_id or None,
            "table_number": table_number, "session_token": session_token,
            "overall_rating": overall_rating, "food_rating": food_rating,
            "service_rating": service_rating, "ambience_rating": ambience_rating,
            "comment": comment, "customer_name": customer_name,
            "tags": tags, "created_at": created_at
        })

        log_event("info", "feedback.submitted", rating=overall_rating, table=table_number)
        return {"success": True, "id": feedback_id}

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        log_event("error", "feedback.failed", str(e))
        raise HTTPException(status_code=500, detail=str(e))
