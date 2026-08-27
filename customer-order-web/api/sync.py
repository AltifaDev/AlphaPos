"""
AlphaPos — Sync API routes (status, retry, full sync data)
"""
from fastapi import APIRouter, HTTPException
from contextlib import closing
import json

from .deps import (
    get_db_connection, get_db_row_connection, get_utc_now_iso,
    MERCHANT_ID, SUPABASE_URL, supabase_post, log_event
)

router = APIRouter(prefix="/v1", tags=["sync"])


@router.get("/sync")
def get_sync():
    """Returns all data for full sync (orders, items, sessions, tables)."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()

            # Orders
            cursor.execute("SELECT * FROM orders WHERE merchant_id = ? ORDER BY created_at DESC LIMIT 200", (MERCHANT_ID,))
            orders = [dict(r) for r in cursor.fetchall()]

            # Order Items
            cursor.execute("""
                SELECT oi.* FROM order_items oi
                JOIN orders o ON oi.order_id = o.id
                WHERE o.merchant_id = ?
            """, (MERCHANT_ID,))
            order_items = [dict(r) for r in cursor.fetchall()]

            # Sessions
            cursor.execute("SELECT * FROM table_sessions WHERE merchant_id = ?", (MERCHANT_ID,))
            sessions = [dict(r) for r in cursor.fetchall()]

            # Tables
            cursor.execute("SELECT * FROM restaurant_tables WHERE merchant_id = ?", (MERCHANT_ID,))
            tables = [dict(r) for r in cursor.fetchall()]

            return {
                "orders": orders,
                "order_items": order_items,
                "sessions": sessions,
                "tables": tables,
                "synced_at": get_utc_now_iso()
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sync/status")
def get_sync_status():
    """Returns status of pending Supabase writes queue."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) as cnt FROM pending_supabase_writes")
            row = cursor.fetchone()
            pending_count = row["cnt"] if row else 0

            cursor.execute("SELECT * FROM pending_supabase_writes ORDER BY created_at DESC LIMIT 10")
            items = [dict(r) for r in cursor.fetchall()]

            return {
                "pending_count": pending_count,
                "items": items,
                "supabase_configured": bool(SUPABASE_URL)
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/sync/retry")
def post_sync_retry():
    """Retry all pending Supabase writes."""
    try:
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, endpoint, payload FROM pending_supabase_writes ORDER BY created_at ASC LIMIT 50")
            rows = cursor.fetchall()

            succeeded = 0
            failed = 0
            for row in rows:
                row_id, endpoint, payload_str = row
                try:
                    payload = json.loads(payload_str)
                    success = supabase_post(endpoint, payload, queue_on_fail=False)
                    if success:
                        cursor.execute("DELETE FROM pending_supabase_writes WHERE id = ?", (row_id,))
                        succeeded += 1
                    else:
                        failed += 1
                except Exception:
                    failed += 1
            conn.commit()

        return {"success": True, "retried": succeeded + failed, "succeeded": succeeded, "failed": failed}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sync/supabase-health")
def get_supabase_health():
    """Checks connection health with Supabase VPS."""
    from .deps import SUPABASE_URL, SUPABASE_ANON_KEY
    import urllib.request

    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        return {"online": False, "reason": "Credentials not configured in .env"}

    try:
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/",
            headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"}
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                return {"online": True, "url": SUPABASE_URL}
            else:
                return {"online": False, "reason": f"HTTP status {response.status}"}
    except Exception as e:
        return {"online": False, "reason": str(e)}


@router.post("/sync/supabase-seed")
def post_supabase_seed():
    """Seeds actual inventory items, recipes, and lots to the remote Supabase VPS."""
    from .deps import IS_PRODUCTION
    if IS_PRODUCTION:
        raise HTTPException(status_code=404, detail="Not found")
    from .deps import supabase_request, MERCHANT_ID
    import datetime

    logs = []

    # 1. Define Seed Data
    items_to_seed = [
        {
            "id": "aa555555-5555-5555-5555-555555555555", "merchant_id": MERCHANT_ID,
            "name": "Giant River Prawn", "sku": "ING-PRAWN", "unit": "piece",
            "current_quantity": 200.0, "reorder_level": 30.0, "cost_price": 50.0
        },
        {
            "id": "bb555555-5555-5555-5555-555555555555", "merchant_id": MERCHANT_ID,
            "name": "Chicken Breast", "sku": "ING-CHICKEN", "unit": "g",
            "current_quantity": 8000.0, "reorder_level": 1500.0, "cost_price": 0.12
        },
        {
            "id": "cc555555-5555-5555-5555-555555555555", "merchant_id": MERCHANT_ID,
            "name": "Honey Mango", "sku": "ING-MANGO", "unit": "piece",
            "current_quantity": 150.0, "reorder_level": 25.0, "cost_price": 15.0
        },
        {
            "id": "dd555555-5555-5555-5555-555555555555", "merchant_id": MERCHANT_ID,
            "name": "Rice Noodles", "sku": "ING-NOODLE", "unit": "g",
            "current_quantity": 10000.0, "reorder_level": 2000.0, "cost_price": 0.05
        }
    ]

    recipes_to_seed = [
        # Giant River Prawn for Grilled River Prawn (8b8231c9-5351-5e5b-a966-d5323a205866)
        {
            "id": "aa999999-9999-9999-9999-999999999991", "merchant_id": MERCHANT_ID,
            "menu_item_id": "8b8231c9-5351-5e5b-a966-d5323a205866", "inventory_item_id": "aa555555-5555-5555-5555-555555555555",
            "quantity_required": 1.0, "yield_percentage": 100.0
        },
        # Chicken Breast for Classic Gai Yang (Half) (7271cc13-4ab8-5440-95fd-b1cddeecaf95)
        # Yield is set to 80% (waste 20%)
        {
            "id": "aa999999-9999-9999-9999-999999999992", "merchant_id": MERCHANT_ID,
            "menu_item_id": "7271cc13-4ab8-5440-95fd-b1cddeecaf95", "inventory_item_id": "bb555555-5555-5555-5555-555555555555",
            "quantity_required": 300.0, "yield_percentage": 80.0
        },
        # Honey Mango for Classic Som Tum Thai (eaa14775-851a-5e23-8139-25c92ce38a0b)
        {
            "id": "aa999999-9999-9999-9999-999999999993", "merchant_id": MERCHANT_ID,
            "menu_item_id": "eaa14775-851a-5e23-8139-25c92ce38a0b", "inventory_item_id": "cc555555-5555-5555-5555-555555555555",
            "quantity_required": 1.0, "yield_percentage": 100.0
        }
    ]

    today_str = datetime.date.today().isoformat()
    day_plus_1 = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
    day_plus_2 = (datetime.date.today() + datetime.timedelta(days=2)).isoformat()
    day_plus_3 = (datetime.date.today() + datetime.timedelta(days=3)).isoformat()
    day_plus_5 = (datetime.date.today() + datetime.timedelta(days=5)).isoformat()
    day_plus_10 = (datetime.date.today() + datetime.timedelta(days=10)).isoformat()


    lots_to_seed = [
        # Prawn Lots
        {
            "id": "aa111111-1111-1111-1111-111111111111", "inventory_item_id": "aa555555-5555-5555-5555-555555555555",
            "merchant_id": MERCHANT_ID,
            "lot_number": "LOT-PR-001", "received_date": today_str, "expiry_date": day_plus_2,
            "initial_quantity": 100.0, "remaining_quantity": 100.0, "lot_cost_price": 48.0
        },
        {
            "id": "aa222222-2222-2222-2222-222222222222", "inventory_item_id": "aa555555-5555-5555-5555-555555555555",
            "merchant_id": MERCHANT_ID,
            "lot_number": "LOT-PR-002", "received_date": today_str, "expiry_date": day_plus_10,
            "initial_quantity": 100.0, "remaining_quantity": 100.0, "lot_cost_price": 52.0
        },
        # Chicken Lots
        {
            "id": "bb111111-1111-1111-1111-111111111111", "inventory_item_id": "bb555555-5555-5555-5555-555555555555",
            "merchant_id": MERCHANT_ID,
            "lot_number": "LOT-CK-001", "received_date": today_str, "expiry_date": day_plus_1,
            "initial_quantity": 4000.0, "remaining_quantity": 4000.0, "lot_cost_price": 0.11
        },
        {
            "id": "bb222222-2222-2222-2222-222222222222", "inventory_item_id": "bb555555-5555-5555-5555-555555555555",
            "merchant_id": MERCHANT_ID,
            "lot_number": "LOT-CK-002", "received_date": today_str, "expiry_date": day_plus_5,
            "initial_quantity": 4000.0, "remaining_quantity": 4000.0, "lot_cost_price": 0.13
        },
        # Mango Lots
        {
            "id": "cc111111-1111-1111-1111-111111111111", "inventory_item_id": "cc555555-5555-5555-5555-555555555555",
            "merchant_id": MERCHANT_ID,
            "lot_number": "LOT-MG-001", "received_date": today_str, "expiry_date": day_plus_3,
            "initial_quantity": 75.0, "remaining_quantity": 75.0, "lot_cost_price": 14.0
        },
        {
            "id": "cc222222-2222-2222-2222-222222222222", "inventory_item_id": "cc555555-5555-5555-5555-555555555555",
            "merchant_id": MERCHANT_ID,
            "lot_number": "LOT-MG-002", "received_date": today_str, "expiry_date": None,
            "initial_quantity": 75.0, "remaining_quantity": 75.0, "lot_cost_price": 16.0
        },
        # Noodles Lot
        {
            "id": "dd111111-1111-1111-1111-111111111111", "inventory_item_id": "dd555555-5555-5555-5555-555555555555",
            "merchant_id": MERCHANT_ID,
            "lot_number": "LOT-ND-001", "received_date": today_str, "expiry_date": None,
            "initial_quantity": 10000.0, "remaining_quantity": 10000.0, "lot_cost_price": 0.05
        }
    ]

    try:
        # A. Clear existing seeded data to avoid constraint conflicts (and allow resets)
        logs.append("Cleaning existing test inventory data from Supabase...")

        # We query with filter on our specific seeded IDs
        for lot in lots_to_seed:
            supabase_request("DELETE", "inventory_lots", query_params={"id": f"eq.{lot['id']}"})
        for recipe in recipes_to_seed:
            supabase_request("DELETE", "recipes", query_params={"id": f"eq.{recipe['id']}"})
        for item in items_to_seed:
            supabase_request("DELETE", "inventory_items", query_params={"id": f"eq.{item['id']}"})

        logs.append("Database clean: OK")

        # B. Insert Inventory Items
        logs.append("Inserting Inventory Items...")
        for item in items_to_seed:
            success, res = supabase_request("POST", "inventory_items", payload=item)
            if success:
                logs.append(f"  Item added: {item['name']} (SKU: {item['sku']})")
            else:
                logs.append(f"  Failed item: {item['name']} - Error: {res}")

        # C. Insert Recipes
        logs.append("Inserting Recipes...")
        for recipe in recipes_to_seed:
            success, res = supabase_request("POST", "recipes", payload=recipe)
            if success:
                logs.append(f"  Recipe added: MenuItem ID {recipe['menu_item_id']} -> Item ID {recipe['inventory_item_id']}")
            else:
                logs.append(f"  Failed recipe for item {recipe['inventory_item_id']} - Error: {res}")

        # D. Insert Lots
        logs.append("Inserting Inventory Lots...")
        for lot in lots_to_seed:
            success, res = supabase_request("POST", "inventory_lots", payload=lot)
            if success:
                logs.append(f"  Lot added: {lot['lot_number']} (Exp: {lot['expiry_date'] or 'Never'})")
            else:
                logs.append(f"  Failed lot: {lot['lot_number']} - Error: {res}")

        logs.append("Supabase Seeding completed successfully! 🎉")
        return {"success": True, "logs": logs}

    except Exception as e:
        logs.append(f"Fatal error during seeding: {str(e)}")
        return {"success": False, "logs": logs}
