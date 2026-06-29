"""
AlphaPos — Payments API routes
"""
from fastapi import APIRouter, HTTPException, Request
from contextlib import closing
import uuid
import json

from .deps import (
    get_db_connection, get_utc_now_iso, clean_string, parse_positive_float,
    MERCHANT_ID, PROMPTPAY_ID, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["payments"])


@router.post("/payments")
async def post_payment(request: Request):
    """Record a payment for an order."""
    try:
        pay_data = await request.json()
        pay_id = clean_string(pay_data.get("id") or str(uuid.uuid4()), "id", 50, required=True, pattern=r"[A-Za-z0-9_-]+")
        order_id = clean_string(pay_data.get("order_id"), "order_id", 50, required=True, pattern=r"[A-Za-z0-9_-]+")
        amount = parse_positive_float(pay_data.get("amount", 0), "amount")
        method = clean_string(pay_data.get("payment_method") or pay_data.get("method") or "Cash", "payment_method", 40, required=True)
        created_at = get_utc_now_iso()

        # Normalise method
        method_lower = method.lower()
        if method_lower == "cash":
            method = "Cash"
        elif method_lower in ("qr", "qr promptpay", "promptpay qr", "promptpay"):
            method = "QR PromptPay"
        elif method_lower in ("card", "credit card", "credit_card"):
            method = "Credit Card"

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT total FROM orders WHERE id = ?", (order_id,))
            order_row = cursor.fetchone()
            if not order_row:
                raise ValueError(f"Order '{order_id}' not found.")
            if amount - float(order_row[0]) > 0.05:
                raise ValueError("Payment amount exceeds order total.")

            cursor.execute("""
                INSERT OR REPLACE INTO payments (id, order_id, amount, payment_method, created_at, merchant_id)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (pay_id, order_id, amount, method, created_at, MERCHANT_ID))
            conn.commit()

        supabase_post("payments", {
            "id": pay_id, "order_id": order_id, "amount": amount,
            "payment_method": method.lower().replace(" ", "_"),
            "created_at": created_at, "status": "completed", "merchant_id": MERCHANT_ID
        })

        log_event("info", "payment.saved", order_id=order_id, amount=amount, method=method)
        return {"success": True}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/payments/intent")
async def create_payment_intent(request: Request):
    """Generate a payment intent (PromptPay QR data or card token placeholder)."""
    try:
        data = await request.json()
        amount = parse_positive_float(data.get("amount", 0), "amount")
        method = data.get("method", "promptpay")
        order_id = data.get("order_id", "")

        if method == "promptpay" and PROMPTPAY_ID:
            # Generate PromptPay payload (simplified)
            return {
                "success": True,
                "method": "promptpay",
                "promptpay_id": PROMPTPAY_ID,
                "amount": amount,
                "reference": order_id or str(uuid.uuid4())[:8],
            }
        else:
            return {
                "success": True,
                "method": method,
                "message": "Payment gateway not configured. Use manual payment.",
                "amount": amount
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
