"""
AlphaPos — Orders API routes (GET list, POST create, DELETE items)
"""
from fastapi import APIRouter, HTTPException, Request
from contextlib import closing
from typing import Optional, List
from pydantic import BaseModel
import json
import uuid

from .deps import (
    get_db_connection, get_db_row_connection, get_utc_now_iso,
    clean_string, parse_positive_float, calculate_order_total,
    MERCHANT_ID, web_ordering_enabled_for_payload, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["orders"])


class OrderModifier(BaseModel):
    id: Optional[str] = None
    modifier_id: Optional[str] = None
    name: Optional[str] = None
    price: Optional[float] = 0


class OrderItem(BaseModel):
    id: Optional[str] = None
    item_id: Optional[str] = None
    name: Optional[str] = None
    quantity: Optional[int] = 1
    qty: Optional[int] = None
    price: Optional[float] = 0
    status: Optional[str] = "cooking"
    notes: Optional[str] = ""
    modifiers: Optional[List[OrderModifier]] = []


class CreateOrderRequest(BaseModel):
    id: Optional[str] = None
    tableNumber: Optional[str] = None
    table_number: Optional[str] = None
    total: Optional[float] = 0
    items: List[dict] = []
    status: Optional[str] = "preparing"
    sessionToken: Optional[str] = None
    session_token: Optional[str] = None
    guestCount: Optional[int] = None
    guest_count: Optional[int] = 2
    orderNumber: Optional[str] = None
    order_number: Optional[str] = None
    merchant_id: Optional[str] = None


class DeleteOrderItemRequest(BaseModel):
    item_id: str
    order_id: str


@router.get("/orders")
def get_orders(table_number: Optional[str] = None, status: Optional[str] = None):
    """Returns orders, optionally filtered by table_number or status."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()

            query = "SELECT * FROM orders WHERE merchant_id = ?"
            params = [MERCHANT_ID]

            if table_number:
                query += " AND table_number = ?"
                params.append(table_number)
            if status:
                query += " AND status = ?"
                params.append(status)

            query += " ORDER BY created_at DESC LIMIT 100"
            cursor.execute(query, params)
            orders = cursor.fetchall()

            result = []
            for order in orders:
                order_id = order["id"]
                cursor.execute("SELECT * FROM order_items WHERE order_id = ?", (order_id,))
                items = cursor.fetchall()

                item_list = []
                for item in items:
                    item_keys = item.keys()
                    item_dict = {
                        "id": item["id"],
                        "item_id": item["item_id"] if "item_id" in item_keys else "",
                        "name": item["item_name"],
                        "quantity": item["quantity"],
                        "price": item["price"],
                        "status": item["status"],
                        "notes": item["notes"] if "notes" in item_keys else "",
                    }
                    item_list.append(item_dict)

                order_keys = order.keys()
                result.append({
                    "id": order["id"],
                    "order_number": order["order_number"],
                    "table_number": order["table_number"],
                    "total": order["total"],
                    "status": order["status"],
                    "created_at": order["created_at"],
                    "updated_at": order["updated_at"] if "updated_at" in order_keys else "",
                    "session_token": order["session_token"] if "session_token" in order_keys else "",
                    "guest_count": order["guest_count"] if "guest_count" in order_keys else 2,
                    "items": item_list,
                })
            return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/orders")
async def create_order(request: Request):
    """Submit a new order or update existing. Server-side price validation."""
    try:
        order_data = await request.json()

        if not web_ordering_enabled_for_payload(order_data):
            raise HTTPException(status_code=403, detail="Web ordering is disabled.")

        table_number = clean_string(
            order_data.get("tableNumber") or order_data.get("table_number") or "1",
            "table_number", 10, required=True, pattern=r"[A-Za-z0-9_-]+"
        )
        total_client = parse_positive_float(order_data.get("total", 0.0), "total")
        items = order_data.get("items", [])
        if len(items) > 100:
            raise ValueError("Order item limit exceeded.")
        if not isinstance(items, list) or not items:
            raise ValueError("Order must contain at least one item.")

        order_id = clean_string(
            order_data.get("id") or str(uuid.uuid4()), "id", 50, required=True, pattern=r"[A-Za-z0-9_-]+"
        )
        status = clean_string(order_data.get("status") or "preparing", "status", 20, required=True)
        allowed_statuses = {"preparing", "ready", "served", "completed", "cancelled", "confirmed"}
        if status not in allowed_statuses:
            raise ValueError(f"Invalid order status '{status}'.")

        session_token = order_data.get("sessionToken") or order_data.get("session_token")
        session_token = clean_string(session_token, "session_token", 80, pattern=r"[A-Za-z0-9_-]+") or None
        guest_count = max(1, min(int(order_data.get("guestCount") or order_data.get("guest_count") or 2), 100))
        order_number = clean_string(
            order_data.get("orderNumber") or order_data.get("order_number") or f"ORD-{str(uuid.uuid4().int)[:4]}",
            "order_number", 20, required=True, pattern=r"[A-Za-z0-9_-]+"
        )
        created_at_str = get_utc_now_iso()

        with closing(get_db_connection()) as conn:
            with conn:
                cursor = conn.cursor()

                # Server-side price validation
                computed_subtotal = 0.0
                verified_items = []

                for item in items:
                    if not isinstance(item, dict):
                        raise ValueError("Each item must be an object.")
                    menu_item_id = clean_string(
                        item.get("item_id") or item.get("id"), "item_id", 50, required=True, pattern=r"[A-Za-z0-9_-]+"
                    )
                    qty = max(1, min(int(item.get("quantity") or item.get("qty", 1)), 99))

                    cursor.execute("SELECT name, price FROM menu_items WHERE id = ?", (menu_item_id,))
                    row = cursor.fetchone()
                    if not row:
                        raise ValueError(f"Menu item '{menu_item_id}' not found.")
                    menu_item_name = row[0]
                    base_price = float(row[1])

                    # Modifiers
                    item_modifiers = item.get("modifiers", [])
                    modifier_price_sum = 0.0
                    verified_modifiers = []
                    for mod in (item_modifiers or []):
                        if not isinstance(mod, dict):
                            continue
                        mod_id = clean_string(mod.get("modifier_id") or mod.get("id"), "mod_id", 50, pattern=r"[A-Za-z0-9_-]+")
                        if not mod_id:
                            continue
                        cursor.execute("SELECT extra_price FROM modifiers WHERE id = ? AND is_available = 1", (mod_id,))
                        mod_row = cursor.fetchone()
                        mod_price = float(mod_row[0]) if mod_row else 0
                        modifier_price_sum += mod_price
                        verified_modifiers.append({
                            "id": str(uuid.uuid4()),
                            "modifier_id": mod_id,
                            "price": mod_price
                        })

                    computed_item_price = base_price + modifier_price_sum
                    computed_subtotal += computed_item_price * qty
                    verified_items.append({
                        "id": clean_string(item.get("id") or str(uuid.uuid4()), "item_id", 50, pattern=r"[A-Za-z0-9_-]+"),
                        "item_id": menu_item_id,
                        "name": menu_item_name,
                        "quantity": qty,
                        "price": computed_item_price,
                        "status": clean_string(item.get("status") or "cooking", "item_status", 20),
                        "notes": clean_string(item.get("notes") or "", "notes", 500),
                        "modifiers": verified_modifiers
                    })

                computed_total = calculate_order_total(computed_subtotal)
                if abs(total_client - computed_total) > 0.05:
                    raise ValueError(f"Total mismatch. Client: {total_client:.2f}, Server: {computed_total:.2f}")

                total = computed_total

                # Validate active session exists before allowing order
                if session_token:
                    cursor.execute(
                        "SELECT 1 FROM table_sessions WHERE table_number = ? AND session_token = ? AND is_active = 1",
                        (table_number, session_token)
                    )
                    if not cursor.fetchone():
                        raise ValueError("Session is no longer active. Please scan the QR code again.")
                else:
                    raise ValueError("Session token is required to place an order.")

                # Upsert order
                cursor.execute("SELECT id FROM orders WHERE id = ?", (order_id,))
                exists = cursor.fetchone()

                if exists:
                    cursor.execute("""
                        UPDATE orders SET status=?, total=?, updated_at=?, session_token=COALESCE(?, session_token), guest_count=?, is_synced=0
                        WHERE id=?
                    """, (status, total, get_utc_now_iso(), session_token, guest_count, order_id))
                else:
                    cursor.execute("""
                        INSERT INTO orders (id, order_number, table_number, total, status, created_at, updated_at, session_token, guest_count, merchant_id, is_synced)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """, (order_id, order_number, table_number, total, status, created_at_str, created_at_str, session_token, guest_count, MERCHANT_ID))

                # Upsert order items
                for vi in verified_items:
                    cursor.execute("SELECT id FROM order_items WHERE id = ? AND order_id = ?", (vi["id"], order_id))
                    if cursor.fetchone():
                        cursor.execute("UPDATE order_items SET quantity=?, price=?, status=?, notes=? WHERE id=?",
                                       (vi["quantity"], vi["price"], vi["status"], vi["notes"], vi["id"]))
                    else:
                        cursor.execute("""
                            INSERT INTO order_items (id, order_id, item_name, quantity, price, status, item_id, merchant_id, notes)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, (vi["id"], order_id, vi["name"], vi["quantity"], vi["price"], vi["status"], vi["item_id"], MERCHANT_ID, vi["notes"]))

        # Dual-write to Supabase (best-effort)
        supabase_post("orders", {
            "id": order_id, "order_number": order_number, "table_number": table_number,
            "total": total, "status": status, "created_at": created_at_str, "merchant_id": MERCHANT_ID
        })

        log_event("info", "order.created", order_id=order_id, total=total, items=len(verified_items))
        return {"success": True, "id": order_id, "total": total, "order_number": order_number}

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except HTTPException:
        raise
    except Exception as e:
        log_event("error", "order.failed", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/orders/items/delete")
async def delete_order_item(request: Request):
    """Delete a specific item from an order."""
    try:
        data = await request.json()
        item_id = clean_string(data.get("item_id"), "item_id", 50, required=True, pattern=r"[A-Za-z0-9_-]+")
        order_id = clean_string(data.get("order_id"), "order_id", 50, required=True, pattern=r"[A-Za-z0-9_-]+")

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM order_items WHERE id = ? AND order_id = ?", (item_id, order_id))
            conn.commit()
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Item not found")

        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
